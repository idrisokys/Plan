import SwiftUI
import AppKit

/// Düzenleme modunda tek öğe seçilince alt çubuk: adı değiştirme alanı (Android ile aynı yerleşim).
struct RenameBar: View {
    @EnvironmentObject var m: NotesModel
    @State private var prevCount = 0

    var body: some View {
        let over = m.renameText.count > m.maxChars
        let canSave = !m.renameText.trimmed.isEmpty
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $m.renameText)
                    .font(.system(size: m.fontSize))
                    .foregroundStyle(NT.onSurface)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                if m.renameText.isEmpty {
                    Text(m.renaming?.isDir == true ? L("Klasör adı", "Folder name") : L("Ad", "Name"))
                        .font(.system(size: m.fontSize))
                        .foregroundStyle(NT.onSurfaceVariant)
                        .padding(.horizontal, 17)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: m.editorHeight(for: m.renameText))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(NT.outline, lineWidth: 1))
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

            HStack(spacing: 0) {
                Text(over ? "\(m.renameText.count)/\(m.maxChars) → .txt" : "\(m.renameText.count)/\(m.maxChars)")
                    .font(.system(size: 11))
                    .foregroundStyle(over ? NT.error : NT.onSurface)
                    .padding(.leading, 8)
                EditModeButton()
                Spacer()
                IconBtn(MI.paste, help: L("Yapıştır", "Paste")) { m.pasteIntoRename() }
                IconBtn(MI.save, tint: canSave ? NT.primary : NT.onSurface, help: L("Kaydet (⌘S)", "Save (⌘S)")) { m.saveRename() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!canSave)
                if !m.inlineRename { MoveButtons() }
            }
        }
        .padding(8)
        .background(NT.bar)
    }
}
