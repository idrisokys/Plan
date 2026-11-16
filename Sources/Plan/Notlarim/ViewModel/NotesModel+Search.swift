import SwiftUI
import AppKit

extension NotesModel {
    // MARK: - Arama

    func startSearch() {
        // .txt açıkken ⌘F metnin içinde arar
        if txt != nil { if !txtEditing { txtSearching = true }; return }
        let q = linkText.trimmed
        guard !q.isEmpty else { return }
        NSApp.keyWindow?.makeFirstResponder(nil)
        editMode = false
        selected = []
        runSearch(q)
    }

    func runSearch(_ q: String) {
        guard let rootURL = root else { return }
        searchFlag?.cancel()
        let flag = CancelFlag()
        searchFlag = flag
        searchQuery = q
        hits = nil
        Task { [weak self] in
            // Ağır tarama arka planda (ortak NotesStore.searchAsync); sonuç ana aktörde yazılır.
            let r = await NotesStore.searchAsync(root: rootURL, query: q, alive: { !flag.isCancelled })
            if !flag.isCancelled { self?.hits = r }
        }
    }

    func exitSearch(_ clearText: Bool) {
        searchFlag?.cancel()
        if clearText && linkText.trimmed == searchQuery { linkText = "" }
        searchQuery = nil
        hits = nil
    }
}
