import SwiftUI
import AppKit

// Koyu zemin, yarı saydam siyah yuvarlak düğmeler.
// Üst çubuk: [OCR] [arama kutusu] [Kalem → Notlarım] [Paylaş]
// Çubuğu basılı tutup sağa çekersen sağa gizlenir (yalnızca OCR simgesi görünür); o bölümü sola çekersen tamamı açılır.
private let panelBG = Color(white: 0.13)
private let idleBG = Color.black.opacity(0.45)
private let dim = Color.white.opacity(0.67)

/// Paylaş / ON simgesinin ve altındaki ⇄ simgesinin çapı (aynı hizada dururlar).
private let onSize: CGFloat = 30

/// Arama çubuğunun (ve paylaşım açıkken cihaz satırının) yüksekliği: sağdaki düğme simgeleriyle (circle varsayılanı) aynı.
private let barH: CGFloat = 36

private func circle(_ system: String, size: CGFloat = 36) -> some View {
    Image(systemName: system).font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
        .frame(width: size, height: size)
        .background(Circle().fill(idleBG))
}

struct ContentView: View {
    @ObservedObject private var qs = QuickShare.shared
    @State private var text = ""
    @State private var status = ""
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Arama kutusunun ipucu: bugünün tarihi, örn. "Cuma 15 Kasım"
    private var todayLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "EEEE d MMMM"
        return f.string(from: Date())
    }

    var body: some View {
        VStack(spacing: 6) {
            if !status.isEmpty { Text(status).font(.footnote).foregroundStyle(dim) }
            bar
        }
        .padding(12)
        .frame(width: 330)
        .background(panelBG)
        .preferredColorScheme(.dark)
        .onAppear { focused = true }
        .onChange(of: qs.running) { on in if !on { focused = true } }     // paylaşım kapanınca arama kutusu geri gelir
        .onReceive(qs.$message) { if !$0.isEmpty { flash($0) } }
    }

    // MARK: Üst çubuk
    private var bar: some View {
        // Paylaşım açıkken arama kutusu kaybolur; yerine cihaza gönderme seçenekleri gelir (düğmeler en alt satırda hizalı; liste yukarı doğru uzar).
        let rowH: CGFloat? = qs.running ? barH : nil
        return HStack(alignment: qs.running ? .bottom : .center, spacing: 8) {
            // OCR: ekrandan alan seç, içindeki yazıyı okuyup panoya kopyala
            Button { ScreenOCR.run() } label: { circle("text.viewfinder") }
                .buttonStyle(.plain).help(L("Ekrandan yazı kopyala (OCR)", "Copy text from screen (OCR)"))
                .frame(height: rowH)

            if qs.running {
                devicesList
            } else {
                TextField("", text: $text, prompt: Text(todayLabel).foregroundColor(dim))
                    .textFieldStyle(.plain).font(.system(size: 16)).foregroundStyle(.white)
                    .lineLimit(1).focused($focused).onSubmit(submit)
                    .padding(.horizontal, 14).frame(height: barH)
                    .background(Capsule().fill(idleBG))
            }

            // Kalem: Notlarım (notlar ve linkler) penceresini açar; ayrı uygulama değil, bu uygulamanın parçası
            Button { notesButton() } label: { circle("square.and.pencil") }
                .buttonStyle(.plain).help(L("Notlarım (aç/kapat) · yazı varsa Notlarım'da ara", "My Notes (open/close) · searches notes if text is typed"))
                .frame(height: rowH)
            // Hızlı Paylaş: dokun = aç/kapat. Açıkken ikon açık mavi "ON" olur. (Basılı tutarak klasör açma kaldırıldı.)
            shareButton
                .contentShape(Circle())
                .onTapGesture { qs.toggle() }
                .help("Hızlı Paylaş: dokun aç/kapat")
                .frame(height: rowH)
        }
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
                    .frame(maxWidth: .infinity, minHeight: barH, alignment: .leading)
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
                    .frame(maxWidth: .infinity, minHeight: barH, alignment: .leading)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: barH / 2).fill(idleBG))
    }

    /// Gönderme / alma bilgisi: bildirim yok, yalnızca bilgi varken tek satır (açıklama ve simge yok).
    @ViewBuilder private var infoLine: some View {
        if let i = qs.info {
            VStack(spacing: 0) {
                Text(i.text)
                    .font(.system(size: 15)).foregroundStyle(.white).lineLimit(1).truncationMode(.middle)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: barH, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { if let f = i.folder { NSWorkspace.shared.open(f) } }     // "Alındı" satırı: kayıt klasörünü aç
                    .help(i.folder != nil ? "Kayıt klasörünü aç" : "")
                Divider().overlay(Color.white.opacity(0.1)).padding(.horizontal, 8)
            }
        }
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

    /// Kalem simgesi: kutuda yazı varsa Notlarım'da arar, yoksa Notlarım penceresini açar/kapatır.
    private func notesButton() {
        if trimmed.isEmpty { NotesWindow.toggle() } else { searchNotes() }
    }

    /// Yazılanı Notlarım'da arar: Notlarım penceresini açar ve yazılanı orada arar (plan://search ile aynı yol).
    private func searchNotes() {
        let q = trimmed
        guard !q.isEmpty else { return }
        text = ""
        NotesWindow.show()
        NotesModel.shared.externalSearch(q)
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
