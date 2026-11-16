import SwiftUI
import AppKit

extension NotesModel {
    // MARK: - Ekleme

    func addTxt() {
        let text = linkText.trimmed
        guard !text.isEmpty, let dir = current else { return }
        linkText = ""
        Task {
            let ok = await self.io { NotesStore.addTextFile(dir, text: text) }
            self.reload()
            self.toast(ok ? L("Metin dosyası eklendi", "Text file added") : L("Eklenemedi", "Couldn't add"))
        }
    }

    /// Enter / gönder: kural NotesStore.submit'te (menü çubuğu paneli de aynısını kullanır):
    /// link ise link olarak, sınırı aşan metin .txt olarak, kısa metin not olarak kaydedilir.
    func addFromText() {
        let text = linkText.trimmed
        guard !text.isEmpty, let dir = current else { return }
        linkText = ""
        Task {
            let r = await NotesStore.submit(dir, text)
            self.reload()
            switch r {
            case .added:    self.toast(L("Eklendi", "Added"))
            case .textFile: self.toast(L("Metin dosyası eklendi", "Text file added"))
            case .failed:   self.toast(L("Kaydedilemedi", "Couldn't save"))
            }
        }
    }

    /// Satıra uzun basınca metni doğrudan panoya kopyalar (.txt: içerik, link: adres, not: metin, klasör: ad).
    func copyEntry(_ e: Entry) {
        Task {
            var t: String? = e.title
            if !e.isDir {
                if e.isTxt { t = await self.io { NotesStore.readPlain(e.url) } }
                else { let (u, n) = await self.io { NotesStore.readLink(e.url) }; t = u ?? n ?? e.title }
            }
            if let t = t {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(t, forType: .string)
                self.toast(L("Kopyalandı", "Copied"))
            } else { self.toast(L("Kopyalanamadı", "Couldn't copy")) }
        }
    }

    /// Sürükle-bırak ve Servisler menüsünden gelen metin/link.
    func addExternal(_ text: String, into dir: URL, okMessage: String, subject: String? = nil) {
        Task {
            let ok = await NotesStore.addFromText(dir, text, subject)
            self.reload()
            self.toast(ok ? okMessage : L("Kaydedilemedi", "Couldn't save"))
        }
    }

    /// Servisler menüsü: ana listeye ekler (Paylaş → Notlarım).
    /// `subject`: paylaşan uygulamanın (tarayıcı) verdiği sayfa başlığı; yoksa başlık sayfadan alınır.
    func shareAdd(_ text: String, subject: String? = nil) {
        if text.trimmed.isEmpty { toast(L("Paylaşılacak bir şey bulunamadı", "Nothing to share")); return }
        guard let r = root else { toast(L("Önce Notlarım’ı açın (Link klasörü bulunamadı)", "Open My Notes first (Link folder not found)")); return }
        addExternal(text, into: r, okMessage: L("Kaydedildi", "Saved"), subject: subject)
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let dir = current else { return false }
        for p in providers {
            if p.canLoadObject(ofClass: URL.self) {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    guard let url = url, !url.isFileURL else { return }
                    Task { @MainActor in self.addExternal(url.absoluteString, into: dir, okMessage: L("Eklendi", "Added")) }
                }
                return true
            }
            if p.canLoadObject(ofClass: String.self) {
                _ = p.loadObject(ofClass: String.self) { s, _ in
                    guard let s = s, !s.trimmed.isEmpty else { return }
                    Task { @MainActor in self.addExternal(s, into: dir, okMessage: L("Eklendi", "Added")) }
                }
                return true
            }
        }
        return false
    }

    func paste() {
        if let s = NSPasteboard.general.string(forType: .string) { linkText = s }
    }
}
