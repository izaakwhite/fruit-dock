import AppKit
import FruitDockCore

/// Real `NSWorkspace`-backed implementation of `ApplicationProviding`.
///
/// The only file in the app that touches `NSWorkspace`.
@MainActor
final class SystemApplicationProvider: ApplicationProviding {
    private var changeHandler: (() -> Void)?
    private var observers: [NSObjectProtocol] = []

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
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.changeHandler?()
                }
            }
        }
    }

    func activateOrLaunch(_ application: ApplicationInfo, on displayID: DisplayID?) {
        if let running = runningApplication(for: application.bundleIdentifier) {
            running.activate()
            // Placement is best-effort; the app is already frontmost either way.
            if let displayID {
                WindowPlacer.place(pid: running.processIdentifier, onto: displayID)
            }
            return
        }

        let url = URL(fileURLWithPath: application.path)
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { app, error in
            if let error {
                NSLog("fruit-dock: could not launch \(application.name) — \(error)")
                return
            }
            guard let displayID, let pid = app?.processIdentifier else { return }

            // A just-launched app has no windows yet, so `place` retries until
            // one appears or it gives up.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    WindowPlacer.place(pid: pid, onto: displayID)
                }
            }
        }
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
