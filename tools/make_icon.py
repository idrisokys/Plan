#!/usr/bin/env python3
"""Uygulama simgesini vektör olarak çizer.

Şekiller bir kez tanımlanır; aynı tanımdan hem Resources/AppIcon.svg (vektör kaynak)
hem de Resources/AppIcon.png (1024x1024, build.sh bunu .icns'e çevirir) üretilir.

Kullanım (proje kökünden):  python3 tools/make_icon.py
Gerekli: Python 3, Pillow, numpy.
"""
import math
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageChops

S = 3                     # PNG için süper örnekleme
W = 1024
N = W * S
DY = -24                  # içerik, zemine göre biraz yukarı kaydırılır (görsel denge)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


# ----------------------------------------------------------------------------- yol (path)
class Path:
    def __init__(self):
        self.seg, self.closed = [], False

    def M(self, x, y): self.seg.append(("M", x, y)); return self
    def L(self, x, y): self.seg.append(("L", x, y)); return self
    def C(self, *a): self.seg.append(("C",) + a); return self
    def Z(self): self.closed = True; return self

    def d(self):
        out = []
        for g in self.seg:
            if g[0] == "M": out.append(f"M{g[1]:.1f} {g[2]:.1f}")
            elif g[0] == "L": out.append(f"L{g[1]:.1f} {g[2]:.1f}")
            else: out.append("C" + " ".join(f"{v:.1f}" for v in g[1:]))
        if self.closed: out.append("Z")
        return "".join(out)

    def pts(self):
        pts, cur = [], None
        for g in self.seg:
            if g[0] in "ML":
                cur = (g[1], g[2]); pts.append(cur)
            else:
                x1, y1, x2, y2, x, y = g[1:]; x0, y0 = cur
                for i in range(1, 25):
                    t = i / 24; u = 1 - t
                    pts.append((u**3*x0 + 3*u*u*t*x1 + 3*u*t*t*x2 + t**3*x,
                                u**3*y0 + 3*u*u*t*y1 + 3*u*t*t*y2 + t**3*y))
                cur = (x, y)
        return pts


def poly(points, closed=True):
    p = Path()
    for i, (x, y) in enumerate(points):
        p.M(x, y) if i == 0 else p.L(x, y)
    if closed: p.Z()
    return p


def ellipse(cx, cy, rx, ry, rot=0.0):
    k = 0.5522847498
    base = [(rx, 0, rx, ry*k, rx*k, ry, 0, ry), (-rx*k, ry, -rx, ry*k, -rx, 0, 0, 0)]
    pts = [(rx, 0), (rx, ry*k), (rx*k, ry), (0, ry), (-rx*k, ry), (-rx, ry*k), (-rx, 0),
           (-rx, -ry*k), (-rx*k, -ry), (0, -ry), (rx*k, -ry), (rx, -ry*k), (rx, 0)]
    c, s = math.cos(math.radians(rot)), math.sin(math.radians(rot))
    pts = [(cx + x*c - y*s, cy + x*s + y*c) for x, y in pts]
    p = Path().M(*pts[0])
    for i in range(1, 13, 3):
        p.C(*pts[i], *pts[i+1], *pts[i+2])
    return p.Z()


def rrect(x, y, w, h, r):
    k = r * 0.4477152502
    return (Path().M(x + r, y).L(x + w - r, y)
            .C(x + w - k, y, x + w, y + k, x + w, y + r).L(x + w, y + h - r)
            .C(x + w, y + h - k, x + w - k, y + h, x + w - r, y + h).L(x + r, y + h)
            .C(x + k, y + h, x, y + h - k, x, y + h - r).L(x, y + r)
            .C(x, y + k, x + k, y, x + r, y).Z())


def mapped(p, f):
    q = Path(); q.closed = p.closed
    for g in p.seg:
        v = list(g[1:])
        out = []
        for i in range(0, len(v), 2):
            out += list(f(v[i], v[i+1]))
        q.seg.append((g[0],) + tuple(out))
    return q


def mirror(p): return mapped(p, lambda x, y: (W - x, y))
def shift(p, dx, dy): return mapped(p, lambda x, y: (x + dx, y + dy))


# ----------------------------------------------------------------------------- boyalar
def Lin(x1, y1, x2, y2, stops): return ("lin", x1, y1, x2, y2, stops)
def Rad(cx, cy, r, stops): return ("rad", cx, cy, r, stops)


def hexrgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))


def stop_arrays(stops):
    offs = [s[0] for s in stops]
    cols = np.array([hexrgb(s[1]) for s in stops], dtype=np.float32)
    al = [s[2] if len(s) > 2 else 1.0 for s in stops]
    return offs, cols, al


def grad_eval(g, bb, dy):
    x0, y0, x1, y1 = bb
    xs = (np.arange(x0, x1, dtype=np.float32) + 0.5) / S
    ys = (np.arange(y0, y1, dtype=np.float32) + 0.5) / S
    X, Y = np.meshgrid(xs, ys)
    if g[0] == "lin":
        _, ax, ay, bx, by, stops = g
        ay += dy; by += dy
        dx_, dy_ = bx - ax, by - ay
        t = ((X - ax) * dx_ + (Y - ay) * dy_) / (dx_*dx_ + dy_*dy_)
    else:
        _, cx, cy, r, stops = g
        cy += dy
        t = np.sqrt((X - cx)**2 + (Y - cy)**2) / r
    t = np.clip(t, 0, 1)
    offs, cols, al = stop_arrays(stops)
    rgb = np.dstack([np.interp(t, offs, cols[:, i]) for i in range(3)])
    a = np.interp(t, offs, al)
    return rgb, a


# ----------------------------------------------------------------------------- sahne
SHAPES = []


def add(path, fill=None, stroke=None, sw=0, op=1.0, shadow=None, clip=None, dy=DY, round_ends=True):
    SHAPES.append(dict(path=path, fill=fill, stroke=stroke, sw=sw, op=op,
                       shadow=shadow, clip=clip, dy=dy, round_ends=round_ends))


def superellipse(cx, cy, a, n=5.0, k=360):
    pts = []
    for i in range(k):
        t = 2 * math.pi * i / k
        c, s = math.cos(t), math.sin(t)
        x = a * math.copysign(abs(c) ** (2 / n), c)
        y = a * math.copysign(abs(s) ** (2 / n), s)
        pts.append((cx + x, cy + y))
    return poly(pts)


def build():
    """Koyu zemin üzerinde 3B büyüteç: gümüş çerçeve, koyu mavi cam, siyah saplı."""
    cx, cy = 440, 428                     # büyüteç merkezi
    TH = math.radians(43)                 # sap yönü (aşağı-sağ)
    ux, uy = math.cos(TH), math.sin(TH)   # sap ekseni
    nx, ny = -uy, ux                      # eksene dik

    def P(u, v):                          # yerel (eksen, dik) -> global
        return (cx + ux * u + nx * v, cy + uy * u + ny * v)

    def seg_rect(u0, u1, w0, w1=None, r=0.0):
        """Eksen boyunca u0..u1, genişliği w0 (uçta w1) olan, köşeleri yuvarlak şerit."""
        w1 = w0 if w1 is None else w1
        pts = [P(u0, -w0 / 2), P(u1, -w1 / 2), P(u1, w1 / 2), P(u0, w0 / 2)]
        return poly(pts)

    def across(u, w, stops):              # eksene dik (sapın enine) degrade
        a, b = P(u, -w / 2), P(u, w / 2)
        return Lin(a[0], a[1], b[0], b[1], stops)

    DY0 = 0

    # --- zemin: koyu lacivert-siyah yuvarlak kare -------------------------------------
    body = superellipse(512, 512, 412, 5.0)
    add(body, fill=Lin(512, 100, 512, 924, [(0, "#262A40"), (0.35, "#161824"), (1, "#0A0B11")]),
        shadow=(0, 14, 16, 0.45), dy=0)
    add(body, fill=Rad(512, 140, 560, [(0, "#8FA6E8", 0.16), (0.5, "#8FA6E8", 0.03), (1, "#8FA6E8", 0.0)]),
        clip=body, dy=0)
    add(body, stroke="#B9C6F5", sw=4, op=0.20, clip=body, dy=0)

    # --- çerçevenin arkasındaki mavi ışıma --------------------------------------------
    add(ellipse(cx, cy, 250, 250), fill=Rad(cx, cy, 250,
        [(0.78, "#5E8DFF", 0.0), (0.84, "#5E8DFF", 0.16), (1.0, "#5E8DFF", 0.0)]), dy=DY0)

    # --- sap (çerçeveden önce çizilir; çerçeve boyunun üstüne biner) -------------------
    # boyun
    neck = seg_rect(190, 268, 30)
    add(neck, fill=across(230, 30, [(0, "#5B606C"), (0.35, "#E6E9EF"), (0.6, "#9097A3"), (1, "#3C404A")]),
        stroke="#23262E", sw=3, shadow=(6, 12, 10, 0.5), dy=DY0)
    # tutacak (mat siyah)
    grip = seg_rect(286, 470, 60)
    add(grip, fill=across(380, 60, [(0, "#2B2D34"), (0.30, "#4A4D56"), (0.55, "#1B1C21"), (1, "#0E0F13")]),
        stroke="#050609", sw=4, shadow=(8, 16, 14, 0.55), dy=DY0)
    # tutacağın üstündeki yumuşak ışık çizgisi
    ha, hb = P(300, -17), P(458, -17)
    add(poly([ha, hb], False), stroke="#8A8E9A", sw=5, op=0.35, dy=DY0)
    # boyun ile tutacak arası gümüş yaka
    for (u0, u1, w) in ((262, 276, 38), (276, 290, 54)):
        add(seg_rect(u0, u1, w), fill=across((u0 + u1) / 2, w,
            [(0, "#4A4E58"), (0.30, "#F4F6FA"), (0.60, "#A5ABB6"), (1, "#41454F")]),
            stroke="#262932", sw=3, dy=DY0)
    # uç kapak
    add(seg_rect(466, 500, 58), fill=across(483, 58,
        [(0, "#4C505B"), (0.30, "#F2F4F8"), (0.62, "#A2A8B3"), (1, "#3E424C")]),
        stroke="#262932", sw=3, dy=DY0)
    # uç yüzey: mavi parıltı
    ex, ey = P(499, 0)
    add(ellipse(ex, ey, 9, 24, math.degrees(TH)), fill=Rad(ex, ey, 26,
        [(0, "#CFE0FF"), (0.5, "#6D9BF0"), (1, "#2D4F9E")]), stroke="#1E2840", sw=2, dy=DY0)

    # --- gümüş çerçeve ----------------------------------------------------------------
    R_OUT, R_MID, R_IN, R_GLASS = 204, 182, 168, 160
    add(ellipse(cx, cy, R_OUT, R_OUT),
        fill=Lin(cx - 170, cy - 190, cx + 170, cy + 190,
                 [(0, "#FFFFFF"), (0.28, "#D4D8DF"), (0.55, "#8D929D"), (0.78, "#C9CDD5"), (1, "#EEF0F4")]),
        stroke="#3A3E48", sw=4, shadow=(8, 16, 16, 0.6), dy=DY0)
    # iç eğim (ışık yönü ters: sol-üstte koyu, sağ-altta açık)
    add(ellipse(cx, cy, R_MID, R_MID),
        fill=Lin(cx - 150, cy - 160, cx + 150, cy + 160,
                 [(0, "#7A808C"), (0.45, "#BCC1CA"), (1, "#F6F7FA")]), dy=DY0)
    add(ellipse(cx, cy, R_IN, R_IN), fill="#0A0D18", dy=DY0)
    # dış kenarda ince parlak çizgi
    add(ellipse(cx, cy, R_OUT - 5, R_OUT - 5), stroke="#FFFFFF", sw=3, op=0.55, dy=DY0)

    # --- cam --------------------------------------------------------------------------
    glass = ellipse(cx, cy, R_GLASS, R_GLASS)
    add(glass, fill=Rad(cx - 60, cy - 70, 300,
        [(0, "#5878B0"), (0.30, "#2C3F69"), (0.70, "#141B31"), (1, "#0B0F1E")]), dy=DY0)
    # sağ-alt kenardaki mavi ışık halkası
    add(ellipse(cx, cy, R_GLASS - 5, R_GLASS - 5),
        stroke=Lin(cx - 120, cy - 120, cx + 130, cy + 130,
                   [(0, "#7DB0FF", 0.0), (0.55, "#7DB0FF", 0.0), (0.85, "#8DBBFF", 0.75), (1, "#B5D3FF", 0.95)]),
        sw=9, clip=glass, dy=DY0)
    # sol-üst parlama alanı
    glare = (Path().M(cx - 150, cy - 40)
             .C(cx - 140, cy - 105, cx - 85, cy - 148, cx - 20, cy - 158)
             .C(cx - 40, cy - 110, cx - 80, cy - 70, cx - 150, cy - 40).Z())
    add(glare, fill=Lin(cx - 150, cy - 150, cx - 30, cy - 50,
        [(0, "#FFFFFF", 0.55), (1, "#FFFFFF", 0.04)]), clip=glass, dy=DY0)
    # üstteki kavisli yansıma çizgisi
    add(Path().M(cx - 120, cy - 105).C(cx - 80, cy - 130, cx - 30, cy - 135, cx + 15, cy - 118),
        stroke="#FFFFFF", sw=4, op=0.40, clip=glass, dy=DY0)
    # küçük parlak nokta
    add(ellipse(cx - 78, cy - 98, 26, 10, -35), fill="#FFFFFF", op=0.55, clip=glass, dy=DY0)


# ----------------------------------------------------------------------------- PNG çizimi
def mask_fill(path, dy):
    m = Image.new("L", (N, N), 0)
    ImageDraw.Draw(m).polygon([(x * S, (y + dy) * S) for x, y in path.pts()], fill=255)
    return m


def mask_stroke(path, sw, dy):
    m = Image.new("L", (N, N), 0)
    d = ImageDraw.Draw(m)
    pts = [(x * S, (y + dy) * S) for x, y in path.pts()]
    if path.closed:
        pts = pts + [pts[0], pts[1]]
    d.line(pts, fill=255, width=max(1, round(sw * S)), joint="curve")
    r = sw * S / 2
    for p in (pts[0], pts[-1]):
        d.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=255)
    return m


def paint(canvas, mask, color, op, clip, dy):
    if clip is not None:
        mask = ImageChops.multiply(mask, clip)
    bb = mask.getbbox()
    if not bb:
        return
    m = np.asarray(mask.crop(bb)).astype(np.float32) / 255 * op
    h, w = m.shape
    if isinstance(color, str):
        rgb = np.empty((h, w, 3), np.float32); rgb[:] = hexrgb(color); a = m
    else:
        rgb, ga = grad_eval(color, bb, dy); a = m * ga
    layer = Image.fromarray(np.dstack([rgb, a * 255]).clip(0, 255).astype("uint8"), "RGBA")
    region = Image.alpha_composite(canvas.crop(bb), layer)
    canvas.paste(region, bb[:2])


def drop_shadow(canvas, union, sh, clip):
    dx, dy_, blur, op = sh
    bb = union.getbbox()
    if not bb:
        return
    pad = int((blur * 3 + abs(dx) + abs(dy_)) * S) + 4
    box = (max(0, bb[0] - pad), max(0, bb[1] - pad), min(N, bb[2] + pad), min(N, bb[3] + pad))
    m = union.crop(box)
    moved = Image.new("L", m.size, 0)
    moved.paste(m, (round(dx * S), round(dy_ * S)))
    moved = moved.filter(ImageFilter.GaussianBlur(blur * S))
    full = Image.new("L", (N, N), 0); full.paste(moved, box[:2])
    paint(canvas, full, "#000000", op, clip, 0)


def render_png(path):
    canvas = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    for sh in SHAPES:
        dy = sh["dy"]
        fm = mask_fill(sh["path"], dy) if sh["fill"] else None
        sm = mask_stroke(sh["path"], sh["sw"], dy) if sh["stroke"] else None
        clip = mask_fill(sh["clip"], dy) if sh["clip"] else None
        if sh["shadow"]:
            union = fm if sm is None else (sm if fm is None else ImageChops.lighter(fm, sm))
            drop_shadow(canvas, union, sh["shadow"], clip)
        if fm: paint(canvas, fm, sh["fill"], sh["op"], clip, dy)
        if sm: paint(canvas, sm, sh["stroke"], sh["op"], clip, dy)
    canvas.resize((W, W), Image.LANCZOS).save(path)


# ----------------------------------------------------------------------------- SVG yazımı
def paint_svg(color, defs, key):
    if color is None:
        return "none"
    if isinstance(color, str):
        return color
    gid = f"g{key}"
    if color[0] == "lin":
        _, x1, y1, x2, y2, stops = color
        head = f'<linearGradient id="{gid}" gradientUnits="userSpaceOnUse" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">'
        tail = "</linearGradient>"
    else:
        _, cx, cy, r, stops = color
        head = f'<radialGradient id="{gid}" gradientUnits="userSpaceOnUse" cx="{cx}" cy="{cy}" r="{r}">'
        tail = "</radialGradient>"
    body = "".join(
        f'<stop offset="{s[0]}" stop-color="{s[1]}"' + (f' stop-opacity="{s[2]}"' if len(s) > 2 else "") + "/>"
        for s in stops)
    defs.append(head + body + tail)
    return f"url(#{gid})"


def render_svg(path):
    defs, body = [], []
    open_dy = None
    for i, sh in enumerate(SHAPES):
        if sh["dy"] != open_dy:
            if open_dy not in (None, 0):
                body.append("</g>")
            if sh["dy"] != 0:
                body.append(f'<g transform="translate(0 {sh["dy"]})">')
            open_dy = sh["dy"]
        a = [f'd="{sh["path"].d()}"', f'fill="{paint_svg(sh["fill"], defs, f"{i}f")}"']
        if sh["stroke"]:
            a += [f'stroke="{paint_svg(sh["stroke"], defs, f"{i}s")}"', f'stroke-width="{sh["sw"]}"',
                  'stroke-linecap="round"', 'stroke-linejoin="round"']
        if sh["op"] != 1.0:
            a.append(f'opacity="{sh["op"]}"')
        if sh["shadow"]:
            dx, dy_, blur, op = sh["shadow"]
            defs.append(f'<filter id="s{i}" x="-25%" y="-25%" width="150%" height="150%" color-interpolation-filters="sRGB">'
                        f'<feDropShadow dx="{dx}" dy="{dy_}" stdDeviation="{blur}" flood-color="#000" flood-opacity="{op}"/></filter>')
            a.append(f'filter="url(#s{i})"')
        if sh["clip"]:
            defs.append(f'<clipPath id="c{i}"><path d="{sh["clip"].d()}"/></clipPath>')
            a.append(f'clip-path="url(#c{i})"')
        body.append("<path " + " ".join(a) + "/>")
    if open_dy not in (None, 0):
        body.append("</g>")
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{W}" viewBox="0 0 {W} {W}">\n'
           f'<title>Notlarım</title>\n<defs>\n' + "\n".join(defs) + "\n</defs>\n" + "\n".join(body) + "\n</svg>\n")
    open(path, "w", encoding="utf-8").write(svg)


if __name__ == "__main__":
    build()
    out = os.path.join(ROOT, "Resources")
    render_svg(os.path.join(out, "AppIcon.svg"))
    render_png(os.path.join(out, "AppIcon.png"))
    # Menü çubuğu simgesi: ana simgenin küçüğü (zemin kareyi kırpıp küçültür)
    big = Image.open(os.path.join(out, "AppIcon.png")).convert("RGBA")
    crop = big.crop((84, 84, 940, 940))
    for name, px in (("MenuIcon.png", 44), ("MenuIcon@3x.png", 66)):
        crop.resize((px, px), Image.LANCZOS).save(os.path.join(out, name))
    for px in (16, 32, 48, 128):                      # Chrome eklentisi simgeleri
        crop.resize((px, px), Image.LANCZOS).save(os.path.join(ROOT, "chrome-extension", "icons", f"icon{px}.png"))
    print("tamam:", len(SHAPES), "şekil")
