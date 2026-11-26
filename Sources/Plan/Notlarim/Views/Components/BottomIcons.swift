import SwiftUI

/// Alt çubukta soldaki halka düğmesinin sağında duran simgeler. Yalnızca yenile kaldı
/// (geri, yeni klasör ve çöp simgeleri kaldırıldı).
struct BottomIcons: View {
    @EnvironmentObject var m: NotesModel

    var body: some View {
        HStack(spacing: 0) {
            if m.searchQuery == nil {
                IconBtn(MI.refresh, help: L("Yenile (⌘R)", "Refresh (⌘R)")) { m.refresh() }
            }
        }
    }
}
