import SwiftUI
import Observation

@Observable
final class PaneModel: Identifiable {
    let id = UUID()
    var currentURL: URL = FileManager.default.homeDirectoryForCurrentUser
    var items: [FileItem] = []
    var selection = Set<URL>()
    var sortOrder: [KeyPathComparator<FileItem>] = [
        KeyPathComparator(\FileItem.name, comparator: .localizedStandard)
    ]
    var errorMessage: String?
    var filter = "" { didSet { if searchSubfolders { restartSearch() } } }
    /// Search the filter text in all subfolders instead of only filtering the current folder.
    var searchSubfolders = UserDefaults.standard.bool(forKey: "searchSubfolders") {
        didSet {
            UserDefaults.standard.set(searchSubfolders, forKey: "searchSubfolders")
            restartSearch()
        }
    }
    var searchResults: [FileItem] = []
    var searching = false
    var foldersScanned = 0
    /// Name of the tag whose files are shown (a Spotlight search over the whole Mac), nil in a normal folder.
    var tagFilter: String?
    /// Set when the list shows a saved search (tagFilter then holds its name).
    var savedSearchID: UUID?
    var tagResults: [FileItem] = []
    var tagSearching = false
    @ObservationIgnored private var tagTask: Task<Void, Never>?
    var title: String { tagFilter ?? CloudLocation.title(for: currentURL) }
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    var searchActive: Bool { tagFilter == nil && searchSubfolders && !filter.isEmpty }
    /// 0 = list, 1 = icons, 2 = columns (columns not built yet, shows the list)
    var viewMode = 0
    var showHidden = UserDefaults.standard.bool(forKey: "showHidden")

    private var backStack: [URL] = []
    private var forwardStack: [URL] = []

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }
    var canGoUp: Bool { currentURL.path != "/" }

    var sortedItems: [FileItem] {
        let visible: [FileItem]
        if tagFilter != nil {
            visible = filter.isEmpty ? tagResults : tagResults.filter { $0.name.localizedCaseInsensitiveContains(filter) }
        } else {
            visible = searchActive ? searchResults
                : filter.isEmpty ? items : items.filter { $0.name.localizedCaseInsensitiveContains(filter) }
        }
        let sorted = visible.sorted(using: sortOrder)
        let foldersFirst = UserDefaults.standard.object(forKey: "foldersFirst") as? Bool ?? true
        guard foldersFirst else { return sorted }
        return sorted.filter { $0.isDirectory } + sorted.filter { !$0.isDirectory }
    }

    init(url: URL? = nil) {
        if let url { currentURL = url }
        load()
    }

    func navigate(to url: URL) {
        let target = url.standardizedFileURL
        if tagFilter != nil {
            clearTag()
            if target == currentURL { load(); return }
        }
        guard target != currentURL else { return }
        backStack.append(currentURL)
        forwardStack.removeAll()
        currentURL = target
        filter = ""
        load()
    }

    func goBack() {
        guard let prev = backStack.popLast() else { return }
        clearTag()
        forwardStack.append(currentURL)
        currentURL = prev
        load()
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        clearTag()
        backStack.append(currentURL)
        currentURL = next
        load()
    }

    func goUp() {
        guard canGoUp else { return }
        navigate(to: currentURL.deletingLastPathComponent())
    }

    func open(_ urls: Set<URL>) {
        for url in urls {
            let item = FileItem(url: url)
            if item.isDirectory {
                navigate(to: url)
                return
            } else if FileTools.isArchive(url) {
                extractArchive(url)
            } else {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// Double-clicking an archive extracts it next to itself, like Finder, then selects the new folder.
    func extractArchive(_ url: URL) {
        let dir = url.deletingLastPathComponent()
        Task { @MainActor [weak self] in
            let err = await Task.detached(priority: .userInitiated) {
                FileTools.decompress([url], in: dir)
            }.value
            guard let self else { return }
            self.reloadKeepingSelection()
            if let err {
                let alert = NSAlert()
                alert.messageText = "Could not extract \(url.lastPathComponent)"
                alert.informativeText = err
                alert.runModal()
            } else if dir.standardizedFileURL == self.currentURL.standardizedFileURL {
                // The new folder is the newest item named after the archive.
                let base = url.deletingPathExtension().lastPathComponent
                if let folder = self.items.filter({ $0.isDirectory && $0.name.hasPrefix(base) })
                    .max(by: { $0.name.count < $1.name.count || ($0.name.count == $1.name.count && $0.name < $1.name) }) {
                    self.selection = [folder.url]
                }
            }
        }
    }

    func toggleHidden() {
        showHidden.toggle()
        load()
    }

    func load() { reload(keepSelection: false) }

    /// Re-reads the folder after a change made outside the app, keeping the selection.
    private func refresh() { reload(keepSelection: true) }

    /// Re-reads the folder (and the tag view) after a change made in the app, keeping the selection.
    func reloadKeepingSelection() {
        reload(keepSelection: true)
        if tagFilter != nil { startTagQuery() }
    }

    // MARK: Tags

    /// Shows new tags on files without re-reading the folder.
    func applyTagChanges(_ map: [URL: [String]]) {
        for i in items.indices { if let t = map[items[i].url] { items[i].tags = t } }
        for i in searchResults.indices { if let t = map[searchResults[i].url] { searchResults[i].tags = t } }
        if tagFilter != nil {
            for i in tagResults.indices { if let t = map[tagResults[i].url] { tagResults[i].tags = t } }
        }
        if let f = tagFilter, savedSearchID == nil {
            let store = TagStore.shared
            tagResults.removeAll { item in map[item.url] != nil && !item.tags.contains { store.matches($0, f) } }
        }
        resyncSignature()
    }

    /// Takes the tag change as the new state, so the 2-second folder watcher does not reload the folder for it.
    private func resyncSignature() {
        let dir = currentURL
        let hidden = showHidden
        Task { [weak self] in
            let sig = await Task.detached(priority: .utility) { () -> Int? in
                guard let urls = try? FileManager.default.contentsOfDirectory(
                    at: dir,
                    includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .creationDateKey, .tagNamesKey],
                    options: hidden ? [] : [.skipsHiddenFiles]
                ) else { return nil }
                return Self.signature(of: urls)
            }.value
            guard let self, self.currentURL == dir, let sig else { return }
            self.lastSignature = sig
        }
    }

    func showSaved(_ search: SavedSearch) {
        savedSearchID = search.id
        tagFilter = search.name
        tagResults = []
        selection.removeAll()
        filter = ""
        startTagQuery()
    }

    func showTag(_ name: String) {
        savedSearchID = nil
        let onNetwork = (try? currentURL.resourceValues(forKeys: [.volumeIsLocalKey]))?.volumeIsLocal == false
        tagScanRoot = onNetwork ? currentURL : nil
        tagFilter = name
        tagResults = []
        selection.removeAll()
        filter = ""
        startTagQuery()
    }

    func clearTag() {
        tagTask?.cancel()
        tagFilter = nil
        savedSearchID = nil
        tagResults = []
        tagSearching = false
    }

    /// Folder to scan by hand when the tag view was opened on a network disk (Spotlight does not index those).
    @ObservationIgnored private var tagScanRoot: URL?

    private func startTagQuery() {
        tagTask?.cancel()
        guard let name = tagFilter else { return }
        tagSearching = true
        let saved = savedSearchID.flatMap { SavedSearchStore.shared.item($0) }
        let query = saved.map { $0.makeQuery() }
        let folder = saved?.folder ?? ""
        let scanRoot = saved == nil ? tagScanRoot : nil
        tagTask = Task { [weak self] in
            var urls: [URL]
            if let query { urls = await SpotlightSearch.run(query, onlyIn: folder) } else { urls = await TagQuery.run(name) }
            guard let self, !Task.isCancelled, self.tagFilter == name else { return }
            self.showTagResults(urls, finished: scanRoot == nil)
            guard let scanRoot else { return }
            let extra = await TagQuery.scan(name, root: scanRoot)
            guard !Task.isCancelled, self.tagFilter == name else { return }
            let known = Set(urls)
            urls += extra.filter { !known.contains($0) }
            self.showTagResults(urls, finished: true)
        }
    }

    private func showTagResults(_ urls: [URL], finished: Bool) {
        let home = NSHomeDirectory()
        tagResults = urls.map { url in
            var item = FileItem(url: url)
            var parent = url.deletingLastPathComponent().path
            if parent.hasPrefix(home) { parent = "~" + String(parent.dropFirst(home.count)) }
            item.folder = parent
            return item
        }
        if finished { tagSearching = false }
    }

    private func reload(keepSelection: Bool) {
        let previousSelection = selection
        var knownSizes: [URL: Int64] = [:]
        if keepSelection {
            for item in items where item.sizeCalculated { knownSizes[item.url] = item.size }
        } else {
            selection.removeAll()
        }
        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: currentURL,
                includingPropertiesForKeys: FileItem.keys,
                options: showHidden ? [] : [.skipsHiddenFiles]
            )
            items = urls.map { FileItem(url: $0) }
            TagStore.shared.remember(items.flatMap(\.tags))
            lastSignature = Self.signature(of: urls)
            errorMessage = nil
            if keepSelection {
                for i in items.indices {
                    if let size = knownSizes[items[i].url] {
                        items[i].size = size
                        items[i].sizeCalculated = true
                    }
                }
                let present = Set(items.map(\.url))
                selection = previousSelection.filter { present.contains($0) }
            }
        } catch {
            items = []
            errorMessage = error.localizedDescription
        }
        startFolderSizes()
        if !keepSelection { startWatching(); if searchActive { restartSearch() } }
    }

    // MARK: Search in subfolders

    func stopSearch() {
        searchTask?.cancel()
        searching = false
    }

    func restartSearch() {
        searchTask?.cancel()
        searchResults = []
        foldersScanned = 0
        guard searchActive else { searching = false; return }
        searching = true
        let root = currentURL.standardizedFileURL
        let query = filter
        let hidden = showHidden
        let stream = AsyncStream<SearchBatch> { cont in
            let worker = Task.detached(priority: .userInitiated) {
                Self.scan(root: root, query: query, hidden: hidden, into: cont)
                cont.finish()
            }
            cont.onTermination = { _ in worker.cancel() }
        }
        searchTask = Task { [weak self] in
            for await batch in stream {
                guard let self, !Task.isCancelled else { return }
                let rootPath = root.path
                self.searchResults.append(contentsOf: batch.urls.map { url in
                    var item = FileItem(url: url)
                    let parent = url.deletingLastPathComponent().path
                    item.folder = parent == rootPath ? "" : String(parent.dropFirst(rootPath.count + 1))
                    return item
                })
                self.foldersScanned = batch.folders
            }
            guard !Task.isCancelled else { return }
            self?.searching = false
        }
    }

    nonisolated private static func scan(root: URL, query: String, hidden: Bool, into cont: AsyncStream<SearchBatch>.Continuation) {
        var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !hidden { options.insert(.skipsHiddenFiles) }
        guard let en = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: options) else { return }
        var batch: [URL] = []
        var folders = 0
        var found = 0
        var last = Date()
        while let url = en.nextObject() as? URL {
            if Task.isCancelled { return }
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true { folders += 1 }
            if url.lastPathComponent.localizedCaseInsensitiveContains(query) {
                batch.append(url)
                found += 1
                if found >= 5000 { break }
            }
            if Date().timeIntervalSince(last) > 0.15 {
                cont.yield(SearchBatch(urls: batch, folders: folders))
                batch = []
                last = Date()
            }
        }
        cont.yield(SearchBatch(urls: batch, folders: folders))
    }

    // MARK: Watching the folder for changes made outside the app

    @ObservationIgnored private var watchTask: Task<Void, Never>?
    @ObservationIgnored private var lastSignature = 0

    /// Checks the current folder every 2 seconds (only while the app is active) and reloads it when a name,
    /// size, modified date or created date has changed.
    private func startWatching() {
        watchTask?.cancel()
        let dir = currentURL
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled, self.currentURL == dir else { return }
                guard NSApplication.shared.isActive else { continue }
                let hidden = self.showHidden
                let sig = await Task.detached(priority: .utility) { () -> Int? in
                    guard let urls = try? FileManager.default.contentsOfDirectory(
                        at: dir,
                        includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .creationDateKey, .tagNamesKey],
                        options: hidden ? [] : [.skipsHiddenFiles]
                    ) else { return nil }
                    return Self.signature(of: urls)
                }.value
                guard !Task.isCancelled, self.currentURL == dir else { return }
                if let sig, sig != self.lastSignature { self.refresh() }
            }
        }
    }

    nonisolated private static func signature(of urls: [URL]) -> Int {
        var hasher = Hasher()
        for url in urls.sorted(by: { $0.path < $1.path }) {
            let v = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .creationDateKey, .tagNamesKey])
            hasher.combine(url.path)
            hasher.combine(v?.contentModificationDate)
            hasher.combine(v?.fileSize)
            hasher.combine(v?.creationDate)
            hasher.combine(v?.tagNames)
        }
        return hasher.finalize()
    }

    @ObservationIgnored private var sizeTask: Task<Void, Never>?

    /// Calculates the total size of every folder in the background when "Calculate all folder sizes" is on.
    private func startFolderSizes() {
        sizeTask?.cancel()
        guard UserDefaults.standard.bool(forKey: "calculateFolderSizes") else { return }
        let folders = items.filter(\.isDirectory).map(\.url)
        guard !folders.isEmpty else { return }
        let dir = currentURL
        sizeTask = Task { [weak self] in
            for url in folders {
                if Task.isCancelled { return }
                let size = await Task.detached(priority: .utility) { FileTools.size(of: url) }.value
                if Task.isCancelled { return }
                guard let self, self.currentURL == dir,
                      let i = self.items.firstIndex(where: { $0.url == url }) else { continue }
                self.items[i].size = size
                self.items[i].sizeCalculated = true
            }
        }
    }
}

nonisolated struct SearchBatch: Sendable {
    var urls: [URL]
    var folders: Int
}
