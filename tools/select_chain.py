#!/usr/bin/env python3
"""Chooses one generated candidate per stage for stages 6-20 so the chapter keeps its rhythm.

Input: candidate JSON files written by
    godot --headless --path . -s res://tools/build_arrow_levels.gd -- candidates SPECS OUT.json [ids...]
Stages 1-5 stay as they are (stage 1 hand-made, 2-4 frozen in chapter1_gen.txt, 5 = the fixed first
HARD board in a005_hard.txt); their challenge is read from game/data/v2/campaign.json.

Rhythm (also enforced by the build and by tools/validate_arrow_levels.py), on the challenge score
(ArrowSolver.challenge: estimated search time x few ways in x removal depth x small cells on a phone):
milestones 5, 10, 15 and 20 are the peaks, each above the previous one; the stage right after a
milestone is a breather at most 75 % of it; every other stage is at least 2 % above the one before.
Among all chains that obey the local rules (dynamic programming), the chosen one stays closest to
TARGET (multiples of stage 5's challenge), with a small bonus for key moves (one removal opening
two or more exits) and for varied arrow shapes.

Writes tools/levels_src/chapter1_gen.txt (stages 2-4 kept, 6-20 replaced).
Usage: python3 tools/select_chain.py SPECS.json CANDIDATES.json [CANDIDATES.json ...]
"""
from collections import Counter
from pathlib import Path
import json
import math
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
GEN = ROOT / "tools/levels_src/chapter1_gen.txt"
# Challenge targets as multiples of stage 5 (the first HARD board).
TARGET = {6: 0.6, 7: 0.85, 8: 1.0, 9: 1.15, 10: 1.45, 11: 0.8, 12: 1.1, 13: 1.25, 14: 1.4, 15: 1.7,
          16: 1.0, 17: 1.4, 18: 1.6, 19: 1.8, 20: 2.2}
MILESTONES = {5, 10, 15, 20}
HEADER = """# Outtap chapter 1, stages 2-4 and 6-20 (rules "arrow-path-2", schema 2).
# Generated from candidate specs and chosen by tools/select_chain.py for the chapter's rhythm:
# milestones 5/10/15/20 are the peaks, the stage after each is a breather, the rest rise in between
# (challenge = ArrowSolver.challenge). Then frozen here. Editing a block is the hand adjustment; the
# build re-validates everything with the real rules and fails if the rhythm breaks.
# Bands (colors only, names never shown): 5-9, 10-14, 15-19, 20. Stage 5 lives in a005_hard.txt.
"""
ROT = {"U": "R", "R": "D", "D": "L", "L": "U"}
FLIP = {"U": "U", "D": "D", "L": "R", "R": "L"}


def challenge(m, w, h):
    """Same formula as ArrowSolver.challenge."""
    cell = min(460.0 / (w + 0.64), 820.0 / (h + 0.64))
    entry = 1.0 + 0.08 * max(0.0, 6.0 - min(m["initial_free"], 6))
    depth = 1.0 + m["layers"] / 100.0
    reading = 1.0 + 0.6 * max(0.0, (22.0 - cell) / 22.0)
    return m["est_seconds"] * entry * depth * reading


def shape_key(moves):
    """An arrow's form up to rotation and mirroring."""
    forms = []
    for flip in (False, True):
        mm = "".join(FLIP[c] for c in moves) if flip else moves
        for _ in range(4):
            forms.append(mm)
            mm = "".join(ROT[c] for c in mm)
    return min(forms)


def variety(tokens):
    """Distinct forms per arrow, and how often the most common form repeats."""
    counts = Counter(shape_key(t.split(":")[1]) for t in tokens)
    return len(counts) / len(tokens), counts.most_common(1)[0][1]


def main():
    specs = {s["id"]: s for s in json.loads(Path(sys.argv[1]).read_text())}
    pack = json.loads((ROOT / "game/data/v2/campaign.json").read_text())
    fixed = {int(l["id"][1:]): challenge(l["m"], l["w"], l["h"]) for l in pack["levels"] if int(l["id"][1:]) <= 5}
    base = fixed[5]
    cands = {}
    for path in sys.argv[2:]:
        for c in json.loads(Path(path).read_text()):
            c["c"] = challenge(c["m"], c["w"], c["h"])
            c["variety"], c["repeat"] = variety(c["tokens"])
            cands.setdefault(int(c["id"][1:]), []).append(c)
    stages = sorted(i for i in cands if i >= 6)
    missing = [i for i in range(6, 21) if i not in cands]
    if missing:
        sys.exit(f"no candidates for stages {missing}")

    def cost(i, c):
        e = math.log(c["c"] / (TARGET[i] * base))
        return 4.0 * e * e - 0.6 * c["m"]["keys"] / c["m"]["n"] - 0.4 * c["variety"] + 0.01 * c["repeat"]

    def fits(i, prev_c, c):
        if i - 1 in MILESTONES and i not in MILESTONES:
            return c <= 0.75 * prev_c
        return c >= 1.02 * prev_c

    best = []  # per stage: candidate index -> (total cost, previous index)
    for k, i in enumerate(stages):
        row = {}
        for j, c in enumerate(cands[i]):
            here = cost(i, c)
            if k == 0:
                if fits(i, fixed[5], c["c"]):
                    row[j] = (here, None)
                continue
            options = [(best[k - 1][p][0] + here, p) for p in best[k - 1] if fits(i, cands[stages[k - 1]][p]["c"], c["c"])]
            if options:
                row[j] = min(options)
        if not row:
            sys.exit(f"no candidate for stage {i} fits the rhythm; generate more")
        best.append(row)
    j = min(best[-1], key=lambda x: best[-1][x][0])
    chosen = {}
    for k in range(len(stages) - 1, -1, -1):
        chosen[stages[k]] = cands[stages[k]][j]
        j = best[k][j][1]
    peak = fixed[5]
    for i in (10, 15, 20):
        if chosen[i]["c"] <= peak:
            sys.exit(f"stage {i} does not peak above the previous milestone ({chosen[i]['c']:.0f} <= {peak:.0f})")
        peak = chosen[i]["c"]

    # Keep stages 2-4 exactly as frozen; replace 6-20.
    text = GEN.read_text()
    blocks = re.split(r"(?m)^(?=# n=|@ )", text)
    kept = []
    current = []
    for block in blocks[1:]:
        current.append(block)
        m = re.match(r"@ (a\d{3}) ", block)
        if m:
            if int(m.group(1)[1:]) < 5:
                kept.extend(current)
            current = []
    if not kept:
        sys.exit("could not find stages 2-4 in chapter1_gen.txt")
    lines = [HEADER, "".join(kept).rstrip("\n"), ""]
    for i in stages:
        c = chosen[i]
        s = specs[c["id"]]
        m = c["m"]
        lines.append(f"# n={m['n']} len={m['avg_len']:.2f} free={m['initial_free']} layers={m['layers']} keys={m['keys']} "
                     f"est={m['est_seconds']:.1f}s challenge={c['c']:.0f} (x{c['c'] / base:.2f} of stage 5)")
        header = f"@ {c['id']} {s['tag']} seed={c['seed']} gen={c['gen']} grade={s.get('grade', 0)}"
        if s.get("shape"):
            header += f" shape={s['shape']}"
        for flag in ("soft", "milestone", "final"):
            if s.get(flag):
                header += " " + flag
        for key in ("coach", "theme"):
            if s.get(key):
                header += f" {key}={s[key]}"
        lines += [header, f"size {c['w']} {c['h']}", *c["tokens"], ""]
    GEN.write_text("\n".join(lines))
    print(f"stage 5 challenge {base:.0f}")
    for i in stages:
        c = chosen[i]
        print(f"a{i:03d} {c['w']}x{c['h']} n={c['m']['n']} free={c['m']['initial_free']} layers={c['m']['layers']} keys={c['m']['keys']} "
              f"c={c['c']:.0f} (x{c['c'] / base:.2f}, target x{TARGET[i]}) variety={c['variety']:.2f} repeat={c['repeat']}")


if __name__ == "__main__":
    main()
