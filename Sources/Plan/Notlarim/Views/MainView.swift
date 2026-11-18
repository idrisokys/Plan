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
        // Pencere başlığı da boş: "Notlarım" yazısı hiçbir yerde görünmez.
        .navigationTitle("")
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                // Başlık yok: "Notlarım" ve klasör adı gösterilmez; yalnızca arama bilgisi / seçili sayısı görünür
                if m.searchQuery != nil || (m.editMode && !m.selected.isEmpty) {
                    Text(m.title).font(.headline).lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: 160, alignment: .leading)
                }
                // Aramada yenile en solda (aramayı yeniler); normal görünümde çöp kutusunun soluna taşınır
                if m.searchQuery != nil {
                    Button { m.refresh() } label: { Image(systemName: "arrow.clockwise") }
                        .help(L("Yenile (⌘R)", "Refresh (⌘R)"))
                }
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
                    // Yenile: çöp kutusunun solunda; Link klasörünü tekrar kontrol eder ve listeyi yeniden yükler
                    Button { m.refresh() } label: { Image(systemName: "arrow.clockwise") }
                        .help(L("Yenile (⌘R)", "Refresh (⌘R)"))
                }
            }
        }
        .sheet(item: $m.sheet) { s in
            switch s {
            case .folder:
                FolderSheet()
            case .move:
                if let r = m.root, let c = m.current {
                    MoveSheet(root: r, current: c, exclude: Set(m.moving.filter { $0.isDir }.map { $0.key }))
                }
            case .placeD:
                if let r = m.root {
                    MoveSheet(root: r, current: m.current ?? r, exclude: [], mode: .placeD)
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
        let pinLabel = targets.allSatisfy { $0.pinned } ? L("Sabitlemeyi kaldır", "Unpin") : L("Sabitle", "Pin")
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
            // Üç nokta: tek tıkla menü (Düzenle / Sabitle / Taşı / Paylaş / Sil); "Düzenle" yalnızca bu satırın adını düzenler
            Menu {
                Button(L("Düzenle", "Edit")) { m.beginRename(e) }
                Divider()
                Button(pinLabel) { m.togglePin(targets) }
                Button(L("Taşı", "Move")) { m.beginMove(targets) }
                Button(L("Paylaş", "Share")) { m.shareEntries(targets) }
                Button(L("Sil", "Delete")) { m.deleteNow(targets) }
                Divider()
                Button(L("Veri yeri U", "Data place U")) { m.setPlaceU(e) }
                Button(L("Veri yeri D", "Data place D")) { m.beginPlaceD() }
            } label: {
                // Sabitlenmiş öğe: üç nokta koyu kırmızı
                Image(systemName: "ellipsis")
                    .foregroundColor(e.pinned ? Color(red: 0.72, green: 0.11, blue: 0.11) : Color.primary)
                    .frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .background((sel || m.renaming?.key == e.key) ? Color.accentColor.opacity(0.22) : Color.clear)
        .onTapGesture { m.tap(e) }
        .onLongPressGesture(minimumDuration: 0.5) { m.copyEntry(e) }
        .contextMenu {
            Button(pinLabel) { m.togglePin(targets) }
            Button(L("Taşı", "Move")) { m.beginMove(targets) }
            Button(L("Paylaş", "Share")) { m.shareEntries(targets) }
            Button(L("Sil", "Delete")) { m.deleteNow(targets) }
            Divider()
            Button(L("Düzenle", "Edit")) { m.beginRename(e) }
        }
    }
}
