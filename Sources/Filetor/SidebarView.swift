import SwiftUI
import UniformTypeIdentifiers

struct Place: Identifiable, Hashable {
    let name: String
    let icon: String
    let url: URL
    var id: URL { url }
}

struct SidebarView: View {
    let app: AppModel
    @AppStorage("textSize") private var textSize = 1

    private var favorites: [Place] { app.favorites.urls.map { app.favorites.place(for: $0) } }

    @AppStorage("sidebarCollapsed") private var collapsedRaw = ""

    private func isCollapsed(_ title: String) -> Bool { collapsedRaw.split(separator: ",").contains(Substring(title)) }

    private func toggleCollapsed(_ title: String) {
        var set = Set(collapsedRaw.split(separator: ",").map(String.init))
        if set.contains(title) { set.remove(title) } else { set.insert(title) }
        collapsedRaw = set.joined(separator: ",")
    }

    @AppStorage("sidebarOrder") private var orderRaw = "Cloud,Favorites"
    @State private var draggingSection: String?
    /// Order while dragging; a plain @State so moves animate (the saved order follows).
    @State private var liveOrder: [String]?
    @State private var draggingFavorite: URL?

    private static let allSections = ["Cloud", "Favorites"]

    /// Saved section order; unknown names are dropped and missing ones appended.
    private var order: [String] {
        if let liveOrder { return liveOrder }
        var out: [String] = []
        for t in orderRaw.split(separator: ",").map(String.init) where Self.allSections.contains(t) && !out.contains(t) { out.append(t) }
        for t in Self.allSections where !out.contains(t) { out.append(t) }
        return out
    }

    /// Moves a section to the position of `target` (below it when dragged downwards, above it when dragged upwards).
    private func moveSection(_ title: String, onto target: String) {
        var o = order
        guard let from = o.firstIndex(of: title), let to = o.firstIndex(of: target), from != to else { return }
        o.remove(at: from)
        o.insert(title, at: to)
        liveOrder = o
        orderRaw = o.joined(separator: ",")
    }

    /// Clears the drag state once the mouse button is released, also when the drag is cancelled.
    private func watchDragEnd() {
        Task { @MainActor in
            while NSEvent.pressedMouseButtons != 0 { try? await Task.sleep(for: .milliseconds(100)) }
            try? await Task.sleep(for: .milliseconds(150))
            draggingSection = nil
            draggingFavorite = nil
        }
    }

    private func dragCard(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13 * s, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8 * s)
            .frame(width: 200 * s, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(.regularMaterial))
    }

    private func sectionDelegate(_ title: String, urls: Bool = false) -> SectionDropDelegate {
        SectionDropDelegate(
            title: title,
            dragging: $draggingSection,
            draggingFavorite: draggingFavorite,
            acceptsURLs: urls,
            move: { from, to in moveSection(from, onto: to) },
            favorites: app.favorites
        )
    }

    @ViewBuilder private func sectionView(_ title: String) -> some View {
        switch title {
        case "Cloud":
            if !cloud.isEmpty {
                section("Cloud", cloud)
                    .onDrop(of: [.text], delegate: sectionDelegate("Cloud"))
            }
        default:
            // Searches always stay directly below Favorites, so they move together with it.
            VStack(alignment: .leading, spacing: 14 * s) {
                section("Favorites", favorites, isFavorites: true)
                    .onDrop(of: [.text, .fileURL], delegate: sectionDelegate("Favorites", urls: true))
                searchesSection
            }
        }
    }

    @State private var tick = 0

    /// iCloud Drive and cloud providers (Google Drive, Dropbox, OneDrive) that exist on this Mac.
    private var cloud: [Place] {
        _ = tick
        return CloudLocation.all().map { Place(name: $0.name, icon: $0.icon, url: $0.url) }
    }

    private var s: CGFloat { UIScale.value(textSize) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14 * s) {
                ForEach(order, id: \.self) { title in
                    sectionView(title)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .background(Color.primary.opacity(0.04))
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in tick += 1 }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in tick += 1 }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 11.5 * s, weight: .semibold))
            Image(systemName: isCollapsed(title) ? "chevron.right" : "chevron.down")
                .font(.system(size: 8 * s, weight: .bold))
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.primary.opacity(0.4))
        .padding(.horizontal, 8)
        .padding(.bottom, 2 * s)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { toggleCollapsed(title) } }
        .onDrag {
            draggingSection = title
            watchDragEnd()
            return NSItemProvider(object: title as NSString)
        } preview: {
            dragCard(title)
        }
    }

    /// One sidebar row: icon, name, highlight when selected. Callers add tap and menu behaviour.
    private func row(icon: String, title: String, selected: Bool, vertical: CGFloat = 5) -> some View {
        HStack(spacing: 8 * s) {
            Image(systemName: icon)
                .font(.system(size: 12.5 * s))
                .foregroundStyle(Color.filetor)
                .frame(width: 20 * s)
            Text(title)
                .font(.system(size: 13 * s))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, vertical * s)
        .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Color.primary.opacity(0.09) : Color.clear))
        .contentShape(Rectangle())
    }

    private func section(_ title: String, _ places: [Place], isFavorites: Bool = false) -> some View {
        let pane = app.active
        let current = pane.currentURL.standardizedFileURL.path
        let browsingFolders = pane.tagFilter == nil
        return VStack(alignment: .leading, spacing: 2 * s) {
            sectionHeader(title)
            ForEach(isCollapsed(title) ? [] : places) { p in
                row(icon: p.icon, title: p.name,
                    selected: browsingFolders && current == p.url.standardizedFileURL.path,
                    vertical: isFavorites ? 9 : 5)
                    .onTapGesture { pane.navigate(to: p.url) }
                    .modifier(FavoriteRowModifier(enabled: isFavorites, url: p.url, app: app, dragging: $draggingFavorite,
                                                  card: dragCard(p.name), onDragStart: watchDragEnd))
            }
        }
    }

    /// Saved searches, shown under Favorites.
    private var searchesSection: some View {
        let store = SavedSearchStore.shared
        let pane = app.active
        return VStack(alignment: .leading, spacing: 2 * s) {
            sectionHeader("Searches")
            if !isCollapsed("Searches") {
                row(icon: "plus", title: "New Saved Search…", selected: false)
                    .onTapGesture { app.savedSearchDialog = SavedSearch(folder: pane.currentURL.path) }
                ForEach(store.items) { search in
                    let on = pane.savedSearchID == search.id
                    row(icon: "magnifyingglass", title: search.name, selected: on)
                        .onTapGesture {
                            if on {
                                pane.clearTag()
                                pane.load()
                            } else {
                                pane.showSaved(search)
                            }
                        }
                        .contextMenu {
                            Button("Edit…") { app.savedSearchDialog = search }
                            Button("Remove from Sidebar") {
                                if on { pane.clearTag(); pane.load() }
                                store.remove(search.id)
                            }
                        }
                }
            }
        }
    }
}

/// Drag to reorder (live, with animation), drop folders to add, right-click to remove (Favorites only).
struct FavoriteRowModifier<Card: View>: ViewModifier {
    let enabled: Bool
    let url: URL
    let app: AppModel
    @Binding var dragging: URL?
    let card: Card
    let onDragStart: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content
                .onDrag {
                    dragging = url
                    onDragStart()
                    return NSItemProvider(object: url as NSURL)
                } preview: {
                    card
                }
                .onDrop(of: [.fileURL], delegate: FavoriteRowDropDelegate(url: url, dragging: $dragging, app: app))
                .contextMenu {
                    Button("Remove from Favorites") { app.favorites.remove(url) }
                }
        } else {
            content
        }
    }
}

/// Reads file URLs from a drop and hands each one over on the main actor.
@MainActor
func addDroppedURLs(_ info: DropInfo, to store: FavoritesStore, before: URL?) {
    for provider in info.itemProviders(for: [.fileURL]) {
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in store.insert([url], before: before) }
        }
    }
}

/// Dropping on a Favorites row: a favorite being dragged slides into place (reorder);
/// any other files or folders are moved into that favorite folder.
struct FavoriteRowDropDelegate: DropDelegate {
    let url: URL
    @Binding var dragging: URL?
    let app: AppModel

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.fileURL]) }

    func dropEntered(info: DropInfo) {
        guard let d = dragging, d != url else { return }
        withAnimation(.easeInOut(duration: 0.22)) { app.favorites.move(d, onto: url) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        if dragging != nil { dragging = nil; return true }
        let dest = url
        for provider in info.itemProviders(for: [.fileURL]) {
            _ = provider.loadObject(ofClass: URL.self) { file, _ in
                guard let file else { return }
                // A folder cannot be moved into itself or into one of its own subfolders.
                guard !(dest.path + "/").hasPrefix(file.path + "/") else { return }
                Task { @MainActor in app.dropTransfer([file], into: dest, move: true) }
            }
        }
        return true
    }
}

/// Dropping on a sidebar section: a dragged section slides into place (move cursor);
/// on Favorites, folders from a file list are added at the end.
struct SectionDropDelegate: DropDelegate {
    let title: String
    @Binding var dragging: String?
    let draggingFavorite: URL?
    let acceptsURLs: Bool
    let move: (String, String) -> Void
    let favorites: FavoritesStore

    func validateDrop(info: DropInfo) -> Bool {
        dragging != nil || (acceptsURLs && info.hasItemsConforming(to: [.fileURL]))
    }

    func dropEntered(info: DropInfo) {
        guard let d = dragging, d != title else { return }
        withAnimation(.easeInOut(duration: 0.22)) { move(d, title) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: (dragging != nil || draggingFavorite != nil) ? .move : .copy)
    }

    func performDrop(info: DropInfo) -> Bool {
        if dragging != nil { dragging = nil; return true }
        if draggingFavorite != nil { return true }
        guard acceptsURLs else { return false }
        addDroppedURLs(info, to: favorites, before: nil)
        return true
    }
}
