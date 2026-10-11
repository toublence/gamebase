#!/usr/bin/env python3
"""Objective checks for Outtap audio (no listening involved — subjective review is still needed).

Reports per effect: duration, peak/RMS dBFS, spectral centroid and share of energy above 4 kHz
(harshness proxy), clipped samples. Simulates the in-game mixes that stack sounds (a fast streak
of slides at the game's gains, a collision with a lost heart) and reports their peak. Decodes the
music loop and measures the loop seam (sample jump and level change across the wrap point) and the
music/effect level balance at default volumes.
Usage: python3 tools/analyze_audio.py
"""
from pathlib import Path
import cmath
import math
import struct
import subprocess
import wave

ROOT = Path(__file__).resolve().parents[1]
AUDIO = ROOT / "assets/audio"


def read_wav(path):
    with wave.open(str(path)) as w:
        rate = w.getframerate()
        data = w.readframes(w.getnframes())
    return [s / 32768.0 for s in struct.unpack("<%dh" % (len(data) // 2), data)], rate


def db(x):
    return 20 * math.log10(max(x, 1e-9))


def rms(xs):
    return math.sqrt(sum(x * x for x in xs) / max(1, len(xs)))


def spectrum_stats(xs, rate, n=1024):
    """Spectral centroid and share of energy above 4 kHz in the loudest Hann window (plain DFT)."""
    if len(xs) < n:
        xs = xs + [0.0] * (n - len(xs))
    best, start = -1.0, 0
    for i in range(0, len(xs) - n + 1, n // 4):
        e = sum(v * v for v in xs[i:i + n])
        if e > best:
            best, start = e, i
    window = [xs[start + i] * (0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1))) for i in range(n)]
    total = weighted = high = 0.0
    for k in range(1, n // 2):
        w = cmath.exp(-2j * math.pi * k / n)
        acc, z = 0j, 1 + 0j
        for v in window:
            acc += v * z
            z *= w
        power = abs(acc) ** 2
        f = k * rate / n
        total += power
        weighted += f * power
        if f > 4000:
            high += power
    total = total or 1e-12
    return weighted / total, high / total


def resample(xs, pitch):
    out, t = [], 0.0
    while t < len(xs) - 1:
        i = int(t)
        f = t - i
        out.append(xs[i] * (1 - f) + xs[i + 1] * f)
        t += pitch
    return out


def place(mixbuf, xs, at, gain):
    for i, v in enumerate(xs):
        j = at + i
        if j >= len(mixbuf):
            mixbuf.extend([0.0] * (j - len(mixbuf) + 1))
        mixbuf[j] += v * gain


def main():
    print("Effects (peak / RMS dBFS, centroid, energy > 4 kHz, clipped samples):")
    sounds = {}
    for path in sorted(AUDIO.glob("*.wav")):
        xs, rate = read_wav(path)
        sounds[path.stem] = (xs, rate)
        active = [v for v in xs if abs(v) > 0.003] or xs
        centroid, high = spectrum_stats(xs, rate)
        clipped = sum(1 for v in xs if abs(v) >= 0.999)
        print(f"  {path.name:16s} {len(xs)/rate:5.2f}s  peak {db(max(abs(v) for v in xs)):6.1f}  rms {db(rms(active)):6.1f}"
              f"  centroid {centroid:6.0f} Hz  >4k {high*100:5.1f}%  clipped {clipped}")
    sfx_bus = 0.8  # default sfx_volume setting
    # Fast streak: 8 slides 60 ms apart (above the 34 ms same-sound throttle), climbing the scale.
    steps = [0, 2, 4, 7, 9, 12, 14, 14]
    rate = sounds["slide"][1]
    buf = []
    for i, st in enumerate(steps):
        name = "slide_long" if i % 3 == 2 else "slide"
        place(buf, resample(sounds[name][0], 2 ** (st / 12)), int(i * 0.06 * rate), 10 ** (-7 / 20) * sfx_bus)
        place(buf, sounds["tap"][0], int((i * 0.06 - 0.05) * rate) if i else 0, 10 ** (-16 / 20) * sfx_bus)
    print(f"Fast streak mix peak: {db(max(abs(v) for v in buf)):.1f} dBFS (must stay below 0)")
    buf = []
    place(buf, sounds["bump"][0], 0, 10 ** (-11 / 20) * sfx_bus)
    place(buf, sounds["life"][0], 0, 10 ** (-13 / 20) * sfx_bus)
    print(f"Collision + heart mix peak: {db(max(abs(v) for v in buf)):.1f} dBFS")
    slide_rms = rms([v for v in sounds["slide"][0] if abs(v) > 0.003]) * 10 ** (-7 / 20) * sfx_bus
    bump_rms = rms([v for v in sounds["bump"][0] if abs(v) > 0.003]) * 10 ** (-11 / 20) * sfx_bus
    print(f"Collision vs slide loudness: {db(bump_rms) - db(slide_rms):+.1f} dB (collision should not be louder)")
    # A big moment stacks: the last slide, the clear fanfare, the golden chime and the wow sweep.
    buf = []
    place(buf, sounds["slide_long"][0], 0, 10 ** (-7 / 20) * sfx_bus)
    place(buf, sounds["gold"][0], int(0.1 * rate), 10 ** (-9 / 20) * sfx_bus)
    place(buf, sounds["clear_hard"][0], int(0.3 * rate), 10 ** (-6 / 20) * sfx_bus)
    place(buf, sounds["wow"][0], int(0.35 * rate), 10 ** (-8 / 20) * sfx_bus)
    print(f"HARD clear stack peak (before the master limiter): {db(max(abs(v) for v in buf)):.1f} dBFS")
    for name in ["music_calm", "music_tense", "music_hard"]:
        music = AUDIO / f"{name}.ogg"
        raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", str(music), "-f", "s16le", "-ac", "1", "-"],
                             capture_output=True, check=True).stdout
        xs = [s / 32768.0 for s in struct.unpack("<%dh" % (len(raw) // 2), raw)]
        seg = int(len(xs) * 0.004)
        head, tail = xs[:seg], xs[-seg:]
        jump = abs(xs[0] - xs[-1])
        typical_step = sum(abs(xs[i + 1] - xs[i]) for i in range(0, len(xs) - 1, 97)) / (len(xs) / 97)
        print(f"{name}: {len(xs)} samples, peak {db(max(abs(v) for v in xs)):.1f} dBFS, rms {db(rms(xs[::7])):.1f} dBFS")
        print(f"  loop seam: sample jump {jump:.4f} vs typical step {typical_step:.4f}; level first/last 0.2 s"
              f" {db(rms(head)):.1f} / {db(rms(tail)):.1f} dBFS")
        # The seam is a bar start, where notes begin; compare it with the other 15 bar starts.
        bar = len(xs) // 16
        onsets = sorted(max(abs(xs[k * bar + d] - xs[k * bar + d - 1]) for d in range(0, 8)) for k in range(1, 16))
        print(f"  bar-start steps elsewhere (first 8 samples): median {onsets[len(onsets) // 2]:.4f}, max {onsets[-1]:.4f}")
        music_level = rms(xs[::7]) * 0.45  # default music_volume
        print(f"  balance at defaults: music {db(music_level):.1f} dBFS rms vs slide {db(slide_rms):.1f} dBFS rms"
              f" ({db(slide_rms) - db(music_level):+.1f} dB effects over music)")


if __name__ == "__main__":
    main()
