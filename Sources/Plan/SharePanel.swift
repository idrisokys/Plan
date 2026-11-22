import SwiftUI
import AppKit

/// Finder'ın Paylaş menüsünden gelen dosyalar için "açık cihaz seç" paneli.
/// Hızlı Paylaş kapalıysa açılır; listeden cihaza dokununca dosyalar gönderilir, bitince panel kapanır.
@MainActor
final class SharePanel {
    static let shared = SharePanel()
    private var panel: NSPanel?

    func show(files: [URL]) {
        let files = files.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !files.isEmpty else { return }
        if !QuickShare.shared.running { QuickShare.shared.start() }
        close()

        let view = QuickShareSheet(files: files) { [weak self] in self?.close() }
        let host = NSHostingController(rootView: view)
        let p = NSPanel(contentViewController: host)
        p.styleMask = [.titled, .closable, .fullSizeContentView, .nonactivatingPanel]
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isMovableByWindowBackground = true
        p.level = .floating
        p.isReleasedWhenClosed = false
        p.becomesKeyOnlyIfNeeded = false
        p.center()
        panel = p
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}
