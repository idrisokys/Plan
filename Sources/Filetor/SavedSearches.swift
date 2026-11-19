import SwiftUI
import Observation

/// File groups offered in a saved search. Design and Documents are lists of extensions, the others use Spotlight types.
nonisolated enum SearchGroup {
    static let all: [(key: String, title: String)] = [
        ("images", "Images"), ("design", "Design"), ("pdf", "PDF"),
        ("documents", "Documents"), ("video", "Video"), ("folders", "Folders"),
    ]
    static let designExtensions = ["psd", "psb", "ai", "eps", "svg", "fig", "sketch", "indd", "xd"]
    static let documentExtensions = ["doc", "docx", "pages", "txt", "rtf", "odt", "xls", "xlsx", "numbers", "csv",
                                     "ppt", "pptx", "key", "md"]

    static func extensionClauses(_ list: [String]) -> String {
        list.map { "kMDItemFSName == \"*.\($0)\"c" }.joined(separator: " || ")
    }

    static func clause(_ key: String) -> String? {
        switch key {
        case "images": return "kMDItemContentTypeTree == \"public.image\"c"
        case "pdf": return "kMDItemContentType == \"com.adobe.pdf\"c"
        case "video": return "kMDItemContentTypeTree == \"public.movie\"c"
        case "folders": return "kMDItemContentType == \"public.folder\"c"
        case "design": return extensionClauses(designExtensions)
        case "documents": return extensionClauses(documentExtensions)
        default: return nil
        }
    }
}

/// A search that is kept in the sidebar and run through Spotlight whenever it is opened.
nonisolated struct SavedSearch: Codable, Identifiable, Hashable {
    var id = UUID()
    var name = ""
    /// Folder to search in; empty means the whole Mac.
    var folder = ""
    var nameContains = ""
    var groups: [String] = []
    /// File extensions as typed, for example "psd, ai, svg".
    var extensions = ""
    /// Changed in the last N days; 0 means any time.
    var days = 0
    /// Tag name; empty means any.
    var tag = ""

    var extensionList: [String] {
        extensions.split(whereSeparator: { ", ;".contains($0) })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased() }
            .filter { !$0.isEmpty }
    }

    var isEmpty: Bool {
        nameContains.trimmingCharacters(in: .whitespaces).isEmpty && groups.isEmpty && extensionList.isEmpty
            && days == 0 && tag.isEmpty
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Spotlight query text. `tagAliases` are the names the chosen tag can have on disk.
    func query(tagAliases: [String]) -> String {
        var parts: [String] = []
        let n = nameContains.trimmingCharacters(in: .whitespaces)
        if !n.isEmpty { parts.append("kMDItemFSName == \"*\(Self.escape(n))*\"cd") }
        var kinds = groups.compactMap { SearchGroup.clause($0) }
        if !extensionList.isEmpty { kinds.append(SearchGroup.extensionClauses(extensionList)) }
        if !kinds.isEmpty { parts.append("(" + kinds.joined(separator: " || ") + ")") }
        if days > 0 { parts.append("kMDItemFSContentChangeDate >= $time.today(-\(days))") }
        if !tagAliases.isEmpty {
            parts.append("(" + tagAliases.map { "kMDItemUserTags == \"\(Self.escape($0))\"c" }.joined(separator: " || ") + ")")
        }
        return parts.map { "(\($0))" }.joined(separator: " && ")
    }

    /// Name used when the user leaves the name empty.
    var suggestedName: String {
        var bits: [String] = []
        let n = nameContains.trimmingCharacters(in: .whitespaces)
        if !n.isEmpty { bits.append(n) }
        for g in SearchGroup.all where groups.contains(g.key) { bits.append(g.title) }
        bits.append(contentsOf: extensionList)
        if days > 0 { bits.append(days == 365 ? "1 year" : "\(days) days") }
        if !tag.isEmpty { bits.append(tag) }
        return bits.isEmpty ? "Saved Search" : bits.joined(separator: ", ")
    }
}

extension SavedSearch {
    @MainActor func makeQuery() -> String {
        query(tagAliases: tag.isEmpty ? [] : TagStore.shared.aliases(of: tag))
    }
}

/// Runs a Spotlight query with mdfind in the background.
enum SpotlightSearch {
    static func run(_ query: String, onlyIn folder: String) async -> [URL] {
        await Task.detached(priority: .userInitiated) { search(query, folder) }.value
    }

    nonisolated private static func search(_ query: String, _ folder: String) -> [URL] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["-0"] + (folder.isEmpty ? [] : ["-onlyin", folder]) + [query]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return data.split(separator: 0).prefix(3000).compactMap { chunk in
            String(data: Data(chunk), encoding: .utf8).map { URL(fileURLWithPath: $0) }
        }
    }
}

@Observable
final class SavedSearchStore {
    static let shared = SavedSearchStore()
    private static let key = "savedSearches.v1"

    private(set) var items: [SavedSearch]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([SavedSearch].self, from: data) {
            items = saved
        } else {
            items = []
        }
    }

    func item(_ id: UUID) -> SavedSearch? { items.first { $0.id == id } }

    func save(_ search: SavedSearch) {
        if let i = items.firstIndex(where: { $0.id == search.id }) { items[i] = search } else { items.append(search) }
        persist()
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}

// MARK: - Dialog

private struct FolderChoice: Hashable {
    let title: String
    let path: String
}

/// Buttons side by side at their own width; a button that does not fit moves to the next row.
private struct ChipFlow: Layout {
    var spacing: CGFloat

    private func rows(_ subviews: Subviews, width: CGFloat) -> [[Int]] {
        var rows: [[Int]] = [[]]
        var x: CGFloat = 0
        for i in subviews.indices {
            let w = subviews[i].sizeThatFits(.unspecified).width
            if x > 0, x + w > width { rows.append([]); x = 0 }
            rows[rows.count - 1].append(i)
            x += w + spacing
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rs = rows(subviews, width: width)
        var height: CGFloat = 0
        var maxW: CGFloat = 0
        for r in rs {
            let hs = r.map { subviews[$0].sizeThatFits(.unspecified).height }
            height += (hs.max() ?? 0)
            maxW = max(maxW, r.map { subviews[$0].sizeThatFits(.unspecified).width }.reduce(0, +) + spacing * CGFloat(max(r.count - 1, 0)))
        }
        height += spacing * CGFloat(max(rs.count - 1, 0))
        return CGSize(width: proposal.width ?? maxW, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for r in rows(subviews, width: bounds.width) {
            var x = bounds.minX
            var rowHeight: CGFloat = 0
            for i in r {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
                x += size.width + spacing
                rowHeight = max(rowHeight, size.height)
            }
            y += rowHeight + spacing
        }
    }
}

/// Toggle button of the Kind row: accent text and border when on.
private struct ChipToggle: View {
    let title: String
    @Binding var isOn: Bool
    let scale: CGFloat

    var body: some View {
        Text(title)
            .foregroundStyle(isOn ? Color.filetor : Color.primary)
            .padding(.horizontal, 12 * scale)
            .padding(.vertical, 5 * scale)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(isOn ? Color.filetor : Color.primary.opacity(0.18)))
            .contentShape(Rectangle())
            .onTapGesture { isOn.toggle() }
    }
}

struct SavedSearchSheet: View {
    let app: AppModel
    @Environment(\.closePanel) private var dismiss
    @AppStorage("textSize") private var textSize = 1
    @State private var draft: SavedSearch
    @State private var count = ""

    init(app: AppModel, initial: SavedSearch) {
        self.app = app
        _draft = State(initialValue: initial)
    }

    private var s: CGFloat { UIScale.value(textSize) }
    private static let dayValues = [0, 7, 30, 365]
    private var isEditing: Bool { SavedSearchStore.shared.item(draft.id) != nil }
    private var liveQuery: String { draft.isEmpty ? "" : draft.makeQuery() }

    private var folderChoices: [FolderChoice] {
        var out = [FolderChoice(title: "This Mac", path: "")]
        var seen: Set<String> = [""]
        for p in [draft.folder] + app.favorites.urls.map(\.path) where !p.isEmpty && !seen.contains(p) {
            seen.insert(p)
            out.append(FolderChoice(title: p == "/" ? "Macintosh HD" : URL(fileURLWithPath: p).lastPathComponent, path: p))
        }
        return out
    }

    private func row<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 12) {
            Text(label).foregroundStyle(.secondary).frame(width: 110 * s, alignment: .leading)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func groupBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { draft.groups.contains(key) },
            set: { on in
                if on { if !draft.groups.contains(key) { draft.groups.append(key) } } else { draft.groups.removeAll { $0 == key } }
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isEditing ? "Edit Saved Search" : "New Saved Search").font(.system(size: 22 * s))

            row("Name") {
                TextField(draft.suggestedName, text: $draft.name).textFieldStyle(PathsTextFieldStyle(scale: s))
            }
            row("Search in") {
                Picker("", selection: $draft.folder) {
                    ForEach(folderChoices, id: \.self) { Text($0.title).tag($0.path) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            row("Name contains") {
                TextField("", text: $draft.nameContains).textFieldStyle(PathsTextFieldStyle(scale: s))
            }
            row("Kind") {
                ChipFlow(spacing: 6) {
                    ForEach(SearchGroup.all, id: \.key) { g in
                        ChipToggle(title: g.title, isOn: groupBinding(g.key), scale: s)
                    }
                }
            }
            row("Extensions") {
                TextField("psd, ai, svg", text: $draft.extensions).textFieldStyle(PathsTextFieldStyle(scale: s))
            }
            row("Modified") {
                SegmentedChoice(options: ["Any", "7 days", "30 days", "1 year"],
                                selection: Binding(
                                    get: { Self.dayValues.firstIndex(of: draft.days) ?? 0 },
                                    set: { draft.days = Self.dayValues[$0] }),
                                scale: s, accent: true)
            }
            row("Tag") {
                Picker("", selection: $draft.tag) {
                    Text("Any").tag("")
                    ForEach(TagStore.shared.all) { Text($0.name).tag($0.name) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }

            Text(draft.isEmpty ? "Set at least one condition." : count)
                .font(.system(size: 12 * s)).foregroundStyle(.secondary)
                .padding(.leading, 122 * s)

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(PathsButtonStyle(scale: s))
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    var result = draft
                    let typed = result.name.trimmingCharacters(in: .whitespaces)
                    result.name = typed.isEmpty ? result.suggestedName : typed
                    SavedSearchStore.shared.save(result)
                    app.active.showSaved(result)
                    dismiss()
                }
                .buttonStyle(PathsButtonStyle(scale: s, prominent: true))
                .keyboardShortcut(.defaultAction)
                .disabled(draft.isEmpty)
            }
        }
        .font(.system(size: 13 * s))
        .padding(28)
        .frame(width: 560 * s)
        .task(id: liveQuery + "|" + draft.folder) {
            guard !draft.isEmpty else { count = ""; return }
            count = "Searching…"
            try? await Task.sleep(for: .milliseconds(450))
            if Task.isCancelled { return }
            let urls = await SpotlightSearch.run(liveQuery, onlyIn: draft.folder)
            if Task.isCancelled { return }
            count = urls.count >= 3000 ? "3000+ items found now" : (urls.count == 1 ? "1 item found now" : "\(urls.count) items found now")
        }
    }
}
