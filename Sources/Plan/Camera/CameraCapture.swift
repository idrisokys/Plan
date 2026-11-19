import SwiftUI
import AppKit
import AVFoundation

/// Çekilen resim ve videoların kaydedildiği klasör: İndirilenler (Downloads).
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

/// Resim çek / video çek penceresi. Çekilenler İndirilenler klasörüne kaydedilir.
@MainActor
enum CameraWindow {
    enum Mode { case photo, video }
    private static var controller: Controller?

    static func open(_ mode: Mode) {
        controller?.window.close()
        NSApp.activate(ignoringOtherApps: true)
        let c = Controller(mode: mode)
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
        let window: NSWindow

        init(mode: Mode) {
            model = CameraModel(mode: mode)
            let host = NSHostingView(rootView: CameraView(model: model))
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
            super.init()
            window.title = mode == .photo ? L("Resim çek", "Take photo") : L("Video çek", "Record video")
            window.contentView = host
            window.minSize = NSSize(width: 360, height: 300)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = .black
            window.level = .floating
            window.center()
            window.delegate = self
        }

        func windowWillClose(_ notification: Notification) {
            model.shutdown()
            CameraWindow.closed(self)
        }
    }
}

@MainActor
final class CameraModel: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate {
    let mode: CameraWindow.Mode
    let session = AVCaptureSession()
    private let photoOut = AVCapturePhotoOutput()
    private let movieOut = AVCaptureMovieFileOutput()
    private let queue = DispatchQueue(label: "plan.camera.session")
    private var timer: Timer?
    private var closing = false

    @Published var isRecording = false
    @Published var seconds = 0
    @Published var error: String?

    init(mode: CameraWindow.Mode) {
        self.mode = mode
        super.init()
    }

    // MARK: Başlat
    func start() {
        AVCaptureDevice.requestAccess(for: .video) { ok in
            Task { @MainActor in
                guard ok else {
                    self.error = L("Kamera izni verilmemiş. Sistem Ayarları > Gizlilik ve Güvenlik > Kamera'dan Plan'a izin ver.",
                                   "Camera access denied. Allow Plan in System Settings > Privacy & Security > Camera.")
                    return
                }
                if self.mode == .video {
                    AVCaptureDevice.requestAccess(for: .audio) { _ in
                        Task { @MainActor in self.configure() }
                    }
                } else {
                    self.configure()
                }
            }
        }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = mode == .photo ? .photo : .high

        guard let cam = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: cam),
              session.canAddInput(input) else {
            session.commitConfiguration()
            error = L("Kamera bulunamadı", "No camera found")
            return
        }
        session.addInput(input)

        // Video: mikrofon izni varsa sesli kaydet, yoksa sessiz devam et
        if mode == .video,
           AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
           let mic = AVCaptureDevice.default(for: .audio),
           let micInput = try? AVCaptureDeviceInput(device: mic),
           session.canAddInput(micInput) {
            session.addInput(micInput)
        }

        if mode == .photo {
            if session.canAddOutput(photoOut) { session.addOutput(photoOut) }
        } else {
            if session.canAddOutput(movieOut) { session.addOutput(movieOut) }
        }
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
            let name = url.lastPathComponent
            Task { @MainActor in HUD.show(L("İndirilenler'e kaydedildi: ", "Saved to Downloads: ") + name) }
        } catch {
            Task { @MainActor in HUD.show(L("Kaydedilemedi", "Could not save")) }
        }
    }

    // MARK: Video
    func toggleRecording() {
        if isRecording {
            movieOut.stopRecording()
        } else {
            guard session.isRunning, !movieOut.isRecording else { return }
            let url = MediaDir.newURL(prefix: "Plan", ext: "mov")
            movieOut.startRecording(to: url, recordingDelegate: self)
            isRecording = true
            seconds = 0
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.seconds += 1 }
            }
        }
    }

    nonisolated func fileOutput(_ output: AVCaptureFileOutput,
                                didFinishRecordingTo outputFileURL: URL,
                                from connections: [AVCaptureConnection],
                                error: Error?) {
        // Hata olsa bile kayıt başarıyla bitmiş olabilir (ör. disk dolmadan durdurma)
        var ok = error == nil
        if let e = error as NSError?,
           let finished = e.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool {
            ok = finished
        }
        let name = outputFileURL.lastPathComponent
        Task { @MainActor in
            self.timer?.invalidate()
            self.timer = nil
            self.isRecording = false
            HUD.show(ok ? L("İndirilenler'e kaydedildi: ", "Saved to Downloads: ") + name
                        : L("Video kaydedilemedi", "Could not save video"))
            if self.closing { self.stopSession() }
        }
    }

    // MARK: Kapat
    func shutdown() {
        closing = true
        if isRecording {
            movieOut.stopRecording()      // bitince delegate oturumu kapatır
        } else {
            stopSession()
        }
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
        ZStack(alignment: .bottom) {
            Color.black
            CameraPreview(session: model.session)
            if let e = model.error {
                Text(e)
                    .font(.system(size: 14)).foregroundStyle(.white)
                    .multilineTextAlignment(.center).padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            controls
        }
    }

    private var controls: some View {
        VStack(spacing: 6) {
            if model.isRecording {
                Text(String(format: "%02d:%02d", model.seconds / 60, model.seconds % 60))
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Color.red.opacity(0.85)))
            }
            Button {
                if model.mode == .photo { model.takePhoto() } else { model.toggleRecording() }
            } label: {
                ZStack {
                    Circle().stroke(Color.white, lineWidth: 3).frame(width: 64, height: 64)
                    if model.mode == .photo {
                        Circle().fill(Color.white).frame(width: 52, height: 52)
                    } else if model.isRecording {
                        RoundedRectangle(cornerRadius: 6).fill(Color.red).frame(width: 28, height: 28)
                    } else {
                        Circle().fill(Color.red).frame(width: 52, height: 52)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(model.error != nil)
            .help(model.mode == .photo ? L("Resim çek", "Take photo")
                  : (model.isRecording ? L("Kaydı durdur", "Stop recording") : L("Kaydı başlat", "Start recording")))
        }
        .padding(.bottom, 16)
    }
}
