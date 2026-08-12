import Foundation
import FruitDockCore

/// Finds the applications installed on this Mac.
///
/// Scans the standard directories rather than asking Launch Services, whose
/// only public query for "every application" is
/// `LSCopyApplicationURLsForBundleIdentifier`, which needs the identifier we
/// are trying to discover. A directory listing is also the set the user
/// recognises: what they see in Finder's Applications window.
@MainActor
final class InstalledApplicationScanner: InstalledApplicationProviding {

    /// Searched in this order; the first copy of a given bundle identifier
    /// wins, so a user's own install shadows nothing it should not.
    ///
    /// Utilities is listed separately because the scan is shallow — recursing
    /// would drag in the helper apps nested inside other bundles, which are
    /// not applications a user launches.
    private static var searchPaths: [String] {
        var paths = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
        ]
        // Present only on some Macs, and skipped silently when absent.
        paths.append((NSHomeDirectory() as NSString).appendingPathComponent("Applications"))
        return paths
    }

    var installedApplications: [ApplicationInfo] {
        Self.searchPaths.flatMap(applications(in:))
    }

    func applicationExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    private func applications(in directory: String) -> [ApplicationInfo] {
        let url = URL(fileURLWithPath: directory)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        return contents.compactMap(application(at:))
    }

    private func application(at url: URL) -> ApplicationInfo? {
        guard url.pathExtension == "app" else { return nil }

        // An identifier is required rather than synthesised: it is what
        // pinning and deduplication key on, and a bundle without one is not
        // something `activateOrLaunch` could bring forward either.
        guard let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier else {
            return nil
        }

        return ApplicationInfo(
            bundleIdentifier: identifier,
            name: FileManager.default.displayName(atPath: url.path),
            path: url.path
        )
    }
}
