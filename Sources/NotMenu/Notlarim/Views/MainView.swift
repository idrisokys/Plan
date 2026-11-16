import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MainView: View {
    @EnvironmentObject var m: NotesModel

    var body: some View {
        VStack(spacing: 0) {
            if m.searchQuery != nil { SearchResultsView() } else { listView }
            Divider()
            if m.renaming != nil { RenameBar() }
            else if m.editMode && m.selected.count > 1 { MultiBar() }
            else { AddBar() }
        }
        // Başlık sistem başlığı yerine araç çubuğunda durur; simgeler başlıktan hemen sonra sağa doğru sıralanır.
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                // Yenile: en solda; Link klasörünü tekrar kontrol eder ve listeyi yeniden yükler (aramada aramayı yeniler)
                Button { m.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .help(L("Yenile (⌘R)", "Refresh (⌘R)"))
                if m.searchQuery != nil {
                    Button { m.exitSearch(true) } label: { Image(systemName: "chevron.left") }
                        .help(L("Aramadan çık", "Exit search"))
                } else if !m.stack.isEmpty {
                    Button { m.goBack() } label: { Image(systemName: "chevron.left") }
                        .help(L("Geri", "Back"))
                }
                if m.searchQuery == nil {
                    Button { m.sheet = .folder } label: { Image(systemName: "folder.badge.plus") }
                        .help(L("Klasör", "Folder"))
                    // Çöp kutusu: Link klasöründeki her şeyi macOS Çöp Kutusu'na gönderir (önce sorar)
                    Button { m.askTrashAll = true } label: { Image(systemName: "trash") }
                        .help(L("Tüm notları Çöp Kutusu'na gönder", "Send all notes to Trash"))
                    // Eşitle: aynı ağdaki açık cihazlarla (Hızlı Paylaş) notları eşitler
                    Button { m.syncNow() } label: {
                        if m.syncing { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.triangle.2.circlepath") }
                    }
                    .disabled(m.syncing)
                    .help(L("Cihazlarla eşitle", "Sync with devices"))
                }
                // İkonların SAĞINDA; "Notlarım" başlığı gösterilmez, yalnızca klasör içindeyken / arama ve seçim sırasında bilgi yazısı çıkar
                if m.title != L("Notlarım", "My Notes") {
                    Text(m.title).font(.headline).lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: 160, alignment: .leading)
                }
            }
        }
        .confirmationDialog(L("Link klasöründeki tüm dosyalar Çöp Kutusu'na gönderilsin mi?", "Send everything in the Link folder to Trash?"),
                            isPresented: $m.askTrashAll, titleVisibility: .visible) {
            Button(L("Çöp Kutusu'na gönder", "Send to Trash"), role: .destructive) { m.trashAllToBin() }
            Button(L("Vazgeç", "Cancel"), role: .cancel) { }
        } message: {
            Text(L("Notlar, linkler ve klasörler Çöp Kutusu'na taşınır; oradan geri alabilirsiniz.", "Notes, links and folders are moved to the Trash; you can restore them from there."))
        }
        .sheet(item: $m.sheet) { s in
            switch s {
            case .folder:
                FolderSheet()
            case .move:
                if let r = m.root, let c = m.current {
                    MoveSheet(root: r, current: c, exclude: Set(m.moving.filter { $0.isDir }.map { $0.key }))
                }
            }
        }
        .onDrop(of: [UTType.url, UTType.plainText], isTargeted: nil) { providers in
            m.handleDrop(providers)
        }
    }

    @ViewBuilder
    private var listView: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(m.list) { e in row(e) }
            }
            .listStyle(.inset)
            .onChange(of: m.revealTick) { _ in
                if let k = m.revealKey { proxy.scrollTo(k) }   // taşınan satır görünür kalsın
            }
            .overlay {
                if m.loaded != nil && m.list.isEmpty {
                    Text(L("Burada henüz bir şey yok. Alttaki alana link veya metin yapıştırın, bir linki pencereye sürükleyin ya da tarayıcıda Paylaş → Notlarım'ı seçin.", "Nothing here yet. Paste a link or text into the box below, drag a link into the window, or choose Share → My Notes in your browser."))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(32)
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ e: Entry) -> some View {
        let sel = m.selected.contains(e.key)
        // Öğe birden çok seçilenin içindeyse işlem tüm seçilenlere uygulanır
        let targets: [Entry] = (sel && m.selected.count > 1) ? m.list.filter { m.selected.contains($0.key) } : [e]
        HStack(spacing: 10) {
            if m.editMode {
                // Düzenleme modunda soldaki boşluğa tıklamak satırı seçer / seçimi kaldırır
                Image(systemName: sel ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(sel ? Color.accentColor : Color.secondary.opacity(0.5))
                    .frame(width: 24)
                    .contentShape(Rectangle())
                    .onTapGesture { m.toggle(e.key) }
            } else {
                Image(systemName: e.isDir ? "folder" : (e.isTxt ? "doc.text" : "link"))
                    .frame(width: 24)
            }
            Text(e.title).font(.system(size: m.fontSize)).lineLimit(4).truncationMode(.tail)
            Spacer(minLength: 8)
            // Üç nokta: tek tıkla menü (Taşı / Paylaş / Sil); basılı tutunca düzenleme modu açılır/kapanır
            Menu {
                Button(m.editMode ? L("Düzenlemeyi bitir", "Done editing") : L("Düzenle", "Edit")) {
                    if m.editMode { m.toggleEdit() } else { m.beginEdit() }
                }
                Divider()
                Button(L("Taşı", "Move")) { m.beginMove(targets) }
                Button(L("Paylaş", "Share")) { m.shareEntries(targets) }
                Button(L("Sil", "Delete")) { m.deleteNow(targets) }
            } label: {
                Image(systemName: "ellipsis").frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                m.editMode.toggle(); m.selected = []
            })
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .background(sel ? Color.accentColor.opacity(0.22) : Color.clear)
        .onTapGesture { m.tap(e) }
        .onLongPressGesture(minimumDuration: 0.5) { m.copyEntry(e) }
        .contextMenu {
            Button(L("Taşı", "Move")) { m.beginMove(targets) }
            Button(L("Paylaş", "Share")) { m.shareEntries(targets) }
            Button(L("Sil", "Delete")) { m.deleteNow(targets) }
            Divider()
            Button(m.editMode ? L("Düzenlemeyi bitir", "Done editing") : L("Düzenle", "Edit")) { m.toggleEdit() }
        }
    }
}
