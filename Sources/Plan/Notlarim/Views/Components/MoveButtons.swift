import SwiftUI

/// Düzenleme modunda seçili öğeler için: başa al, yukarı, aşağı, sona al.
struct MoveButtons: View {
    @EnvironmentObject var m: NotesModel

    var body: some View {
        HStack(spacing: 0) {
            IconBtn(MI.alignTop, help: L("Başa al", "Move to top")) { m.moveSelected(-2) }
                .disabled(!m.canMoveUp)
            IconBtn(MI.arrowUp, help: L("Yukarı taşı", "Move up")) { m.moveSelected(-1) }
                .disabled(!m.canMoveUp)
            IconBtn(MI.arrowDown, help: L("Aşağı taşı", "Move down")) { m.moveSelected(1) }
                .disabled(!m.canMoveDown)
            IconBtn(MI.alignBottom, help: L("Sona al", "Move to bottom")) { m.moveSelected(2) }
                .disabled(!m.canMoveDown)
        }
    }
}

/// Düzenleme modunda birden çok öğe seçiliyken alt çubuk: seçili sayısı + halka düğmesi + sıra düğmeleri.
struct MultiBar: View {
    @EnvironmentObject var m: NotesModel

    var body: some View {
        HStack(spacing: 0) {
            Text("\(m.selected.count) " + L("seçili", "selected"))
                .font(.system(size: 11))
                .foregroundStyle(NT.onSurface)
                .padding(.leading, 8)
            EditModeButton()
            BottomIcons()
            Spacer()
            MoveButtons()
        }
        .padding(8)
        .background(NT.bar)
    }
}
