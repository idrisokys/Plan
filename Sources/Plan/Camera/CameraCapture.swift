import SwiftUI
import AppKit
import AVFoundation

/// Çekilen resimlerin kaydedildiği klasör: İndirilenler (Downloads).
enum MediaDir {
    static var downloads: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Downloads")
    }

    /// Plan_20260119_153000.jpg gibi; aynı ada denk gelirse sonuna sayı eklenir.
    static func newURL(prefix: String, ext: String) -> URL {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        let stamp = f.string(from: Date())
        var url = downloads.appendingPathComponent("\(prefix)_\(stamp).\(ext)")
        var i = 1
        while FileManager.default.fileExists(atPath: url.path) {
            url = downloads.appendingPathComponent("\(prefix)_\(stamp)_\(i).\(ext)")
            i += 1
        }
        return url
    }
}

/// Boşluk (Space) tuşunu yakalayan kamera penceresi.
@MainActor
private final class CameraNSWindow: NSWindow {
    var onSpace: (() -> Void)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 49, !event.isARepeat,
           event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
            onSpace?()
            return
        }
        super.sendEvent(event)
    }
}

/// Çekilen resim: dosya ve küçük önizleme.
struct Shot: Identifiable {
    let id = UUID()
    let url: URL
    let thumb: NSImage
}

/// Resim çek penceresi. Çekilenler İndirilenler klasörüne kaydedilir.
@MainActor
enum CameraWindow {
    private static var controller: Controller?

    static func open() {
        controller?.window.close()
        NSApp.activate(ignoringOtherApps: true)
        let c = Controller()
        controller = c
        c.model.start()
        c.window.makeKeyAndOrderFront(nil)
    }

    fileprivate static func closed(_ c: Controller) {
        if controller === c { controller = nil }
    }

    @MainActor
    fileprivate final class Controller: NSObject, NSWindowDelegate {
        let model: CameraModel
        let window: CameraNSWindow

        override init() {
            model = CameraModel()
            let host = NSHostingView(rootView: CameraView(model: model))
            window = CameraNSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 560),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
            super.init()
            window.title = L("Resim çek", "Take photo")
            window.contentView = host
            window.minSize = NSSize(width: 360, height: 380)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = .black
            window.center()
            window.delegate = self
            window.onSpace = { [weak self] in self?.model.takePhoto() }
        }

        func windowWillClose(_ notification: Notification) {
            model.shutdown()
            CameraWindow.closed(self)
        }
    }
}

@MainActor
final class CameraModel: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let photoOut = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "plan.camera.session")
    @Published var error: String?
    @Published var shots: [Shot] = []

    // MARK: Başlat
    func start() {
        AVCaptureDevice.requestAccess(for: .video) { ok in
            Task { @MainActor in
                guard ok else {
                    self.error = L("Kamera izni verilmemiş. Sistem Ayarları > Gizlilik ve Güvenlik > Kamera'dan Plan'a izin ver.",
                                   "Camera access denied. Allow Plan in System Settings > Privacy & Security > Camera.")
                    return
                }
                self.configure()
            }
        }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let cam = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: cam),
              session.canAddInput(input) else {
            session.commitConfiguration()
            error = L("Kamera bulunamadı", "No camera found")
            return
        }
        session.addInput(input)

        if session.canAddOutput(photoOut) { session.addOutput(photoOut) }
        session.commitConfiguration()

        let s = session
        queue.async { s.startRunning() }
    }

    // MARK: Resim
    func takePhoto() {
        guard session.isRunning else { return }
        var settings = AVCapturePhotoSettings()
        if photoOut.availablePhotoCodecTypes.contains(.jpeg) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        }
        photoOut.capturePhoto(with: settings, delegate: self)
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else {
            Task { @MainActor in HUD.show(L("Resim çekilemedi", "Could not take photo")) }
            return
        }
        let url = MediaDir.newURL(prefix: "Plan", ext: "jpg")
        do {
            try data.write(to: url)
            Task { @MainActor in
                if let img = NSImage(data: data) { self.shots.append(Shot(url: url, thumb: img)) }
            }
        } catch {
            Task { @MainActor in HUD.show(L("Kaydedilemedi", "Could not save")) }
        }
    }

    // MARK: Kapat
    func shutdown() {
        stopSession()
    }

    private func stopSession() {
        let s = session
        queue.async { if s.isRunning { s.stopRunning() } }
    }
}

// MARK: Arayüz
private final class PreviewNSView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        previewLayer.videoGravity = .resizeAspect
        layer?.addSublayer(previewLayer)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }
}

private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let v = PreviewNSView()
        v.previewLayer.session = session
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct CameraView: View {
    @ObservedObject var model: CameraModel

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                CameraPreview(session: model.session)
                if let e = model.error {
                    Text(e)
                        .font(.system(size: 14)).foregroundStyle(.white)
                        .multilineTextAlignment(.center).padding(24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            strip
        }
        .background(Color.black)
    }

    /// Photo Booth gibi alttaki önizleme şeridi: küçük resme tıklayınca resim düzenleyicide açılır.
    private var strip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if model.shots.isEmpty {
                        Text(L("Resim çekmek için Boşluk (Space) tuşuna bas", "Press Space to take a photo"))
                            .font(.system(size: 13)).foregroundStyle(.white.opacity(0.55))
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(model.shots) { shot in
                        Image(nsImage: shot.thumb)
                            .resizable().scaledToFill()
                            .frame(width: 80, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.25), lineWidth: 1))
                            .contentShape(Rectangle())
                            .onTapGesture { ImageEditorWindow.open(shot.url) }
                            .help(L("Düzenlemek için tıkla", "Click to edit"))
                            .id(shot.id)
                    }
                }
                .padding(.horizontal, 10)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 80)
            }
            .onChange(of: model.shots.count) { _, _ in
                if let last = model.shots.last { withAnimation { proxy.scrollTo(last.id) } }
            }
        }
        .frame(height: 80)
        .background(Color(white: 0.08))
    }
}
