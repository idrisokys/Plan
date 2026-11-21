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
    INK = "#4B2108"        # koyu kahverengi çizgi
    # --- zemin -------------------------------------------------------------
    body = superellipse(512, 512, 412, 5.0)
    add(body, fill=Lin(512, 100, 512, 924, [(0, "#2D9CFF"), (0.38, "#0B55CC"), (0.78, "#08317F"), (1, "#061E55")]),
        shadow=(0, 14, 16, 0.45), dy=0)
    add(body, fill=Rad(512, 150, 540, [(0, "#FFFFFF", 0.38), (0.55, "#FFFFFF", 0.06), (1, "#FFFFFF", 0.0)]),
        clip=body, dy=0)
    add(body, stroke="#FFFFFF", sw=4, op=0.22, clip=body, dy=0)

    # --- kitabın altındaki zemin gölgesi ----------------------------------------
    add(ellipse(512, 770, 340, 34), fill="#02123A", op=0.45, shadow=(0, 0, 18, 0.5))

    # --- kitap -------------------------------------------------------------------
    add(rrect(196, 376, 632, 372, 30), fill=Lin(512, 376, 512, 748, [(0, "#CB7A2C"), (1, "#7E3E12")]),
        stroke=INK, sw=8, shadow=(0, 16, 14, 0.45))
    add(rrect(212, 392, 600, 340, 22), stroke="#E7A85C", sw=4, op=0.55)

    left = (Path().M(512, 404).C(470, 372, 372, 360, 258, 384).L(258, 690)
            .C(372, 664, 470, 676, 512, 710).Z())
    right = mirror(left)
    for pg in (shift(left, 0, 16), shift(right, 0, 16)):                   # sayfa destesi
        add(pg, fill="#DDBF8C", stroke="#5A2A0C", sw=7)
    add(left, fill=Lin(258, 0, 512, 0, [(0, "#FFF7E4"), (1, "#F0DBB2")]), stroke="#5A2A0C", sw=7)
    add(right, fill=Lin(766, 0, 512, 0, [(0, "#FFF7E4"), (1, "#F0DBB2")]), stroke="#5A2A0C", sw=7)
    add(poly([(512, 404), (512, 710)], False), stroke="#C7A06A", sw=6)

    for i in range(4):                                                      # sol sayfa yazı çizgileri
        y = 444 + i * 44
        add(Path().M(300, y + 6).C(340, y - 6, 392, y - 8, 430, y + 2), stroke="#D8BC8E", sw=8)
    for i in range(5):                                                      # sağ sayfa yazı çizgileri
        y = 442 + i * 44
        add(Path().M(584, y + 2).C(622, y - 8, 676, y - 6, 722, y + 6), stroke="#D8BC8E", sw=8)

    ribbon = Path().M(440, 366).L(506, 376).L(506, 508).L(473, 484).L(440, 508).Z()
    add(ribbon, fill=Lin(440, 366, 506, 508, [(0, "#54B0FF"), (1, "#1B6BD0")]), stroke="#0F3F85", sw=6,
        shadow=(2, 6, 5, 0.35))

    # --- büyüteç -----------------------------------------------------------------
    cx, cy = 378, 612
    hx0, hy0, hx1, hy1 = 462, 696, 562, 800
    add(poly([(hx0, hy0), (hx1, hy1)], False), stroke="#4A2208", sw=58, shadow=(0, 14, 12, 0.4))
    add(poly([(hx0, hy0), (hx1, hy1)], False), stroke=Lin(440, 700, 580, 800, [(0, "#B76F36"), (1, "#7A3F18")]), sw=42)
    add(poly([(hx0 - 6, hy0 - 6), (hx1 - 6, hy1 - 8)], False), stroke="#D79A60", sw=8, op=0.7)
    add(poly([(hx0 + 10, hy0 + 10), (hx0 + 34, hy0 + 36)], False), stroke="#4A2208", sw=54)
    add(poly([(hx0 + 10, hy0 + 10), (hx0 + 34, hy0 + 36)], False), stroke="#F3B93A", sw=40)

    ring = ellipse(cx, cy, 124, 124)
    glass = ellipse(cx, cy, 94, 94)
    add(ring, fill=Lin(260, 500, 500, 724, [(0, "#FFE680"), (0.5, "#F5B72E"), (1, "#D98A14")]),
        stroke="#6B3A08", sw=8, shadow=(0, 14, 12, 0.4))
    add(ellipse(cx, cy, 100, 100), fill="#8A5A10")
    add(glass, fill=Rad(cx - 40, cy - 44, 150, [(0, "#FFFFFF", 0.95), (0.55, "#CFE0F6", 0.9), (1, "#8FB0DE", 0.92)]),
        stroke="#7A5A1A", sw=4)
    for i, y in enumerate((594, 636, 678)):                                 # camın içinde büyüyen yazı
        add(Path().M(280, y + 8).C(330, y - 6, 420, y - 6, 476, y + 6), stroke="#6F88B0", sw=9, op=0.5, clip=glass)
    add(ellipse(cx - 38, cy - 48, 44, 20, -38), fill="#FFFFFF", op=0.7)

    # --- tüy kalem ---------------------------------------------------------------
    P0, P1, P2 = (700, 872), (728, 610), (872, 236)

    def B(t):
        u = 1 - t
        return (u*u*P0[0] + 2*u*t*P1[0] + t*t*P2[0], u*u*P0[1] + 2*u*t*P1[1] + t*t*P2[1])

    def nrm(t):
        u = 1 - t
        tx = 2*u*(P1[0]-P0[0]) + 2*t*(P2[0]-P1[0])
        ty = 2*u*(P1[1]-P0[1]) + 2*t*(P2[1]-P1[1])
        l = math.hypot(tx, ty)
        return (-ty / l, tx / l)                 # sağa bakan normal

    T0, WL, WR, NS = 0.30, 84, 98, 34
    NOTCH = {(1, 9): 0.52, (1, 16): 0.50, (1, 23): 0.55, (-1, 12): 0.55, (-1, 20): 0.55}

    def width(s):
        return math.sin(math.pi * (s ** 0.75)) ** 0.85

    def side(sign, wmax):
        pts = []
        for i in range(NS + 1):
            s = i / NS
            t = T0 + (1 - T0) * s
            tooth = (1.0 if i % 2 == 0 else 0.90) * NOTCH.get((sign, i), 1.0)
            tt = min(1.0, t + (0.012 if i % 2 else 0))
            bx, by = B(tt); nx, ny = nrm(tt)
            w = wmax * width(s) * tooth
            pts.append((bx + sign * nx * w, by + sign * ny * w))
        return pts

    left_pts = side(-1, WL)
    right_pts = side(+1, WR)
    vane = poly(left_pts + right_pts[::-1])
    add(vane, fill=Lin(700, 820, 900, 250, [(0, "#F4A323"), (0.5, "#FFC93C"), (1, "#FFE98A")]),
        stroke="#6B3A08", sw=7, shadow=(0, 14, 14, 0.4))
    for k in range(1, 12):                                                  # tüy telleri
        s = k / 12
        t = T0 + (1 - T0) * s
        bx, by = B(t)
        for sign, wmax in ((-1, WL), (1, WR)):
            tt = min(1.0, t + 0.07)
            ex, ey = B(tt); nx, ny = nrm(tt)
            w = wmax * width(min(1.0, s + 0.07)) * 0.78
            add(poly([(bx, by), (ex + sign * nx * w, ey + sign * ny * w)], False),
                stroke="#C77F18", sw=4, op=0.55)
    shaft = poly([B(0.12 + 0.88 * i / 40) for i in range(41)], False)
    add(shaft, stroke="#6B3A08", sw=19)
    add(shaft, stroke="#FFE9A0", sw=10)

    # uç (nib)
    nl = (B(0.20)[0] + nrm(0.20)[0] * -17, B(0.20)[1] + nrm(0.20)[1] * -17)
    nr = (B(0.20)[0] + nrm(0.20)[0] * 17, B(0.20)[1] + nrm(0.20)[1] * 17)
    nib = poly([B(0.0), nl, nr])
    add(nib, fill=Lin(690, 780, 740, 880, [(0, "#FFE27A"), (1, "#E9A21F")]), stroke="#6B3A08", sw=6)
    add(poly([B(0.015), B(0.14)], False), stroke="#6B3A08", sw=4)
    add(ellipse(B(0.17)[0], B(0.17)[1], 5, 5), fill="#6B3A08")


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
    print("tamam:", len(SHAPES), "şekil")
