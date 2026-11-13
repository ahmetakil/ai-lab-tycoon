#!/usr/bin/env python3
"""World-map art for AI Lab Tycoon: one cutaway isometric room per RoomDef
(ground plate + floor + two back walls + props), plus the parents' house.

Same pipeline as the other generators: Python writes SVG (iso helpers in
iso.py), rsvg-convert rasterizes, ImageMagick compresses.

Geometry contract with the Flutter side (lib/ui/world/): one grid cell is
U = 100 SVG units, iso(x, y, z) from iso.py, the floor's back corner is
the SVG origin, the placement grid starts at (m*U, m*U) where m is the
room's prop margin. A tile sprite's footprint is exactly one cell, so the
existing tile_*.png art sits on these floor diamonds unchanged.

It also writes lib/ui/world/room_art.g.dart with each image's viewBox,
the margin, and the light/LED/seat points the game animates on top.

Usage (from repo root):
    python3 tool/art/generate_rooms.py [out_dir]   # default: assets/images
"""
import math
import os
import random
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from iso import C30, Scene, iso, shade, OUT as INK  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
OUTDIR = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.join(ROOT, 'assets', 'images')
DART = os.path.join(ROOT, 'lib', 'ui', 'world', 'room_art.g.dart')
TMP = tempfile.mkdtemp(prefix='rooms_')
U = 100.0

# Flat-drawing transforms: draw in 2D, land on the floor / a back wall.
FLOOR_M = f'matrix({C30:.5f} 0.5 {-C30:.5f} 0.5 0 0)'  # flat (x, y) -> iso(x, y, 0)


def lw_m(L):
    """Left back wall (plane x=0). Flat u runs from the front end (y=L) to the
    back corner (y=0) so text reads left-to-right; flat v = -z."""
    return f'matrix({C30:.5f} -0.5 0 1 {-C30 * L:.3f} {0.5 * L:.3f})'


RW_M = f'matrix({C30:.5f} 0.5 0 1 0 0)'  # right back wall (plane y=0): u = x, v = -z


def g(m, body, extra=''):
    return f'<g transform="{m}" {extra}>{body}</g>'


def rect(x, y, w, h, fill, op=1, stroke=None, sw=1, rx=0, extra=''):
    st = f' stroke="{stroke}" stroke-width="{sw}"' if stroke else ''
    return f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" rx="{rx}" fill="{fill}" opacity="{op}"{st} {extra}/>'


def circ(x, y, r, fill, op=1, extra=''):
    return f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r:.1f}" fill="{fill}" opacity="{op}" {extra}/>'


def path(d, stroke, sw=2, op=1, fill='none', extra=''):
    return (f'<path d="{d}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" stroke-linecap="round" '
            f'stroke-linejoin="round" opacity="{op}" {extra}/>')


def text(x, y, s, size, fill, op=1, weight='bold', anchor='start', family='Helvetica, Arial, sans-serif'):
    return (f'<text x="{x:.1f}" y="{y:.1f}" font-family="{family}" font-size="{size}" font-weight="{weight}" '
            f'fill="{fill}" opacity="{op}" text-anchor="{anchor}">{s}</text>')


class Room:
    def __init__(self, rid, w, h, m, wall, ground, glow=3.0):
        self.id = rid
        self.w, self.h, self.m = w, h, m
        self.L = (max(w, h) + m) * U  # square floor
        self.wall = wall
        self.ground = ground
        self.s = Scene(glow=glow)
        self.lights = []  # (kind, x, y, color)
        self.seat = None
        self.defs = []

    # ---- bookkeeping
    def add(self, el):
        self.s.els.append(el)

    def grad(self, gid, stops, kind='linear', **attrs):
        a = ' '.join(f'{k.replace("_", "-")}="{v}"' for k, v in attrs.items())
        st = ''.join(f'<stop offset="{o}" stop-color="{c}" stop-opacity="{op}"/>' for o, c, op in stops)
        self.defs.append(f'<{kind}Gradient id="{gid}" {a}>{st}</{kind}Gradient>')
        return f'url(#{gid})'

    def light(self, kind, p, color='#FFFFFF'):
        self.lights.append((kind, p[0], p[1], color))

    @property
    def grid0(self):
        return self.m * U

    # ---- standard parts
    def ground_plate(self, color, body=''):
        """Exterior ground under and around the room, faded out with a radial mask."""
        L, G = self.L, self.ground
        fade = self.grad(f'gp_{self.id}', [(0, '#FFF', 1), (0.55, '#FFF', 0.85), (1, '#FFF', 0)], 'radial',
                         gradientUnits='userSpaceOnUse', cx=L / 2, cy=L / 2, r=L / 2 + G)
        self.defs.append(f'<mask id="gm_{self.id}" maskUnits="userSpaceOnUse" x="{-G - L}" y="{-G - L}" '
                         f'width="{3 * L + 2 * G}" height="{3 * L + 2 * G}">'
                         f'<rect x="{-G}" y="{-G}" width="{L + 2 * G}" height="{L + 2 * G}" fill="{fade}"/></mask>')
        self.add(g(FLOOR_M, f'<g mask="url(#gm_{self.id})">' + rect(-G, -G, L + 2 * G, L + 2 * G, color) + body + '</g>'))

    def floor(self, body):
        L = self.L
        clip = f'fl_{self.id}'
        self.defs.append(f'<clipPath id="{clip}"><rect x="0" y="0" width="{L}" height="{L}"/></clipPath>')
        self.add(g(FLOOR_M, f'<g clip-path="url(#{clip})">{body}</g>'))

    def floor_ao(self, op=0.45):
        """Soft shadow where the floor meets the back walls."""
        L = self.L
        a = self.grad(f'aoa_{self.id}', [(0, '#000', op), (1, '#000', 0)], x1=0, y1=0, x2=0, y2=1)
        b = self.grad(f'aob_{self.id}', [(0, '#000', op), (1, '#000', 0)], x1=0, y1=0, x2=1, y2=0)
        self.add(g(FLOOR_M, rect(0, 0, L, 70, a) + rect(0, 0, 70, L, b)))

    def walls(self, left_body, right_body, left_color, right_color, cap='#20263A', thick=14):
        L, H, t = self.L, self.wall, thick
        # wall faces with their own flat drawing, clipped to the wall
        self.defs.append(f'<clipPath id="wc_{self.id}"><rect x="0" y="{-H}" width="{L}" height="{H}"/></clipPath>')
        clip = f'clip-path="url(#wc_{self.id})"'
        self.add(g(lw_m(L), f'<g {clip}>' + rect(0, -H, L, H, left_color) + left_body + '</g>'))
        self.add(g(RW_M, f'<g {clip}>' + rect(0, -H, L, H, right_color) + right_body + '</g>'))
        # caps (cutaway top edge) and front end faces
        self.s.poly2([iso(0, L, H), iso(0, 0, H), iso(L, 0, H), iso(L, -t, H), iso(-t, -t, H), iso(-t, L, H)], cap, sw=1.4)
        self.s.poly2([iso(0, L, 0), iso(-t, L, 0), iso(-t, L, H), iso(0, L, H)], shade(cap, -0.25), sw=1.2)
        self.s.poly2([iso(L, 0, 0), iso(L, -t, 0), iso(L, -t, H), iso(L, 0, H)], shade(cap, 0.1), sw=1.2)
        # inner corner line
        self.s.line2([iso(0, 0, 0), iso(0, 0, H)], '#000000', sw=1.2, opacity=0.35)

    def baseboard(self, color, h=10):
        L = self.L
        self.add(g(lw_m(L), rect(0, -h, L, h, color)))
        self.add(g(RW_M, rect(0, -h, L, h, color)))

    def grid_outline(self, color, op=0.5, sw=2, dash=None):
        g0, W, Hh = self.grid0, self.w * U, self.h * U
        d = f' stroke-dasharray="{dash}"' if dash else ''
        self.add(g(FLOOR_M, f'<rect x="{g0}" y="{g0}" width="{W}" height="{Hh}" fill="none" stroke="{color}" '
                            f'stroke-width="{sw}" opacity="{op}"{d}/>'))

    # ---- output
    def viewbox(self):
        L, G, H = self.L, self.ground, self.wall
        x0 = -(L + G) * C30
        top = max(H, G * 1.0) + 30
        return (x0, -top, -2 * x0, (L + G) + top + 10)

    def svg(self):
        vb = self.viewbox()
        gl = self.s.glow * vb[2] / 900
        defs = (f'<filter id="g" filterUnits="userSpaceOnUse" x="{vb[0]:.1f}" y="{vb[1]:.1f}" width="{vb[2]:.1f}" '
                f'height="{vb[3]:.1f}"><feGaussianBlur stdDeviation="{gl:.2f}" result="b"/><feMerge><feMergeNode in="b"/>'
                f'<feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>' + ''.join(self.s.defs + self.defs))
        return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{vb[0]:.1f} {vb[1]:.1f} {vb[2]:.1f} {vb[3]:.1f}">'
                f'<defs>{defs}</defs>' + '\n'.join(self.s.els) + '</svg>')


# =============================================================== props
def box(r, x, y, z, w, d, h, color, **kw):
    return r.s.box(x, y, z, w, d, h, color=color, **kw)


def cardboard(r, x, y, z, w, d, h, label=None, seed=0):
    b = box(r, x, y, z, w, d, h, '#9C7445', top='#B98C57', sw=1.2)
    r.s.frect(b, 'top', 0.45, 0, 0.55, 1, '#C9B28A', opacity=0.8)
    r.s.frect(b, 'left', 0.45, 0, 0.55, 0.35, '#C9B28A', opacity=0.8)
    return b


def fridge(r, x, y):
    b = box(r, x, y, 0, 62, 60, 165, '#CFC6A6', top='#E2DBC0', right='#9E9677')
    r.s.frect(b, 'left', 0.02, 0.36, 0.98, 0.39, '#7E7660')
    r.s.frect(b, 'left', 0.82, 0.08, 0.88, 0.3, '#8D8A80')
    r.s.frect(b, 'left', 0.82, 0.45, 0.88, 0.7, '#8D8A80')
    # rust, magnets, a crayon drawing
    rnd = random.Random(3)
    for _ in range(9):
        u, v = rnd.uniform(0.05, 0.95), rnd.uniform(0.75, 0.98)
        r.s.fcircle(b, 'left', u, v, 0.03, 0.012, '#7A4B2A', stroke=None, opacity=0.6)
    r.s.frect(b, 'left', 0.2, 0.12, 0.55, 0.3, '#F4F1E6', stroke=INK, sw=0.6)
    r.s.fline(b, 'left', [(0.25, 0.25), (0.33, 0.17), (0.4, 0.24), (0.5, 0.15)], '#D04545', sw=1.2)
    for u, c in ((0.15, '#E04B4B'), (0.62, '#3D7BE0'), (0.7, '#F2C230')):
        r.s.fcircle(b, 'left', u, 0.5, 0.035, 0.015, c, stroke=None)


def mattress(r, x, y, w, d):
    b = box(r, x, y, 0, w, d, 20, '#B7A78A', top='#D8CDB2', sw=1.3)
    rnd = random.Random(5)
    for _ in range(4):
        u, v = rnd.uniform(0.2, 0.8), rnd.uniform(0.2, 0.8)
        r.s.fcircle(b, 'top', u, v, 0.12, 0.08, '#A08E68', stroke=None, opacity=0.5)
    for k in range(1, 6):
        r.s.fline(b, 'top', [(k / 6, 0.05), (k / 6, 0.95)], '#BFB295', sw=1, opacity=0.6)
    box(r, x + 10, y + 8, 20, w * 0.7, 30, 10, '#E8E2D4', sw=1.1)  # pillow
    box(r, x + 6, y + d * 0.45, 20, w * 0.85, d * 0.45, 6, '#5E6E8C', top='#71819F', sw=1.1)  # blanket


def lawnmower(r, x, y):
    for (wx, wy) in ((x + 6, y + 6), (x + 54, y + 6), (x + 6, y + 56), (x + 54, y + 56)):
        cx, cy = iso(wx, wy, 8)
        r.s.ellipse2(cx, cy, 9, 7, '#1C1C22', sw=1.2)
    b = box(r, x, y, 8, 60, 62, 22, '#B4362F', top='#D2493F')
    r.s.cyl(x + 30, y + 30, 30, 14, 10, color='#3B3B44')
    r.s.line3([(x + 55, y + 10, 30), (x + 110, y - 10, 105)], INK, sw=6)
    r.s.line3([(x + 55, y + 10, 30), (x + 110, y - 10, 105)], '#9AA0AE', sw=3.5)
    r.s.line3([(x + 55, y + 52, 30), (x + 110, y + 40, 105)], INK, sw=6)
    r.s.line3([(x + 55, y + 52, 30), (x + 110, y + 40, 105)], '#9AA0AE', sw=3.5)
    r.s.line3([(x + 110, y - 10, 105), (x + 110, y + 40, 105)], INK, sw=7)
    r.s.line3([(x + 110, y - 10, 105), (x + 110, y + 40, 105)], '#2E2E36', sw=4.5)
    return b


def shelf(r, x, y, w, d, h, levels, items, seed=1):
    rnd = random.Random(seed)
    posts = [(x, y), (x + w - 5, y), (x, y + d - 5), (x + w - 5, y + d - 5)]
    for i, (px, py) in enumerate(posts[:2]):
        box(r, px, py, 0, 5, 5, h, '#6E6A60', sw=0.8)
    for k in range(levels):
        z = 8 + k * (h - 10) / (levels - 1 if levels > 1 else 1)
        box(r, x, y, z, w, d, 4, '#8A7A5C', top='#A39070', sw=0.9)
        cx = x + 6
        if k < levels - 1:
            while cx < x + w - 22:
                kind = rnd.choice(items)
                if kind == 'can':
                    c = rnd.choice(['#C94A3C', '#3C78C9', '#D8C24A', '#E6E6E0'])
                    r.s.cyl(cx + 9, y + d / 2, z + 4, 9, 20, color=c)
                    cx += 22
                elif kind == 'box':
                    bw = rnd.uniform(16, 30)
                    cardboard(r, cx, y + 4, z + 4, bw, d - 10, rnd.uniform(14, (h - 10) / levels - 6))
                    cx += bw + 4
                elif kind == 'part':
                    c = rnd.choice(['#2E3B6B', '#3B4568', '#4A5A8A'])
                    pb = box(r, cx, y + 6, z + 4, 26, d - 14, 10, c, sw=0.8)
                    r.s.frect(pb, 'left', 0.1, 0.3, 0.6, 0.7, rnd.choice(['#39FF9F', '#3DD6FF']), glow=True)
                    cx += 30
                else:
                    cx += 12
    for px, py in posts[2:]:
        box(r, px, py, 0, 5, 5, h, '#6E6A60', sw=0.8)


def desk(r, x, y, w, d, top='#7A5A3A', z=50):
    for (lx, ly) in ((x + 4, y + 4), (x + w - 10, y + 4), (x + 4, y + d - 10), (x + w - 10, y + d - 10)):
        box(r, lx, ly, 0, 6, 6, z, shade(top, -0.4), sw=0.8)
    return box(r, x, y, z, w, d, 6, top, top=shade(top, 0.2), sw=1.2)


def monitor(r, x, y, z, w=34, h=26, glow='#7FD8FF', crt=False):
    if crt:
        b = box(r, x, y, z, w, 30, h, '#C8C2AE', sw=1.1)
        r.s.frect(b, 'left', 0.1, 0.12, 0.9, 0.8, glow, glow=True)
        return iso(x + w / 2, y + 30, z + h / 2)
    box(r, x + w / 2 - 3, y + 4, z, 6, 6, 8, '#2A2F3A', sw=0.8)
    b = box(r, x, y + 4, z + 8, w, 4, h, '#1A1E28', sw=1.0)
    r.s.frect(b, 'left', 0.06, 0.1, 0.94, 0.88, glow, glow=True)
    return iso(x + w / 2, y + 8, z + 8 + h / 2)


def chair(r, x, y, color='#3A3F52'):
    cx, cy = iso(x + 14, y + 14, 4)
    r.s.ellipse2(cx, cy, 14, 7, '#1A1C24', sw=1)
    r.s.line3([(x + 14, y + 14, 4), (x + 14, y + 14, 26)], '#222', sw=3)
    box(r, x, y, 26, 28, 28, 6, color, sw=1)
    box(r, x, y + 24, 30, 28, 5, 34, color, sw=1)


def server_cabinet(r, x, y, w, d, h, color='#1E2436', led_cols=('#39FF9F', '#3DD6FF'), rows=6, seed=2, face='left'):
    b = box(r, x, y, 0, w, d, h, color, sw=1.2)
    rnd = random.Random(seed)
    for i in range(rows):
        v0 = 0.06 + i * 0.88 / rows
        v1 = v0 + 0.88 / rows * 0.8
        r.s.frect(b, face, 0.08, v0, 0.92, v1, '#0E121C', stroke=INK, sw=0.5)
        for k in range(3):
            u = 0.16 + k * 0.08
            p = Scene.fpt(b, face, u, (v0 + v1) / 2)
            r.light('led', p, rnd.choice(led_cols))
    return b


def crah(r, x, y, w, d, h, face='left', color='#B9C1CF'):
    b = box(r, x, y, 0, w, d, h, color, sw=1.2)
    for k in range(7):
        v = 0.1 + k * 0.06
        r.s.frect(b, face, 0.08, v, 0.92, v + 0.03, shade(color, -0.35))
    r.s.frect(b, face, 0.25, 0.62, 0.75, 0.72, '#13202C')
    p = Scene.fpt(b, face, 0.32, 0.67)
    r.light('led', p, '#3DD6FF')
    p = Scene.fpt(b, face, 0.42, 0.67)
    r.light('led', p, '#39FF9F')
    return b


def cable_tray_right(r, z, x0, x1, y=18, cables=('#FF8A3D', '#3D7BE0', '#FFD447')):
    """Ladder tray hanging along the right wall."""
    for k, c in enumerate(cables):
        r.s.line3([(x0, y - 6 + k * 5, z + 3), (x1, y - 6 + k * 5, z + 3)], c, sw=3.2)
    r.s.line3([(x0, y - 10, z), (x1, y - 10, z)], '#8E9CC4', sw=2.2)
    r.s.line3([(x0, y + 10, z), (x1, y + 10, z)], '#8E9CC4', sw=2.2)
    xx = x0
    while xx <= x1:
        r.s.line3([(xx, y - 10, z), (xx, y + 10, z)], '#6E7AA0', sw=1.4)
        xx += 30


def cable_tray_left(r, z, y0, y1, x=18, cables=('#FF8A3D', '#3D7BE0', '#FFD447')):
    for k, c in enumerate(cables):
        r.s.line3([(x - 6 + k * 5, y0, z + 3), (x - 6 + k * 5, y1, z + 3)], c, sw=3.2)
    r.s.line3([(x - 10, y0, z), (x - 10, y1, z)], '#8E9CC4', sw=2.2)
    r.s.line3([(x + 10, y0, z), (x + 10, y1, z)], '#8E9CC4', sw=2.2)
    yy = y0
    while yy <= y1:
        r.s.line3([(x - 10, yy, z), (x + 10, yy, z)], '#6E7AA0', sw=1.4)
        yy += 30


def pipe(r, pts, color, sw=8, glow=False):
    r.s.line3(pts, INK, sw=sw + 3)
    r.s.line3(pts, color, sw=sw, glow=glow)
    r.s.line3(pts, shade(color, 0.6), sw=max(1.2, sw * 0.25), opacity=0.8)


def led_strip_right(r, z, x0, x1, step, colors):
    rnd = random.Random(int(z + x0))
    x = x0
    while x <= x1:
        r.light('led', iso(x, 0, z), rnd.choice(colors))
        x += step


def led_strip_left(r, z, y0, y1, step, colors):
    rnd = random.Random(int(z + y0) + 7)
    y = y0
    while y <= y1:
        r.light('led', iso(0, y, z), rnd.choice(colors))
        y += step


def loss_board(x, y, w, h, title='loss', color='#D04545', alt='#3D7BE0', messy=True):
    """Whiteboard with hand-drawn loss curves (flat wall coords)."""
    s = rect(x - 4, y - 4, w + 8, h + 8, '#9AA0AE', rx=2) + rect(x, y, w, h, '#F3F5F0')
    ax = x + 14
    s += path(f'M{ax},{y + 10} L{ax},{y + h - 14} L{x + w - 10},{y + h - 14}', '#3A3F52', sw=2)
    pts = []
    for i in range(24):
        t = i / 23
        px = ax + 4 + t * (w - 30)
        py = y + 18 + (h - 40) * (1 - math.exp(-4 * t)) ** 0.9
        py = y + h - 18 - (h - 40) * math.exp(-3.5 * t) - (2 if messy and i % 3 == 0 else 0)
        pts.append((px, py))
    s += path('M' + ' L'.join(f'{a:.1f},{b:.1f}' for a, b in pts), color, sw=2.6)
    pts2 = [(a, b - 10 - 4 * math.sin(i)) for i, (a, b) in enumerate(pts)]
    s += path('M' + ' L'.join(f'{a:.1f},{b:.1f}' for a, b in pts2), alt, sw=2, op=0.8)
    s += text(ax + 6, y + 16, title, 11, '#3A3F52', weight='bold', family='Comic Sans MS, Chalkboard, sans-serif')
    if messy:
        s += text(x + w - 60, y + 30, 'AGI??', 12, '#D04545', family='Comic Sans MS, Chalkboard, sans-serif')
        s += path(f'M{x + w - 66},{y + 34} l50,0', '#D04545', sw=1.4)
    return s


def poster(x, y, w, h, bg, fg, label, sub=''):
    s = rect(x, y, w, h, bg, stroke='#000000', sw=1)
    s += text(x + w / 2, y + h * 0.45, label, min(16, w / max(4, len(label)) * 1.6), fg, anchor='middle')
    if sub:
        s += text(x + w / 2, y + h * 0.75, sub, 8, fg, op=0.8, anchor='middle', weight='normal')
    return s


# =============================================================== rooms
def garage():
    r = Room('garage', 4, 4, 1.6, wall=210, ground=170)
    L, g0 = r.L, r.grid0
    rnd = random.Random(1)
    # yard: lawn with a driveway strip in front
    lawn = ''.join(circ(rnd.uniform(-170, L + 170), rnd.uniform(-170, L + 170), rnd.uniform(2, 6), '#3E5A2E', 0.6)
                   for _ in range(160))
    drive = rect(g0 - 20, L, L - g0 + 40, 170, '#5A5852') + ''.join(
        rect(g0 - 20, L + 60 * k, L - g0 + 40, 2, '#3E3D39', 0.8) for k in range(1, 3))
    r.ground_plate('#2C4224', body=lawn + drive)
    # grimy concrete
    fl = rect(0, 0, L, L, '#5C5A52')
    for _ in range(140):
        fl += circ(rnd.uniform(0, L), rnd.uniform(0, L), rnd.uniform(4, 26), rnd.choice(['#46443D', '#6A675D', '#3C3A34']),
                   rnd.uniform(0.15, 0.4))
    for k in range(1, 4):
        fl += rect(k * L / 4, 0, 2.5, L, '#33312C', 0.8) + rect(0, k * L / 4, L, 2.5, '#33312C', 0.8)
    # oil stain (rainbow rim) and cracks
    ox, oy = g0 + 250, g0 + 280
    fl += f'<ellipse cx="{ox}" cy="{oy}" rx="78" ry="58" fill="#1C1B19" opacity="0.75"/>'
    fl += f'<ellipse cx="{ox + 6}" cy="{oy - 4}" rx="70" ry="50" fill="none" stroke="#6A4D8C" stroke-width="3" opacity="0.35"/>'
    fl += f'<ellipse cx="{ox - 30}" cy="{oy + 50}" rx="22" ry="14" fill="#1C1B19" opacity="0.7"/>'
    fl += path(f'M{g0 + 40},{g0 + 60} l40,30 l10,45 l38,22 l20,50', '#2A2925', sw=2.2, op=0.9)
    fl += path(f'M{L - 60},{g0 + 30} l-30,40 l-6,40', '#2A2925', sw=2, op=0.9)
    # extension cord from the wall outlet to the grid
    fl += path(f'M{g0 + 120},{4} C{g0 + 140},{80} {g0 + 40},{100} {g0 + 70},{g0 + 30}', '#E8A33D', sw=5)
    r.floor(fl)
    r.floor_ao(0.55)
    # walls: bare cinder block (left), unpainted drywall (right)
    blocks = ''
    for row in range(int(r.wall / 26) + 1):
        y = -r.wall + row * 26
        blocks += rect(0, y, L, 2, '#4E4C45', 0.9)
        off = 0 if row % 2 else 30
        for k in range(int(L / 60) + 2):
            blocks += rect(off + k * 60, y, 2, 26, '#4E4C45', 0.9)
    blocks += f'<rect x="0" y="{-r.wall}" width="{L}" height="{r.wall}" fill="url(#lwgrime)"/>'
    r.defs.append('<linearGradient id="lwgrime" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#000" stop-opacity="0.35"/>'
                  '<stop offset="0.7" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#3A2A14" stop-opacity="0.35"/></linearGradient>')
    # dusty little window (night outside) on the left wall
    blocks += rect(150, -170, 120, 70, '#7B7669') + rect(156, -164, 108, 58, '#14203A')
    blocks += rect(209, -164, 3, 58, '#7B7669') + rect(156, -137, 108, 3, '#7B7669')
    blocks += circ(240, -150, 3, '#F4F1E6', 0.9) + circ(180, -126, 1.5, '#F4F1E6', 0.7)
    blocks += path('M160,-110 q20,-18 40,-4 q16,10 30,-6', '#AFA690', sw=1, op=0.5)  # cobweb-ish
    # pegboard with tools
    peg = rect(L - 200, -175, 150, 95, '#9A7C55')
    for i in range(14):
        for j in range(9):
            peg += circ(L - 192 + i * 10.5, -168 + j * 10, 1.2, '#5E4A30')
    peg += path(f'M{L - 180},-160 l0,50 M{L - 186},-160 l12,0', '#5E6470', sw=4)  # screwdriver-ish
    peg += path(f'M{L - 150},-165 l0,55', '#9AA0AE', sw=5) + rect(L - 158, -168, 16, 12, '#B4362F')  # hammer
    peg += f'<circle cx="{L - 105}" cy="-130" r="20" fill="none" stroke="#E8A33D" stroke-width="5"/>'  # coiled cord
    right = peg
    # drywall: tape seams, water stain, outlet, whiteboard with loss curves
    right_bg = ''.join(rect(k * 120, -r.wall, 10, r.wall, '#B5AE98', 0.55) for k in range(1, int(L / 120) + 1))
    right_bg += f'<ellipse cx="{L - 300}" cy="{-r.wall + 30}" rx="50" ry="26" fill="#6E5A3A" opacity="0.25"/>'
    right_bg += rect(g0 + 110, -36, 18, 26, '#E8E2D4', stroke='#00000066') + circ(g0 + 116, -27, 2, '#333') + circ(g0 + 122, -19, 2, '#333')
    right_bg += loss_board(60, -186, 190, 104, 'loss')
    r.walls(blocks, right_bg + right, '#77746A', '#9D9682', cap='#3A3832')
    r.baseboard('#3C3A34', 8)
    # bulb cord from the ceiling joist (the bulb itself is drawn and flickered in Flutter)
    bulb = iso(g0 + 200, g0 + 200, 250)
    r.s.line2([iso(g0 + 200, g0 + 200, 330), bulb], '#1A1A1A', sw=1.6)
    r.light('bulb', bulb, '#FFD58A')
    # props, back to front
    fridge(r, 6, 6)
    cardboard(r, 300, 8, 0, 60, 50, 46)
    cardboard(r, 306, 14, 46, 48, 40, 32)
    cardboard(r, 372, 10, 0, 44, 44, 30)
    # desk where "you" sit, a CRT and a laptop
    d = desk(r, 110, 10, 150, 64, top='#6A4E33', z=48)
    scr = monitor(r, 150, 18, 54, w=44, h=34, glow='#62D6A0', crt=True)
    r.light('screen', scr, '#62D6A0')
    r.s.box(205, 40, 54, 34, 22, 2, color='#30343E')
    box(r, 110, 10, 54, 24, 20, 14, '#B4362F', top='#D2493F', sw=0.8)  # energy drink pack
    chair(r, 170, 92, color='#5A3A3A')
    r.seat = iso(184, 106, 36)
    shelf(r, 8, 210, 70, 120, 150, 4, ['can', 'can', 'box'], seed=4)
    mattress(r, 10, 370, 120, 175)
    lawnmower(r, 470, 30)
    # bucket + mop
    r.s.cyl(40, 92, 0, 14, 22, color='#3D6FB0')
    r.s.line3([(40, 92, 18), (28, 70, 120)], '#C9A36A', sw=3)
    return r


def closet():
    r = Room('closet', 7, 7, 1.2, wall=200, ground=150)
    L, g0 = r.L, r.grid0
    rnd = random.Random(2)
    # strip-mall sidewalk and asphalt
    walk = ''.join(rect(-150, -150 + k * 60, L + 300, 2, '#3A3F4C', 0.8) for k in range(int((L + 300) / 60)))
    walk += ''.join(rect(-150 + k * 60, -150, 2, L + 300, '#3A3F4C', 0.8) for k in range(int((L + 300) / 60)))
    r.ground_plate('#4A4F5C', body=walk)
    # worn carpet tiles
    fl = rect(0, 0, L, L, '#3F4760')
    for i in range(int(L / 60) + 1):
        for j in range(int(L / 60) + 1):
            c = rnd.choice(['#3B4259', '#434B66', '#3F4760', '#394058'])
            fl += rect(i * 60, j * 60, 60, 60, c) + rect(i * 60, j * 60, 60, 1.5, '#2C3246') + rect(i * 60, j * 60, 1.5, 60, '#2C3246')
    fl += f'<ellipse cx="{g0 + 300}" cy="{g0 + 200}" rx="40" ry="26" fill="#5B4A36" opacity="0.35"/>'  # coffee
    r.floor(fl)
    r.floor_ao(0.45)
    left = ''
    # door with exit sign
    left += rect(90, -175, 90, 175, '#5D5648') + rect(96, -169, 78, 169, '#8A7F68') + circ(162, -85, 4, '#D8D2B8')
    left += rect(106, -196, 58, 16, '#0F2A18') + text(135, -184, 'EXIT', 12, '#39FF9F', anchor='middle')
    r.light('led', iso(0, L - 135, 188), '#39FF9F')
    left += rect(260, -190, 120, 40, '#C9CED6') + ''.join(rect(266, -184 + k * 7, 108, 3, '#7E8595') for k in range(5))  # AC vent
    left += poster(420, -160, 90, 110, '#1C2A4A', '#3DD6FF', 'SHIP IT', 'v0.1')
    left += poster(530, -150, 70, 90, '#F2C230', '#1A1A1A', 'HIRING', 'ML eng')
    right = ''
    right += rect(30, -180, 170, 100, '#B48A5A') + rect(36, -174, 158, 88, '#C9A46E')  # corkboard
    for k in range(11):
        right += rect(44 + (k % 6) * 25, -168 + (k // 6) * 36, 20, 20, rnd.choice(['#FFE16B', '#FF9EC2', '#9EE6FF', '#B8FF9E']))
    right += loss_board(240, -186, 200, 104, 'eval acc', color='#3D7BE0', alt='#39B26A', messy=False)
    right += rect(g0 + 260, -36, 30, 22, '#E8E2D4', stroke='#00000066')
    r.walls(left, right, '#A89F8A', '#C2B9A2', cap='#4A4538')
    r.baseboard('#5D5648', 12)
    # ceiling fluorescent tube
    p0, p1 = iso(g0 + 150, g0 + 250, 260), iso(g0 + 350, g0 + 250, 260)
    r.light('tube', ((p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2), '#DDF3FF')
    # props
    server_cabinet(r, 8, 8, 56, 56, 120, rows=5, seed=3)
    d = desk(r, 520, 10, 170, 66, top='#C7C1B2', z=52)
    s1 = monitor(r, 540, 14, 58, w=40, h=28, glow='#3DD6FF')
    s2 = monitor(r, 600, 14, 58, w=40, h=28, glow='#39FF9F')
    r.light('screen', s1, '#3DD6FF')
    r.light('screen', s2, '#39FF9F')
    box(r, 650, 30, 58, 26, 22, 18, '#E8E2D4', sw=0.8)  # mug-ish box
    chair(r, 590, 96)
    r.seat = iso(604, 110, 36)
    shelf(r, 10, 220, 60, 110, 160, 4, ['part', 'box', 'part'], seed=6)
    for k in range(3):
        cardboard(r, 210 + k * 6, 14, k * 18, 56, 44, 18)  # pizza boxes
    r.s.cyl(30, 420, 0, 18, 60, color='#3D6FB0')  # water cooler
    r.s.cyl(30, 420, 60, 14, 40, color='#9EE6FF')
    r.s.cyl(30, 560, 0, 14, 24, color='#E0C040')  # mop bucket
    r.s.line3([(30, 560, 20), (18, 540, 140)], '#C9A36A', sw=3)
    return r


def colo():
    r = Room('colo', 10, 10, 1.0, wall=200, ground=150)
    L, g0 = r.L, r.grid0
    r.ground_plate('#23283A')
    fl = rect(0, 0, L, L, '#5E6676')
    for i in range(int(L / 50) + 1):
        fl += rect(i * 50, 0, 1.5, L, '#4C5362') + rect(0, i * 50, L, 1.5, '#4C5362')
    # cold-aisle perforated rows
    for j in range(r.h):
        if j % 3 == 1:
            for i in range(r.w):
                for a in range(5):
                    for b in range(5):
                        fl += circ(g0 + i * 100 + 18 + a * 16, g0 + j * 100 + 18 + b * 16, 2.6, '#3A404E')
    # yellow safety tape around the cage floor
    fl += f'<rect x="{g0 - 14}" y="{g0 - 14}" width="{r.w * 100 + 28}" height="{r.h * 100 + 28}" fill="none" stroke="#F2C230" stroke-width="7" stroke-dasharray="26 14"/>'
    r.floor(fl)
    r.floor_ao(0.35)

    def mesh(body_len):
        s = ''
        for k in range(int(body_len / 14) + 2):
            s += path(f'M{k * 14},{-r.wall} l-{r.wall},{r.wall}', '#AEB7C8', sw=1, op=0.45)
            s += path(f'M{k * 14 - r.wall},{-r.wall} l{r.wall},{r.wall}', '#AEB7C8', sw=1, op=0.45)
        for k in range(int(body_len / 100) + 1):
            s += rect(k * 100, -r.wall, 6, r.wall, '#8E97A8')
        s += rect(0, -r.wall, body_len, 6, '#8E97A8') + rect(0, -70, body_len, 4, '#8E97A8')
        return s

    # behind the cage: other tenants' racks in the dark
    def neighbours(seed):
        rnd = random.Random(seed)
        s = ''
        for k in range(int(L / 80)):
            x = 10 + k * 80
            s += rect(x, -r.wall + 20, 64, r.wall - 20, '#101522')
            for j in range(9):
                s += rect(x + 8, -r.wall + 34 + j * 18, 48, 10, '#1A2032')
                if rnd.random() < 0.6:
                    s += circ(x + 14 + rnd.uniform(0, 36), -r.wall + 39 + j * 18, 2, rnd.choice(['#39FF9F', '#3DD6FF', '#FFB547']), 0.9)
        return s

    r.walls(neighbours(1) + mesh(L), neighbours(2) + mesh(L), '#0A0E18', '#0C111C', cap='#5E6676', thick=6)
    # blinking LEDs on the neighbours (sampled points on both walls)
    rnd = random.Random(9)
    for k in range(int(L / 80)):
        for j in range(0, 9, 2):
            z = r.wall - 39 - j * 18
            r.light('led', iso(10 + k * 80 + 20 + rnd.uniform(0, 26), 0, z), rnd.choice(['#39FF9F', '#3DD6FF']))
            r.light('led', iso(0, L - (10 + k * 80 + 20 + rnd.uniform(0, 26)), z), rnd.choice(['#39FF9F', '#FFB547']))
    cable_tray_right(r, r.wall - 30, 20, L - 20)
    cable_tray_left(r, r.wall - 30, 20, L - 20)
    # props
    r.s.cyl(40, 40, 0, 14, 50, color='#C9302C')  # fire extinguisher
    r.s.cyl(40, 40, 50, 6, 10, color='#222222')
    box(r, 300, 10, 0, 70, 50, 80, '#3B4568', sw=1)  # crash cart
    box(r, 300, 10, 80, 70, 50, 4, '#55658F')
    monitor(r, 318, 16, 84, w=34, h=22, glow='#3DD6FF')
    cardboard(r, 10, 300, 0, 60, 70, 40)
    cardboard(r, 14, 380, 0, 52, 60, 30)
    b = box(r, 2, 600, 80, 6, 30, 40, '#2A2F3A', sw=0.8)  # badge reader
    r.light('led', Scene.fpt(b, 'right', 0.5, 0.3), '#FF4D6A')
    return r


def hall():
    r = Room('hall', 14, 14, 1.0, wall=230, ground=150)
    L, g0 = r.L, r.grid0
    r.ground_plate('#1E2333', body=''.join(rect(-150 + k * 90, L + 40, 4, 60, '#E0E4EC', 0.6) for k in range(int((L + 300) / 90))))
    fl = rect(0, 0, L, L, '#9AA3B4')
    for i in range(int(L / 50) + 1):
        fl += rect(i * 50, 0, 2, L, '#7A8396') + rect(0, i * 50, L, 2, '#7A8396')
    for j in range(r.h):
        for i in range(r.w):
            if (i + j) % 4 == 0:
                for a in range(4):
                    for b in range(4):
                        fl += circ(g0 + i * 100 + 14 + a * 24, g0 + j * 100 + 14 + b * 24, 3, '#6E778A')
    fl += f'<rect x="{g0 - 6}" y="{g0 - 6}" width="{r.w * 100 + 12}" height="{r.h * 100 + 12}" fill="none" stroke="#39FF9F" stroke-width="3" opacity="0.35"/>'
    r.floor(fl)
    r.floor_ao(0.3)
    left = rect(0, -60, L, 8, '#39FF9F', extra='filter="url(#g)"')
    for k in range(5):
        x = 80 + k * 230
        left += rect(x, -200, 150, 110, '#D9DEE6', stroke='#AEB6C4') + rect(x + 10, -190, 130, 8, '#AEB6C4')
    right = rect(0, -60, L, 8, '#39FF9F', extra='filter="url(#g)"')
    # big hexagon "lab" mark + NOC screen
    hx, hy = 260, -140
    hexp = ' '.join(f'{hx + 46 * math.cos(math.pi / 3 * k + math.pi / 6):.1f},{hy + 46 * math.sin(math.pi / 3 * k + math.pi / 6):.1f}' for k in range(6))
    right += f'<polygon points="{hexp}" fill="none" stroke="#39FF9F" stroke-width="7" filter="url(#g)"/>'
    right += circ(hx, hy, 12, '#39FF9F', extra='filter="url(#g)"')
    for k in range(6):
        a = math.pi / 3 * k + math.pi / 6
        right += path(f'M{hx},{hy} L{hx + 30 * math.cos(a):.1f},{hy + 30 * math.sin(a):.1f}', '#39FF9F', sw=3)
    right += rect(480, -205, 300, 130, '#0E1422', stroke='#2A3550', sw=4)
    gp = ' '.join(f'{490 + i * 14},{-110 - 50 * (1 - math.exp(-i / 6)) - 6 * math.sin(i):.1f}' for i in range(21))
    right += f'<polyline points="{gp}" fill="none" stroke="#39FF9F" stroke-width="3"/>'
    right += ''.join(rect(640 + k * 18, -120 - (k * 13 % 60), 12, 30 + (k * 13 % 60), '#3DD6FF', 0.8) for k in range(7))
    right += text(492, -185, 'CLUSTER HEALTH', 13, '#8E9CC4')
    r.walls(left, right, '#C3CAD6', '#D7DDE6', cap='#6E7790')
    r.baseboard('#6E7790', 14)
    led_strip_right(r, 56, 30, L - 30, 40, ['#39FF9F'])
    cable_tray_right(r, r.wall - 25, 20, L - 20)
    cable_tray_left(r, r.wall - 25, 20, L - 20)
    for k in range(4):
        crah(r, 6, 120 + k * 280, 70, 140, 150, face='right')
    for k in range(3):
        server_cabinet(r, 900 + k * 70, 6, 60, 70, 170, rows=8, seed=10 + k)
    return r


def campus():
    r = Room('campus', 18, 18, 1.0, wall=260, ground=150)
    L, g0 = r.L, r.grid0
    r.ground_plate('#151A28')
    fl = rect(0, 0, L, L, '#273047')
    for i in range(int(L / 100) + 1):
        fl += rect(i * 100, 0, 2, L, '#3DD6FF', 0.22) + rect(0, i * 100, L, 2, '#3DD6FF', 0.22)
    fl += f'<rect x="{g0 - 8}" y="{g0 - 8}" width="{r.w * 100 + 16}" height="{r.h * 100 + 16}" fill="none" stroke="#B07CFF" stroke-width="4" opacity="0.6" filter="url(#g)"/>'
    r.floor(fl)
    r.floor_ao(0.4)

    def glass(seed):
        s = ''
        for k in range(int(L / 110)):
            x = 10 + k * 110
            s += rect(x, -r.wall + 20, 96, r.wall - 70, '#16203A', stroke='#3A4A70', sw=3)
            s += path(f'M{x + 10},{-r.wall + 40} l40,60', '#6B85C0', sw=2, op=0.35)
        return s

    left = glass(1) + rect(0, -40, L, 10, '#B07CFF', extra='filter="url(#g)"')
    right = glass(2) + rect(0, -40, L, 10, '#B07CFF', extra='filter="url(#g)"')
    right += rect(420, -230, 440, 150, '#0A0F1C', stroke='#B07CFF', sw=4)
    right += text(640, -150, 'COMPUTE', 46, '#B07CFF', anchor='middle')
    right += text(640, -110, 'campus · 20 MW', 16, '#8E9CC4', anchor='middle', weight='normal')
    r.walls(left, right, '#1D2640', '#222C4A', cap='#3A4670')
    # liquid-cooling manifolds (cyan glow) along both walls
    pipe(r, [(30, 14, 30), (L - 30, 14, 30)], '#3DD6FF', sw=9, glow=True)
    pipe(r, [(30, 28, 18), (L - 30, 28, 18)], '#2A7FFF', sw=7, glow=True)
    pipe(r, [(14, 30, 30), (14, L - 30, 30)], '#3DD6FF', sw=9, glow=True)
    pipe(r, [(28, 30, 18), (28, L - 30, 18)], '#2A7FFF', sw=7, glow=True)
    for x in range(100, int(L), 200):
        pipe(r, [(x, 14, 30), (x, 14, r.wall - 40)], '#3DD6FF', sw=6, glow=True)
    cable_tray_right(r, r.wall - 25, 20, L - 20, cables=('#B07CFF', '#3DD6FF', '#FFB547'))
    cable_tray_left(r, r.wall - 25, 20, L - 20, cables=('#B07CFF', '#3DD6FF', '#FFB547'))
    led_strip_left(r, 120, 30, L - 30, 55, ['#B07CFF', '#3DD6FF'])
    led_strip_right(r, 200, 30, L - 30, 55, ['#B07CFF', '#3DD6FF'])
    for k in range(3):
        server_cabinet(r, 40 + k * 70, 40, 60, 54, 200, color='#141A2C', rows=10, seed=20 + k, led_cols=('#B07CFF', '#3DD6FF'))
    return r


def gigasite():
    r = Room('gigasite', 22, 22, 1.2, wall=340, ground=170)
    L, g0 = r.L, r.grid0
    rnd = random.Random(4)
    dirt = ''.join(circ(rnd.uniform(-170, L + 170), rnd.uniform(-170, L + 170), rnd.uniform(4, 14), '#3A3326', 0.5) for _ in range(220))
    r.ground_plate('#2E3A22', body=dirt)
    fl = rect(0, 0, L, L, '#5B606B')
    for i in range(int(L / 120) + 1):
        fl += rect(i * 120, 0, 3, L, '#474B55') + rect(0, i * 120, L, 3, '#474B55')
    fl += f'<rect x="{g0 - 10}" y="{g0 - 10}" width="{r.w * 100 + 20}" height="{r.h * 100 + 20}" fill="none" stroke="#FF6FD8" stroke-width="4" opacity="0.5" filter="url(#g)"/>'
    for k in range(6):
        fl += rect(30, 140 + k * 200, 60, 6, '#F2C230', 0.8)
    r.floor(fl)
    # no walls: a perimeter fence and the plant behind it
    fence_h = 70
    for x in range(0, int(L) + 1, 60):
        r.s.line3([(x, 0, 0), (x, 0, fence_h)], '#8E97A8', sw=2.4)
    for y in range(0, int(L) + 1, 60):
        r.s.line3([(0, y, 0), (0, y, fence_h)], '#8E97A8', sw=2.4)
    for z in (20, 45, fence_h):
        r.s.line3([(0, 0, z), (L, 0, z)], '#8E97A8', sw=1.4, opacity=0.7)
        r.s.line3([(0, 0, z), (0, L, z)], '#8E97A8', sw=1.4, opacity=0.7)
    # power pylons + lines along the back
    for y in (-130, ):
        for x in range(80, int(L), 360):
            base = [(x - 20, y - 20, 0), (x + 20, y + 20, 0)]
            r.s.line3([(x - 24, y, 0), (x, y, 300), (x + 24, y, 0)], '#9AA3B4', sw=3)
            r.s.line3([(x - 40, y, 240), (x + 40, y, 240)], '#9AA3B4', sw=3)
            r.s.line3([(x - 30, y, 200), (x + 30, y, 200)], '#9AA3B4', sw=3)
            r.light('led', iso(x, y, 304), '#FF4D6A')
    r.s.line3([(80, -130, 240), (L, -130, 236)], '#5C6378', sw=1.2)
    # cooling towers behind the left fence
    for k, y in enumerate((150, 520, 890)):
        cx, cy, rx, ry, ty = r.s.cyl(-90, y, 0, 70, 210, color='#9AA3B4')
        r.s.ellipse2(cx, ty, rx * 0.8, ry * 0.8, '#3DD6FF', stroke=None, glow=True, opacity=0.7)
        r.light('steam', (cx, ty - 10), '#DDE6F2')
    # substation: transformers in the back strip
    for k in range(4):
        b = box(r, 160 + k * 150, 10, 0, 110, 80, 90, '#6E7790', sw=1.2)
        for f in range(6):
            r.s.frect(b, 'left', 0.08 + f * 0.15, 0.15, 0.13 + f * 0.15, 0.9, '#4E566C')
        r.s.cyl(160 + k * 150 + 55, 50, 90, 10, 30, color='#C9CED6')
        r.light('led', Scene.fpt(b, 'left', 0.5, 0.1), '#FFB547')
    # glowing manifold into the pad
    pipe(r, [(L - 40, 30, 20), (300, 30, 20), (300, 30, 0)], '#FF6FD8', sw=10, glow=True)
    pipe(r, [(30, L - 40, 20), (30, 300, 20)], '#3DD6FF', sw=10, glow=True)
    return r


def orbital():
    """The post-game orbital station: a truss deck in sun-synchronous orbit,
    two solar wings standing where other rooms have back walls, radiator
    panels off the front edges, a docking node, stars and the Earth's limb."""
    r = Room('orbital', 24, 24, 1.2, wall=760, ground=220)
    L, g0, s = r.L, r.grid0, r.s
    W = r.w * U
    # ---- backdrop (screen space): stars, nebulae, the Earth's limb and the
    # Sun, inside a soft elliptical fade so it melts into the dark world map
    x0 = -(L + 520) * C30
    top, bot = -900.0, L + 760.0
    vb = (x0, top, -2 * x0, bot - top)
    r.viewbox = lambda: vb
    cx, cy = 0.0, (top + bot) / 2
    rx, ry = -x0, (bot - top) / 2
    fade = r.grad('sf_fade', [(0, '#FFF', 1), (0.5, '#FFF', 0.92), (0.8, '#FFF', 0.55), (1, '#FFF', 0)], 'radial',
                  gradientUnits='userSpaceOnUse', cx=cx, cy=cy, r=ry,
                  gradientTransform=f'translate({cx} {cy}) scale({rx / ry:.4f} 1) translate({-cx} {-cy})')
    r.defs.append(f'<mask id="sf_m" maskUnits="userSpaceOnUse" x="{vb[0]}" y="{vb[1]}" width="{vb[2]}" height="{vb[3]}">'
                  f'<rect x="{vb[0]}" y="{vb[1]}" width="{vb[2]}" height="{vb[3]}" fill="{fade}"/></mask>')
    rnd = random.Random(42)
    bg = rect(vb[0], vb[1], vb[2], vb[3], '#03050C')
    neb = r.grad('neb', [(0, '#5B3FA8', 0.32), (1, '#5B3FA8', 0)], 'radial')
    neb2 = r.grad('neb2', [(0, '#1E6FA8', 0.28), (1, '#1E6FA8', 0)], 'radial')
    bg += f'<ellipse cx="-1300" cy="-350" rx="900" ry="420" fill="{neb}"/>'
    bg += f'<ellipse cx="1500" cy="300" rx="800" ry="520" fill="{neb2}"/>'
    for _ in range(520):
        x, y = rnd.uniform(vb[0], vb[0] + vb[2]), rnd.uniform(vb[1], vb[1] + vb[3])
        bg += circ(x, y, rnd.choice((1.6, 2.2, 2.2, 3.0, 4.2)), rnd.choice(('#FFFFFF', '#CFE0FF', '#FFE9C4')),
                   rnd.uniform(0.35, 1))
    for _ in range(14):  # a few bright ones with a cross glint
        x, y = rnd.uniform(vb[0], vb[0] + vb[2]), rnd.uniform(vb[1], vb[1] + vb[3])
        bg += circ(x, y, 5, '#FFFFFF', 0.95, extra='filter="url(#g)"')
        bg += path(f'M{x - 16},{y} L{x + 16},{y} M{x},{y - 16} L{x},{y + 16}', '#FFFFFF', sw=1.4, op=0.6)
    # Earth: a huge sphere low on the right, its limb and blue atmosphere
    ex, ey, er = 1500.0, L + 3820, 4300.0
    ocean = r.grad('ocean', [(0, '#3E86D8', 1), (0.55, '#1A4E9E', 1), (1, '#0A1E4A', 1)], 'radial',
                   gradientUnits='userSpaceOnUse', cx=ex - 900, cy=ey - er + 300, r=er * 0.9)
    atm = r.grad('atm', [(0, '#7FD8FF', 0), (0.955, '#7FD8FF', 0), (0.975, '#9BE3FF', 0.75), (1, '#4AA8FF', 0)],
                 'radial', gradientUnits='userSpaceOnUse', cx=ex, cy=ey, r=er + 160)
    r.defs.append(f'<clipPath id="earth_c"><circle cx="{ex}" cy="{ey}" r="{er}"/></clipPath>')
    land = ''
    for _ in range(9):  # continents: clusters of overlapping blobs
        a = rnd.uniform(math.radians(212), math.radians(300))
        d = rnd.uniform(er * 0.82, er * 0.97)
        px, py = ex + d * math.cos(a), ey + d * math.sin(a)
        for _ in range(7):
            qx, qy = px + rnd.uniform(-180, 180), py + rnd.uniform(-60, 60)
            land += f'<ellipse cx="{qx:.0f}" cy="{qy:.0f}" rx="{rnd.uniform(60, 160):.0f}" ry="{rnd.uniform(25, 60):.0f}" fill="#3E7A48" opacity="0.42"/>'
    clouds = ''
    for _ in range(320):  # thin streaks following the curve
        a = rnd.uniform(math.radians(200), math.radians(320))
        d = rnd.uniform(er * 0.84, er * 0.998)
        px, py = ex + d * math.cos(a), ey + d * math.sin(a)
        clouds += (f'<ellipse cx="{px:.0f}" cy="{py:.0f}" rx="{rnd.uniform(30, 140):.0f}" ry="{rnd.uniform(3, 9):.0f}" '
                   f'fill="#F2F7FF" opacity="{rnd.uniform(0.18, 0.5):.2f}" '
                   f'transform="rotate({math.degrees(a) + 90:.1f} {px:.0f} {py:.0f})"/>')
    night = r.grad('night', [(0, '#000', 0), (0.5, '#000', 0), (1, '#000', 0.75)], x1=0, y1=0, x2=1, y2=0.4)
    earth = (circ(ex, ey, er + 160, atm) + '<g clip-path="url(#earth_c)">' + circ(ex, ey, er, ocean) + land + clouds
             + rect(ex - er, ey - er, 2 * er, 2 * er, night) + '</g>')
    sun = r.grad('sun', [(0, '#FFFFFF', 1), (0.08, '#FFF4D6', 0.95), (0.3, '#FFD58A', 0.25), (1, '#FFB547', 0)], 'radial')
    sunel = f'<circle cx="-1500" cy="-560" r="520" fill="{sun}"/>'
    r.add(f'<g mask="url(#sf_m)">{bg}{earth}{sunel}</g>')

    # ---- deck underside: a truss box under the two front edges
    D = 90
    s.poly2([iso(0, L, 0), iso(L, L, 0), iso(L, L, -D), iso(0, L, -D)], '#1A2034', sw=2)
    s.poly2([iso(L, 0, 0), iso(L, L, 0), iso(L, L, -D), iso(L, 0, -D)], '#121729', sw=2)
    for k in range(0, int(L), 140):
        s.line3([(k, L, 0), (k + 140, L, -D)], '#8E9CC4', sw=2.2, opacity=0.8)
        s.line3([(k + 140, L, 0), (k, L, -D)], '#8E9CC4', sw=2.2, opacity=0.8)
        s.line3([(L, k, 0), (L, k + 140, -D)], '#6E7AA0', sw=2.2, opacity=0.8)
        s.line3([(L, k + 140, 0), (L, k, -D)], '#6E7AA0', sw=2.2, opacity=0.8)
        s.line3([(k, L, 0), (k, L, -D)], '#B8C2D6', sw=2.6)
        s.line3([(L, k, 0), (L, k, -D)], '#8E9CC4', sw=2.6)
    s.line3([(0, L, -D), (L, L, -D), (L, 0, -D)], '#B8C2D6', sw=3)

    # ---- radiators: white ribbed panels on booms off the two front edges
    def radiator(along_x, a0, a1, out0, out1, z):
        def P(a, o):
            return (a, L + o, z) if along_x else (L + o, a, z)
        s.poly2([iso(*P(a0, out0)), iso(*P(a1, out0)), iso(*P(a1, out1)), iso(*P(a0, out1))], '#DCE4EF', sw=2.4)
        n = int((out1 - out0) / 34)
        for k in range(1, n):
            o = out0 + k * (out1 - out0) / n
            s.line2([iso(*P(a0 + 8, o)), iso(*P(a1 - 8, o))], '#9DA9BD', sw=2)
        # coolant manifold along the inner edge, glowing faintly warm
        s.line2([iso(*P(a0, out0 + 8)), iso(*P(a1, out0 + 8))], '#FF9F6B', sw=5, glow=True, opacity=0.8)
        s.line2([iso(*P(a0, out0)), iso(*P(a1, out0))], INK, sw=1.2)

    for a0 in (240, 980, 1720):
        mid = a0 + 260
        s.line3([(mid, L, -D / 2), (mid, L + 120, -40)], '#B8C2D6', sw=6)
        radiator(True, a0, a0 + 520, 120, 560, -40)
        s.line3([(L, mid, -D / 2), (L + 120, mid, -40)], '#B8C2D6', sw=6)
        radiator(False, a0, a0 + 520, 120, 560, -40)

    # ---- docking node at the front corner, with a capsule docked
    pipe(r, [(L - 40, L - 40, -45), (L + 160, L + 160, -45)], '#B8C2D6', sw=34)
    ncx, ncy = iso(L + 230, L + 230, -45)
    s.ellipse2(ncx, ncy, 78, 78, '#8E9CC4', sw=2.6)
    s.ellipse2(ncx, ncy, 58, 58, '#3A4466', sw=2)
    s.ellipse2(ncx, ncy, 40, 40, '#1A2034', sw=2)
    for k in range(8):
        a = math.pi / 4 * k
        s.ellipse2(ncx + 68 * math.cos(a), ncy + 68 * math.sin(a), 5, 5, '#FFB547', stroke=None, glow=True)
    r.light('led', (ncx, ncy - 78), '#39FF9F')
    r.light('led', (ncx - 78, ncy), '#FF4D6A')
    c0 = iso(L + 300, L + 300, -45)
    c1 = iso(L + 470, L + 470, -45)
    c2 = iso(L + 700, L + 700, -45)
    s.poly2([(c0[0] - 50, c0[1]), (c0[0] + 50, c0[1]), (c1[0] + 80, c1[1]), (c1[0] - 80, c1[1])], '#E4E8EE', sw=2.4)
    s.poly2([(c1[0] - 80, c1[1]), (c1[0] + 80, c1[1]), (c2[0] + 80, c2[1]), (c2[0] - 80, c2[1])], '#2A3048', sw=2.4)
    for f in (0.3, 0.6):
        y = c1[1] + (c2[1] - c1[1]) * f
        xm = c1[0] + (c2[0] - c1[0]) * f
        s.line2([(xm - 80, y), (xm + 80, y)], '#8E9CC4', sw=2)
    for sg in (1, -1):
        s.poly2([(c1[0] + sg * 80, c1[1] + 40), (c1[0] + sg * 300, c1[1] + 10), (c1[0] + sg * 300, c1[1] + 80),
                 (c1[0] + sg * 80, c1[1] + 110)], '#1C3A7A', sw=2)
        for xx in (140, 200, 260):
            s.line2([(c1[0] + sg * xx, c1[1] + 20), (c1[0] + sg * xx, c1[1] + 95)], '#4F7FD8', sw=1.4)
    s.ellipse2((c0[0] + c1[0]) / 2, (c0[1] + c1[1]) / 2 - 4, 14, 10, '#3DD6FF', stroke=INK, glow=True)

    # ---- the deck: dark composite panels on a truss grid
    fl = rect(0, 0, L, L, '#20283E')
    for i in range(int(L / 100) + 1):
        fl += rect(i * 100 - 1, 0, 3, L, '#141A2C') + rect(0, i * 100 - 1, L, 3, '#141A2C')
    for j in range(r.h + 1):
        for i in range(r.w + 1):
            fl += circ(g0 + i * 100, g0 + j * 100, 6, '#56627F')
    for j in range(r.h):
        for i in range(r.w):
            fl += rect(g0 + i * 100 + 14, g0 + j * 100 + 14, 72, 72, 'none', op=0.16, stroke='#3DD6FF', sw=2, rx=10)
    fl += rect(0, 0, L, g0 - 14, '#2C3550') + rect(0, 0, g0 - 14, L, '#2C3550')
    fl += rect(0, L - 40, L, 40, '#2C3550') + rect(L - 40, 0, 40, L, '#2C3550')
    for k in range(int(L / 80)):
        fl += rect(k * 80 + 10, g0 - 30, 40, 8, '#FFB547', 0.75) + rect(g0 - 30, k * 80 + 10, 8, 40, '#FFB547', 0.75)
    fl += (f'<rect x="{g0 - 8}" y="{g0 - 8}" width="{W + 16}" height="{W + 16}" fill="none" stroke="#3DD6FF" '
           f'stroke-width="4" opacity="0.55" filter="url(#g)"/>')
    r.floor(fl)
    s.line3([(0, L, 0), (L, L, 0), (L, 0, 0)], '#B8C2D6', sw=3.4)

    # ---- solar wings where other rooms have back walls: two blankets per
    # side between masts, blue cells in gold frames, struts to the deck
    OFF = -70

    def P(left, a, z):
        return (OFF, a, z) if left else (a, OFF, z)

    def wing(left, a0, a1, z0, z1):
        s.poly2([iso(*P(left, a0, z0)), iso(*P(left, a1, z0)), iso(*P(left, a1, z1)), iso(*P(left, a0, z1))],
                '#162A5C', stroke='#C9A24A', sw=4)
        cols, rows = int((a1 - a0) / 44), int((z1 - z0) / 44)
        for c in range(1, cols):
            a = a0 + c * (a1 - a0) / cols
            s.line2([iso(*P(left, a, z0)), iso(*P(left, a, z1))], '#3E6CC4', sw=1.4, opacity=0.9)
        for k in range(1, rows):
            z = z0 + k * (z1 - z0) / rows
            s.line2([iso(*P(left, a0, z)), iso(*P(left, a1, z))], '#3E6CC4', sw=1.4, opacity=0.9)
        mid = (z0 + z1) / 2
        s.line2([iso(*P(left, a0, mid)), iso(*P(left, a1, mid))], '#C9A24A', sw=5)
        sheen = [iso(*P(left, a0 + (a1 - a0) * 0.12, z1)), iso(*P(left, a0 + (a1 - a0) * 0.42, z1)),
                 iso(*P(left, a0 + (a1 - a0) * 0.3, z0)), iso(*P(left, a0, z0))]
        s.poly2(sheen, '#9CC4FF', stroke=None, opacity=0.12)

    for left in (True, False):
        for a in (100, 1260, 2420):
            q = (0, a + 120, 0) if left else (a + 120, 0, 0)
            s.line3([P(left, a, 230), q], '#8E9CC4', sw=3)
        for a0, a1 in ((140, 1180), (1340, 2380)):
            wing(left, a0, a1, 230, 720)
        for a in (100, 1260, 2420):
            s.line3([P(left, a, 0), P(left, a, 740)], INK, sw=12)
            s.line3([P(left, a, 0), P(left, a, 740)], '#B8C2D6', sw=8)
            r.light('led', iso(*P(left, a, 750)), '#FF4D6A' if left else '#39FF9F')
    s.line3([(OFF, OFF, 40), (OFF, L, 40)], '#B8C2D6', sw=10)
    s.line3([(OFF, OFF, 40), (L, OFF, 40)], '#B8C2D6', sw=10)
    s.cyl(OFF, OFF, 0, 60, 120, color='#8E9CC4')
    r.light('led', iso(OFF, OFF, 130), '#FFB547')

    # ---- equipment on the back walkway: control-moment gyros and batteries
    for k in range(6):
        b = box(r, 160 + k * 380, 20, 0, 120, 70, 50, '#3A4466', sw=1.4)
        s.frect(b, 'left', 0.1, 0.35, 0.9, 0.6, '#3DD6FF', glow=True, opacity=0.6)
        r.light('led', Scene.fpt(b, 'left', 0.85, 0.2), '#39FF9F')
    for k in range(6):
        b = box(r, 20, 160 + k * 380, 0, 70, 120, 50, '#3A4466', sw=1.4)
        s.frect(b, 'right', 0.1, 0.35, 0.9, 0.6, '#FFB547', glow=True, opacity=0.5)
    return r


def house():
    """The parents' house, standing beside the garage (decor only)."""
    r = Room('house', 4, 4, 0, wall=0, ground=60)
    s = r.s
    W, D, H = 440, 380, 230
    b = s.box(0, 0, 0, W, D, H, color='#8C7A68', top='#5A4A40', right='#6E5E50')
    # siding lines
    for k in range(1, 12):
        s.fline(b, 'left', [(0, k / 12), (1, k / 12)], '#6E5E50', sw=1, opacity=0.7)
        s.fline(b, 'right', [(0, k / 12), (1, k / 12)], '#56483C', sw=1, opacity=0.7)
    # roof
    ridge = H + 150
    s.poly2([iso(-20, D + 20, H), iso(W + 20, D + 20, H), iso(W + 20, D / 2, ridge), iso(-20, D / 2, ridge)], '#5A3A34', sw=1.6)
    s.poly2([iso(W + 20, -20, H), iso(W + 20, D + 20, H), iso(W + 20, D / 2, ridge)], '#7A5048', sw=1.6)
    for k in range(1, 8):
        z = H + (ridge - H) * k / 8
        dy = (D / 2 + 20) * (1 - k / 8)
        s.line2([iso(-20, D / 2 + dy, z), iso(W + 20, D / 2 + dy, z)], '#4A2E2A', sw=1, opacity=0.7)
    # windows (one warm lit), door, chimney
    for u, lit in ((0.12, True), (0.42, False), (0.72, True)):
        s.frect(b, 'left', u, 0.18, u + 0.16, 0.48, '#FFD58A' if lit else '#1C2438', glow=lit, stroke=INK, sw=1)
        s.frect(b, 'left', u + 0.078, 0.18, u + 0.082, 0.48, '#3A3028')
    s.frect(b, 'left', 0.12, 0.6, 0.28, 0.94, '#1C2438', stroke=INK, sw=1)
    s.frect(b, 'left', 0.5, 0.52, 0.64, 1.0, '#5A3A2A', stroke=INK, sw=1)
    s.frect(b, 'right', 0.3, 0.2, 0.6, 0.5, '#FFD58A', glow=True, stroke=INK, sw=1)
    r.light('window', Scene.fpt(b, 'left', 0.2, 0.33), '#FFD58A')
    r.light('window', Scene.fpt(b, 'right', 0.45, 0.35), '#FFD58A')
    s.box(80, 80, H + 40, 40, 40, 130, color='#7A4A3A')
    # bushes + mailbox
    for (x, y) in ((60, D + 40), (300, D + 40)):
        cx, cy = iso(x, y, 0)
        s.ellipse2(cx, cy - 16, 40, 26, '#2E5A2A', sw=1.4)
    s.box(W + 30, D + 120, 0, 6, 6, 60, color='#5E5E5E')
    s.box(W + 22, D + 112, 60, 24, 22, 18, color='#3D6FB0')
    pts = s.pts
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    pad = 30
    vb = (min(xs) - pad, min(ys) - pad, max(xs) - min(xs) + 2 * pad, max(ys) - min(ys) + 2 * pad)
    r.viewbox = lambda: vb
    return r


# =============================================================== output
def render(r, max_w=2600, density=1.4):
    vb = r.viewbox()
    w = int(min(max_w, vb[2] * density))
    h = int(w * vb[3] / vb[2])
    svgp = os.path.join(TMP, f'world_{r.id}.svg')
    open(svgp, 'w').write(r.svg())
    png = os.path.join(TMP, f'world_{r.id}.png')
    out = os.path.join(OUTDIR, f'world_{r.id}.webp')
    subprocess.run(['rsvg-convert', '-w', str(w), '-h', str(h), svgp, '-o', png], check=True)
    # Lossy WebP with alpha: ~4x smaller than PNG for these big painted rooms.
    subprocess.run(['magick', png, '-strip', '-quality', '88', '-define', 'webp:alpha-quality=95', out], check=True)
    return out


def dart_meta(rs):
    lines = ['// GENERATED by tool/art/generate_rooms.py. Do not edit by hand.',
             '// Coordinates are SVG units: 1 grid cell = 100, origin = floor back corner.',
             "import 'room_art.dart';", '', 'const roomArt = <String, RoomArt>{']
    for r in rs:
        vb = r.viewbox()
        lights = ', '.join(f"RoomLight('{k}', {x:.1f}, {y:.1f}, 0xFF{c.lstrip('#').upper()})" for k, x, y, c in r.lights)
        seat = f'({r.seat[0]:.1f}, {r.seat[1]:.1f})' if r.seat else 'null'
        lines.append(f"  '{r.id}': RoomArt(")
        lines.append(f'    vb: ({vb[0]:.1f}, {vb[1]:.1f}, {vb[2]:.1f}, {vb[3]:.1f}),')
        lines.append(f'    margin: {r.m},')
        lines.append(f'    wall: {r.wall:.1f},')
        lines.append(f'    seat: {seat},')
        lines.append(f'    lights: [{lights}],')
        lines.append('  ),')
    lines.append('};')
    open(DART, 'w').write('\n'.join(lines) + '\n')


def main():
    only = set(os.environ.get('ONLY', '').split(',')) - {''}
    rs = [garage(), closet(), colo(), hall(), campus(), gigasite(), orbital(), house()]
    for r in rs:
        if not only or r.id in only:
            print(render(r, density=1.6 if r.id in ('garage', 'house') else 1.25))
    dart_meta(rs)
    print(DART)


if __name__ == '__main__':
    main()
