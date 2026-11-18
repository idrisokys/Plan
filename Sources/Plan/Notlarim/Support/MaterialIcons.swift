import SwiftUI
import AppKit

// Android'deki Notlarım ekranının Material (filled) simgeleri ve koyu renk şeması.
// Simgeler SVG yol verisinden çizilir (24 × 24 çizim alanı); renk `foregroundStyle` ile verilir.

/// Android `darkColorScheme()` renkleri (Notlarım ekranının görünümüyle birebir).
enum NT {
    static func hex(_ v: UInt32, _ a: Double = 1) -> Color {
        Color(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255,
              blue: Double(v & 0xFF) / 255, opacity: a)
    }
    static let bg = hex(0x141118)                 // yüzey (liste arka planı)
    static let bar = hex(0x23202B)                // alt çubuk / üst çubuk (tonal yükseklik)
    static let dialog = hex(0x2B2930)             // diyalog yüzeyi
    static let onSurface = hex(0xE6E0E9)          // metin ve simgeler
    static let onSurfaceVariant = hex(0xCAC4D0)
    static let outline = hex(0x938F99)            // metin alanı çerçevesi
    static let outlineVariant = hex(0x49454F)     // satır ayırıcı
    static let primary = hex(0xD0BCFF)
    static let secondaryContainer = hex(0x4A4458) // seçili satır
    static let error = hex(0xF2B8B5)
    static let pinnedRed = hex(0xB71C1C)          // sabitlenmiş öğenin üç noktası
    static let online = hex(0x66BB6A)
    static let hiAll = NSColor(srgbRed: 1, green: 0.757, blue: 0.027, alpha: 0.33)
    static let hiCur = NSColor(srgbRed: 1, green: 0.596, blue: 0, alpha: 0.8)
    static let bgNS = NSColor(srgbRed: 0x14 / 255, green: 0x11 / 255, blue: 0x18 / 255, alpha: 1)
    static let onSurfaceNS = NSColor(srgbRed: 0xE6 / 255, green: 0xE0 / 255, blue: 0xE9 / 255, alpha: 1)
}

/// Compose `Icons.Default.*` yol verileri.
enum MI {
    static let folder = "M10,4H4c-1.1,0 -1.99,0.9 -1.99,2L2,18c0,1.1 0.9,2 2,2h16c1.1,0 2,-0.9 2,-2V8c0,-1.1 -0.9,-2 -2,-2h-8l-2,-2z"
    static let folderOpen = "M20,6h-8l-2,-2H4c-1.1,0 -1.99,0.9 -1.99,2L2,18c0,1.1 0.9,2 2,2h16c1.1,0 2,-0.9 2,-2V8c0,-1.1 -0.9,-2 -2,-2zM20,18H4V8h16v10z"
    static let link = "M3.9,12c0,-1.71 1.39,-3.1 3.1,-3.1h4L11,7L7,7c-2.76,0 -5,2.24 -5,5s2.24,5 5,5h4v-1.9L7,15.1c-1.71,0 -3.1,-1.39 -3.1,-3.1zM8,13h8v-2L8,11v2zM17,7h-4v1.9h4c1.71,0 3.1,1.39 3.1,3.1s-1.39,3.1 -3.1,3.1h-4L13,17h4c2.76,0 5,-2.24 5,-5s-2.24,-5 -5,-5z"
    static let description = "M14,2H6c-1.1,0 -1.99,0.9 -1.99,2L4,20c0,1.1 0.89,2 1.99,2H18c1.1,0 2,-0.9 2,-2V8l-6,-6zM16,18H8v-2h8v2zM16,14H8v-2h8v2zM13,9V3.5L18.5,9H13z"
    static let moreVert = "M12,8c1.1,0 2,-0.9 2,-2s-0.9,-2 -2,-2 -2,0.9 -2,2 0.9,2 2,2zM12,10c-1.1,0 -2,0.9 -2,2s0.9,2 2,2 2,-0.9 2,-2 -0.9,-2 -2,-2zM12,16c-1.1,0 -2,0.9 -2,2s0.9,2 2,2 2,-0.9 2,-2 -0.9,-2 -2,-2z"
    static let createNewFolder = "M20,6h-8l-2,-2H4c-1.11,0 -1.99,0.89 -1.99,2L2,18c0,1.11 0.89,2 2,2h16c1.1,0 2,-0.9 2,-2V8c0,-1.1 -0.9,-2 -2,-2zM19,14h-3v3h-2v-3h-3v-2h3V9h2v3h3v2z"
    static let refresh = "M17.65,6.35C16.2,4.9 14.21,4 12,4c-4.42,0 -7.99,3.58 -7.99,8s3.57,8 7.99,8c3.73,0 6.84,-2.55 7.73,-6h-2.08c-0.82,2.33 -3.04,4 -5.65,4 -3.31,0 -6,-2.69 -6,-6s2.69,-6 6,-6c1.66,0 3.14,0.69 4.22,1.78L13,11h7V4l-2.35,2.35z"
    static let search = "M15.5,14h-0.79l-0.28,-0.27C15.41,12.59 16,11.11 16,9.5 16,5.91 13.09,3 9.5,3S3,5.91 3,9.5 5.91,16 9.5,16c1.61,0 3.09,-0.59 4.23,-1.57l0.27,0.28v0.79l5,4.99L20.49,19l-4.99,-5zM9.5,14C7.01,14 5,11.99 5,9.5S7.01,5 9.5,5 14,7.01 14,9.5 11.99,14 9.5,14z"
    static let close = "M19,6.41L17.59,5 12,10.59 6.41,5 5,6.41 10.59,12 5,17.59 6.41,19 12,13.41 17.59,19 19,17.59 13.41,12z"
    static let paste = "M19,2h-4.18C14.4,0.84 13.3,0 12,0c-1.3,0 -2.4,0.84 -2.82,2H5c-1.1,0 -2,0.9 -2,2v16c0,1.1 0.9,2 2,2h14c1.1,0 2,-0.9 2,-2V4c0,-1.1 -0.9,-2 -2,-2zM12,2c0.55,0 1,0.45 1,1s-0.45,1 -1,1 -1,-0.45 -1,-1 0.45,-1 1,-1zM19,20H5V4h2v3h10V4h2v16z"
    static let save = "M17,3L5,3c-1.11,0 -2,0.9 -2,2v14c0,1.1 0.89,2 2,2h14c1.1,0 2,-0.9 2,-2L21,7l-4,-4zM12,19c-1.66,0 -3,-1.34 -3,-3s1.34,-3 3,-3 3,1.34 3,3 -1.34,3 -3,3zM15,9L5,9L5,5h10v4z"
    static let arrowBack = "M20,11H7.83l5.59,-5.59L12,4l-8,8 8,8 1.41,-1.41L7.83,13H20v-2z"
    static let contentCopy = "M16,1L4,1c-1.1,0 -2,0.9 -2,2v14h2L4,3h12L16,1zM19,5L8,5c-1.1,0 -2,0.9 -2,2v14c0,1.1 0.9,2 2,2h11c1.1,0 2,-0.9 2,-2L21,7c0,-1.1 -0.9,-2 -2,-2zM19,21L8,21L8,7h11v14z"
    static let edit = "M3,17.25V21h3.75L17.81,9.94l-3.75,-3.75L3,17.25zM20.71,7.04c0.39,-0.39 0.39,-1.02 0,-1.41l-2.34,-2.34c-0.39,-0.39 -1.02,-0.39 -1.41,0l-1.83,1.83 3.75,3.75 1.83,-1.83z"
    static let arrowUp = "M7.41,15.41L12,10.83l4.59,4.58L18,14l-6,-6 -6,6z"
    static let arrowDown = "M7.41,8.59L12,13.17l4.59,-4.58L18,10l-6,6 -6,-6 1.41,-1.41z"
    static let alignTop = "M8,11h3v10h2V11h3l-4,-4 -4,4zM4,3v2h16V3H4z"
    static let alignBottom = "M16,13h-3V3h-2v10H8l4,4 4,-4zM4,19v2h16v-2H4z"
    static let pin = "M16,9V4l1,0c0.55,0 1,-0.45 1,-1v0c0,-0.55 -0.45,-1 -1,-1H7C6.45,2 6,2.45 6,3v0c0,0.55 0.45,1 1,1l1,0v5c0,1.66 -1.34,3 -3,3h0v2h5.97v7l1,1l1,-1v-7H19v-2h0C17.34,12 16,10.66 16,9z"
}

/// SVG yol verisini (M L H V C S Q T Z; büyük/küçük harf) 24 × 24 alanından verilen kareye ölçekleyen şekil.
struct SVGPathShape: Shape {
    let d: String

    func path(in rect: CGRect) -> Path {
        let p = SVGPathParser.parse(d)
        let s = min(rect.width, rect.height) / 24
        let ox = rect.minX + (rect.width - 24 * s) / 2
        let oy = rect.minY + (rect.height - 24 * s) / 2
        return p.applying(CGAffineTransform(a: s, b: 0, c: 0, d: s, tx: ox, ty: oy))
    }
}

enum SVGPathParser {
    static func parse(_ d: String) -> Path {
        var path = Path()
        let s = Array(d)
        var i = 0
        var cur = CGPoint.zero
        var start = CGPoint.zero
        var lastC: CGPoint? = nil      // önceki kübik eğrinin ikinci kontrol noktası (S için)
        var lastQ: CGPoint? = nil      // önceki ikinci derece eğrinin kontrol noktası (T için)
        var cmd: Character = " "

        func isSep(_ c: Character) -> Bool { c == " " || c == "," || c == "\n" || c == "\t" || c == "\r" }
        func skip() { while i < s.count && isSep(s[i]) { i += 1 } }
        func isCmd(_ c: Character) -> Bool { "MmLlHhVvCcSsQqTtZz".contains(c) }
        func num() -> CGFloat {
            skip()
            var j = i
            if j < s.count && (s[j] == "-" || s[j] == "+") { j += 1 }
            var dot = false
            while j < s.count {
                let c = s[j]
                if c >= "0" && c <= "9" { j += 1 }
                else if c == "." && !dot { dot = true; j += 1 }
                else { break }
            }
            let str = String(s[i..<j])
            i = j
            return CGFloat(Double(str) ?? 0)
        }
        func pt(_ rel: Bool) -> CGPoint {
            let x = num()
            let y = num()
            return rel ? CGPoint(x: cur.x + x, y: cur.y + y) : CGPoint(x: x, y: y)
        }

        while true {
            skip()
            if i >= s.count { break }
            let c = s[i]
            if isCmd(c) {
                cmd = c
                i += 1
                if c == "Z" || c == "z" {
                    path.closeSubpath()
                    cur = start
                    lastC = nil; lastQ = nil
                    continue
                }
            } else if cmd == " " || cmd == "Z" || cmd == "z" {
                break   // komutsuz sayı: geçersiz veri
            }
            let rel = cmd.isLowercase
            switch cmd {
            case "M", "m":
                cur = pt(rel)
                path.move(to: cur)
                start = cur
                cmd = rel ? "l" : "L"        // M'den sonraki çiftler çizgidir
                lastC = nil; lastQ = nil
            case "L", "l":
                cur = pt(rel)
                path.addLine(to: cur)
                lastC = nil; lastQ = nil
            case "H", "h":
                let x = num()
                cur = CGPoint(x: rel ? cur.x + x : x, y: cur.y)
                path.addLine(to: cur)
                lastC = nil; lastQ = nil
            case "V", "v":
                let y = num()
                cur = CGPoint(x: cur.x, y: rel ? cur.y + y : y)
                path.addLine(to: cur)
                lastC = nil; lastQ = nil
            case "C", "c":
                let p1 = pt(rel)
                let p2 = pt(rel)
                let p3 = pt(rel)
                path.addCurve(to: p3, control1: p1, control2: p2)
                cur = p3
                lastC = p2; lastQ = nil
            case "S", "s":
                let p2 = pt(rel)
                let p3 = pt(rel)
                var p1 = cur
                if let lc = lastC { p1 = CGPoint(x: 2 * cur.x - lc.x, y: 2 * cur.y - lc.y) }
                path.addCurve(to: p3, control1: p1, control2: p2)
                cur = p3
                lastC = p2; lastQ = nil
            case "Q", "q":
                let p1 = pt(rel)
                let p2 = pt(rel)
                path.addQuadCurve(to: p2, control: p1)
                cur = p2
                lastQ = p1; lastC = nil
            case "T", "t":
                let p2 = pt(rel)
                var p1 = cur
                if let lq = lastQ { p1 = CGPoint(x: 2 * cur.x - lq.x, y: 2 * cur.y - lq.y) }
                path.addQuadCurve(to: p2, control: p1)
                cur = p2
                lastQ = p1; lastC = nil
            default:
                i = s.count
            }
        }
        return path
    }
}

/// Tek renkli Material simgesi (varsayılan 24 pt); rengi `foregroundStyle` belirler.
struct MIcon: View {
    let d: String
    var size: CGFloat = 24
    init(_ d: String, _ size: CGFloat = 24) { self.d = d; self.size = size }
    var body: some View {
        SVGPathShape(d: d).fill().frame(width: size, height: size)
    }
}

/// Android `IconButton` karşılığı: 24 pt simge, pasifken %38 saydamlık.
struct IconBtn: View {
    @Environment(\.isEnabled) private var enabled
    let d: String
    var tint: Color = NT.onSurface
    var help: String = ""
    let action: () -> Void
    init(_ d: String, tint: Color = NT.onSurface, help: String = "", action: @escaping () -> Void) {
        self.d = d; self.tint = tint; self.help = help; self.action = action
    }
    var body: some View {
        Button(action: action) {
            MIcon(d).foregroundStyle(tint).opacity(enabled ? 1 : 0.38)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
