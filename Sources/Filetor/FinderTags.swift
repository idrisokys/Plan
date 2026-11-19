import SwiftUI
import AppKit
import Observation

/// A tag shown in the sidebar and in the Tags menu. Standard tags have a colour, named tags (#project) have none.
struct TagInfo: Identifiable, Hashable {
    let name: String
    let color: NSColor?
    var id: String { name }
}

/// Standard Finder tags and the named tags Filetor knows about (created here or seen on files in opened folders).
@Observable
final class TagStore {
    static let shared = TagStore()

    /// Finder label numbers in menu order: Red, Orange, Yellow, Green, Blue, Purple, Gray.
    private static let order = [6, 7, 5, 2, 4, 3, 1]
    private static let english = ["", "Gray", "Green", "Purple", "Blue", "Yellow", "Red", "Orange"]
    private static let colors: [NSColor] = [
        .clear, rgb(0x8e8e93), rgb(0x34c759), rgb(0xaf52de), rgb(0x0683ff), rgb(0xffcc00), rgb(0xff3b30), rgb(0xf97316),
    ]

    private static func rgb(_ hex: Int) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }

    let standard: [TagInfo]
    private(set) var custom: [String]
    @ObservationIgnored private var removed: Set<String>

    private init() {
        let labels = NSWorkspace.shared.fileLabels
        standard = Self.order.map { n in
            TagInfo(name: n < labels.count ? labels[n] : Self.english[n], color: Self.colors[n])
        }
        custom = UserDefaults.standard.stringArray(forKey: "tags.custom") ?? []
        removed = Set(UserDefaults.standard.stringArray(forKey: "tags.removed") ?? [])
    }

    var all: [TagInfo] { standard + custom.map { TagInfo(name: $0, color: nil) } }

    /// Label number 1...7 of a standard tag name (localized or English), nil for any other name.
    private func label(for name: String) -> Int? {
        let labels = NSWorkspace.shared.fileLabels
        for n in 1...7 {
            if name.caseInsensitiveCompare(Self.english[n]) == .orderedSame { return n }
            if n < labels.count, name.caseInsensitiveCompare(labels[n]) == .orderedSame { return n }
        }
        return nil
    }

    func color(for name: String) -> NSColor? { label(for: name).map { Self.colors[$0] } }
    func isStandard(_ name: String) -> Bool { label(for: name) != nil }

    /// Names a tag can have on disk: the localized name and the English one for standard tags.
    func aliases(of name: String) -> [String] {
        guard let n = label(for: name) else { return [name] }
        let labels = NSWorkspace.shared.fileLabels
        var out = [name]
        for c in [Self.english[n], n < labels.count ? labels[n] : ""] where !c.isEmpty && !out.contains(c) { out.append(c) }
        return out
    }

    /// True when a tag found on a file is the tag called `name`.
    func matches(_ fileTag: String, _ name: String) -> Bool {
        aliases(of: name).contains { $0.caseInsensitiveCompare(fileTag) == .orderedSame }
    }

    /// Adds named tags seen on files, except those the user removed from the sidebar.
    func remember(_ names: [String]) {
        var added = false
        for n in names where !n.isEmpty && !custom.contains(n) && !removed.contains(n) && !isStandard(n) {
            custom.append(n)
            added = true
        }
        if added { save() }
    }

    func add(_ name: String) {
        removed.remove(name)
        if !isStandard(name), !custom.contains(name) { custom.append(name) }
        save()
    }

    func remove(_ name: String) {
        custom.removeAll { $0 == name }
        removed.insert(name)
        save()
    }

    private func save() {
        UserDefaults.standard.set(custom, forKey: "tags.custom")
        UserDefaults.standard.set(Array(removed), forKey: "tags.removed")
    }
}

enum FinderTags {
    nonisolated static func read(_ url: URL) -> [String] {
        // A fresh URL: the one from the file list carries cached (old) tag values.
        (try? URL(fileURLWithPath: url.path).resourceValues(forKeys: [.tagNamesKey]))?.tagNames ?? []
    }

    /// Returns an error text, or nil when the tags were written.
    nonisolated static func write(_ tags: [String], to url: URL) -> String? {
        do {
            // NSURL works on every macOS version; the Swift setter for tagNames needs macOS 26.
            try (URL(fileURLWithPath: url.path) as NSURL).setResourceValue(tags as NSArray, forKey: .tagNamesKey)
            return nil
        } catch {
            return "\(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    /// Menu title with a coloured circle in front (filled for standard tags, hollow for named tags).
    /// Drawn as text because menu item images are not shown reliably.
    static func menuTitle(_ name: String, color: NSColor?) -> NSAttributedString {
        let font = NSFont.menuFont(ofSize: 0)
        let out = NSMutableAttributedString(
            string: color == nil ? "○" : "●",
            attributes: [.foregroundColor: color ?? NSColor.secondaryLabelColor, .font: font])
        out.append(NSAttributedString(string: "  " + name, attributes: [.font: font]))
        return out
    }
}

/// Finds every file with a tag through Spotlight.
enum TagQuery {
    static func run(_ name: String) async -> [URL] {
        let clauses = TagStore.shared.aliases(of: name).map { "kMDItemUserTags == \"\(SavedSearch.escape($0))\"c" }
        return await SpotlightSearch.run(clauses.joined(separator: " || "), onlyIn: "")
    }
}

extension TagQuery {
    /// Looks through a folder (and everything in it) for files with the tag. Slow, used where Spotlight has no index.
    static func scan(_ name: String, root: URL) async -> [URL] {
        let names = TagStore.shared.aliases(of: name)
        let task = Task.detached(priority: .utility) { scanFolder(names, root) }
        return await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }

    nonisolated private static func scanFolder(_ names: [String], _ root: URL) -> [URL] {
        guard let en = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.tagNamesKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var out: [URL] = []
        var visited = 0
        while let url = en.nextObject() as? URL {
            if Task.isCancelled { break }
            visited += 1
            if visited > 100_000 { break }
            let tags = (try? url.resourceValues(forKeys: [.tagNamesKey]))?.tagNames ?? []
            if tags.contains(where: { t in names.contains { $0.caseInsensitiveCompare(t) == .orderedSame } }) {
                out.append(url)
                if out.count >= 3000 { break }
            }
        }
        return out
    }
}

/// Coloured circles of the standard tags, overlapping slightly like in Finder.
final class TagDotsView: NSView {
    private let colors: [NSColor]
    private let d: CGFloat
    private let step: CGFloat

    init(colors: [NSColor], scale s: CGFloat) {
        self.colors = colors
        d = 10 * s
        step = 7 * s
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    var contentWidth: CGFloat { d + step * CGFloat(max(colors.count - 1, 0)) }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let y = (bounds.height - d) / 2
        for (i, c) in colors.enumerated() {
            c.setFill()
            NSBezierPath(ovalIn: NSRect(x: CGFloat(i) * step, y: y, width: d, height: d)).fill()
        }
    }
}

// MARK: - Changing tags

/// What to do with the tags of the selected files.
nonisolated enum TagChange: Sendable {
    /// Add the tag, or remove it when every file already has it.
    case toggle(aliases: [String], name: String)
    case add(aliases: [String], name: String)
    case removeAll
}

nonisolated struct TagResult: Sendable {
    var before: [URL: [String]]
    var after: [URL: [String]]
    var failed: [String]
}

extension FinderTags {
    nonisolated private static func has(_ tag: String, _ aliases: [String]) -> Bool {
        aliases.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
    }

    /// Reads and writes the tags. Runs in the background: on cloud drives (Google Drive) this can take a while.
    nonisolated static func apply(_ change: TagChange, to urls: [URL], known: [URL: [String]]) -> TagResult {
        var before: [URL: [String]] = [:]
        for u in urls { before[u] = known[u] ?? read(u) }
        var removing = false
        if case .toggle(let aliases, _) = change {
            removing = urls.allSatisfy { u in (before[u] ?? []).contains { has($0, aliases) } }
        }
        var after = before
        var failed: [String] = []
        for u in urls {
            let old = before[u] ?? []
            let new: [String]
            switch change {
            case .removeAll:
                new = []
            case .toggle(let aliases, let name):
                let kept = old.filter { !has($0, aliases) }
                new = removing ? kept : kept + [name]
            case .add(let aliases, let name):
                new = old.contains { has($0, aliases) } ? old : old + [name]
            }
            guard new != old else { continue }
            if let error = write(new, to: u) { failed.append(error) } else { after[u] = new }
        }
        return TagResult(before: before, after: after, failed: failed)
    }
}

extension AppModel {
    /// Adds the tag to every selected file, or removes it when all of them already have it.
    func toggleTag(_ name: String, on urls: Set<URL>) {
        applyTags(.toggle(aliases: TagStore.shared.aliases(of: name), name: name), to: urls)
    }

    func removeAllTags(_ urls: Set<URL>) {
        applyTags(.removeAll, to: urls)
    }

    func newTag(for urls: Set<URL>) {
        let dialog = NSAlert()
        dialog.messageText = "New Tag"
        dialog.informativeText = "Name of the tag, for example #project."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        dialog.accessoryView = field
        dialog.addButton(withTitle: "Add")
        dialog.addButton(withTitle: "Cancel")
        dialog.window.initialFirstResponder = field
        guard dialog.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        TagStore.shared.add(name)
        applyTags(.add(aliases: TagStore.shared.aliases(of: name), name: name), to: urls)
    }

    func reloadPanesKeepingSelection() {
        for g in groups { g.current.reloadKeepingSelection() }
    }

    /// Tags as shown in the lists now (no disk read, which is slow and unreliable on cloud drives).
    private func knownTags(_ urls: Set<URL>) -> [URL: [String]] {
        var out: [URL: [String]] = [:]
        for g in groups {
            for tab in g.tabs {
                for item in tab.items where urls.contains(item.url) { out[item.url] = item.tags }
                for item in tab.searchResults where urls.contains(item.url) { out[item.url] = item.tags }
                for item in tab.tagResults where urls.contains(item.url) { out[item.url] = item.tags }
            }
        }
        return out
    }

    private func applyTags(_ change: TagChange, to urls: Set<URL>) {
        let list = Array(urls)
        let known = knownTags(urls)
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { FinderTags.apply(change, to: list, known: known) }.value
            guard let self else { return }
            TagStore.shared.remember(result.after.values.flatMap { $0 })
            if result.before != result.after {
                let restore: ([URL: [String]]) -> String? = { map in
                    var errors: [String] = []
                    for (u, t) in map { if let e = FinderTags.write(t, to: u) { errors.append(e) } }
                    return errors.first
                }
                let before = result.before
                let after = result.after
                self.pushUndo("Tags", undo: { restore(before) }, redo: { [weak self] in
                    let error = restore(after)
                    self?.reloadPanesKeepingSelection()
                    return error
                })
            }
            // Update the lists in place instead of re-reading the folders (slow on cloud drives).
            for g in self.groups { for tab in g.tabs { tab.applyTagChanges(result.after) } }
            if !result.failed.isEmpty { self.alert = result.failed.prefix(3).joined(separator: "\n") }
        }
    }
}
