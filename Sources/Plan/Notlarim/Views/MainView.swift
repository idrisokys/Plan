import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Android'deki Notlarım ekranı: üstte başlık + klasör / U / D / yenile, ortada liste, altta ekleme çubuğu.
struct MainView: View {
    @EnvironmentObject var m: NotesModel

    var body: some View {
        VStack(spacing: 0) {
            if m.searchQuery != nil { SearchResultsView() } else { listView }
            if m.renaming != nil { RenameBar() }
            else if m.editMode && m.selected.count > 1 { MultiBar() }
            else { AddBar() }
        }
        .background(NT.bg)
        .navigationTitle("")
        .toolbar {
            // Tüm simgeler tek sırada, soldan sağa; aralarında boşluk yok.
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 0) {
                    if m.searchQuery != nil {
                        IconBtn(MI.arrowBack, help: L("Aramadan çık", "Exit search"), box: ToolbarMetrics.box) { m.exitSearch(true) }
                    } else if !m.stack.isEmpty {
                        IconBtn(MI.arrowBack, help: L("Geri", "Back"), box: ToolbarMetrics.box) { m.goBack() }
                    }
                    if m.searchQuery == nil {
                        IconBtn(MI.createNewFolder, help: L("Klasör", "Folder"), box: ToolbarMetrics.box) { m.sheet = .folder }
                        IconBtn(MI.refresh, help: L("Yenile (⌘R)", "Refresh (⌘R)"), box: ToolbarMetrics.box) { m.refresh() }
                        // Çöp: seçilenleri hızlıca .onemsiz klasörüne taşır
                        IconBtn(MI.delete, help: L("Seçilenleri .onemsiz klasörüne taşı", "Move selected to .onemsiz"), box: ToolbarMetrics.box) { m.trashSelected() }
                    }
                    PinWindowButton()
                    // Başlık yok; yalnızca arama sonucu ya da seçili sayısı varsa kısa bilgi gösterilir.
                    if !m.title.isEmpty {
                        Text(m.title)
                            .font(.system(size: 15))
                            .foregroundStyle(NT.onSurface)
                            .lineLimit(1).truncationMode(.tail)
                            .frame(maxWidth: 110, alignment: .leading)
                            .padding(.leading, 6)
                    }
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
            case .share:
                QuickShareSheet(files: m.sharing) { m.sheet = nil; m.sharing = [] }
            }
        }
        .onDrop(of: [UTType.url, UTType.plainText], isTargeted: nil) { providers in
            m.handleDrop(providers)
        }
    }

    @ViewBuilder
    private var listView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(m.list) { e in
                        VStack(spacing: 0) {
                            row(e)
                            Rectangle().fill(NT.outlineVariant).frame(height: 1)
                        }
                        .id(e.key)
                    }
                }
            }
            .onChange(of: m.revealTick) { _ in
                if let k = m.revealKey { proxy.scrollTo(k) }   // taşınan satır görünür kalsın
            }
            .overlay {
                if m.loaded != nil && m.list.isEmpty {
                    Text(L("Burada henüz bir şey yok. Alttaki alana link veya metin yapıştırın, bir linki pencereye sürükleyin ya da tarayıcıda Paylaş → Notlarım'ı seçin.", "Nothing here yet. Paste a link or text into the box below, drag a link into the window, or choose Share → My Notes in your browser."))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(NT.onSurface)
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
        HStack(spacing: 16) {
            if m.editMode {
                // Düzenleme modunda kutucuk yok: yalnızca boşluk (seçim satıra dokunarak yapılır)
                Color.clear.frame(width: 24, height: 24)
            } else {
                MIcon(e.isDir ? MI.folder : (e.isTxt ? MI.description : MI.link))
                    .foregroundStyle(NT.onSurface)
            }
            Text(e.title)
                .font(.system(size: m.fontSize))
                .foregroundStyle(NT.onSurface)
                .lineLimit(4).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            // Üç nokta: tek tıkla menü (Sabitle / Taşı / Paylaş / Sil). Sabitlenmiş öğede kırmızı.
            ZStack {
                // Simge ayrı çizilir: sabitlenmişse kırmızı, değilse normal renk (menü stili rengi bozamaz)
                MIcon(MI.moreVert)
                    .foregroundStyle(e.pinned ? NT.pinnedRed : NT.onSurface)
                    .allowsHitTesting(false)
                Menu {
                    Button(pinLabel) { m.togglePin(targets) }
                    Button(L("Taşı", "Move")) { m.beginMove(targets) }
                    Button(L("Paylaş", "Share")) { m.shareEntries(targets) }
                    Button(L("Sil", "Delete")) { m.deleteNow(targets) }
                } label: {
                    Color.clear.frame(width: 34, height: 34).contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .frame(width: 34, height: 34)
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(sel ? NT.secondaryContainer : NT.bg)
        .contentShape(Rectangle())
        .onTapGesture { m.tap(e) }
        .onLongPressGesture(minimumDuration: 0.5) { m.copyEntry(e) }
        .contextMenu {
            Button(pinLabel) { m.togglePin(targets) }
            Button(L("Taşı", "Move")) { m.beginMove(targets) }
            Button(L("Paylaş", "Share")) { m.shareEntries(targets) }
            Button(L("Sil", "Delete")) { m.deleteNow(targets) }
        }
    }
}
