import SwiftUI
import AppKit

private let edBG = Color(white: 0.13)
private let edIdle = Color.black.opacity(0.45)
private let edDim = Color.white.opacity(0.67)

private func edCircle(_ system: String, size: CGFloat = 36, active: Bool = false) -> some View {
    Image(systemName: system).font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
        .frame(width: size, height: size)
        .background(Circle().fill(active ? Color.white.opacity(0.3) : edIdle))
}

struct ImageEditorView: View {
    @ObservedObject var model: ImageEditorModel
    @State private var dragHandle: CropHandle?
    @State private var cropStart: CGRect = .zero
    @State private var showResize = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            canvasArea
            bottomPanel
        }
        .background(edBG)
        .preferredColorScheme(.dark)
        .frame(minWidth: 560, minHeight: 520)
    }

    // MARK: Üst çubuk
    private var topBar: some View {
        HStack(spacing: 8) {
            Button { ImageEditorWindow.openPicker() } label: { edCircle("folder") }
                .buttonStyle(.plain).help(L("Başka resim aç", "Open another image"))
            Button { model.navigate(-1) } label: { edCircle("chevron.left") }
                .buttonStyle(.plain).disabled(!model.canNavigate).opacity(model.canNavigate ? 1 : 0.4)
                .keyboardShortcut(.leftArrow, modifiers: [])
                .help(L("Önceki resim (←)", "Previous image (←)"))
            Button { model.navigate(1) } label: { edCircle("chevron.right") }
                .buttonStyle(.plain).disabled(!model.canNavigate).opacity(model.canNavigate ? 1 : 0.4)
                .keyboardShortcut(.rightArrow, modifiers: [])
                .help(L("Sonraki resim (→)", "Next image (→)"))
            Button { model.undo() } label: { edCircle("arrow.uturn.backward") }
                .buttonStyle(.plain).disabled(!model.canUndo).opacity(model.canUndo ? 1 : 0.4)
                .keyboardShortcut("z", modifiers: .command)
                .help(L("Geri al (⌘Z)", "Undo (⌘Z)"))
            Text(model.title).font(.system(size: 14, weight: .medium)).foregroundStyle(edDim)
                .lineLimit(1).truncationMode(.middle).padding(.leading, 6)
            Spacer(minLength: 8)
            Button { model.copyToClipboard() } label: { edCircle("doc.on.doc") }
                .buttonStyle(.plain).help(L("Panoya kopyala", "Copy to clipboard"))
            Menu {
                Button(L("Farklı kaydet…", "Save As…")) { model.saveAs() }
                Button(L("Üzerine yaz", "Overwrite original")) { model.overwrite() }
            } label: { edCircle("square.and.arrow.down") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help(L("Kaydet", "Save"))
            Button { model.share() } label: { edCircle("square.and.arrow.up") }
                .buttonStyle(.plain).help(L("Paylaş", "Share"))
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    // MARK: Resim alanı
    private var canvasArea: some View {
        GeometryReader { geo in
            let W = CGFloat(model.current.width), H = CGFloat(model.current.height)
            let availW = max(geo.size.width - 24, 10), availH = max(geo.size.height - 24, 10)
            let scale = min(availW / W, availH / H)
            let size = CGSize(width: W * scale, height: H * scale)
            let origin = CGPoint(x: (geo.size.width - size.width) / 2, y: (geo.size.height - size.height) / 2)
            let fit = CGRect(origin: origin, size: size)
            ZStack(alignment: .topLeading) {
                Image(decorative: model.display, scale: 1)
                    .resizable().interpolation(.medium)
                    .frame(width: size.width, height: size.height)
                    .offset(x: origin.x, y: origin.y)
                strokesLayer(fit: fit, scale: scale)
                if model.tool == .crop { cropOverlay(fit: fit, scale: scale) }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(dragGesture(fit: fit, scale: scale))
        }
        .background(Color.black.opacity(0.35))
    }

    private func strokesLayer(fit: CGRect, scale: CGFloat) -> some View {
        Canvas { ctx, _ in
            ctx.clip(to: Path(fit))
            var all = model.strokes
            if let l = model.liveStroke { all.append(l) }
            for s in all {
                guard let first = s.points.first else { continue }
                var path = Path()
                let f = toView(first, fit, scale)
                path.move(to: f)
                if s.points.count == 1 { path.addLine(to: CGPoint(x: f.x + 0.01, y: f.y)) }
                for p in s.points.dropFirst() { path.addLine(to: toView(p, fit, scale)) }
                ctx.stroke(path, with: .color(Color(nsColor: s.color)),
                           style: StrokeStyle(lineWidth: s.width * scale, lineCap: .round, lineJoin: .round))
            }
        }
        .allowsHitTesting(false)
    }

    private func cropOverlay(fit: CGRect, scale: CGFloat) -> some View {
        Canvas { ctx, _ in
            let r = viewRect(model.cropRect, fit, scale)
            var dimPath = Path(fit)
            dimPath.addRect(r)
            ctx.fill(dimPath, with: .color(.black.opacity(0.55)), style: FillStyle(eoFill: true))
            ctx.stroke(Path(r), with: .color(.white), lineWidth: 1.5)
            for i in 1...2 {                                          // üçler kuralı çizgileri
                let fx = r.minX + r.width * CGFloat(i) / 3
                let fy = r.minY + r.height * CGFloat(i) / 3
                var g = Path()
                g.move(to: CGPoint(x: fx, y: r.minY)); g.addLine(to: CGPoint(x: fx, y: r.maxY))
                g.move(to: CGPoint(x: r.minX, y: fy)); g.addLine(to: CGPoint(x: r.maxX, y: fy))
                ctx.stroke(g, with: .color(.white.opacity(0.35)), lineWidth: 0.75)
            }
            let pts = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                       CGPoint(x: r.minX, y: r.midY), CGPoint(x: r.maxX, y: r.midY),
                       CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.midX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)]
            for p in pts {
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)), with: .color(.white))
            }
            let label = "\(Int(model.cropRect.width.rounded())) × \(Int(model.cropRect.height.rounded()))"
            ctx.draw(Text(label).font(.system(size: 11, weight: .medium)).foregroundColor(.white),
                     at: CGPoint(x: r.minX + 8, y: r.minY + 8), anchor: .topLeading)
        }
        .allowsHitTesting(false)
    }

    private func dragGesture(fit: CGRect, scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { v in
                switch model.tool {
                case .draw:
                    if model.liveStroke == nil {
                        if fit.insetBy(dx: -8, dy: -8).contains(v.startLocation) {
                            model.beginStroke(at: toPx(v.location, fit, scale), scale: scale)
                        }
                    } else {
                        model.extendStroke(toPx(v.location, fit, scale))
                    }
                case .crop:
                    if dragHandle == nil {
                        dragHandle = model.hitCrop(v.startLocation, viewRect(model.cropRect, fit, scale))
                        cropStart = model.cropRect
                    }
                    if let h = dragHandle, !h.isNone {
                        let d = CGSize(width: v.translation.width / scale, height: v.translation.height / scale)
                        model.cropRect = model.resized(cropStart, h, d)
                    }
                default:
                    break
                }
            }
            .onEnded { _ in
                if model.tool == .draw { model.endStroke() }
                dragHandle = nil
            }
    }

    // MARK: Koordinat dönüşümleri (piksel ↔ ekran)
    private func toPx(_ p: CGPoint, _ fit: CGRect, _ s: CGFloat) -> CGPoint {
        CGPoint(x: min(max((p.x - fit.minX) / s, 0), CGFloat(model.current.width)),
                y: min(max((p.y - fit.minY) / s, 0), CGFloat(model.current.height)))
    }
    private func toView(_ p: CGPoint, _ fit: CGRect, _ s: CGFloat) -> CGPoint {
        CGPoint(x: fit.minX + p.x * s, y: fit.minY + p.y * s)
    }
    private func viewRect(_ r: CGRect, _ fit: CGRect, _ s: CGFloat) -> CGRect {
        CGRect(x: fit.minX + r.minX * s, y: fit.minY + r.minY * s, width: r.width * s, height: r.height * s)
    }

    // MARK: Alt panel
    private var bottomPanel: some View {
        VStack(spacing: 12) {
            switch model.tool {
            case .filter?: filterStrip
            case .crop?: cropPanel
            case .draw?: drawPanel
            case nil: EmptyView()
            }
            HStack(spacing: 28) {
                toolTab(.filter, "camera.filters", L("Filtre", "Filters"))
                toolTab(.crop, "crop", L("Kırp / Döndür", "Crop / Rotate"))
                toolTab(.draw, "pencil.tip", L("Çiz", "Draw"))
            }
        }
        .padding(12).frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.25))
    }

    private func toolTab(_ t: EditorTool, _ icon: String, _ title: String) -> some View {
        Button { model.selectTool(t) } label: {
            VStack(spacing: 4) {
                edCircle(icon, active: model.tool == t)
                Text(title).font(.system(size: 11)).foregroundStyle(model.tool == t ? Color.white : edDim)
            }
        }.buttonStyle(.plain)
    }

    private var filterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(0..<EditorFilters.all.count, id: \.self) { i in
                    let sel = i == model.filterIndex
                    Button { model.selectFilter(i) } label: {
                        VStack(spacing: 4) {
                            Group {
                                if i < model.thumbs.count {
                                    Image(decorative: model.thumbs[i], scale: 1).resizable().scaledToFill()
                                } else {
                                    Color.gray.opacity(0.3)
                                }
                            }
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(sel ? Color.white : Color.clear, lineWidth: 2))
                            Text(EditorFilters.all[i].name).font(.system(size: 11))
                                .foregroundStyle(sel ? Color.white : edDim).lineLimit(1)
                        }
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 4)
        }
        .frame(height: 92)
    }

    private var cropPanel: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(CropAspect.allCases) { a in
                    Button { model.setAspect(a) } label: {
                        Text(a.title).font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                            .padding(.horizontal, 12).frame(height: 30)
                            .background(Capsule().fill(model.aspect == a ? Color.white.opacity(0.3) : edIdle))
                    }.buttonStyle(.plain)
                }
                if model.aspect == .custom {
                    TextField("", value: $model.customX, format: .number)
                        .textFieldStyle(.plain).multilineTextAlignment(.center).frame(width: 40, height: 28)
                        .background(Capsule().fill(edIdle))
                    Text(":").foregroundStyle(edDim)
                    TextField("", value: $model.customY, format: .number)
                        .textFieldStyle(.plain).multilineTextAlignment(.center).frame(width: 40, height: 28)
                        .background(Capsule().fill(edIdle))
                }
            }
            .onChange(of: model.customX) { _ in if model.aspect == .custom { model.setAspect(.custom) } }
            .onChange(of: model.customY) { _ in if model.aspect == .custom { model.setAspect(.custom) } }

            HStack(spacing: 10) {
                Button { model.rotateRight() } label: { edCircle("rotate.right") }
                    .buttonStyle(.plain).help(L("Sağa döndür", "Rotate right"))
                Button { model.flipHorizontal() } label: { edCircle("arrow.left.and.right.righttriangle.left.righttriangle.right") }
                    .buttonStyle(.plain).help(L("Yatay çevir", "Flip horizontally"))
                Button { model.flipVertical() } label: { edCircle("arrow.up.and.down.righttriangle.up.righttriangle.down") }
                    .buttonStyle(.plain).help(L("Dikey çevir", "Flip vertically"))
                Button { model.prepareResize(); showResize = true } label: { edCircle("arrow.up.left.and.arrow.down.right") }
                    .buttonStyle(.plain).help(L("Yeniden boyutlandır", "Resize"))
                    .popover(isPresented: $showResize, arrowEdge: .top) { resizePopover }
                Spacer()
                Button { model.applyCrop() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                        Text(L("Kırp", "Crop"))
                    }
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 18).frame(height: 36)
                    .background(Capsule().fill(Color.white.opacity(0.25)))
                }.buttonStyle(.plain).help(L("Seçili alanı kırp", "Crop to selection"))
            }
        }
    }

    private var resizePopover: some View {
        let wBinding = Binding<Int>(
            get: { model.resizeW },
            set: { w in
                model.resizeW = w
                if model.keepRatio, w > 0 { model.resizeH = max(1, Int((Double(w) / model.resizeRatio).rounded())) }
            })
        let hBinding = Binding<Int>(
            get: { model.resizeH },
            set: { h in
                model.resizeH = h
                if model.keepRatio, h > 0 { model.resizeW = max(1, Int((Double(h) * model.resizeRatio).rounded())) }
            })
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField("", value: wBinding, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder).frame(width: 80)
                Text("×")
                TextField("", value: hBinding, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder).frame(width: 80)
                Text("px").foregroundStyle(edDim)
            }
            Toggle(L("Oranı koru", "Keep aspect ratio"), isOn: $model.keepRatio)
            HStack {
                Spacer()
                Button(L("Uygula", "Apply")) { model.applyResize(); showResize = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
    }

    private var drawPanel: some View {
        HStack(spacing: 12) {
            ColorPicker("", selection: $model.brushColor, supportsOpacity: false).labelsHidden()
            ForEach([Color.red, .yellow, .green, .blue, .white, .black], id: \.self) { c in
                Button { model.brushColor = c } label: {
                    Circle().fill(c).frame(width: 22, height: 22)
                        .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 1))
                }.buttonStyle(.plain)
            }
            Spacer(minLength: 8)
            Circle().fill(model.brushColor)
                .frame(width: max(CGFloat(model.brushSize), 3), height: max(CGFloat(model.brushSize), 3))
                .frame(width: 42, height: 42)
            Slider(value: $model.brushSize, in: 2...40).frame(width: 150)
            Button { model.undo() } label: { edCircle("arrow.uturn.backward") }
                .buttonStyle(.plain).disabled(!model.canUndo).opacity(model.canUndo ? 1 : 0.4)
                .help(L("Geri al", "Undo"))
        }
        .frame(height: 48)
    }
}
