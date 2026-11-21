import SwiftUI

/// Eskiden üst satırda duran simgeler: geri, klasör, yenile, çöp, her zaman üstte.
/// Alt çubukta soldaki halka düğmesinin sağına, soldan sağa sıralanır.
struct BottomIcons: View {
    @EnvironmentObject var m: NotesModel

    var body: some View {
        HStack(spacing: 0) {
            if m.searchQuery != nil {
                IconBtn(MI.arrowBack, help: L("Aramadan çık", "Exit search")) { m.exitSearch(true) }
            } else if !m.stack.isEmpty {
                IconBtn(MI.arrowBack, help: L("Geri", "Back")) { m.goBack() }
            }
            if m.searchQuery == nil {
                IconBtn(MI.createNewFolder, help: L("Klasör", "Folder")) { m.sheet = .folder }
                IconBtn(MI.refresh, help: L("Yenile (⌘R)", "Refresh (⌘R)")) { m.refresh() }
                // Çöp: seçilenleri hızlıca .onemsiz klasörüne taşır
                IconBtn(MI.delete, help: L("Seçilenleri .onemsiz klasörüne taşı", "Move selected to .onemsiz")) { m.trashSelected() }
            }
            PinWindowButton(box: 34)
        }
    }
}
