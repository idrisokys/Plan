import SwiftUI
import AppKit
import Filetor

/// Finder'ın Paylaş menüsünden ve dosya yöneticisinden gelen dosyalar için "açık cihaz seç" paneli.
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

    /// Filetor'un Paylaş menüsü bu alanlar üzerinden açık cihazları listeler ve gönderir.
    static func installFiletorHooks() {
        NearbyShare.devices = {
            QuickShare.shared.devices.map { NearbyShare.Device(id: $0.id, name: $0.name) }
        }
        NearbyShare.send = { files, id in
            guard let d = QuickShare.shared.devices.first(where: { $0.id == id }) else { return }
            QuickShare.shared.send(files, to: d)
        }
        NearbyShare.openPanel = { files in SharePanel.shared.show(files: files) }
    }
}
