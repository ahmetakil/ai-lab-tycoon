#!/usr/bin/env python3
"""Systems art for AI Lab Tycoon: network cable runs, network/cooling tier
icons, central cooling plants, the moving-day props and the era-move banner.

Same pipeline and palette as generate_tiles.py: Python writes isometric SVG
(iso.py), rsvg-convert rasterizes, ImageMagick compresses.

Geometry contract (same as tile_*.png):
  * 256px tiles use viewBox (-100,-84,200,200); the cell footprint is x,y in
    [0,100] and iso() maps it to the diamond x:[-86.6,86.6], y:[0,100].
  * 512px plants / truck use viewBox (-200,-168,400,400): a 2x2-cell
    footprint [0,200]^2 at the same pixels-per-unit as the tiles.

Cable tiles (cable_<tier>_x / _y / _tray) run along the cell centre line
(y=50 for _x, x=50 for _y) and are clipped exactly at the cell boundary
planes, so tiles placed on neighbouring cells join seamlessly. The tray runs
along the x axis (mirror horizontally for the y axis).

The truck faces +x, the direction of the garage driveway in world_garage
(generate_rooms.py draws it along x); move_truck_flip is its mirror image.

Usage (from repo root):
    python3 tool/art/generate_systems.py [out_dir]   # default: assets/images
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
OUTDIR = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.join(ROOT, 'assets', 'images')
TMP = tempfile.mkdtemp(prefix='systems_')

ORANGE = '#FF8A3D'
YELLOW = '#FFD447'
VIOLET = '#B07CFF'
PINK = '#FF6FD8'
BLUE = '#3D8BFF'
COOL = '#3E6E95'
COOLD = '#2A4D70'
CARD = '#9C7445'
FONT = 'Helvetica, Arial, sans-serif'

VB1 = (-100.0, -84.0, 200.0, 200.0)
VB2 = (-200.0, -168.0, 400.0, 400.0)

TIERS = ['copper1g', 'copper10g', 'fiber100g', 'ib400g', 'ibspine', 'nvlink', 'optical']
TIER_ACCENT = {'copper1g': ORANGE, 'copper10g': YELLOW, 'fiber100g': CYAN, 'ib400g': GREEN,
               'ibspine': GREEN, 'nvlink': '#B8FFD9', 'optical': VIOLET}


def run(*a):
    subprocess.run(a, check=True)


def wrap_svg(s, vb, size, extra_defs='', w=None, h=None, bg=''):
    g = s.glow * vb[2] / 300
    defs = (f'<filter id="g" filterUnits="userSpaceOnUse" x="{vb[0]}" y="{vb[1]}" width="{vb[2]}" height="{vb[3]}">'
            f'<feGaussianBlur stdDeviation="{g:.2f}" result="b"/>'
            f'<feMerge><feMergeNode in="b"/><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>'
            + ''.join(s.defs) + extra_defs)
    W, H = w or size, h or size
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" '
            f'viewBox="{vb[0]} {vb[1]} {vb[2]} {vb[3]}"><defs>{defs}</defs>{bg}' + '\n'.join(s.els) + '</svg>')


def render(svg, name, w, h=None):
    p = os.path.join(TMP, name + '.svg')
    open(p, 'w').write(svg)
    out = os.path.join(OUTDIR, name + '.png')
    run('rsvg-convert', '-w', str(w), '-h', str(h or w), p, '-o', out)
    return out


def icon(s, name, size=256, pad=0.08):
    p = os.path.join(TMP, name + '.svg')
    open(p, 'w').write(s.svg(pad=pad, size=size))
    out = os.path.join(OUTDIR, name + '.png')
    run('rsvg-convert', '-w', str(size), '-h', str(size), p, '-o', out)
    return out


# ------------------------------------------------------------------ shared helpers
def ground(s, cx, cy, r, color, x0, y0, x1, y1, op=0.30):
    p = iso(cx, cy, 0)
    s.aura(p[0], p[1], r, color, op)
    s.poly2([iso(x0, y0, 0), iso(x1 + 4, y0, 0), iso(x1 + 4, y1 + 4, 0), iso(x0, y1 + 4, 0)], '#000000',
            stroke=None, opacity=0.38)


def pipe3(s, pts, color, sw=6, glow=False):
    s.line3(pts, OUT, sw=sw + 3)
    s.line3(pts, color, sw=sw, glow=glow)
    s.line3(pts, shade(color, 0.55), sw=max(1.2, sw * 0.25), opacity=0.8)


def fan_top(s, b, cu, cv, r, blade=STEEL, hub=CYAN, ring=DARK, n=5):
    w, d = b[3], b[4]
    ru, rv = r / w, r / d
    s.fcircle(b, 'top', cu, cv, ru * 1.12, rv * 1.12, shade(ring, 0.25), sw=1.2)
    s.fcircle(b, 'top', cu, cv, ru, rv, ring, sw=1.4)
    for k in range(n):
        t = k * 2 * math.pi / n
        s.fpoly(b, 'top', [(cu + .18 * ru * math.cos(t), cv + .18 * rv * math.sin(t)),
                           (cu + .9 * ru * math.cos(t + .35), cv + .9 * rv * math.sin(t + .35)),
                           (cu + .9 * ru * math.cos(t + .9), cv + .9 * rv * math.sin(t + .9))], blade, stroke=OUT, sw=0.6)
    s.fcircle(b, 'top', cu, cv, ru * .26, rv * .26, hub, stroke=None, glow=True)


def face_matrix(b, face):
    """Flat drawing (U right along the face, V down from the face top, world units) -> face plane."""
    x, y, z, w, d, h = b
    if face == 'left':
        Y = y + d
        return f'matrix({C30:.5f} 0.5 0 1 {(x - Y) * C30:.2f} {(x + Y) / 2 - z - h:.2f})'
    X = x + w
    return f'matrix({C30:.5f} -0.5 0 1 {(X - y - d) * C30:.2f} {(X + y + d) / 2 - z - h:.2f})'


def face_text(s, b, face, u, v, txt, size, fill, weight='bold', anchor='middle', extra=''):
    s.add(f'<g transform="{face_matrix(b, face)}"><text x="{u:.1f}" y="{v:.1f}" font-family="{FONT}" '
          f'font-size="{size}" font-weight="{weight}" fill="{fill}" text-anchor="{anchor}" {extra}>{txt}</text></g>')


def puff(s, x, y, r, op=0.7):
    s.ellipse2(x, y, r * 1.3, r, '#DDF6FF', stroke=None, opacity=op, glow=True)


# ============================================================ 1. cable runs
def axis_pt(axis, t, off, z):
    return (t, 50 + off, z) if axis == 'x' else (50 + off, t, z)


def band(s, axis, z, cid):
    # E: ~1px overlap into the next cell (+x / +y). Cells drawn back to front then cover the
    # anti-aliased clip edge with opaque content instead of leaving a hairline seam.
    E = 0.7
    if axis == 'x':
        pts = [iso(0, -3000, z), iso(0, 3000, z), iso(100 + E, 3000, z), iso(100 + E, -3000, z)]
    else:
        pts = [iso(-3000, 0, z), iso(3000, 0, z), iso(3000, 100 + E, z), iso(-3000, 100 + E, z)]
    s.defs.append(f'<clipPath id="{cid}" clipPathUnits="userSpaceOnUse"><polygon points="{fmt(pts)}"/></clipPath>')
    s.add(f'<g clip-path="url(#{cid})">')


def run_pts(axis, off, z, amp=0.0, k=1, ph=0.0, t0=-40, t1=140, step=4):
    pts = []
    t = t0
    while t <= t1 + 1e-6:
        o = off + amp * math.sin(2 * math.pi * k * t / 100 + ph)
        pts.append(axis_pt(axis, t, o, z))
        t += step
    return pts


def cable(s, pts, color, sw, hi=None, glow=False, outline=OUT, op=1.0):
    s.line3(pts, outline, sw=sw + 2.6, opacity=op)
    s.line3(pts, color, sw=sw, glow=glow, opacity=op)
    s.line3(pts, hi or shade(color, 0.5), sw=max(0.8, sw * 0.28), opacity=0.85 * op)


def fiber(s, pts, color, sw=2.4, core=WHITE):
    s.line3(pts, OUT, sw=sw + 3.0)
    s.line3(pts, color, sw=sw + 1.2, glow=True)
    s.line3(pts, core, sw=max(0.7, sw * 0.4), opacity=0.9)


def pulses(s, axis, off, z, color, period=50, r=2.4, t0=12):
    for t in range(t0 - 200, 300, period):
        p = iso(*axis_pt(axis, t, off, z))
        s.ellipse2(p[0], p[1], r, r, color, stroke=None, glow=True)


def collars(s, axis, off, z, sw, color, period=50, t0=25, length=6):
    for t in range(t0 - 200, 300, period):
        a, b = axis_pt(axis, t - length / 2, off, z), axis_pt(axis, t + length / 2, off, z)
        s.line2([iso(*a), iso(*b)], OUT, sw=sw + 4.2, cap='butt')
        s.line2([iso(*a), iso(*b)], color, sw=sw + 1.6, cap='butt', glow=True)


def floor_shadow(s, axis, half, z=0.3, op=0.35):
    pts = [iso(*axis_pt(axis, -60, -half, z)), iso(*axis_pt(axis, 160, -half, z)),
           iso(*axis_pt(axis, 160, half, z)), iso(*axis_pt(axis, -60, half, z))]
    s.poly2(pts, '#000000', stroke=None, opacity=op)


def trough(s, axis, half, h, color, rim=None):
    """Low open floor channel: back wall, bottom, (cables go here), then front wall via trough_front."""
    bot = [iso(*axis_pt(axis, -60, -half, 0.5)), iso(*axis_pt(axis, 160, -half, 0.5)),
           iso(*axis_pt(axis, 160, half, 0.5)), iso(*axis_pt(axis, -60, half, 0.5))]
    s.poly2(bot, shade(color, -0.45), stroke=OUT, sw=1.2)
    back = [iso(*axis_pt(axis, -60, -half, 0.5)), iso(*axis_pt(axis, 160, -half, 0.5)),
            iso(*axis_pt(axis, 160, -half, h)), iso(*axis_pt(axis, -60, -half, h))]
    s.poly2(back, shade(color, -0.2), stroke=OUT, sw=1.2)


def trough_front(s, axis, half, h, color, rim=None):
    wall_t = 3
    if axis == 'x':
        b = (-60, 50 + half - wall_t, 0, 220, wall_t, h)
    else:
        b = (50 + half - wall_t, -60, 0, wall_t, 220, h)
    s.box(*b, color=color, sw=1.2)
    if rim:
        if axis == 'x':
            s.line3([(-60, 50 + half, h), (160, 50 + half, h)], rim, sw=1.6, glow=True)
        else:
            s.line3([(50 + half, -60, h), (50 + half, 160, h)], rim, sw=1.6, glow=True)


def rail(s, axis, off, z, h, color, thick=3):
    if axis == 'x':
        return s.box(-60, 50 + off - thick / 2, z, 220, thick, h, color=color, sw=1.2)
    return s.box(50 + off - thick / 2, -60, z, thick, 220, h, color=color, sw=1.2)


TRAY_Z = 70


def tray(s, spec, axis='x'):
    """Overhead tray along `axis` at TRAY_Z with one trapeze hanger per cell (period 100)."""
    z = TRAY_Z
    half = spec['half']
    rc = spec['rail']
    rh = spec.get('rail_h', 10)
    solid = spec.get('solid', False)
    # hanger rods at the back (drawn before everything), threaded up to a ceiling anchor
    for off in (-half - 3,):
        a = axis_pt(axis, 50, off, z - 4)
        b = axis_pt(axis, 50, off, z + 46)
        s.line3([a, b], OUT, sw=3.6)
        s.line3([a, b], SILVER, sw=1.8)
    # unistrut under the tray (across)
    ua, ub = axis_pt(axis, 50, -half - 6, z - 4), axis_pt(axis, 50, half + 6, z - 4)
    if axis == 'x':
        s.box(46, 50 - half - 6, z - 6, 8, 2 * half + 12, 4, color=STEEL, sw=1.1)
    else:
        s.box(50 - half - 6, 46, z - 6, 2 * half + 12, 8, 4, color=STEEL, sw=1.1)
    # back rail
    rail(s, axis, -half, z, rh, rc)
    # tray floor
    fl = [iso(*axis_pt(axis, -60, -half, z + 0.5)), iso(*axis_pt(axis, 160, -half, z + 0.5)),
          iso(*axis_pt(axis, 160, half, z + 0.5)), iso(*axis_pt(axis, -60, half, z + 0.5))]
    s.poly2(fl, shade(rc, -0.55) if solid else '#000000', stroke=None, opacity=1 if solid else 0.0)
    if not solid:
        # ladder rungs every 25 (divides 100 -> seamless)
        for t in range(-50, 160, 25):
            s.line3([axis_pt(axis, t, -half, z + 0.5), axis_pt(axis, t, half, z + 0.5)], OUT, sw=3.6)
            s.line3([axis_pt(axis, t, -half, z + 0.5), axis_pt(axis, t, half, z + 0.5)], shade(rc, -0.1), sw=2)
    spec['cables'](s, axis, z + 1)
    if spec.get('mesh'):
        # wire-basket front: two wires + uprights every 10 (divides 100 -> seamless)
        for t in range(-60, 161, 10):
            s.line3([axis_pt(axis, t, half, z), axis_pt(axis, t, half, z + rh)], OUT, sw=2.6)
            s.line3([axis_pt(axis, t, half, z), axis_pt(axis, t, half, z + rh)], rc, sw=1.3)
        for zz in (z, z + rh):
            s.line3([axis_pt(axis, -60, half, zz), axis_pt(axis, 160, half, zz)], OUT, sw=3.4)
            s.line3([axis_pt(axis, -60, half, zz), axis_pt(axis, 160, half, zz)], rc, sw=1.8)
    else:
        rail(s, axis, half, z, rh, rc)
    if spec.get('rim'):
        if axis == 'x':
            s.line3([(-60, 50 + half + 1.5, z + rh), (160, 50 + half + 1.5, z + rh)], spec['rim'], sw=1.6, glow=True)
        else:
            s.line3([(50 + half + 1.5, -60, z + rh), (50 + half + 1.5, 160, z + rh)], spec['rim'], sw=1.6, glow=True)


def bundle(s, axis, z, offs, colors, sw, amp=0.0, k=1, glow=False, hi=None, layers=None):
    order = sorted(range(len(offs)), key=lambda i: ((layers or [0] * len(offs))[i], offs[i]))
    for i in order:
        zz = z + sw / 2 + (layers[i] * sw * 0.8 if layers else 0)
        pts = run_pts(axis, offs[i], zz, amp=amp, k=k, ph=i * 1.7)
        cable(s, pts, colors[i % len(colors)], sw, glow=glow, hi=hi)


# ---- per-tier cable contents (floor run at z~0 and tray contents share these)
def c_copper1g(s, axis, z, tray=False):
    bundle(s, axis, z, [-7, 0, 7], [ORANGE, '#E5652A', '#FFA45C'], 5, amp=0 if tray else 1.6, k=1)


def c_copper10g(s, axis, z, tray=False):
    bundle(s, axis, z, [-12, -4, 4, 12], [AMBER, ORANGE, YELLOW, '#FF9F2E'], 7, amp=0 if tray else 1.2, k=1)


def c_fiber100g(s, axis, z, tray=False):
    for i, off in enumerate((-8, -2.5, 3, 8.5)):
        pts = run_pts(axis, off, z + 2, amp=0 if tray else 1.0, k=2, ph=i)
        fiber(s, pts, CYAN, sw=2.2)
    pulses(s, axis, -2.5, z + 2, WHITE, period=50, t0=20)
    pulses(s, axis, 8.5, z + 2, WHITE, period=50, t0=45)


def c_ib400g(s, axis, z, tray=False):
    offs = [-10, 0, 10]
    for i, off in enumerate(offs):
        zz = z + 4.5
        cable(s, run_pts(axis, off, zz), '#262B40', 9, hi='#56607F')
        collars(s, axis, off, zz, 9, GREEN, period=50, t0=25 + i * 8, length=6)


def c_ibspine(s, axis, z, tray=False):
    offs = [-15, -5, 5, 15, -10, 0, 10]
    layers = [0, 0, 0, 0, 1, 1, 1]
    for i in sorted(range(len(offs)), key=lambda i: (layers[i], offs[i])):
        zz = z + 4.5 + layers[i] * 7
        cable(s, run_pts(axis, offs[i], zz), '#22263A' if i % 2 else '#2A3048', 9, hi='#56607F')
    # green velcro straps every 25 around the whole bundle
    for t in range(-50, 160, 25):
        a, b = axis_pt(axis, t, -20, z + 11), axis_pt(axis, t, 20, z + 11)
        s.line3([a, b], OUT, sw=6.5)
        s.line3([a, b], GREEN, sw=3.6, glow=True)
    for t in range(-50, 160, 50):
        p = iso(*axis_pt(axis, t + 12, -5, z + 9))
        s.ellipse2(p[0], p[1], 2.2, 2.2, GREEN, stroke=None, glow=True)


def c_nvlink(s, axis, z, tray=False):
    offs = [-10, -5, 0, 5, 10]
    for i, off in enumerate(offs):
        pts = run_pts(axis, off, z + 3)
        s.line3(pts, OUT, sw=7.6)
    for i, off in enumerate(offs):
        pts = run_pts(axis, off, z + 3)
        s.line3(pts, GREEN, sw=5.0, glow=True)
        s.line3(pts, '#EAFFF4', sw=2.0)
    pulses(s, axis, 0, z + 3, WHITE, period=25, r=2.6, t0=10)


def c_optical(s, axis, z, tray=False):
    for i, off in enumerate((-7, 7)):
        pts = run_pts(axis, off, z + 5)
        s.line3(pts, OUT, sw=13, opacity=0.9)
        s.line3(pts, '#3A2266', sw=10.5)
        s.line3(pts, VIOLET, sw=6.5, glow=True)
        s.line3(pts, '#F0E4FF', sw=2.2)
        # tube highlight
        hp = run_pts(axis, off - 2.5, z + 8)
        s.line3(hp, '#FFFFFF', sw=1.2, opacity=0.5)
        pulses(s, axis, off, z + 5, WHITE, period=50, r=3.2, t0=15 + i * 25)
    # clips holding the pipes every 50
    for t in range(-50, 160, 50):
        a, b = axis_pt(axis, t + 25, -14, z + 6), axis_pt(axis, t + 25, 14, z + 6)
        s.line3([a, b], OUT, sw=5.6)
        s.line3([a, b], '#5A4A8A', sw=3.2)


CABLES = {
    'copper1g': dict(fn=c_copper1g, floor='loose', half=13, tray=dict(half=14, rail=SILVER, mesh=True, rail_h=8)),
    'copper10g': dict(fn=c_copper10g, floor='loose', half=19, tray=dict(half=19, rail=SILVER, mesh=True, rail_h=10)),
    'fiber100g': dict(fn=c_fiber100g, floor='channel', half=13, color='#1E2A44', rim=CYAN,
                      tray=dict(half=14, rail='#2A3A5E', solid=True, rim=CYAN, rail_h=8)),
    'ib400g': dict(fn=c_ib400g, floor='loose', half=17, tray=dict(half=17, rail='#3A4058')),
    'ibspine': dict(fn=c_ibspine, floor='channel', half=22, color='#2A3048', rim=GREEN, h=10,
                    tray=dict(half=22, rail='#3A4058', solid=True, rim=GREEN, rail_h=14)),
    'nvlink': dict(fn=c_nvlink, floor='channel', half=15, color='#1C2238', rim=GREEN, h=5,
                   tray=dict(half=15, rail='#2B3350', solid=True, rim='#B8FFD9', rail_h=8)),
    'optical': dict(fn=c_optical, floor='loose', half=16, tray=dict(half=16, rail='#3A3460', rim=VIOLET)),
}


def cable_floor(tier, axis):
    spec = CABLES[tier]
    s = Scene(glow=3.0)
    band(s, axis, 2, f'cb_{tier}_{axis}')
    half = spec['half']
    if spec['floor'] == 'channel':
        h = spec.get('h', 6)
        floor_shadow(s, axis, half + 3, op=0.4)
        trough(s, axis, half, h, spec['color'])
        spec['fn'](s, axis, 0.5)
        trough_front(s, axis, half, h, spec['color'], rim=spec['rim'])
    else:
        floor_shadow(s, axis, half, op=0.32)
        spec['fn'](s, axis, 0.0)
    s.add('</g>')
    return render(wrap_svg(s, VB1, 256), f'cable_{tier}_{axis}', 256)


def cable_tray(tier):
    spec = CABLES[tier]
    s = Scene(glow=3.0)
    t = dict(spec['tray'])
    t['cables'] = lambda s, axis, z: spec['fn'](s, axis, z, tray=True)
    band(s, 'x', TRAY_Z, f'ct_{tier}')
    tray(s, t, 'x')
    s.add('</g>')
    return render(wrap_svg(s, VB1, 256), f'cable_{tier}_tray', 256)


# ============================================================ 2. network tier icons
def plate(s, accent, x=0, y=0, w=100, d=100):
    b = s.box(x, y, 0, w, d, 6, color='#26315C')
    s.fline(b, 'left', [(0, 0.5), (1, 0.5)], accent, sw=1.6, glow=True)
    s.fline(b, 'right', [(0, 0.5), (1, 0.5)], shade(accent, -0.25), sw=1.6, glow=True)
    return b


def port_row(s, b, face, v0, v1, n, color, u0=0.06, u1=0.94, lit_every=1):
    pw = (u1 - u0) / n
    for i in range(n):
        u = u0 + i * pw
        s.frect(b, face, u + pw * 0.12, v0, u + pw * 0.88, v1, OUT)
        if i % lit_every == 0:
            s.frect(b, face, u + pw * 0.22, v0 + (v1 - v0) * 0.12, u + pw * 0.78, v0 + (v1 - v0) * 0.45, color, glow=True)


def net_icon_copper1g(s):
    plate(s, ORANGE)
    b = s.box(14, 26, 6, 72, 46, 16, color='#3A4166')
    s.frect(b, 'top', 0.1, 0.2, 0.9, 0.8, '#2C3254')
    for i in range(5):
        s.frect(b, 'top', 0.18 + i * 0.14, 0.35, 0.24 + i * 0.14, 0.65, DARK)
    port_row(s, b, 'left', 0.3, 0.8, 4, ORANGE, u0=0.08, u1=0.6)
    for i, c in enumerate((GREEN, ORANGE, ORANGE)):
        s.frect(b, 'left', 0.7 + i * 0.08, 0.42, 0.75 + i * 0.08, 0.58, c, glow=True)
    for (x, tilt) in ((24, -8), (76, 8)):
        s.line3([(x, 30, 22), (x + tilt, 30, 62)], OUT, sw=6.5)
        s.line3([(x, 30, 22), (x + tilt, 30, 62)], '#5A6290', sw=4)
        p = iso(x + tilt, 30, 62)
        s.ellipse2(p[0], p[1], 2.8, 2.8, ORANGE, stroke=OUT, sw=0.8, glow=True)
    for k, x in enumerate((20, 30, 40)):
        pts = [(x, 72, 12), (x + 2, 84, 7), (x - 4, 100, 7)]
        cable(s, pts, (ORANGE, '#E5652A', '#FFA45C')[k], 3.4)


def net_icon_copper10g(s):
    plate(s, YELLOW)
    b = s.box(4, 22, 6, 92, 56, 20, color='#323A60')
    s.fline(b, 'top', [(0.0, 0.97), (1.0, 0.97)], YELLOW, sw=2.4, glow=True)
    s.frect(b, 'left', 0.02, 0.1, 0.98, 0.9, DARK, stroke=OUT, sw=0.6)
    port_row(s, b, 'left', 0.2, 0.47, 10, AMBER, u0=0.04, u1=0.8)
    port_row(s, b, 'left', 0.55, 0.82, 10, YELLOW, u0=0.04, u1=0.8)
    s.frect(b, 'left', 0.84, 0.25, 0.95, 0.8, '#3A425F', stroke=OUT, sw=0.6)
    s.frect(b, 'left', 0.865, 0.35, 0.925, 0.5, GREEN, glow=True)
    for i in range(7):
        s.frect(b, 'top', 0.1 + i * 0.12, 0.2, 0.15 + i * 0.12, 0.8, DARK)
    for k, x in enumerate((10, 19, 28, 37, 46)):
        cable(s, [(x, 78, 18), (x + 1, 88, 10), (x - 4, 100, 7)], (AMBER, ORANGE, YELLOW)[k % 3], 4.2)


def net_icon_fiber100g(s):
    plate(s, CYAN)
    b = s.box(4, 22, 6, 92, 56, 18, color='#2A3558')
    s.fline(b, 'top', [(0.0, 0.97), (1.0, 0.97)], CYAN, sw=2.4, glow=True)
    s.frect(b, 'left', 0.02, 0.1, 0.98, 0.9, DARK, stroke=OUT, sw=0.6)
    # SFP cages, two rows
    port_row(s, b, 'left', 0.2, 0.45, 12, CYAN, u0=0.04, u1=0.86)
    port_row(s, b, 'left', 0.56, 0.82, 12, CYAN, u0=0.04, u1=0.86, lit_every=2)
    s.frect(b, 'left', 0.89, 0.25, 0.96, 0.75, GREEN, glow=True)
    for i in range(7):
        s.frect(b, 'top', 0.08 + i * 0.12, 0.2, 0.13 + i * 0.12, 0.8, DARK)
    for k, x in enumerate((10, 17, 24, 31, 38, 45)):
        fiber(s, [(x, 78, 16), (x - 1, 88, 10), (x - 8, 100, 7)], CYAN, sw=1.8)


def ib_cable_tip(s, pts, sw=6.0):
    cable(s, pts, '#262B40', sw, hi='#56607F')
    a, b = pts[0], pts[1]
    t = 0.32
    m = tuple(a[i] + (b[i] - a[i]) * t for i in range(3))
    s.line3([a, m], OUT, sw=sw + 3.2)
    s.line3([a, m], GREEN, sw=sw + 0.8, glow=True)


def net_icon_ib400g(s):
    plate(s, GREEN)
    b = s.box(6, 16, 6, 88, 66, 26, color='#2A2F4F')
    s.fline(b, 'top', [(0.0, 0.97), (1.0, 0.97)], GREEN, sw=2.4, glow=True)
    s.frect(b, 'left', 0.02, 0.08, 0.98, 0.92, DARK, stroke=OUT, sw=0.6)
    for r in range(2):
        v0 = 0.18 + r * 0.38
        for i in range(8):
            u = 0.05 + i * 0.112
            s.frect(b, 'left', u, v0, u + 0.09, v0 + 0.3, '#1E3A2E', stroke=OUT, sw=0.5)
            s.frect(b, 'left', u + 0.02, v0 + 0.06, u + 0.07, v0 + 0.16, GREEN, glow=True)
    s.frect(b, 'right', 0.1, 0.25, 0.9, 0.75, shade('#2A2F4F', -0.5))
    fan_top(s, b, 0.3, 0.5, 13, blade='#6B6F8F', hub=GREEN)
    fan_top(s, b, 0.7, 0.5, 13, blade='#6B6F8F', hub=GREEN)
    for k, x in enumerate((14, 26, 38)):
        ib_cable_tip(s, [(x, 82, 18), (x + 2, 92, 9), (x - 6, 104, 7)], sw=6.5)


def net_icon_ibspine(s):
    plate(s, GREEN)
    b = s.box(18, 18, 6, 64, 62, 88, color='#2A2F4F')
    for i in range(7):
        v = 0.05 + i * 0.13
        s.frect(b, 'left', 0.06, v, 0.94, v + 0.1, DARK, stroke=OUT, sw=0.5)
        for k in range(7):
            u = 0.1 + k * 0.115
            s.frect(b, 'left', u, v + 0.03, u + 0.07, v + 0.07, GREEN if (i + k) % 5 else WHITE, glow=True)
    for i in range(6):
        s.frect(b, 'right', 0.12, 0.08 + i * 0.15, 0.88, 0.14 + i * 0.15, shade('#2A2F4F', -0.5))
    s.frect(b, 'top', 0.12, 0.12, 0.88, 0.88, DARK)
    # heavy bundle leaving through an overhead tray
    t = s.box(10, 30, 106, 80, 34, 6, color='#3A4058')
    for k in range(5):
        x = 34 + k * 6
        cable(s, [(x, 44, 94), (x, 44, 108)], '#262B40', 5, hi='#56607F')
    for k in range(4):
        y = 36 + k * 7
        cable(s, [(12, y, 112), (88, y, 112)], '#262B40' if k % 2 else '#2E3450', 5.5, hi='#56607F')
    for x in (30, 60):
        s.line3([(x, 30, 115), (x, 64, 115)], GREEN, sw=2.6, glow=True)
    s.fline(t, 'left', [(0, 0.5), (1, 0.5)], GREEN, sw=1.6, glow=True)


def net_icon_nvlink(s):
    plate(s, GREEN)
    # rack frame behind, one switch tray pulled out toward the viewer
    s.box(12, 10, 6, 76, 50, 70, color='#232640')
    for i in range(5):
        if i == 2:
            continue
        z = 10 + i * 13
        tb = s.box(12, 58, z, 76, 2, 10, color='#2B2E4A')
        s.frect(tb, 'left', 0.06, 0.35, 0.94, 0.65, shade(GREEN, -0.25), glow=True)
    tray = s.box(12, 40, 36, 76, 48, 8, color='#2B2A40')
    s.frect(tray, 'top', 0.04, 0.06, 0.96, 0.94, DARK)
    for i in range(4):
        cu = 0.15 + i * 0.233
        s.frect(tray, 'top', cu - 0.08, 0.28, cu + 0.08, 0.6, '#1E3A2E', stroke=OUT, sw=0.6)
        s.frect(tray, 'top', cu - 0.05, 0.34, cu + 0.05, 0.54, GREEN, glow=True)
        s.frect(tray, 'top', cu - 0.025, 0.4, cu + 0.025, 0.48, WHITE, glow=True)
    # glowing links between the ASICs
    for i in range(3):
        a = Scene.fpt(tray, 'top', 0.15 + i * 0.233 + 0.08, 0.44)
        b = Scene.fpt(tray, 'top', 0.15 + (i + 1) * 0.233 - 0.08, 0.44)
        s.line2([a, b], GREEN, sw=2.4, glow=True)
    s.fline(tray, 'top', [(0.06, 0.8), (0.94, 0.8)], '#EAFFF4', sw=2.2, glow=True)
    s.frect(tray, 'left', 0.03, 0.2, 0.97, 0.8, '#1A1C2C')
    for i in range(10):
        s.frect(tray, 'left', 0.05 + i * 0.093, 0.3, 0.1 + i * 0.093, 0.7, GREEN, glow=True)
    # handles
    for u in (0.04, 0.96):
        p = Scene.fpt(tray, 'left', u, 0.5)
        s.ellipse2(p[0], p[1], 2.4, 3.6, SILVER, sw=0.8)


def net_icon_optical(s):
    plate(s, VIOLET)
    b = s.box(10, 18, 6, 80, 60, 40, color='#262B48')
    s.fline(b, 'top', [(0.0, 0.97), (1.0, 0.97)], VIOLET, sw=2.4, glow=True)
    s.frect(b, 'left', 0.03, 0.06, 0.97, 0.94, DARK, stroke=OUT, sw=0.6)
    # 3 x 6 bank of pluggable transceivers, each with a violet pull tab
    for r in range(3):
        for i in range(6):
            u0 = 0.06 + i * 0.148
            v0 = 0.12 + r * 0.28
            s.frect(b, 'left', u0, v0, u0 + 0.12, v0 + 0.2, '#8E9CC4', stroke=OUT, sw=0.6)
            s.frect(b, 'left', u0 + 0.02, v0 + 0.05, u0 + 0.1, v0 + 0.13, '#3A2266')
            s.frect(b, 'left', u0 + 0.035, v0 + 0.07, u0 + 0.085, v0 + 0.11, VIOLET, glow=True)
    for i in range(4):
        s.frect(b, 'right', 0.1 + i * 0.22, 0.2, 0.2 + i * 0.22, 0.8, shade(DARK, -0.3))
    s.frect(b, 'top', 0.15, 0.15, 0.85, 0.85, '#1E2240', stroke=OUT)
    # light pipes beaming out of the front
    for k, x in enumerate((18, 34, 50, 66)):
        pts = [(x, 78, 30 - k * 3), (x - 2, 92, 22 - k * 3), (x - 10, 106, 10)]
        s.line3(pts, OUT, sw=7)
        s.line3(pts, VIOLET, sw=4.6, glow=True)
        s.line3(pts, '#F0E4FF', sw=1.4)


NET_ICONS = {'copper1g': net_icon_copper1g, 'copper10g': net_icon_copper10g, 'fiber100g': net_icon_fiber100g,
             'ib400g': net_icon_ib400g, 'ibspine': net_icon_ibspine, 'nvlink': net_icon_nvlink,
             'optical': net_icon_optical}


# ============================================================ 3. cooling plants (2x2 cells)
def pad(s):
    b = s.box(4, 4, 0, 192, 192, 6, color='#3A4258', top='#4A5470')
    for k in range(1, 4):
        s.fline(b, 'top', [(k / 4, 0), (k / 4, 1)], '#3A4258', sw=1, opacity=0.8)
        s.fline(b, 'top', [(0, k / 4), (1, k / 4)], '#3A4258', sw=1, opacity=0.8)
    s.fline(b, 'left', [(0, 0.5), (1, 0.5)], CYAN, sw=1.6, glow=True, opacity=0.8)
    return b


def plant_base(s):
    ground(s, 100, 100, 175, CYAN, 4, 4, 196, 196, op=0.28)
    pad(s)


def valve(s, x, y, z, r=6):
    p = iso(x, y, z)
    s.ellipse2(p[0], p[1], r * 1.1, r * 0.6, RED, stroke=OUT, sw=1.2)
    s.ellipse2(p[0], p[1], r * 0.35, r * 0.2, OUT, stroke=None)


def chiller_unit(s, x, y, w, d, h, nfans):
    b = s.box(x, y, 6, w, d, h, color=COOL)
    for i in range(int(w / 9)):
        u = 0.03 + i * 9 / w
        s.frect(b, 'left', u, 0.14, u + 4 / w, 0.86, COOLD)
    for i in range(int(d / 9)):
        u = 0.05 + i * 9 / d
        s.frect(b, 'right', u, 0.14, u + 4 / d, 0.56, shade(COOL, -0.55))
    # control panel on the end
    s.frect(b, 'right', 0.25, 0.64, 0.75, 0.9, DARK, stroke=OUT, sw=0.8)
    s.frect(b, 'right', 0.32, 0.69, 0.68, 0.8, CYAN, glow=True)
    for i in range(nfans):
        fan_top(s, b, (i + 0.5) / nfans, 0.5, min(w / nfans, d) * 0.38, blade='#9FDDF2', hub=CYAN)
    s.fline(b, 'top', [(0, 0.98), (1, 0.98)], CYAN, sw=1.6, glow=True, opacity=0.8)
    return b


def plant_chiller(s):
    plant_base(s)
    # two air-cooled chillers (back to front)
    chiller_unit(s, 12, 14, 124, 64, 50, 3)
    chiller_unit(s, 12, 98, 124, 64, 50, 3)
    # pump skid in front of the ends
    sk = s.box(148, 22, 6, 42, 156, 6, color='#2B3350')
    for (y, c) in ((40, BLUE), (120, BLUE)):
        m = s.box(156, y, 12, 26, 22, 18, color='#2F4F7A')
        s.frect(m, 'left', 0.1, 0.3, 0.9, 0.5, shade(BLUE, 0.2), glow=True)
        s.cyl(169, y + 30, 12, 9, 16, color='#3B5F8F')
    # supply (blue) and return (cyan) pipes: from the chillers to a header that rises and runs off the pad
    for (yy, c, zz) in ((30, BLUE, 26), (60, CYAN, 40)):
        pipe3(s, [(136, yy, zz), (162, yy, zz), (162, yy, 74)], c, sw=8)
    for (yy, c, zz) in ((114, BLUE, 26), (144, CYAN, 40)):
        pipe3(s, [(136, yy, zz), (176, yy, zz), (176, yy, 74)], c, sw=8)
    pipe3(s, [(162, 16, 74), (162, 196, 74)], BLUE, sw=10, glow=False)
    pipe3(s, [(176, 16, 74), (176, 196, 74)], CYAN, sw=10, glow=False)
    for y in (90, 186):
        valve(s, 162, y, 80)
        valve(s, 176, y, 80)
    # pipe-rack posts
    for y in (24, 100, 176):
        s.box(158, y, 6, 4, 4, 64, color=STEEL, sw=1)
        s.box(180, y, 6, 4, 4, 64, color=STEEL, sw=1)
    p = iso(169, 196, 74)
    s.aura(p[0], p[1], 26, CYAN, 0.35)


def plant_tower(s):
    plant_base(s)
    # supply pipe behind
    pipe3(s, [(10, 30, 6 + 70), (10, 30, 100), (60, 30, 100)], ORANGE, sw=9)
    b = s.box(18, 22, 6, 164, 140, 86, color='#557A9C')
    # louvres
    for i in range(9):
        v = 0.08 + i * 0.085
        s.frect(b, 'left', 0.03, v, 0.97, v + 0.045, COOLD)
        s.frect(b, 'right', 0.03, v, 0.97, v + 0.045, shade(COOLD, -0.4))
    # cell divider
    s.fline(b, 'left', [(0.5, 0), (0.5, 1)], OUT, sw=2)
    s.frect(b, 'left', 0.0, 0.88, 1.0, 1.0, CYAN, glow=True, opacity=0.85)
    s.frect(b, 'right', 0.0, 0.88, 1.0, 1.0, shade(CYAN, -0.3), glow=True, opacity=0.85)
    # ladder on the right face
    for u in (0.12, 0.2):
        s.fline(b, 'right', [(u, 0.05), (u, 1.0)], SILVER, sw=1.6)
    for k in range(10):
        v = 0.08 + k * 0.09
        s.fline(b, 'right', [(0.12, v), (0.2, v)], SILVER, sw=1.2)
    # deck + fan stacks
    top = 92
    stacks = ((60, 92), (140, 92))
    for (x, y) in stacks:
        cx, cy, rx, ry, ty = s.cyl(x, y, top, 32, 34, color='#6E93B5')
        s.ellipse2(cx, ty, rx * 0.84, ry * 0.84, DARK, sw=1.2)
        # fan blades in the stack
        for k in range(4):
            t = k * math.pi / 2 + 0.4
            s.line2([(cx, ty), (cx + rx * 0.75 * math.cos(t), ty + ry * 0.75 * math.sin(t))], STEEL, sw=4)
        s.ellipse2(cx, ty, rx * 0.2, ry * 0.2, CYAN, stroke=None, glow=True)
    # handrail around the deck
    rail = [(20, 24, top + 14), (180, 24, top + 14), (180, 160, top + 14), (20, 160, top + 14), (20, 24, top + 14)]
    s.line3(rail, SILVER, sw=1.6)
    for (x, y) in ((20, 160), (100, 160), (180, 160), (180, 92), (180, 24)):
        s.line3([(x, y, top), (x, y, top + 14)], SILVER, sw=1.4)
    # steam (a hint)
    for (x, y) in stacks:
        p = iso(x, y, top + 34)
        for k, (ox, oy, r) in enumerate(((0, -6, 18), (12, -26, 16), (-4, -46, 13), (8, -62, 9))):
            puff(s, p[0] + ox, p[1] + oy, r, op=0.62 - k * 0.13)
    # cold-water outlet in front
    pipe3(s, [(60, 162, 16), (60, 194, 16)], BLUE, sw=10)
    pipe3(s, [(120, 162, 16), (120, 194, 16)], BLUE, sw=10)
    valve(s, 60, 182, 24)
    valve(s, 120, 182, 24)


def plant_liquid(s):
    plant_base(s)
    # pipe rack (back posts)
    for x in (24, 100, 176):
        s.box(x, 20, 6, 5, 5, 96, color=STEEL, sw=1)
    s.box(20, 18, 96, 164, 10, 5, color=STEEL, sw=1)
    # two CDU cabinets
    for (x, y) in ((22, 40), (70, 40)):
        b = s.box(x, y, 6, 40, 40, 80, color=COOL)
        s.frect(b, 'left', 0.1, 0.08, 0.9, 0.34, '#183552', stroke=OUT)
        s.frect(b, 'left', 0.18, 0.14, 0.82, 0.28, CYAN, glow=True)
        for k in range(5):
            s.frect(b, 'left', 0.12, 0.44 + k * 0.1, 0.88, 0.48 + k * 0.1, COOLD)
        for k in range(4):
            s.frect(b, 'right', 0.12, 0.15 + k * 0.2, 0.88, 0.24 + k * 0.2, shade(COOL, -0.5))
        s.frect(b, 'top', 0.2, 0.2, 0.8, 0.8, DARK)
        s.frect(b, 'top', 0.35, 0.35, 0.65, 0.65, CYAN, glow=True)
        # risers to the header
        pipe3(s, [(x + 12, y + 2, 86), (x + 12, y + 2, 100), (x + 12, 30, 100)], BLUE, sw=6)
        pipe3(s, [(x + 28, y + 2, 86), (x + 28, y + 2, 92), (x + 28, 30, 92)], CYAN, sw=6)
    # expansion tank + pump
    s.cyl(150, 50, 6, 18, 70, color='#3B6FB0')
    p = iso(150, 50, 76)
    s.ellipse2(p[0], p[1], 6, 3.4, CYAN, stroke=None, glow=True)
    m = s.box(130, 92, 6, 36, 24, 22, color='#2F4F7A')
    s.frect(m, 'left', 0.1, 0.35, 0.9, 0.6, BLUE, glow=True)
    s.cyl(176, 104, 6, 10, 26, color='#3B5F8F')
    # the manifold: supply (blue) and return (cyan) headers along x up high, then down and out the front
    pipe3(s, [(16, 30, 100), (186, 30, 100)], BLUE, sw=11)
    pipe3(s, [(16, 30, 92), (186, 30, 92)], CYAN, sw=9)
    pipe3(s, [(186, 30, 100), (186, 30, 108), (186, 196, 108)], BLUE, sw=11)
    pipe3(s, [(178, 30, 92), (178, 150, 92), (178, 150, 30), (178, 196, 30)], CYAN, sw=9)
    # floor manifold with drops (toward the room)
    pipe3(s, [(16, 150, 18), (178, 150, 18)], BLUE, sw=10)
    pipe3(s, [(130, 104, 20), (130, 150, 20)], BLUE, sw=8)
    for x in (30, 60, 90, 120):
        pipe3(s, [(x, 150, 18), (x, 194, 18)], BLUE, sw=6)
        valve(s, x, 172, 24, r=4.5)
    for x in (45, 75, 105):
        pipe3(s, [(x, 150, 40), (x, 194, 40)], CYAN, sw=5)
    pipe3(s, [(30, 150, 40), (178, 150, 40)], CYAN, sw=7)
    # droplet sign
    p = iso(100, 100, 150)
    s.path2(f'M{p[0]:.1f},{p[1] - 18:.1f} C{p[0] + 12:.1f},{p[1] - 4:.1f} {p[0] + 10:.1f},{p[1] + 10:.1f} {p[0]:.1f},{p[1] + 10:.1f} '
            f'C{p[0] - 10:.1f},{p[1] + 10:.1f} {p[0] - 12:.1f},{p[1] - 4:.1f} {p[0]:.1f},{p[1] - 18:.1f} Z', CYAN,
            [(p[0] - 12, p[1] - 18), (p[0] + 12, p[1] + 10)], glow=True)


def dry_unit(s, x, y, w, d, z, h, nfans):
    for (lx, ly) in ((x + 2, y + 2), (x + w - 8, y + 2), (x + 2, y + d - 8), (x + w - 8, y + d - 8),
                     (x + w / 2 - 3, y + d - 8), (x + w / 2 - 3, y + 2)):
        s.box(lx, ly, 6, 6, 6, z - 6, color=STEEL, sw=1)
    b = s.box(x, y, z, w, d, h, color='#4F6E92')
    n = int(w / 14)
    for i in range(n):
        u = 0.03 + i * 0.94 / n
        s.fline(b, 'left', [(u, 0.15), (u + 0.47 / n, 0.85), (u + 0.94 / n, 0.15)], COOLD, sw=2)
    m = int(d / 14)
    for i in range(m):
        u = 0.04 + i * 0.92 / m
        s.fline(b, 'right', [(u, 0.15), (u + 0.46 / m, 0.85), (u + 0.92 / m, 0.15)], shade(COOLD, -0.35), sw=2)
    s.frect(b, 'left', 0.0, 0.86, 1.0, 1.0, CYAN, glow=True, opacity=0.8)
    for i in range(nfans):
        fan_top(s, b, (i + 0.5) / nfans, 0.5, min(w / nfans, d) * 0.4, blade=SILVER, hub=CYAN)
    return b


def plant_dry(s):
    plant_base(s)
    # header pipes underneath, behind the legs
    pipe3(s, [(10, 40, 14), (190, 40, 14)], BLUE, sw=8)
    pipe3(s, [(10, 120, 14), (190, 120, 14)], CYAN, sw=8)
    dry_unit(s, 10, 16, 180, 68, 34, 30, 4)
    dry_unit(s, 10, 100, 180, 68, 34, 30, 4)
    pipe3(s, [(190, 40, 14), (196, 40, 14)], BLUE, sw=8)
    pipe3(s, [(190, 120, 14), (196, 120, 14)], CYAN, sw=8)
    pipe3(s, [(60, 172, 14), (60, 196, 14)], BLUE, sw=8)
    pipe3(s, [(100, 172, 14), (100, 196, 14)], CYAN, sw=8)


PLANTS = {'chiller': plant_chiller, 'tower': plant_tower, 'liquid': plant_liquid, 'dry': plant_dry}


# ---- cooling tier icons (simplified, chunkier versions)
def cool_plate(s):
    return plate(s, CYAN)


def cool_icon_chiller(s):
    cool_plate(s)
    b = s.box(8, 16, 6, 84, 56, 38, color=COOL)
    for i in range(9):
        s.frect(b, 'left', 0.04 + i * 0.105, 0.16, 0.09 + i * 0.105, 0.84, COOLD)
    for i in range(5):
        s.frect(b, 'right', 0.08 + i * 0.18, 0.16, 0.14 + i * 0.18, 0.84, shade(COOL, -0.55))
    for cu in (0.25, 0.75):
        fan_top(s, b, cu, 0.5, 18, blade='#9FDDF2', hub=CYAN)
    pipe3(s, [(28, 72, 20), (28, 100, 20)], BLUE, sw=8)
    pipe3(s, [(56, 72, 30), (56, 100, 30)], CYAN, sw=8)
    valve(s, 28, 88, 26, r=4.5)


def cool_icon_tower(s):
    cool_plate(s)
    b = s.box(12, 14, 6, 76, 72, 46, color='#557A9C')
    for i in range(6):
        s.frect(b, 'left', 0.04, 0.1 + i * 0.13, 0.96, 0.16 + i * 0.13, COOLD)
        s.frect(b, 'right', 0.04, 0.1 + i * 0.13, 0.96, 0.16 + i * 0.13, shade(COOLD, -0.4))
    s.frect(b, 'left', 0.0, 0.88, 1.0, 1.0, CYAN, glow=True)
    for (x, y) in ((32, 62), (68, 28)):
        cx, cy, rx, ry, ty = s.cyl(x, y, 52, 16, 20, color='#6E93B5')
        s.ellipse2(cx, ty, rx * 0.8, ry * 0.8, DARK, sw=1)
        s.ellipse2(cx, ty, rx * 0.25, ry * 0.25, CYAN, stroke=None, glow=True)
    for (x, y) in ((32, 62), (68, 28)):
        p = iso(x, y, 74)
        for k, (ox, oy, r) in enumerate(((0, -2, 9), (6, -13, 8), (-2, -23, 6))):
            puff(s, p[0] + ox, p[1] + oy, r, op=0.8 - k * 0.2)


def cool_icon_liquid(s):
    cool_plate(s)
    b = s.box(10, 14, 6, 38, 40, 64, color=COOL)
    s.frect(b, 'left', 0.12, 0.1, 0.88, 0.4, '#183552', stroke=OUT)
    s.frect(b, 'left', 0.2, 0.18, 0.8, 0.32, CYAN, glow=True)
    for k in range(3):
        s.frect(b, 'left', 0.14, 0.5 + k * 0.14, 0.86, 0.56 + k * 0.14, COOLD)
        s.frect(b, 'right', 0.14, 0.2 + k * 0.22, 0.86, 0.3 + k * 0.22, shade(COOL, -0.5))
    pipe3(s, [(48, 24, 54), (90, 24, 54), (90, 90, 54), (90, 90, 12)], BLUE, sw=9)
    pipe3(s, [(48, 44, 40), (76, 44, 40), (76, 90, 40), (76, 90, 12)], CYAN, sw=8)
    for y in (58, 74):
        pipe3(s, [(90, y, 54), (90, y, 30), (100, y, 30)], BLUE, sw=5)
    valve(s, 90, 40, 60, r=5)
    p = iso(30, 60, 98)
    s.path2(f'M{p[0]:.1f},{p[1] - 13:.1f} C{p[0] + 9:.1f},{p[1] - 3:.1f} {p[0] + 7:.1f},{p[1] + 7:.1f} {p[0]:.1f},{p[1] + 7:.1f} '
            f'C{p[0] - 7:.1f},{p[1] + 7:.1f} {p[0] - 9:.1f},{p[1] - 3:.1f} {p[0]:.1f},{p[1] - 13:.1f} Z', CYAN,
            [(p[0] - 9, p[1] - 13), (p[0] + 9, p[1] + 7)], glow=True)


def cool_icon_dry(s):
    cool_plate(s)
    for (lx, ly) in ((10, 12), (84, 12), (10, 82), (84, 82)):
        s.box(lx, ly, 6, 6, 6, 14, color=STEEL, sw=1)
    b = s.box(8, 10, 20, 84, 80, 22, color='#4F6E92')
    for i in range(6):
        u = 0.05 + i * 0.15
        s.fline(b, 'left', [(u, 0.2), (u + 0.075, 0.8), (u + 0.15, 0.2)], COOLD, sw=2)
        s.fline(b, 'right', [(u, 0.2), (u + 0.075, 0.8), (u + 0.15, 0.2)], shade(COOLD, -0.35), sw=2)
    s.frect(b, 'left', 0.0, 0.86, 1.0, 1.0, CYAN, glow=True, opacity=0.85)
    for i in range(2):
        for j in range(2):
            fan_top(s, b, 0.27 + i * 0.46, 0.27 + j * 0.46, 15, blade=SILVER, hub=CYAN)


COOL_ICONS = {'chiller': cool_icon_chiller, 'tower': cool_icon_tower, 'liquid': cool_icon_liquid, 'dry': cool_icon_dry}


# ============================================================ 4. moving sequence
def wheel_left(s, x, y, z, r):
    """Wheel on a y-plane (visible from the left face), centred at (x, y, z)."""
    b = (x - r, y, z - r, 2 * r, 0, 2 * r)
    s.fcircle(b, 'left', 0.5, 0.5, 0.5, 0.5, '#15171F', sw=1.6, n=32)
    s.fcircle(b, 'left', 0.5, 0.5, 0.27, 0.27, '#8E9CC4', sw=1.0, n=24)
    s.fcircle(b, 'left', 0.5, 0.5, 0.09, 0.09, '#3A4058', stroke=None, n=12)


def truck_scene(s, x0=12, y0=70):
    W, D = 178, 60   # along x, across y
    ground(s, x0 + W / 2, y0 + D / 2, 0, GREEN, x0 - 4, y0 + 2, x0 + W, y0 + D, op=0.0)
    # far-side wheels hint
    # chassis
    s.box(x0 + 4, y0 + 6, 10, W - 8, D - 12, 8, color='#20253A')
    # cargo box
    box = s.box(x0, y0, 18, 126, D, 78, color='#D9DFEA', top='#EEF2F8', right='#A9B2C6')
    s.frect(box, 'left', 0.0, 0.7, 1.0, 0.78, GREEN, glow=True)
    s.frect(box, 'left', 0.0, 0.8, 1.0, 0.84, CYAN, glow=True)
    s.frect(box, 'right', 0.0, 0.7, 1.0, 0.78, shade(GREEN, -0.25), glow=True)
    # chip logo on the side
    cu, cv = 0.5, 0.38
    s.frect(box, 'left', cu - 0.11, cv - 0.2, cu + 0.11, cv + 0.2, '#2E3B6B', stroke=OUT, sw=1.2)
    for k in range(5):
        uu = cu - 0.09 + k * 0.045
        s.frect(box, 'left', uu, cv - 0.27, uu + 0.02, cv - 0.2, '#8E9CC4')
        s.frect(box, 'left', uu, cv + 0.2, uu + 0.02, cv + 0.27, '#8E9CC4')
    s.frect(box, 'left', cu - 0.06, cv - 0.1, cu + 0.06, cv + 0.1, GREEN, glow=True)
    # ribs
    for k in range(1, 6):
        s.fline(box, 'left', [(k / 6, 0.03), (k / 6, 0.66)], '#B8C0D2', sw=1.2)
    s.fline(box, 'top', [(0, 0.5), (1, 0.5)], '#C9D0DE', sw=1.2)
    # cab
    cx = x0 + 130
    cab = s.box(cx, y0 + 2, 18, 48, D - 4, 40, color='#2E3B6B')
    # cab upper with sloped windshield
    zt = 18 + 40
    s.poly2([iso(cx, y0 + D - 2, zt), iso(cx + 30, y0 + D - 2, zt + 30), iso(cx, y0 + D - 2, zt + 30)], '#2E3B6B', sw=1.6)
    s.poly2([iso(cx + 30, y0 + 2, zt + 30), iso(cx + 30, y0 + D - 2, zt + 30), iso(cx + 48, y0 + D - 2, zt),
             iso(cx + 48, y0 + 2, zt)], '#9FDDF2', sw=1.6)
    s.poly2([iso(cx + 33, y0 + 8, zt + 25), iso(cx + 33, y0 + D - 8, zt + 25), iso(cx + 45, y0 + D - 8, zt + 5),
             iso(cx + 45, y0 + 8, zt + 5)], '#CFF3FF', stroke=None, opacity=0.6)
    s.poly2([iso(cx, y0 + 2, zt + 30), iso(cx + 30, y0 + 2, zt + 30), iso(cx + 30, y0 + D - 2, zt + 30),
             iso(cx, y0 + D - 2, zt + 30)], shade('#2E3B6B', 0.28), sw=1.6)
    # side window
    s.poly2([iso(cx + 6, y0 + D - 2, zt + 4), iso(cx + 26, y0 + D - 2, zt + 4), iso(cx + 26, y0 + D - 2, zt + 25),
             iso(cx + 6, y0 + D - 2, zt + 25)], '#9FDDF2', sw=1.2)
    s.poly2([iso(cx + 32, y0 + D - 2, zt), iso(cx + 30, y0 + D - 2, zt + 28), iso(cx + 30, y0 + D - 2, zt + 30), iso(cx + 48, y0 + D - 2, zt)],
            '#2E3B6B', sw=1.2)
    s.frect(cab, 'left', 0.12, 0.25, 0.22, 0.32, SILVER)
    s.fline(cab, 'left', [(0.1, 0.05), (0.1, 0.95)], OUT, sw=1)
    s.fline(cab, 'left', [(0.0, 0.62), (1.0, 0.62)], GREEN, sw=2.4, glow=True)
    # front: grille, headlights, bumper
    s.frect(cab, 'right', 0.3, 0.25, 0.7, 0.62, DARK, stroke=OUT, sw=0.8)
    for k in range(4):
        s.frect(cab, 'right', 0.32, 0.3 + k * 0.08, 0.68, 0.33 + k * 0.08, '#4A5680')
    for u in (0.12, 0.88):
        s.frect(cab, 'right', u - 0.08, 0.28, u + 0.08, 0.44, '#FFF2C4', glow=True, stroke=OUT, sw=0.8)
    s.frect(cab, 'right', 0.04, 0.5, 0.18, 0.58, AMBER, glow=True)
    s.frect(cab, 'right', 0.82, 0.5, 0.96, 0.58, AMBER, glow=True)
    s.box(cx + 48, y0, 14, 5, D, 8, color='#4A5270')
    # mirror
    s.line3([(cx + 28, y0 + D - 2, zt + 10), (cx + 30, y0 + D + 8, zt + 12)], OUT, sw=2.4)
    s.box(cx + 26, y0 + D + 6, zt + 4, 4, 3, 14, color=DARK, sw=1)
    # wheels (front side)
    for wx in (x0 + 28, x0 + 98, cx + 28):
        p = (wx, y0 + D + 0.5, 15)
        # wheel arch
        wheel_left(s, wx, y0 + D + 1, 15, 15)
    # tail lights on the back corner
    p = iso(x0, y0 + D, 26)
    s.ellipse2(p[0] + 2, p[1] - 2, 2.6, 4, RED, stroke=OUT, sw=0.8, glow=True)


def move_truck():
    s = Scene(glow=3.0)
    x0, y0 = 12, 72
    # shadow
    s.poly2([iso(x0 - 2, y0 + 4, 0), iso(x0 + 186, y0 + 4, 0), iso(x0 + 186, y0 + 66, 0), iso(x0 - 2, y0 + 66, 0)],
            '#000000', stroke=None, opacity=0.4)
    truck_scene(s, x0, y0)
    out = render(wrap_svg(s, VB2, 512), 'move_truck', 512)
    flip = os.path.join(OUTDIR, 'move_truck_flip.png')
    run('magick', out, '-flop', flip)
    return [out, flip]


def cardboard(s, x, y, z, w, d, h, tape='#C9B28A'):
    b = s.box(x, y, z, w, d, h, color=CARD, top='#B98C57', right='#7A5A34', sw=1.4)
    s.frect(b, 'top', 0.43, 0, 0.57, 1, tape, opacity=0.9)
    s.frect(b, 'left', 0.43, 0, 0.57, 0.3, tape, opacity=0.9)
    s.frect(b, 'right', 0.0, 0.0, 0.08, 0.3, tape, opacity=0.0)
    s.fline(b, 'top', [(0.5, 0), (0.5, 1)], '#7A5A34', sw=0.8, opacity=0.8)
    return b


def glass_glyph(s, b, face, cu, cv, sz, color='#D33A3A'):
    # wine glass: bowl + stem + foot, drawn in face uv
    w = b[3] if face == 'left' else b[4]
    h = b[5]
    su, sv = sz / w, sz / h
    bowl = [(cu - 0.5 * su + 0.5 * su * (1 - math.cos(t)) * 0 + 0.5 * su * math.sin(t) * 0, 0) for t in [0]]
    pts = []
    for k in range(13):
        t = math.pi * k / 12
        pts.append((cu - 0.45 * su * math.cos(t), cv - 0.5 * sv + 0.45 * sv * math.sin(t)))
    s.fpoly(b, face, [(cu - 0.45 * su, cv - 0.5 * sv)] + pts + [(cu + 0.45 * su, cv - 0.5 * sv)], color, stroke=None)
    s.frect(b, face, cu - 0.05 * su, cv - 0.08 * sv, cu + 0.05 * su, cv + 0.4 * sv, color)
    s.frect(b, face, cu - 0.3 * su, cv + 0.4 * sv, cu + 0.3 * su, cv + 0.5 * sv, color)


def up_arrows(s, b, face, cu, cv, sz, color=OUT):
    w = b[3] if face == 'left' else b[4]
    h = b[5]
    su, sv = sz / w, sz / h
    for k in (-0.3, 0.3):
        u = cu + k * su
        s.fpoly(b, face, [(u, cv - 0.5 * sv), (u + 0.22 * su, cv - 0.15 * sv), (u + 0.08 * su, cv - 0.15 * sv),
                          (u + 0.08 * su, cv + 0.5 * sv), (u - 0.08 * su, cv + 0.5 * sv), (u - 0.08 * su, cv - 0.15 * sv),
                          (u - 0.22 * su, cv - 0.15 * sv)], color, stroke=None)


def label(s, b, face, u0, v0, u1, v1, fill='#F3F5F0', stroke=OUT):
    s.frect(b, face, u0, v0, u1, v1, fill, stroke=stroke, sw=0.9)


def move_boxes():
    s = Scene(glow=3.0)
    ground(s, 50, 50, 80, GREEN, 6, 8, 94, 92, op=0.22)
    # big bottom box, a second beside it, and a small one on top
    b1 = cardboard(s, 8, 30, 0, 64, 56, 42)
    b2 = cardboard(s, 66, 14, 0, 28, 40, 30)
    b3 = cardboard(s, 16, 36, 42, 46, 40, 30)
    # label on the big box front: "GPUs – FRAGILE"
    label(s, b1, 'left', 0.06, 0.38, 0.94, 0.86, fill='#F3F5F0')
    s.frect(b1, 'left', 0.06, 0.62, 0.94, 0.86, '#D33A3A')
    face_text(s, b1, 'left', 32, 26, 'GPUs –', 12.5, '#1A2242')
    face_text(s, b1, 'left', 32, 35.4, 'FRAGILE', 10.5, '#FFFFFF')
    # top box: big red FRAGILE sticker + glass
    label(s, b3, 'left', 0.08, 0.12, 0.92, 0.5, fill='#D33A3A')
    face_text(s, b3, 'left', 23, 12.2, 'FRAGILE', 9.5, '#FFFFFF')
    glass_glyph(s, b3, 'left', 0.5, 0.75, 13, color='#1A2242')
    # this-side-up arrows + glass on the side box and right faces
    up_arrows(s, b2, 'left', 0.5, 0.45, 16)
    s.frect(b2, 'right', 0.2, 0.25, 0.8, 0.75, '#D33A3A', stroke=OUT, sw=0.8)
    glass_glyph(s, b2, 'right', 0.5, 0.5, 13, color='#F3F5F0')
    s.frect(b3, 'right', 0.2, 0.3, 0.8, 0.7, '#D33A3A', stroke=OUT, sw=0.8)
    glass_glyph(s, b3, 'right', 0.5, 0.52, 12, color='#F3F5F0')
    # GPU chip sticker glowing on top box lid
    s.frect(b3, 'top', 0.62, 0.15, 0.9, 0.42, '#2E3B6B', stroke=OUT, sw=0.8)
    s.frect(b3, 'top', 0.69, 0.22, 0.83, 0.35, GREEN, glow=True)
    return render(wrap_svg(s, VB1, 256), 'move_boxes', 256)


def move_dolly():
    s = Scene(glow=3.0)
    ground(s, 50, 50, 80, GREEN, 10, 18, 86, 84, op=0.22)
    # back wheel (far)
    wheel_left(s, 16, 26, 12, 12)
    # rails (behind the server), nose plate
    for y in (30, 70):
        s.box(14, y - 2, 6, 5, 4, 112, color='#C23B32', top='#E05A4E', sw=1.2)
    s.box(18, 28, 4, 56, 44, 4, color=SILVER, sw=1.2)
    s.line3([(16, 30, 60), (16, 70, 60)], OUT, sw=4.4)
    s.line3([(16, 30, 60), (16, 70, 60)], '#C23B32', sw=2.6)
    # the server, standing on its end, front panel facing +x
    b = s.box(22, 30, 8, 46, 40, 92, color='#2A3766')
    for i in range(8):
        v = 0.06 + i * 0.11
        s.frect(b, 'right', 0.08, v, 0.92, v + 0.08, DARK, stroke=OUT, sw=0.5)
        s.frect(b, 'right', 0.14, v + 0.025, 0.14 + 0.25 + (i * 37 % 10) / 30, v + 0.055, GREEN if i % 3 else CYAN, glow=True)
    for i in range(6):
        s.frect(b, 'left', 0.08, 0.08 + i * 0.15, 0.92, 0.12 + i * 0.15, shade('#2A3766', -0.45))
    s.frect(b, 'top', 0.2, 0.2, 0.8, 0.8, DARK)
    s.frect(b, 'top', 0.35, 0.35, 0.65, 0.65, GREEN, glow=True)
    # amber ratchet strap around it
    for v in (0.28, 0.7):
        s.frect(b, 'left', 0.0, v, 1.0, v + 0.06, AMBER, stroke=OUT, sw=0.6)
        s.frect(b, 'right', 0.0, v, 1.0, v + 0.06, shade(AMBER, -0.2), stroke=OUT, sw=0.6)
    p = Scene.fpt(b, 'left', 0.5, 0.31)
    s.poly2([(p[0] - 4, p[1] - 4), (p[0] + 4, p[1] - 4), (p[0] + 4, p[1] + 5), (p[0] - 4, p[1] + 5)], SILVER, sw=0.8)
    # handle loop above
    s.line3([(16, 30, 118), (12, 36, 128), (12, 64, 128), (16, 70, 118)], OUT, sw=5)
    s.line3([(16, 30, 118), (12, 36, 128), (12, 64, 128), (16, 70, 118)], '#C23B32', sw=3)
    s.line3([(12, 40, 128), (12, 60, 128)], OUT, sw=6.5)
    s.line3([(12, 40, 128), (12, 60, 128)], '#1A1C24', sw=4.5)
    # front wheel (near)
    s.line3([(16, 70, 12), (16, 76, 12)], OUT, sw=3)
    wheel_left(s, 16, 76, 12, 12)
    return render(wrap_svg(s, VB1, 256), 'move_dolly', 256)


# ============================================================ 5. era move banner (900x300, opaque)
BW, BH = 900, 300


def move_banner():
    s = Scene(glow=3.0)
    rnd = random.Random(42)
    # ground and road (road runs along x, like the driveway / world roads)
    s.poly2([iso(-900, -900, 0), iso(900, -900, 0), iso(900, 900, 0), iso(-900, 900, 0)], '#141A30', stroke=None)
    for k in range(-12, 13):
        s.line3([(k * 60, -900, 0), (k * 60, 900, 0)], '#1C2440', sw=1, opacity=0.6)
        s.line3([(-900, k * 60, 0), (900, k * 60, 0)], '#1C2440', sw=1, opacity=0.6)
    s.poly2([iso(-900, 60, 0), iso(900, 60, 0), iso(900, 140, 0), iso(-900, 140, 0)], '#232A44', stroke=None)
    s.line3([(-900, 60, 0), (900, 60, 0)], '#3A4466', sw=2)
    s.line3([(-900, 140, 0), (900, 140, 0)], '#3A4466', sw=2)
    for x in range(-900, 900, 50):
        s.line3([(x, 100, 0), (x + 24, 100, 0)], AMBER, sw=2.2, opacity=0.85, glow=True)
    # old garage (behind, left) and the new building (right), both small silhouettes
    g = s.box(-140, 170, 0, 60, 46, 34, color='#4A4038')
    s.poly2([iso(-140, 216, 34), iso(-80, 216, 34), iso(-80, 193, 52), iso(-140, 193, 52)], '#5A3A34', sw=1.4)
    s.poly2([iso(-80, 170, 34), iso(-80, 216, 34), iso(-80, 193, 52)], '#7A5048', sw=1.4)
    s.frect(g, 'left', 0.2, 0.3, 0.8, 1.0, '#2A2520')
    s.frect(g, 'left', 0.25, 0.35, 0.75, 0.5, '#FFD58A', glow=True)
    nb = s.box(170, -175, 0, 80, 64, 56, color='#2A3560')
    for i in range(6):
        s.frect(nb, 'left', 0.06 + i * 0.15, 0.3, 0.14 + i * 0.15, 0.7, GREEN if i % 3 else CYAN, glow=True)
    for i in range(4):
        s.frect(nb, 'right', 0.08 + i * 0.22, 0.35, 0.18 + i * 0.22, 0.65, shade(GREEN, -0.3), glow=True)
    for i in range(3):
        r = s.box(176 + i * 25, -163, 56, 18, 34, 5, color=STEEL, sw=1.2)
        s.frect(r, 'top', 0.3, 0.3, 0.7, 0.7, CYAN, glow=True)
    # little truck on the road, heading to the new place
    ts = Scene(glow=3.0)
    truck_scene(ts, 0, 0)
    tx, ty = iso(95, 70, 0)
    s.add(f'<g transform="translate({tx:.1f},{ty:.1f}) scale(0.42)">' + '\n'.join(ts.els) + '</g>')
    s.defs += ts.defs
    # view window
    c = iso(30, 70, 40)
    w = 760
    h = w * BH / BW
    vb = (c[0] - w / 2, c[1] - h / 2 + 22, w, h)
    # confetti: rotated rectangles, dots and streamers in the neon palette, lighter in the centre
    cols = [GREEN, CYAN, AMBER, PINK, VIOLET, RED, WHITE, YELLOW]
    conf = []
    for _ in range(170):
        x = rnd.uniform(vb[0], vb[0] + w)
        y = rnd.uniform(vb[1], vb[1] + h * 0.92)
        dx = abs(x - (vb[0] + w / 2)) / (w / 2)
        if dx < 0.35 and rnd.random() < 0.6:
            continue
        col = rnd.choice(cols)
        a = rnd.uniform(0, 180)
        sz = rnd.uniform(4, 9)
        kind = rnd.random()
        if kind < 0.6:
            conf.append(f'<rect x="{-sz / 2:.1f}" y="{-sz / 4:.1f}" width="{sz:.1f}" height="{sz / 2:.1f}" fill="{col}" '
                        f'stroke="{OUT}" stroke-width="0.6" transform="translate({x:.1f},{y:.1f}) rotate({a:.0f})"/>')
        elif kind < 0.85:
            conf.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{sz / 3:.1f}" fill="{col}" stroke="{OUT}" stroke-width="0.6"/>')
        else:
            L = rnd.uniform(18, 34)
            conf.append(f'<path d="M{x:.1f},{y:.1f} q{L / 4:.1f},{-L / 3:.1f} {L / 2:.1f},0 t{L / 2:.1f},0" fill="none" '
                        f'stroke="{col}" stroke-width="2.6" stroke-linecap="round" transform="rotate({a:.0f} {x:.1f} {y:.1f})" '
                        f'filter="url(#g)"/>')
    # a few sparkle bursts
    for (fx, fy, sz) in ((0.1, 0.2, 18), (0.88, 0.16, 22), (0.22, 0.55, 12), (0.76, 0.5, 14), (0.95, 0.75, 10)):
        x, y = vb[0] + fx * w, vb[1] + fy * h
        p = []
        for i in range(8):
            t = math.pi / 4 * i - math.pi / 2
            r = sz / 2 if i % 2 == 0 else sz * 0.13
            p.append((x + r * math.cos(t), y + r * math.sin(t)))
        conf.append(f'<polygon points="{fmt(p)}" fill="{WHITE}" filter="url(#g)"/>')
    gl = 3.0 * w / 300 * 0.45
    r = f'x="{vb[0]:.1f}" y="{vb[1]:.1f}" width="{w:.1f}" height="{h:.1f}"'
    defs = (f'<filter id="g" filterUnits="userSpaceOnUse" x="{vb[0]:.1f}" y="{vb[1]:.1f}" width="{w:.1f}" height="{h:.1f}">'
            f'<feGaussianBlur stdDeviation="{gl:.2f}" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="b"/>'
            f'<feMergeNode in="SourceGraphic"/></feMerge></filter>'
            f'<linearGradient id="sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#05070F"/>'
            f'<stop offset="1" stop-color="#151C38"/></linearGradient>'
            f'<radialGradient id="mid" cx="0.5" cy="0.42" r="0.42"><stop offset="0" stop-color="#2A1F55" stop-opacity="0.75"/>'
            f'<stop offset="1" stop-color="#2A1F55" stop-opacity="0"/></radialGradient>'
            f'<radialGradient id="vig" cx="0.5" cy="0.45" r="0.8"><stop offset="0.5" stop-color="#000" stop-opacity="0"/>'
            f'<stop offset="1" stop-color="#000" stop-opacity="0.55"/></radialGradient>' + ''.join(s.defs))
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{BW}" height="{BH}" viewBox="{vb[0]:.1f} {vb[1]:.1f} {w:.1f} {h:.1f}">'
           f'<defs>{defs}</defs><rect {r} fill="url(#sky)"/>' + '\n'.join(s.els)
           + f'<rect {r} fill="url(#mid)"/>' + ''.join(conf) + f'<rect {r} fill="url(#vig)"/></svg>')
    p = os.path.join(TMP, 'move_banner.svg')
    open(p, 'w').write(svg)
    out = os.path.join(OUTDIR, 'move_banner.png')
    run('rsvg-convert', '-w', str(BW), '-h', str(BH), p, '-o', out)
    run('magick', out, '-alpha', 'off', out)
    return out


# ============================================================ main
def compress(paths):
    pq = shutil.which('pngquant')
    for p in paths:
        if pq:
            subprocess.run([pq, '--force', '--skip-if-larger', '--quality=70-95', '--ext', '.png', p])
        elif os.path.basename(p) == 'move_banner.png':
            run('magick', p, '-strip', '-dither', 'FloydSteinberg', '-colors', '256', '-define', 'png:compression-level=9',
                'PNG8:' + p)
        else:
            run('magick', p, '-strip', '-define', 'png:compression-level=9', p)


def main():
    os.makedirs(OUTDIR, exist_ok=True)
    only = set(os.environ.get('ONLY', '').split(',')) - {''}
    want = lambda k: not only or k in only  # noqa: E731
    made = []
    for tier in TIERS:
        if want('cables') or want(tier):
            made += [cable_floor(tier, 'x'), cable_floor(tier, 'y'), cable_tray(tier)]
        if want('net_icons') or want(tier):
            s = Scene(glow=3.5)
            NET_ICONS[tier](s)
            made.append(icon(s, f'net_tier_{tier}'))
    for k, fn in PLANTS.items():
        if want('plants') or want(k):
            s = Scene(glow=3.0)
            fn(s)
            made.append(render(wrap_svg(s, VB2, 512), f'plant_{k}', 512))
        if want('cool_icons') or want(k):
            s = Scene(glow=3.5)
            COOL_ICONS[k](s)
            made.append(icon(s, f'cool_tier_{k}'))
    if want('move'):
        made += move_truck()
        made.append(move_boxes())
        made.append(move_dolly())
    if want('banner'):
        made.append(move_banner())
    if os.environ.get('NOCOMPRESS') != '1':
        compress(made)
    for p in made:
        print(p)
    shutil.rmtree(TMP, ignore_errors=True)


if __name__ == '__main__':
    main()
