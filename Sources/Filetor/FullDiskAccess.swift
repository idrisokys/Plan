import AppKit

/// Full Disk Access: once it is granted, macOS stops asking for Desktop, Documents,
/// Downloads, removable volumes etc. one folder at a time.
enum FullDiskAccess {
    /// Opens System Settings > Privacy & Security > Full Disk Access.
    static func openSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
        ]
        for s in urls {
            if let url = URL(string: s), NSWorkspace.shared.open(url) { return }
        }
    }

    /// True when the app can read a file that only Full Disk Access holders may read.
    static var isGranted: Bool {
        let probes = [
            "/Library/Application Support/com.apple.TCC/TCC.db",
            NSHomeDirectory() + "/Library/Safari/CloudTabs.db",
            NSHomeDirectory() + "/Library/Safari/Bookmarks.plist",
        ]
        for path in probes where FileManager.default.fileExists(atPath: path) {
            if let h = FileHandle(forReadingAtPath: path) {
                try? h.close()
                return true
            }
            return false
        }
        return true // nothing to test with: do not nag
    }
}
