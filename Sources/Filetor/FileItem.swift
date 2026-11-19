import Foundation

struct FileItem: Identifiable, Hashable {
    let url: URL
    let name: String
    let isDirectory: Bool
    var size: Int64
    /// True once the total size of a folder has been calculated.
    var sizeCalculated = false
    /// Folder of a recursive search result, relative to the searched folder (empty otherwise).
    var folder = ""
    let modified: Date
    let kind: String
    let created: Date
    let added: Date
    let lastOpened: Date
    /// Finder tag names (standard colour tags and named tags).
    var tags: [String]

    var id: URL { url }

    /// Tag names as one text, used for sorting the Tags column.
    var tagsText: String { tags.joined(separator: " ") }

    static let keys: [URLResourceKey] = [
        .isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .localizedTypeDescriptionKey,
        .creationDateKey, .addedToDirectoryDateKey, .contentAccessDateKey, .tagNamesKey
    ]

    init(url: URL) {
        let v = try? url.resourceValues(forKeys: Set(Self.keys))
        self.url = url
        self.name = url.lastPathComponent
        self.isDirectory = v?.isDirectory ?? false
        self.size = Int64(v?.fileSize ?? 0)
        self.modified = v?.contentModificationDate ?? .distantPast
        self.kind = v?.localizedTypeDescription ?? ""
        self.created = v?.creationDate ?? .distantPast
        self.added = v?.addedToDirectoryDate ?? .distantPast
        self.lastOpened = v?.contentAccessDate ?? .distantPast
        self.tags = v?.tagNames ?? []
    }
}
