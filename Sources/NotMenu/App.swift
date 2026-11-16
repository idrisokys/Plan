import SwiftUI
import AppKit

@main
struct NotMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var notes = NotesModel.shared

    var body: some Scene {
        MenuBarExtra {
            ContentView()
        } label: {
            Image(nsImage: MenuIcon.image)
        }
        .menuBarExtraStyle(.window)

        // Notlarım (eski adıyla Link Cepte): menü çubuğundaki kalem düğmesiyle açılan tek pencere.
        // Tek pencere olduğu için notlarim:// adresi geldiğinde yeni pencere açılmaz.
        Window(L("Notlarım", "My Notes"), id: NotesWindow.id) {
            NotesRoot().environmentObject(notes)
        }
        .defaultSize(width: 400, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu(L("Notlarım", "My Notes")) {
                Button(L("Ekle", "Add")) { notes.addFromText() }
                    .keyboardShortcut(.return, modifiers: .command)
                Button(L("Metin Dosyası Olarak Ekle (.txt)", "Add as Text File (.txt)")) { notes.addTxt() }
                    .keyboardShortcut(.return, modifiers: [.command, .shift])
                Button(L("Ara", "Search")) { notes.startSearch() }
                    .keyboardShortcut("f", modifiers: .command)
                Divider()
                Button(L("Yeni Klasör", "New Folder")) { notes.sheet = .folder }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button(L("Düzenle", "Edit")) { notes.toggleEdit() }
                    .keyboardShortcut("e", modifiers: .command)
                Button(L("Yenile", "Refresh")) { notes.refresh() }
                    .keyboardShortcut("r", modifiers: .command)
                Button(L("Cihazlarla Eşitle", "Sync with Devices")) { notes.syncNow() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Button(L("Geri", "Back")) { notes.goBack() }
                    .keyboardShortcut("[", modifiers: .command)
                Divider()
                Button(L("Yazıyı Büyüt", "Larger Text")) { notes.bumpFont(1) }
                    .keyboardShortcut("+", modifiers: .command)
                Button(L("Yazıyı Küçült", "Smaller Text")) { notes.bumpFont(-1) }
                    .keyboardShortcut("-", modifiers: .command)
                Divider()
                Button(L("Chrome Eklentisi Klasörünü Aç", "Open Chrome Extension Folder")) { notes.openChromeExtension() }
            }
        }
    }
}

/// Notlarım penceresinin kökü: pencere açma eylemini saklar (AppDelegate'in notlarim://search adresi için).
private struct NotesRoot: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        NotesContentView().onAppear { NotesWindow.opener = openWindow }
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
        registerShareExtension()
        if UserDefaults.standard.bool(forKey: "qsOn") { QuickShare.shared.start() }
    }

    /// Pencere kapanınca uygulama çıkmaz; menü çubuğunda çalışmaya devam eder.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Paylaş eklentisini sisteme tanıtır ve etkinleştirmeyi dener (hata olursa sessizce geçer).
    private func registerShareExtension() {
        let appex = Bundle.main.bundleURL.appendingPathComponent("Contents/PlugIns/NotlarimShare.appex")
        guard FileManager.default.fileExists(atPath: appex.path) else { return }
        DispatchQueue.global(qos: .utility).async {
            for args in [["-a", appex.path], ["-e", "use", "-i", AppInfo.shareExtensionID]] {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
                p.arguments = args
                try? p.run()
                p.waitUntilExit()
            }
        }
    }

    /// Paylaş eklentisi / Chrome eklentisinden gelen notlarim://add?t=... ve notlarim://search?q=... adresleri.
    /// Eski linkcepte:// adresleri de kabul edilir.
    func application(_ application: NSApplication, open urls: [URL]) {
        for u in urls where u.scheme == AppInfo.urlScheme || u.scheme == AppInfo.legacyURLScheme {
            guard let c = URLComponents(url: u, resolvingAgainstBaseURL: false) else { continue }
            if u.host == "search" {
                if let q = c.queryItems?.first(where: { $0.name == "q" })?.value {
                    Task { @MainActor in
                        NotesWindow.show()
                        NotesModel.shared.externalSearch(q)
                    }
                }
                continue
            }
            guard let t = c.queryItems?.first(where: { $0.name == "t" })?.value else { continue }
            Task { @MainActor in
                NotesModel.shared.shareAdd(t)
                    }
        }
    }
}

/// Herhangi bir uygulamada metin seç → sağ tık → Hizmetler → "Notlarıma Kaydet" (Paylaş menüsünün macOS karşılığı).
/// Pencere açmaz; başlık alma ve kısa bildirim Notlarım tarafında yapılır.
final class ServiceProvider: NSObject {
    @objc func saveSelection(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let text = pboard.string(forType: .string) ?? ""
        Task { @MainActor in
            NotesModel.shared.shareAdd(text)
            }
    }
}
