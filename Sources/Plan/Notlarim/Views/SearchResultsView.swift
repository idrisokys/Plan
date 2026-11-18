import SwiftUI
import AppKit

struct SearchResultsView: View {
    @EnvironmentObject var m: NotesModel

    var body: some View {
        if let hits = m.hits {
            if hits.isEmpty {
                Text(L("Sonuç bulunamadı.", "No results found."))
                    .foregroundStyle(NT.onSurface)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(NT.bg)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(hits) { h in
                            hitRow(h)
                            Rectangle().fill(NT.outlineVariant).frame(height: 1)
                        }
                    }
                }
                .background(NT.bg)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(NT.bg)
        }
    }

    @ViewBuilder
    private func hitRow(_ h: Hit) -> some View {
        HStack(alignment: .center, spacing: 16) {
            MIcon(h.entry.isDir ? MI.folder : ((h.isNote || h.entry.isTxt) ? MI.description : MI.link))
                .foregroundStyle(NT.onSurface)
            VStack(alignment: .leading, spacing: 2) {
                Text(h.path.isEmpty ? L("Ana liste", "Main list") : h.path.map { $0.name }.joined(separator: " › "))
                    .font(.system(size: max(m.fontSize - 4, 9)))
                    .foregroundStyle(NT.onSurfaceVariant)
                    .lineLimit(1)
                Text(h.entry.title)
                    .font(.system(size: m.fontSize))
                    .foregroundStyle(NT.onSurface)
                    .lineLimit(4)
                if !h.isNote && !h.detail.isEmpty {
                    Text(h.detail)
                        .font(.system(size: max(m.fontSize - 2, 9)))
                        .foregroundStyle(NT.onSurfaceVariant)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            IconBtn(MI.folderOpen, help: L("Klasöre git", "Go to folder")) {
                m.exitSearch(true)
                m.setStack(h.path)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            if h.entry.isDir { m.exitSearch(true); m.setStack(h.path + [h.entry]) }   // klasör: içine gir
            else { m.open(h.entry) }
        }
    }
}
