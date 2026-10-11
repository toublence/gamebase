#!/usr/bin/env python3
"""Independent re-implementation of the "arrow-path-2" rules (shares no code with the game).

For every bundled level in game/data/v2/*.json it checks: schema/rules tags, connected
non-overlapping in-bounds paths of at least two cells, no head pointing into its own body, the
content hash, that the stored solution clears the board when replayed with the escape rule, that
the board is solvable by exact peeling, and that the stored metrics' arrow count matches.
Design rules on top: a stored silhouette covers every arrow cell, golden arrows are real arrow ids,
no two levels share a silhouette, a graded (HARD and above) board never lets more than
max(6, 12 % of its arrows) leave at the start, the first four stages are not graded, grades never go
down, and the chapter keeps its rhythm (challenge recomputed here, same formula as
ArrowSolver.challenge): milestones peak above the previous milestone, the stage after a milestone
is a breather at most 75 % of it, and every other stage is at least 2 % above the one before.
Usage: python3 tools/validate_arrow_levels.py
"""
from pathlib import Path
import hashlib
import math
import json
import sys

ROOT = Path(__file__).resolve().parents[1]
RULES = "arrow-path-2"


def arrows_of(level):
    return [[(flat[i], flat[i + 1]) for i in range(0, len(flat), 2)] for flat in level["a"]]


def canonical(level):
    parts = [".".join(str(int(v)) for v in flat) for flat in level["a"]]
    return f"{RULES}|{level['w']}|{level['h']}|{';'.join(parts)}"


def head_and_dir(path):
    (hx, hy), (px, py) = path[-1], path[-2]
    return (hx, hy), (hx - px, hy - py)


def escapes(level, occupied, i, path):
    (x, y), (dx, dy) = head_and_dir(path)
    x, y = x + dx, y + dy
    while 0 <= x < level["w"] and 0 <= y < level["h"]:
        if (x, y) in occupied:
            return False
        x, y = x + dx, y + dy
    return True


def structure(level):
    problems = []
    if level.get("rules") != RULES or level.get("schema") != 2:
        problems.append("wrong rules/schema tag")
    seen = {}
    paths = arrows_of(level)
    for i, path in enumerate(paths):
        if len(path) < 2:
            problems.append(f"arrow {i} shorter than two cells")
            continue
        for k, (x, y) in enumerate(path):
            if not (0 <= x < level["w"] and 0 <= y < level["h"]):
                problems.append(f"arrow {i} off board")
            if (x, y) in seen:
                problems.append(f"arrow {i} overlaps arrow {seen[(x, y)]}")
            seen[(x, y)] = i
            if k and abs(x - path[k - 1][0]) + abs(y - path[k - 1][1]) != 1:
                problems.append(f"arrow {i} not connected")
        (x, y), (dx, dy) = head_and_dir(path)
        x, y = x + dx, y + dy
        while 0 <= x < level["w"] and 0 <= y < level["h"]:
            if (x, y) in set(path):
                problems.append(f"arrow {i} points into its own body")
                break
            x, y = x + dx, y + dy
    return problems


def replay(level, order):
    paths = arrows_of(level)
    occupied = {c: i for i, p in enumerate(paths) for c in p}
    alive = set(range(len(paths)))
    for i in order:
        if i not in alive or not escapes(level, occupied, i, paths[i]):
            return False
        alive.discard(i)
        for c in paths[i]:
            del occupied[c]
    return not alive


def peel(level):
    paths = arrows_of(level)
    occupied = {c: i for i, p in enumerate(paths) for c in p}
    alive = set(range(len(paths)))
    while alive:
        free = [i for i in sorted(alive) if escapes(level, occupied, i, paths[i])]
        if not free:
            return False
        for i in free:
            alive.discard(i)
            for c in paths[i]:
                del occupied[c]
    return True


def free_ids(level, occupied, paths, alive):
    return [i for i in sorted(alive) if escapes(level, occupied, i, paths[i])]


def solve_profile(level):
    """Removal layers (peeling) and the estimated search time of ArrowSolver.metrics: each step
    removes the lowest-numbered free arrow and costs 0.25 + 0.45 * log2(1 + alive / free)."""
    paths = arrows_of(level)
    occupied = {c: i for i, p in enumerate(paths) for c in p}
    alive = set(range(len(paths)))
    layers = 0
    while alive:
        free = free_ids(level, occupied, paths, alive)
        if not free:
            break
        layers += 1
        for i in free:
            alive.discard(i)
            for c in paths[i]:
                del occupied[c]
    occupied = {c: i for i, p in enumerate(paths) for c in p}
    alive = set(range(len(paths)))
    est = 0.0
    free = free_ids(level, occupied, paths, alive)
    while alive and free:
        est += 0.25 + 0.45 * math.log2(1 + len(alive) / len(free))
        gone = free[0]
        alive.discard(gone)
        for c in paths[gone]:
            del occupied[c]
        free = free_ids(level, occupied, paths, alive)
    return layers, est


def challenge(level, est, layers):
    """Same as ArrowSolver.challenge: search time x entry (few ways in) x depth x reading (small cells)."""
    cell = min(460.0 / (level["w"] + 0.64), 820.0 / (level["h"] + 0.64))
    entry = 1.0 + 0.08 * max(0.0, 6.0 - min(initial_free(level), 6))
    depth = 1.0 + layers / 100.0
    reading = 1.0 + 0.6 * max(0.0, (22.0 - cell) / 22.0)
    return est * entry * depth * reading


def initial_free(level):
    paths = arrows_of(level)
    occupied = {c: i for i, p in enumerate(paths) for c in p}
    return sum(1 for i, p in enumerate(paths) if escapes(level, occupied, i, p))


def design(level):
    problems = []
    paths = arrows_of(level)
    mask = level.get("mask")
    if mask is not None:
        if len(mask) != level["w"] * level["h"] or set(mask) - {"0", "1"}:
            problems.append("silhouette mask has the wrong size or characters")
        else:
            for p in paths:
                for x, y in p:
                    if mask[y * level["w"] + x] != "1":
                        problems.append(f"arrow cell {(x, y)} lies outside the silhouette")
    gold = level.get("gold", [])
    if len(set(gold)) != len(gold) or any(not (0 <= g < len(paths)) for g in gold):
        problems.append(f"golden arrow ids {gold} are not distinct arrow ids")
    grade = int(level.get("grade", 1 if level.get("hard") else 0))
    if grade > 0:
        limit = max(6, math.ceil(0.12 * len(paths)))
        if initial_free(level) > limit:
            problems.append(f"graded board lets {initial_free(level)} arrows leave at the start (max {limit})")
        if int(level["id"][1:]) <= 4:
            problems.append("graded board inside the first four stages")
    return problems


def main():
    total, problems = 0, []
    for path in sorted((ROOT / "game/data/v2").glob("*.json")):
        pack = json.loads(path.read_text())
        if pack.get("rules") != RULES:
            problems.append(f"{path.name}: pack rules tag is not {RULES}")
        ids = set()
        shapes = {}
        previous = None
        last_peak = -1.0
        for level in pack["levels"]:
            total += 1
            lid = level["id"]
            if lid in ids:
                problems.append(f"{lid}: duplicate id")
            ids.add(lid)
            for p in structure(level):
                problems.append(f"{lid}: {p}")
            if hashlib.sha256(canonical(level).encode()).hexdigest()[:16] != level["hash"]:
                problems.append(f"{lid}: hash mismatch")
            if not replay(level, level["sol"]):
                problems.append(f"{lid}: stored solution does not clear the board")
            if not peel(level):
                problems.append(f"{lid}: not solvable")
            if level.get("m", {}).get("n") != len(level["a"]):
                problems.append(f"{lid}: metrics arrow count mismatch")
            for p in design(level):
                problems.append(f"{lid}: {p}")
            layers, est = solve_profile(level)
            if abs(est - level.get("m", {}).get("est_seconds", -1)) > 0.11:
                problems.append(f"{lid}: stored est_seconds {level['m'].get('est_seconds')} != recomputed {est:.2f}")
            c = challenge(level, est, layers)
            milestone = bool(level.get("hard", False))
            if previous is not None:
                pid, pc, pgrade, pmilestone = previous
                if pmilestone and not milestone and c > 0.75 * pc:
                    problems.append(f"{lid}: should be a breather after {pid} (challenge {pc:.0f}->{c:.0f})")
                elif not pmilestone and c < 1.02 * pc:
                    problems.append(f"{lid}: not harder than {pid} (challenge {pc:.0f}->{c:.0f})")
                if int(level.get("grade", 0)) < pgrade:
                    problems.append(f"{lid}: grade goes down after {pid}")
            if milestone:
                if c <= last_peak:
                    problems.append(f"{lid}: peaks lower than the previous milestone ({c:.0f} <= {last_peak:.0f})")
                last_peak = c
            previous = (lid, c, int(level.get("grade", 0)), milestone)
            shape = level.get("shape")
            if shape:
                if shape in shapes:
                    problems.append(f"{lid}: repeats the {shape} silhouette of {shapes[shape]}")
                shapes[shape] = lid
        print(f"{path.name}: {len(pack['levels'])} levels")
    if problems:
        print("\n".join(problems))
        return 1
    print(f"All {total} arrow-path-2 levels pass the independent rule check.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
