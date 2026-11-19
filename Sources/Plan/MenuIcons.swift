import SwiftUI

// Plan için çizilmiş iki simge (SF Symbols değil): üç çizgili menü ve dosya yöneticisi.

/// Üç çizgili menü simgesi: iki uzun çizgi, altta kısa çizgi.
struct MenuLinesIcon: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4.5) {
            Capsule().frame(width: 18, height: 2.2)
            Capsule().frame(width: 18, height: 2.2)
            Capsule().frame(width: 11, height: 2.2)
        }
        .foregroundStyle(.white)
        .frame(width: 18, height: 18)
    }
}

/// Sekmeli klasör çerçevesi (köşeleri yuvarlak).
struct FolderShape: Shape {
    func path(in r: CGRect) -> Path {
        let rad: CGFloat = 2.5
        let tabW = r.width * 0.42
        let tabH = r.height * 0.2
        let top = r.minY + tabH
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + rad))
        p.addQuadCurve(to: CGPoint(x: r.minX + rad, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + tabW, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + tabW + tabH, y: top))
        p.addLine(to: CGPoint(x: r.maxX - rad, y: top))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: top + rad), control: CGPoint(x: r.maxX, y: top))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - rad))
        p.addQuadCurve(to: CGPoint(x: r.maxX - rad, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + rad, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - rad), control: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// Dosya yöneticisi simgesi: klasörün ortasında dikey çizgi (çift panel).
struct FileManagerIcon: View {
    var body: some View {
        ZStack {
            FolderShape().stroke(Color.white, style: StrokeStyle(lineWidth: 1.7, lineJoin: .round))
            Capsule().fill(Color.white).frame(width: 1.6, height: 7).offset(y: 2.5)
        }
        .frame(width: 20, height: 16)
    }
}
