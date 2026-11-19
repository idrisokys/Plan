import SwiftUI
import AppKit

/// Plan'ın dosya yöneticisi (Filetor) penceresi.
/// Menü satırındaki dosya yöneticisi simgesi `show()` çağırır; pencere ilk açılışta oluşturulur,
/// kapatılınca gizlenir (sekmeler ve ayarlar korunur).
@MainActor
public enum FiletorWindow {
    static var window: NSWindow?
    private static var model: AppModel?
    private static var closeObserver: NSObjectProtocol?

    /// Pencereyi açar ya da öne getirir.
    public static func show() {
        if window == nil { build() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Açıksa kapatır, kapalıysa açar.
    public static func toggle() {
        if let w = window, w.isVisible { w.performClose(nil) } else { show() }
    }

    private static func build() {
        // Filetor'un kendi sekmeleri var; sistem sekme çubuğu araç çubuğunun üstüne çizilmesin.
        NSWindow.allowsAutomaticWindowTabbing = false

        let app = AppModel()
        model = app

        let host = NSHostingController(rootView: ContentView(app: app))
        host.sizingOptions = []          // pencere boyutunu içerik değil biz belirleriz

        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.contentViewController = host
        w.setContentSize(NSSize(width: 1100, height: 700))
        w.titlebarAppearsTransparent = true       // SwiftUI'daki .windowStyle(.hiddenTitleBar) karşılığı
        w.titleVisibility = .hidden
        w.title = "Filetor"
        w.minSize = NSSize(width: 700, height: 450)
        w.isReleasedWhenClosed = false
        w.center()
        w.setFrameAutosaveName("PlanFiletorWindow")
        window = w
    }
}
