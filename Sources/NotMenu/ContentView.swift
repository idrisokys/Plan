import SwiftUI
import AppKit

// Koyu zemin, yarı saydam siyah yuvarlak düğmeler.
// Üst çubuk: [Paylaş] [arama kutusu] [Kalem → Notlarım] [Kapat]
private let panelBG = Color(white: 0.13)
private let idleBG = Color.black.opacity(0.45)
private let onRed = Color(red: 1.0, green: 0.45, blue: 0.45)          // açık kırmızı "ON"
private let menuBG = Color(red: 0.165, green: 0.165, blue: 0.165)
private let dim = Color.white.opacity(0.67)

private let linkCepteID = "io.github.idrisokys.linkcepte.mac"

private func circle(_ system: String, size: CGFloat = 40) -> some View {
    Image(systemName: system).font(.system(size: 16, weight: .medium)).foregroundStyle(.white)
        .frame(width: size, height: size)
        .background(Circle().fill(idleBG))
}

// MARK: Arama motorları (eklenenler UserDefaults'ta tutulur)
struct SearchEngine: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var url: String          // %s veya {q} sorgunun yerine geçer; yoksa sorgu sona eklenir

    var letter: String {
        let f = String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
        return f.isEmpty ? "?" : f
    }

    func searchURL(_ query: String) -> URL? {
        guard let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        var u = url
        if u.contains("%s") { u = u.replacingOccurrences(of: "%s", with: q) }
        else if u.contains("{q}") { u = u.replacingOccurrences(of: "{q}", with: q) }
        else { u += q }
        return URL(string: u)
    }

    static func load() -> [SearchEngine] {
        guard let d = UserDefaults.standard.data(forKey: "engines"),
              let e = try? JSONDecoder().decode([SearchEngine].self, from: d) else { return [] }
        return e
    }
    static func save(_ e: [SearchEngine]) {
        if let d = try? JSONEncoder().encode(e) { UserDefaults.standard.set(d, forKey: "engines") }
    }
}

struct ContentView: View {
    @EnvironmentObject var model: NoteModel
    @ObservedObject private var qs = QuickShare.shared
    @State private var text = ""
    @State private var status = ""
    @State private var engines = SearchEngine.load()
    @State private var addOpen = false
    @State private var newName = ""
    @State private var newURL = ""
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hits: [Note] { Store.search(model.notes, text) }

    var body: some View {
        VStack(spacing: 6) {
            bar
            if qs.running { devicesList }
            if !status.isEmpty { Text(status).font(.caption).foregroundStyle(dim) }
            if !trimmed.isEmpty { searchResults }
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
            // Hızlı Paylaş: dokun = aç/kapat. Açıkken ikon açık kırmızı "ON" olur. Basılı tut = alınan dosyalar klasörü.
            shareButton
                .contentShape(Circle())
                .onTapGesture { qs.toggle() }
                .onLongPressGesture { NSWorkspace.shared.open(QuickShare.receiveDir) }
                .help("Hızlı Paylaş: dokun aç/kapat, basılı tut klasörü aç")

            TextField("", text: $text, prompt: Text("Ara; Enter ile link / metin ekle").foregroundColor(dim))
                .textFieldStyle(.plain).font(.system(size: 16)).foregroundStyle(.white)
                .lineLimit(1).focused($focused).onSubmit(submit)
                .padding(.horizontal, 16).frame(height: 44)
                .background(Capsule().fill(idleBG))

            // Kalem: Notlarım uygulamasını (notlar ve linkler) pencere olarak açar
            Button { openLinkCepte() } label: { circle("square.and.pencil") }
                .buttonStyle(.plain).help("Notlarım")
            // Kapat: uygulamadan çıkar
            Button { NSApp.terminate(nil) } label: { circle("xmark") }
                .buttonStyle(.plain).help("Kapat")
        }
    }

    @ViewBuilder private var shareButton: some View {
        if qs.running {
            Text("ON").font(.system(size: 13, weight: .heavy)).foregroundStyle(onRed)
                .frame(width: 40, height: 40)
                .background(Circle().fill(onRed.opacity(0.18)))
                .overlay(Circle().stroke(onRed.opacity(0.8), lineWidth: 1.5))
        } else {
            circle("antenna.radiowaves.left.and.right")
        }
    }

    // MARK: Paylaşım açıkken: o an açık cihazlar, sağında klasör ikonu
    private var devicesList: some View {
        VStack(spacing: 0) {
            if qs.devices.isEmpty {
                Text("Açık cihaz aranıyor…").font(.system(size: 13)).foregroundStyle(dim)
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else {
                ForEach(qs.devices) { d in
                    HStack(spacing: 12) {
                        Image(systemName: "wifi").font(.system(size: 15)).foregroundStyle(.white)
                            .frame(width: 34, height: 34).background(Circle().fill(Color.white.opacity(0.12)))
                        Text(d.name).font(.system(size: 17)).foregroundStyle(.white).lineLimit(1)
                        Spacer(minLength: 4)
                        if qs.sendingTo.contains(d.id) {
                            ProgressView().controlSize(.small).frame(width: 34, height: 34)
                        } else {
                            Button { pickAndSend(to: d) } label: { circle("folder", size: 34) }
                                .buttonStyle(.plain).help("Dosya seç ve gönder")
                        }
                    }.padding(.horizontal, 8).padding(.vertical, 5)
                }
            }
        }
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 14).fill(menuBG))
    }

    // MARK: Arama sonuçları: en çok 3 not + (sorgu · + · eklenen motorlar) satırı
    private var searchResults: some View {
        VStack(spacing: 0) {
            ForEach(hits.prefix(3)) { n in NoteRow(note: n, onChange: model.reload, onStatus: flash) }
            HStack(spacing: 14) {
                Text(trimmed).font(.system(size: 17)).foregroundStyle(.white).lineLimit(1)
                Spacer()
                Button { addOpen.toggle() } label: {
                    Image(systemName: "plus").font(.system(size: 17, weight: .heavy)).foregroundStyle(.white)
                        .frame(width: 36, height: 36).background(Circle().fill(Color.white.opacity(0.2)))
                }
                .buttonStyle(.plain).help("Arama motoru ekle")
                ForEach(engines) { e in
                    Button { run(e) } label: { letterIcon(e.letter, color: .white, heavy: false) }
                        .buttonStyle(.plain).help(e.name)
                        .contextMenu { Button("Sil") { removeEngine(e) } }
                }
            }.padding(.horizontal, 8).padding(.top, 6)
            if addOpen { addEnginePanel }
        }
    }

    private func letterIcon(_ l: String, color: Color, heavy: Bool) -> some View {
        Text(l).font(.system(size: 17, weight: heavy ? .heavy : .semibold)).foregroundStyle(color)
            .frame(width: 36, height: 36).background(Circle().fill(Color.white.opacity(0.2)))
    }

    // MARK: Arama motoru ekleme bölümü (+ ile açılır/kapanır)
    private var addEnginePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            field("Ad (örn. Google)", $newName)
            field("Adres (örn. https://www.google.com/search?q=%s)", $newURL)
            HStack {
                Text("%s = aranan kelime").font(.caption).foregroundStyle(dim)
                Spacer()
                Button("Ekle") { addEngine() }
                    .buttonStyle(.plain).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.2)))
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(menuBG))
        .padding(.top, 8)
    }

    private func field(_ prompt: String, _ b: Binding<String>) -> some View {
        TextField("", text: b, prompt: Text(prompt).foregroundColor(dim))
            .textFieldStyle(.plain).font(.system(size: 14)).foregroundStyle(.white)
            .padding(.horizontal, 12).frame(height: 32)
            .background(Capsule().fill(idleBG))
    }

    // MARK: Eylemler
    private func submit() {
        guard !trimmed.isEmpty else { return }
        if Store.submit(trimmed) { text = ""; flash("Eklendi"); model.reload() } else { flash("Eklenemedi") }
    }
    private func run(_ e: SearchEngine) {
        guard let u = e.searchURL(trimmed) else { flash("Adres geçersiz"); return }
        NSWorkspace.shared.open(u); text = ""
    }
    private func addEngine() {
        let n = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        var u = newURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !u.isEmpty else { flash("Adres gerekli"); return }
        if !u.lowercased().hasPrefix("http") { u = "https://" + u }
        guard let host = URL(string: u.replacingOccurrences(of: "%s", with: "x").replacingOccurrences(of: "{q}", with: "x"))?.host
        else { flash("Adres geçersiz"); return }
        let e = SearchEngine(name: n.isEmpty ? host.replacingOccurrences(of: "www.", with: "") : n, url: u)
        engines.append(e); SearchEngine.save(engines)
        newName = ""; newURL = ""; addOpen = false
        flash("\(e.name) eklendi")
    }
    private func removeEngine(_ e: SearchEngine) {
        engines.removeAll { $0.id == e.id }; SearchEngine.save(engines)
    }
    private func openLinkCepte() {
        let ws = NSWorkspace.shared
        guard let u = ws.urlForApplication(withBundleIdentifier: linkCepteID) else { flash("Notlarım uygulaması kurulu değil"); return }
        let cfg = NSWorkspace.OpenConfiguration(); cfg.activates = true
        ws.openApplication(at: u, configuration: cfg) { _, err in
            if err != nil { DispatchQueue.main.async { flash("Notlarım açılamadı") } }
        }
    }
    private func pickAndSend(to d: QSDevice) {
        NSApp.activate(ignoringOtherApps: true)
        let p = NSOpenPanel(); p.canChooseFiles = true; p.canChooseDirectories = false; p.allowsMultipleSelection = true
        p.prompt = "Gönder"; p.message = "\(d.name) cihazına gönderilecek dosyaları seç"
        if p.runModal() == .OK, !p.urls.isEmpty { QuickShare.shared.send(p.urls, to: d) }
    }
    private func flash(_ s: String) {
        status = s
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if status == s { status = "" } }
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
