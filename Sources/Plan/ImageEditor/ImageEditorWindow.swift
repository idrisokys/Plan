import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Combine

/// Resim düzenleyici pencereleri: menüdeki Düzenle düğmesi İndirilenler'deki en yeni resmi doğrudan açar (←/→ ile diğerleri gezilir).
/// Her resim kendi penceresinde açılır; kaydedilmemiş değişiklik varsa kapatırken sorulur.
@MainActor
enum ImageEditorWindow {
    private static var controllers: [Controller] = []

    static var hasWindows: Bool { !controllers.isEmpty }

    /// Seçim penceresi yok: İndirilenler'deki en yeni resim açılır, diğer resimler ←/→ ile gezilir.
    static func openDownloads() {
        let imgs = ImageEditorModel.images(in: MediaDir.downloads)
        guard !imgs.isEmpty else {
            HUD.show(L("İndirilenler'de resim yok", "No images in Downloads"))
            return
        }
        // Açılamayan (bozuk) dosyalar atlanır; ilk açılan resimle düzenleyici başlar
        for u in imgs { if open(u, quiet: true) { return } }
        HUD.show(L("Resim açılamadı", "Could not open image"))
    }

    /// Resim seç → düzenleyiciyi aç (düzenleyicideki "Başka resim aç" düğmesi kullanır).
    /// `startingAt` verilirse seçici o klasörde açılır (ör. İndirilenler).
    static func openPicker(startingAt dir: URL? = nil) {
        NSApp.activate(ignoringOtherApps: true)
        let p = NSOpenPanel()
        p.canChooseFiles = true
        p.canChooseDirectories = false
        p.allowsMultipleSelection = true
        p.allowedContentTypes = [.image]
        if let dir { p.directoryURL = dir }
        p.prompt = L("Aç", "Open")
        p.message = L("Düzenlenecek resmi seç", "Choose an image to edit")
        guard p.runModal() == .OK else { return }
        for u in p.urls {
            let isImage = UTType(filenameExtension: u.pathExtension)?.conforms(to: .image) ?? true
            if isImage { open(u) } else { NSWorkspace.shared.open(u) }
        }
    }

    @discardableResult
    static func open(_ url: URL, quiet: Bool = false) -> Bool {
        guard let model = ImageEditorModel(url: url) else {
            if !quiet { HUD.show(L("Resim açılamadı", "Could not open image")) }
            return false
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
        return true
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
