import SwiftUI

/// Düzenleme modunda seçili öğeler için: yukarı, aşağı.
struct MoveButtons: View {
    @EnvironmentObject var m: NotesModel

    var body: some View {
        HStack(spacing: 0) {
            IconBtn(MI.arrowUp, help: L("Yukarı taşı", "Move up")) { m.moveSelected(-1) }
                .disabled(!m.canMoveUp)
            IconBtn(MI.arrowDown, help: L("Aşağı taşı", "Move down")) { m.moveSelected(1) }
                .disabled(!m.canMoveDown)
        }
    }
}

/// Düzenleme modunda birden çok öğe seçiliyken alt çubuk: halka düğmesi + sıra düğmeleri.
struct MultiBar: View {
    @EnvironmentObject var m: NotesModel

    var body: some View {
        HStack(spacing: 0) {
            EditModeButton()
            BottomIcons()
            Spacer()
            MoveButtons()
        }
        .padding(8)
        .background(NT.bar)
    }
}
