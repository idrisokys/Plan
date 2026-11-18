import SwiftUI
import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers

// Resim düzenleyici (Android'deki "Temel Düzenleyici"nin macOS karşılığı):
// filtreler, kırpma (serbest / 1:1 / 4:3 / 16:9 / özel), döndürme, aynalama, yeniden boyutlandırma,
// serbest çizim (renk, fırça boyutu), geri al, farklı kaydet / üzerine yaz.

enum EditorTool { case filter, crop, draw }

/// Çizim darbesi; noktalar görüntü piksel koordinatındadır (başlangıç sol-üst).
struct EditorStroke {
    var points: [CGPoint]
    var color: NSColor
    var width: CGFloat          // piksel
}

enum CropAspect: String, CaseIterable, Identifiable {
    case free, square, fourThree, sixteenNine, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .free: return L("Serbest", "Free")
        case .square: return "1:1"
        case .fourThree: return "4:3"
        case .sixteenNine: return "16:9"
        case .custom: return L("Özel", "Custom")
        }
    }
}

/// Kırpma çerçevesinin hangi kenarı / köşesi tutuldu.
struct CropHandle {
    var l = false, r = false, t = false, b = false, move = false
    var isNone: Bool { !(l || r || t || b || move) }
}

struct EditorFilter {
    let name: String
    let apply: (CIImage) -> CIImage
}

enum EditorFilters {
    private static func f(_ name: String, _ img: CIImage, _ params: [String: Any] = [:]) -> CIImage {
        guard let flt = CIFilter(name: name) else { return img }
        flt.setValue(img, forKey: kCIInputImageKey)
        for (k, v) in params { flt.setValue(v, forKey: k) }
        return flt.outputImage?.cropped(to: img.extent) ?? img
    }

    private static func tint(_ img: CIImage, r: CGFloat, g: CGFloat, b: CGFloat) -> CIImage {
        f("CIColorMatrix", img, [
            "inputRVector": CIVector(x: r, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: g, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: b, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
        ])
    }

    static let all: [EditorFilter] = [
        EditorFilter(name: L("Yok", "None")) { $0 },
        EditorFilter(name: L("Siyah-Beyaz", "B&W")) { f("CIPhotoEffectMono", $0) },
        EditorFilter(name: "Noir") { f("CIPhotoEffectNoir", $0) },
        EditorFilter(name: L("Sepya", "Sepia")) { f("CISepiaTone", $0, ["inputIntensity": 0.9]) },
        EditorFilter(name: L("Klasik", "Instant")) { f("CIPhotoEffectInstant", $0) },
        EditorFilter(name: L("Solgun", "Fade")) { f("CIPhotoEffectFade", $0) },
        EditorFilter(name: "Chrome") { f("CIPhotoEffectChrome", $0) },
        EditorFilter(name: L("Soğuk", "Cool")) { tint($0, r: 0.9, g: 1.0, b: 1.12) },
        EditorFilter(name: L("Sıcak", "Warm")) { tint($0, r: 1.12, g: 1.02, b: 0.88) },
        EditorFilter(name: L("Kontrast", "Contrast")) { f("CIColorControls", $0, ["inputContrast": 1.35, "inputSaturation": 1.05]) },
        EditorFilter(name: L("Canlı", "Vivid")) { f("CIColorControls", $0, ["inputSaturation": 1.6, "inputContrast": 1.05]) },
        EditorFilter(name: L("Parlak", "Bright")) { f("CIColorControls", $0, ["inputBrightness": 0.12, "inputContrast": 1.05]) },
        EditorFilter(name: L("Keskin", "Sharp")) { f("CISharpenLuminance", $0, ["inputSharpness": 0.9]) },
        EditorFilter(name: L("Vinyet", "Vignette")) { f("CIVignette", $0, ["inputIntensity": 1.2, "inputRadius": 2.0]) },
        EditorFilter(name: L("Negatif", "Negative")) { f("CIColorInvert", $0) }
    ]
}

@MainActor
final class ImageEditorModel: ObservableObject {
    struct Snapshot { let image: CGImage; let strokes: [EditorStroke]; let filter: Int }

    @Published private(set) var sourceURL: URL
    private(set) var folderImages: [URL] = []
    var title: String { sourceURL.lastPathComponent }

    @Published private(set) var current: CGImage          // filtre ve çizim hariç temel görüntü
    @Published private(set) var display: CGImage          // filtre uygulanmış görünüm
    @Published private(set) var thumbs: [CGImage] = []
    @Published var strokes: [EditorStroke] = []
    @Published var liveStroke: EditorStroke?
    @Published var filterIndex = 0
    @Published var tool: EditorTool? = nil          // başlangıçta hiçbir panel açık değil
    @Published var cropRect: CGRect = .zero
    @Published var aspect: CropAspect = .free
    @Published var customX: Double = 3
    @Published var customY: Double = 2
    @Published var brushColor: Color = .red
    @Published var brushSize: Double = 8                  // ekran noktası
    @Published var resizeW = 0
    @Published var resizeH = 0
    @Published var keepRatio = true
    @Published private(set) var undoCount = 0
    private(set) var dirty = false
    private var undoStack: [Snapshot] = []

    var canUndo: Bool { undoCount > 0 }
    var resizeRatio: Double { Double(current.width) / Double(max(current.height, 1)) }

    init?(url: URL) {
        guard let img = Self.load(url) else { return nil }
        sourceURL = url
        current = img
        display = img
        refreshThumbs()
        setAspect(.free)
        folderImages = Self.imagesInFolder(of: url)
    }

    // MARK: Klasördeki resimler arasında gezinme
    var canNavigate: Bool { folderImages.count > 1 }

    static func imagesInFolder(of url: URL) -> [URL] {
        let dir = url.deletingLastPathComponent()
        let items = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
        let imgs = items.filter { u in
            guard let t = UTType(filenameExtension: u.pathExtension) else { return false }
            return t.conforms(to: .image)
        }
        // En yeni tarihli ilk sırada (değiştirilme tarihine göre); tarih eşitse ada göre
        func date(_ u: URL) -> Date {
            (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        return imgs.sorted {
            let a = date($0), b = date($1)
            if a != b { return a > b }
            return $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    /// delta: -1 daha yeni, +1 daha eski resim (uçlardan sonra başa/sona döner).
    func navigate(_ delta: Int) {
        guard canNavigate,
              let i = folderImages.firstIndex(where: { $0.lastPathComponent == sourceURL.lastPathComponent }) else { return }
        if dirty {
            let a = NSAlert()
            a.messageText = L("Kaydedilmemiş değişiklikler var", "You have unsaved changes")
            a.informativeText = L("Başka resme geçersen düzenlemeler kaybolur.", "Switching images will discard your edits.")
            a.addButton(withTitle: L("Geç", "Switch"))
            a.addButton(withTitle: L("Vazgeç", "Cancel"))
            guard a.runModal() == .alertFirstButtonReturn else { return }
        }
        let n = folderImages.count
        var j = i
        for _ in 0..<(n - 1) {
            j = (j + delta + n) % n
            if replace(with: folderImages[j]) { return }
        }
    }

    private func replace(with url: URL) -> Bool {
        guard let img = Self.load(url) else { return false }
        sourceURL = url
        current = img
        display = img
        strokes = []; liveStroke = nil; filterIndex = 0
        undoStack = []; undoCount = 0; dirty = false
        refreshThumbs()
        setAspect(aspect)
        return true
    }

    // MARK: Çöpe at / taşı / yeniden adlandır
    /// Klasörde gösterilecek resim kalmayınca (pencere kapanır).
    var onEmpty: (() -> Void)?

    private func currentIndex() -> Int? {
        folderImages.firstIndex(where: { $0.lastPathComponent == sourceURL.lastPathComponent })
    }

    /// Geçerli dosya klasörden ayrıldı: sıradaki (daha eski) resme geç, yoksa pencereyi kapat.
    private func removeCurrentAndAdvance() {
        dirty = false
        guard let i = currentIndex() else { onEmpty?(); return }
        folderImages.remove(at: i)
        guard !folderImages.isEmpty else { onEmpty?(); return }
        var j = min(i, folderImages.count - 1)
        for _ in 0..<folderImages.count {
            if replace(with: folderImages[j]) { return }
            j = (j + 1) % folderImages.count
        }
        onEmpty?()
    }

    func trash() {
        do {
            try FileManager.default.trashItem(at: sourceURL, resultingItemURL: nil)
            HUD.show(L("Çöp Kutusu'na taşındı", "Moved to Trash"))
            removeCurrentAndAdvance()
        } catch {
            HUD.show(L("Çöpe atılamadı", "Could not move to Trash"))
        }
    }

    func move() {
        NSApp.activate(ignoringOtherApps: true)
        let p = NSOpenPanel()
        p.canChooseFiles = false
        p.canChooseDirectories = true
        p.canCreateDirectories = true
        p.allowsMultipleSelection = false
        p.directoryURL = sourceURL.deletingLastPathComponent()
        p.prompt = L("Buraya taşı", "Move here")
        p.message = L("Resmin taşınacağı klasörü seç", "Choose the folder to move the image to")
        guard p.runModal() == .OK, let dir = p.url else { return }
        if dir.standardizedFileURL == sourceURL.deletingLastPathComponent().standardizedFileURL { return }
        var dest = dir.appendingPathComponent(sourceURL.lastPathComponent)
        var n = 2
        let base = sourceURL.deletingPathExtension().lastPathComponent, ext = sourceURL.pathExtension
        while FileManager.default.fileExists(atPath: dest.path) {          // aynı ada sahip dosya varsa numara ekle
            dest = dir.appendingPathComponent("\(base) \(n)" + (ext.isEmpty ? "" : "." + ext))
            n += 1
        }
        do {
            try FileManager.default.moveItem(at: sourceURL, to: dest)
            HUD.show(L("Taşındı: ", "Moved to: ") + dir.lastPathComponent)
            removeCurrentAndAdvance()
        } catch {
            HUD.show(L("Taşınamadı", "Could not move"))
        }
    }

    func rename() {
        let ext = sourceURL.pathExtension
        let a = NSAlert()
        a.messageText = L("Adı değiştir", "Rename")
        a.informativeText = ext.isEmpty ? "" : L("Uzantı (.\(ext)) korunur.", "The extension (.\(ext)) is kept.")
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        tf.stringValue = sourceURL.deletingPathExtension().lastPathComponent
        a.accessoryView = tf
        a.addButton(withTitle: L("Değiştir", "Rename"))
        a.addButton(withTitle: L("Vazgeç", "Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        a.window.initialFirstResponder = tf
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let name = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/"), !name.contains(":") else {
            HUD.show(L("Geçersiz ad", "Invalid name")); return
        }
        let dest = sourceURL.deletingLastPathComponent()
            .appendingPathComponent(ext.isEmpty ? name : name + "." + ext)
        if dest.lastPathComponent == sourceURL.lastPathComponent { return }
        guard !FileManager.default.fileExists(atPath: dest.path) else {
            HUD.show(L("Bu adla bir dosya var", "A file with this name already exists")); return
        }
        do {
            let i = currentIndex()
            try FileManager.default.moveItem(at: sourceURL, to: dest)
            if let i = i { folderImages[i] = dest }
            sourceURL = dest                                  // düzenlemeler korunur, başlık güncellenir
            HUD.show(L("Ad değiştirildi", "Renamed"))
        } catch {
            HUD.show(L("Ad değiştirilemedi", "Could not rename"))
        }
    }

    // MARK: Paylaş
    private var sharePicker: NSSharingServicePicker?

    /// Düzenlenmiş resmi geçici dosyaya yazıp macOS paylaşım menüsünü sağ üstte açar.
    func share() {
        let ext = sourceURL.pathExtension.lowercased()
        let useJpeg = ext == "jpg" || ext == "jpeg"
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PlanEditorShare", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(sourceURL.deletingPathExtension().lastPathComponent + (useJpeg ? ".jpg" : ".png"))
        try? FileManager.default.removeItem(at: url)
        guard save(to: url), let view = NSApp.keyWindow?.contentView else {
            HUD.show(L("Paylaşılamadı", "Could not share")); return
        }
        let picker = NSSharingServicePicker(items: [url])
        sharePicker = picker
        let b = view.bounds
        let anchor = NSRect(x: b.maxX - 48, y: b.maxY - 52, width: 36, height: 36)
        picker.show(relativeTo: anchor, of: view, preferredEdge: .minY)
    }

    // MARK: Yükleme
    /// EXIF yönünü uygulayarak tam çözünürlükte yükler.
    static func load(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        var maxDim = 8192
        if let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int {
            maxDim = max(w, h)
        }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDim
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
            ?? CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    // MARK: Geri al
    func pushUndo() {
        undoStack.append(Snapshot(image: current, strokes: strokes, filter: filterIndex))
        if undoStack.count > 40 { undoStack.removeFirst() }
        undoCount = undoStack.count
        dirty = true
    }

    func undo() {
        guard let s = undoStack.popLast() else { return }
        current = s.image
        strokes = s.strokes
        filterIndex = s.filter
        undoCount = undoStack.count
        refreshDisplay(); refreshThumbs(); setAspect(aspect)
    }

    // MARK: Görünüm
    private func refreshDisplay() { display = Self.applyFilter(filterIndex, to: current) }

    private func refreshThumbs() {
        let small = Self.scaled(current, maxDim: 128)
        thumbs = (0..<EditorFilters.all.count).map { Self.applyFilter($0, to: small) }
    }

    func selectTool(_ t: EditorTool) {
        if tool == t { tool = nil; return }              // aynı simgeye tekrar basınca panel kapanır
        tool = t
        if t == .crop { setAspect(aspect) }
    }

    // MARK: Filtre
    func selectFilter(_ i: Int) {
        guard i != filterIndex else { return }
        pushUndo()
        filterIndex = i
        refreshDisplay()
    }

    // MARK: Çizim
    func beginStroke(at p: CGPoint, scale: CGFloat) {
        pushUndo()
        liveStroke = EditorStroke(points: [p], color: NSColor(brushColor), width: CGFloat(brushSize) / max(scale, 0.0001))
    }
    func extendStroke(_ p: CGPoint) { liveStroke?.points.append(p) }
    func endStroke() {
        if let s = liveStroke { strokes.append(s) }
        liveStroke = nil
    }

    // MARK: Görüntü işlemleri (önce filtre ve çizimler görüntüye işlenir)
    private func apply(_ op: (CGImage) -> CGImage?) {
        pushUndo()
        if filterIndex != 0 || !strokes.isEmpty {
            current = flattened()
            strokes = []
            filterIndex = 0
        }
        if let r = op(current) { current = r }
        refreshDisplay(); refreshThumbs(); setAspect(aspect)
    }

    func rotateRight() { apply { Self.rotated($0) } }
    func flipHorizontal() { apply { Self.flipped($0, horizontal: true) } }
    func flipVertical() { apply { Self.flipped($0, horizontal: false) } }

    func applyCrop() {
        let full = CGRect(x: 0, y: 0, width: current.width, height: current.height)
        let r = cropRect.integral.intersection(full)
        guard r.width >= 1, r.height >= 1, r != full else { return }
        apply { $0.cropping(to: r) }
    }

    func prepareResize() {
        resizeW = current.width
        resizeH = current.height
    }

    func applyResize() {
        let w = min(max(resizeW, 1), 16000), h = min(max(resizeH, 1), 16000)
        guard w != current.width || h != current.height else { return }
        apply { Self.resized($0, w, h) }
    }

    /// Filtre ve çizimler işlenmiş son görüntü.
    func flattened() -> CGImage {
        let base = display
        guard !strokes.isEmpty else { return base }
        let w = base.width, h = base.height
        guard let ctx = Self.makeContext(w, h) else { return base }
        ctx.draw(base, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for s in strokes {
            guard let first = s.points.first else { continue }
            ctx.setStrokeColor(s.color.cgColor)
            ctx.setLineWidth(s.width)
            let hh = CGFloat(h)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: first.x, y: hh - first.y))
            if s.points.count == 1 { ctx.addLine(to: CGPoint(x: first.x + 0.01, y: hh - first.y)) }
            for p in s.points.dropFirst() { ctx.addLine(to: CGPoint(x: p.x, y: hh - p.y)) }
            ctx.strokePath()
        }
        return ctx.makeImage() ?? base
    }

    // MARK: Kırpma çerçevesi
    var aspectValue: CGFloat? {
        switch aspect {
        case .free: return nil
        case .square: return 1
        case .fourThree: return 4.0 / 3.0
        case .sixteenNine: return 16.0 / 9.0
        case .custom:
            guard customX > 0, customY > 0 else { return 1 }
            return CGFloat(customX / customY)
        }
    }

    /// Oranı ayarlar; çerçeve görüntüye sığan en büyük ortalanmış çerçeve olur.
    func setAspect(_ a: CropAspect) {
        aspect = a
        let W = CGFloat(current.width), H = CGFloat(current.height)
        guard let ar = aspectValue else { cropRect = CGRect(x: 0, y: 0, width: W, height: H); return }
        var w = W, h = W / ar
        if h > H { h = H; w = H * ar }
        cropRect = CGRect(x: (W - w) / 2, y: (H - h) / 2, width: w, height: h)
    }

    func hitCrop(_ p: CGPoint, _ vr: CGRect) -> CropHandle {
        var h = CropHandle()
        let t = min(24, min(vr.width, vr.height) / 3)
        guard vr.insetBy(dx: -t, dy: -t).contains(p) else { return h }
        h.l = abs(p.x - vr.minX) <= t
        h.r = abs(p.x - vr.maxX) <= t
        h.t = abs(p.y - vr.minY) <= t
        h.b = abs(p.y - vr.maxY) <= t
        if h.l && h.r { if abs(p.x - vr.minX) < abs(p.x - vr.maxX) { h.r = false } else { h.l = false } }
        if h.t && h.b { if abs(p.y - vr.minY) < abs(p.y - vr.maxY) { h.b = false } else { h.t = false } }
        if h.isNone { h.move = vr.contains(p) }
        return h
    }

    /// `r0` sürükleme başındaki çerçeve, `d` piksel cinsinden kayma.
    func resized(_ r0: CGRect, _ h: CropHandle, _ d: CGSize) -> CGRect {
        let W = CGFloat(current.width), H = CGFloat(current.height)
        let minS = min(24, min(W, H))
        if h.move {
            let x = min(max(r0.minX + d.width, 0), W - r0.width)
            let y = min(max(r0.minY + d.height, 0), H - r0.height)
            return CGRect(x: x, y: y, width: r0.width, height: r0.height)
        }
        guard let ar = aspectValue else {
            var minX = r0.minX, maxX = r0.maxX, minY = r0.minY, maxY = r0.maxY
            if h.l { minX = min(max(r0.minX + d.width, 0), r0.maxX - minS) }
            if h.r { maxX = max(min(r0.maxX + d.width, W), r0.minX + minS) }
            if h.t { minY = min(max(r0.minY + d.height, 0), r0.maxY - minS) }
            if h.b { maxY = max(min(r0.maxY + d.height, H), r0.minY + minS) }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
        let horizontal = h.l || h.r, vertical = h.t || h.b
        if horizontal && vertical {                     // köşe: karşı köşe sabit
            let ax = h.l ? r0.maxX : r0.minX
            let ay = h.t ? r0.maxY : r0.minY
            let sx: CGFloat = h.l ? -1 : 1, sy: CGFloat = h.t ? -1 : 1
            let cx = (h.l ? r0.minX : r0.maxX) + d.width
            let cy = (h.t ? r0.minY : r0.maxY) + d.height
            var w = max((cx - ax) * sx, minS)
            var hh = max((cy - ay) * sy, minS)
            if w / ar > hh { hh = w / ar } else { w = hh * ar }
            let maxW = sx > 0 ? W - ax : ax
            let maxH = sy > 0 ? H - ay : ay
            if w > maxW { w = maxW; hh = w / ar }
            if hh > maxH { hh = maxH; w = hh * ar }
            return CGRect(x: sx > 0 ? ax : ax - w, y: sy > 0 ? ay : ay - hh, width: w, height: hh)
        }
        if horizontal {                                  // sol / sağ kenar: yükseklik ortadan oranla uyar
            let newW = h.r ? r0.width + d.width : r0.width - d.width
            let maxW = h.r ? W - r0.minX : r0.maxX
            let midY = r0.midY
            let maxH = 2 * min(midY, H - midY)
            let w = min(max(newW, minS), min(maxW, maxH * ar))
            let hh = w / ar
            return CGRect(x: h.r ? r0.minX : r0.maxX - w, y: midY - hh / 2, width: w, height: hh)
        }
        let newH = h.b ? r0.height + d.height : r0.height - d.height      // üst / alt kenar
        let maxH = h.b ? H - r0.minY : r0.maxY
        let midX = r0.midX
        let maxW = 2 * min(midX, W - midX)
        let hh = min(max(newH, minS), min(maxH, maxW / ar))
        let w = hh * ar
        return CGRect(x: midX - w / 2, y: h.b ? r0.minY : r0.maxY - hh, width: w, height: hh)
    }

    // MARK: Kaydet / kopyala
    func copyToClipboard() {
        let img = NSImage(cgImage: flattened(), size: .zero)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([img])
        HUD.show(L("Panoya kopyalandı", "Copied to clipboard"))
    }

    func overwrite() {
        let alert = NSAlert()
        alert.messageText = L("Orijinal dosyanın üzerine yazılsın mı?", "Overwrite the original file?")
        alert.informativeText = sourceURL.path
        alert.addButton(withTitle: L("Üzerine yaz", "Overwrite"))
        alert.addButton(withTitle: L("Vazgeç", "Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        finishSave(save(to: sourceURL), sourceURL)
    }

    func saveAs() {
        NSApp.activate(ignoringOtherApps: true)
        let p = NSSavePanel()
        p.allowedContentTypes = [.png, .jpeg, .heic, .tiff]
        p.canCreateDirectories = true
        p.directoryURL = sourceURL.deletingLastPathComponent()
        let okExt = ["png", "jpg", "jpeg", "heic", "tif", "tiff"]
        let ext = okExt.contains(sourceURL.pathExtension.lowercased()) ? sourceURL.pathExtension : "png"
        p.nameFieldStringValue = sourceURL.deletingPathExtension().lastPathComponent
            + "-" + L("düzenlendi", "edited") + "." + ext
        guard p.runModal() == .OK, var u = p.url else { return }
        if u.pathExtension.isEmpty { u.appendPathExtension("png") }
        finishSave(save(to: u), u)
    }

    private func finishSave(_ ok: Bool, _ url: URL) {
        if ok { dirty = false; HUD.show(L("Kaydedildi: ", "Saved: ") + url.lastPathComponent) }
        else { HUD.show(L("Kaydedilemedi (png, jpg, heic, tiff desteklenir)", "Could not save (png, jpg, heic, tiff supported)")) }
    }

    /// Uzantıya göre biçim seçer.
    private func save(to url: URL) -> Bool {
        let type: UTType
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": type = .jpeg
        case "heic": type = .heic
        case "tif", "tiff": type = .tiff
        case "png": type = .png
        default: return false
        }
        let img = flattened()
        let out = type == .jpeg ? Self.opaque(img) : img
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else { return false }
        var props: [CFString: Any] = [:]
        if type == .jpeg || type == .heic { props[kCGImageDestinationLossyCompressionQuality] = 0.92 }
        CGImageDestinationAddImage(dest, out, props as CFDictionary)
        return CGImageDestinationFinalize(dest)
    }

    // MARK: Piksel işlemleri
    static let ciContext = CIContext(options: nil)

    static func applyFilter(_ i: Int, to img: CGImage) -> CGImage {
        guard i > 0, i < EditorFilters.all.count else { return img }
        let input = CIImage(cgImage: img)
        let out = EditorFilters.all[i].apply(input)
        return ciContext.createCGImage(out, from: input.extent) ?? img
    }

    static func makeContext(_ w: Int, _ h: Int, opaque: Bool = false) -> CGContext? {
        CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast).rawValue)
    }

    /// 90° sağa (saat yönünde).
    static func rotated(_ img: CGImage) -> CGImage? {
        let w = img.width, h = img.height
        guard let c = makeContext(h, w) else { return nil }
        c.translateBy(x: 0, y: CGFloat(w))
        c.rotate(by: -.pi / 2)
        c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return c.makeImage()
    }

    static func flipped(_ img: CGImage, horizontal: Bool) -> CGImage? {
        let w = img.width, h = img.height
        guard let c = makeContext(w, h) else { return nil }
        if horizontal { c.translateBy(x: CGFloat(w), y: 0); c.scaleBy(x: -1, y: 1) }
        else { c.translateBy(x: 0, y: CGFloat(h)); c.scaleBy(x: 1, y: -1) }
        c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return c.makeImage()
    }

    static func resized(_ img: CGImage, _ w: Int, _ h: Int) -> CGImage? {
        guard let c = makeContext(w, h) else { return nil }
        c.interpolationQuality = .high
        c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return c.makeImage()
    }

    static func scaled(_ img: CGImage, maxDim: Int) -> CGImage {
        let m = max(img.width, img.height)
        guard m > maxDim else { return img }
        let k = CGFloat(maxDim) / CGFloat(m)
        let w = max(1, Int(CGFloat(img.width) * k)), h = max(1, Int(CGFloat(img.height) * k))
        return resized(img, w, h) ?? img
    }

    /// JPEG alfa kanalını sevmez: beyaz zemin üstüne çizer.
    static func opaque(_ img: CGImage) -> CGImage {
        let rect = CGRect(x: 0, y: 0, width: img.width, height: img.height)
        guard let c = makeContext(img.width, img.height, opaque: true) else { return img }
        c.setFillColor(CGColor(gray: 1, alpha: 1))
        c.fill(rect)
        c.draw(img, in: rect)
        return c.makeImage() ?? img
    }
}
