import AppKit

/// Tuş kombinasyonunu yakalayan kutu: tıkla ya da pencere açılınca dinler, basılan kombinasyonu bildirir.
private final class RecorderView: NSView {
    var onCapture: ((Shortcut) -> Void)?
    var onCancel: (() -> Void)?
    var onInvalid: (() -> Void)?
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

    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }

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

/// Menü çubuğu simgesinden açılan "Kısayol" penceresi: kısayolu görür, yeni tuşa basarak değiştirir, kapatır ya da sıfırlar.
@MainActor
final class ShortcutSettings: NSObject, NSWindowDelegate {
    static let shared = ShortcutSettings()

    private var window: NSPanel?
    private let recorder = RecorderView(frame: NSRect(x: 0, y: 0, width: 300, height: 56))
    private let hint = NSTextField(wrappingLabelWithString: "")
    private let toggleBtn = NSButton(title: "", target: nil, action: nil)

    func show() {
        if window == nil { build() }
        QuickCapture.suspend()               // aynı kombinasyona basınca kısayol çalışmasın, tuş yakalayıcıya ulaşsın
        refresh()
        startRecording()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(recorder)
    }

    private func build() {
        let w = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 228),
                        styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = L("Hızlı Kaydet Kısayolu", "Quick Save Shortcut")
        w.isReleasedWhenClosed = false
        w.level = .floating
        w.delegate = self

        let title = NSTextField(wrappingLabelWithString:
            L("Herhangi bir uygulamada metin ya da link seç, bu kısayola bas: Notlarım'a kaydedilir.",
              "Select text or a link in any app and press this shortcut to save it to My Notes."))
        title.font = .systemFont(ofSize: 12)
        title.textColor = .secondaryLabelColor

        recorder.onCapture = { [weak self] s in self?.apply(s) }
        recorder.onCancel = { [weak self] in self?.refresh(); self?.recorder.recording = false }
        recorder.onInvalid = { [weak self] in
            self?.hint.stringValue = L("En az bir değiştirici tuş (⌃ ⌥ ⌘) ile birlikte bas.",
                                       "Include at least one modifier key (⌃ ⌥ ⌘).")
        }

        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.alignment = .center

        let change = NSButton(title: L("Değiştir", "Change"), target: self, action: #selector(changeTapped))
        let reset = NSButton(title: L("Sıfırla (⌃⌥N)", "Reset (⌃⌥N)"), target: self, action: #selector(resetTapped))
        toggleBtn.target = self
        toggleBtn.action = #selector(toggleTapped)
        let done = NSButton(title: L("Tamam", "Done"), target: self, action: #selector(doneTapped))
        done.keyEquivalent = "\r"
        for b in [change, reset, toggleBtn, done] { b.bezelStyle = .rounded }

        let row = NSStackView(views: [change, reset, toggleBtn])
        row.spacing = 8
        let stack = NSStackView(views: [title, recorder, hint, row, done])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        recorder.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            title.widthAnchor.constraint(equalToConstant: 300),
            recorder.widthAnchor.constraint(equalToConstant: 300),
            recorder.heightAnchor.constraint(equalToConstant: 56),
            hint.widthAnchor.constraint(equalToConstant: 300)
        ])
        w.contentView = content
        window = w
    }

    // MARK: Durum

    private func refresh() {
        recorder.recording = false
        recorder.text = QuickCapture.enabled ? QuickCapture.shortcut.display : L("Kapalı", "Off")
        toggleBtn.title = QuickCapture.enabled ? L("Kapat", "Turn Off") : L("Aç", "Turn On")
        hint.stringValue = ""
    }

    private func startRecording() {
        recorder.recording = true
        recorder.text = L("Yeni kısayola bas…  (Esc: vazgeç)", "Press new shortcut…  (Esc: cancel)")
        hint.stringValue = ""
        window?.makeFirstResponder(recorder)
    }

    private func apply(_ s: Shortcut) {
        QuickCapture.shortcut = s
        QuickCapture.enabled = true
        refresh()
        if !QuickCapture.apply() {
            // Başka bir uygulama (ya da sistem) bu kombinasyonu zaten kullanıyor.
            hint.stringValue = L("Bu kısayol başka bir uygulamada kullanımda olabilir; başka bir tane dene.",
                                 "This shortcut may be taken by another app; try a different one.")
            QuickCapture.suspend()
        } else {
            QuickCapture.suspend()      // pencere açıkken kapalı kalsın; kapanınca yeniden etkinleşir
            hint.stringValue = L("Kaydedildi.", "Saved.")
        }
    }

    // MARK: Düğmeler

    @objc private func changeTapped() { startRecording() }

    @objc private func resetTapped() {
        QuickCapture.shortcut = .default
        QuickCapture.enabled = true
        refresh()
        hint.stringValue = L("Varsayılana döndü.", "Reset to default.")
    }

    @objc private func toggleTapped() {
        QuickCapture.enabled.toggle()
        refresh()
    }

    @objc private func doneTapped() { window?.close() }

    /// Pencere kapanınca kısayolu (ayara göre) yeniden etkinleştirir.
    func windowWillClose(_ notification: Notification) {
        if !QuickCapture.apply() {
            HUD.show(L("Kısayol kaydedilemedi; başka uygulama kullanıyor olabilir",
                       "Couldn't register shortcut; another app may be using it"))
        }
    }
}
