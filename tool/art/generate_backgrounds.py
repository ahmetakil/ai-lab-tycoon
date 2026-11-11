#!/usr/bin/env python3
"""Era backgrounds for AI Lab Tycoon (bg_<era>.png, 1536x1024).

Same pipeline and palette as generate_tiles.py: Python writes isometric SVG
(iso.py), rsvg-convert rasterizes, ImageMagick quantizes. The Garage and
Startup backgrounds are hand-made; the Medium lab uses the old Lab hall
(bg_mediumLab.png). This script draws the other three:

    bg_smallLab.png   a colocation cage: fenced racks on a raised floor
    bg_bigLab.png     a datacenter campus: halls, roof chillers, a substation
    bg_globalLab.png  a gigawatt site: a grid of buildings, cooling towers,
                      a power plant and transmission lines

Usage (from repo root):
    python3 tool/art/generate_backgrounds.py [out_dir]   # default: assets/images
Needs: rsvg-convert, magick (ImageMagick 7).
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
TMP = tempfile.mkdtemp(prefix='bg_')
W, H = 1536, 1024
VIOLET = '#B07CFF'
PINK = '#FF6FD8'


def run(*a):
    subprocess.run(a, check=True)


def render(s, name, sky, accent, view, stars=False, seed=1):
    """view = (cx, cy, width) of the iso-space window to show (3:2)."""
    cx, cy, vw = view
    vh = vw * H / W
    x0, y0 = cx - vw / 2, cy - vh / 2
    g = s.glow * vw / 300
    defs = (f'<filter id="g" filterUnits="userSpaceOnUse" x="{x0:.1f}" y="{y0:.1f}" width="{vw:.1f}" height="{vh:.1f}">'
            f'<feGaussianBlur stdDeviation="{g:.2f}" result="b"/>'
            f'<feMerge><feMergeNode in="b"/><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>'
            f'<linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">'
            f'<stop offset="0" stop-color="{sky[0]}"/><stop offset="1" stop-color="{sky[1]}"/></linearGradient>'
            f'<radialGradient id="vig" cx="0.5" cy="0.45" r="0.75">'
            f'<stop offset="0.55" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity="0.7"/></radialGradient>'
            f'<radialGradient id="acc" cx="0.62" cy="0.2" r="0.6">'
            f'<stop offset="0" stop-color="{accent}" stop-opacity="0.22"/><stop offset="1" stop-color="{accent}" stop-opacity="0"/></radialGradient>'
            + ''.join(s.defs))
    bg = f'<rect x="{x0:.1f}" y="{y0:.1f}" width="{vw:.1f}" height="{vh:.1f}" fill="url(#sky)"/>'
    bg += f'<rect x="{x0:.1f}" y="{y0:.1f}" width="{vw:.1f}" height="{vh:.1f}" fill="url(#acc)"/>'
    if stars:
        rnd = random.Random(seed)
        for _ in range(70):
            sx, sy = x0 + rnd.random() * vw, y0 + rnd.random() * vh * 0.32
            r = vw / 1536 * (0.8 + rnd.random() * 1.6)
            bg += f'<circle cx="{sx:.1f}" cy="{sy:.1f}" r="{r:.2f}" fill="#EAF2FF" opacity="{0.25 + rnd.random() * 0.5:.2f}"/>'
    vig = f'<rect x="{x0:.1f}" y="{y0:.1f}" width="{vw:.1f}" height="{vh:.1f}" fill="url(#vig)"/>'
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" '
           f'viewBox="{x0:.1f} {y0:.1f} {vw:.1f} {vh:.1f}"><defs>{defs}</defs>{bg}'
           + '\n'.join(s.els) + vig + '</svg>')
    p = os.path.join(TMP, name + '.svg')
    open(p, 'w').write(svg)
    png = os.path.join(TMP, name + '.png')
    run('rsvg-convert', '-w', str(W), '-h', str(H), p, '-o', png)
    out = os.path.join(OUT, name + '.png')
    # Match the other backgrounds: 8-bit colormap PNG, light dithering.
    run('magick', png, '-dither', 'FloydSteinberg', '-colors', '256', 'PNG8:' + out)
    print('wrote', out)


# ------------------------------------------------------------------ pieces
def floor(s, x0, y0, x1, y1, color, grid=None, step=10, gsw=0.8, gop=0.35):
    s.poly2([iso(x0, y0, 0), iso(x1, y0, 0), iso(x1, y1, 0), iso(x0, y1, 0)], color, sw=2)
    if grid:
        x = x0 + step
        while x < x1:
            s.line3([(x, y0, 0), (x, y1, 0)], grid, sw=gsw, opacity=gop)
            x += step
        y = y0 + step
        while y < y1:
            s.line3([(x0, y, 0), (x1, y, 0)], grid, sw=gsw, opacity=gop)
            y += step


def rack(s, x, y, w=8, d=10, h=34, color=NAVY, seed=0, leds=(GREEN, CYAN), rows=9, face='left'):
    rnd = random.Random(seed)
    b = s.box(x, y, 0, w, d, h, color=color, sw=1.4)
    # Door frame and LED rows on the face toward the camera.
    s.frect(b, face, 0.08, 0.05, 0.92, 0.95, shade(color, -0.45), stroke=OUT, sw=0.8)
    for i in range(rows):
        v = 0.1 + i * 0.8 / rows
        n = rnd.randint(1, 3)
        for k in range(n):
            u = 0.16 + k * 0.22
            c = leds[rnd.randint(0, len(leds) - 1)]
            s.frect(b, face, u, v, u + rnd.choice((0.08, 0.14, 0.2)), v + 0.025, c, glow=True)
    return b


def fence(s, x0, y0, x1, y1, h, color=SILVER, step=2.0, op=0.35):
    """Chain-link cage walls along the back (y=y0) and left (x=x0) sides,
    plus a low front rail, drawn as thin lines."""
    for (ax, ay, bx, by) in ((x0, y0, x1, y0), (x0, y0, x0, y1)):
        L = math.hypot(bx - ax, by - ay)
        n = int(L / step)
        for i in range(n + 1):
            t = i / n
            px, py = ax + (bx - ax) * t, ay + (by - ay) * t
            s.line3([(px, py, 0), (px, py, h)], color, sw=0.6, opacity=op)
        for z in (0, h * 0.5, h):
            s.line3([(ax, ay, z), (bx, by, z)], color, sw=1.6 if z in (0, h) else 0.8, opacity=0.7)
    # diagonal mesh hint on the back wall
    k = 0.0
    while k < (x1 - x0):
        s.line3([(x0 + k, y0, 0), (min(x1, x0 + k + h), y0, min(h, x1 - x0 - k))], color, sw=0.4, opacity=op * 0.6)
        k += step * 2


def tray(s, pts, color=CYAN, z=40):
    s.line3([(x, y, z) for x, y in pts], shade(color, -0.4), sw=6, opacity=0.8)
    s.line3([(x, y, z) for x, y in pts], color, sw=1.8, glow=True)


def hall(s, x, y, w, d, h, color=NAVY, seed=0, win=CYAN, roof_units=6):
    rnd = random.Random(seed)
    b = s.box(x, y, 0, w, d, h, color=color, top=shade(color, -0.25), sw=1.8)
    # roof membrane seams and a lit parapet edge
    for k in range(1, 6):
        s.fline(b, 'top', [(k / 6, 0.04), (k / 6, 0.96)], shade(color, -0.45), sw=1)
    s.fline(b, 'top', [(0, 1), (1, 1), (1, 0)], shade(win, -0.35), sw=1.2, opacity=0.8)
    # window strips (glowing server-hall slits)
    for face, n in (('left', max(3, int(w / 10))), ('right', max(2, int(d / 10)))):
        for i in range(n):
            u = (i + 0.3) / n
            s.frect(b, face, u, 0.35, u + 0.35 / n, 0.55, win if rnd.random() > 0.25 else GREEN, glow=True, opacity=0.85)
    # roof chillers with fans
    cols = 3 if roof_units >= 3 else roof_units
    rows_ = max(1, math.ceil(roof_units / cols))
    for i in range(roof_units):
        ux = x + 4 + (w - 10) * ((i % cols) / max(1, cols - 1))
        uy = y + 4 + (d - 9) * ((i // cols) / max(1, rows_ - 1))
        u = s.box(ux, uy, h, 6, 5, 2.4, color=STEEL, sw=1.0)
        s.fcircle(u, 'top', 0.5, 0.5, 0.33, 0.33, shade(CYAN, -0.5), stroke=OUT, sw=0.6)
        cx, cy = iso(ux + 3, uy + 2.5, h + 2.4)
        s.aura(cx, cy, 6, CYAN, 0.35)
    return b


def transformer(s, x, y, color=STEEL):
    b = s.box(x, y, 0, 4, 4, 5, color=color, sw=1.0)
    for i in range(3):
        s.cyl(x + 0.8 + i * 1.2, y + 2, 5, 0.35, 2.2, color=SILVER, sw=0.6)
    return b


def pylon(s, x, y, h=26, color=SILVER):
    base = [(x - 2, y - 2), (x + 2, y - 2), (x + 2, y + 2), (x - 2, y + 2)]
    for bx, by in base:
        s.line3([(bx, by, 0), (x, y, h)], color, sw=1.2, opacity=0.9)
    for z in (h * 0.55, h * 0.82):
        s.line3([(x - 5, y, z), (x + 5, y, z)], color, sw=1.4)
    return [(x - 5, y, h * 0.82), (x + 5, y, h * 0.82), (x - 5, y, h * 0.55), (x + 5, y, h * 0.55)]


def cooling_tower(s, x, y, r=7, h=30, color='#3A4670'):
    """Hyperboloid-ish tower: a cylinder with a pinched outline and steam."""
    cx, cy = iso(x, y, 0)
    rx, ry = r * C30 * 1.15, r * 0.66
    ty = cy - h * 1.6
    pinch = 0.5
    d = (f'M{cx - rx:.1f},{cy:.1f} Q{cx - rx * pinch:.1f},{(cy + ty) / 2:.1f} {cx - rx * 0.82:.1f},{ty:.1f} '
         f'L{cx + rx * 0.82:.1f},{ty:.1f} Q{cx + rx * pinch:.1f},{(cy + ty) / 2:.1f} {cx + rx:.1f},{cy:.1f} '
         f'A{rx:.1f},{ry:.1f} 0 0 1 {cx - rx:.1f},{cy:.1f} Z')
    s.path2(d, color, [(cx - rx, ty - ry), (cx + rx, cy + ry)], sw=1.6)
    s.ellipse2(cx, ty, rx * 0.82, ry * 0.82, shade(color, -0.5), sw=1.4)
    s.ellipse2(cx, ty, rx * 0.7, ry * 0.6, shade(AMBER, -0.55), stroke=None, opacity=0.8)
    # steam plume
    for k in range(5):
        s.aura(cx + k * rx * 0.25, ty - ry - k * rx * 0.55, rx * (0.9 + 0.35 * k), WHITE, 0.16 - 0.025 * k)


# ------------------------------------------------------------------ scenes
def small_lab():
    """Colocation cage: two rows of racks behind a fence on a raised floor."""
    s = Scene(glow=3.0)
    # back walls of the host datacenter
    s.poly2([iso(-20, -20, 0), iso(150, -20, 0), iso(150, -20, 70), iso(-20, -20, 70)], '#141B3A', sw=2)
    s.poly2([iso(-20, -20, 0), iso(-20, 130, 0), iso(-20, 130, 70), iso(-20, -20, 70)], '#1A2248', sw=2)
    floor(s, -20, -20, 150, 130, '#121A36', grid='#3DD6FF', step=8, gop=0.18)
    # perforated cold-aisle tiles
    for i in range(10):
        b = (8 + i * 8, 44, 0, 8, 8, 0.01)
        s.frect(b, 'top', 0.1, 0.1, 0.9, 0.9, shade(CYAN, -0.55), opacity=0.7)
        for k in range(3):
            s.frect(b, 'top', 0.2 + k * 0.25, 0.3, 0.3 + k * 0.25, 0.7, CYAN, glow=True, opacity=0.35)
    # neighbouring customer's cage in the back (dim)
    for i in range(6):
        rack(s, 100 + i * 8.5, -12, color='#232C55', seed=40 + i, leds=(shade(GREEN, -0.4), shade(CYAN, -0.4)), rows=6)
    # our cage
    fence(s, 2, 12, 96, 100, 40)
    # CRAC unit at the back of the cage
    crac = s.box(4, 14, 0, 14, 8, 30, color=STEEL, sw=1.4)
    s.frect(crac, 'left', 0.1, 0.12, 0.9, 0.5, shade(STEEL, -0.4), stroke=OUT, sw=0.8)
    for k in range(4):
        s.fline(crac, 'left', [(0.15, 0.18 + k * 0.08), (0.85, 0.18 + k * 0.08)], SILVER, sw=1)
    s.frect(crac, 'left', 0.62, 0.62, 0.86, 0.72, AMBER, glow=True)
    # two rows of racks facing the cold aisle
    for i in range(10):
        rack(s, 8 + i * 8.6, 22, seed=i, leds=(GREEN, CYAN, GREEN))
    for i in range(10):
        rack(s, 8 + i * 8.6, 56, seed=20 + i, leds=(GREEN, CYAN, AMBER))
    # overhead cable trays (fiber in yellow, power in cyan)
    tray(s, [(6, 28), (96, 28)], CYAN, z=44)
    tray(s, [(6, 62), (96, 62)], CYAN, z=44)
    tray(s, [(50, 28), (50, 62)], AMBER, z=46)
    render(s, 'bg_smallLab', ('#0B1230', '#05070F'), GREEN, view=(20, 40, 210))


def big_lab():
    """Datacenter campus seen from above: halls, roof chillers, a substation."""
    s = Scene(glow=3.0)
    floor(s, -60, -60, 260, 220, '#0D1426', grid='#2A3A5A', step=20, gop=0.25)
    # roads
    for y in (50, 120):
        s.poly2([iso(-60, y, 0), iso(260, y, 0), iso(260, y + 8, 0), iso(-60, y + 8, 0)], '#1C2640', sw=0)
        s.line3([(-60, y + 4, 0.1), (260, y + 4, 0.1)], AMBER, sw=1, opacity=0.5, dash='6 8')
    s.poly2([iso(100, -60, 0), iso(108, -60, 0), iso(108, 220, 0), iso(100, 220, 0)], '#1C2640', sw=0)
    # substation (behind, left)
    for i in range(3):
        for j in range(2):
            transformer(s, -30 + i * 9, -40 + j * 9)
    s.line3([(-40, -46, 0), (-40, -46, 12)], SILVER, sw=1)
    # halls, back to front
    halls = [(0, -30, 90, 70, 18, 1), (120, -30, 90, 70, 18, 2), (0, 64, 90, 48, 16, 3),
             (120, 64, 90, 48, 16, 4), (0, 135, 90, 60, 18, 5), (120, 135, 90, 60, 18, 6)]
    for (x, y, w, d, h, seed) in sorted(halls, key=lambda t: t[0] + t[1]):
        hall(s, x, y, w, d, h, color='#2B3766', seed=seed, win=VIOLET if seed % 2 else CYAN, roof_units=9)
    # power lines from the substation to the halls
    for tx in (20, 140):
        s.line3([(-25, -36, 10), (tx, -30, 18)], CYAN, sw=1.2, glow=True, opacity=0.8)
    # parked cars / lights
    rnd = random.Random(3)
    for k in range(30):
        x, y = rnd.uniform(-50, 250), rnd.choice((52, 122)) + rnd.uniform(0, 4)
        cx, cy = iso(x, y, 0.5)
        s.aura(cx, cy, 4, AMBER if k % 3 else RED, 0.5)
    render(s, 'bg_bigLab', ('#0D0820', '#05070F'), VIOLET, view=(-10, 55, 360))


def global_lab():
    """Gigawatt site: a grid of buildings, cooling towers and a power plant
    feeding them through transmission lines."""
    s = Scene(glow=3.0)
    floor(s, -260, -260, 360, 360, '#0C1222', grid='#2A3A5A', step=40, gop=0.18)
    # power plant + cooling towers at the back
    for (x, y) in ((-150, -110), (-115, -140), (-80, -170)):
        cooling_tower(s, x, y, r=13, h=34)
    plant = s.box(-160, -60, 0, 44, 34, 20, color='#2E3560', sw=1.6)
    s.frect(plant, 'left', 0.1, 0.4, 0.9, 0.55, AMBER, glow=True, opacity=0.8)
    s.frect(plant, 'right', 0.1, 0.4, 0.9, 0.55, AMBER, glow=True, opacity=0.6)
    s.cyl(-140, -50, 20, 3, 34, color=STEEL)
    # transmission line from the plant to the site
    towers = [(-110, -30), (-75, -10), (-40, 10)]
    prev = None
    for (x, y) in towers:
        arms = pylon(s, x, y, h=30)
        if prev:
            for a, b in zip(prev, arms):
                s.line3([a, b], PINK, sw=1.2, glow=True, opacity=0.85)
        prev = arms
    # grid of buildings (each gigasite tile in the game is one of these)
    bl = []
    for i in range(7):
        for j in range(6):
            bl.append((-20 + i * 30, -90 + j * 30, 24, 24, 11 + ((i * 7 + j * 3) % 4) * 2, i * 10 + j))
    for (x, y, w, d, h, seed) in sorted(bl, key=lambda t: t[0] + t[1]):
        hall(s, x, y, w, d, h, color='#2A3462', seed=seed, win=PINK if (seed % 3 == 0) else CYAN, roof_units=3)
    # site substations along the front edge
    for k in range(5):
        transformer(s, -32, -86 + k * 34)
    cx, cy = iso(80, -10, 0)
    s.aura(cx, cy, 180, PINK, 0.10)
    render(s, 'bg_globalLab', ('#140620', '#05070F'), PINK, view=(-30, -78, 450), stars=True)


if __name__ == '__main__':
    for tool in ('rsvg-convert', 'magick'):
        if not shutil.which(tool):
            sys.exit(f'missing {tool}')
    small_lab()
    big_lab()
    global_lab()
    shutil.rmtree(TMP, ignore_errors=True)
