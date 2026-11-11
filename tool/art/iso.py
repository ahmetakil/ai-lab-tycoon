"""Tiny isometric SVG toolkit for AI Lab Tycoon art (shared style)."""
import math

C30 = math.cos(math.radians(30))

# ---- palette (style guide) ----
NAVY = '#2E3B6B'
DARK = '#1A2242'
STEEL = '#55658F'
SILVER = '#8E9CC4'
GREEN = '#39FF9F'
CYAN = '#3DD6FF'
AMBER = '#FFB547'
RED = '#FF6B6B'
OUT = '#080C1A'
WHITE = '#EAF2FF'


def _hex(c):
    c = c.lstrip('#')
    return [int(c[i:i + 2], 16) for i in (0, 2, 4)]


def shade(c, f):
    r = _hex(c)
    if f >= 0:
        r = [int(v + (255 - v) * f) for v in r]
    else:
        r = [int(v * (1 + f)) for v in r]
    return '#%02X%02X%02X' % tuple(max(0, min(255, v)) for v in r)


def iso(x, y, z):
    return ((x - y) * C30, (x + y) * 0.5 - z)


def fmt(pts):
    return ' '.join('%.1f,%.1f' % p for p in pts)


class Scene:
    def __init__(self, glow=4.0):
        self.els = []
        self.pts = []
        self.glow = glow
        self.defs = []

    # -- bookkeeping
    def _reg(self, pts):
        self.pts.extend(pts)

    def add(self, s, bbox=None):
        if bbox:
            self._reg(bbox)
        self.els.append(s)

    # -- 2D primitives (screen space)
    def poly2(self, pts, fill, stroke=OUT, sw=1.6, glow=False, opacity=1, extra=''):
        self._reg(pts)
        f = ' filter="url(#g)"' if glow else ''
        st = f' stroke="{stroke}" stroke-width="{sw}" stroke-linejoin="round"' if stroke else ''
        self.els.append(f'<polygon points="{fmt(pts)}" fill="{fill}"{st} opacity="{opacity}"{f} {extra}/>')

    def line2(self, pts, stroke, sw=2, glow=False, opacity=1, cap='round', dash=None):
        self._reg(pts)
        f = ' filter="url(#g)"' if glow else ''
        d = f' stroke-dasharray="{dash}"' if dash else ''
        self.els.append(f'<polyline points="{fmt(pts)}" fill="none" stroke="{stroke}" stroke-width="{sw}" '
                        f'stroke-linecap="{cap}" stroke-linejoin="round" opacity="{opacity}"{f}{d}/>')

    def path2(self, d, fill, bbox, stroke=OUT, sw=1.6, glow=False, opacity=1):
        self._reg(bbox)
        f = ' filter="url(#g)"' if glow else ''
        st = f' stroke="{stroke}" stroke-width="{sw}" stroke-linejoin="round" stroke-linecap="round"' if stroke else ''
        self.els.append(f'<path d="{d}" fill="{fill}"{st} opacity="{opacity}"{f}/>')

    def ellipse2(self, cx, cy, rx, ry, fill, stroke=OUT, sw=1.6, glow=False, opacity=1):
        self._reg([(cx - rx, cy - ry), (cx + rx, cy + ry)])
        f = ' filter="url(#g)"' if glow else ''
        st = f' stroke="{stroke}" stroke-width="{sw}"' if stroke else ''
        self.els.append(f'<ellipse cx="{cx:.1f}" cy="{cy:.1f}" rx="{rx:.1f}" ry="{ry:.1f}" fill="{fill}"{st} opacity="{opacity}"{f}/>')

    def aura(self, cx, cy, r, color, opacity=0.35):
        gid = 'a%d' % len(self.defs)
        self.defs.append(f'<radialGradient id="{gid}"><stop offset="0" stop-color="{color}" stop-opacity="{opacity}"/>'
                         f'<stop offset="1" stop-color="{color}" stop-opacity="0"/></radialGradient>')
        self.els.append(f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{r:.1f}" fill="url(#{gid})"/>')

    # -- 3D primitives
    def box(self, x, y, z, w, d, h, color=NAVY, top=None, left=None, right=None, sw=1.6, glow=False):
        tc = top or shade(color, 0.28)
        lc = left or color
        rc = right or shade(color, -0.32)
        T = [iso(x, y, z + h), iso(x + w, y, z + h), iso(x + w, y + d, z + h), iso(x, y + d, z + h)]
        R = [iso(x + w, y, z), iso(x + w, y + d, z), iso(x + w, y + d, z + h), iso(x + w, y, z + h)]
        L = [iso(x, y + d, z), iso(x + w, y + d, z), iso(x + w, y + d, z + h), iso(x, y + d, z + h)]
        for pts, c in ((R, rc), (L, lc), (T, tc)):
            self.poly2(pts, c, sw=sw, glow=glow)
        return (x, y, z, w, d, h)

    @staticmethod
    def fpt(b, face, u, v):
        x, y, z, w, d, h = b
        if face == 'top':
            return iso(x + u * w, y + v * d, z + h)
        if face == 'right':
            return iso(x + w, y + u * d, z + (1 - v) * h)
        if face == 'left':
            return iso(x + u * w, y + d, z + (1 - v) * h)
        raise ValueError(face)

    def frect(self, b, face, u0, v0, u1, v1, fill, glow=False, stroke=None, sw=1.0, opacity=1):
        pts = [self.fpt(b, face, u0, v0), self.fpt(b, face, u1, v0), self.fpt(b, face, u1, v1), self.fpt(b, face, u0, v1)]
        self.poly2(pts, fill, stroke=stroke, sw=sw, glow=glow, opacity=opacity)

    def fpoly(self, b, face, uv, fill, glow=False, stroke=None, sw=1.0, opacity=1):
        self.poly2([self.fpt(b, face, u, v) for u, v in uv], fill, stroke=stroke, sw=sw, glow=glow, opacity=opacity)

    def fline(self, b, face, uv, stroke, sw=2, glow=False, opacity=1):
        self.line2([self.fpt(b, face, u, v) for u, v in uv], stroke, sw=sw, glow=glow, opacity=opacity)

    def fcircle(self, b, face, cu, cv, ru, rv, fill, stroke=OUT, sw=1.2, glow=False, n=28, opacity=1):
        uv = [(cu + ru * math.cos(t), cv + rv * math.sin(t)) for t in (2 * math.pi * i / n for i in range(n))]
        self.fpoly(b, face, uv, fill, glow=glow, stroke=stroke, sw=sw, opacity=opacity)

    def line3(self, pts3, stroke, sw=2, glow=False, opacity=1, dash=None):
        self.line2([iso(*p) for p in pts3], stroke, sw=sw, glow=glow, opacity=opacity, dash=dash)

    def cyl(self, x, y, z, r, h, color=NAVY, top=None, sw=1.6, glow=False):
        """Vertical cylinder centred at iso (x,y), base z."""
        cx, cy = iso(x, y, z)
        rx, ry = r * C30 * 1.15, r * 0.66
        ty = cy - h
        side = shade(color, -0.15)
        d = (f'M{cx - rx:.1f},{ty:.1f} L{cx - rx:.1f},{cy:.1f} A{rx:.1f},{ry:.1f} 0 0 0 {cx + rx:.1f},{cy:.1f} '
             f'L{cx + rx:.1f},{ty:.1f} Z')
        self.path2(d, side, [(cx - rx, ty - ry), (cx + rx, cy + ry)], sw=sw, glow=glow)
        self.ellipse2(cx, ty, rx, ry, top or shade(color, 0.28), sw=sw, glow=glow)
        return cx, cy, rx, ry, ty

    # -- glyphs (screen space, centred at cx,cy, size s)
    def check(self, cx, cy, s, color=GREEN, sw=None):
        self.line2([(cx - s * .5, cy), (cx - s * .15, cy + s * .35), (cx + s * .55, cy - s * .4)], color, sw=sw or s * .22, glow=True)

    def cross(self, cx, cy, s, color=RED, sw=None):
        self.line2([(cx - s / 2, cy - s / 2), (cx + s / 2, cy + s / 2)], color, sw=sw or s * .2, glow=True)
        self.line2([(cx + s / 2, cy - s / 2), (cx - s / 2, cy + s / 2)], color, sw=sw or s * .2, glow=True)

    def bolt(self, cx, cy, s, color=AMBER, glow=True):
        p = [(0.15, -0.5), (-0.3, 0.08), (-0.02, 0.08), (-0.15, 0.5), (0.32, -0.12), (0.04, -0.12), (0.2, -0.5)]
        self.poly2([(cx + u * s, cy + v * s) for u, v in p], color, sw=s * 0.03, glow=glow)

    def sparkle(self, cx, cy, s, color=WHITE):
        p = []
        for i in range(8):
            t = math.pi / 4 * i - math.pi / 2
            r = s / 2 if i % 2 == 0 else s * 0.13
            p.append((cx + r * math.cos(t), cy + r * math.sin(t)))
        self.poly2(p, color, stroke=None, glow=True)

    def arrow(self, x0, y0, x1, y1, color=GREEN, sw=7):
        ang = math.atan2(y1 - y0, x1 - x0)
        hl = sw * 2.2
        bx, by = x1 - hl * math.cos(ang), y1 - hl * math.sin(ang)
        self.line2([(x0, y0), (bx, by)], color, sw=sw, glow=True)
        px, py = -math.sin(ang), math.cos(ang)
        self.poly2([(x1, y1), (bx + px * hl * .75, by + py * hl * .75), (bx - px * hl * .75, by - py * hl * .75)],
                   color, stroke=None, glow=True)

    # -- output
    def svg(self, pad=0.08, size=512, square=True, bg=None):
        xs = [p[0] for p in self.pts]
        ys = [p[1] for p in self.pts]
        x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
        w, h = x1 - x0, y1 - y0
        if square:
            m = max(w, h)
            x0 -= (m - w) / 2
            y0 -= (m - h) / 2
            w = h = m
        p = max(w, h) * pad
        vb = (x0 - p, y0 - p, w + 2 * p, h + 2 * p)
        g = self.glow * max(vb[2], vb[3]) / 300
        defs = (f'<filter id="g" filterUnits="userSpaceOnUse" x="{vb[0]:.1f}" y="{vb[1]:.1f}" width="{vb[2]:.1f}" height="{vb[3]:.1f}">'
                f'<feGaussianBlur stdDeviation="{g:.2f}" result="b"/>'
                f'<feMerge><feMergeNode in="b"/><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>'
                + ''.join(self.defs))
        bgr = f'<rect x="{vb[0]}" y="{vb[1]}" width="{vb[2]}" height="{vb[3]}" fill="{bg}"/>' if bg else ''
        W = size
        H = size if square else int(size * vb[3] / vb[2])
        return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" '
                f'viewBox="{vb[0]:.1f} {vb[1]:.1f} {vb[2]:.1f} {vb[3]:.1f}"><defs>{defs}</defs>{bgr}'
                + '\n'.join(self.els) + '</svg>')
