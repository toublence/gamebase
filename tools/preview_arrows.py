#!/usr/bin/env python3
"""Renders arrow-path-2 levels to SVG (and PNG via macOS qlmanage) for design reviews.

Usage: python3 tools/preview_arrows.py LEVELS.json OUT_DIR [ids...]
LEVELS.json may be a pack ({"levels": [...]}) or a list of levels. Free arrows (escapable now)
are outlined so reviewers can see the opening moves.
"""
import json
import subprocess
import sys
from pathlib import Path

COLORS = ["#23314A", "#1E7F79", "#7A3E6B", "#B0552F", "#4E6A2E", "#3B5BA0", "#8A6A1F", "#5B4B8A"]
VEC = {(0, -1): 0, (1, 0): 1, (0, 1): 2, (-1, 0): 3}


def cells(flat):
    return [(flat[i], flat[i + 1]) for i in range(0, len(flat), 2)]


def free_ids(level):
    occ = {}
    for i, flat in enumerate(level["a"]):
        for c in cells(flat):
            occ[c] = i
    result = []
    for i, flat in enumerate(level["a"]):
        cs = cells(flat)
        (hx, hy), (px, py) = cs[-1], cs[-2]
        dx, dy = hx - px, hy - py
        x, y = hx + dx, hy + dy
        ok = True
        while 0 <= x < level["w"] and 0 <= y < level["h"]:
            if (x, y) in occ:
                ok = False
                break
            x, y = x + dx, y + dy
        if ok:
            result.append(i)
    return result


def svg(level, size=60):
    w, h = level["w"], level["h"]
    pad = size * 0.5
    W, H = w * size + pad * 2, h * size + pad * 2 + 30
    S = max(W, H)  # square canvas: Quick Look thumbnails are square
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{S:.0f}" height="{S:.0f}" viewBox="0 0 {S:.0f} {S:.0f}">',
           f'<rect width="100%" height="100%" fill="#F5EFE4"/>']
    mask = level.get("mask")
    if mask:
        # The level's silhouette: one soft tile per picture cell, slightly overlapping.
        for y in range(h):
            for x in range(w):
                if mask[y * w + x] == "1":
                    out.append(f'<rect x="{pad+x*size-size*0.08:.1f}" y="{pad+y*size-size*0.08:.1f}" width="{size*1.16:.1f}" height="{size*1.16:.1f}" rx="{size*0.3:.1f}" fill="#EAE0CF"/>')
                    out.append(f'<circle cx="{pad+(x+.5)*size}" cy="{pad+(y+.5)*size}" r="{size*0.05}" fill="#CDBEA4"/>')
    else:
        out.append(f'<rect x="{pad*0.4}" y="{pad*0.4}" width="{w*size+pad*1.2}" height="{h*size+pad*1.2}" rx="{size*0.4}" fill="#EAE0CF"/>')
        for y in range(h):
            for x in range(w):
                out.append(f'<circle cx="{pad+(x+.5)*size}" cy="{pad+(y+.5)*size}" r="{size*0.05}" fill="#CDBEA4"/>')
    free = set(free_ids(level))
    for i, flat in enumerate(level["a"]):
        cs = cells(flat)
        color = COLORS[i % len(COLORS)]
        pts = " ".join(f"{pad+(x+.5)*size:.1f},{pad+(y+.5)*size:.1f}" for x, y in cs)
        if i in free:
            out.append(f'<polyline points="{pts}" fill="none" stroke="#F2B53A" stroke-width="{size*0.62:.1f}" stroke-linecap="round" stroke-linejoin="round" opacity="0.55"/>')
        if i in level.get("gold", []):
            out.append(f'<polyline points="{pts}" fill="none" stroke="#E2A72E" stroke-width="{size*0.56:.1f}" stroke-linecap="round" stroke-linejoin="round"/>')
        out.append(f'<polyline points="{pts}" fill="none" stroke="{color}" stroke-width="{size*0.36:.1f}" stroke-linecap="round" stroke-linejoin="round"/>')
        (hx, hy), (px, py) = cs[-1], cs[-2]
        dx, dy = hx - px, hy - py
        cx, cy = pad + (hx + .5) * size, pad + (hy + .5) * size
        tip = (cx + dx * size * 0.48, cy + dy * size * 0.48)
        nx, ny = -dy, dx
        b1 = (cx - dx * size * 0.05 + nx * size * 0.36, cy - dy * size * 0.05 + ny * size * 0.36)
        b2 = (cx - dx * size * 0.05 - nx * size * 0.36, cy - dy * size * 0.05 - ny * size * 0.36)
        out.append(f'<polygon points="{tip[0]:.1f},{tip[1]:.1f} {b1[0]:.1f},{b1[1]:.1f} {b2[0]:.1f},{b2[1]:.1f}" fill="{color}" stroke="{color}" stroke-width="{size*0.08:.1f}" stroke-linejoin="round"/>')
    m = level.get("m", {})
    label = f'{level.get("id","?")} {level.get("shape","")} {w}x{h} n={len(level["a"])} free={len(free)} layers={m.get("layers","?")} est={m.get("est_seconds","?")}s gold={level.get("gold","")}'
    out.append(f'<text x="{pad*0.4}" y="{H-8}" font-family="Helvetica" font-size="18" fill="#23314A">{label}</text>')
    out.append("</svg>")
    return "\n".join(out)


def main():
    data = json.loads(Path(sys.argv[1]).read_text())
    levels = data["levels"] if isinstance(data, dict) else data
    out_dir = Path(sys.argv[2])
    out_dir.mkdir(parents=True, exist_ok=True)
    wanted = set(sys.argv[3:])
    paths = []
    for level in levels:
        if wanted and level.get("id") not in wanted:
            continue
        p = out_dir / f'{level.get("id","level")}.svg'
        p.write_text(svg(level))
        paths.append(str(p))
    if paths:
        subprocess.run(["qlmanage", "-t", "-s", "700", "-o", str(out_dir)] + paths, capture_output=True)
    print(f"rendered {len(paths)} to {out_dir}")


if __name__ == "__main__":
    main()
