"""Synthesizes Outtap's short voice cheers with Supertone Supertonic 2 (ONNX, offline).

Model: Supertone/supertonic-2 (BigScience OpenRAIL-M; Licensor claims no rights in the output; the
output must be disclosed as machine generated). Code: supertone-inc/supertonic helper (MIT).
Every take is seeded, so the same command reproduces the same files.
"""
import argparse
import os
import sys

import numpy as np
import soundfile as sf

LINES = {
    "ko": {"good": "굿!", "nice": "나이스!", "yes": "예스!", "woo": "우와!", "bravo": "브라보!", "yahoo": "야호!", "wow": "와우!"},
    "en": {"good": "Good!", "nice": "Nice!", "yes": "Yes!", "woo": "Whoa!", "bravo": "Bravo!", "yahoo": "Yahoo!", "wow": "Wow!"},
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--code", required=True)
    ap.add_argument("--models", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--styles", nargs="+", default=["F1", "F2", "F3", "F4", "F5", "M1", "M2", "M3", "M4", "M5"])
    ap.add_argument("--langs", nargs="+", default=["ko", "en"])
    ap.add_argument("--takes", type=int, default=2)
    ap.add_argument("--steps", type=int, default=16)
    ap.add_argument("--speed", type=float, default=1.0)
    args = ap.parse_args()
    sys.path.insert(0, args.code)
    from helper import load_text_to_speech, load_voice_style  # noqa: E402

    tts = load_text_to_speech(os.path.join(args.models, "onnx"))
    os.makedirs(args.out, exist_ok=True)
    for style_name in args.styles:
        style = load_voice_style([os.path.join(args.models, "voice_styles", f"{style_name}.json")])
        for lang in args.langs:
            for key, text in LINES[lang].items():
                for take in range(args.takes):
                    np.random.seed(7919 * (take + 1) + sum(map(ord, style_name + lang + key)))
                    wav, dur = tts(text, lang, style, args.steps, args.speed)
                    samples = wav[0, : int(tts.sample_rate * float(np.ravel(dur)[0]))]
                    sf.write(os.path.join(args.out, f"{lang}_{key}_{style_name}_{take}.wav"), samples, tts.sample_rate)
        print("style done", style_name, flush=True)


if __name__ == "__main__":
    main()
