import AppKit
import Carbon.HIToolbox
import ApplicationServices

// MARK: - Kısayol modeli

/// Kullanıcının seçtiği küresel kısayol (UserDefaults'ta JSON olarak saklanır).
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt          // NSEvent.ModifierFlags.rawValue (yalnızca ⌃ ⌥ ⇧ ⌘)
    var label: String            // tuşun görünen adı: "N", "Space", "F5" ...

    static let relevant: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

    /// Varsayılanlar: Notlarıma kaydet ⌃⌥N, cihazlara gönder ⌃⌥S
    static let saveDefault = Shortcut(keyCode: UInt32(kVK_ANSI_N),
                                      modifiers: NSEvent.ModifierFlags([.control, .option]).rawValue, label: "N")
    static let sendDefault = Shortcut(keyCode: UInt32(kVK_ANSI_S),
                                      modifiers: NSEvent.ModifierFlags([.control, .option]).rawValue, label: "S")

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers).intersection(Shortcut.relevant) }

    /// Carbon'un istediği değiştirici maskesi.
    var carbonModifiers: UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.shift)   { m |= UInt32(shiftKey) }
        if flags.contains(.option)  { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        return m
    }

    /// Ekranda görünen hâl, örn. "⌃⌥N".
    var display: String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option)  { s += "⌥" }
        if flags.contains(.shift)   { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s + label
    }

    /// Basılan tuştan kısayol üretir; geçersizse (değiştirici yok vb.) nil.
    static func from(event e: NSEvent) -> Shortcut? {
        let f = e.modifierFlags.intersection(relevant)
        let code = UInt32(e.keyCode)
        let isFunctionKey = functionKeys.contains(Int(code))
        // Değiştiricisiz tuş küresel kısayol olamaz (F tuşları hariç): yazı yazarken her yerde tetiklenirdi.
        if f.isEmpty && !isFunctionKey { return nil }
        // Yalnızca ⇧ ile de olmaz (büyük harf yazmayı bozar).
        if f == .shift && !isFunctionKey { return nil }
        return Shortcut(keyCode: code, modifiers: f.rawValue, label: keyLabel(code: Int(code), event: e))
    }

    private static let functionKeys: Set<Int> = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8,
                                                 kVK_F9, kVK_F10, kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15,
                                                 kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]

    private static let fNames: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7",
        kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13",
        kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20"
    ]

    private static func keyLabel(code: Int, event e: NSEvent) -> String {
        switch code {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Home: return "Home"
        case kVK_End: return "End"
        case kVK_PageUp: return "PgUp"
        case kVK_PageDown: return "PgDn"
        default:
            if let n = fNames[code] { return n }
            let c = (e.charactersIgnoringModifiers ?? "").uppercased()
            return c.isEmpty ? "#\(code)" : c
        }
    }
}

// MARK: - Küresel kısayol kaydı (Carbon; erişilebilirlik izni gerektirmez)

private let hotKeyHandler: EventHandlerUPP = { _, event, _ in
    var hk = EventHotKeyID()
    let st = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                               nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
    guard st == noErr else { return st }
    let id = hk.id
    Task { @MainActor in QuickCapture.hotKeyPressed(id) }
    return noErr
}

/// İki küresel kısayol:
///  • `.send`: seçili metin / link / dosyalar açık cihazlara gönderilir (metin ve link, Notlarım kayıt biçimine çevrilerek).
///  • `.save`: seçili metin / link Notlarım'a eklenir.
@MainActor
enum QuickCapture {
    enum Action: UInt32, CaseIterable {
        case save = 1, send = 2

        var title: String {
            switch self {
            case .save: return L("Notlarıma Kaydet", "Save to My Notes")
            case .send: return L("Cihazlara Gönder", "Send to Devices")
            }
        }
        var detail: String {
            switch self {
            case .save: return L("Seçili metin ya da link Notlarım'a eklenir.", "Selected text or link is added to My Notes.")
            case .send: return L("Seçili metin, link ve dosyalar açık cihazlara gönderilir.", "Selected text, links and files are sent to open devices.")
            }
        }
        var defaultShortcut: Shortcut { self == .save ? .saveDefault : .sendDefault }
        fileprivate var shortcutKey: String { self == .save ? "quickSaveShortcut" : "quickSendShortcut" }
        fileprivate var enabledKey: String { self == .save ? "quickSaveEnabled" : "quickSendEnabled" }
    }

    private static var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private static var handlerInstalled = false
    private static var busy = false

    // MARK: Ayarlar

    static func shortcut(_ a: Action) -> Shortcut {
        if let d = UserDefaults.standard.data(forKey: a.shortcutKey),
           let s = try? JSONDecoder().decode(Shortcut.self, from: d) { return s }
        return a.defaultShortcut
    }

    static func setShortcut(_ s: Shortcut, for a: Action) {
        if let d = try? JSONEncoder().encode(s) { UserDefaults.standard.set(d, forKey: a.shortcutKey) }
    }

    static func enabled(_ a: Action) -> Bool {
        UserDefaults.standard.object(forKey: a.enabledKey) as? Bool ?? true
    }

    static func setEnabled(_ on: Bool, for a: Action) { UserDefaults.standard.set(on, forKey: a.enabledKey) }

    /// Menüde / pencerede görünen kısayol metni ("⌃⌥N" ya da "Kapalı").
    static func display(_ a: Action) -> String { enabled(a) ? shortcut(a).display : L("Kapalı", "Off") }

    // MARK: Kayıt

    /// Kayıtlı ayarlara göre tüm kısayolları sisteme tanıtır. Kaydedilemeyen (başka uygulama kullanıyor) eylemleri döndürür.
    @discardableResult
    static func apply() -> [Action] {
        unregisterAll()
        var failed: [Action] = []
        for a in Action.allCases where enabled(a) {
            if !register(a) { failed.append(a) }
        }
        return failed
    }

    /// Kısayol penceresi açıkken (tuş yakalanırken) geçici olarak hepsini devre dışı bırakır.
    static func suspend() { unregisterAll() }

    private static func register(_ a: Action) -> Bool {
        if !handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            guard InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &spec, nil, nil) == noErr else { return false }
            handlerInstalled = true
        }
        let s = shortcut(a)
        let id = EventHotKeyID(signature: OSType(0x504C414E), id: a.rawValue)      // 'PLAN'
        var ref: EventHotKeyRef?
        let st = RegisterEventHotKey(s.keyCode, s.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref)
        guard st == noErr, let ref else { return false }                              // başka uygulama aynı kısayolu tutuyorsa hata verir
        hotKeyRefs[a.rawValue] = ref
        return true
    }

    private static func unregisterAll() {
        for (_, r) in hotKeyRefs { UnregisterEventHotKey(r) }
        hotKeyRefs.removeAll()
    }

    // MARK: Tetikleme

    fileprivate static func hotKeyPressed(_ id: UInt32) {
        if let a = Action(rawValue: id) { run(a) }
    }

    /// Seçimi yakalar; eyleme göre Notlarım'a kaydeder ya da açık cihazlara göndermek için paylaşım panelini açar.
    static func run(_ action: Action) {
        guard !busy else { return }
        // Başka uygulamadan seçimi okumak / ⌘C göndermek için Erişilebilirlik izni gerekir.
        guard AXIsProcessTrusted() else {
            let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
            HUD.show(L("Erişilebilirlik izni verin, sonra tekrar deneyin",
                       "Allow Accessibility, then try again"))
            return
        }
        busy = true
        Task { @MainActor in
            defer { busy = false }
            let captured = await captureSelection()
            switch (action, captured) {
            case (.send, .files(let urls)?):
                SharePanel.shared.show(files: urls)
            case (.send, .text(let t)?) where !t.trimmed.isEmpty:
                // Önce Notlarım'a aynen kaydedilir (aynı kural), sonra kaydedilen dosya açık cihazlara gönderilir.
                let files = await saveToNotes(t, announce: false)
                if !files.isEmpty { SharePanel.shared.show(files: files) }
            case (.save, .text(let t)?) where !t.trimmed.isEmpty:
                await saveToNotes(t, announce: true)
            case (.save, .files?):
                HUD.show(L("Dosyalar için “Cihazlara Gönder” kısayolunu kullanın", "Use the “Send to Devices” shortcut for files"))
            default:
                HUD.show(L("Seçili metin, link ya da dosya bulunamadı", "No selected text, link or file found"))
            }
        }
    }

    // MARK: Ortak kayıt kuralı (Notlarım'a ekleme ve gönderme için aynı)

    private enum Stored { case link, note, textFile, failed }

    /// Ortak kural: boşluk içeren veri link değildir (kısa → not, 116 karakterden uzun → .txt); boşluksuz ve nokta ya da "/" içeren veri
    /// link olarak yazılır (`://` yoksa başına https:// eklenir; başlık sayfadan alınır, alınamazsa alan adı).
    private static func store(_ text: String, in dir: URL) async -> Stored {
        let t = text.trimmed
        if isLink(t) {
            let url = t.contains("://") ? t : "https://" + t
            let title = await PageTitle.fetch(url) ?? NotesStore.makeURL(url)?.host ?? t
            return NotesStore.addLink(dir, title: title, url: url) ? .link : .failed
        }
        if t.count > NotesStore.addMax { return NotesStore.addTextFile(dir, text: t) ? .textFile : .failed }
        return NotesStore.addNote(dir, text: t) ? .note : .failed
    }

    /// Link kuralı (tek ve basit): boşluk (ya da satır sonu) içeren veri link DEĞİLDİR; boşluksuz ama nokta ya da "/" içermeyen
    /// tek kelime de link değildir. Geri kalan her veri link olarak kaydedilir.
    static func isLink(_ text: String) -> Bool {
        let t = text.trimmed
        guard !t.isEmpty, !t.contains(where: { $0.isWhitespace }) else { return false }
        return t.contains(".") || t.contains("/")
    }

    /// Metni/linki Notlarım'a (ana Link klasörü) kaydeder ve oluşan dosyayı döndürür (başarısızsa boş).
    /// `announce`: başarıda "kaydedildi" bildirimi gösterilsin mi (gönderirken paylaşım paneli açılacağı için gösterilmez).
    @discardableResult
    private static func saveToNotes(_ text: String, announce: Bool) async -> [URL] {
        guard let root = NotesStore.root else {
            HUD.show(L("Link klasörü bulunamadı", "Link folder not found")); return []
        }
        let fm = FileManager.default
        let before = Set((try? fm.contentsOfDirectory(atPath: root.path)) ?? [])
        let r = await store(text, in: root)
        NotesModel.shared.reload()
        if r == .failed { HUD.show(L("Kaydedilemedi", "Couldn't save")); return [] }
        if announce {
            HUD.show(r == .textFile ? L("Notlarıma metin dosyası olarak kaydedildi", "Saved to My Notes as a text file")
                                    : L("Notlarıma kaydedildi", "Saved to My Notes"))
        }
        // Yeni oluşan dosya: kayıttan önce klasörde olmayan, gizli olmayan ad.
        let after = (try? fm.contentsOfDirectory(atPath: root.path)) ?? []
        return after.filter { !before.contains($0) && !$0.hasPrefix(".") }
            .map { root.appendingPathComponent($0) }
    }

    // MARK: Seçimi yakalama

    private enum Captured { case text(String), files([URL]) }

    /// 1) Erişilebilirlik ile seçili metin (panoya dokunmaz), 2) olmazsa ⌘C gönderip panoyu okur (dosya mı metin mi) ve eski panoyu geri koyar,
    /// 3) hiçbir şey seçili değilse panodaki mevcut içerik (kopyalanmış dosya ya da metin).
    private static func captureSelection() async -> Captured? {
        if let s = axSelectedText(), !s.trimmed.isEmpty { return .text(s) }

        let pb = NSPasteboard.general
        let snapshot = snapshotPasteboard(pb)
        let before = pb.changeCount

        await waitForModifiersReleased()
        sendCopy()

        // ⌘C'nin panoyu güncellemesini bekle (en çok ~0,5 sn)
        var changed = false
        for _ in 0..<25 {
            try? await Task.sleep(nanoseconds: 20_000_000)
            if pb.changeCount != before { changed = true; break }
        }
        let result = pasteboardContent(pb)
        if changed { restorePasteboard(pb, snapshot) }
        return result
        // changed == false: seçim yok; panoda zaten kopyalanmış içerik varsa o kullanıldı.
    }

    /// Panodaki içerik: dosya(lar) varsa dosyalar; yoksa metin (link sayfa adresi olarak da gelmiş olabilir).
    private static func pasteboardContent(_ pb: NSPasteboard) -> Captured? {
        if let urls = pb.readObjects(forClasses: [NSURL.self],
                                     options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            return .files(urls)
        }
        // Tarayıcı "Bağlantıyı Kopyala" gibi durumlarda adres yalnızca ayrı bir pano türünde gelebilir.
        let str = pb.string(forType: .string)?.trimmed ?? pb.string(forType: .URL)?.trimmed ?? ""
        return str.isEmpty ? nil : .text(str)
    }

    private static func axSelectedText() -> String? {
        let sys = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused else { return nil }
        let el = focused as! AXUIElement
        var sel: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXSelectedTextAttribute as CFString, &sel) == .success,
              let s = sel as? String else { return nil }
        return s
    }

    /// Kısayoldaki ⌃⌥ gibi tuşlar hâlâ basılıyken ⌘C gönderirsek hedef uygulama karışık değiştirici görür; bırakılmasını bekle.
    private static func waitForModifiersReleased() async {
        let mask: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]
        for _ in 0..<50 {
            let f = CGEventSource.flagsState(.combinedSessionState)
            if f.intersection(mask).isEmpty { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private static func sendCopy() {
        let src = CGEventSource(stateID: .hidSystemState)
        let c = CGKeyCode(kVK_ANSI_C)
        let down = CGEvent(keyboardEventSource: src, virtualKey: c, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: c, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    // MARK: Pano yedeği

    private typealias Snapshot = [[(NSPasteboard.PasteboardType, Data)]]

    private static func snapshotPasteboard(_ pb: NSPasteboard) -> Snapshot {
        (pb.pasteboardItems ?? []).map { item in
            item.types.compactMap { t in item.data(forType: t).map { (t, $0) } }
        }
    }

    private static func restorePasteboard(_ pb: NSPasteboard, _ snap: Snapshot) {
        pb.clearContents()
        guard !snap.isEmpty else { return }
        let items: [NSPasteboardItem] = snap.map { pairs in
            let it = NSPasteboardItem()
            for (t, d) in pairs { it.setData(d, forType: t) }
            return it
        }
        pb.writeObjects(items)
    }
}
