import SwiftUI
import AppKit

@MainActor
final class NotesModel: ObservableObject {
    static let shared = NotesModel()

    /// Hızlı Paylaş eşitlemesi ~/Link içeriğini değiştirince listeyi yeniler (art arda gelen bildirimler birleştirilir).
    private static var reloadPending = false
    private let syncObserver = NotificationCenter.default.addObserver(forName: .notesChangedBySync, object: nil, queue: .main) { _ in
        Task { @MainActor in
            if NotesModel.reloadPending { return }
            NotesModel.reloadPending = true
            try? await Task.sleep(nanoseconds: 400_000_000)
            NotesModel.reloadPending = false
            NotesModel.shared.reload()
        }
    }

    @Published var root: URL? = NotesStore.root
    @Published var stack: [Entry] = []
    @Published var loaded: [Entry]? = nil
    @Published var editMode = false { didSet { syncRename() } }
    @Published var selected: Set<String> = [] { didSet { syncRename() } }
    @Published var linkText = ""
    @Published var searchQuery: String? = nil
    @Published var hits: [Hit]? = nil
    @Published var sheet: Sheet? = nil
    @Published var moving: [Entry] = []
    @Published var renaming: Entry? = nil      // düzenleme modunda tek öğe seçiliyse o öğe (adı altta değiştirilir)
    @Published var renameText = ""
    /// ⋮ menüsindeki "Düzenle": yalnızca o satırın adı alttaki alanda düzenlenir; seçim modu açılmaz.
    @Published var inlineRename = false

    // Pencere her zaman üstte mi? Varsayılan: hayır. Sağ üstteki raptiye düğmesiyle değişir; kalıcıdır.
    @Published var alwaysOnTop: Bool = UserDefaults.standard.bool(forKey: "alwaysOnTop") {
        didSet {
            UserDefaults.standard.set(alwaysOnTop, forKey: "alwaysOnTop")
            NotesWindow.window?.level = alwaysOnTop ? .floating : .normal
        }
    }
    // Tam pencerede açık .txt dosyası
    @Published var txt: Entry? = nil
    @Published var txtSaved = ""               // dosyadaki son hâl
    @Published var txtDraft = ""               // düzenlenen metin
    @Published var txtEditing = false
    @Published var txtAskDiscard = false
    @Published var txtSaving = false
    var txtDirty: Bool { txtEditing && txtDraft != txtSaved }
    // .txt içinde arama (okuma görünümü)
    @Published var txtSearching = false { didSet { txtRecompute() } }
    @Published var txtQuery = "" { didSet { txtRecompute() } }
    @Published var txtMatches: [NSRange] = []
    @Published var txtCur = 0
    // Çöp kutusu düğmesi: onay sorusu

    // Yazı boyutu (punto): liste, arama sonuçları, alt alanlar ve .txt görünümü bunu kullanır; kalıcıdır.
    static let minFont = 10.0, maxFont = 32.0, defaultFont = 16.0
    @Published var fontSize: Double = NotesModel.loadFontSize() {
        didSet { UserDefaults.standard.set(fontSize, forKey: "fontSize") }
    }
    private static func loadFontSize() -> Double {
        let d = UserDefaults.standard
        var v = d.double(forKey: "fontSize")
        // Yazılar büyütüldü: daha önce kaydedilmiş boyut bir kez +2 yapılır
        if v != 0 && !d.bool(forKey: "fontBumped2") { v += 2; d.set(v, forKey: "fontSize") }
        d.set(true, forKey: "fontBumped2")
        return v == 0 ? defaultFont : min(max(v, minFont), maxFont)
    }
    func bumpFont(_ delta: Double) { fontSize = min(max(fontSize + delta, NotesModel.minFont), NotesModel.maxFont) }

    let maxChars = 220   // ad değiştirme sınırı
    /// .url kayıtlarında (link/not) ad alanı sınırsızdır; 220'yi aşarsa kayıt otomatik .txt olur. Klasör ve .txt adları 220 ile sınırlı kalır.
    var editCap: Int {
        if let r = renaming, !r.isDir, !r.isTxt { return 20_000 }
        return maxChars
    }
    /// Ekleme / ad alanı yüksekliği (Android: en az 2, en çok 8 satır). Satır sayısı yaklaşık hesaplanır.
    func editorHeight(for text: String) -> CGFloat {
        let perLine = 40
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .reduce(0) { $0 + max(1, ($1.count + perLine - 1) / perLine) }
        let n = min(8, max(2, lines))
        return CGFloat(n) * fontSize * 1.25 + 20
    }
    let addMax = NotesStore.addMax     // alttaki ekleme alanı sınırı (panelle ortak)
    var prevLinkCount = 0   // Enter ile gönderimi algılamak için önceki uzunluk

    /// Tüm dosya işlemleri sıralı yapılır.
    private let queue = DispatchQueue(label: "plan.io")

    // Arama / sıra değiştirme
    private(set) lazy var reorderInput = ReorderInput(model: self)
    var searchFlag: CancelFlag?
    /// Son taşınan satır: liste bu satırı görünür tutmak için kaydırılır.
    @Published var revealKey: String? = nil
    @Published var revealTick = 0

    var current: URL? { stack.last?.url ?? root }
    var list: [Entry] { loaded ?? [] }

    var title: String {
        if let q = searchQuery { return "“\(q)”" + (hits.map { " · \($0.count) \(L("sonuç", "results"))" } ?? "") }
        if editMode && !selected.isEmpty { return "\(selected.count) \(L("seçili", "selected"))" }
        return stack.last?.name ?? L("Notlarım", "My Notes")
    }

    func io<T>(_ block: @escaping () -> T) async -> T {
        await withCheckedContinuation { c in
            queue.async { c.resume(returning: block()) }
        }
    }

    func toast(_ s: String) { HUD.show(s) }

    /// Düzenleme modunda tam bir öğe seçiliyse adı alttaki alanda değiştirilir.
    private func syncRename() {
        if inlineRename { return }   // satır içi düzenleme seçimden bağımsızdır
        let e: Entry? = (editMode && selected.count == 1) ? list.first(where: { selected.contains($0.key) }) : nil
        if e?.key != renaming?.key {
            renaming = e
            renameText = e?.title ?? ""
        }
    }
}
