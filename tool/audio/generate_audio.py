#!/usr/bin/env python3
"""Procedural audio for AI Lab Tycoon.

Synthesizes every sound effect and the background music loop from scratch
(oscillators, envelopes, filters, noise, a convolution reverb). No samples,
no third-party audio. Everything sits in A minor / C major so stings never
clash with the music.

Requirements: Python 3.10+, numpy, scipy, and ffmpeg (with libmp3lame) on PATH.

    python3 -m venv /tmp/audio-venv && /tmp/audio-venv/bin/pip install numpy scipy
    /tmp/audio-venv/bin/python tool/audio/generate_audio.py            # writes assets/audio/*.mp3
    /tmp/audio-venv/bin/python tool/audio/generate_audio.py --only click --keep-wav /tmp/wav

Output: 44.1 kHz MP3. SFX are mono, normalized to -3 dBFS peak. The music is
stereo, a sample-exact 32-bar loop at 90 BPM (85.33 s) whose reverb/delay
tail is wrapped around to the start, normalized to about -16 LUFS.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 44100
RNG = np.random.default_rng(1234)  # deterministic output


# --------------------------------------------------------------------------
# Building blocks
# --------------------------------------------------------------------------

def mtof(m: float) -> float:
    return 440.0 * 2 ** ((m - 69) / 12)


def n_of(dur: float) -> int:
    return int(round(dur * SR))


def _freq_arr(freq, n: int) -> np.ndarray:
    return np.broadcast_to(np.asarray(freq, dtype=float), (n,)).astype(float)


def _phase(freq, n: int, ph0: float = 0.0) -> np.ndarray:
    f = _freq_arr(freq, n)
    return (ph0 + np.cumsum(f) / SR) % 1.0


def sine(freq, n: int, ph0: float = 0.0) -> np.ndarray:
    return np.sin(2 * np.pi * _phase(freq, n, ph0))


def tri(freq, n: int, ph0: float = 0.0) -> np.ndarray:
    p = _phase(freq, n, ph0)
    return 2 * np.abs(2 * p - 1) - 1


def saw(freq, n: int, ph0: float = 0.0) -> np.ndarray:
    """Band-limited (polyBLEP) sawtooth."""
    f = _freq_arr(freq, n)
    dt = f / SR
    p = (ph0 + np.cumsum(dt)) % 1.0
    y = 2 * p - 1
    m = p < dt
    t = p[m] / dt[m]
    y[m] -= t + t - t * t - 1
    m = p > 1 - dt
    t = (p[m] - 1) / dt[m]
    y[m] -= t * t + t + t + 1
    return y


def square(freq, n: int, ph0: float = 0.0, width: float = 0.5) -> np.ndarray:
    return 0.5 * (saw(freq, n, ph0) - saw(freq, n, ph0 + width))


def noise(n: int) -> np.ndarray:
    return RNG.standard_normal(n)


def detuned(fn, freq, n: int, cents=(-7, 0, 7), **kw) -> np.ndarray:
    """Unison voices with small detune (a cheap chorus)."""
    out = np.zeros(n)
    for c in cents:
        out += fn(np.asarray(freq) * 2 ** (c / 1200), n, ph0=RNG.random(), **kw)
    return out / len(cents)


def adsr(n: int, a=0.005, d=0.1, s=0.7, r=0.1, curve=3.0) -> np.ndarray:
    """Attack/decay/sustain with the release living in the last r seconds."""
    t = np.arange(n) / SR
    dur = n / SR
    a = max(a, 1e-4)
    env = np.where(t < a, (t / a) ** 0.8,
                   s + (1 - s) * np.exp(-(t - a) * curve / max(d, 1e-4)))
    rs = max(dur - r, 0.0)
    rel = np.where(t < rs, 1.0, np.exp(-(t - rs) * 5.0 / max(r, 1e-4)))
    env = env * rel
    tail = min(n, n_of(0.004))
    if tail:
        env[-tail:] *= np.linspace(1, 0, tail)
    return env


def perc(n: int, tau: float, a: float = 0.002) -> np.ndarray:
    t = np.arange(n) / SR
    env = np.exp(-t / tau) * np.clip(t / max(a, 1e-4), 0, 1)
    tail = min(n, n_of(0.004))
    env[-tail:] *= np.linspace(1, 0, tail)
    return env


def butter(x: np.ndarray, fc, kind: str = "low", order: int = 2) -> np.ndarray:
    nyq = SR / 2
    if isinstance(fc, (tuple, list)):
        wn = [min(f / nyq, 0.99) for f in fc]
    else:
        wn = min(fc / nyq, 0.99)
    sos = signal.butter(order, wn, btype=kind, output="sos")
    return signal.sosfilt(sos, x, axis=-1)


def svf(x: np.ndarray, fc, q: float = 0.707, mode: str = "lp") -> np.ndarray:
    """Time-varying state-variable filter (TPT form). fc may be an array."""
    n = len(x)
    fcv = np.clip(_freq_arr(fc, n), 20, SR * 0.45)
    g = np.tan(np.pi * fcv / SR)
    k = 1.0 / q
    a1 = 1 / (1 + g * (g + k))
    a2 = g * a1
    a3 = g * a2
    xs, a1l, a2l, a3l = x.tolist(), a1.tolist(), a2.tolist(), a3.tolist()
    ic1 = ic2 = 0.0
    out = [0.0] * n
    want_bp = mode == "bp"
    for i in range(n):
        v3 = xs[i] - ic2
        v1 = a1l[i] * ic1 + a2l[i] * v3
        v2 = ic2 + a2l[i] * ic1 + a3l[i] * v3
        ic1 = 2 * v1 - ic1
        ic2 = 2 * v2 - ic2
        out[i] = v1 if want_bp else v2
    return np.asarray(out)


def ease(n: int, start: float, end: float, power: float = 1.0, expo: bool = True) -> np.ndarray:
    t = np.linspace(0, 1, n) ** power
    if expo:
        return start * (end / start) ** t
    return start + (end - start) * t


def reverb_ir(dur: float = 1.5, seed: int = 0, bright: float = 6000) -> np.ndarray:
    rng = np.random.default_rng(seed)
    n = n_of(dur)
    t = np.arange(n) / SR
    ir = rng.standard_normal(n) * np.exp(-t * 6.9 / dur)
    ir = butter(ir, bright, "low", 1)
    ir[: n_of(0.012)] = 0  # pre-delay
    return ir / np.sqrt(np.sum(ir ** 2))


def reverb(x: np.ndarray, wet: float = 0.2, dur: float = 1.2, seed: int = 0,
           bright: float = 6000) -> np.ndarray:
    ir = reverb_ir(dur, seed, bright)
    y = np.zeros(len(x) + len(ir) - 1)
    y[: len(x)] += x
    y += wet * signal.fftconvolve(x, ir) * 0.6
    return y


def place(buf: np.ndarray, x: np.ndarray, at: int, gain: float = 1.0) -> None:
    """Mix x into buf starting at sample `at` (buf may be 1-D or 2xN)."""
    if at >= buf.shape[-1]:
        return
    end = min(buf.shape[-1], at + x.shape[-1])
    buf[..., at:end] += gain * x[..., : end - at]


def finish_sfx(x: np.ndarray, dur: float | None = None, fade_in=0.001,
               fade_out=0.012) -> np.ndarray:
    if dur is not None:
        n = n_of(dur)
        x = np.pad(x, (0, max(0, n - len(x))))[:n]
    x = x - np.mean(x)  # no DC
    fi, fo = n_of(fade_in), n_of(fade_out)
    if fi:
        x[:fi] *= np.linspace(0, 1, fi)
    if fo:
        x[-fo:] *= np.linspace(1, 0, fo) ** 2
    peak = np.max(np.abs(x))
    return x * (10 ** (-3 / 20) / peak)


# --------------------------------------------------------------------------
# Sound effects (A minor / C major)
# --------------------------------------------------------------------------

def sfx_click() -> np.ndarray:
    n = n_of(0.04)
    t = np.arange(n) / SR
    f = 1500 + 900 * np.exp(-t / 0.004)
    body = sine(f, n) * perc(n, 0.006, 0.0005)
    thump = sine(420, n) * perc(n, 0.008, 0.0008) * 0.45
    tick = butter(noise(n), 3500, "high") * perc(n, 0.0015, 0.0002) * 0.25
    x = butter(body + thump + tick, 6500, "low")
    return finish_sfx(x, 0.04, fade_in=0.0005, fade_out=0.006)


def bell(freq: float, n: int, tau: float, bright: float = 1.0) -> np.ndarray:
    partials = [(1.0, 1.0, 1.0), (2.0, 0.35 * bright, 0.6),
                (3.01, 0.18 * bright, 0.4), (4.2, 0.08 * bright, 0.25),
                (5.43, 0.05 * bright, 0.18)]
    out = np.zeros(n)
    for ratio, amp, tdec in partials:
        out += amp * detuned(sine, freq * ratio, n, cents=(-3, 3)) * perc(n, tau * tdec, 0.002)
    return out


def sfx_purchase() -> np.ndarray:
    total = n_of(0.5)
    out = np.zeros(total)
    for at, m, dur, tau in [(0.0, 83, 0.07, 0.05), (0.055, 88, 0.24, 0.08)]:  # B5 -> E6
        n = n_of(dur)
        tone = detuned(sine, mtof(m), n, cents=(-5, 5)) + 0.25 * tri(mtof(m) * 2, n)
        tone += 0.12 * sine(mtof(m) * 2.76, n) * perc(n, tau * 0.5)
        place(out, tone * perc(n, tau, 0.001), n_of(at))
    out = reverb(out, wet=0.18, dur=0.5, seed=3)
    out = butter(out, 7000, "low")
    return finish_sfx(out, 0.24)


def sfx_upgrade() -> np.ndarray:
    total = n_of(0.9)
    out = np.zeros(total)
    for at, m in [(0.0, 76), (0.11, 81)]:  # E5 -> A5
        n = total - n_of(at)
        t = np.arange(n) / SR
        glide = mtof(m) * (1 - 0.02 * np.exp(-t / 0.01))
        place(out, bell(glide, n, 0.32), n_of(at))
    pad_n = n_of(0.6)
    pad = detuned(saw, mtof(57), pad_n) + detuned(saw, mtof(64), pad_n)
    pad = butter(pad, 1200, "low") * adsr(pad_n, 0.05, 0.2, 0.5, 0.3) * 0.12
    place(out, pad, 0)
    out = reverb(out, wet=0.22, dur=0.9, seed=4)
    return finish_sfx(out, 0.75, fade_out=0.06)


def sfx_training_start() -> np.ndarray:
    dur = 1.4
    n = n_of(dur)
    t = np.arange(n) / SR
    rise = np.clip(t / 1.0, 0, 1)
    # Air whoosh: band-passed noise sweeping upward.
    sweep = ease(n, 250, 2600, power=1.4)
    whoosh = svf(noise(n), sweep, q=1.2, mode="bp")
    whoosh *= np.sin(np.pi * np.clip(t / 1.25, 0, 1)) ** 1.5 * 0.9
    # Fans spinning up: blade-rate amplitude modulation on filtered noise + hum.
    blade = 6 + 64 * (1 - np.exp(-t / 0.45))
    am = 0.55 + 0.45 * sine(blade, n)
    fan = butter(noise(n), (400, 2200), "band") * am * rise * 0.6
    hum = butter(saw(blade * 2, n), 900, "low") * rise * 0.35
    # Synth riser A2 -> A3 with an opening filter.
    pitch = ease(n, mtof(45), mtof(57), power=0.8)
    riser = svf(detuned(saw, pitch, n), ease(n, 250, 2400, power=1.3), q=1.0)
    riser *= adsr(n, 0.3, 0.5, 0.8, 0.25) * 0.5
    out = whoosh + fan + hum + riser
    # Power-on chime at the top (A4 + E5).
    ping_n = n_of(0.4)
    ping = (bell(mtof(69), ping_n, 0.25, 0.6) + 0.6 * bell(mtof(76), ping_n, 0.25, 0.4)) * 0.45
    place(out, ping, n_of(0.95))
    out = butter(out, 40, "high")
    out = reverb(out, wet=0.15, dur=0.8, seed=5)
    return finish_sfx(out, dur, fade_in=0.01, fade_out=0.08)


def pluck(freq: float, n: int, tau: float) -> np.ndarray:
    x = detuned(tri, freq, n, cents=(-6, 6)) + 0.35 * sine(freq * 2, n) + 0.15 * saw(freq, n)
    return butter(x, 5000, "low") * perc(n, tau, 0.002)


def sfx_training_done() -> np.ndarray:
    total = n_of(1.3)
    out = np.zeros(total)
    for i, m in enumerate([72, 76, 79, 84]):  # C5 E5 G5 C6
        at = n_of(i * 0.075)
        tau = 0.5 if i == 3 else 0.22
        place(out, pluck(mtof(m), total - at, tau) * (0.8 + 0.07 * i), at)
    place(out, bell(mtof(91), n_of(0.6), 0.3, 0.3) * 0.18, n_of(0.3))  # G6 sparkle
    out = reverb(out, wet=0.25, dur=1.0, seed=6)
    return finish_sfx(out, 1.1, fade_out=0.15)


def brass(freqs, n: int, open_hz=3200, base_hz=900, a=0.02, d=0.25, s=0.75, r=0.12,
          vibrato=0.0) -> np.ndarray:
    t = np.arange(n) / SR
    vib = 1 + vibrato * np.clip((t - 0.25) / 0.3, 0, 1) * np.sin(2 * np.pi * 5.5 * t)
    x = np.zeros(n)
    for f in freqs:
        x += detuned(saw, f * vib, n, cents=(-8, 0, 8)) + 0.3 * square(f * vib, n)
    env = adsr(n, a, d, s, r)
    cutoff = base_hz + (open_hz - base_hz) * np.exp(-t / 0.12) * np.clip(t / a, 0, 1)
    cutoff = cutoff * (0.6 + 0.4 * env)
    return svf(x / len(freqs), cutoff, q=0.9) * env


def sfx_release() -> np.ndarray:
    total = n_of(1.8)
    out = np.zeros(total)
    for i, m in enumerate([67, 72, 76]):  # G4 C5 E5 pickups
        place(out, brass([mtof(m)], n_of(0.1), a=0.008, d=0.05, s=0.8, r=0.03) * 0.8, n_of(i * 0.11))
    hit = n_of(0.33)
    chord = brass([mtof(m) for m in (72, 76, 79, 84)], n_of(0.95), open_hz=4000, base_hz=1300,
                  a=0.015, d=0.3, s=0.7, r=0.4, vibrato=0.004)
    place(out, chord, hit)
    bn = n_of(0.6)
    boom = sine(ease(bn, 110, 48, 0.5), bn) * perc(bn, 0.16) * 0.7  # timpani-ish C
    place(out, boom, hit)
    cn = n_of(0.9)
    cym = butter(noise(cn), 6000, "high") * perc(cn, 0.25, 0.003) * 0.12
    place(out, cym, hit)
    out = reverb(out, wet=0.25, dur=1.0, seed=7)
    return finish_sfx(out, 1.42, fade_out=0.2)


def sfx_stunt_fail() -> np.ndarray:
    total = n_of(1.85)
    out = np.zeros(total)
    notes = [(0.0, 62, 0.27), (0.3, 61, 0.27), (0.6, 60, 0.27), (0.9, 59, 0.9)]  # D4 C#4 C4 B3
    for i, (at, m, dur) in enumerate(notes):
        n = n_of(dur)
        t = np.arange(n) / SR
        last = i == len(notes) - 1
        f = mtof(m) * np.ones(n)
        if last:
            f = f * (1 + 0.012 * np.sin(2 * np.pi * 5.0 * t) * np.clip(t / 0.15, 0, 1))
            f = f * (1 - 0.03 * np.clip((t - 0.4) / 0.5, 0, 1))
        x = detuned(saw, f, n, cents=(-6, 6)) + 0.5 * square(f, n, width=0.3)
        wah = 350 + 1300 * np.sin(np.pi * np.clip(t / (dur * (0.6 if last else 0.9)), 0, 1))
        if last:
            wah = 350 + 1300 * (0.5 + 0.5 * np.sin(2 * np.pi * 5.0 * t - np.pi / 2)) * np.exp(-t / 0.6)
        x = svf(x, wah, q=2.2) * adsr(n, 0.02, 0.2, 0.85, 0.18 if not last else 0.35)
        place(out, x, n_of(at))
    out = reverb(out, wet=0.15, dur=0.7, seed=8)
    return finish_sfx(out, 1.8, fade_out=0.12)


def sfx_era_up() -> np.ndarray:
    total = n_of(2.6)
    out = np.zeros(total)
    # Noise riser into the hit.
    rn = n_of(0.36)
    riser = svf(noise(rn), ease(rn, 400, 5000), q=1.5, mode="bp") * np.linspace(0, 1, rn) ** 2 * 0.35
    place(out, riser, 0)
    # Fast sparkling arpeggio up C major.
    for i, m in enumerate([72, 76, 79, 84, 88]):
        place(out, pluck(mtof(m), n_of(0.5), 0.18) * 0.55, n_of(i * 0.06))
    hit = n_of(0.36)
    # Big Cmaj9 pad swell.
    pn = n_of(1.9)
    pad = np.zeros(pn)
    for m in (60, 64, 67, 71, 74):
        pad += detuned(saw, mtof(m), pn, cents=(-10, -3, 4, 11))
    pad = butter(pad / 5, 2400, "low") * adsr(pn, 0.03, 0.6, 0.55, 0.9)
    place(out, pad * 0.75, hit)
    # Sub boom on C2/C3.
    bn = n_of(0.9)
    boom = (sine(ease(bn, 130, 65, 0.4), bn) + 0.4 * sine(mtof(36), bn)) * perc(bn, 0.3, 0.004)
    place(out, boom * 0.8, hit)
    # Shimmer: high bells with tremolo.
    sn = n_of(1.6)
    t = np.arange(sn) / SR
    shim = (bell(mtof(91), sn, 0.6, 0.4) + bell(mtof(96), sn, 0.5, 0.3)) * (0.7 + 0.3 * np.sin(2 * np.pi * 7 * t))
    place(out, shim * 0.22, hit + n_of(0.05))
    out = reverb(out, wet=0.35, dur=1.6, seed=9)
    return finish_sfx(out, 2.1, fade_out=0.35)


def drum_kick(n: int, punch: float = 1.0) -> np.ndarray:
    t = np.arange(n) / SR
    f = 45 + 75 * np.exp(-t / 0.04)
    k = sine(f, n) * perc(n, 0.22, 0.001)
    k += punch * 0.15 * butter(noise(n), 2500, "low") * perc(n, 0.004, 0.0005)
    return k


def drum_snare(n: int) -> np.ndarray:
    tone = sine(190, n) * perc(n, 0.05)
    nz = butter(noise(n), (1200, 7000), "band") * perc(n, 0.11, 0.001)
    return 0.5 * tone + 0.7 * nz


def sfx_rival_beaten() -> np.ndarray:
    total = n_of(1.9)
    out = np.zeros(total)
    stabs = [(0.0, (65, 69, 72)), (0.17, (67, 71, 74))]  # F, G
    for at, ch in stabs:
        x = brass([mtof(m) for m in ch], n_of(0.13), open_hz=3500, base_hz=1200,
                  a=0.006, d=0.06, s=0.7, r=0.04)
        place(out, x * 0.9, n_of(at))
        place(out, drum_snare(n_of(0.2)) * 0.35, n_of(at))
    hit = n_of(0.34)
    final = brass([mtof(m) for m in (57, 69, 73, 76)], n_of(1.05), open_hz=4200, base_hz=1400,
                  a=0.01, d=0.25, s=0.75, r=0.45, vibrato=0.005)  # A major (picardy)
    place(out, final, hit)
    place(out, drum_kick(n_of(0.5)) * 0.9, hit)
    place(out, drum_snare(n_of(0.3)) * 0.4, hit)
    cn = n_of(1.2)
    crash = butter(noise(cn), 4500, "high") * perc(cn, 0.35, 0.002) * 0.16
    place(out, crash, hit)
    out = reverb(out, wet=0.25, dur=1.1, seed=10)
    return finish_sfx(out, 1.6, fade_out=0.25)


def sfx_viral_alarm() -> np.ndarray:
    total = n_of(0.62)
    out = np.zeros(total)
    for at in (0.0, 0.22):
        n = n_of(0.15)
        t = np.arange(n) / SR
        bend = 2 ** ((-1 + np.clip(t / 0.02, 0, 1)) / 12)
        x = 0.0
        for m, amp in ((81, 1.0), (88, 0.55)):  # A5 + E6
            f = mtof(m) * bend
            x = x + amp * (detuned(sine, f, n, cents=(-4, 4)) + 0.3 * tri(f, n))
        x = butter(x, 3800, "low") * adsr(n, 0.004, 0.05, 0.8, 0.04)
        place(out, x, n_of(at))
    out = reverb(out, wet=0.15, dur=0.5, seed=11)
    return finish_sfx(out, 0.6, fade_out=0.08)


def sfx_error() -> np.ndarray:
    n = n_of(0.3)
    t = np.arange(n) / SR
    drop = 1 - 0.04 * np.clip(t / 0.25, 0, 1)
    x = detuned(saw, 110 * drop, n, cents=(-5, 5)) + 0.7 * saw(116.54 * drop, n) + 0.6 * sine(55 * drop, n)
    x = butter(x, 650, "low", 2) * adsr(n, 0.012, 0.12, 0.6, 0.08)
    x *= 0.85 + 0.15 * np.sin(2 * np.pi * 28 * t)
    return finish_sfx(x, 0.3, fade_in=0.004, fade_out=0.03)


# --------------------------------------------------------------------------
# Music loop: chill synthwave, A minor, 90 BPM, 32 bars
# --------------------------------------------------------------------------

BPM = 90
BEAT = SR * 60 // BPM  # 29400 samples, exact
BARS = 32
LOOP = BARS * 4 * BEAT
S16 = BEAT // 4

# (bass midi, pad voicing) per 2-bar slot
CHORDS = {
    "Am7": (45, (57, 60, 64, 67)),
    "Fmaj7": (41, (53, 57, 60, 64)),
    "C": (48, (55, 60, 64, 67)),
    "G": (43, (55, 59, 62, 67)),
    "Dm7": (50, (57, 60, 62, 65)),
    "Em7": (40, (55, 59, 62, 64)),
}
PROG = ["Am7", "Fmaj7", "C", "G", "Am7", "Fmaj7", "Dm7", "Em7"] * 2  # 16 slots x 2 bars

LEAD = [  # (beat, length in beats, midi) for bars 16-23
    (0, 1.5, 76), (1.5, 0.5, 74), (2, 1, 72), (3, 1, 69), (4, 3, 72),
    (8, 1.5, 72), (9.5, 0.5, 74), (10, 1, 76), (11, 1, 77), (12, 3, 76),
    (16, 1.5, 79), (17.5, 0.5, 76), (18, 1, 74), (19, 1, 72), (20, 3, 76),
    (24, 1.5, 74), (25.5, 0.5, 72), (26, 1, 71), (27, 1, 67), (28, 3.5, 69),
]


def chord_at_bar(bar: int):
    return CHORDS[PROG[(bar // 2) % len(PROG)]]


def arp_cutoff(bar: float) -> float:
    """Arp brightness: opens over bars 0-8, closes over bars 26-32 (matches at the wrap)."""
    if bar < 8:
        return 900 + 1700 * (bar / 8)
    if bar >= 26:
        return 2600 - 1700 * ((bar - 26) / 6)
    return 2600


def render_music() -> np.ndarray:
    tail = 5 * SR
    L = LOOP + tail
    pad_bus = np.zeros((2, L))
    arp_bus = np.zeros((2, L))
    lead_bus = np.zeros((2, L))
    bass_bus = np.zeros(L)
    drum_bus = np.zeros((2, L))
    snare_send = np.zeros(L)

    # Pads: detuned saws, different detune per side for width.
    slot_len = 8 * BEAT
    for slot in range(BARS // 2):
        _, voicing = chord_at_bar(slot * 2)
        n = slot_len + n_of(1.6)
        for ch, cents in ((0, (-9, -2, 6)), (1, (-6, 3, 10))):
            x = np.zeros(n)
            for m in voicing:
                x += detuned(saw, mtof(m), n, cents=cents)
            x = butter(x / len(voicing), 2200, "low", 2)
            x *= adsr(n, 0.7, 1.0, 0.85, 1.6)
            place(pad_bus[ch], x, slot * slot_len, 0.32)

    # Bass: soft round root on a gentle synthwave pattern.
    for bar in range(BARS):
        root, _ = chord_at_bar(bar)
        for beat, length, g in ((0, 1.0, 1.0), (1.5, 0.45, 0.6), (2, 1.0, 0.85), (3.5, 0.45, 0.6)):
            n = int(length * BEAT)
            f = mtof(root)
            x = 0.8 * sine(f, n) + 0.5 * butter(saw(f, n), 700, "low") + 0.3 * sine(2 * f, n)
            x *= adsr(n, 0.008, 0.25, 0.65, 0.08)
            place(bass_bus, x, bar * 4 * BEAT + int(beat * BEAT), 0.24 * g)

    # Arp: 16ths over chord tones, filtered per section, ping-pong delay later.
    pattern = [0, 1, 2, 3, 2, 1, 0, 1, 0, 1, 2, 3, 4, 3, 2, 1]
    for bar in range(BARS):
        _, voicing = chord_at_bar(bar)
        tones = [m + 12 for m in voicing] + [voicing[0] + 24]
        for step, idx in enumerate(pattern):
            n = n_of(0.45)
            f = mtof(tones[idx])
            x = 0.6 * square(f, n, width=0.35) + 0.4 * tri(f * 1.003, n)
            x = butter(x, arp_cutoff(bar + step / 16), "low", 2) * perc(n, 0.11, 0.002)
            vel = 1.0 if step % 4 == 0 else (0.75 if step % 2 == 0 else 0.6)
            pan = 0.5 + 0.18 * np.sin(2 * np.pi * (bar * 16 + step) / 32)
            at = bar * 4 * BEAT + step * S16
            place(arp_bus[0], x, at, 0.2 * vel * (1 - pan) * 2)
            place(arp_bus[1], x, at, 0.2 * vel * pan * 2)

    # Lead: soft sine/triangle with delayed vibrato, bars 16-23.
    for beat, length, m in LEAD:
        n = int(length * BEAT) + n_of(0.3)
        t = np.arange(n) / SR
        f = mtof(m) * (1 + 0.006 * np.sin(2 * np.pi * 5.2 * t) * np.clip((t - 0.2) / 0.4, 0, 1))
        x = sine(f, n) + 0.3 * tri(f, n) + 0.1 * sine(2 * f, n)
        x = butter(x, 3000, "low") * adsr(n, 0.04, 0.3, 0.75, 0.3)
        at = 16 * 4 * BEAT + int(beat * BEAT)
        place(lead_bus[0], x, at, 0.2)
        place(lead_bus[1], x, at, 0.18)

    # Drums: soft kick, brushed snare, swung hats.
    kick_times = []
    for bar in range(BARS):
        b0 = bar * 4 * BEAT
        for beat in (0, 2):
            kick_times.append(b0 + beat * BEAT)
            place(drum_bus, np.tile(drum_kick(n_of(0.45), 0.8), (2, 1)), b0 + beat * BEAT, 0.3)
        if bar % 4 == 3:  # little pickup kick at the end of each phrase
            kick_times.append(b0 + int(3.5 * BEAT))
            place(drum_bus, np.tile(drum_kick(n_of(0.45), 0.8), (2, 1)), b0 + int(3.5 * BEAT), 0.18)
        for beat in (1, 3):
            s = drum_snare(n_of(0.3))
            place(drum_bus, np.tile(s, (2, 1)), b0 + beat * BEAT, 0.16)
            place(snare_send, s, b0 + beat * BEAT, 0.16)
        for e in range(8):
            off = e % 2 == 1
            at = b0 + e * (BEAT // 2) + (int(0.09 * BEAT) if off else 0)  # swing
            hn = n_of(0.06)
            h = butter(butter(noise(hn), 7000, "high"), 11000, "low") * perc(hn, 0.018 if not off else 0.026, 0.0005)
            pan = 0.42 if off else 0.58
            g = 0.09 if off else 0.06
            place(drum_bus[0], h, at, g * (1 - pan) * 2)
            place(drum_bus[1], h, at, g * pan * 2)

    # Sidechain-style pump on pads and arp.
    duck = np.ones(L)
    t_rel = np.arange(BEAT * 2) / SR
    dip = 1 - 0.35 * np.exp(-t_rel / 0.13)
    for kt in kick_times:
        end = min(L, kt + len(dip))
        duck[kt:end] = np.minimum(duck[kt:end], dip[: end - kt])
    pad_bus *= duck
    arp_bus *= duck

    # Ping-pong dotted-eighth delay on the arp + lead.
    dly = 3 * S16
    send = arp_bus.sum(axis=0) * 0.5 + lead_bus.sum(axis=0) * 0.4
    echo = np.zeros((2, L))
    g = 0.38
    for k in range(1, 9):
        shifted = np.zeros(L)
        shifted[k * dly:] = send[: L - k * dly] * g ** k
        echo[(k - 1) % 2] += shifted
    echo = butter(butter(echo, 3500, "low"), 250, "high")

    # Stereo reverb send.
    rev_in = (pad_bus.sum(axis=0) * 0.35 + arp_bus.sum(axis=0) * 0.3 + lead_bus.sum(axis=0) * 0.4
              + snare_send * 0.9)
    rev = np.vstack([signal.fftconvolve(rev_in, reverb_ir(3.0, s, 5000))[:L] for s in (21, 22)])

    mix = (pad_bus + arp_bus + lead_bus + drum_bus + bass_bus[None, :]
           + 0.55 * echo + 0.45 * rev)

    # Wrap everything that rings past the loop point back onto the start.
    looped = mix[:, :LOOP].copy()
    spill = mix[:, LOOP:]
    looped[:, : spill.shape[1]] += spill

    # Master EQ applied circularly (filter 3 copies, keep the middle) so no seam.
    tiled = np.tile(looped, (1, 3))
    tiled = butter(tiled, 28, "high", 2)
    tiled = butter(tiled, 13000, "low", 2)
    looped = tiled[:, LOOP: 2 * LOOP]
    looped /= np.max(np.abs(looped))
    return looped


# --------------------------------------------------------------------------
# Output
# --------------------------------------------------------------------------

def soft_limit(x: np.ndarray, knee: float, ceiling: float) -> np.ndarray:
    """Transparent below `knee`, tanh-rounded above it, never exceeding `ceiling`."""
    a = np.abs(x)
    over = a > knee
    y = x.copy()
    y[over] = np.sign(x[over]) * (knee + (ceiling - knee) * np.tanh((a[over] - knee) / (ceiling - knee)))
    return y


def write_wav(path: Path, x: np.ndarray) -> None:
    data = x.T if x.ndim == 2 else x
    wavfile.write(path, SR, np.clip(data, -1, 1).astype(np.float32))


def measure_loudness(path: Path) -> tuple[float, float]:
    r = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", str(path), "-af",
                        "loudnorm=print_format=json", "-f", "null", "-"],
                       capture_output=True, text=True)
    blob = re.search(r"\{[^{}]*\"input_i\"[^{}]*\}", r.stderr, re.S)
    d = json.loads(blob.group(0))
    return float(d["input_i"]), float(d["input_tp"])


def encode_mp3(wav: Path, mp3: Path, stereo: bool, kbps: int) -> None:
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(wav),
                    "-ac", "2" if stereo else "1", "-ar", str(SR), "-c:a", "libmp3lame",
                    "-b:a", f"{kbps}k", "-map_metadata", "-1", str(mp3)], check=True)


SFX = {
    "click": sfx_click,
    "purchase": sfx_purchase,
    "upgrade": sfx_upgrade,
    "trainingStart": sfx_training_start,
    "trainingDone": sfx_training_done,
    "release": sfx_release,
    "stuntFail": sfx_stunt_fail,
    "eraUp": sfx_era_up,
    "rivalBeaten": sfx_rival_beaten,
    "viralAlarm": sfx_viral_alarm,
    "error": sfx_error,
}


def main() -> None:
    repo = Path(__file__).resolve().parents[2]
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", type=Path, default=repo / "assets" / "audio")
    ap.add_argument("--keep-wav", type=Path, help="also keep the intermediate WAVs here")
    ap.add_argument("--only", nargs="*", help="names to render (default: all + music_loop)")
    ap.add_argument("--music-lufs", type=float, default=-16.0)
    args = ap.parse_args()
    if not shutil.which("ffmpeg"):
        raise SystemExit("ffmpeg not found on PATH")

    args.out.mkdir(parents=True, exist_ok=True)
    wav_dir = args.keep_wav or Path(tempfile.mkdtemp())
    wav_dir.mkdir(parents=True, exist_ok=True)
    wanted = set(args.only) if args.only else set(SFX) | {"music_loop"}

    for name, fn in SFX.items():
        if name not in wanted:
            continue
        x = fn()
        wav = wav_dir / f"{name}.wav"
        write_wav(wav, x)
        encode_mp3(wav, args.out / f"{name}.mp3", stereo=False, kbps=128)
        print(f"{name:14s} {len(x) / SR:5.2f}s")

    if "music_loop" in wanted:
        x = render_music()
        wav = wav_dir / "music_loop.wav"
        ceiling, knee = 10 ** (-1.5 / 20), 10 ** (-7.5 / 20)
        x = x * 0.5
        for _ in range(3):  # converge on the LUFS target through the soft limiter
            write_wav(wav, x)
            lufs, _tp = measure_loudness(wav)
            x = soft_limit(x * 10 ** ((args.music_lufs - lufs) / 20), knee, ceiling)
        write_wav(wav, x)
        lufs, tp = measure_loudness(wav)
        encode_mp3(wav, args.out / "music_loop.mp3", stereo=True, kbps=112)
        print(f"music_loop     {len(x[0]) / SR:5.2f}s  {lufs:.1f} LUFS  TP {tp:.1f} dBTP")


if __name__ == "__main__":
    main()
