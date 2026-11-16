import SwiftUI
import AppKit

extension NotesModel {
    // MARK: - Cihazlarla eşitle

    /// Eşitle tuşu: aynı ağdaki açık cihazlarla (Hızlı Paylaş) notları eşitler: eksikler eklenir,
    /// aynı dosyanın yeni olanı eskisinin üzerine yazılır. Silinen dosyalar eşitlenmez.
    func syncNow() {
        guard !syncing else { return }
        syncing = true
        toast(L("Eşitleniyor…", "Syncing…"))
        Task {
            let r = await self.io { NoteSync.run() }
            self.syncing = false
            self.reload()
            self.toast(r.message)
        }
    }
}
