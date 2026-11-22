import SwiftUI
import AppKit

// Koyu zemin, yarı saydam siyah yuvarlak düğmeler.
// Üst çubuk: [Paylaş] [arama kutusu] [Kalem → Notlarım] [Gizle]
private let panelBG = Color(white: 0.13)
private let idleBG = Color.black.opacity(0.45)
private let onBlue = Color(red: 0.55, green: 0.80, blue: 1.0)          // açık mavi "ON"
private let menuBG = Color(red: 0.165, green: 0.165, blue: 0.165)
private let dim = Color.white.opacity(0.67)

/// Paylaş / ON simgesinin ve altındaki ⇄ simgesinin çapı (aynı hizada dururlar).
private let onSize: CGFloat = 30

private func circle(_ system: String, size: CGFloat = 36) -> some View {
    Image(systemName: system).font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
        .frame(width: size, height: size)
        .background(Circle().fill(idleBG))
}

private func circleView<C: View>(size: CGFloat = 36, @ViewBuilder _ content: () -> C) -> some View {
    content()
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
    // Sonuç yazıları Notlarım'ın yazı boyutunu izler (⌘+ / ⌘−)
    @ObservedObject private var notes = NotesModel.shared
    @ObservedObject private var qs = QuickShare.shared
    @State private var text = ""
    @State private var status = ""
    // Arama sonuçları Notlarım penceresiyle aynı koddan gelir (NotesStore.searchAsync)
    @State private var hits: [Hit] = []
    @State private var searchFlag: CancelFlag?
    @State private var contacts: [ContactHit] = []      // Rehber'den eşleşen kişiler
    @State private var engines = SearchEngine.load()
    @State private var addOpen = false
    @State private var newName = ""
    @State private var newURL = ""
    @State private var syncOpen = false          // ⇄ simgesinin penceresi (açık cihaz satırında)
    @State private var syncPicked = Set<String>()
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 6) {
            // Çubuk ekranın altında sabit: arama kutusu en altta, sonuçlar ondan yukarı doğru dizilir
            // (panel sağ alt köşe sabit kalıp yukarı büyür).
            if !qs.running && !trimmed.isEmpty { searchResults }
            if !status.isEmpty { Text(status).font(.footnote).foregroundStyle(dim) }
            bar
        }
        .padding(12)
        .frame(width: 330)
        .background(panelBG)
        .preferredColorScheme(.dark)
        .onAppear { focused = true; search() }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            let e = SearchEngine.load()
            if e != engines { engines = e }          // panel ve sabit çubuk aynı arama motorlarını gösterir
        }
        .onChange(of: text) { _ in search() }
        .onChange(of: qs.running) { on in if !on { focused = true } }     // paylaşım kapanınca arama kutusu geri gelir
        .onReceive(qs.$message) { if !$0.isEmpty { flash($0) } }
    }

    // MARK: Üst çubuk
    private var bar: some View {
        // Paylaşım açıkken arama kutusu kaybolur; yerine cihaza gönderme seçenekleri gelir (düğmeler en alt satırda hizalı; liste yukarı doğru uzar).
        let rowH: CGFloat? = qs.running ? 38 : nil
        return HStack(alignment: qs.running ? .bottom : .center, spacing: 8) {
            // Hızlı Paylaş: dokun = aç/kapat. Açıkken ikon açık mavi "ON" olur. (Basılı tutarak klasör açma kaldırıldı.)
            shareButton
                .contentShape(Circle())
                .onTapGesture { qs.toggle() }
                .help("Hızlı Paylaş: dokun aç/kapat")
                .frame(height: rowH)

            if qs.running {
                devicesList
            } else {
                TextField("", text: $text, prompt: Text("Ara; Enter ile ekle").foregroundColor(dim))
                    .textFieldStyle(.plain).font(.system(size: 16)).foregroundStyle(.white)
                    .lineLimit(1).focused($focused).onSubmit(submit)
                    .padding(.horizontal, 14).frame(height: 38)
                    .background(Capsule().fill(idleBG))
            }

            // Kalem: Notlarım (notlar ve linkler) penceresini açar; ayrı uygulama değil, bu uygulamanın parçası
            Button { NotesWindow.toggle() } label: { circle("square.and.pencil") }
                .buttonStyle(.plain).help("Notlarım (aç/kapat)")
                .frame(height: rowH)
            // Eşitle ⇄: eski çıkış (çarpı) düğmesinin yerinde; yalnızca paylaşım açıkken görünür
            if qs.running {
                syncButton.frame(height: rowH)
            }
        }
    }

    // MARK: Eşitle ⇄ — Link klasörünü açık cihazlarla eşitler. Pencerede cihazlar işaretlenir, eşitleme yöntemi seçilir.
    private var syncButton: some View {
        Button { syncOpen.toggle() } label: {
            if qs.syncing { circleView { ProgressView().controlSize(.small) } }
            else { circle("arrow.triangle.2.circlepath") }
        }
        .buttonStyle(.plain).disabled(qs.syncing)
        .help(L("Cihazlarla eşitle (Link klasörü)", "Sync with devices (Link folder)"))
        .popover(isPresented: $syncOpen, arrowEdge: .top) { syncPopover }
    }

    @ViewBuilder private var shareButton: some View {
        if qs.running {
            Text("ON").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                .frame(width: onSize, height: onSize)
                .background(Circle().fill(idleBG))
        } else {
            circle("antenna.radiowaves.left.and.right", size: onSize)
        }
    }

    // MARK: Paylaşım açıkken arama kutusunun yerinde: o an açık cihazlar, sağında klasör ikonu
    // Üstteki ve alttaki yazı aynı görünümde (aynı boy, renk) ve sola hizalı.
    private var devicesList: some View {
        VStack(alignment: .leading, spacing: 0) {
            infoLine
            if qs.devices.isEmpty {
                Text("Açık cihaz aranıyor…").font(.system(size: 15)).foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
            } else {
                // Cihaz sayısı arttıkça liste yukarı uzar: ilk cihaz en altta (düğmelerle aynı satırda)
                ForEach(Array(qs.devices.reversed())) { d in
                    HStack(spacing: 8) {
                        Text(d.name).font(.system(size: 15)).foregroundStyle(.white).lineLimit(1)
                        Spacer(minLength: 4)
                        if qs.sendingTo.contains(d.id) {
                            ProgressView().controlSize(.small).frame(width: 30, height: 30)
                        } else {
                            Button { pickAndSend(to: d) } label: { circle("folder", size: 30) }
                                .buttonStyle(.plain).help("Dosya seç ve gönder")
                        }
                    }
                    .padding(.leading, 14).padding(.trailing, 4)
                    .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 19).fill(idleBG))
    }

    private var syncPopover: some View {
        let chosen = qs.devices.filter { syncPicked.contains($0.id) }
        return VStack(alignment: .leading, spacing: 6) {
            Text(L("Nasıl eşitlensin?", "How to sync?")).font(.headline)
            if qs.devices.isEmpty {
                Text(L("Açık cihaz bulunamadı", "No open device found")).foregroundStyle(.secondary)
            } else {
                ForEach(qs.devices) { d in
                    Toggle(d.name, isOn: Binding(
                        get: { syncPicked.contains(d.id) },
                        set: { if $0 { syncPicked.insert(d.id) } else { syncPicked.remove(d.id) } }))
                }
            }
            Divider()
            ForEach([(1, L("Bu cihaza göre", "Based on this device")),
                     (2, L("Karşıdaki cihaza göre", "Based on the other device")),
                     (0, L("İki cihazda aynı olsun", "Make both the same"))], id: \.0) { m in
                Button(m.1) { syncOpen = false; qs.sync(mode: m.0, with: chosen) }
                    .disabled(chosen.isEmpty)
            }
        }
        .padding(14).frame(minWidth: 230)
    }

    /// Gönderme / alma bilgisi: bildirim yok, yalnızca bilgi varken tek satır (açıklama ve simge yok).
    @ViewBuilder private var infoLine: some View {
        if let i = qs.info {
            VStack(spacing: 0) {
                Text(i.text)
                    .font(.system(size: 15)).foregroundStyle(.white).lineLimit(1).truncationMode(.middle)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { if let f = i.folder { NSWorkspace.shared.open(f) } }     // "Alındı" satırı: kayıt klasörünü aç
                    .help(i.folder != nil ? "Kayıt klasörünü aç" : "")
                Divider().overlay(Color.white.opacity(0.1)).padding(.horizontal, 8)
            }
        }
    }

    // MARK: Arama sonuçları — alttan üste: [arama kutusu] ← en iyi sonuç ← … ← (sorgu · eklenen motorlar · +) ← motor ekleme paneli
    // Motorlar + düğmesinin SOLUNDA durur: + en sağda, yeni eklenen motor en solda (sola doğru büyür).
    private var searchResults: some View {
        VStack(spacing: 0) {
            if addOpen { addEnginePanel }
            HStack(spacing: 10) {
                Text(trimmed).font(.system(size: notes.fontSize)).foregroundStyle(.white).lineLimit(1)
                Spacer(minLength: 4)
                ForEach(Array(engines.reversed())) { e in
                    Button { run(e) } label: { letterIcon(e.letter, color: .white, heavy: false) }
                        .buttonStyle(.plain).help(e.name)
                        .contextMenu { Button("Sil") { removeEngine(e) } }
                }
                // Yazılanı temizle: + düğmesinin solunda
                Button { text = ""; focused = true } label: {
                    Image(systemName: "delete.left").font(.system(size: 16, weight: .medium)).foregroundStyle(.white)
                        .frame(width: 36, height: 36).background(Circle().fill(Color.white.opacity(0.2)))
                }
                .buttonStyle(.plain).help(L("Yazılanı temizle", "Clear text"))
                Button { addOpen.toggle() } label: {
                    Image(systemName: "plus").font(.system(size: 17, weight: .heavy)).foregroundStyle(.white)
                        .frame(width: 36, height: 36).background(Circle().fill(Color.white.opacity(0.2)))
                }
                .buttonStyle(.plain).help("Arama motoru ekle")
            }.padding(.horizontal, 8).padding(.vertical, 6)
            // En iyi sonuç arama kutusuna en yakın (altta); diğerleri yukarı doğru sıralanır
            ForEach(Array(hits.prefix(3).reversed())) { h in
                HitRow(hit: h, onOpen: { open(h) }, onDelete: { delete(h) })
            }
            // Kişiler notların üstünde: en iyi eşleşme notlara yakın kalır
            ForEach(Array(contacts.reversed())) { c in
                ContactRow(contact: c) { NSWorkspace.shared.open(URL(string: "addressbook://\(c.id)")!) }
            }
        }
    }

    private func letterIcon(_ l: String, color: Color, heavy: Bool) -> some View {
        Text(l).font(.system(size: 19, weight: heavy ? .heavy : .semibold)).foregroundStyle(color)
            .frame(width: 36, height: 36).background(Circle().fill(Color.white.opacity(0.2)))
    }

    // MARK: Arama motoru ekleme bölümü (+ ile açılır/kapanır)
    private var addEnginePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            field("Ad (örn. Google)", $newName)
            field("Adres (örn. https://www.google.com/search?q=%s)", $newURL)
            HStack {
                Text("%s = aranan kelime").font(.footnote).foregroundStyle(dim)
                Spacer()
                Button("Ekle") { addEngine() }
                    .buttonStyle(.plain).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.2)))
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(menuBG))
        .padding(.bottom, 8)
    }

    private func field(_ prompt: String, _ b: Binding<String>) -> some View {
        TextField("", text: b, prompt: Text(prompt).foregroundColor(dim))
            .textFieldStyle(.plain).font(.system(size: 15)).foregroundStyle(.white)
            .padding(.horizontal, 12).frame(height: 32)
            .background(Capsule().fill(idleBG))
    }

    // MARK: Eylemler
    /// Enter: ekleme kuralı Notlarım penceresindekiyle aynıdır (NotesStore.submit).
    private func submit() {
        let t = trimmed
        guard !t.isEmpty else { return }
        guard let root = NotesStore.root else { flash("Link klasörü bulunamadı"); return }
        text = ""
        Task { @MainActor in
            let r = await NotesStore.submit(root, t)
            if r == .failed { text = t; flash("Eklenemedi"); return }
            flash(r == .textFile ? "Metin dosyası eklendi" : "Eklendi")
            NotesModel.shared.reload()
        }
    }

    /// Yazdıkça arar: tarama Notlarım'daki aramayla aynı koddur (NotesStore.searchAsync).
    private func search() {
        searchFlag?.cancel()
        let q = trimmed
        guard !q.isEmpty else { hits = []; contacts = []; return }
        let flag = CancelFlag()
        searchFlag = flag
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)      // yazarken her tuşta taramayı başlatma
            if flag.isCancelled { return }
            // Kişiler (Rehber) notlardan bağımsız aranır; Link klasörü olmasa da çalışır
            async let people = ContactSearch.search(q)
            if let root = NotesStore.root {
                let r = await NotesStore.searchAsync(root: root, query: q, alive: { !flag.isCancelled })
                if !flag.isCancelled { hits = r }
            } else if !flag.isCancelled { hits = [] }
            let c = await people
            if !flag.isCancelled { contacts = c }
        }
    }

    /// Sonuca dokunma: Notlarım'daki "aç" koduyla aynı (link açılır, not kopyalanır); klasör ve .txt Notlarım'da açılır.
    private func open(_ h: Hit) {
        let m = NotesModel.shared
        if h.entry.isDir {
            NotesWindow.show(); m.exitSearch(false); m.setStack(h.path + [h.entry])
        } else if h.entry.isTxt {
            NotesWindow.show(); m.open(h.entry)
        } else {
            m.open(h.entry)
        }
    }
    private func delete(_ h: Hit) {
        NotesModel.shared.deleteNow([h.entry]) { search() }
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

/// Panelde arama sonucu satırı; veri Notlarım aramasının `Hit` modelidir, paylaş/kopyala/sil de Notlarım'ın kodunu çağırır.
struct HitRow: View {
    @ObservedObject private var notes = NotesModel.shared
    let hit: Hit
    let onOpen: () -> Void
    let onDelete: () -> Void
    @State private var hover = false
    private var e: Entry { hit.entry }

    private var icon: String { e.isDir ? "folder" : (e.isTxt ? "doc.text" : (hit.isNote ? "note.text" : "link")) }
    private var sub: String {
        if !hit.detail.isEmpty { return hit.detail.replacingOccurrences(of: "\n", with: " ") }
        return hit.path.map { $0.name }.joined(separator: " › ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15)).foregroundStyle(.white)
                .frame(width: 34, height: 34).background(Circle().fill(Color.white.opacity(0.12)))
            VStack(alignment: .leading, spacing: 1) {
                Text(e.title).font(.system(size: notes.fontSize)).foregroundStyle(.white).lineLimit(1)
                if !sub.isEmpty { Text(sub).font(.system(size: max(notes.fontSize - 1, 9))).foregroundStyle(dim).lineLimit(1) }
            }
            Spacer(minLength: 4)
            if hover {
                if !e.isDir {
                    Button { NotesModel.shared.shareEntries([e]) } label: { Image(systemName: "square.and.arrow.up") }
                    Button { NotesModel.shared.copyEntry(e) } label: { Image(systemName: "doc.on.doc") }
                }
                Button { onDelete() } label: { Image(systemName: "trash") }
            }
        }
        .buttonStyle(.plain).foregroundStyle(.white)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 10).fill(hover ? Color.white.opacity(0.08) : .clear))
        .contentShape(Rectangle()).onHover { hover = $0 }
        .onTapGesture { onOpen() }
    }
}

/// Panelde kişi satırı: tıklayınca Rehber'de açılır; üzerine gelince telefonu / e-postayı kopyala.
struct ContactRow: View {
    @ObservedObject private var notes = NotesModel.shared
    let contact: ContactHit
    let onOpen: () -> Void
    @State private var hover = false

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 15)).foregroundStyle(.white)
                .frame(width: 34, height: 34).background(Circle().fill(Color.white.opacity(0.12)))
            VStack(alignment: .leading, spacing: 1) {
                Text(contact.name).font(.system(size: notes.fontSize)).foregroundStyle(.white).lineLimit(1)
                if !contact.detail.isEmpty {
                    Text(contact.detail).font(.system(size: max(notes.fontSize - 1, 9))).foregroundStyle(dim).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if hover {
                if !contact.phone.isEmpty {
                    Button { copy(contact.phone) } label: { Image(systemName: "phone") }
                        .help(L("Telefonu kopyala", "Copy phone"))
                }
                if !contact.email.isEmpty {
                    Button { copy(contact.email) } label: { Image(systemName: "envelope") }
                        .help(L("E-postayı kopyala", "Copy email"))
                }
            }
        }
        .buttonStyle(.plain).foregroundStyle(.white)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 10).fill(hover ? Color.white.opacity(0.08) : .clear))
        .contentShape(Rectangle()).onHover { hover = $0 }
        .onTapGesture { onOpen() }
    }
}
