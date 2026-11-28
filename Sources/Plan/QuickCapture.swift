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

    /// Varsayılan: ⌃⌥N
    static let `default` = Shortcut(keyCode: UInt32(kVK_ANSI_N),
                                    modifiers: NSEvent.ModifierFlags([.control, .option]).rawValue,
                                    label: "N")

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

private let hotKeyHandler: EventHandlerUPP = { _, _, _ in
    Task { @MainActor in QuickCapture.hotKeyPressed() }
    return noErr
}

/// Küresel kısayol + "seçili metni yakala → Notlarım'a kaydet" akışı.
@MainActor
enum QuickCapture {
    private static let defaultsKey = "quickSaveShortcut"
    private static let enabledKey = "quickSaveEnabled"
    private static var hotKeyRef: EventHotKeyRef?
    private static var handlerInstalled = false
    private static var busy = false

    // MARK: Ayarlar

    /// Geçerli kısayol (kayıtlı yoksa varsayılan).
    static var shortcut: Shortcut {
        get {
            if let d = UserDefaults.standard.data(forKey: defaultsKey),
               let s = try? JSONDecoder().decode(Shortcut.self, from: d) { return s }
            return .default
        }
        set {
            if let d = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(d, forKey: defaultsKey) }
        }
    }

    /// Kısayol açık mı? (Varsayılan: açık)
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    // MARK: Kayıt

    /// Kayıtlı ayara göre kısayolu sisteme tanıtır (açılışta ve her değişiklikte çağrılır).
    @discardableResult
    static func apply() -> Bool {
        unregister()
        guard enabled else { return true }
        return register(shortcut)
    }

    /// Kısayol penceresi açıkken (tuş yakalanırken) geçici olarak devre dışı bırakır.
    static func suspend() { unregister() }

    private static func register(_ s: Shortcut) -> Bool {
        if !handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let st = InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &spec, nil, nil)
            guard st == noErr else { return false }
            handlerInstalled = true
        }
        let id = EventHotKeyID(signature: OSType(0x504C414E), id: 1)      // 'PLAN'
        var ref: EventHotKeyRef?
        let st = RegisterEventHotKey(s.keyCode, s.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref)
        guard st == noErr, let ref else { return false }                    // başka uygulama aynı kısayolu tutuyorsa hata verir
        hotKeyRef = ref
        return true
    }

    private static func unregister() {
        if let r = hotKeyRef { UnregisterEventHotKey(r); hotKeyRef = nil }
    }

    // MARK: Tetikleme

    fileprivate static func hotKeyPressed() { run() }

    /// Seçili metni (yoksa panodakini) Notlarım'a kaydeder; dosya(lar) seçiliyse açık cihazlara gönderme panelini açar.
    static func run() {
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
            switch await captureSelection() {
            case .files(let urls):
                // Dosya(lar) seçiliyken: açık cihaz seçme paneli (Finder Paylaş menüsündeki ile aynı).
                SharePanel.shared.show(files: urls)
            case .text(let t) where !t.trimmed.isEmpty:
                save(t)
            default:
                HUD.show(L("Kaydedilecek metin ya da dosya bulunamadı", "Nothing to save or send"))
            }
        }
    }

    private static func save(_ text: String) {
        guard let root = NotesStore.root else {
            HUD.show(L("Link klasörü bulunamadı", "Link folder not found")); return
        }
        Task { @MainActor in
            let r = await NotesStore.submit(root, text)
            NotesModel.shared.reload()
            switch r {
            case .added:    HUD.show(L("Notlarıma kaydedildi", "Saved to My Notes"))
            case .textFile: HUD.show(L("Notlarıma metin dosyası olarak kaydedildi", "Saved to My Notes as a text file"))
            case .failed:   HUD.show(L("Kaydedilemedi", "Couldn't save"))
            }
        }
    }

    // MARK: Seçimi yakalama

    private enum Captured { case text(String), files([URL]) }

    /// 1) Erişilebilirlik ile seçili metin (panoya dokunmaz), 2) olmazsa ⌘C gönderip panoyu okur (dosya mı metin mi) ve eski panoyu geri koyar,
    /// 3) hiçbir şey seçili değilse panodaki mevcut içerik (kopyalanmış dosya ya da metin).
    private static func captureSelection() async -> Captured? {
        if let s = axSelectedText(), !s.trimmed.isEmpty { return .text(normalizeLink(s)) }

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
        let str = pb.string(forType: .string)?.trimmed ?? ""
        if NotesStore.extractUrl(str) != nil { return .text(str) }
        // Tarayıcı "Bağlantıyı Kopyala" gibi durumlarda adres ayrı bir pano türünde gelebilir.
        if let u = pb.string(forType: .URL)?.trimmed, NotesStore.extractUrl(u) != nil { return .text(u) }
        return str.isEmpty ? nil : .text(normalizeLink(str))
    }

    /// Tek parça, "https://" yazmayan adresleri (www.site.com, site.com/yol, site.com) link yapar;
    /// böylece Notlarım'ın link kuralı (başlık alma, link olarak kaydetme) onlara da uygulanır.
    static func normalizeLink(_ text: String) -> String {
        let t = text.trimmed
        guard !t.isEmpty, !t.contains(where: { $0.isWhitespace }), NotesStore.extractUrl(t) == nil,
              !t.contains("://"), !t.contains("@") else { return text }
        let host = #"(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}"#
        let rest = #"(?::\d+)?(?:[/?#]\S*)?"#
        let hasPathOrWWW = t.lowercased().hasPrefix("www.") || t.contains("/") || t.contains("?")
        let common = ["com", "net", "org", "io", "co", "app", "dev", "edu", "gov", "info", "tv", "me", "ai", "tr", "xyz", "ly", "be"]
        let hostPart = String(t.split(whereSeparator: { "/?#".contains($0) }).first ?? "")
        let tld = hostPart.split(separator: ".").last.map { String($0).lowercased() } ?? ""
        let plainDomainOK = common.contains(tld.split(separator: ":").first.map(String.init) ?? tld)
        guard t.range(of: "^" + host + rest + "$", options: [.regularExpression, .caseInsensitive]) != nil,
              hasPathOrWWW || plainDomainOK else { return text }
        return "https://" + t
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
