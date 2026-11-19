import AppKit
import UniformTypeIdentifiers

/// Safari (ve diğer uygulamaların) Paylaş menüsündeki "Notlarım" girişi.
/// Kendisi dosya yazmaz; linki `plan://add?t=...` adresiyle ana uygulamaya iletir
/// (ana uygulama arka planda başlığı alıp kaydeder ve kısa bir bildirim gösterir).
@objc(ShareViewController)
final class ShareViewController: NSViewController {
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Finder'dan dosya paylaşıldıysa: yolları ana uygulamaya ilet, o açık cihaz seçme panelini gösterir
        collectFiles { [weak self] files in
            DispatchQueue.main.async {
                guard let self else { return }
                if !files.isEmpty { self.forwardFiles(files); return }
                self.collect { text in
                    DispatchQueue.main.async { self.forward(text, subject: self.pageTitle()) }
                }
            }
        }
    }

    private func collectFiles(_ done: @escaping ([URL]) -> Void) {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        let providers = items.flatMap { $0.attachments ?? [] }
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !providers.isEmpty else { done([]); return }
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []
        for p in providers {
            group.enter()
            p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var u: URL?
                if let x = item as? URL { u = x }
                else if let d = item as? Data { u = URL(dataRepresentation: d, relativeTo: nil) }
                else if let s = item as? String { u = URL(string: s) }
                if let u, u.isFileURL { lock.lock(); urls.append(u); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) { done(urls) }
    }

    private func forwardFiles(_ files: [URL]) {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let query = files.map { "f=" + ($0.path.addingPercentEncoding(withAllowedCharacters: allowed) ?? "") }.joined(separator: "&")
        guard let url = URL(string: "plan://send?" + query) else { finish(); return }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true    // cihaz seçme paneli öne gelsin
        NSWorkspace.shared.open(url, configuration: cfg) { [weak self] _, _ in
            DispatchQueue.main.async { self?.finish() }
        }
    }

    private func collect(_ done: @escaping (String?) -> Void) {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        let providers = items.flatMap { $0.attachments ?? [] }

        if let p = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }) {
            p.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                if let u = item as? URL { done(u.isFileURL ? nil : u.absoluteString) }
                else if let s = item as? String { done(s) }
                else if let d = item as? Data, let s = String(data: d, encoding: .utf8) { done(s) }
                else { done(nil) }
            }
            return
        }
        if let p = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }) {
            p.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                done(item as? String)
            }
            return
        }
        done(items.first?.attributedContentText?.string)
    }

    /// Paylaşan uygulamanın (Safari vb.) verdiği sayfa başlığı.
    private func pageTitle() -> String? {
        let item = (extensionContext?.inputItems as? [NSExtensionItem])?.first
        let t = item?.attributedTitle?.string ?? item?.attributedContentText?.string
        let v = t?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (v?.isEmpty == false) ? v : nil
    }

    private func forward(_ text: String?, subject: String? = nil) {
        guard let text = text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { finish(); return }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let enc = text.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        var link = "plan://add?t=" + enc
        if let s = subject, s != text { link += "&s=" + (s.addingPercentEncoding(withAllowedCharacters: allowed) ?? "") }
        guard let url = URL(string: link) else { finish(); return }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = false   // uygulamayı öne getirme
        NSWorkspace.shared.open(url, configuration: cfg) { [weak self] _, _ in
            DispatchQueue.main.async { self?.finish() }
        }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
