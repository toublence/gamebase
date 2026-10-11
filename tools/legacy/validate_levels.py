#!/usr/bin/env python3
"""Independent re-implementation of the Outtap rules used to cross-check bundled level data.

It shares no code with the GDScript game. For every bundled level it checks structure, the
content hash, that the stored solution clears the board with the real rules, and solvability
(exact peel for the basic ruleset, exhaustive search for the switch ruleset). It also mirrors the
Mulberry32 stream so the GDScript PRNG can be compared value by value.

Usage: python3 tools/validate_levels.py            # validate game/data/*.json
       python3 tools/validate_levels.py --ascii F  # peel hand-authored ASCII blocks in F
"""
from pathlib import Path
import hashlib
import json
import sys

ROOT = Path(__file__).resolve().parents[2]
VEC = [(0, -1), (1, 0), (0, 1), (-1, 0)]  # up, right, down, left (clockwise)
SYMBOLS = "^>v<"
MASK = 0xFFFFFFFF


def mulberry32(seed):
    state = seed & MASK
    while True:
        state = (state + 0x6D2B79F5) & MASK
        t = state
        t = ((t ^ (t >> 15)) * (t | 1)) & MASK
        t ^= (t + (((t ^ (t >> 7)) * (t | 61)) & MASK)) & MASK
        yield (t ^ (t >> 14)) & MASK


class Board:
    def __init__(self, level):
        self.w, self.h = level["w"], level["h"]
        self.blocks = []
        self.cells = {}
        for i, e in enumerate(level["b"]):
            kind = e[3] if len(e) > 3 else 0
            links = list(e[4]) if len(e) > 4 else []
            self.blocks.append({"x": e[0], "y": e[1], "d": e[2], "kind": kind, "links": links, "alive": True})
            self.cells[(e[0], e[1])] = i

    def blocker(self, i):
        b = self.blocks[i]
        dx, dy = VEC[b["d"]]
        x, y = b["x"] + dx, b["y"] + dy
        while 0 <= x < self.w and 0 <= y < self.h:
            if (x, y) in self.cells:
                return self.cells[(x, y)]
            x, y = x + dx, y + dy
        return None

    def free(self):
        return [i for i, b in enumerate(self.blocks) if b["alive"] and self.blocker(i) is None]

    def escape(self, i):
        b = self.blocks[i]
        assert b["alive"] and self.blocker(i) is None
        b["alive"] = False
        del self.cells[(b["x"], b["y"])]
        turned = []
        if b["kind"] == 1:
            for t in b["links"]:
                if self.blocks[t]["alive"]:
                    self.blocks[t]["d"] = (self.blocks[t]["d"] + 1) % 4
                    turned.append(t)
        return turned

    def undo(self, i, turned):
        for t in turned:
            self.blocks[t]["d"] = (self.blocks[t]["d"] + 3) % 4
        b = self.blocks[i]
        b["alive"] = True
        self.cells[(b["x"], b["y"])] = i

    def alive(self):
        return sum(1 for b in self.blocks if b["alive"])


def canonical(level):
    parts = []
    for e in level["b"]:
        kind = e[3] if len(e) > 3 else 0
        links = ".".join(str(t) for t in e[4]) if len(e) > 4 else ""
        parts.append(f"{e[0]},{e[1]},{e[2]},{kind},{links}")
    return f"{level.get('rules', 'basic-1')}|{level['w']}|{level['h']}|{';'.join(parts)}"


def content_hash(level):
    return hashlib.sha256(canonical(level).encode()).hexdigest()[:16]


def peel(level):
    board = Board(level)
    layers = []
    while board.alive():
        layer = board.free()
        if not layer:
            break
        for i in layer:
            board.escape(i)
        layers.append(layer)
    return board.alive() == 0, layers


def solve_switch(level, budget=300000):
    board = Board(level)
    memo = {}
    visited = [0]

    def key():
        return tuple(b["alive"] for b in board.blocks)

    def search():
        k = key()
        if k in memo:
            return memo[k]
        if board.alive() == 0:
            return []
        visited[0] += 1
        if visited[0] > budget:
            raise TimeoutError
        for i in board.free():
            turned = board.escape(i)
            line = search()
            board.undo(i, turned)
            if line is not None:
                memo[k] = [i] + line
                return memo[k]
        memo[k] = None
        return None

    try:
        return search()
    except TimeoutError:
        return "timeout"


def replay(level, order):
    board = Board(level)
    for i in order:
        if not (0 <= i < len(board.blocks)) or not board.blocks[i]["alive"] or board.blocker(i) is not None:
            return False
        board.escape(i)
    return board.alive() == 0


def structure(level):
    errors = []
    w, h = level["w"], level["h"]
    seen = set()
    for i, e in enumerate(level["b"]):
        x, y, d = e[0], e[1], e[2]
        if not (0 <= x < w and 0 <= y < h):
            errors.append(f"block {i} outside")
        if d not in (0, 1, 2, 3):
            errors.append(f"block {i} bad dir")
        if (x, y) in seen:
            errors.append(f"block {i} overlaps")
        seen.add((x, y))
        if len(e) > 3 and e[3] == 1:
            if not e[4]:
                errors.append(f"switch {i} without links")
            for t in e[4]:
                if not (0 <= t < len(level["b"])) or t == i:
                    errors.append(f"switch {i} bad link {t}")
    return errors


def parse_ascii(text):
    rows = [line.split() for line in text.strip().splitlines() if line.strip()]
    blocks = []
    for y, row in enumerate(rows):
        for x, tok in enumerate(row):
            if tok != ".":
                blocks.append([x, y, SYMBOLS.index(tok[0])])
    return {"w": len(rows[0]), "h": len(rows), "b": blocks, "rules": "basic-1"}


def validate_file(path):
    data = json.loads(path.read_text())
    problems, count = [], 0
    ids = set()
    for level in data["levels"]:
        count += 1
        lid = level["id"]
        if lid in ids:
            problems.append(f"{lid}: duplicate id")
        ids.add(lid)
        for err in structure(level):
            problems.append(f"{lid}: {err}")
        if content_hash(level) != level["hash"]:
            problems.append(f"{lid}: hash mismatch")
        if not replay(level, level["sol"]):
            problems.append(f"{lid}: stored solution does not clear the board")
        if level.get("rules", "basic-1") == "basic-1":
            ok, _ = peel(level)
            if not ok:
                problems.append(f"{lid}: basic board not solvable")
        else:
            line = solve_switch(level)
            if line == "timeout":
                problems.append(f"{lid}: solver timeout (not counted as solvable)")
            elif line is None:
                problems.append(f"{lid}: switch board not solvable")
    return count, problems


def main():
    if len(sys.argv) > 2 and sys.argv[1] == "--ascii":
        chunks = Path(sys.argv[2]).read_text().split("\n\n")
        bodies = ["\n".join(l for l in c.splitlines() if not l.startswith("#")) for c in chunks]
        for n, body in enumerate(b for b in bodies if b.strip()):
            level = parse_ascii(body)
            ok, layers = peel(level)
            print(f"[{n + 1}] {level['w']}x{level['h']} n={len(level['b'])} solvable={ok} "
                  f"layers={len(layers)} free0={len(layers[0]) if layers else 0} "
                  f"sizes={[len(l) for l in layers]}")
        return 0
    stream = mulberry32(12345)
    print("mulberry32(12345):", [next(stream) for _ in range(4)])
    total, problems = 0, []
    for path in sorted((ROOT / "game/data/legacy").glob("*.json")):
        count, found = validate_file(path)
        total += count
        problems += [f"{path.name}: {p}" for p in found]
        print(f"{path.name}: {count} levels, {len(found)} problems")
    if problems:
        print("\n".join(problems))
        return 1
    print(f"All {total} bundled levels pass the independent rule check.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
