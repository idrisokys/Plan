import AppKit

/// Tuş kombinasyonunu yakalayan kutu: tıkla ya da pencere açılınca dinler, basılan kombinasyonu bildirir.
private final class RecorderView: NSView {
    var onCapture: ((Shortcut) -> Void)?
    var onCancel: (() -> Void)?
    var onInvalid: (() -> Void)?
    var onActivate: (() -> Void)?
    var text = "" { didSet { needsDisplay = true } }
    var recording = true { didSet { needsDisplay = true } }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8)
        (recording ? NSColor.controlAccentColor.withAlphaComponent(0.12) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = recording ? 2 : 1
        path.stroke()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: recording ? 14 : 22, weight: .medium),
            .foregroundColor: recording ? NSColor.secondaryLabelColor : NSColor.labelColor
        ]
        let s = NSAttributedString(string: text, attributes: attrs)
        let size = s.size()
        s.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
    }

    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self); onActivate?() }

    /// ⌘ ile başlayan kombinasyonlar önce buraya gelir; uygulamanın kendi menü kısayollarına kaçmasın.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording, window?.firstResponder === self else { return false }
        handle(event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        handle(event)
    }

    private func handle(_ e: NSEvent) {
        if e.keyCode == 53, e.modifierFlags.intersection(Shortcut.relevant).isEmpty {   // Esc
            onCancel?(); return
        }
        if let s = Shortcut.from(event: e) { onCapture?(s) } else { onInvalid?() }
    }
}

/// Menü çubuğu simgesinden açılan "Kısayollar" penceresi: iki kısayol (Cihazlara Gönder, Notlarıma Kaydet).
/// Her biri için yeni tuşa basarak değiştirir, kapatır ya da sıfırlarsın.
@MainActor
final class ShortcutSettings: NSObject, NSWindowDelegate {
    static let shared = ShortcutSettings()

    private final class Row {
        let action: QuickCapture.Action
        let recorder = RecorderView(frame: NSRect(x: 0, y: 0, width: 300, height: 48))
        let hint = NSTextField(wrappingLabelWithString: "")
        let toggleBtn = NSButton(title: "", target: nil, action: nil)
        init(_ a: QuickCapture.Action) { action = a }
    }

    private var window: NSPanel?
    private var rows: [Row] = []

    func show() {
        if window == nil { build() }
        QuickCapture.suspend()               // aynı kombinasyona basınca kısayol çalışmasın, tuş yakalayıcıya ulaşsın
        rows.forEach { refresh($0) }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    private func row(for tag: Int) -> Row? { rows.first { Int($0.action.rawValue) == tag } }

    private func build() {
        let w = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 420),
                        styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = L("Kısayollar", "Shortcuts")
        w.isReleasedWhenClosed = false
        w.level = .floating
        w.delegate = self

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        for a in QuickCapture.Action.allCases {
            let r = Row(a)
            rows.append(r)

            let title = NSTextField(labelWithString: a.title)
            title.font = .systemFont(ofSize: 13, weight: .semibold)
            let detail = NSTextField(wrappingLabelWithString: a.detail)
            detail.font = .systemFont(ofSize: 11)
            detail.textColor = .secondaryLabelColor

            r.recorder.translatesAutoresizingMaskIntoConstraints = false
            r.recorder.onActivate = { [weak self, weak r] in if let r { self?.startRecording(r) } }
            r.recorder.onCapture = { [weak self, weak r] s in if let r { self?.apply(s, to: r) } }
            r.recorder.onCancel = { [weak self, weak r] in if let r { self?.refresh(r) } }
            r.recorder.onInvalid = { [weak r] in
                r?.hint.stringValue = L("En az bir değiştirici tuş (⌃ ⌥ ⌘) ile birlikte bas.",
                                        "Include at least one modifier key (⌃ ⌥ ⌘).")
            }
            r.hint.font = .systemFont(ofSize: 11)
            r.hint.textColor = .secondaryLabelColor
            r.hint.alignment = .center

            let change = NSButton(title: L("Değiştir", "Change"), target: self, action: #selector(changeTapped(_:)))
            let reset = NSButton(title: L("Sıfırla", "Reset"), target: self, action: #selector(resetTapped(_:)))
            r.toggleBtn.target = self
            r.toggleBtn.action = #selector(toggleTapped(_:))
            for b in [change, reset, r.toggleBtn] { b.bezelStyle = .rounded; b.tag = Int(a.rawValue) }
            let btns = NSStackView(views: [change, reset, r.toggleBtn])
            btns.spacing = 8

            for v in [title, detail, r.recorder, r.hint, btns] { stack.addArrangedSubview(v) }
            NSLayoutConstraint.activate([
                detail.widthAnchor.constraint(equalToConstant: 300),
                r.recorder.widthAnchor.constraint(equalToConstant: 300),
                r.recorder.heightAnchor.constraint(equalToConstant: 48),
                r.hint.widthAnchor.constraint(equalToConstant: 300)
            ])
            stack.setCustomSpacing(18, after: btns)
        }

        let done = NSButton(title: L("Tamam", "Done"), target: self, action: #selector(doneTapped))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        stack.addArrangedSubview(done)

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor)
        ])
        w.contentView = content
        window = w
    }

    // MARK: Durum

    private func refresh(_ r: Row) {
        r.recorder.recording = false
        r.recorder.text = QuickCapture.display(r.action)
        r.toggleBtn.title = QuickCapture.enabled(r.action) ? L("Kapat", "Turn Off") : L("Aç", "Turn On")
        r.hint.stringValue = ""
    }

    private func startRecording(_ r: Row) {
        rows.forEach { if $0 !== r { refresh($0) } }
        r.recorder.recording = true
        r.recorder.text = L("Yeni kısayola bas…  (Esc: vazgeç)", "Press new shortcut…  (Esc: cancel)")
        r.hint.stringValue = ""
        window?.makeFirstResponder(r.recorder)
    }

    private func apply(_ s: Shortcut, to r: Row) {
        // Diğer kısayolla aynı kombinasyon olmasın.
        if let other = rows.first(where: { $0 !== r && QuickCapture.enabled($0.action) && QuickCapture.shortcut($0.action) == s }) {
            r.hint.stringValue = L("Bu kombinasyon “\(other.action.title)” için kullanılıyor.",
                                   "This combination is used by “\(other.action.title)”.")
            return
        }
        QuickCapture.setShortcut(s, for: r.action)
        QuickCapture.setEnabled(true, for: r.action)
        refresh(r)
        r.hint.stringValue = L("Kaydedildi.", "Saved.")
    }

    // MARK: Düğmeler

    @objc private func changeTapped(_ sender: NSButton) { if let r = row(for: sender.tag) { startRecording(r) } }

    @objc private func resetTapped(_ sender: NSButton) {
        guard let r = row(for: sender.tag) else { return }
        let d = r.action.defaultShortcut
        if let other = rows.first(where: { $0 !== r && QuickCapture.enabled($0.action) && QuickCapture.shortcut($0.action) == d }) {
            r.hint.stringValue = L("Varsayılan, “\(other.action.title)” tarafından kullanılıyor.",
                                   "Default is used by “\(other.action.title)”.")
            return
        }
        QuickCapture.setShortcut(d, for: r.action)
        QuickCapture.setEnabled(true, for: r.action)
        refresh(r)
        r.hint.stringValue = L("Varsayılana döndü.", "Reset to default.")
    }

    @objc private func toggleTapped(_ sender: NSButton) {
        guard let r = row(for: sender.tag) else { return }
        QuickCapture.setEnabled(!QuickCapture.enabled(r.action), for: r.action)
        refresh(r)
    }

    @objc private func doneTapped() { window?.close() }

    /// Pencere kapanınca kısayolları (ayarlara göre) yeniden etkinleştirir.
    func windowWillClose(_ notification: Notification) {
        rows.forEach { refresh($0) }
        let failed = QuickCapture.apply()
        if !failed.isEmpty {
            HUD.show(L("Kaydedilemeyen kısayol: ", "Couldn't register: ") + failed.map { $0.title }.joined(separator: ", ")
                     + L(" (başka uygulama kullanıyor olabilir)", " (another app may be using it)"))
        }
    }
}
