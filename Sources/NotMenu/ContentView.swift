import SwiftUI
import AppKit
import ServiceManagement

// Android launcher ile aynı görünüm: [Paylaş] [arama kutusu] [Ayarlar] [Notlarım]
// Koyu zemin, yarı saydam siyah yuvarlak düğmeler, koyu kırmızı "açık" durumu, 0xFF2A2A2A ayar menüsü.
private let panelBG = Color(white: 0.13)
private let idleBG = Color.black.opacity(0.45)
private let activeRed = Color(red: 0.55, green: 0, blue: 0).opacity(0.8)
private let menuBG = Color(red: 0.165, green: 0.165, blue: 0.165)
private let accent = Color(red: 0.31, green: 0.76, blue: 0.97)
private let dim = Color.white.opacity(0.67)

private func circle(_ system: String, active: Bool = false, size: CGFloat = 40) -> some View {
    Image(systemName: system).font(.system(size: 16, weight: .medium)).foregroundStyle(.white)
        .frame(width: size, height: size)
        .background(Circle().fill(active ? activeRed : idleBG))
}

struct ContentView: View {
    @EnvironmentObject var model: NoteModel
    @ObservedObject private var qs = QuickShare.shared
    @State private var text = ""
    @State private var notesMode = false
    @State private var showMenu = false
    @State private var status = ""
    @State private var login = SMAppService.mainApp.status == .enabled
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hits: [Note] { Store.search(model.notes, text) }

    var body: some View {
        VStack(spacing: 6) {
            bar
            if showMenu { settingsMenu }
            if !status.isEmpty { Text(status).font(.caption).foregroundStyle(dim) }
            if notesMode { notesList }
            else if !trimmed.isEmpty { searchResults }
        }
        .padding(12)
        .frame(width: 430)
        .background(panelBG)
        .preferredColorScheme(.dark)
        .onAppear { model.reload(); focused = true }
        .onReceive(qs.$message) { if !$0.isEmpty { flash($0) } }
    }

    // MARK: Üst çubuk
    private var bar: some View {
        HStack(spacing: 8) {
            // Hızlı Paylaş: dokun = ağdan dosya almayı aç/kapat (açıkken koyu kırmızı), basılı tut = alınan dosyaların klasörü
            circle("antenna.radiowaves.left.and.right", active: qs.running)
                .contentShape(Circle())
                .onTapGesture { qs.toggle(); flash(qs.running ? "Paylaşım açıldı" : "Paylaşım kapatıldı") }
                .onLongPressGesture { NSWorkspace.shared.open(QuickShare.receiveDir) }
                .help("Hızlı Paylaş: dokun aç/kapat, basılı tut klasörü aç")

            TextField("", text: $text, prompt: Text("Ara; Enter ile link / metin ekle").foregroundColor(dim))
                .textFieldStyle(.plain).font(.system(size: 16)).foregroundStyle(.white)
                .lineLimit(1).focused($focused).onSubmit(submit)
                .padding(.horizontal, 16).frame(height: 44)
                .background(Capsule().fill(idleBG))

            Button { showMenu.toggle() } label: { circle("gearshape", active: showMenu) }
                .buttonStyle(.plain).help("Ayarlar")
            Button { notesMode.toggle(); showMenu = false } label: { circle("square.and.pencil", active: notesMode) }
                .buttonStyle(.plain).help("Notlarım")
        }
    }

    // MARK: Arama sonuçları: not eşleşmeleri + (sorgu · Yandex · Notlarım) satırı
    private var searchResults: some View {
        VStack(spacing: 0) {
            ForEach(hits.prefix(6)) { n in NoteRow(note: n, onChange: model.reload, onStatus: flash) }
            HStack(spacing: 14) {
                Text(trimmed).font(.system(size: 17)).foregroundStyle(.white).lineLimit(1)
                Spacer()
                Button { yandex() } label: {
                    Text("Y").font(.system(size: 17, weight: .heavy)).foregroundStyle(Color.red)
                        .frame(width: 36, height: 36).background(Circle().fill(Color.white.opacity(0.2)))
                }.buttonStyle(.plain).help("Yandex'te ara")
                Button { notesMode = true } label: { circle("note.text", size: 36).opacity(0.9) }
                    .buttonStyle(.plain).help("Notlarımda ara")
            }.padding(.horizontal, 8).padding(.top, 6)
        }
    }

    // MARK: Notlarım
    private var notesList: some View {
        Group {
            if hits.isEmpty {
                Text(trimmed.isEmpty ? "Henüz not yok" : "Sonuç yok — Enter ile kaydet")
                    .foregroundStyle(dim).frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ScrollView { LazyVStack(spacing: 0) {
                    ForEach(hits.prefix(200)) { n in NoteRow(note: n, onChange: model.reload, onStatus: flash) }
                } }.frame(height: 340)
            }
        }
    }

    // MARK: Ayarlar menüsü
    private var settingsMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            menuRow("Notlar klasörünü seç…", "folder") { chooseDir() }
            menuRow("Notlar klasörünü aç", "arrow.up.forward.app") { NSWorkspace.shared.open(Store.dir) }
            menuRow("Alınan dosyalar klasörünü seç…", "tray.and.arrow.down") { chooseRecvDir() }
            menuRow("Alınan dosyalar klasörünü aç", "arrow.up.forward.app") { NSWorkspace.shared.open(QuickShare.receiveDir) }
            menuRow("Girişte başlat", login ? "checkmark.circle.fill" : "circle", tint: login ? accent : nil) { toggleLogin() }
            menuRow("Çık", "power") { NSApp.terminate(nil) }
        }
        .padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(menuBG))
    }

    private func menuRow(_ t: String, _ icon: String, tint: Color? = nil, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 22).foregroundStyle(tint ?? .white)
                Text(t).foregroundStyle(.white); Spacer()
            }.padding(.horizontal, 14).padding(.vertical, 9).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    // MARK: Eylemler
    private func submit() {
        guard !trimmed.isEmpty else { return }
        if Store.submit(trimmed) { text = ""; flash("Eklendi"); model.reload() } else { flash("Eklenemedi") }
    }
    private func yandex() {
        guard let q = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let u = URL(string: "https://yandex.com/search/?text=\(q)") else { return }
        NSWorkspace.shared.open(u); text = ""
    }
    private func flash(_ s: String) {
        status = s
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if status == s { status = "" } }
    }
    private func chooseDir() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
        if p.runModal() == .OK, let u = p.url { UserDefaults.standard.set(u.path, forKey: "notesDir"); model.reload(); flash("Klasör değişti") }
    }
    private func chooseRecvDir() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
        if p.runModal() == .OK, let u = p.url { UserDefaults.standard.set(u.path, forKey: "recvDir"); flash("Klasör değişti") }
    }
    private func toggleLogin() {
        do { if login { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() } } catch { flash("Ayarlanamadı") }
        login = SMAppService.mainApp.status == .enabled
    }
}

struct NoteRow: View {
    let note: Note
    let onChange: () -> Void
    let onStatus: (String) -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: note.isLink ? "link" : (note.isTxt ? "doc.text" : "note.text"))
                .font(.system(size: 15)).foregroundStyle(.white)
                .frame(width: 34, height: 34).background(Circle().fill(Color.white.opacity(0.12)))
            VStack(alignment: .leading, spacing: 1) {
                Text(note.title).font(.system(size: 17)).foregroundStyle(.white).lineLimit(1)
                Text(note.body.replacingOccurrences(of: "\n", with: " ")).font(.system(size: 12)).foregroundStyle(dim).lineLimit(1)
            }
            Spacer(minLength: 4)
            if hover {
                ShareLink(item: note.body) { Image(systemName: "square.and.arrow.up") }
                Button { copy() } label: { Image(systemName: "doc.on.doc") }
                Button { Store.delete(note); onChange() } label: { Image(systemName: "trash") }
            }
        }
        .buttonStyle(.plain).foregroundStyle(.white)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 10).fill(hover ? Color.white.opacity(0.08) : .clear))
        .contentShape(Rectangle()).onHover { hover = $0 }
        .onTapGesture { if note.isLink, let u = URL(string: note.body) { NSWorkspace.shared.open(u) } else { copy() } }
    }
    private func copy() {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(note.body, forType: .string); onStatus("Kopyalandı")
    }
}
