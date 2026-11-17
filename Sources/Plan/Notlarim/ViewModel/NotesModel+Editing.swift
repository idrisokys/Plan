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

    /// "Paylaş": notlar metin olarak paylaşılır (.txt: içerik, link: adres, not: metin); klasörler paylaşılamaz.
    func shareEntries(_ items: [Entry]) {
        Task {
            let texts: [String] = await self.io { () -> [String] in
                var out = [String]()
                for e in items where !e.isDir {
                    if e.isTxt { if let t = NotesStore.readPlain(e.url) { out.append(t) } }
                    else { let (u, t) = NotesStore.readLink(e.url); out.append(u ?? t ?? e.title) }
                }
                return out
            }
            if texts.isEmpty { self.toast(L("Klasörler paylaşılamaz", "Folders cannot be shared")); return }
            self.selected = []
            self.editMode = false
            guard let v = (NSApp.keyWindow ?? NSApp.mainWindow)?.contentView else { return }
            let picker = NSSharingServicePicker(items: [texts.joined(separator: "\n\n")])
            picker.show(relativeTo: NSRect(x: v.bounds.midX, y: v.bounds.midY, width: 1, height: 1), of: v, preferredEdge: .minY)
        }
    }

    func pasteIntoRename() {
        if let s = NSPasteboard.general.string(forType: .string) { renameText = String(s.prefix(editCap)) }
    }

    func saveRename() {
        guard let r = renaming, let dir = current else { return }
        let n = renameText
        if n.trimmed.isEmpty { return }
        let toTxt = !r.isDir && !r.isTxt && n.trimmed.count > maxChars
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
