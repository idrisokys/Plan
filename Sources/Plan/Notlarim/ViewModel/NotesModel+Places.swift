import SwiftUI

extension NotesModel {
    // MARK: - Veri yeri U / D

    private func placeName(_ u: URL) -> String {
        if let r = root, r.standardizedFileURL.path == u.standardizedFileURL.path { return L("Ana liste", "Main list") }
        return u.lastPathComponent
    }

    /// Üst çubuktaki U: içinde bulunulan klasör linklerin varsayılan kayıt yeri olur.
    func setPlaceUHere() {
        guard let target = current else { return }
        NotesStore.setPlaceU(target)
        toast(L("Veri yeri U: ", "Data place U: ") + placeName(target))
    }

    /// Üst çubuktaki D: içinde bulunulan klasör diğer kayıtların varsayılan kayıt yeri olur.
    func setPlaceDHere() {
        guard let target = current else { return }
        NotesStore.setPlaceD(target)
        toast(L("Veri yeri D: ", "Data place D: ") + placeName(target))
    }

    /// ⋮ → "Veri yeri U": seçili klasör (satır klasörse o, değilse içinde bulunulan klasör) linklerin varsayılan kayıt yeri olur.
    func setPlaceU(_ e: Entry) {
        guard let target = e.isDir ? e.url : current else { return }
        NotesStore.setPlaceU(target)
        toast(L("Veri yeri U: ", "Data place U: ") + placeName(target))
    }

    /// ⋮ → "Veri yeri D": diğer kayıtların (kısa metin .url ve .txt) hangi klasöre ekleneceği listeden seçilir.
    func beginPlaceD() { sheet = .placeD }

    func performPlaceD(to dir: URL) {
        NotesStore.setPlaceD(dir)
        sheet = nil
        toast(L("Veri yeri D: ", "Data place D: ") + placeName(dir))
    }
}
