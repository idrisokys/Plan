import SwiftUI
import AppKit

/// .txt dosyasını tüm pencerede gösterir. Sağ üstteki kalemle düzenlenir, kaydet simgesiyle kaydedilip okumaya dönülür.
/// Okuma görünümünde arama (büyüteç): eşleşmeler işaretlenir, ▲▼ ile gezilir.
struct TxtView: View {
    @EnvironmentObject var m: NotesModel
    @FocusState private var focused: Bool
    @FocusState private var searchFocused: Bool

    var body: some View {
        Group {
            if m.txtEditing {
                TextEditor(text: $m.txtDraft)
                    .font(.system(size: m.fontSize))
                    .foregroundStyle(NT.onSurface)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .focused($focused)
                    .onAppear { DispatchQueue.main.async { focused = true } }
            } else {
                ReadTextView(text: m.txtSaved, size: m.fontSize, matches: m.txtMatches, cur: m.txtCur)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NT.bg)
        .navigationTitle("")
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                IconBtn(MI.arrowBack, help: L("Geri", "Back")) { m.txtBack() }
                if !(m.txtSearching && !m.txtEditing) {
                    Text(m.txt?.title ?? "")
                        .font(.system(size: 20))
                        .foregroundStyle(NT.onSurface)
                        .lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: 140, alignment: .leading)
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if m.txtEditing {
                    IconBtn(MI.save, tint: NT.primary, help: L("Kaydet (⌘S)", "Save (⌘S)")) { m.txtSave() }
                        .keyboardShortcut("s", modifiers: .command)
                        .disabled(m.txtSaving)
                } else if m.txtSearching {
                    TextField(L("Metinde ara", "Search in text"), text: $m.txtQuery)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                        .focused($searchFocused)
                        .onSubmit { m.txtGo(1) }
                    if !m.txtQuery.trimmed.isEmpty {
                        Text(m.txtMatches.isEmpty ? "0" : "\(m.txtCur + 1)/\(m.txtMatches.count)")
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(NT.onSurface)
                    }
                    IconBtn(MI.arrowUp, help: L("Önceki", "Previous")) { m.txtGo(-1) }
                        .disabled(m.txtMatches.isEmpty)
                    IconBtn(MI.arrowDown, help: L("Sonraki", "Next")) { m.txtGo(1) }
                        .disabled(m.txtMatches.isEmpty)
                    IconBtn(MI.close, help: L("Aramayı kapat", "Close search")) { m.txtCloseSearch() }
                } else {
                    IconBtn(MI.contentCopy, help: L("Kopyala", "Copy")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(m.txtSaved, forType: .string)
                        HUD.show(L("Kopyalandı", "Copied"))
                    }
                    IconBtn(MI.search, help: L("Ara (⌘F)", "Search (⌘F)")) { m.txtSearching = true }
                    IconBtn(MI.edit, help: L("Düzenle (⌘E)", "Edit (⌘E)")) { m.txtStartEdit() }
                }
            }
        }
        .onChange(of: m.txtSearching) { on in
            if on { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { searchFocused = true } }
        }
        .alert(L("Kaydedilmemiş değişiklikler var", "Unsaved changes"), isPresented: $m.txtAskDiscard) {
            Button(L("Kaydet", "Save")) { m.txtSave() }
            Button(L("Kaydetme", "Discard"), role: .destructive) { m.txtDiscard() }
            Button(L("İptal", "Cancel"), role: .cancel) { }
        } message: {
            Text(L("Değişiklikleri kaydetmek ister misiniz?", "Do you want to save your changes?"))
        }
    }
}

/// Salt okunur, seçilebilir metin; arama eşleşmeleri işaretlenir, geçerli eşleşme görünür yere kaydırılır.
struct ReadTextView: NSViewRepresentable {
    let text: String
    let size: Double
    let matches: [NSRange]
    let cur: Int

    func makeNSView(context: Context) -> NSScrollView {
        let sv = NSTextView.scrollableTextView()
        sv.drawsBackground = false
        if let tv = sv.documentView as? NSTextView {
            tv.isEditable = false
            tv.isSelectable = true
            tv.drawsBackground = false
            tv.textContainerInset = NSSize(width: 12, height: 12)
        }
        return sv
    }

    func updateNSView(_ sv: NSScrollView, context: Context) {
        guard let tv = sv.documentView as? NSTextView else { return }
        let attr = NSMutableAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: CGFloat(size)),
            .foregroundColor: NT.onSurfaceNS
        ])
        for (k, r) in matches.enumerated() where NSMaxRange(r) <= attr.length {
            let c = k == cur ? NT.hiCur : NT.hiAll
            attr.addAttribute(.backgroundColor, value: c, range: r)
        }
        tv.textStorage?.setAttributedString(attr)
        if cur < matches.count, NSMaxRange(matches[cur]) <= attr.length { tv.scrollRangeToVisible(matches[cur]) }
    }
}
