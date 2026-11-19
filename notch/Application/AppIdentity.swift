internal import AppKit

enum AppIdentity {
    static let bundleID = "in.infynite.notch"
    // Detection only. No legacy preferences, credentials, or hooks are imported.
    static let legacyBundleID = "com.Jackson.DynamicNotch"

    @MainActor
    static func prepareLaunch() -> Bool {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        if let other = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first(where: { $0.processIdentifier != currentPID }) {
            other.activate(options: [])
            NSApp.terminate(nil)
            return false
        }
        let older = NSRunningApplication.runningApplications(withBundleIdentifier: legacyBundleID)
        guard !older.isEmpty else { return true }
        let alert = NSAlert()
        alert.messageText = "An older copy of Notch is running"
        alert.informativeText = "Running both copies can create overlapping overlays. Quit the older copies and start fresh? Their preferences and data will not be deleted."
        alert.addButton(withTitle: "Quit older copies")
        alert.addButton(withTitle: "Cancel launch")
        guard alert.runModal() == .alertFirstButtonReturn else {
            NSApp.terminate(nil)
            return false
        }
        for app in older { app.terminate() }
        return true
    }
}
