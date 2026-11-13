#!/usr/bin/env python3
"""Icons for the upgrades added with the six-era expansion (up_<id>.png,
512x512, transparent). Same isometric toolkit and palette as the tiles.

Usage (from repo root):
    python3 tool/art/generate_upgrade_icons.py [out_dir]   # default: assets/images
Needs: rsvg-convert.
"""
import math
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from iso import *  # noqa: E402,F403

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
OUT = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.join(ROOT, 'assets', 'images')
TMP = tempfile.mkdtemp(prefix='up_')
PINK = '#FF6FD8'
VIOLET = '#B07CFF'


def save(s, name):
    p = os.path.join(TMP, name + '.svg')
    open(p, 'w').write(s.svg(pad=0.1, size=512))
    out = os.path.join(OUT, f'up_{name}.png')
    subprocess.run(['rsvg-convert', '-w', '512', '-h', '512', p, '-o', out], check=True)
    print('wrote', out)


def plate(s, color='#2E3B6B'):
    return s.box(0, 0, 0, 100, 100, 6, color=color)


def books_papers():
    s = Scene(glow=3.5)
    cols = ['#C44B6A', '#3D8BFF', '#2FAE7E', '#E0A040', '#8E6BD8']
    for i, c in enumerate(cols):
        s.box(10 + (i % 2) * 3, 30 - (i % 2) * 2, i * 9, 52, 38, 8, color=c, top=shade('#EADFC8', -0.05 * i))
        # page edges on the spine side
        b = (10 + (i % 2) * 3, 30 - (i % 2) * 2, i * 9, 52, 38, 8)
        s.frect(b, 'right', 0.04, 0.3, 0.96, 0.7, '#F4EEDD')
    # a paper sheet with a figure and text lines, propped in front
    pb = s.box(62, 58, 0, 30, 2, 44, color='#E8EEF8', top='#FFFFFF', right='#B9C4D8')
    for k in range(5):
        s.fline(pb, 'left', [(0.12, 0.15 + k * 0.08), (0.88 - (k % 2) * 0.2, 0.15 + k * 0.08)], '#55658F', sw=2)
    s.fline(pb, 'left', [(0.14, 0.86), (0.35, 0.66), (0.55, 0.74), (0.86, 0.56)], GREEN, sw=3, glow=True)
    save(s, 'books_papers')


def chinchilla_scaling():
    s = Scene(glow=3.5)
    b = plate(s)
    # a vertical chart panel: loss vs model size at fixed compute (a U curve)
    p = s.box(10, 6, 6, 80, 4, 70, color='#1A2242', top='#2E3B6B')
    s.fline(p, 'left', [(0.08, 0.9), (0.94, 0.9)], SILVER, sw=2)
    s.fline(p, 'left', [(0.08, 0.1), (0.08, 0.9)], SILVER, sw=2)
    pts = []
    for i in range(21):
        u = 0.12 + i * 0.04
        v = 0.72 - 2.6 * (u - 0.5) ** 2
        pts.append((u, v))
    s.fline(p, 'left', pts, CYAN, sw=4, glow=True)
    s.fcircle(p, 'left', 0.5, 0.72, 0.05, 0.05, GREEN, glow=True)
    s.fline(p, 'left', [(0.5, 0.77), (0.5, 0.9)], GREEN, sw=2, glow=True, opacity=0.6)
    # tokens vs params: a small and a big block on the plate
    s.box(16, 56, 6, 16, 16, 10, color=AMBER)
    s.box(56, 52, 6, 28, 26, 18, color='#3D8BFF')
    save(s, 'chinchilla_scaling')


def zero_sharding():
    s = Scene(glow=3.5)
    plate(s)
    # one model split into four shards, one per GPU, with a thin ring link
    cols = [GREEN, CYAN, AMBER, PINK]
    pos = [(12, 12), (54, 12), (12, 54), (54, 54)]
    for (x, y), c in zip(pos, cols):
        g = s.box(x, y, 6, 34, 34, 10, color='#2E3B6B')
        s.frect(g, 'left', 0.1, 0.3, 0.9, 0.7, shade(c, -0.3), glow=True, opacity=0.8)
        sh = s.box(x + 7, y + 7, 16, 20, 20, 14, color=c, top=shade(c, 0.35))
    s.line3([(29, 29, 34), (71, 29, 34), (71, 71, 34), (29, 71, 34), (29, 29, 34)], WHITE, sw=2, glow=True, opacity=0.8, dash='6 5')
    save(s, 'zero_sharding')


def paged_attention():
    s = Scene(glow=3.5)
    b = plate(s)
    # fixed-size KV pages in a page table: some in use by different requests
    use = {(0, 0): GREEN, (1, 0): GREEN, (3, 0): CYAN, (0, 1): CYAN, (2, 1): GREEN,
           (3, 1): PINK, (1, 2): PINK, (2, 2): CYAN, (0, 3): GREEN, (2, 3): PINK, (3, 3): CYAN}
    for i in range(4):
        for j in range(4):
            c = use.get((i, j))
            x, y = 8 + i * 22, 8 + j * 22
            if c:
                s.box(x, y, 6, 18, 18, 8, color=shade(c, -0.35), top=c, glow=False)
            else:
                s.box(x, y, 6, 18, 18, 2, color='#1A2242')
    save(s, 'paged_attention')


def disaggregated_serving():
    s = Scene(glow=3.5)
    plate(s, color='#26315C')
    # prefill pool (compute-bound, cyan) and decode pool (memory-bound, green)
    for k in range(3):
        a = s.box(8, 60, 6 + k * 14, 32, 32, 12, color='#2E3B6B')
        s.frect(a, 'left', 0.1, 0.35, 0.9, 0.65, CYAN, glow=True)
        s.frect(a, 'right', 0.1, 0.35, 0.9, 0.65, shade(CYAN, -0.3), glow=True)
    for k in range(3):
        d = s.box(60, 8, 6 + k * 14, 32, 32, 12, color='#2E3B6B')
        s.frect(d, 'left', 0.1, 0.35, 0.9, 0.65, GREEN, glow=True)
        s.frect(d, 'right', 0.1, 0.35, 0.9, 0.65, shade(GREEN, -0.3), glow=True)
    # KV cache handed from prefill to decode
    a0, a1 = iso(34, 56, 50), iso(66, 30, 50)
    s.arrow(a0[0], a0[1], a1[0], a1[1], color=AMBER, sw=6)
    save(s, 'disaggregated_serving')


def photonic_compute():
    # speculative: a photonic chip, laser light fanning through an
    # interferometer mesh (the matmul) into detectors
    s = Scene(glow=3.5)
    chip = s.box(6, 6, 0, 88, 88, 10, color='#202A55', top='#1A2242')
    # the mesh: diamond lattice of waveguides on the die
    for k in range(4):
        v = 0.2 + k * 0.2
        s.fline(chip, 'top', [(0.12, v), (0.88, v)], shade(CYAN, -0.45), sw=2)
    for i in range(3):
        u0 = 0.2 + i * 0.22
        for k in range(3):
            v0 = 0.2 + k * 0.2
            s.fline(chip, 'top', [(u0, v0), (u0 + 0.22, v0 + 0.2)], VIOLET, sw=2.4, glow=True)
            s.fline(chip, 'top', [(u0, v0 + 0.2), (u0 + 0.22, v0)], CYAN, sw=2.4, glow=True)
    # lasers in on the left edge, detectors out on the right
    for k, c in enumerate((PINK, CYAN, VIOLET, PINK)):
        v = 0.2 + k * 0.2
        s.fline(chip, 'top', [(0.0, v), (0.14, v)], c, sw=4, glow=True)
        px, py = Scene.fpt(chip, 'top', 0.9, v)
        s.ellipse2(px, py, 4.5, 3, WHITE, stroke=OUT, sw=1, glow=True)
    lx, ly = Scene.fpt(chip, 'top', 0.0, 0.5)
    s.sparkle(lx - 6, ly - 4, 22, WHITE)
    save(s, 'photonic_compute')


def superconducting_logic():
    # speculative: a niobium chip on a cold stage, frost and a flux quantum
    s = Scene(glow=3.5)
    stage = s.cyl(50, 50, 0, 46, 10, color='#8FB3D9', top='#DCEFFF')
    chip = s.box(28, 28, 10, 44, 44, 6, color='#4A5470', top='#2E3B6B')
    for k in range(3):
        v = 0.25 + k * 0.25
        s.fline(chip, 'top', [(0.1, v), (0.9, v)], '#9EC4E6', sw=2)
        s.fline(chip, 'top', [(v, 0.1), (v, 0.9)], '#9EC4E6', sw=2)
    # a single flux quantum: a glowing ring hopping along the line
    s.fcircle(chip, 'top', 0.5, 0.5, 0.14, 0.14, 'none', stroke=CYAN, sw=3, glow=True)
    s.fcircle(chip, 'top', 0.5, 0.5, 0.05, 0.05, WHITE, stroke=None, glow=True)
    # frost on the cold stage
    for (x, y) in ((22, 74), (74, 22), (78, 70)):
        px, py = iso(x, y, 10)
        s.sparkle(px, py, 13, WHITE)
    tx, ty = iso(50, 50, 34)
    s.sparkle(tx, ty, 18, '#BFEFFF')
    save(s, 'superconducting_logic')


if __name__ == '__main__':
    if not shutil.which('rsvg-convert'):
        sys.exit('missing rsvg-convert')
    os.makedirs(OUT, exist_ok=True)
    only = set(os.environ.get('ONLY', '').split(',')) - {''}
    for fn in (books_papers, chinchilla_scaling, zero_sharding, paged_attention, disaggregated_serving,
               photonic_compute, superconducting_logic):
        if not only or fn.__name__ in only:
            fn()
    shutil.rmtree(TMP, ignore_errors=True)
