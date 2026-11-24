import SwiftUI
import AppKit

/// Arama çubuğunu ekranın sağ alt köşesine sabitleyen yüzen panel (ContentView'in aynısı; ortak ekleme/arama kodu).
/// Dock'un (çöp kutusunun) içine konamaz; bu panel Dock'un üstündeki boş alanın sağ alt köşesinde durur.
/// Uygulama açılınca varsayılan olarak görünür; menü çubuğu simgesi göster/gizle düğmesidir.
private final class BarPanel: NSPanel {
    override var canBecomeKey: Bool { true }     // arama kutusuna yazılabilsin
    override var canBecomeMain: Bool { false }
}

/// İçerik büyüyünce (sonuçlar, arama motoru ekleme paneli) pencere sağ alt köşe sabit kalacak şekilde yukarı/sola büyür.
private final class FitHostingView<V: View>: NSHostingView<V> {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // macOS 13+: NSHostingView pencereyi içeriğe göre kendisi boyutlandırır ve sol-üst köşeyi sabit tutar
        // (çubuk aşağı kayar). Boyutlandırmayı yalnızca fitWindow yapsın: sağ-alt köşe sabit, yukarı büyür.
        sizingOptions = [.intrinsicContentSize]
        DispatchQueue.main.async { [weak self] in self?.fitWindow() }
    }
    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        DispatchQueue.main.async { [weak self] in self?.fitWindow() }
    }
    override func layout() {
        super.layout()
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
    private var panel: NSPanel?
    private var host: FitHostingView<ContentView>?
    private let margin: CGFloat = 0          // köşeye tam yapışık (boşluk istersen 4-8 yap)
    private let overDock = true             // true: Dock'un üstüne biner, ekranın gerçek sağ-alt köşesine yapışır; false: Dock'un üstünde durur

    var isShown: Bool { panel?.isVisible == true }

    /// Menü çubuğu simgesi: görünürse gizler, gizliyse gösterir.
    func toggle() { if isShown { hide() } else { show() } }

    func show(focus: Bool = true) {
        if panel == nil { build() }
        place()
        panel?.orderFrontRegardless()
        if focus { panel?.makeKey() }
    }

    func hide() { panel?.orderOut(nil) }

    private func build() {
        let h = FitHostingView(rootView: ContentView())
        h.wantsLayer = true
        h.layer?.cornerRadius = 16
        h.layer?.masksToBounds = true
        let p = BarPanel(contentRect: NSRect(x: 0, y: 0, width: 330, height: 62),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.contentView = h
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .statusBar                      // Dock'un (seviye 20) üstünde kalsın; .floating Dock'un arkasında kalırdı
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

    /// Sağ alt köşe. overDock açıksa tam ekran çerçevesi (Dock dahil), kapalıysa visibleFrame (Dock'un dışı) kullanılır.
    private func place() {
        guard let p = panel, let scr = NSScreen.main else { return }
        let area = overDock ? scr.frame : scr.visibleFrame
        p.setFrameOrigin(NSPoint(x: area.maxX - p.frame.width - margin, y: area.minY + margin))
        host?.fitWindow()
    }
}
