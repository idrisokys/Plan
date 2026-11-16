import Foundation

/// Veri ekleme ve veri arama için TEK ortak giriş noktaları.
/// Hem menü çubuğu panelindeki arama kutusu (ContentView) hem de Notlarım penceresindeki alt alan (AddBar)
/// bunları kullanır; ekleme kuralı ve arama mantığı yalnızca burada durur.
extension NotesStore {
    /// Gönderilen metnin sınırı: bunu aşan (tek parça link olmayan) metin .txt olur.
    static let addMax = 220

    enum SubmitResult { case added, textFile, failed }

    /// Ortak "gönder" kuralı: tek parça link → link (başlığı sayfadan alınır), kısa metin → not (.url içinde TEXT=),
    /// sınırı aşan metin → .txt dosyası. Ağ erişimi yapabildiği için arka planda çağrılır.
    static func submit(_ dir: URL, _ text: String, subject: String? = nil) async -> SubmitResult {
        let t = text.trimmed
        guard !t.isEmpty else { return .failed }
        let singleUrl = extractUrl(t) != nil && !t.contains(where: { $0.isWhitespace })   // boşluksuz uzun link yine link kalır
        if t.count > addMax && !singleUrl {
            return addTextFile(dir, text: t) ? .textFile : .failed
        }
        return await addFromText(dir, t, subject) ? .added : .failed
    }

    /// Ortak arama: tüm klasörlerde, ağır tarama arka planda yapılır. `alive` false dönerse arama bırakılır.
    static func searchAsync(root: URL, query: String, alive: @escaping @Sendable () -> Bool) async -> [Hit] {
        await Task.detached(priority: .userInitiated) {
            search(root: root, query: query, alive: alive)
        }.value
    }
}
