import SwiftUI

extension FileTools {
    /// Number of files and total size of a folder.
    nonisolated static func stats(of folder: URL) -> (files: Int, bytes: Int64) {
        guard let en = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: []) else { return (0, 0) }
        var files = 0
        var bytes: Int64 = 0
        while let url = en.nextObject() as? URL {
            if Task.isCancelled { break }
            let v = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if v?.isRegularFile == true {
                files += 1
                bytes += Int64(v?.fileSize ?? 0)
            }
        }
        return (files, bytes)
    }

    /// Zips a folder to `dest` and tests the zip. On a failure the half-made zip is removed. Returns an error text, or nil.
    nonisolated static func archive(_ folder: URL, to dest: URL) -> String? {
        do {
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            return error.localizedDescription
        }
        if let err = run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", folder.path, dest.path]) {
            try? FileManager.default.removeItem(at: dest)
            return err
        }
        if let err = run("/usr/bin/unzip", ["-tqq", dest.path]) {
            try? FileManager.default.removeItem(at: dest)
            return "The archive did not pass its check and was removed. The original folder is untouched.\n\(err)"
        }
        return nil
    }
}

extension AppModel {
    /// Zips the folder into the archive folder, then (when asked) moves the original to the Trash.
    func archiveProject(_ folder: URL, name: String, to destDir: URL, trashOriginal: Bool, expectedBytes: Int64) {
        let dest = FileTools.unique(destDir.appending(path: name))
        let job = TransferJob(title: "Archiving \(folder.lastPathComponent)")
        job.currentName = dest.lastPathComponent
        transfers.jobs.append(job)
        Task {
            // The zip grows while it is written; its size against the folder size is a rough progress.
            let progress = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(500))
                    let size = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int64) ?? 0
                    if expectedBytes > 0 { job.fraction = min(0.95, Double(size) / Double(expectedBytes)) }
                }
            }
            let error = await Task.detached(priority: .userInitiated) { FileTools.archive(folder, to: dest) }.value
            progress.cancel()
            transfers.jobs.removeAll { $0.id == job.id }
            refresh()
            if let error {
                alert = error
                return
            }
            if trashOriginal { trash([folder]) }
        }
    }
}

struct ArchiveSheet: View {
    let app: AppModel
    let folder: URL
    @Environment(\.closePanel) private var dismiss
    @AppStorage("textSize") private var textSize = 1
    @AppStorage("archiveTrashOriginal") private var trashOriginal = true
    @State private var name: String
    @State private var dest: URL
    @State private var info = "Counting files…"
    @State private var bytes: Int64 = 0

    init(app: AppModel, folder: URL) {
        self.app = app
        self.folder = folder
        let date = Date.now.formatted(.iso8601.year().month().day())
        _name = State(initialValue: "\(folder.lastPathComponent)_\(date).zip")
        _dest = State(initialValue: folder.deletingLastPathComponent())
    }

    private var s: CGFloat { UIScale.value(textSize) }

    private var finalName: String {
        let n = name.trimmingCharacters(in: .whitespaces)
        return n.lowercased().hasSuffix(".zip") ? n : n + ".zip"
    }

    private var problem: String? {
        let n = name.trimmingCharacters(in: .whitespaces)
        if n.isEmpty { return "The name cannot be empty." }
        if n.contains("/") || n.contains(":") { return "The name cannot contain \"/\" or \":\"." }
        let d = dest.standardizedFileURL.path
        let f = folder.standardizedFileURL.path
        if d == f || d.hasPrefix(f + "/") { return "The archive folder cannot be inside the folder being archived." }
        return nil
    }

    private func abbreviated(_ url: URL) -> String { (url.path as NSString).abbreviatingWithTildeInPath }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        var isDir: ObjCBool = false
        panel.directoryURL = FileManager.default.fileExists(atPath: dest.path, isDirectory: &isDir) ? dest : dest.deletingLastPathComponent()
        if panel.runModal() == .OK, let url = panel.url { dest = url }
    }

    private func row<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 12) {
            Text(label).foregroundStyle(.secondary).frame(width: 110 * s, alignment: .leading)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Archive Project").font(.system(size: 22 * s))

            row("Folder") {
                Text(abbreviated(folder))
                    .lineLimit(1).truncationMode(.middle)
                    .padding(.horizontal, 10 * s).padding(.vertical, 6 * s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.03)))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.15)))
            }
            row("Archive name") {
                TextField("", text: $name).textFieldStyle(PathsTextFieldStyle(scale: s))
            }
            row("Save to") {
                HStack(spacing: 8) {
                    Text(abbreviated(dest))
                        .lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Choose…") { chooseDestination() }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10 * s).padding(.vertical, 6 * s)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.18)))
            }
            row("") {
                Toggle("Move the original folder to Trash", isOn: $trashOriginal)
                    .toggleStyle(PathsCheckboxStyle(scale: s))
            }

            Group {
                if let problem {
                    Text(problem).foregroundStyle(Color.orange)
                } else {
                    Text("\(info). The zip is checked before the original is moved.")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 12 * s))
            .padding(.leading, 122 * s)

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(PathsButtonStyle(scale: s))
                    .keyboardShortcut(.cancelAction)
                Button("Archive") {
                    app.archiveProject(folder, name: finalName, to: dest, trashOriginal: trashOriginal, expectedBytes: bytes)
                    dismiss()
                }
                .buttonStyle(PathsButtonStyle(scale: s, prominent: true))
                .keyboardShortcut(.defaultAction)
                .disabled(problem != nil)
            }
        }
        .font(.system(size: 13 * s))
        .padding(28)
        .frame(width: 560 * s)
        .task {
            let folder = folder
            let r = await Task.detached(priority: .utility) { FileTools.stats(of: folder) }.value
            bytes = r.bytes
            let size = ByteCountFormatter.string(fromByteCount: r.bytes, countStyle: .file)
            info = (r.files == 1 ? "1 file" : "\(r.files) files") + ", " + size
        }
    }
}
