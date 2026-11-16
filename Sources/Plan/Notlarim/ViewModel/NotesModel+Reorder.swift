import AppKit

// Düzenleme modunda ↑ / ↓ tuşları veya yukarı-aşağı kaydırma ile sıra değiştirme.
// Klavye ve kaydırma olaylarını `ReorderInput` dinler; bu dosya yalnızca sıranın kendisini değiştirir.
extension NotesModel {
    /// Sıra değiştirme girdisi şu an dinlenmeli mi?
    var reorderActive: Bool {
        editMode && !selected.isEmpty && txt == nil && sheet == nil && searchQuery == nil && root != nil
    }

    func installReorderMonitors() { reorderInput.install() }

    /// İşaretli satırların indeksleri; başa/sona toplanmışsa ilgili düğme pasif olur.
    private var selectedIndices: [Int] { list.indices.filter { selected.contains(list[$0].key) } }
    var canMoveUp: Bool { selectedIndices.enumerated().contains { $0.element != $0.offset } }
    var canMoveDown: Bool {
        let s = selectedIndices
        return s.enumerated().contains { $0.element != list.count - s.count + $0.offset }
    }

    /// mode: -1 bir yukarı, 1 bir aşağı, -2 başa al, 2 sona al (işaretli tüm satırlar için); yeni sırayı kaydeder.
    func moveSelected(_ mode: Int) {
        guard editMode, !selected.isEmpty, var l = loaded, l.count > 1, let dir = current else { return }
        let before = l.map { $0.key }
        switch mode {
        case -1:
            for i in 1..<l.count where selected.contains(l[i].key) && !selected.contains(l[i - 1].key) { l.swapAt(i, i - 1) }
        case 1:
            for i in stride(from: l.count - 2, through: 0, by: -1) where selected.contains(l[i].key) && !selected.contains(l[i + 1].key) { l.swapAt(i, i + 1) }
        case -2:
            l = l.filter { selected.contains($0.key) } + l.filter { !selected.contains($0.key) }
        case 2:
            l = l.filter { !selected.contains($0.key) } + l.filter { selected.contains($0.key) }
        default:
            return
        }
        guard l.map({ $0.key }) != before else { return }
        loaded = l
        revealKey = (mode < 0 ? l.first(where: { selected.contains($0.key) }) : l.last(where: { selected.contains($0.key) }))?.key
        revealTick += 1
        let names = l.map { $0.name }
        Task { await self.io { NotesStore.saveOrder(dir, names) } }
    }
}
