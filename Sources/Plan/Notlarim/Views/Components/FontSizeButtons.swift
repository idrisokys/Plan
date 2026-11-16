import SwiftUI

/// Alt çubuktaki yazı boyutu düğmeleri: A küçük / A büyük (⌘− / ⌘+).
struct FontSizeButtons: View {
    @EnvironmentObject var m: NotesModel

    var body: some View {
        HStack(spacing: 6) {
            Button { m.bumpFont(-1) } label: { Image(systemName: "textformat.size.smaller") }
                .disabled(m.fontSize <= NotesModel.minFont)
                .help(L("Yazıyı küçült (⌘−)", "Smaller text (⌘−)"))
            Button { m.bumpFont(1) } label: { Image(systemName: "textformat.size.larger") }
                .disabled(m.fontSize >= NotesModel.maxFont)
                .help(L("Yazıyı büyüt (⌘+)", "Larger text (⌘+)"))
        }
    }
}
