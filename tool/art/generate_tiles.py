#!/usr/bin/env python3
"""Grid art for AI Lab Tycoon: tile sprites, floor textures, room banners, overlays.

Procedural, same pipeline/palette as the rest of assets/images: Python writes SVG
(isometric helpers in iso.py), rsvg-convert rasterizes, ImageMagick post-processes.

Usage (from repo root):
    python3 tool/art/generate_tiles.py [out_dir]        # default: assets/images
Needs: rsvg-convert, magick (ImageMagick 7). Optional: pngquant.
"""
import math
import os
import random
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from iso import *  # noqa: E402,F403

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
OUT = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.join(ROOT, 'assets', 'images')
TMP = tempfile.mkdtemp(prefix='tiles_')

KIND = {'gpu': GREEN, 'cool': CYAN, 'net': AMBER}
ORANGE = '#FF8A3D'
BEIGE = '#A39C88'

# Fixed view box for every tile so all share one scale/perspective.
# Cell footprint is x,y in [0,100]; iso() maps it to a diamond x:[-86.6,86.6], y:[0,100].
VB = (-100.0, -84.0, 200.0, 200.0)


def run(*a):
    subprocess.run(a, check=True)


def svg_wrap(s, vb=VB, size=256, extra_defs=''):
    g = s.glow * vb[2] / 300
    defs = (f'<filter id="g" filterUnits="userSpaceOnUse" x="{vb[0]}" y="{vb[1]}" width="{vb[2]}" height="{vb[3]}">'
            f'<feGaussianBlur stdDeviation="{g:.2f}" result="b"/>'
            f'<feMerge><feMergeNode in="b"/><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>'
            + ''.join(s.defs) + extra_defs)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" '
            f'viewBox="{vb[0]} {vb[1]} {vb[2]} {vb[3]}"><defs>{defs}</defs>' + '\n'.join(s.els) + '</svg>')


def render(svg, out, w, h=None):
    p = os.path.join(TMP, os.path.basename(out) + '.svg')
    open(p, 'w').write(svg)
    run('rsvg-convert', '-w', str(w), '-h', str(h or w), p, '-o', out)


# ------------------------------------------------------------------ helpers
def base(s, kind, x0=8, y0=8, x1=92, y1=92):
    """Ground shadow + soft kind-coloured floor glow (the at-a-glance kind cue)."""
    cx, cy = iso((x0 + x1) / 2, (y0 + y1) / 2, 0)
    s.aura(cx, cy, 88, KIND[kind], 0.30)
    pts = [iso(x0, y0, 0), iso(x1 + 4, y0, 0), iso(x1 + 4, y1 + 4, 0), iso(x0, y1 + 4, 0)]
    s.poly2(pts, '#000000', stroke=None, opacity=0.38)


def pipe3(s, pts, color, sw=6):
    s.line3(pts, OUT, sw=sw + 3)
    s.line3(pts, color, sw=sw)
    s.line3(pts, shade(color, 0.55), sw=max(1.2, sw * 0.25), opacity=0.8)


def leds(s, b, face, v, u0, u1, n, colors, size=0.05, glow=True):
    for i in range(n):
        u = u0 + (u1 - u0) * (i + 0.5) / n
        c = colors[i % len(colors)]
        s.frect(b, face, u - size / 2, v - size, u + size / 2, v + size, c, glow=glow and c != DARK)


def fan_top(s, b, cu, cv, r, blade=STEEL, hub=GREEN, ring=DARK, n=5):
    w, d = b[3], b[4]
    ru, rv = r / w, r / d
    s.fcircle(b, 'top', cu, cv, ru, rv, ring, sw=1.4)
    for k in range(n):
        t = k * 2 * math.pi / n
        s.fpoly(b, 'top', [(cu + .18 * ru * math.cos(t), cv + .18 * rv * math.sin(t)),
                           (cu + .9 * ru * math.cos(t + .35), cv + .9 * rv * math.sin(t + .35)),
                           (cu + .9 * ru * math.cos(t + .9), cv + .9 * rv * math.sin(t + .9))], blade, stroke=OUT, sw=0.6)
    s.fcircle(b, 'top', cu, cv, ru * .26, rv * .26, hub, stroke=None, glow=True)


def fan_face(s, b, face, cu, cv, r, blade=STEEL, hub=CYAN, ring=DARK, n=5, grille=None):
    w = b[3] if face == 'left' else b[4]
    h = b[5]
    ru, rv = r / w, r / h
    s.fcircle(b, face, cu, cv, ru, rv, ring, sw=1.4)
    for k in range(n):
        t = k * 2 * math.pi / n
        s.fpoly(b, face, [(cu + .18 * ru * math.cos(t), cv + .18 * rv * math.sin(t)),
                          (cu + .9 * ru * math.cos(t + .35), cv + .9 * rv * math.sin(t + .35)),
                          (cu + .9 * ru * math.cos(t + .9), cv + .9 * rv * math.sin(t + .9))], blade, stroke=OUT, sw=0.6)
    s.fcircle(b, face, cu, cv, ru * .24, rv * .24, hub, stroke=None, glow=True)
    if grille:
        for k in (-0.6, -0.2, 0.2, 0.6):
            s.fline(b, face, [(cu + k * ru, cv - rv * math.sqrt(1 - k * k)), (cu + k * ru, cv + rv * math.sqrt(1 - k * k))],
                    grille, sw=1.0, opacity=0.7)


def server_face(s, b, face, rows, col=GREEN, alt=CYAN, u0=0.08, u1=0.92, seed=1):
    """Stacked server units on a rack face with glowing status bars."""
    rnd = random.Random(seed)
    for i in range(rows):
        v0 = 0.06 + i * 0.88 / rows
        v1 = v0 + 0.88 / rows * 0.8
        s.frect(b, face, u0, v0, u1, v1, DARK, stroke=OUT, sw=0.7)
        L = rnd.uniform(0.25, 0.5)
        c = alt if rnd.random() < 0.25 else col
        s.frect(b, face, u0 + 0.06, v0 + (v1 - v0) * 0.3, u0 + 0.06 + L, v0 + (v1 - v0) * 0.7, c, glow=True)
        s.frect(b, face, u1 - 0.12, v0 + (v1 - v0) * 0.3, u1 - 0.06, v0 + (v1 - v0) * 0.7, c, glow=True)


TILES = {}


def tile(name, kind):
    def deco(fn):
        TILES[name] = (fn, kind)
        return fn
    return deco


# ============================================================ GPU tiles (green)
@tile('gpu_old', 'gpu')
def gpu_old(s):
    # sad, dusty beige card lying on its side, faded RGB stripe, cobweb, dust bunnies
    s.box(14, 22, 0, 6, 56, 34, color='#7E8494')  # bent bracket
    b = s.box(20, 22, 0, 66, 56, 20, color=BEIGE)
    fan_top(s, b, 0.5, 0.5, 21, blade='#7B7666', hub='#5E8F6E', ring='#57524A')
    # faded / broken RGB stripe (one segment dead)
    for i, c in enumerate(('#B85A5A', '#5D9D72', '#4F5A80', '#3A3A3A')):
        s.frect(b, 'left', 0.08 + i * 0.21, 0.4, 0.26 + i * 0.21, 0.62, c, glow=(i == 1))
    s.frect(b, 'right', 0.15, 0.35, 0.85, 0.6, '#6F6A5C')
    # dust specks
    rnd = random.Random(7)
    for _ in range(26):
        u, v = rnd.uniform(0.05, 0.95), rnd.uniform(0.05, 0.95)
        p = Scene.fpt(b, 'top', u, v)
        s.ellipse2(p[0], p[1], rnd.uniform(0.8, 1.8), rnd.uniform(0.5, 1.1), '#D8D0BA', stroke=None, opacity=0.75)
    # cobweb across the corner
    c0 = Scene.fpt(b, 'top', 0.0, 0.0)
    for a, bb in (((0.0, 0.35), (0.28, 0.0)), ((0.0, 0.2), (0.16, 0.0))):
        s.line2([Scene.fpt(b, 'top', *a), Scene.fpt(b, 'top', *bb)], '#E6E2D6', sw=0.9, opacity=0.6)
    for t in ((0.0, 0.42), (0.34, 0.0), (0.24, 0.24)):
        s.line2([c0, Scene.fpt(b, 'top', *t)], '#E6E2D6', sw=0.9, opacity=0.6)
    # dust bunnies on the floor
    for (x, y) in ((70, 88), (88, 64)):
        p = iso(x, y, 0)
        s.ellipse2(p[0], p[1], 5, 2.6, '#8F8A7C', stroke=OUT, sw=0.8)
    # sad smoke wisp
    p = Scene.fpt(b, 'top', 0.5, 0.5)
    s.path2(f'M{p[0]:.1f},{p[1]-6:.1f} q-6,-10 0,-18 q6,-8 -1,-18', 'none',
            [(p[0] - 8, p[1] - 44), (p[0] + 8, p[1])], stroke='#9AA0AE', sw=2.2, opacity=0.6)


@tile('gpu_gamer', 'gpu')
def gpu_gamer(s):
    s.box(8, 22, 0, 6, 58, 40, color=SILVER)
    b = s.box(14, 22, 0, 78, 58, 24, color=NAVY)
    for cu in (0.28, 0.72):
        fan_top(s, b, cu, 0.5, 18, n=7)
    s.frect(b, 'left', 0.06, 0.32, 0.94, 0.62, GREEN, glow=True)
    s.frect(b, 'right', 0.1, 0.3, 0.9, 0.55, shade(GREEN, -0.35))
    s.fline(b, 'top', [(0.02, 0.06), (0.98, 0.06)], GREEN, sw=1.6, glow=True)


@tile('gpu_v_class', 'gpu')
def gpu_v_class(s):
    s.box(6, 20, 0, 6, 62, 36, color=SILVER)
    b = s.box(12, 20, 0, 82, 62, 24, color='#3B4568')
    for i in range(10):
        u = 0.08 + i * 0.087
        s.frect(b, 'top', u, 0.12, u + 0.042, 0.88, DARK)
    s.frect(b, 'top', 0.38, 0.36, 0.62, 0.64, '#22305A', stroke=OUT)
    s.frect(b, 'top', 0.43, 0.42, 0.57, 0.58, GREEN, glow=True)
    s.frect(b, 'left', 0.08, 0.38, 0.6, 0.62, GREEN, glow=True)
    s.frect(b, 'left', 0.7, 0.38, 0.92, 0.62, DARK)
    s.frect(b, 'right', 0.15, 0.3, 0.85, 0.7, DARK)


@tile('srv_a_class', 'gpu')
def srv_a_class(s):
    b = s.box(8, 14, 0, 84, 76, 30, color='#2A3766')
    for i in range(8):
        u = 0.06 + i * 0.112
        s.frect(b, 'left', u, 0.18, u + 0.09, 0.82, DARK, stroke=OUT, sw=0.6)
        s.frect(b, 'left', u + 0.02, 0.62, u + 0.07, 0.74, GREEN, glow=True)
    for i in range(6):
        v = 0.12 + i * 0.13
        s.frect(b, 'top', 0.1, v, 0.9, v + 0.06, DARK)
    s.frect(b, 'top', 0.36, 0.42, 0.64, 0.58, GREEN, glow=True)
    s.frect(b, 'right', 0.08, 0.3, 0.92, 0.55, shade(GREEN, -0.4))
    s.frect(b, 'right', 0.08, 0.66, 0.4, 0.82, DARK)


@tile('srv_h_class', 'gpu')
def srv_h_class(s):
    b = s.box(6, 10, 0, 88, 82, 46, color=NAVY)
    # front: two rows of 4 GPU sleds + amber accent band
    for r in range(2):
        for i in range(4):
            u = 0.05 + i * 0.235
            v0 = 0.08 + r * 0.38
            s.frect(b, 'left', u, v0, u + 0.2, v0 + 0.32, DARK, stroke=OUT, sw=0.7)
            s.frect(b, 'left', u + 0.03, v0 + 0.1, u + 0.17, v0 + 0.22, GREEN, glow=True)
    s.frect(b, 'left', 0.0, 0.86, 1.0, 0.96, AMBER)
    s.frect(b, 'right', 0.0, 0.86, 1.0, 0.96, shade(AMBER, -0.35))
    for i in range(5):
        s.frect(b, 'right', 0.08, 0.1 + i * 0.14, 0.92, 0.16 + i * 0.14, DARK)
    s.frect(b, 'top', 0.2, 0.2, 0.8, 0.8, '#22305A', stroke=OUT)
    for (u, v) in ((0.35, 0.35), (0.65, 0.35), (0.35, 0.65), (0.65, 0.65)):
        s.frect(b, 'top', u - 0.1, v - 0.1, u + 0.1, v + 0.1, GREEN, glow=True)


def rack(s, x, y, w, d, h, color, rows, seed, col=GREEN, alt=CYAN, top_glow=None):
    b = s.box(x, y, 0, w, d, h, color=color)
    server_face(s, b, 'left', rows, col=col, alt=alt, seed=seed)
    for i in range(rows):
        v = 0.08 + i * 0.88 / rows
        s.frect(b, 'right', 0.1, v, 0.9, v + 0.88 / rows * 0.6, shade(color, -0.5))
    if top_glow:
        s.frect(b, 'top', 0.2, 0.2, 0.8, 0.8, top_glow, glow=True)
    return b


@tile('rack_h_class', 'gpu')
def rack_h_class(s):
    b = rack(s, 22, 18, 56, 62, 96, '#2C3866', 6, 3)
    s.frect(b, 'top', 0.15, 0.15, 0.85, 0.85, DARK)
    s.frect(b, 'top', 0.3, 0.3, 0.7, 0.7, GREEN, glow=True, opacity=0.7)


@tile('rack_b_class', 'gpu')
def rack_b_class(s):
    # wide NVL rack, liquid manifolds on the side
    b = rack(s, 14, 18, 70, 64, 98, '#25305C', 8, 5, alt=GREEN)
    s.frect(b, 'top', 0.1, 0.1, 0.9, 0.9, DARK)
    s.frect(b, 'top', 0.2, 0.25, 0.8, 0.75, GREEN, glow=True)
    # coolant manifold (thin, cyan) down the right side + hoses
    pipe3(s, [(86, 30, 4), (86, 30, 92)], CYAN, sw=4)
    pipe3(s, [(86, 70, 4), (86, 70, 92)], '#3D8BFF', sw=4)
    pipe3(s, [(86, 30, 92), (86, 50, 102), (86, 70, 92)], SILVER, sw=3)


@tile('rack_r_class', 'gpu')
def rack_r_class(s):
    cx, cy = iso(50, 50, 40)
    s.aura(cx, cy, 90, GREEN, 0.35)
    b = s.box(12, 14, 0, 76, 72, 100, color='#1F2850')
    # glowing vertical light pipes on the front
    for u in (0.12, 0.88):
        s.frect(b, 'left', u - 0.03, 0.04, u + 0.03, 0.96, GREEN, glow=True)
    for i in range(10):
        v = 0.06 + i * 0.088
        s.frect(b, 'left', 0.2, v, 0.8, v + 0.065, DARK, stroke=OUT, sw=0.5)
        s.frect(b, 'left', 0.24, v + 0.02, 0.24 + (0.2 + (i * 37 % 10) / 40), v + 0.045,
                CYAN if i % 4 == 2 else GREEN, glow=True)
    for u in (0.3, 0.7):
        s.frect(b, 'right', u - 0.08, 0.05, u + 0.08, 0.95, DARK)
        s.frect(b, 'right', u - 0.02, 0.1, u + 0.02, 0.9, shade(GREEN, -0.2), glow=True)
    s.frect(b, 'top', 0.08, 0.08, 0.92, 0.92, DARK)
    s.fpoly(b, 'top', [(0.5, 0.15), (0.85, 0.5), (0.5, 0.85), (0.15, 0.5)], GREEN, glow=True)
    s.fpoly(b, 'top', [(0.5, 0.33), (0.67, 0.5), (0.5, 0.67), (0.33, 0.5)], WHITE, glow=True)


@tile('pod_b_class', 'gpu')
def pod_b_class(s):
    # a 3x2 block of racks on a shared plinth, hot-aisle roof with green lights
    s.box(4, 4, 0, 92, 92, 6, color='#1E2747')
    k = 0
    for j in (0, 1):
        for i in (0, 1, 2):
            x, y = 8 + i * 29, 10 + j * 44
            b = s.box(x, y, 6, 26, 36, 58, color='#2A3566')
            server_face(s, b, 'left', 4, seed=k)
            s.frect(b, 'right', 0.15, 0.1, 0.85, 0.9, shade('#2A3566', -0.45))
            s.frect(b, 'top', 0.2, 0.2, 0.8, 0.8, GREEN, glow=True)
            k += 1
    pipe3(s, [(6, 48, 70), (94, 48, 70)], CYAN, sw=3)


@tile('bldg_r_class', 'gpu')
def bldg_r_class(s):
    cx, cy = iso(50, 50, 30)
    s.aura(cx, cy, 95, GREEN, 0.3)
    b = s.box(6, 10, 0, 88, 80, 46, color='#2C3866')
    for i in range(7):
        u = 0.06 + i * 0.13
        s.frect(b, 'left', u, 0.2, u + 0.09, 0.75, DARK, stroke=OUT, sw=0.6)
        s.frect(b, 'left', u + 0.02, 0.3, u + 0.07, 0.65, GREEN, glow=True)
    for i in range(6):
        u = 0.07 + i * 0.15
        s.frect(b, 'right', u, 0.25, u + 0.1, 0.7, DARK, stroke=OUT, sw=0.6)
        s.frect(b, 'right', u + 0.02, 0.35, u + 0.08, 0.6, shade(GREEN, -0.15), glow=True)
    s.frect(b, 'left', 0.0, 0.88, 1.0, 1.0, shade(GREEN, -0.5))
    # rooftop units
    for (x, y) in ((14, 18), (40, 18), (66, 18)):
        r = s.box(x, y, 46, 20, 22, 10, color=STEEL)
        fan_top(s, r, 0.5, 0.5, 8, hub=CYAN, n=4)
    for (x, y) in ((14, 56), (40, 56)):
        r = s.box(x, y, 46, 20, 22, 8, color=STEEL)
        s.frect(r, 'top', 0.2, 0.2, 0.8, 0.8, GREEN, glow=True)
    s.box(68, 56, 46, 18, 24, 16, color=NAVY)


# ------------------------------------------------ speculative (sci-fi) GPUs
VIOLET = '#B07CFF'
PINK = '#FF6FD8'
ICE = '#BFEFFF'


@tile('bldg_p_class', 'gpu')
def bldg_p_class(s):
    # Opal photonic stack: a dark glass block of stacked dies, light
    # conduits (violet/cyan/pink) running up the faces and over the roof
    # into a glowing prism.
    cx, cy = iso(50, 50, 40)
    s.aura(cx, cy, 98, VIOLET, 0.32)
    s.box(6, 10, 0, 88, 80, 6, color='#1B2140')
    layers = 4
    for k in range(layers):
        b = s.box(10 + k * 3, 14 + k * 3, 6 + k * 10, 80 - k * 6, 72 - k * 6, 10,
                  color='#202A55', top='#2B3A70')
        # glassy stripe along each layer's faces
        s.frect(b, 'left', 0.03, 0.35, 0.97, 0.65, shade(CYAN, -0.55), opacity=0.9)
        s.frect(b, 'right', 0.03, 0.35, 0.97, 0.65, shade(VIOLET, -0.6), opacity=0.9)
    top = (10 + 3 * 3, 14 + 3 * 3, 6 + 3 * 10, 80 - 3 * 6, 72 - 3 * 6, 10)
    # vertical light conduits through the stack (waveguides)
    cols = [VIOLET, CYAN, PINK, CYAN, VIOLET]
    for i, c in enumerate(cols):
        u = 0.12 + i * 0.19
        s.line3([(10 + u * 80, 86, 6), (19 + u * 62, 77, 46)], c, sw=2.6, glow=True)
    for i, c in enumerate([PINK, CYAN, VIOLET, PINK]):
        v = 0.15 + i * 0.23
        s.line3([(90, 14 + v * 72, 6), (81, 23 + v * 54, 46)], c, sw=2.2, glow=True, opacity=0.9)
    # roof: waveguide grid feeding a central prism
    for t in (0.25, 0.5, 0.75):
        s.fline(top, 'top', [(0.06, t), (0.94, t)], CYAN, sw=1.6, glow=True, opacity=0.8)
        s.fline(top, 'top', [(t, 0.06), (t, 0.94)], VIOLET, sw=1.6, glow=True, opacity=0.8)
    px, py, pz = 50, 50, 46
    tip = (px, py, pz + 30)
    base4 = [(px - 11, py - 11, pz), (px + 11, py - 11, pz), (px + 11, py + 11, pz), (px - 11, py + 11, pz)]
    s.poly2([iso(*base4[1]), iso(*base4[2]), iso(*tip)], shade(VIOLET, -0.15), sw=1.2)
    s.poly2([iso(*base4[2]), iso(*base4[3]), iso(*tip)], shade(CYAN, -0.05), sw=1.2)
    s.poly2([iso(*base4[2]), iso(*tip), iso(px + 4, py + 4, pz + 12)], WHITE, stroke=None, glow=True, opacity=0.55)
    tx, ty = iso(*tip)
    s.sparkle(tx, ty - 2, 14, WHITE)


@tile('bldg_s_class', 'gpu')
def bldg_s_class(s):
    # Boreal cryo-logic vault: a frosted white-blue vault with a big
    # cryostat dome on the roof, helium lines and icy glow.
    cx, cy = iso(50, 50, 30)
    s.aura(cx, cy, 98, ICE, 0.34)
    b = s.box(8, 12, 0, 84, 76, 40, color='#5D7FA8', top='#DCEFFF', right='#3F5C82')
    # frosted panels with ice-cyan seams
    for i in range(5):
        u = 0.05 + i * 0.19
        s.frect(b, 'left', u, 0.12, u + 0.16, 0.8, '#9EC4E6', stroke=OUT, sw=0.6)
        s.frect(b, 'left', u + 0.02, 0.62, u + 0.14, 0.72, CYAN, glow=True)
    for i in range(4):
        u = 0.06 + i * 0.235
        s.frect(b, 'right', u, 0.15, u + 0.2, 0.8, '#6E92BC', stroke=OUT, sw=0.6)
        s.frect(b, 'right', u + 0.03, 0.62, u + 0.17, 0.72, shade(CYAN, -0.1), glow=True)
    # frost rim along the bottom
    s.frect(b, 'left', 0.0, 0.86, 1.0, 1.0, WHITE, opacity=0.75)
    s.frect(b, 'right', 0.0, 0.86, 1.0, 1.0, ICE, opacity=0.6)
    # helium compressor at the back, line into the cryostat
    s.box(14, 18, 40, 14, 14, 10, color=STEEL)
    pipe3(s, [(21, 25, 50), (21, 25, 56), (38, 40, 56)], ICE, sw=3)
    # cryostat: a frosted tank with glowing cold bands
    s.cyl(50, 50, 40, 24, 6, color='#7FA4CC', top='#DCEFFF')
    c = s.cyl(50, 50, 46, 17, 26, color='#B8D6F2', top='#F2FAFF')
    for k, z in enumerate((52, 62)):
        bx, by = iso(50, 50, z)
        s.ellipse2(bx, by, c[2], c[3], 'none', stroke=CYAN, sw=2.4, glow=True)
    s.ellipse2(c[0], c[4], c[2] * 0.55, c[3] * 0.55, CYAN, stroke=None, glow=True)
    s.sparkle(c[0], c[4] - 2, 12, WHITE)
    # second compressor in front
    s.box(70, 66, 40, 14, 14, 10, color=STEEL)
    pipe3(s, [(77, 73, 50), (77, 73, 56), (62, 62, 56)], ICE, sw=3)
    # frost crystals on the roof edge
    for (u, v) in ((0.1, 0.85), (0.9, 0.15), (0.85, 0.9)):
        px, py = Scene.fpt(b, 'top', u, v)
        s.sparkle(px, py, 8, WHITE)


@tile('mod_z_class', 'gpu')
def mod_z_class(s):
    # Zenith orbital cryo-module: a gold-foiled pressure hull lying on the
    # truss, a white sunshield on top, a frosted cryo core glowing through,
    # its own solar wings out to the sides and radiator fins underneath.
    cx, cy = iso(50, 50, 30)
    s.aura(cx, cy, 100, ICE, 0.34)
    # radiator fins (edge-on, white) under the hull
    for k in range(5):
        y = 18 + k * 15
        s.box(4, y, 0, 92, 4, 14, color='#C9D3E2', top='#F2F6FB', right='#9DA9BD', sw=0.8)
    # solar wings on short booms, sticking out left and right
    for (y0, y1) in ((-30, 6), (94, 130)):
        s.line3([(50, max(y0, 6) if y0 < 0 else 94, 30), (50, (y0 + y1) / 2, 30)], SILVER, sw=2.4)
        pts = [iso(22, y0, 30), iso(78, y0, 30), iso(78, y1, 30), iso(22, y1, 30)]
        s.poly2(pts, '#1C3A7A', stroke='#D8A93E', sw=1.6)
        for k in range(1, 4):
            u = 22 + k * 14
            s.line2([iso(u, y0, 30), iso(u, y1, 30)], '#4F7FD8', sw=1, opacity=0.9)
        s.line2([iso(22, (y0 + y1) / 2, 30), iso(78, (y0 + y1) / 2, 30)], '#4F7FD8', sw=1, opacity=0.9)
    # pressure hull with gold foil and a cyan cryo band
    b = s.box(12, 16, 12, 76, 68, 32, color='#B88A2E', top='#E7C46A', right='#8E6A22')
    for i in range(6):
        u = 0.05 + i * 0.16
        s.frect(b, 'left', u, 0.15, u + 0.12, 0.85, '#D8A93E', stroke=OUT, sw=0.5, opacity=0.85)
    s.frect(b, 'left', 0.0, 0.45, 1.0, 0.6, CYAN, glow=True)
    s.frect(b, 'right', 0.0, 0.45, 1.0, 0.6, shade(CYAN, -0.1), glow=True)
    # sunshield: layered white sheets on top
    for k in range(3):
        s.box(16 + k * 4, 20 + k * 4, 44 + k * 4, 68 - k * 8, 60 - k * 8, 2, color='#DCE4EF', top='#FFFFFF', sw=0.9)
    # frosted core window and a docking ring
    tx, ty = iso(50, 50, 56)
    s.ellipse2(tx, ty, 14, 8, ICE, stroke=OUT, glow=True)
    s.sparkle(tx, ty - 4, 12, WHITE)
    s.cyl(84, 30, 44, 7, 8, color=SILVER)


# ============================================================ Cooling (cyan)
COOL = '#3E6E95'   # steel-blue chassis for cooling gear
COOLD = '#2A4D70'


@tile('cool_fan', 'cool')
def cool_fan(s):
    # upright box fan on little feet, facing the viewer (left face)
    for x in (24, 66):
        s.box(x, 46, 0, 10, 22, 4, color=STEEL)
    b = s.box(18, 52, 4, 64, 12, 74, color=COOL)
    fan_face(s, b, 'left', 0.5, 0.5, 28, blade='#9FDDF2', hub=CYAN, ring=DARK, n=5, grille=SILVER)
    s.fcircle(b, 'left', 0.5, 0.5, 30 / 64, 30 / 74, 'none', stroke=CYAN, sw=1.6, glow=True)
    # knob + cord
    p = Scene.fpt(b, 'right', 0.5, 0.15)
    s.ellipse2(p[0], p[1], 2.5, 2.5, AMBER, stroke=OUT, sw=0.8)
    s.line3([(82, 60, 8), (90, 70, 0), (92, 88, 0)], OUT, sw=2)
    # air streaks
    for k, z in enumerate((26, 42, 58)):
        s.line3([(30 + k * 10, 70, z), (36 + k * 10, 92, z - 4)], CYAN, sw=2.2, glow=True, opacity=0.8)


@tile('cool_window_ac', 'cool')
def cool_window_ac(s):
    b = s.box(10, 22, 0, 80, 62, 50, color='#C7D3E6')
    # front grille: louvres with cyan cold glow
    s.frect(b, 'left', 0.05, 0.1, 0.62, 0.88, '#1E3550', stroke=OUT, sw=0.8)
    for i in range(6):
        v = 0.16 + i * 0.12
        s.frect(b, 'left', 0.07, v, 0.6, v + 0.05, CYAN, glow=True)
    s.frect(b, 'left', 0.68, 0.12, 0.95, 0.46, '#2B3A5A', stroke=OUT, sw=0.8)
    for i, c in enumerate((CYAN, GREEN, DARK)):
        s.frect(b, 'left', 0.72 + i * 0.075, 0.24, 0.77 + i * 0.075, 0.32, c, glow=c != DARK)
    s.frect(b, 'left', 0.7, 0.6, 0.93, 0.8, '#9AA9C4', stroke=OUT, sw=0.6)
    for i in range(8):
        s.frect(b, 'right', 0.06 + i * 0.115, 0.15, 0.1 + i * 0.115, 0.85, '#7F8EAD')
    for i in range(5):
        s.frect(b, 'top', 0.1, 0.12 + i * 0.16, 0.9, 0.18 + i * 0.16, '#8E9CB8')
    # cold air puffs
    for k, (x, z) in enumerate(((22, 30), (40, 18), (30, 8))):
        p = iso(x, 92, z)
        s.ellipse2(p[0], p[1], 7, 3.5, '#BFF3FF', stroke=None, opacity=0.55, glow=True)


@tile('cool_crac', 'cool')
def cool_crac(s):
    b = s.box(10, 22, 0, 80, 56, 86, color=COOL)
    # door panels with cyan grilles
    for i in range(3):
        u = 0.04 + i * 0.32
        s.frect(b, 'left', u, 0.05, u + 0.3, 0.95, COOLD, stroke=OUT, sw=0.7)
        for k in range(7):
            v = 0.12 + k * 0.1
            s.frect(b, 'left', u + 0.05, v, u + 0.25, v + 0.035, '#5FC3E6' if i != 1 else DARK)
    s.frect(b, 'left', 0.4, 0.18, 0.6, 0.32, DARK, stroke=OUT)
    s.frect(b, 'left', 0.43, 0.21, 0.57, 0.29, CYAN, glow=True)
    for i in range(4):
        s.frect(b, 'right', 0.1, 0.12 + i * 0.2, 0.9, 0.2 + i * 0.2, shade(COOL, -0.5))
    fan_top(s, b, 0.27, 0.5, 15, blade='#9FDDF2', hub=CYAN)
    fan_top(s, b, 0.73, 0.5, 15, blade='#9FDDF2', hub=CYAN)


@tile('cool_rear_door', 'cool')
def cool_rear_door(s):
    # rack silhouette behind, heat-exchanger door in front with serpentine coil
    s.box(20, 16, 0, 60, 44, 94, color='#283358')
    b = s.box(18, 60, 0, 64, 10, 98, color=COOL)
    s.frect(b, 'left', 0.06, 0.04, 0.94, 0.96, '#183552', stroke=OUT, sw=0.8)
    pts = []
    n = 7
    for i in range(n):
        v = 0.1 + i * 0.8 / (n - 1)
        pts += [(0.14, v), (0.86, v)] if i % 2 == 0 else [(0.86, v), (0.14, v)]
    s.fline(b, 'left', pts, OUT, sw=5.5)
    s.fline(b, 'left', pts, CYAN, sw=3.2, glow=True)
    # hoses at bottom
    pipe3(s, [(30, 70, 6), (30, 84, 6), (30, 94, 0)], '#3D8BFF', sw=4)
    pipe3(s, [(70, 70, 6), (70, 84, 6), (70, 94, 0)], CYAN, sw=4)
    p = Scene.fpt(b, 'right', 0.5, 0.5)
    s.ellipse2(p[0], p[1], 1.6, 3, CYAN, stroke=None, glow=True)


@tile('cool_liquid', 'cool')
def cool_liquid(s):
    # CDU box with a loop of thick coolant pipes and a cold plate
    b = s.box(14, 14, 0, 44, 44, 52, color=COOL)
    s.frect(b, 'left', 0.12, 0.12, 0.88, 0.5, '#183552', stroke=OUT)
    s.frect(b, 'left', 0.2, 0.22, 0.8, 0.4, CYAN, glow=True)
    for k in range(3):
        s.frect(b, 'right', 0.15, 0.2 + k * 0.22, 0.85, 0.3 + k * 0.22, shade(COOL, -0.5))
    fan_top(s, b, 0.5, 0.5, 14, blade='#9FDDF2', hub=CYAN)
    # cold plate / block on the floor
    cp = s.box(58, 60, 0, 30, 28, 12, color='#1E3550')
    s.frect(cp, 'top', 0.15, 0.15, 0.85, 0.85, CYAN, glow=True)
    pipe3(s, [(40, 58, 30), (40, 74, 30), (40, 74, 8), (58, 74, 8)], '#3D8BFF', sw=6)
    pipe3(s, [(58, 30, 36), (76, 30, 36), (76, 60, 12)], CYAN, sw=6)
    # droplet
    p = iso(30, 80, 46)
    s.path2(f'M{p[0]:.1f},{p[1]-9:.1f} C{p[0]+6:.1f},{p[1]-2:.1f} {p[0]+5:.1f},{p[1]+5:.1f} {p[0]:.1f},{p[1]+5:.1f} '
            f'C{p[0]-5:.1f},{p[1]+5:.1f} {p[0]-6:.1f},{p[1]-2:.1f} {p[0]:.1f},{p[1]-9:.1f} Z', CYAN,
            [(p[0] - 6, p[1] - 9), (p[0] + 6, p[1] + 5)], glow=True)


@tile('cool_chiller', 'cool')
def cool_chiller(s):
    # long, low chiller plant with three big top fans and side coils
    b = s.box(4, 14, 0, 92, 72, 40, color=COOL)
    for i in range(10):
        s.frect(b, 'left', 0.04 + i * 0.096, 0.15, 0.08 + i * 0.096, 0.85, COOLD)
    for i in range(7):
        s.frect(b, 'right', 0.06 + i * 0.13, 0.15, 0.1 + i * 0.13, 0.85, shade(COOL, -0.55))
    for cu in (0.2, 0.5, 0.8):
        fan_top(s, b, cu, 0.5, 15, blade='#9FDDF2', hub=CYAN)
    pipe3(s, [(24, 86, 8), (24, 96, 8)], '#3D8BFF', sw=7)
    pipe3(s, [(44, 86, 8), (44, 96, 8)], CYAN, sw=7)


@tile('cool_tower', 'cool')
def cool_tower(s):
    # mechanical-draft cooling tower: louvred box, two fan stacks, steam
    b = s.box(10, 12, 0, 80, 76, 48, color='#557A9C')
    for i in range(6):
        s.frect(b, 'left', 0.04, 0.1 + i * 0.13, 0.96, 0.16 + i * 0.13, COOLD)
        s.frect(b, 'right', 0.04, 0.1 + i * 0.13, 0.96, 0.16 + i * 0.13, shade(COOLD, -0.4))
    s.frect(b, 'left', 0.0, 0.9, 1.0, 1.0, CYAN, glow=True, opacity=0.8)
    for (x, y) in ((30, 64), (66, 30)):
        cx, cy, rx, ry, ty = s.cyl(x, y, 48, 15, 20, color='#6E93B5')
        s.ellipse2(cx, ty, rx * 0.8, ry * 0.8, DARK, sw=1)
        s.ellipse2(cx, ty, rx * 0.25, ry * 0.25, CYAN, stroke=None, glow=True)
    for (x, y) in ((30, 64), (66, 30)):
        p = iso(x, y, 72)
        for k, (ox, oy, r) in enumerate(((0, -2, 8), (5, -11, 7), (-2, -19, 6))):
            s.ellipse2(p[0] + ox, p[1] + oy, r * 1.3, r, '#DDF6FF', stroke=None, opacity=0.75 - k * 0.2, glow=True)


@tile('cool_dry', 'cool')
def cool_dry(s):
    # closed-loop dry cooler: a low V-coil radiator bank with a grid of fans
    b = s.box(8, 10, 0, 84, 80, 26, color='#4F6E92')
    for i in range(7):
        u = 0.06 + i * 0.13
        s.fline(b, 'left', [(u, 0.2), (u + 0.065, 0.8), (u + 0.13, 0.2)], COOLD, sw=2)
        s.fline(b, 'right', [(u, 0.2), (u + 0.065, 0.8), (u + 0.13, 0.2)], shade(COOLD, -0.35), sw=2)
    s.frect(b, 'left', 0.0, 0.88, 1.0, 1.0, CYAN, glow=True, opacity=0.8)
    for i in range(3):
        for j in range(2):
            fan_top(s, b, 0.2 + i * 0.3, 0.28 + j * 0.44, 11, blade=SILVER, hub=CYAN)
    # sealed loop: two pipes in, no steam
    pipe3(s, [(30, 92, 6), (30, 100, 6)], '#3D8BFF', sw=7)
    pipe3(s, [(50, 92, 6), (50, 100, 6)], CYAN, sw=7)


@tile('cool_radiator', 'cool')
def cool_radiator(s):
    # Deployable radiator wing: stacked white ribbed panels on a short
    # mast, a warm ammonia manifold along their root, no fans at all.
    b = s.box(30, 30, 0, 40, 40, 12, color='#4F6E92')
    s.frect(b, 'left', 0.1, 0.3, 0.9, 0.7, CYAN, glow=True, opacity=0.8)
    s.frect(b, 'right', 0.1, 0.3, 0.9, 0.7, shade(CYAN, -0.2), glow=True, opacity=0.7)
    z0 = 12
    for k, z in enumerate((26, 50, 74)):
        # mast segment up to this panel, then the panel (with thickness)
        s.line3([(50, 50, z0), (50, 50, z)], OUT, sw=7)
        s.line3([(50, 50, z0), (50, 50, z)], SILVER, sw=4.5)
        z0 = z
        d = 4
        s.poly2([iso(8, 92, z), iso(92, 92, z + 6), iso(92, 92, z + 6 - d), iso(8, 92, z - d)], '#8E9CB2', sw=1.2)
        s.poly2([iso(92, 8, z + 6), iso(92, 92, z + 6), iso(92, 92, z + 6 - d), iso(92, 8, z + 6 - d)], '#6E7A90', sw=1.2)
        s.poly2([iso(8, 8, z), iso(92, 8, z + 6), iso(92, 92, z + 6), iso(8, 92, z)], '#E8EEF6', sw=1.4)
        for j in range(1, 7):
            v = 8 + j * 84 / 7
            s.line2([iso(12, v, z + 0.3), iso(88, v, z + 5.7)], '#A9B4C6', sw=1.1)
        s.line2([iso(8, 50, z), iso(92, 50, z + 6)], '#FF9F6B', sw=2.6, glow=True, opacity=0.9)


# ============================================================ Network (amber)
NETC = '#2B3150'


def amber_trim(s, b):
    """Glowing amber edge along the top-front of a network box: the network-kind signature."""
    s.fline(b, 'top', [(0.0, 0.97), (1.0, 0.97)], AMBER, sw=2.6, glow=True)
    s.fline(b, 'top', [(0.97, 0.0), (0.97, 0.97)], shade(AMBER, -0.25), sw=2.2, glow=True)


def ports(s, b, face, v0, v1, n, u0=0.06, u1=0.94, lit=None, color=AMBER):
    lit = lit if lit is not None else set(range(0, n, 1))
    pw = (u1 - u0) / n
    for i in range(n):
        u = u0 + i * pw
        s.frect(b, face, u + pw * 0.12, v0, u + pw * 0.88, v1, OUT)
        if i in lit:
            s.frect(b, face, u + pw * 0.2, v0 + (v1 - v0) * 0.1, u + pw * 0.8, v0 + (v1 - v0) * 0.45,
                    color if i % 3 else ORANGE, glow=True)


@tile('net_home', 'net')
def net_home(s):
    b = s.box(18, 32, 0, 64, 40, 14, color='#3A4166')
    s.frect(b, 'top', 0.1, 0.2, 0.9, 0.8, '#2C3254')
    for i in range(5):
        s.frect(b, 'top', 0.18 + i * 0.14, 0.35, 0.24 + i * 0.14, 0.65, DARK)
    leds(s, b, 'left', 0.5, 0.12, 0.88, 5, [AMBER, AMBER, GREEN, AMBER, ORANGE], size=0.06)
    # three antennas
    for (x, tilt) in ((26, -10), (50, 0), (74, 10)):
        s.line3([(x, 34, 14), (x + tilt, 34, 62)], OUT, sw=6.5)
        s.line3([(x, 34, 14), (x + tilt, 34, 62)], '#5A6290', sw=4)
        p = iso(x + tilt, 34, 62)
        s.ellipse2(p[0], p[1], 2.6, 2.6, AMBER, stroke=OUT, sw=0.8, glow=True)
    # wifi arcs
    p = iso(50, 34, 74)
    for r in (8, 14):
        s.path2(f'M{p[0]-r:.1f},{p[1]:.1f} A{r},{r} 0 0 1 {p[0]+r:.1f},{p[1]:.1f}', 'none',
                [(p[0] - r, p[1] - r), (p[0] + r, p[1])], stroke=AMBER, sw=2.4, glow=True)


@tile('net_5g', 'net')
def net_5g(s):
    b = s.box(12, 28, 0, 76, 44, 18, color=NETC)
    amber_trim(s, b)
    s.frect(b, 'left', 0.03, 0.15, 0.97, 0.85, DARK, stroke=OUT, sw=0.6)
    ports(s, b, 'left', 0.38, 0.8, 5, u0=0.08, u1=0.78)
    s.frect(b, 'left', 0.84, 0.35, 0.92, 0.6, AMBER, glow=True)
    for i in range(6):
        s.frect(b, 'top', 0.12 + i * 0.13, 0.25, 0.17 + i * 0.13, 0.75, DARK)
    for i in range(3):
        s.frect(b, 'right', 0.2 + i * 0.22, 0.3, 0.3 + i * 0.22, 0.7, DARK)
    # plugged cables
    for x in (24, 40):
        s.line3([(x, 72, 6), (x + 2, 92, 0)], AMBER, sw=2.6)


@tile('net_10g', 'net')
def net_10g(s):
    b = s.box(8, 24, 0, 84, 52, 22, color='#323A60')
    amber_trim(s, b)
    s.frect(b, 'left', 0.02, 0.1, 0.98, 0.9, DARK, stroke=OUT, sw=0.6)
    ports(s, b, 'left', 0.25, 0.5, 8, u0=0.05, u1=0.75)
    ports(s, b, 'left', 0.58, 0.83, 8, u0=0.05, u1=0.75)
    s.frect(b, 'left', 0.8, 0.25, 0.95, 0.83, '#3A425F', stroke=OUT, sw=0.6)
    s.frect(b, 'left', 0.83, 0.35, 0.92, 0.5, ORANGE, glow=True)
    s.frect(b, 'top', 0.3, 0.3, 0.7, 0.7, '#262D4C', stroke=OUT)
    s.frect(b, 'top', 0.42, 0.42, 0.58, 0.58, AMBER, glow=True)
    for x in (16, 28, 40):
        s.line3([(x, 76, 8), (x + 3, 96, 0)], AMBER, sw=2.4)


@tile('net_100g', 'net')
def net_100g(s):
    # 1U rack switch on short rails with a bundle of amber DACs
    b = s.box(4, 20, 8, 92, 60, 18, color='#2E3558')
    amber_trim(s, b)
    s.box(4, 74, 0, 6, 6, 8, color=STEEL)
    s.box(90, 74, 0, 6, 6, 8, color=STEEL)
    s.frect(b, 'left', 0.02, 0.1, 0.98, 0.9, DARK, stroke=OUT, sw=0.6)
    ports(s, b, 'left', 0.2, 0.46, 12, u0=0.04, u1=0.86)
    ports(s, b, 'left', 0.56, 0.82, 12, u0=0.04, u1=0.86)
    s.frect(b, 'left', 0.89, 0.25, 0.96, 0.75, ORANGE, glow=True)
    for i in range(7):
        s.frect(b, 'top', 0.08 + i * 0.12, 0.2, 0.13 + i * 0.12, 0.8, DARK)
    for k, x in enumerate((14, 22, 30, 38, 46)):
        s.line3([(x, 80, 16), (x - 2, 90, 8), (x - 6, 100, 0)], ORANGE if k % 2 else AMBER, sw=2.6, glow=k == 2)


@tile('net_ib', 'net')
def net_ib(s):
    b = s.box(6, 14, 0, 88, 70, 28, color='#2A2F4F')
    amber_trim(s, b)
    s.frect(b, 'left', 0.02, 0.08, 0.98, 0.92, DARK, stroke=OUT, sw=0.6)
    for r in range(2):
        v0 = 0.18 + r * 0.38
        for i in range(10):
            u = 0.05 + i * 0.09
            s.frect(b, 'left', u, v0, u + 0.075, v0 + 0.3, '#3B3220', stroke=OUT, sw=0.5)
            s.frect(b, 'left', u + 0.015, v0 + 0.06, u + 0.06, v0 + 0.16, AMBER, glow=True)
    s.frect(b, 'right', 0.1, 0.25, 0.9, 0.75, shade('#2A2F4F', -0.5))
    fan_top(s, b, 0.3, 0.5, 13, blade='#6B6F8F', hub=AMBER)
    fan_top(s, b, 0.7, 0.5, 13, blade='#6B6F8F', hub=AMBER)
    # orange fibre bundle sweeping out the front
    for k in range(6):
        x = 14 + k * 6
        s.line3([(x, 84, 18 - k), (x + 4, 94, 6), (x + 14, 100, 0)], ORANGE if k % 2 else AMBER, sw=2.2, glow=True)


@tile('net_ib_spine', 'net')
def net_ib_spine(s):
    # tall director chassis: line cards with amber port rows, fibre trunk from the top
    b = s.box(18, 18, 0, 64, 62, 92, color='#2A2F4F')
    for i in range(8):
        v = 0.05 + i * 0.112
        s.frect(b, 'left', 0.06, v, 0.94, v + 0.09, DARK, stroke=OUT, sw=0.5)
        for k in range(9):
            u = 0.1 + k * 0.088
            s.frect(b, 'left', u, v + 0.025, u + 0.05, v + 0.065, AMBER if (i + k) % 4 else ORANGE, glow=True)
    for i in range(6):
        s.frect(b, 'right', 0.12, 0.08 + i * 0.15, 0.88, 0.14 + i * 0.15, shade('#2A2F4F', -0.5))
    s.frect(b, 'top', 0.15, 0.15, 0.85, 0.85, DARK)
    # fibre trunk: many strands rising and arching back
    for k in range(7):
        x = 30 + k * 6
        s.line3([(x, 40, 92), (x, 40, 104 + k % 3 * 2), (x - 4, 10, 104), (x - 6, 0, 96)],
                ORANGE if k % 2 else AMBER, sw=2.2, glow=True)
    pipe3(s, [(28, 46, 92), (72, 46, 92)], '#5A4A2A', sw=4)


@tile('net_nvlink', 'net')
def net_nvlink(s):
    # NVLink spine cartridge: rack frame with dense copper backplane cables, amber switch trays
    b = s.box(18, 18, 0, 64, 62, 94, color='#2B2A40')
    for i in range(4):
        v = 0.06 + i * 0.12
        s.frect(b, 'left', 0.06, v, 0.94, v + 0.09, '#3A3426', stroke=OUT, sw=0.5)
        s.frect(b, 'left', 0.12, v + 0.03, 0.88, v + 0.06, AMBER, glow=True)
    # copper cable cassette (lower half): dense vertical bronze strands
    s.frect(b, 'left', 0.06, 0.56, 0.94, 0.96, '#1A1712', stroke=OUT, sw=0.6)
    for k in range(14):
        u = 0.09 + k * 0.059
        s.fline(b, 'left', [(u, 0.58), (u, 0.94)], '#C9803A' if k % 2 else '#E7A24F', sw=2.2)
    for k in range(6):
        u = 0.1 + k * 0.16
        s.fline(b, 'right', [(u, 0.05), (u, 0.95)], '#C9803A', sw=2.6)
    s.frect(b, 'top', 0.15, 0.15, 0.85, 0.85, DARK)
    s.fline(b, 'top', [(0.2, 0.5), (0.8, 0.5)], AMBER, sw=3, glow=True)
    s.fline(b, 'top', [(0.5, 0.2), (0.5, 0.8)], AMBER, sw=3, glow=True)


@tile('net_optical', 'net')
def net_optical(s):
    # optical circuit switch: chassis with a glowing prism core, fibres fanning out in all directions
    cx, cy = iso(50, 50, 50)
    s.aura(cx, cy, 80, AMBER, 0.35)
    rnd = random.Random(4)
    # back fibres (drawn first)
    for k in range(9):
        a = math.pi + k * math.pi / 8
        s.line3([(50, 50, 40), (50 + 48 * math.cos(a), 50 + 48 * math.sin(a), 20 + rnd.uniform(-6, 10))],
                ORANGE if k % 2 else AMBER, sw=2, glow=True, opacity=0.9)
    b = s.box(16, 16, 0, 68, 68, 36, color='#262B48')
    for i in range(10):
        u = 0.05 + i * 0.093
        s.frect(b, 'left', u, 0.25, u + 0.06, 0.7, DARK)
        s.frect(b, 'left', u + 0.015, 0.3, u + 0.045, 0.4, AMBER, glow=True)
        s.frect(b, 'right', u, 0.25, u + 0.06, 0.7, shade(DARK, -0.3))
    s.frect(b, 'top', 0.1, 0.1, 0.9, 0.9, DARK)
    # prism / mirror array
    t0 = [iso(50, 30, 36), iso(70, 50, 36), iso(50, 70, 36), iso(30, 50, 36)]
    apex = iso(50, 50, 64)
    s.poly2([t0[3], t0[2], apex], shade(AMBER, -0.1), glow=True)
    s.poly2([t0[2], t0[1], apex], shade(AMBER, -0.4), glow=True)
    s.poly2([t0[3], apex, t0[0]], shade(AMBER, 0.3), stroke=OUT, opacity=0.6)
    s.ellipse2(apex[0], apex[1], 3, 3, WHITE, stroke=None, glow=True)
    # front fibres fanning toward the viewer
    for k in range(9):
        a = k * math.pi / 8
        s.line3([(50 + 30 * math.cos(a), 50 + 30 * math.sin(a), 24),
                 (50 + 52 * math.cos(a), 50 + 52 * math.sin(a), 4 + rnd.uniform(0, 6))],
                ORANGE if k % 2 else AMBER, sw=2.4, glow=True)


# ============================================================ overlays
def overlay_heat(out):
    s = Scene()
    extra = ('<radialGradient id="h" cx="0.5" cy="0.55" r="0.55"><stop offset="0" stop-color="#FF3B30" stop-opacity="0.55"/>'
             '<stop offset="0.6" stop-color="#FF6B3D" stop-opacity="0.28"/><stop offset="1" stop-color="#FF6B3D" stop-opacity="0"/></radialGradient>'
             '<filter id="w"><feTurbulence type="fractalNoise" baseFrequency="0.035 0.09" numOctaves="2" seed="3"/>'
             '<feDisplacementMap in="SourceGraphic" scale="14"/></filter>')
    els = ['<rect x="-100" y="-84" width="200" height="200" fill="url(#h)"/>']
    for k, x in enumerate((-40, -12, 16, 44)):
        els.append(f'<path d="M{x},{80 - k % 2 * 10} q12,-22 0,-44 q-12,-22 0,-44 q10,-18 2,-34" fill="none" '
                   f'stroke="#FF8A5C" stroke-width="5" stroke-linecap="round" opacity="0.55" filter="url(#w)"/>')
    s.els = els
    render(svg_wrap(s, extra_defs=extra), out, 256)


def overlay_link(out):
    # horizontal connector segment spanning the full cell width (rotate 90° in code for vertical)
    svg = ('<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256"><defs>'
           '<filter id="g" x="-0.2" y="-2" width="1.4" height="5"><feGaussianBlur stdDeviation="7" result="b"/>'
           '<feMerge><feMergeNode in="b"/><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>'
           '<linearGradient id="l" x1="0" x2="1"><stop offset="0" stop-color="#FFB547"/><stop offset="0.5" stop-color="#FFE3B0"/>'
           '<stop offset="1" stop-color="#FFB547"/></linearGradient></defs>'
           '<rect x="0" y="113" width="256" height="30" rx="6" fill="#080C1A" opacity="0.75"/>'
           '<rect x="0" y="119" width="256" height="18" fill="url(#l)" filter="url(#g)"/>'
           '<rect x="0" y="125" width="256" height="6" fill="#FFFFFF" opacity="0.85"/>'
           + ''.join(f'<circle cx="{x}" cy="128" r="4" fill="#FFFFFF" filter="url(#g)"/>' for x in (64, 128, 192))
           + '</svg>')
    render(svg, out, 256)


# ============================================================ floors (128x128 seamless)
def wrap(fn, S=128):
    """Draw fn(dx, dy) at 9 offsets so shapes crossing an edge wrap around."""
    return ''.join(fn(dx, dy) for dx in (-S, 0, S) for dy in (-S, 0, S))


def seam(c='#000000', op=0.45, hi='#FFFFFF', hop=0.05):
    # half-width seams on every edge -> a full 2px cell line once tiled
    return (f'<rect x="0" y="0" width="128" height="1" fill="{c}" opacity="{op}"/>'
            f'<rect x="0" y="127" width="128" height="1" fill="{c}" opacity="{op}"/>'
            f'<rect x="0" y="0" width="1" height="128" fill="{c}" opacity="{op}"/>'
            f'<rect x="127" y="0" width="1" height="128" fill="{c}" opacity="{op}"/>'
            f'<rect x="1" y="1" width="126" height="1" fill="{hi}" opacity="{hop}"/>'
            f'<rect x="1" y="1" width="1" height="126" fill="{hi}" opacity="{hop}"/>')


def floor_png(name, body, noise=0.06, blur=0.6):
    svg = f'<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">{body}</svg>'
    raw = os.path.join(TMP, f'floor_{name}_raw.png')
    render(svg, raw, 128)
    out = os.path.join(OUT, f'floor_{name}.png')
    # tileable noise: per-pixel noise is seamless; virtual-pixel tile keeps the blur seamless too
    run('magick', raw, '-virtual-pixel', 'tile', '(', '+clone', '-fill', 'gray50', '-colorize', '100',
        '-attenuate', str(noise * 10), '+noise', 'Gaussian', '-colorspace', 'gray', '-blur', f'0x{blur}', ')',
        '-compose', 'softlight', '-composite', '-alpha', 'off', out)
    return out


def floors():
    rnd = random.Random(11)
    # garage: concrete, oil stain, hairline crack
    stain = wrap(lambda dx, dy: f'<path d="M{70+dx},{92+dy} c8,-14 30,-16 40,-6 c9,9 4,22 -10,26 c-10,3 -16,-4 -24,-2 '
                 f'c-8,2 -12,-8 -6,-18 z" fill="#0A0D18" opacity="0.32"/>'
                 f'<ellipse cx="{92+dx}" cy="{98+dy}" rx="9" ry="5" fill="#070912" opacity="0.28"/>'
                 f'<circle cx="{60+dx}" cy="{112+dy}" r="2.2" fill="#0A0D18" opacity="0.3"/>')
    crack = wrap(lambda dx, dy: f'<polyline points="{10+dx},{20+dy} {24+dx},{30+dy} {30+dx},{46+dy} {46+dx},{52+dy}" '
                 f'fill="none" stroke="#0C0F1C" stroke-width="1" opacity="0.7"/>')
    flecks = ''.join(f'<circle cx="{rnd.uniform(0,128):.1f}" cy="{rnd.uniform(0,128):.1f}" r="{rnd.uniform(0.4,1.1):.1f}" '
                     f'fill="#{rnd.choice(["2E3656", "121628"])}" opacity="0.7"/>' for _ in range(70))
    floor_png('garage', f'<rect width="128" height="128" fill="#1C2135"/>{flecks}{stain}{crack}' + seam(op=0.5), noise=0.09)

    # closet: muted 2x2 linoleum check
    body = '<rect width="128" height="128" fill="#1B2034"/>'
    body += '<rect x="0" y="0" width="64" height="64" fill="#1E2339"/><rect x="64" y="64" width="64" height="64" fill="#1E2339"/>'
    body += '<rect x="0" y="63.5" width="128" height="1" fill="#0E1222" opacity="0.6"/><rect x="63.5" y="0" width="1" height="128" fill="#0E1222" opacity="0.6"/>'
    body += ''.join(f'<rect x="{rnd.uniform(0,128):.0f}" y="{rnd.uniform(0,128):.0f}" width="{rnd.uniform(2,6):.0f}" height="1" '
                    f'fill="#2B3352" opacity="0.5"/>' for _ in range(24))
    floor_png('closet', body + seam(op=0.55), noise=0.05)

    # colo: steel diamond mesh over a dark void
    body = '<rect width="128" height="128" fill="#121729"/>'
    for i in range(-8, 17):
        o = i * 16
        body += f'<line x1="{o}" y1="0" x2="{o+128}" y2="128" stroke="#2C3556" stroke-width="2.2"/>'
        body += f'<line x1="{o}" y1="128" x2="{o+128}" y2="0" stroke="#252D4A" stroke-width="2.2"/>'
    for i in range(0, 128, 16):
        for j in range(0, 128, 16):
            body += f'<circle cx="{i}" cy="{j}" r="1.6" fill="#3A4570"/>'
    body += '<rect x="0" y="0" width="128" height="3" fill="#2A3352"/><rect x="0" y="0" width="3" height="128" fill="#2A3352"/>'
    floor_png('colo', body + seam(op=0.6), noise=0.04)

    # hall: raised floor tile with perforated centre
    body = '<rect width="128" height="128" fill="#171C33"/>'
    body += '<rect x="4" y="4" width="120" height="120" rx="3" fill="#1B2139" stroke="#10142A" stroke-width="2"/>'
    for i in range(8):
        for j in range(8):
            body += f'<circle cx="{22 + i*12}" cy="{22 + j*12}" r="2.2" fill="#0D1122" opacity="0.8"/>'
    body += '<rect x="5" y="5" width="118" height="1.5" fill="#FFFFFF" opacity="0.06"/>'
    floor_png('hall', body + seam(op=0.65), noise=0.04)

    # campus: dark steel tread plate
    body = '<rect width="128" height="128" fill="#171B2B"/>'
    for i in range(4):
        for j in range(4):
            cx, cy = 16 + i * 32, 16 + j * 32
            r = 45 if (i + j) % 2 else -45
            body += (f'<rect x="{cx-8}" y="{cy-1.8}" width="16" height="3.6" rx="1.8" fill="#262C44" stroke="#0E1120" '
                     f'stroke-width="0.8" transform="rotate({r} {cx} {cy})"/>')
            cx2, cy2 = cx + 16, cy + 16
            body += wrap(lambda dx, dy, cx2=cx2, cy2=cy2, r=r: (
                f'<rect x="{cx2-8+dx}" y="{cy2-1.8+dy}" width="16" height="3.6" rx="1.8" fill="#262C44" stroke="#0E1120" '
                f'stroke-width="0.8" transform="rotate({-r} {cx2+dx} {cy2+dy})"/>'))
    floor_png('campus', body + seam(op=0.6), noise=0.05)

    # gigasite: near-black epoxy panels, corner bolts, faint hex emboss
    body = '<rect width="128" height="128" fill="#121522"/>'
    hx = ''
    for row in range(-1, 6):
        for col in range(-1, 6):
            cx = col * 32 + (16 if row % 2 else 0)
            cy = row * 27.7128 * (128 / (27.7128 * 4.618))
            pts = ' '.join(f'{cx + 15*math.cos(math.radians(60*k+30)):.1f},{cy + 15*math.sin(math.radians(60*k+30)):.1f}' for k in range(6))
            hx += f'<polygon points="{pts}" fill="none" stroke="#1C2033" stroke-width="1.2"/>'
    body += hx
    for (x, y) in ((8, 8), (120, 8), (8, 120), (120, 120)):
        body += f'<circle cx="{x}" cy="{y}" r="2.6" fill="#2A3049" stroke="#07090F" stroke-width="0.8"/>'
    floor_png('gigasite', body + seam(op=0.7), noise=0.05)
    floor_orbital()


def floor_orbital():
    # orbital station: composite deck panels on a truss grid, node bolts
    # and a faint cyan module-socket ring
    body = '<rect width="128" height="128" fill="#1A2136"/>'
    body += '<rect x="6" y="6" width="116" height="116" rx="4" fill="#20283E" stroke="#121829" stroke-width="2"/>'
    body += '<rect x="22" y="22" width="84" height="84" rx="12" fill="none" stroke="#3DD6FF" stroke-width="1.6" opacity="0.28"/>'
    for i in range(1, 4):
        body += f'<line x1="{i * 32}" y1="10" x2="{i * 32}" y2="118" stroke="#161C30" stroke-width="1"/>'
    for (x, y) in ((6, 6), (122, 6), (6, 122), (122, 122)):
        body += f'<circle cx="{x}" cy="{y}" r="4.2" fill="#56627F" stroke="#07090F" stroke-width="0.8"/>'
    body += '<rect x="7" y="7" width="114" height="1.5" fill="#FFFFFF" opacity="0.07"/>'
    floor_png('orbital', body + seam(op=0.7), noise=0.04)


# ============================================================ room banners (900x300)
BW, BH = 900, 300


def banner_crop(src, out, x, y, w):
    h = w // 3
    run('magick', os.path.join(ROOT, 'assets', 'images', src), '-crop', f'{w}x{h}+{x}+{y}', '+repage', '-resize', f'{BW}x{BH}!',
        '(', '-size', f'{BW}x{BH}', 'radial-gradient:none-#00000070', ')', '-compose', 'over', '-composite',
        '-alpha', 'off', out)


def banner_svg(s, cx, cy, w, out):
    h = w * BH / BW
    vb = (cx - w / 2, cy - h / 2, w, h)
    g = 4.0 * w / 300 * 0.45
    defs = (f'<filter id="g" filterUnits="userSpaceOnUse" x="{vb[0]}" y="{vb[1]}" width="{w}" height="{h}">'
            f'<feGaussianBlur stdDeviation="{g:.2f}" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="b"/>'
            f'<feMergeNode in="SourceGraphic"/></feMerge></filter>'
            f'<radialGradient id="vig" cx="0.5" cy="0.45" r="0.8"><stop offset="0.5" stop-color="#000" stop-opacity="0"/>'
            f'<stop offset="1" stop-color="#000" stop-opacity="0.6"/></radialGradient>'
            f'<linearGradient id="sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#05070F"/>'
            f'<stop offset="1" stop-color="#151C38"/></linearGradient>' + ''.join(s.defs))
    r = f'x="{vb[0]:.1f}" y="{vb[1]:.1f}" width="{w:.1f}" height="{h:.1f}"'
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{BW}" height="{BH}" viewBox="{vb[0]:.1f} {vb[1]:.1f} {w:.1f} {h:.1f}">'
           f'<defs>{defs}</defs><rect {r} fill="url(#sky)"/>' + '\n'.join(s.els) + f'<rect {r} fill="url(#vig)"/></svg>')
    render(svg, out, BW, BH)


def poly3(s, pts, fill, **kw):
    s.poly2([iso(*p) for p in pts], fill, **kw)


def stars(s, cx, cy, w, h, n, seed):
    rnd = random.Random(seed)
    for _ in range(n):
        x, y = cx + rnd.uniform(-w / 2, w / 2), cy + rnd.uniform(-h / 2, -h / 6)
        s.ellipse2(x, y, 1.2, 1.2, WHITE, stroke=None, opacity=rnd.uniform(0.3, 0.9))


def dc_building(s, x, y, w, d, h, seed, roof_fans=True):
    b = s.box(x, y, 0, w, d, h, color='#2A3560')
    rnd = random.Random(seed)
    n = max(3, int(w / 22))
    for i in range(n):
        u = 0.05 + i * 0.9 / n
        s.frect(b, 'left', u, 0.3, u + 0.9 / n * 0.6, 0.7, GREEN if rnd.random() < 0.8 else CYAN, glow=True, opacity=0.85)
    m = max(2, int(d / 22))
    for i in range(m):
        u = 0.05 + i * 0.9 / m
        s.frect(b, 'right', u, 0.35, u + 0.9 / m * 0.6, 0.65, shade(GREEN, -0.3), glow=True, opacity=0.8)
    if roof_fans:
        k = max(2, int(w / 34))
        for i in range(k):
            r = s.box(x + 8 + i * (w - 16) / k, y + d * 0.3, h, (w - 16) / k * 0.7, d * 0.4, 6, color=STEEL, sw=1.2)
            s.frect(r, 'top', 0.3, 0.3, 0.7, 0.7, CYAN, glow=True)
    return b


def tower_hyper(s, x, y, r, h):
    cx, cy = iso(x, y, 0)
    rx0, ry0 = r * C30 * 1.15, r * 0.66
    rx1 = rx0 * 0.7
    ty = cy - h
    d = (f'M{cx-rx0:.1f},{cy:.1f} Q{cx-rx0*0.55:.1f},{cy-h*0.55:.1f} {cx-rx1:.1f},{ty:.1f} L{cx+rx1:.1f},{ty:.1f} '
         f'Q{cx+rx0*0.55:.1f},{cy-h*0.55:.1f} {cx+rx0:.1f},{cy:.1f} A{rx0:.1f},{ry0:.1f} 0 0 1 {cx-rx0:.1f},{cy:.1f} Z')
    s.path2(d, '#5C6E94', [(cx - rx0, ty - ry0), (cx + rx0, cy + ry0)])
    s.ellipse2(cx, ty, rx1, ry0 * 0.7, DARK, sw=1.4)
    for k, (ox, oy, rr) in enumerate(((0, -14, 18), (14, -34, 22), (-6, -58, 26))):
        s.ellipse2(cx + ox, ty + oy, rr * 1.4, rr, '#B9D4EA', stroke=None, opacity=0.35 - k * 0.08)


def pylon(s, x, y, h):
    a, b = iso(x, y, 0), iso(x, y, h)
    s.line2([(a[0] - 10, a[1]), (b[0], b[1]), (a[0] + 10, a[1])], '#4A5680', sw=2.2)
    for f in (0.75, 0.9):
        p = iso(x, y, h * f)
        s.line2([(p[0] - 16, p[1]), (p[0] + 16, p[1])], '#4A5680', sw=2)
    return b


def colo_banner(out):
    s = Scene()
    poly3(s, [(0, 0, 0), (600, 0, 0), (600, 400, 0), (0, 400, 0)], '#161C33', stroke=None)
    poly3(s, [(0, 0, 0), (0, 400, 0), (0, 400, 160), (0, 0, 160)], '#1E2644', stroke=None)
    poly3(s, [(0, 0, 0), (600, 0, 0), (600, 0, 160), (0, 0, 160)], '#1A2140', stroke=None)
    # neighbouring cages (dim) + our cage with racks
    for (cx0, glow) in ((40, False), (200, True), (360, False)):
        for i in range(4):
            b = s.box(cx0 + i * 30, 60, 0, 26, 40, 90, color='#2A3566' if glow else '#222B4E')
            server_face(s, b, 'left', 6, seed=i + cx0, col=GREEN if glow else '#2F7A60', alt=CYAN if glow else '#2F6A80')
        # mesh walls
        x0, x1, y0, y1, H = cx0 - 10, cx0 + 130, 40, 150, 120
        for xx in range(int(x0), int(x1) + 1, 8):
            s.line3([(xx, y1, 0), (xx, y1, H)], '#7F8DB5', sw=0.8, opacity=0.35)
        for zz in range(0, H + 1, 8):
            s.line3([(x0, y1, zz), (x1, y1, zz)], '#7F8DB5', sw=0.8, opacity=0.35)
        s.line3([(x0, y1, 0), (x0, y1, H), (x1, y1, H), (x1, y1, 0)], '#8E9CC4', sw=2)
        s.line3([(x1, y0, H), (x1, y1, H)], '#8E9CC4', sw=2)
        if glow:
            p = iso(cx0 + 60, y1, 105)
            s.ellipse2(p[0], p[1], 4, 4, AMBER, stroke=OUT, glow=True)
    # overhead ladder rack with amber cables
    s.line3([(0, 30, 150), (600, 30, 150)], AMBER, sw=3, glow=True)
    s.line3([(0, 36, 150), (600, 36, 150)], ORANGE, sw=2, glow=True)
    c = iso(230, 100, 105)
    banner_svg(s, c[0] + 10, c[1], 680, out)


def campus_banner(out):
    s = Scene()
    stars(s, *iso(400, 300, 0), 1400, 500, 60, 1)
    poly3(s, [(-200, -200, 0), (900, -200, 0), (900, 800, 0), (-200, 800, 0)], '#141A30', stroke=None)
    # roads
    for y in (150, 330):
        poly3(s, [(-200, y, 0), (900, y, 0), (900, y + 24, 0), (-200, y + 24, 0)], '#1E2440', stroke=None)
        for x in range(-180, 900, 50):
            s.line3([(x, y + 12, 0), (x + 22, y + 12, 0)], AMBER, sw=1.2, opacity=0.6)
    # back row towers + buildings, front row buildings
    for x in (520, 600):
        tower_hyper(s, x, 40, 34, 90)
    for i, x in enumerate((0, 170, 340)):
        dc_building(s, x, 20, 140, 110, 46, seed=i)
    for i, x in enumerate((-40, 130, 300, 470)):
        dc_building(s, x, 190, 140, 120, 50, seed=10 + i)
    # substation
    for k in range(4):
        s.box(640 + k * 26, 220, 0, 18, 18, 22, color=STEEL)
    for x in (650, 720):
        top = pylon(s, x, 360, 110)
    s.line3([(650, 360, 102), (720, 360, 102), (900, 360, 106)], AMBER, sw=1.2, opacity=0.7)
    c = iso(320, 250, 30)
    banner_svg(s, c[0] + 20, c[1] - 95, 1040, out)


def gigasite_banner(out):
    s = Scene()
    stars(s, *iso(500, 400, 0), 1800, 600, 80, 2)
    poly3(s, [(-300, -300, 0), (1200, -300, 0), (1200, 1000, 0), (-300, 1000, 0)], '#10142A', stroke=None)
    # a row of hyperbolic towers behind
    for k, x in enumerate((520, 610, 700, 790, 880, 970)):
        tower_hyper(s, x, -60 - (k % 2) * 70, 38, 130)
    # massive halls
    for j, y in enumerate((-260, -50, 160)):
        for i, x in enumerate((-380, -110, 160, 430)[:4 - (j == 0)]):
            if x > 300 and y < 0:
                continue
            dc_building(s, x, y, 230, 170, 74, seed=20 + i + 5 * j)
    # substation + transmission lines + power plant glow
    for k in range(6):
        b = s.box(680 + (k % 3) * 34, 160 + (k // 3) * 40, 0, 22, 22, 30, color=STEEL)
        s.frect(b, 'top', 0.3, 0.3, 0.7, 0.7, AMBER, glow=True)
    tops = [pylon(s, x, 420, 150) for x in (700, 820, 940)]
    s.line2([(t[0], t[1] + 10) for t in tops], AMBER, sw=1.4, opacity=0.8, glow=True)
    c = iso(400, 260, 30)
    s.aura(*iso(780, -60, 60), 220, AMBER, 0.12)
    banner_svg(s, c[0] + 40, c[1] - 260, 2000, out)


def orbital_banner(out):
    s = Scene()
    rnd = random.Random(7)
    c = iso(300, 300, 60)
    cx, cy = c[0] + 60, c[1] - 30
    w = 1900
    h = w / 3
    for _ in range(160):
        s.ellipse2(cx + rnd.uniform(-w / 2, w / 2), cy + rnd.uniform(-h / 2, h / 2), 1.3, 1.3, WHITE,
                   stroke=None, opacity=rnd.uniform(0.3, 0.95))
    # Earth's limb along the bottom, with its blue atmosphere
    er = 2600
    ex, ey = cx + 300, cy + h / 2 + er - 150
    s.ellipse2(ex, ey, er + 26, er + 26, '#4AA8FF', stroke=None, opacity=0.35, glow=True)
    s.ellipse2(ex, ey, er, er, '#1A4E9E', stroke=None)
    for _ in range(70):
        a = rnd.uniform(math.radians(235), math.radians(305))
        d = rnd.uniform(er * 0.97, er * 0.998)
        s.ellipse2(ex + d * math.cos(a), ey + d * math.sin(a), rnd.uniform(14, 40), 2.4, '#F2F7FF',
                   stroke=None, opacity=rnd.uniform(0.2, 0.55))
    s.aura(cx - 700, cy - 200, 160, '#FFF4D6', 0.8)
    # the station: a deck with modules, solar wings, radiators
    poly3(s, [(0, 0, 0), (600, 0, 0), (600, 600, 0), (0, 600, 0)], '#20283E', stroke=OUT)
    poly3(s, [(0, 600, 0), (600, 600, 0), (600, 600, -24), (0, 600, -24)], '#1A2034', stroke=OUT)
    poly3(s, [(600, 0, 0), (600, 600, 0), (600, 600, -24), (600, 0, -24)], '#121729', stroke=OUT)
    for y in (-20, ):
        for x0, x1 in ((20, 280), (320, 580)):
            poly3(s, [(x0, y, 60), (x1, y, 60), (x1, y, 230), (x0, y, 230)], '#162A5C', stroke='#C9A24A')
            for k in range(1, 9):
                xx = x0 + k * (x1 - x0) / 9
                s.line3([(xx, y, 60), (xx, y, 230)], '#3E6CC4', sw=1)
    for x in (-20, ):
        for y0, y1 in ((20, 280), (320, 580)):
            poly3(s, [(x, y0, 60), (x, y1, 60), (x, y1, 230), (x, y0, 230)], '#162A5C', stroke='#C9A24A')
            for k in range(1, 9):
                yy = y0 + k * (y1 - y0) / 9
                s.line3([(x, yy, 60), (x, yy, 230)], '#3E6CC4', sw=1)
    for k in range(3):
        a0 = 40 + k * 190
        poly3(s, [(a0, 640, -16), (a0 + 150, 640, -16), (a0 + 150, 780, -16), (a0, 780, -16)], '#DCE4EF')
        poly3(s, [(640, a0, -16), (780, a0, -16), (780, a0 + 150, -16), (640, a0 + 150, -16)], '#DCE4EF')
    for i in range(4):
        for j in range(4):
            b = s.box(60 + i * 130, 60 + j * 130, 0, 90, 90, 40, color='#B88A2E', top='#E7C46A', right='#8E6A22')
            s.frect(b, 'left', 0.0, 0.45, 1.0, 0.62, CYAN, glow=True)
            s.frect(b, 'right', 0.0, 0.45, 1.0, 0.62, shade(CYAN, -0.1), glow=True)
            s.box(66 + i * 130, 66 + j * 130, 40, 78, 78, 3, color='#DCE4EF', top='#FFFFFF', sw=0.8)
    banner_svg(s, cx, cy, w, out)


def banners():
    banner_crop('bg_garage.png', os.path.join(OUT, 'room_garage.png'), 0, 230, 1536)
    banner_crop('bg_startup.png', os.path.join(OUT, 'room_closet.png'), 60, 40, 1200)
    colo_banner(os.path.join(OUT, 'room_colo.png'))
    banner_crop('bg_lab.png', os.path.join(OUT, 'room_hall.png'), 0, 180, 1536)
    campus_banner(os.path.join(OUT, 'room_campus.png'))
    gigasite_banner(os.path.join(OUT, 'room_gigasite.png'))
    orbital_banner(os.path.join(OUT, 'room_orbital.png'))


# ============================================================ main
def compress(paths):
    pq = shutil.which('pngquant')
    for p in paths:
        if pq:
            subprocess.run([pq, '--force', '--skip-if-larger', '--quality=70-95', '--ext', '.png', p])
        elif os.path.basename(p).startswith('room_'):
            # opaque banners: palette PNG like the existing bg_* images
            run('magick', p, '-strip', '-dither', 'FloydSteinberg', '-colors', '256', '-define', 'png:compression-level=9', 'PNG8:' + p)
        else:
            run('magick', p, '-strip', '-define', 'png:compression-level=9', p)


def main():
    os.makedirs(OUT, exist_ok=True)
    made = []
    only = set(os.environ.get('ONLY', '').split(',')) - {''}
    for name, (fn, kind) in TILES.items():
        if only and name not in only:
            continue
        s = Scene(glow=3.0)
        base(s, kind)
        fn(s)
        out = os.path.join(OUT, f'tile_{name}.png')
        render(svg_wrap(s), out, 256)
        made.append(out)
    # ONLY=floor_<room> / room_<room> regenerates one floor or banner.
    if 'floor_orbital' in only:
        made.append(floor_orbital() or os.path.join(OUT, 'floor_orbital.png'))
    if 'room_orbital' in only:
        orbital_banner(os.path.join(OUT, 'room_orbital.png'))
        made.append(os.path.join(OUT, 'room_orbital.png'))
    if not only:
        overlay_heat(os.path.join(OUT, 'tile_overlay_heat.png'))
        overlay_link(os.path.join(OUT, 'tile_overlay_link.png'))
        made += [os.path.join(OUT, 'tile_overlay_heat.png'), os.path.join(OUT, 'tile_overlay_link.png')]
        floors()
        banners()
        made += [os.path.join(OUT, f) for f in os.listdir(OUT) if f.startswith(('floor_', 'room_'))]
    compress(made)
    print(f'{len(made)} files -> {OUT}')


if __name__ == '__main__':
    main()
