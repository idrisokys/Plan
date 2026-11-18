import SwiftUI
import AppKit

extension NotesModel {
    // MARK: - Düzenleme

    /// "Sil": öğeler silinmez, ana dizindeki gizli .onemsiz klasörüne taşınır.
    func deleteNow(_ items: [Entry], then: (() -> Void)? = nil) {
        selected = []
        Task {
            let n = await self.io { items.filter { NotesStore.trash($0.url) }.count }
            self.reload()
            then?()
            self.toast(n == items.count
                ? L(".onemsiz klasörüne taşındı (\(n))", "Moved to .onemsiz (\(n))")
                : L("\(n)/\(items.count) öğe .onemsiz'e taşınabildi", "\(n)/\(items.count) items moved to .onemsiz"))
        }
    }

    /// "Sabitle" / "Sabitlemeyi kaldır": hepsi sabitliyse kaldırır, değilse hepsini sabitler.
    func togglePin(_ items: [Entry]) {
        guard let dir = current, !items.isEmpty else { return }
        let pin = !items.allSatisfy { $0.pinned }
        let names = items.map { $0.name }
        selected = []
        Task {
            await self.io { NotesStore.setPinned(dir, names, pin) }
            self.reload()
        }
    }

    /// "Paylaş": seçili notların kaynak dosyaları (.txt / .url) Hızlı Paylaş ile açık cihazlara gönderilir; klasörler gönderilemez.
    func shareEntries(_ items: [Entry]) {
        let files = items.filter { !$0.isDir }.map { $0.url }
        if files.isEmpty { toast(L("Klasörler paylaşılamaz", "Folders cannot be shared")); return }
        selected = []
        sharing = files
        sheet = .share
    }

    /// ⋮ → "Düzenle": yalnızca bu satırın adını alttaki alanda düzenler (seçim modu açılmaz).
    func beginRename(_ e: Entry) {
        editMode = false
        selected = []
        inlineRename = true
        renaming = e
        renameText = e.title
    }

    /// Satır içi düzenlemeyi kapatır (kaydedilmemiş değişiklik uygulanmaz).
    func cancelRename() {
        guard inlineRename else { return }
        inlineRename = false
        renaming = nil
        renameText = ""
    }

    func pasteIntoRename() {
        if let s = NSPasteboard.general.string(forType: .string) { renameText = String(s.prefix(editCap)) }
    }

    func saveRename() {
        guard let r = renaming, let dir = current else { return }
        let n = renameText
        if n.trimmed.isEmpty { return }
        let toTxt = !r.isDir && !r.isTxt && n.trimmed.count > maxChars
        inlineRename = false
        renaming = nil
        selected = []
        editMode = false          // kayıt yapılınca düzenleme modu otomatik kapanır
        Task {
            let ok = await self.io { () -> Bool in
                if toTxt {
                    // Link ise adres kaybolmasın diye metnin altına eklenir
                    let (u, _) = NotesStore.readLink(r.url)
                    var body = n.trimmed
                    if let u = u { body += "\n" + u }
                    return NotesStore.convertToTxt(dir, r, body)
                }
                return NotesStore.rename(dir, r, n)
            }
            self.reload()
            if !ok { self.toast(L("Ad değiştirilemedi (aynı adda öğe olabilir)", "Couldn't rename (an item with that name may exist)")) }
            else if toTxt { self.toast(L("Uzun olduğu için .txt olarak kaydedildi", "Too long, saved as .txt")) }
        }
    }

    func createFolder(_ name: String) {
        guard let dir = current else { return }
        Task {
            _ = await self.io { NotesStore.addFolder(dir, name) }
            self.reload()
        }
    }

    func beginMove(_ targets: [Entry]) {
        moving = targets
        sheet = .move
    }

    func performMove(to target: URL) {
        let files = moving
        sheet = nil
        moving = []
        selected = []
        Task {
            let ok = await self.io { files.filter { NotesStore.moveEntry($0, to: target) }.count }
            self.reload()
            self.toast(ok == files.count
                  ? L("\(ok) öğe taşındı", "\(ok) item(s) moved")
                  : L("\(ok)/\(files.count) öğe taşınabildi", "\(ok)/\(files.count) item(s) could be moved"))
        }
    }
}
