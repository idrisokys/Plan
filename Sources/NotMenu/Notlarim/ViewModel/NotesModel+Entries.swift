import SwiftUI
import AppKit

extension NotesModel {
    // MARK: - Satır işlemleri

    func tap(_ e: Entry) {
        if editMode { toggle(e.key) }
        else if e.isDir { setStack(stack + [e]) }
        else { open(e) }
    }

    func toggle(_ key: String) {
        if selected.contains(key) { selected.remove(key) } else { selected.insert(key) }
    }

    func toggleEdit() {
        if txt != nil { txtStartEdit(); return }   // .txt açıkken ⌘E metni düzenler
        editMode.toggle()
        selected = []
    }

    /// ⋮ menüsündeki "Düzenle": düzenleme modunu açar (kapalıysa); açıksa açık bırakır.
    func beginEdit() {
        if !editMode { editMode = true; selected = [] }
    }

    func open(_ e: Entry) {
        Task {
            if e.isTxt {
                let t = await self.io { NotesStore.readPlain(e.url) }
                if let t = t { self.openTxt(e, t) } else { self.toast(L("Dosya okunamadı", "Couldn't read the file")) }
                return
            }
            let (u, t) = await self.io { NotesStore.readLink(e.url) }
            if let u = u {
                // Yerel dosya / uygulama çalıştıran şemalar açılmaz (elle yazılmış veya geri yüklenmiş .url dosyalarına karşı)
                if let link = NotesStore.makeURL(u), !["file", "javascript"].contains(link.scheme?.lowercased() ?? ""),
                   NSWorkspace.shared.open(link) { return }
                self.toast(L("Link açılamadı", "Couldn't open the link"))
            } else if let t = t {
                // Kısa metin (not): önizleme açılmaz, tek tıklayınca metin doğrudan panoya kopyalanır
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(t, forType: .string)
                self.toast(L("Kopyalandı", "Copied"))
            } else {
                self.toast(L("Link okunamadı", "Couldn't read the link"))
            }
        }
    }
}
