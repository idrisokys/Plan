import SwiftUI
import AppKit

final class NoteModel: ObservableObject {
    static let shared = NoteModel()
    @Published var notes: [Note] = []
    func reload() {
        DispatchQueue.global(qos: .userInitiated).async {
            let n = Store.loadAll()
            DispatchQueue.main.async { self.notes = n }
        }
    }
}

@main
struct NotMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = NoteModel.shared
    var body: some Scene {
        MenuBarExtra {
            ContentView().environmentObject(model)
        } label: {
            Image(nsImage: MenuIcon.image)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Menü çubuğu simgesi: uygulama ana simgesinin küçüğü (Resources/MenuIcon.png, 44px = 22pt @2x).
enum MenuIcon {
    static let image: NSImage = {
        let img = Bundle.main.url(forResource: "MenuIcon", withExtension: "png").flatMap { NSImage(contentsOf: $0) }
            ?? NSImage(systemSymbolName: "magnifyingglass.circle", accessibilityDescription: "Notlarım")
            ?? NSImage()
        img.size = NSSize(width: 20, height: 20)
        img.isTemplate = false      // renkli kalsın (ana simgenin küçüğü)
        return img
    }()
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.servicesProvider = ServiceProvider()
        NSUpdateDynamicServices()
        NoteModel.shared.reload()
        if UserDefaults.standard.bool(forKey: "qsOn") { QuickShare.shared.start() }
    }
}

/// Herhangi bir uygulamada metin seç → sağ tık → Hizmetler → "Notlarıma Kaydet" (Paylaş menüsünün macOS karşılığı).
final class ServiceProvider: NSObject {
    @objc func saveSelection(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let t = pboard.string(forType: .string), Store.submit(t) else { return }
        NoteModel.shared.reload()
    }
}
