import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Combine

/// Resim düzenleyici pencereleri: alt çubuktaki resim düğmesi bir resim seçtirir ve düzenleyiciyi açar.
/// Her resim kendi penceresinde açılır; kaydedilmemiş değişiklik varsa kapatırken sorulur.
@MainActor
enum ImageEditorWindow {
    private static var controllers: [Controller] = []

    static var hasWindows: Bool { !controllers.isEmpty }

    /// Resim seç → düzenleyiciyi aç.
    static func openPicker() {
        NSApp.activate(ignoringOtherApps: true)
        let p = NSOpenPanel()
        p.canChooseFiles = true
        p.canChooseDirectories = false
        p.allowsMultipleSelection = true
        p.allowedContentTypes = [.image]
        p.prompt = L("Aç", "Open")
        p.message = L("Düzenlenecek resmi seç", "Choose an image to edit")
        if p.runModal() == .OK { for u in p.urls { open(u) } }
    }

    static func open(_ url: URL) {
        guard let model = ImageEditorModel(url: url) else {
            HUD.show(L("Resim açılamadı", "Could not open image"))
            return
        }

        let host = NSHostingView(rootView: ImageEditorView(model: model))
        var size = NSSize(width: 860, height: 700)
        if let vf = NSScreen.main?.visibleFrame {
            size.width = min(size.width, vf.width * 0.9)
            size.height = min(size.height, vf.height * 0.9)
        }
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable],
                         backing: .buffered, defer: false)
        w.title = url.lastPathComponent
        w.contentView = host
        w.minSize = NSSize(width: 560, height: 520)
        w.isReleasedWhenClosed = false
        w.appearance = NSAppearance(named: .darkAqua)
        w.backgroundColor = NSColor(white: 0.13, alpha: 1)
        w.center()

        let c = Controller(window: w, model: model)
        w.delegate = c
        controllers.append(c)
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    fileprivate static func closed(_ c: Controller) {
        controllers.removeAll { $0 === c }
        // Pencere kalmadıysa ve Notlarım de açık değilse yeniden yalnızca menü çubuğunda kal
    }

    @MainActor
    fileprivate final class Controller: NSObject, NSWindowDelegate {
        let window: NSWindow
        let model: ImageEditorModel
        private var titleSub: AnyCancellable?

        init(window: NSWindow, model: ImageEditorModel) {
            self.window = window
            self.model = model
            super.init()
            model.onEmpty = { [weak window] in window?.close() }
            titleSub = model.$sourceURL.sink { [weak window] u in window?.title = u.lastPathComponent }
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard model.dirty else { return true }
            let a = NSAlert()
            a.messageText = L("Kaydedilmemiş değişiklikler var", "You have unsaved changes")
            a.informativeText = L("Kapatırsan yapılan düzenlemeler kaybolur.", "Closing will discard your edits.")
            a.addButton(withTitle: L("Kapat", "Close"))
            a.addButton(withTitle: L("Vazgeç", "Cancel"))
            return a.runModal() == .alertFirstButtonReturn
        }

        func windowWillClose(_ notification: Notification) {
            ImageEditorWindow.closed(self)
        }
    }
}
