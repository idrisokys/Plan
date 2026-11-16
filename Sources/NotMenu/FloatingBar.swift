import SwiftUI
import AppKit

/// Arama çubuğunu ekranın sağ alt köşesine sabitleyen yüzen panel (ContentView'in aynısı; ortak ekleme/arama kodu).
/// Dock'un (çöp kutusunun) içine konamaz; bu panel Dock'un üstündeki boş alanın sağ alt köşesinde durur.
/// Sabitleme tercihi kalıcıdır: uygulama açılınca çubuk yeniden belirir.
private final class BarPanel: NSPanel {
    override var canBecomeKey: Bool { true }     // arama kutusuna yazılabilsin
    override var canBecomeMain: Bool { false }
}

/// İçerik büyüyünce (sonuçlar, arama motoru ekleme paneli) pencere sağ alt köşe sabit kalacak şekilde yukarı/sola büyür.
private final class FitHostingView<V: View>: NSHostingView<V> {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in self?.fitWindow() }
    }
    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        DispatchQueue.main.async { [weak self] in self?.fitWindow() }
    }
    func fitWindow() {
        guard let w = window else { return }
        let s = fittingSize
        guard s.width > 0, s.height > 0,
              abs(w.frame.width - s.width) > 0.5 || abs(w.frame.height - s.height) > 0.5 else { return }
        let f = w.frame
        w.setFrame(NSRect(x: f.maxX - s.width, y: f.minY, width: s.width, height: s.height), display: true)
    }
}

@MainActor
final class FloatingBar {
    static let shared = FloatingBar()
    private static let key = "pinBar"
    private var panel: NSPanel?
    private var host: FitHostingView<ContentView>?
    private let margin: CGFloat = 12

    /// Sabitleme açıkken uygulama açılışında çubuğu gösterir (odağı almadan).
    func restoreIfWanted() {
        if UserDefaults.standard.bool(forKey: Self.key) { show(focus: false) }
    }

    func show(focus: Bool = true) {
        UserDefaults.standard.set(true, forKey: Self.key)
        if panel == nil { build() }
        place()
        panel?.orderFrontRegardless()
        if focus { panel?.makeKey() }
    }

    func hide() {
        UserDefaults.standard.set(false, forKey: Self.key)
        panel?.orderOut(nil)
    }

    private func build() {
        let h = FitHostingView(rootView: ContentView(floating: true))
        h.wantsLayer = true
        h.layer?.cornerRadius = 16
        h.layer?.masksToBounds = true
        let p = BarPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 62),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.contentView = h
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        panel = p
        host = h
        // Ekran / Dock düzeni değişince köşeye geri yerleştir
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.place() }
        }
    }

    /// Sağ alt köşe: visibleFrame Dock ve menü çubuğunu zaten dışarıda bırakır (Dock altta ya da sağdaysa çubuk onun üstünde/solunda durur).
    private func place() {
        guard let p = panel, let scr = NSScreen.main else { return }
        let vf = scr.visibleFrame
        p.setFrameOrigin(NSPoint(x: vf.maxX - p.frame.width - margin, y: vf.minY + margin))
        host?.fitWindow()
    }
}
