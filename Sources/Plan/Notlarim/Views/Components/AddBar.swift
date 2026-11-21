import SwiftUI
import AppKit

/// Android'deki alt ekleme çubuğu: çerçeveli metin alanı; altta sayaç, düzenleme (halka) düğmesi, ara / temizle / yapıştır.
struct AddBar: View {
    @EnvironmentObject var m: NotesModel

    var body: some View {
        let canAdd = !m.linkText.trimmed.isEmpty
        let over = m.linkText.count > m.addMax
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $m.linkText)
                    .font(.system(size: m.fontSize))
                    .foregroundStyle(NT.onSurface)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .onChange(of: m.linkText) { new in
                        // Enter gönderir (Shift+Enter yeni satır). Yapıştırma birden fazla karakter ekler, etkilenmez.
                        if new.hasSuffix("\n"), new.count == m.prevLinkCount + 1, !NSEvent.modifierFlags.contains(.shift) {
                            m.linkText = String(new.dropLast())
                            m.addFromText()
                        }
                        m.prevLinkCount = m.linkText.count
                    }
                if m.linkText.isEmpty {
                    Text(L("Link veya metin yapıştır (Enter: kaydet)", "Paste a link or text (Enter: save)"))
                        .font(.system(size: m.fontSize))
                        .foregroundStyle(NT.onSurfaceVariant)
                        .padding(.horizontal, 17)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: m.editorHeight(for: m.linkText))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(NT.outline, lineWidth: 1))

            HStack(spacing: 0) {
                Text("\(m.linkText.count)/\(m.addMax)")
                    .font(.system(size: 11))
                    .foregroundStyle(over ? NT.error : NT.onSurface)
                    .padding(.leading, 8)
                EditModeButton()
                BottomIcons()
                Spacer()
                IconBtn(MI.search, help: L("Ara", "Search")) { m.startSearch() }
                    .disabled(!canAdd)
                IconBtn(MI.close, help: L("Temizle", "Clear")) { m.linkText = "" }
                    .disabled(m.linkText.isEmpty)
                IconBtn(MI.paste, help: L("Yapıştır", "Paste")) { m.paste() }
            }
        }
        .padding(8)
        .background(NT.bar)
    }
}

/// Düzenleme (çoklu seçim) moduna geçiren düğme: iç içe iki halka. Mod açıkken vurgu rengiyle çizilir.
struct EditModeButton: View {
    @EnvironmentObject var m: NotesModel

    var body: some View {
        let c = m.editMode ? NT.primary : NT.onSurface
        ZStack {
            Circle().stroke(c, lineWidth: 2).frame(width: 22, height: 22)
            Circle().stroke(c, lineWidth: 2).frame(width: 12, height: 12)
        }
        .frame(width: 34, height: 34)
        .contentShape(Rectangle())
        .help(m.editMode ? L("Düzenlemeyi bitir (⌘E)", "Done editing (⌘E)") : L("Düzenleme modu: satırları seç, sırala (⌘E)", "Edit mode: select and reorder rows (⌘E)"))
        .onTapGesture { m.toggleEdit() }
    }
}
