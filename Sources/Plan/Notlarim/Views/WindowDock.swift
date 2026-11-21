import SwiftUI
import AppKit

/// Pencere ilk açıldığında içerik alanını 350 × 650 yapar ve ekranın sağ kenarına (üste) tutturur.
/// Pencere kullanıcı istemeden (uygulama açılışında) belirmişse kapatır; kapanınca Dock simgesini kaldırır.
struct WindowDock: NSViewRepresentable {
    static let size = NSSize(width: 350, height: 650)

    final class DockView: NSView {
        private var done = false
        private var closeObserver: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard !done, let w = window else { return }
            done = true
            NotesWindow.window = w
            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
                    Task { @MainActor in NotesWindow.didClose() }
                }
            DispatchQueue.main.async {
                if !NotesWindow.requested { w.close(); return }
                w.isRestorable = false
                w.level = NotesModel.shared.alwaysOnTop ? .floating : .normal   // varsayılan: normal; sağ üstteki raptiyeyle değişir
                w.appearance = NSAppearance(named: .darkAqua)   // Android Notlarım ekranı gibi koyu
                w.backgroundColor = NT.bgNS
                w.titleVisibility = .hidden
                w.title = ""                  // "Notlarım" başlığı gösterilmez
                // Üst satır içeriğin parçası (TitleBarRow): başlık çubuğu saydam, içerik onun altına uzanır
                w.titlebarAppearsTransparent = true
                w.styleMask.insert(.fullSizeContentView)
                w.styleMask.remove(.resizable)      // boyut sabit: 350 × 650
                w.setContentSize(WindowDock.size)
                w.contentMinSize = WindowDock.size
                w.contentMaxSize = WindowDock.size
                guard let scr = w.screen ?? NSScreen.main else { return }
                let vf = scr.visibleFrame
                w.setFrameTopLeftPoint(NSPoint(x: vf.maxX - w.frame.width, y: vf.maxY))
            }
        }

        deinit { if let o = closeObserver { NotificationCenter.default.removeObserver(o) } }
    }

    func makeNSView(context: Context) -> NSView { DockView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
