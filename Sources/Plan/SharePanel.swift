import SwiftUI
import AppKit

/// Finder'ın Paylaş menüsünden ve Hızlı Kaydet kısayolundan gelen dosyalar için "açık cihaz seç" paneli.
/// İçerik Notlarım'daki Paylaş penceresiyle ORTAK: `QuickShareSheet` (Hızlı Paylaş'ı açma, cihaz arama, gönderme orada).
/// Bu sınıf yalnızca onu serbest bir panele koyar.
@MainActor
final class SharePanel {
    static let shared = SharePanel()
    private var panel: NSPanel?

    func show(files: [URL]) {
        let files = files.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !files.isEmpty else { return }
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
