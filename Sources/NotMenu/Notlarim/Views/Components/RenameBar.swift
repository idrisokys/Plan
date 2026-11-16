import SwiftUI
import AppKit

struct RenameBar: View {
    @EnvironmentObject var m: NotesModel
    @State private var prevCount = 0

    var body: some View {
        VStack(spacing: 6) {
            // Ekleme alanıyla aynı boyutta: satır seçilince alt çubuk küçülmez
            ZStack(alignment: .topLeading) {
                TextEditor(text: $m.renameText)
                    .font(.system(size: m.fontSize))
                    .scrollContentBackground(.hidden)
                    .padding(4)
                if m.renameText.isEmpty {
                    Text(m.renaming?.isDir == true ? L("Klasör adı", "Folder name") : L("Ad", "Name"))
                        .font(.system(size: m.fontSize))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: m.editorMinHeight, maxHeight: m.editorMaxHeight)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.35)))
            .onChange(of: m.renameText) { v in
                // Enter doğrudan kaydeder (Shift+Enter yeni satır). Yapıştırma birden fazla karakter ekler, etkilenmez.
                if v.hasSuffix("\n"), v.count == prevCount + 1, !NSEvent.modifierFlags.contains(.shift) {
                    m.renameText = String(v.dropLast())
                    prevCount = m.renameText.count
                    if !m.renameText.trimmed.isEmpty { m.saveRename() }
                    return
                }
                prevCount = v.count
                // Uzunluk sınırlanır (.url kayıtlarında 20 000; 220'yi aşan kayıt .txt olur)
                if v.count > m.editCap { m.renameText = String(v.prefix(m.editCap)) }
            }
            HStack(spacing: 10) {
                let over = m.renameText.count > m.maxChars
                Text(over ? "\(m.renameText.count)/\(m.maxChars) → .txt" : "\(m.renameText.count)/\(m.maxChars)")
                    .font(.footnote)
                    .foregroundStyle(over ? Color.red : Color.secondary)
                DoneEditButton()
                MoveButtons()
                Spacer()
                Button { m.pasteIntoRename() } label: { Image(systemName: "doc.on.clipboard") }
                    .help(L("Yapıştır", "Paste"))
                Button { m.saveRename() } label: { Image(systemName: "square.and.arrow.down") }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(m.renameText.trimmed.isEmpty)
                    .help(L("Kaydet (⌘S)", "Save (⌘S)"))
            }
            .frame(height: 30)   // ekleme çubuğundaki düğme satırıyla aynı yükseklik
        }
        .padding(8)
        .background(.bar)
    }
}
