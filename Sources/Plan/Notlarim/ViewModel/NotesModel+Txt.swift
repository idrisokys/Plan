import SwiftUI
import AppKit

extension NotesModel {
    // MARK: - Metin dosyası (.txt) tam pencere görünümü

    func openTxt(_ e: Entry, _ text: String) {
        txt = e
        txtSaved = text
        txtDraft = text
        txtEditing = false
        txtAskDiscard = false
        txtSaving = false
        txtSearching = false
        txtQuery = ""
        txtRecompute()
    }

    func txtStartEdit() {
        guard txt != nil, !txtEditing else { return }
        txtCloseSearch()
        txtDraft = txtSaved
        txtEditing = true
    }

    // MARK: Metin içinde arama (okuma görünümü)

    /// Türkçe harfleri sadeleştirir (ı/İ→i, ş→s ...); UTF-16 uzunluğunu korur, böylece konumlar metinle aynı kalır.
    nonisolated static func fk(_ t: String) -> String {
        var out = String.UnicodeScalarView()
        for u in t.unicodeScalars {
            switch u {
            case "ı", "İ", "I": out.append("i")
            case "ö", "Ö": out.append("o")
            case "ü", "Ü": out.append("u")
            case "ş", "Ş": out.append("s")
            case "ç", "Ç": out.append("c")
            case "ğ", "Ğ": out.append("g")
            default:
                let l = String(u).lowercased().unicodeScalars
                if l.count == 1, let f = l.first, f.utf16.count == u.utf16.count { out.append(f) } else { out.append(u) }
            }
        }
        return String(out)
    }

    func txtRecompute() {
        let q = NotesModel.fk(txtQuery.trimmed)
        guard txtSearching, !q.isEmpty else { txtMatches = []; txtCur = 0; return }
        let hay = NotesModel.fk(txtSaved) as NSString
        var out = [NSRange]()
        var from = 0
        while out.count < 5000 && from < hay.length {
            let r = hay.range(of: q, options: [], range: NSRange(location: from, length: hay.length - from))
            if r.location == NSNotFound { break }
            out.append(r)
            from = r.location + max(r.length, 1)
        }
        txtMatches = out
        txtCur = 0
    }

    func txtGo(_ d: Int) {
        guard !txtMatches.isEmpty else { return }
        txtCur = (txtCur + d + txtMatches.count) % txtMatches.count
    }

    func txtCloseSearch() {
        txtSearching = false
        txtQuery = ""
    }

    /// Kaydeder ve okuma görünümüne döner.
    func txtSave() {
        guard let e = txt, !txtSaving else { return }
        let t = txtDraft
        txtSaving = true
        Task {
            let ok = await self.io { NotesStore.writePlain(e.url, t) }
            self.txtSaving = false
            if ok {
                if self.txt?.key == e.key { self.txtSaved = t; self.txtEditing = false; self.txtAskDiscard = false; self.txtRecompute() }
            } else {
                self.toast(L("Kaydedilemedi", "Couldn't save"))
            }
        }
    }

    func txtDiscard() {
        txtDraft = txtSaved
        txtEditing = false
        txtAskDiscard = false
    }

    /// Geri: kaydedilmemiş değişiklik varsa sorar; düzenliyorsa okumaya döner; değilse listeye çıkar.
    func txtBack() {
        if txtSearching { txtCloseSearch() }
        else if txtDirty { txtAskDiscard = true }
        else if txtEditing { txtEditing = false }
        else { txt = nil }
    }
}
