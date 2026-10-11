"""Objective review of synthesized voice takes (no listening): ASR round trip with faster-whisper,
level, duration, silence, and pitch movement (autocorrelation F0)."""
import argparse
import glob
import json
import os
import re

import numpy as np
import soundfile as sf

EXPECT = {
    "ko": {"good": ["굿", "굳"], "nice": ["나이스"], "yes": ["예스", "yes"], "woo": ["우와", "와"], "bravo": ["브라보"],
           "yahoo": ["야호"], "wow": ["와우", "우와"]},
    "en": {"good": ["good"], "nice": ["nice"], "yes": ["yes"], "woo": ["whoa", "woah", "wow"], "bravo": ["bravo"],
           "yahoo": ["yahoo"], "wow": ["wow", "whoa", "woah"]},
}


def f0_track(x, sr, fmin=80, fmax=500):
    frame, hop = int(0.04 * sr), int(0.01 * sr)
    out = []
    for i in range(0, len(x) - frame, hop):
        w = x[i:i + frame] * np.hanning(frame)
        if np.sqrt(np.mean(w ** 2)) < 0.02:
            continue
        ac = np.correlate(w, w, "full")[frame - 1:]
        lo, hi = int(sr / fmax), int(sr / fmin)
        k = lo + int(np.argmax(ac[lo:hi]))
        if ac[k] > 0.35 * ac[0]:
            out.append(sr / k)
    return np.array(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--wavs", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--model", default="small")
    args = ap.parse_args()
    from faster_whisper import WhisperModel
    model = WhisperModel(args.model, device="cpu", compute_type="int8")
    rows = []
    for path in sorted(glob.glob(os.path.join(args.wavs, "*.wav"))):
        name = os.path.basename(path)[:-4]
        lang, rest = name.split("_", 1)
        key, style, take = rest.rsplit("_", 2)
        x, sr = sf.read(path)
        mono = x if x.ndim == 1 else x.mean(axis=1)
        n16 = int(len(mono) * 16000 / sr)
        audio16 = np.interp(np.linspace(0, len(mono) - 1, n16), np.arange(len(mono)), mono).astype(np.float32)
        audio16 = np.concatenate([np.zeros(4000, np.float32), audio16, np.zeros(4000, np.float32)])
        segments, _ = model.transcribe(audio16, language=lang, beam_size=5, vad_filter=False,
                                       condition_on_previous_text=False)
        text = " ".join(s.text for s in segments).strip()
        norm = re.sub(r"[^\w\s]", "", text.lower()).strip()
        norm_ko = norm.replace(" ", "")
        ok = any((e.replace(" ", "") in norm_ko) if lang == "ko" else (e in norm) for e in EXPECT[lang][key])
        voiced = np.where(np.abs(x) > 0.02)[0]
        lead = voiced[0] / sr if len(voiced) else 0.0
        trail = (len(x) - voiced[-1]) / sr if len(voiced) else 0.0
        f0 = f0_track(x, sr)
        rng = float(12 * np.log2(np.percentile(f0, 90) / np.percentile(f0, 10))) if len(f0) > 4 else 0.0
        body = x[voiced[0]:voiced[-1]] if len(voiced) > 1 else x
        rows.append({"file": name, "lang": lang, "key": key, "style": style, "take": int(take), "asr": text, "ok": bool(ok),
                     "dur": round(len(x) / sr, 3), "peak_db": round(float(20 * np.log10(np.max(np.abs(x)) + 1e-9)), 1),
                     "rms_db": round(float(20 * np.log10(np.sqrt(np.mean(body ** 2)) + 1e-9)), 1),
                     "lead": round(float(lead), 3), "trail": round(float(trail), 3),
                     "f0_med": round(float(np.median(f0)), 1) if len(f0) else 0.0, "f0_range_st": round(rng, 2)})
        print(name, "OK " if ok else "BAD", text, flush=True)
    json.dump(rows, open(args.out, "w"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
