import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Android'deki Notlarım ekranı: üstte başlık + klasör / U / D / yenile, ortada liste, altta ekleme çubuğu.
struct MainView: View {
    @EnvironmentObject var m: NotesModel
    private let menuPad: CGFloat = 8      // üç noktanın sağındaki boşluk da menüyü açar

    var body: some View {
        VStack(spacing: 0) {
            // Simgeler alt çubukta (soldaki halka düğmesinin sağında); üstte yalnızca trafik ışıkları yeri ve varsa kısa bilgi.
            TitleBarRow {
                // Başlık yok; yalnızca arama sonucu ya da seçili sayısı varsa kısa bilgi gösterilir.
                if !m.title.isEmpty {
                    Text(m.title)
                        .font(.system(size: 15))
                        .foregroundStyle(NT.onSurface)
                        .lineLimit(1).truncationMode(.tail)
                        .padding(.leading, 6)
                }
            }
            if m.searchQuery != nil { SearchResultsView() } else { listView }
            if m.renaming != nil { RenameBar() }
            else if m.editMode && m.selected.count > 1 { MultiBar() }
            else { AddBar() }
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(NT.bg)
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
        let pinLabel = targets.allSatisfy { $0.pinned } ? L("Sabiti kaldır", "Unpin") : L("Sabitle", "Pin")
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
            // Üç nokta ve sağındaki boşluk: tek tıkla menü (Sabitle / Düzenle / Taşı / Paylaş / Sil). Sabitlenmiş öğede kırmızı.
            ZStack(alignment: .leading) {
                // Simge ayrı çizilir: sabitlenmişse kırmızı, değilse normal renk (menü stili rengi bozamaz)
                MIcon(MI.moreVert)
                    .foregroundStyle(e.pinned ? NT.pinnedRed : NT.onSurface)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
                Menu {
                    Button(pinLabel) { m.togglePin(targets) }
                    Button(L("Düzenle", "Edit")) { m.beginRename(e) }
                    Button(L("Taşı", "Move")) { m.beginMove(targets) }
                    Button(L("Paylaş", "Share")) { m.shareEntries(targets) }
                    Button(L("Sil", "Delete")) { m.deleteNow(targets) }
                } label: {
                    Color.clear.frame(width: 34 + menuPad, height: 34).contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .frame(width: 34 + menuPad, height: 34)
        }
        .padding(.leading, 16)
        .padding(.trailing, 0)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(sel ? NT.secondaryContainer : NT.bg)
        .contentShape(Rectangle())
        .onTapGesture { m.tap(e) }
        .onLongPressGesture(minimumDuration: 0.5) { m.copyEntry(e) }
        .contextMenu {
            Button(pinLabel) { m.togglePin(targets) }
            Button(L("Düzenle", "Edit")) { m.beginRename(e) }
            Button(L("Taşı", "Move")) { m.beginMove(targets) }
            Button(L("Paylaş", "Share")) { m.shareEntries(targets) }
            Button(L("Sil", "Delete")) { m.deleteNow(targets) }
        }
    }
}
