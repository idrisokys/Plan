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
        case "Tags":
            tagsSection
                .onDrop(of: [.text], delegate: sectionDelegate("Tags"))
        default:
            section("Favorites", favorites, isFavorites: true)
                .onDrop(of: [.text, .fileURL], delegate: sectionDelegate("Favorites", urls: true))
        }
    }

    @State private var tick = 0

    private var devices: [Place] {
        _ = tick
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsInternalKey]
        let vols = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return vols.map { url in
            let v = try? url.resourceValues(forKeys: Set(keys))
            let name = url.path == "/" ? FileManager.default.displayName(atPath: "/") : (v?.volumeName ?? url.lastPathComponent)
            return Place(name: name, icon: (v?.volumeIsInternal ?? true) ? "internaldrive" : "externaldrive", url: url)
        }
    }

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

    private func section(_ title: String, _ places: [Place], ejectable: Bool = false, isFavorites: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2 * s) {
            sectionHeader(title)
            ForEach(isCollapsed(title) ? [] : places) { p in
                let pane = app.active
                let on = pane.tagFilter == nil
                    && pane.currentURL.standardizedFileURL.path == p.url.standardizedFileURL.path
                HStack(spacing: 8 * s) {
                    Image(systemName: p.icon)
                        .font(.system(size: 12.5 * s))
                        .foregroundStyle(Color.filetor)
                        .frame(width: 20 * s)
                    Text(p.name)
                        .font(.system(size: 13 * s))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if ejectable && p.url.path != "/" {
                        Button { app.eject(p.url) } label: {
                            Image(systemName: "eject.fill")
                                .font(.system(size: 10 * s))
                                .foregroundStyle(Color.primary.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                        .help("Eject")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, (isFavorites ? 9 : 5) * s)
                .background(RoundedRectangle(cornerRadius: 7).fill(on ? Color.primary.opacity(0.09) : Color.clear))
                .contentShape(Rectangle())
                .onTapGesture {
                    app.active.navigate(to: p.url)
                }
                .modifier(FavoriteRowModifier(enabled: isFavorites, url: p.url, app: app, dragging: $draggingFavorite,
                                              card: dragCard(p.name), onDragStart: watchDragEnd))
            }
        }
    }

    private func tagCircle(_ color: NSColor?) -> some View {
        Group {
            if let color {
                Circle().fill(Color(nsColor: color))
            } else {
                Circle().strokeBorder(Color.primary.opacity(0.45), lineWidth: 1.4)
            }
        }
        .frame(width: 10.5 * s, height: 10.5 * s)
    }

    private var searchesSection: some View {
        let store = SavedSearchStore.shared
        return VStack(alignment: .leading, spacing: 2 * s) {
            sectionHeader("Searches")
            if !isCollapsed("Searches") {
                HStack(spacing: 8 * s) {
                    Image(systemName: "plus")
                        .font(.system(size: 12.5 * s))
                        .foregroundStyle(Color.filetor)
                        .frame(width: 20 * s)
                    Text("New Saved Search…").font(.system(size: 13 * s))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5 * s)
                .contentShape(Rectangle())
                .onTapGesture { app.savedSearchDialog = SavedSearch(folder: app.active.currentURL.path) }
                ForEach(store.items) { search in
                    let on = app.active.savedSearchID == search.id
                    HStack(spacing: 8 * s) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12.5 * s))
                            .foregroundStyle(Color.filetor)
                            .frame(width: 20 * s)
                        Text(search.name)
                            .font(.system(size: 13 * s))
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5 * s)
                    .background(RoundedRectangle(cornerRadius: 7).fill(on ? Color.primary.opacity(0.09) : Color.clear))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if on {
                            app.active.clearTag()
                            app.active.load()
                        } else {
                            app.active.showSaved(search)
                        }
                    }
                    .contextMenu {
                        Button("Edit…") { app.savedSearchDialog = search }
                        Button("Remove from Sidebar") {
                            if on { app.active.clearTag(); app.active.load() }
                            store.remove(search.id)
                        }
                    }
                }
            }
        }
    }

    private var tagsSection: some View {
        let store = TagStore.shared
        return VStack(alignment: .leading, spacing: 2 * s) {
            sectionHeader("Tags")
            if !isCollapsed("Tags") {
                ForEach(store.all) { tag in
                    let on = app.active.tagFilter == tag.name && app.active.savedSearchID == nil
                    HStack(spacing: 8 * s) {
                        tagCircle(tag.color)
                            .frame(width: 20 * s)
                        Text(tag.name)
                            .font(.system(size: 13 * s))
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5 * s)
                    .background(RoundedRectangle(cornerRadius: 7).fill(on ? Color.primary.opacity(0.09) : Color.clear))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if on {
                            // Second click on the selected tag leaves the tag view.
                            app.active.clearTag()
                            app.active.load()
                        } else {
                            app.active.showTag(tag.name)
                        }
                    }
                    .contextMenu {
                        if tag.color == nil {
                            Button("Remove from Sidebar") { store.remove(tag.name) }
                        }
                    }
                }
            }
        }
    }


    private var shared: some View {
        VStack(alignment: .leading, spacing: 2 * s) {
            sectionHeader("Shared")
            if !isCollapsed("Shared") {
            HStack(spacing: 8 * s) {
                Image(systemName: "plus")
                    .font(.system(size: 12.5 * s))
                    .foregroundStyle(Color.filetor)
                    .frame(width: 20 * s)
                Text("Connect to Server").font(.system(size: 13 * s))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5 * s)
            .contentShape(Rectangle())
            .onTapGesture { app.showConnect = true }
            ForEach(app.network.servers) { server in
                HStack(spacing: 8 * s) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 12.5 * s))
                        .foregroundStyle(Color.filetor)
                        .frame(width: 20 * s)
                    Text(server.name).font(.system(size: 13 * s)).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5 * s)
                .contentShape(Rectangle())
                .help("Connect to \(server.name)")
                .onTapGesture { app.network.connect(server) }
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
