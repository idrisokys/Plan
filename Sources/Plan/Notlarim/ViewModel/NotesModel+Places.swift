import SwiftUI

extension NotesModel {
    // MARK: - Veri yeri U / D (Android'deki üst çubuk U ve D düğmeleri)

    private func placeName(_ u: URL) -> String {
        if let r = root, r.standardizedFileURL.path == u.standardizedFileURL.path { return L("Ana liste", "Main list") }
        return u.lastPathComponent
    }

    /// U: içinde bulunulan klasör linklerin (URL) varsayılan kayıt yeri olur.
    func setPlaceUHere() {
        guard let target = current else { return }
        NotesStore.setPlaceU(target)
        toast(L("Veri yeri U: ", "Data place U: ") + placeName(target))
    }

    /// D: içinde bulunulan klasör diğer kayıtların (kısa metin ve .txt) varsayılan kayıt yeri olur.
    func setPlaceDHere() {
        guard let target = current else { return }
        NotesStore.setPlaceD(target)
        toast(L("Veri yeri D: ", "Data place D: ") + placeName(target))
    }
}
