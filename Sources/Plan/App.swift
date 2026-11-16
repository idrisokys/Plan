import SwiftUI
import AppKit

@main
struct PlanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var notes = NotesModel.shared

    var body: some Scene {
        // Notlarım: menü çubuğundaki kalem düğmesiyle açılan tek pencere.
        // Tek pencere olduğu için plan:// adresi geldiğinde yeni pencere açılmaz.
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

/// Notlarım penceresinin kökü: pencere açma eylemini saklar (AppDelegate'in plan://search adresi için).
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

/// Menü çubuğu simgesi: tıklayınca alttaki arama çubuğu görünür, tekrar tıklayınca gizlenir.
/// Sağ tık (veya ⌃-tık): Notlarım / Çık menüsü.
@MainActor
final class StatusItemController: NSObject {
    static let shared = StatusItemController()
    private var item: NSStatusItem?

    func install() {
        guard item == nil else { return }
        let it = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        it.button?.image = MenuIcon.image
        it.button?.target = self
        it.button?.action = #selector(clicked)
        it.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item = it
    }

    @objc private func clicked() {
        let e = NSApp.currentEvent
        if e?.type == .rightMouseUp || e?.modifierFlags.contains(.control) == true {
            let m = NSMenu()
            let notes = NSMenuItem(title: L("Notlarım", "My Notes"), action: #selector(openNotes), keyEquivalent: "")
            notes.target = self
            let rec = NSMenuItem(title: L("Kayıt yeri", "Save Location"), action: #selector(chooseSaveLocation), keyEquivalent: "")
            rec.target = self
            rec.toolTip = QuickShare.receiveDir.path
            let folder = NSMenuItem(title: L("Notlarım klasörü", "My Notes Folder"), action: #selector(openNotesFolder), keyEquivalent: "")
            folder.target = self
            let quit = NSMenuItem(title: L("Çık", "Quit"), action: #selector(quit), keyEquivalent: "")
            quit.target = self
            m.addItem(notes); m.addItem(rec); m.addItem(folder); m.addItem(.separator()); m.addItem(quit)
            item?.menu = m
            item?.button?.performClick(nil)
            item?.menu = nil
        } else {
            FloatingBar.shared.toggle()
        }
    }
    @objc private func openNotes() { NotesWindow.show() }

    /// Paylaşımla gelen dosyaların kaydedileceği klasörü seçtirir (UserDefaults "recvDir").
    @objc private func chooseSaveLocation() {
        NSApp.activate(ignoringOtherApps: true)
        let p = NSOpenPanel()
        p.canChooseFiles = false; p.canChooseDirectories = true; p.canCreateDirectories = true
        p.allowsMultipleSelection = false
        p.directoryURL = QuickShare.receiveDir
        p.prompt = L("Seç", "Choose")
        p.message = L("Paylaşımla gelen dosyaların kaydedileceği klasörü seç", "Choose where received files are saved")
        if p.runModal() == .OK, let u = p.url { UserDefaults.standard.set(u.path, forKey: "recvDir") }
    }

    /// Notlarımın kayıtlı olduğu klasörü Finder'da açar.
    @objc private func openNotesFolder() {
        if let r = NotesStore.root { NSWorkspace.shared.open(r) }
    }
    @objc private func quit() { NSApp.terminate(nil) }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.servicesProvider = ServiceProvider()
        NSUpdateDynamicServices()
        registerShareExtension()
        Task { @MainActor in
            StatusItemController.shared.install()
            FloatingBar.shared.show(focus: false)      // arama çubuğu varsayılan olarak sağ altta sabit açılır
        }
        if UserDefaults.standard.bool(forKey: "qsOn") { QuickShare.shared.start() }
    }

    /// Pencere kapanınca uygulama çıkmaz; menü çubuğunda çalışmaya devam eder.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Paylaş eklentisini sisteme tanıtır ve etkinleştirmeyi dener (hata olursa sessizce geçer).
    private func registerShareExtension() {
        let appex = Bundle.main.bundleURL.appendingPathComponent("Contents/PlugIns/PlanShare.appex")
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

    /// Paylaş eklentisi / Chrome eklentisinden gelen plan://add?t=... ve plan://search?q=... adresleri.
    func application(_ application: NSApplication, open urls: [URL]) {
        for u in urls where u.scheme == AppInfo.urlScheme {
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
            let s = c.queryItems?.first(where: { $0.name == "s" })?.value      // tarayıcının verdiği sayfa başlığı
            Task { @MainActor in
                NotesModel.shared.shareAdd(t, subject: s)
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
