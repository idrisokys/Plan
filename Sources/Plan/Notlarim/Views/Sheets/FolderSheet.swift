import SwiftUI
import AppKit

struct FolderSheet: View {
    @EnvironmentObject var m: NotesModel
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("Yeni klasör", "New folder")).font(.system(size: 20)).foregroundStyle(NT.onSurface)
            TextField(L("Klasör adı", "Folder name"), text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { create() }
            HStack(spacing: 8) {
                Spacer()
                Button(L("İptal", "Cancel")) { m.sheet = nil }
                    .keyboardShortcut(.cancelAction)
                Button(L("Oluştur", "Create")) { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmed.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 340)
        .background(NT.dialog)
        .onAppear { focused = true }
    }

    private func create() {
        let n = name
        if n.trimmed.isEmpty { return }
        m.sheet = nil
        m.createFolder(n)
    }
}
