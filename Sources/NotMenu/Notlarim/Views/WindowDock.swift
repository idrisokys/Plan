import SwiftUI
import AppKit

/// Pencere ilk açıldığında içerik alanını 300 × 450 yapar ve ekranın sağ kenarına (üste) tutturur.
/// Pencere kullanıcı istemeden (uygulama açılışında) belirmişse kapatır; kapanınca Dock simgesini kaldırır.
struct WindowDock: NSViewRepresentable {
    static let size = NSSize(width: 300, height: 450)

    final class DockView: NSView {
        private var done = false
        private var closeObserver: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard !done, let w = window else { return }
            done = true
            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
                    Task { @MainActor in NotesWindow.didClose() }
                }
            DispatchQueue.main.async {
                if !NotesWindow.requested { w.close(); return }
                w.isRestorable = false
                w.setContentSize(WindowDock.size)
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
