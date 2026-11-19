import AppKit

/// Folder-by-folder access (Desktop, Documents, Downloads) without Full Disk Access.
///
/// macOS remembers a "Files & Folders" grant per app *code identity*. Two things make it ask again and again:
///  1. the prompts come one at a time, whenever a folder happens to be touched first, and
///  2. an unsigned / ad-hoc signed build gets a new identity (its cdhash) on every build or update,
///     so macOS forgets earlier answers. `scripts/sign.sh` and the CI workflow fix that by signing with a
///     fixed designated requirement (the bundle identifier).
///
/// This helper asks for the three folders together, once, right at the first launch.
enum FolderAccess {
    private static let doneKey = "folderAccessRequested.v1"

    nonisolated static var protectedFolders: [URL] {
        let fm = FileManager.default
        return [FileManager.SearchPathDirectory.desktopDirectory, .documentDirectory, .downloadsDirectory]
            .compactMap { fm.urls(for: $0, in: .userDomainMask).first }
    }

    /// Listing a folder is what makes macOS show its permission prompt (and returns false when access is denied).
    nonisolated static func probe(_ url: URL) -> Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil
    }

    /// Triggers the three prompts back to back, off the main thread so the window stays responsive.
    static func requestAll(completion: (@MainActor (Bool) -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async {
            let allGranted = protectedFolders.map(probe).allSatisfy { $0 }
            DispatchQueue.main.async { completion?(allGranted) }
        }
    }

    /// First launch only. After that macOS keeps the answers (as long as the app's signature stays the same).
    static func requestOnFirstLaunch() {
        guard !UserDefaults.standard.bool(forKey: doneKey) else { return }
        UserDefaults.standard.set(true, forKey: doneKey)
        requestAll()
    }

    /// System Settings > Privacy & Security > Files & Folders, for folders that were answered with "Don't Allow".
    static func openSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_FilesAndFolders",
        ]
        for s in urls {
            if let url = URL(string: s), NSWorkspace.shared.open(url) { return }
        }
    }
}
