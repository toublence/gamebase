"""Picks one take per line for one voice style (ASR-verified, most pitch movement), trims silence,
removes rumble and normalizes loudness, then writes the game's voice files and a manifest."""
import argparse
import json
import os

import numpy as np
import soundfile as sf

TARGET_RMS_DB = -17.0
EXACT = {"ko": {"good": "굿", "nice": "나이스", "yes": "예스", "woo": "우와", "bravo": "브라보", "yahoo": "야호", "wow": "와우"},
         "en": {"good": "good", "nice": "nice", "yes": "yes", "woo": "whoa", "bravo": "bravo", "yahoo": "yahoo", "wow": "wow"}}
PEAK_LIMIT_DB = -1.5


def highpass(x, sr, cutoff=90.0):
    a = np.exp(-2 * np.pi * cutoff / sr)
    y = np.zeros_like(x)
    prev_x = prev_y = 0.0
    for i, v in enumerate(x):
        prev_y = a * (prev_y + v - prev_x)
        prev_x = v
        y[i] = prev_y
    return y


def trim(x, sr, threshold_db=-38.0, pre=0.012, post=0.07):
    env = np.abs(x)
    limit = np.max(env) * 10 ** (threshold_db / 20)
    idx = np.where(env > limit)[0]
    start = max(0, idx[0] - int(pre * sr))
    end = min(len(x), idx[-1] + int(post * sr))
    y = x[start:end].copy()
    fade_in, fade_out = int(0.004 * sr), int(0.05 * sr)
    y[:fade_in] *= np.linspace(0, 1, fade_in)
    y[-fade_out:] *= np.linspace(1, 0, fade_out)
    return y


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--eval", required=True)
    ap.add_argument("--wavs", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--style", required=True)
    args = ap.parse_args()
    rows = json.load(open(args.eval))
    manifest = {}
    for lang in ["ko", "en"]:
        for key in sorted(set(r["key"] for r in rows)):
            takes = [r for r in rows if r["lang"] == lang and r["key"] == key and r["style"] == args.style and r["ok"]]
            if not takes:
                raise SystemExit(f"no verified take for {lang}/{key}")
            # Prefer takes the recognizer heard as exactly the line (nothing extra), then the liveliest.
            def exact(r):
                heard = " ".join("".join(ch for ch in r["asr"].lower() if ch.isalnum() or ch == " ").split())
                return heard.replace(" ", "") == EXACT[lang][key].replace(" ", "")

            best = max(takes, key=lambda r: (exact(r), r["f0_range_st"]))
            x, sr = sf.read(os.path.join(args.wavs, best["file"] + ".wav"))
            x = trim(highpass(x.astype(np.float64), sr), sr)
            voiced = x[np.abs(x) > np.max(np.abs(x)) * 0.05]
            gain = 10 ** (TARGET_RMS_DB / 20) / max(1e-9, np.sqrt(np.mean(voiced ** 2)))
            gain = min(gain, 10 ** (PEAK_LIMIT_DB / 20) / np.max(np.abs(x)))
            x = x * gain
            os.makedirs(os.path.join(args.out, lang), exist_ok=True)
            sf.write(os.path.join(args.out, lang, f"{key}.wav"), x.astype(np.float32), sr, subtype="PCM_16")
            manifest[f"{lang}/{key}"] = {"source_take": best["file"], "asr": best["asr"], "pitch_range_st": best["f0_range_st"],
                                         "seconds": round(len(x) / sr, 3),
                                         "peak_db": round(float(20 * np.log10(np.max(np.abs(x)))), 1)}
            print(lang, key, best["file"], manifest[f"{lang}/{key}"]["seconds"], "s")
    json.dump(manifest, open(os.path.join(args.out, "manifest.json"), "w"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
