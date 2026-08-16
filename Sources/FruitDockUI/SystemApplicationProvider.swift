import AppKit
import FruitDockCore

/// Real `NSWorkspace`-backed implementation of `ApplicationProviding`.
///
/// The only file in the app that touches `NSWorkspace`.
@MainActor
final class SystemApplicationProvider: ApplicationProviding {
    private var changeHandler: (() -> Void)?
    private var observers: [NSObjectProtocol] = []
    private let placer: WindowPlacer

    init(accessibility: AccessibilityPermission) {
        self.placer = WindowPlacer(permission: accessibility)
    }

    var runningApplications: [ApplicationInfo] {
        let ownPID = ProcessInfo.processInfo.processIdentifier

        return NSWorkspace.shared.runningApplications.compactMap { app in
            // `.regular` excludes background daemons and other menu-bar
            // agents, which have no business in a dock.
            guard app.activationPolicy == .regular,
                  app.processIdentifier != ownPID,
                  let bundleID = app.bundleIdentifier,
                  let url = app.bundleURL
            else { return nil }

            return ApplicationInfo(
                bundleIdentifier: bundleID,
                name: app.localizedName ?? url.deletingPathExtension().lastPathComponent,
                path: url.path
            )
        }
    }

    /// Observes launch and terminate notifications rather than polling.
    ///
    /// Polling `runningApplications` on a timer is the standard way an idle
    /// menu-bar agent misses its CPU budget (NFR-1); these notifications cost
    /// nothing while nothing happens.
    func onRunningApplicationsChange(_ handler: @escaping () -> Void) {
        changeHandler = handler

        let center = NSWorkspace.shared.notificationCenter
        for observer in observers {
            center.removeObserver(observer)
        }
        observers = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
        ].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                // Read out here, and only the pid crosses: `Notification` is
                // not `Sendable`, so it cannot be touched inside the isolated
                // block.
                let terminated =
                    name == NSWorkspace.didTerminateApplicationNotification
                    ? (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                        .processIdentifier
                    : nil

                MainActor.assumeIsolated {
                    if let terminated {
                        // A retry chain outliving its process would go on
                        // interrogating the Accessibility API about a pid that
                        // no longer exists, and pids get reused.
                        self?.placer.cancelRetries(for: terminated)
                    }
                    self?.changeHandler?()
                }
            }
        }
    }

    /// Activation comes first and unconditionally; placement is appended to it
    /// and can fail freely. Without Accessibility permission this method still
    /// does everything it did before the feature existed.
    func activateOrLaunch(_ application: ApplicationInfo, on displayID: DisplayID?) {
        if let running = runningApplication(for: application.bundleIdentifier) {
            // Hidden (⌘H) and minimised are different states with different
            // remedies, and an app can be in both. Neither is undone by
            // `activate()`, so a click on either used to bring the app forward
            // with nothing on screen and look like it had done nothing.
            if running.isHidden {
                running.unhide()
            }
            running.activate()
            placer.restoreMinimisedWindow(pid: running.processIdentifier)

            if let displayID {
                placer.place(pid: running.processIdentifier, onto: displayID)
            }
            return
        }

        let url = URL(fileURLWithPath: application.path)
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { [weak self] app, error in
            if let error {
                NSLog("fruit-dock: could not launch \(application.name) — \(error)")
                return
            }
            // Only the pid crosses the queue hop: `NSRunningApplication` is not
            // `Sendable`, and this completion arrives on an arbitrary queue.
            guard let displayID, let pid = app?.processIdentifier else { return }

            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.placer.place(pid: pid, onto: displayID)
                }
            }
        }
    }

    func open(folderAtPath path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    /// Every minimised window across the running applications.
    ///
    /// Read through the Accessibility API on demand rather than tracked, because
    /// macOS posts no notification when a window is minimised — the same absence
    /// that forces the Dock-location poll (T10). Reading on refresh is the
    /// cheaper of the two wrongs: a stale tile until the next refresh, rather
    /// than a timer interrogating every process on the machine.
    ///
    /// Without Accessibility permission this is empty, which the dock treats as
    /// "none" — the section simply does not appear, rather than appearing empty.
    var minimizedWindows: [WindowTile] {
        guard placer.hasPermission else { return [] }

        return runningApplications.flatMap { application -> [WindowTile] in
            guard let running = runningApplication(for: application.bundleIdentifier)
            else { return [] }

            return placer.minimizedWindows(pid: running.processIdentifier)
                .map { found in
                    WindowTile(
                        title: found.title,
                        application: application,
                        processIdentifier: running.processIdentifier,
                        windowIndex: found.index
                    )
                }
        }
    }

    func restore(_ window: WindowTile) {
        // Activated as well as restored: a window that returns behind whatever
        // the user was looking at reads as the click having failed.
        runningApplication(for: window.application.bundleIdentifier)?.activate()
        placer.restore(windowAt: window.windowIndex, pid: window.processIdentifier)
    }

    func openTrash() {
        NSWorkspace.shared.open(
            URL(fileURLWithPath: (NSHomeDirectory() as NSString).appendingPathComponent(".Trash"))
        )
    }

    func quit(_ application: ApplicationInfo) {
        runningApplication(for: application.bundleIdentifier)?.terminate()
    }

    private func runningApplication(for bundleID: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleID }
    }
}
