import SwiftUI

/// Düzenleme modunda seçili öğeler için: başa al, yukarı, aşağı, sona al.
struct MoveButtons: View {
    @EnvironmentObject var m: NotesModel

    var body: some View {
        HStack(spacing: 6) {
            Button { m.moveSelected(-2) } label: { Image(systemName: "arrow.up.to.line") }
                .disabled(!m.canMoveUp).help(L("Başa al", "Move to top"))
            Button { m.moveSelected(-1) } label: { Image(systemName: "chevron.up") }
                .disabled(!m.canMoveUp).help(L("Yukarı taşı", "Move up"))
            Button { m.moveSelected(1) } label: { Image(systemName: "chevron.down") }
                .disabled(!m.canMoveDown).help(L("Aşağı taşı", "Move down"))
            Button { m.moveSelected(2) } label: { Image(systemName: "arrow.down.to.line") }
                .disabled(!m.canMoveDown).help(L("Sona al", "Move to bottom"))
        }
    }
}

/// Düzenleme modunda birden çok öğe seçiliyken alt çubuk: seçili sayısı + sıra düğmeleri.
struct MultiBar: View {
    @EnvironmentObject var m: NotesModel

    var body: some View {
        HStack(spacing: 10) {
            Text("\(m.selected.count) " + L("seçili", "selected")).font(.caption).foregroundStyle(.secondary)
            Spacer()
            MoveButtons()
        }
        .frame(height: 30)
        .padding(8)
        .background(.bar)
    }
}
