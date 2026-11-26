import Foundation
import Network

/// Android'deki Hızlı Paylaş ile aynı protokol:
///  - mDNS: `_qshare._tcp`, servis adı "QS"+kimlik[0..10], TXT: n=cihaz adı, i=kimlik  (Swift: NetService/NWBrowser)
///  - Alma, gönderme ve Link eşitleme: düz TCP, `POST /u` + `X-Name` + `Content-Length` …  (Rust: rust/plan_core/src/share)
/// Telefon/TV, aynı ağdaki açık Mac'i bulur ve dosyayı doğrudan gönderir.
struct QSDevice: Identifiable, Hashable {
    let id: String          // Bonjour servis adı
    let name: String        // TXT "n" (cihaz adı)
    let endpoint: NWEndpoint
}

/// Paylaşım ekranındaki bilgi satırı (bildirim yok; yalnızca panelde gösterilir).
struct QSInfo: Equatable {
    enum Kind { case sending, sent, receiving, received, failed }
    var kind: Kind
    var text: String
    var folder: URL? = nil      // alınan dosyanın kaydedildiği klasör (satıra tıklayınca açılır)
    var icon: String {
        switch kind {
        case .sending: return "arrow.up.circle"
        case .sent: return "checkmark.circle"
        case .receiving: return "arrow.down.circle"
        case .received: return "arrow.down.circle.fill"
        case .failed: return "exclamationmark.triangle"
        }
    }
}

extension Notification.Name { static let notesChangedBySync = Notification.Name("notesChangedBySync") }

final class QuickShare: ObservableObject {
    static let shared = QuickShare()
    @Published var running = false
    @Published var message = ""
    @Published var info: QSInfo?        // son gönderme / alma durumu (paylaşım ekranında tek satır)
    @Published var devices: [QSDevice] = []
    @Published var sendingTo = Set<String>()
    @Published var syncing = false

    private var server: RustShare.Server?
    private var service: NetService?
    private var browser: NWBrowser?

    static var identity: String {
        if let i = UserDefaults.standard.string(forKey: "qsId") { return i }
        let i = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        UserDefaults.standard.set(i, forKey: "qsId"); return i
    }

    static var receiveDir: URL {
        let d = UserDefaults.standard.string(forKey: "recvDir").map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    // MARK: Aç / kapat

    func start() {
        guard server == nil else { return }
        RustShare.setLanguage()
        // Alma sunucusu Rust'ta; Bonjour yalnızca onun portunu duyurur.
        guard let s = RustShare.Server(recvDir: Self.receiveDir, linkRoot: NotesStore.root,
                                       onEvent: { [weak self] e in self?.handle(e) }) else {
            DispatchQueue.main.async { self.message = "Paylaşım açılamadı" }
            return
        }
        server = s
        UserDefaults.standard.set(true, forKey: "qsOn")
        let id = Self.identity
        let name = Host.current().localizedName ?? "Mac"
        let port = Int32(s.port)
        DispatchQueue.main.async {
            self.running = true
            let svc = NetService(domain: "local.", type: "_qshare._tcp.", name: "QS" + String(id.prefix(10)), port: port)
            svc.setTXTRecord(NetService.data(fromTXTRecord: ["n": Data(name.utf8), "i": Data(id.utf8)]))
            svc.publish()
            self.service = svc
        }
        startBrowsing()
    }

    func stop() {
        server?.stop(); server = nil
        UserDefaults.standard.set(false, forKey: "qsOn")
        browser?.cancel(); browser = nil
        DispatchQueue.main.async {
            self.service?.stop(); self.service = nil
            self.running = false
            self.devices = []
            self.info = nil
        }
    }

    func toggle() { running ? stop() : start() }

    /// Paylaşım ekranı açılınca: kapalıysa kendiliğinden açar (elle "Aç"a basmaya gerek kalmaz).
    func ensureRunning() { if !running { start() } }

    /// Açık cihaz aramasını yeniden başlatır (paylaşım ekranındaki ⟳ simgesi).
    func refreshDevices() {
        if server == nil { start() } else { startBrowsing() }
    }

    // MARK: Açık cihazları bul (aynı ağda _qshare._tcp yayınlayanlar)
    private func startBrowsing() {
        browser?.cancel()
        let b = NWBrowser(for: .bonjourWithTXTRecord(type: "_qshare._tcp", domain: nil), using: .tcp)
        let myName = "QS" + String(Self.identity.prefix(10))
        b.browseResultsChangedHandler = { [weak self] results, _ in
            var out: [QSDevice] = []
            for r in results {
                guard case let .service(name, _, _, _) = r.endpoint else { continue }
                var title = name, id = ""
                if case let .bonjour(txt) = r.metadata {
                    title = txt.dictionary["n"] ?? name
                    id = txt.dictionary["i"] ?? ""
                }
                if name == myName || id == Self.identity { continue }   // kendimizi listeleme
                out.append(QSDevice(id: name, name: title, endpoint: r.endpoint))
            }
            out.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            DispatchQueue.main.async { self?.devices = out }
        }
        b.start(queue: .global(qos: .userInitiated))
        browser = b
    }

    /// Bonjour uç noktasını Rust'ın kullanacağı "ip:port" adresine çevirir (IPv4 tercih edilir). Engelleyici (≤ 8 sn).
    static func resolveAddress(_ ep: NWEndpoint) -> String? {
        let params = NWParameters.tcp
        if let ip = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options { ip.version = .v4 }
        let conn = NWConnection(to: ep, using: params)
        let sem = DispatchSemaphore(value: 0)
        var addr: String?
        conn.stateUpdateHandler = { st in
            switch st {
            case .ready:
                if case let .hostPort(host, port)? = conn.currentPath?.remoteEndpoint {
                    var h = "\(host)"
                    if let i = h.firstIndex(of: "%") { h = String(h[..<i]) }     // arayüz eki (fe80::1%en0)
                    addr = h.contains(":") ? "[\(h)]:\(port.rawValue)" : "\(h):\(port.rawValue)"
                }
                sem.signal()
            case .failed, .cancelled: sem.signal()
            default: break
            }
        }
        conn.start(queue: DispatchQueue(label: "qs.resolve"))
        _ = sem.wait(timeout: .now() + 8)
        conn.cancel()
        return addr
    }

    // MARK: Dosya gönder (Rust: client::send_files)
    /// `toLink` true: karşı cihazın Link klasörüne, false: indirme (Download) klasörüne.
    func send(_ files: [URL], to d: QSDevice, toLink: Bool = false) {
        guard !files.isEmpty else { return }
        let first = files[0].lastPathComponent
        DispatchQueue.main.async {
            self.sendingTo.insert(d.id)
            self.info = QSInfo(kind: .sending, text: files.count == 1 ? "Gönderiliyor: \(first)" : "Gönderiliyor: \(files.count) dosya → \(d.name)")
        }
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            var okCount = 0
            if let addr = Self.resolveAddress(d.endpoint) {
                okCount = RustShare.send(files, toAddress: addr, toLink: toLink, linkRoot: NotesStore.root)
            }
            DispatchQueue.main.async { self.sendingTo.remove(d.id) }
            if okCount == files.count {
                post(.sent, files.count == 1 ? "Gönderildi: \(first) → \(d.name)" : "\(okCount) dosya gönderildi → \(d.name)")
            } else {
                post(.failed, "Gönderilemedi (\(files.count - okCount) dosya) → \(d.name)")
            }
        }
    }

    // MARK: Link eşitleme (Rust: sync::run)

    /// Paylaşım ekranındaki ⇄ simgesi: seçilen cihazlarla ~/Link klasörünü eşitler (mode: 0 iki cihazda aynı, 1 bu cihaza göre, 2 karşıdakine göre).
    func sync(mode: Int, with devices: [QSDevice]) {
        guard !syncing, !devices.isEmpty else { return }
        syncing = true
        post(.sending, L("Eşitleniyor…", "Syncing…"))
        let targets = mode == 2 ? Array(devices.prefix(1)) : devices     // mod 2'de yalnızca ilk seçilen
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            var peers: [(name: String, addr: String)] = []
            var errs: [String] = []
            for d in targets {
                if let a = Self.resolveAddress(d.endpoint) { peers.append((d.name, a)) }
                else { errs.append("\(d.name): " + L("bağlantı kurulamadı", "could not connect")) }
            }
            var ok = false
            var text = errs.first ?? L("Açık cihaz bulunamadı", "No open device found")
            // Mod 2 yıkıcıdır: ilk cihaza ulaşılamadıysa başka cihaza kaydırma
            if !peers.isEmpty, let r = RustShare.sync(mode: mode, linkRoot: NotesStore.root, peers: peers) {
                ok = r.ok && errs.isEmpty
                text = errs.isEmpty ? r.message : r.message + "\n" + errs[0]
            }
            DispatchQueue.main.async {
                self.syncing = false
                NotificationCenter.default.post(name: .notesChangedBySync, object: nil)
            }
            post(ok ? .sent : .failed, text)
        }
    }

    // MARK: Rust olayları

    private func handle(_ e: RustShare.Event) {
        switch e {
        case .receiving(let n): post(.receiving, "Alınıyor: \(n)")
        case .received(let n, let folder): post(.received, "Alındı: \(n)", folder: folder)
        case .failed(let n): post(.failed, "Alma yarım kaldı: \(n)")
        case .notesChanged:
            // Eşitleme ~/Link içeriğini değiştirdi: açık Notlarım penceresi listeyi yeniler.
            DispatchQueue.main.async { NotificationCenter.default.post(name: .notesChangedBySync, object: nil) }
        }
    }

    /// Bildirim göndermez; bilgi yalnızca paylaşım ekranındaki satırda görünür.
    func post(_ kind: QSInfo.Kind, _ s: String, folder: URL? = nil) {
        DispatchQueue.main.async { self.info = QSInfo(kind: kind, text: s, folder: folder) }
    }
}
