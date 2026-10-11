class_name LevelGenerator
extends RefCounted
## Development-time content generator. Bundled levels are produced by tools/build_levels.gd and
## shipped as data; the game never generates during play.
##
## Basic boards use reverse construction: a block may be placed only if its full path to the
## board edge is clear of the blocks already placed. Removing blocks in reverse placement order
## therefore always works. The final board is still re-validated with the real rules.
const VERSION := "og-gen-1"

const SHAPES := ["rect", "diamond", "ring", "heart", "plus", "hourglass", "arch", "wave", "twin", "stairs", "oval", "frame_dense"]

## Cells allowed for blocks. Returns a PackedByteArray of w*h (1 = allowed).
static func shape_mask(shape: String, w: int, h: int) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(w * h)
	var cx := (w - 1) * 0.5
	var cy := (h - 1) * 0.5
	for y in h:
		for x in w:
			var dx := (x - cx) / maxf(0.5, cx + 0.5)
			var dy := (y - cy) / maxf(0.5, cy + 0.5)
			var on := true
			match shape:
				"diamond": on = absf(dx) + absf(dy) <= 1.05
				"ring": on = not (absf(dx) < 0.42 and absf(dy) < 0.32)
				"heart":
					# Two lobes over a downward triangle, in cell-center coordinates.
					var u := dx * 1.05
					var v := dy * 1.05
					var lobe := minf(Vector2(u + 0.48, v + 0.42).length(), Vector2(u - 0.48, v + 0.42).length())
					on = lobe <= 0.56 or (v >= -0.45 and absf(u) <= (1.0 - (v + 0.45) / 1.5) * 1.02)
				"plus": on = absf(dx) < 0.45 or absf(dy) < 0.4
				"hourglass": on = absf(dx) <= absf(dy) + 0.38
				"arch": on = not (absf(dx) < 0.4 and dy > -0.1)
				"wave": on = absf(dy - sin(x * 1.3) * 0.35) < 0.75
				"twin": on = absf(dx) > 0.15 or absf(dy) > 0.7
				"stairs": on = (x + (h - 1 - y)) >= int((w + h) * 0.25) and (x + (h - 1 - y)) <= int((w + h) * 0.9)
				"oval": on = dx * dx + dy * dy <= 1.08
				_: on = true
			mask[y * w + x] = 1 if on else 0
	return mask

## Builds one basic board. params: w, h, n, shape, block_bias (0..1, preference for cells that sit
## on earlier blocks' exit paths), turn_bias (preference for perpendicular dependencies).
static func build_basic(seed_value: int, params: Dictionary) -> Dictionary:
	var rng := Prng.new(seed_value)
	var w: int = params["w"]
	var h: int = params["h"]
	var target: int = params["n"]
	var mask := shape_mask(str(params.get("shape", "rect")), w, h)
	var block_bias: float = params.get("block_bias", 0.6)
	var path_bias: float = params.get("path_bias", 0.35)
	var symmetric := str(params.get("symmetry", "")) == "rot180"
	var longest := float(maxi(w, h))
	var cells := w * h
	# clear[d][cell]: the path from cell to the edge in direction d is empty.
	var clear: Array[PackedByteArray] = []
	for d in 4:
		var row := PackedByteArray()
		row.resize(cells)
		row.fill(1)
		clear.append(row)
	var cover := PackedInt32Array() # how many placed blocks must travel through this cell
	cover.resize(cells)
	var occupied := PackedByteArray()
	occupied.resize(cells)
	var blocks: Array = []
	var dir_counts := [0, 0, 0, 0]
	var candidates := PackedInt32Array()
	var weights := PackedFloat32Array()
	while blocks.size() < target:
		candidates.clear()
		weights.clear()
		for c in cells:
			if occupied[c] == 1 or mask[c] == 0:
				continue
			for d in 4:
				if clear[d][c] == 0:
					continue
				var weight := 1.0 + block_bias * 3.0 * minf(cover[c], 3)
				# Long paths placed early get crossed by later blocks: deeper dependencies.
				weight *= 1.0 + path_bias * 3.0 * float(_exit_len(c % w, c / w, d, w, h) - 1) / longest
				# Keep directions balanced so no single arrow dominates the read.
				weight *= 1.0 / (1.0 + 0.35 * maxf(0.0, dir_counts[d] - blocks.size() * 0.25))
				candidates.append(c * 4 + d)
				weights.append(weight)
		if candidates.is_empty():
			break
		var choice := candidates[rng.pick_weighted(weights)]
		var cell := choice / 4
		var d := choice % 4
		var x := cell % w
		var y := cell / w
		if symmetric:
			var mx := w - 1 - x
			var my := h - 1 - y
			var md := (d + 2) % 4
			if mx == x and my == y:
				_place(x, y, d, w, h, clear, cover, occupied, blocks, dir_counts)
				continue
			# The twin must also have a clear path once the first block is down.
			_place(x, y, d, w, h, clear, cover, occupied, blocks, dir_counts)
			var twin := my * w + mx
			if occupied[twin] == 0 and mask[twin] == 1 and clear[md][twin] == 1 and blocks.size() < target:
				_place(mx, my, md, w, h, clear, cover, occupied, blocks, dir_counts)
			continue
		_place(x, y, d, w, h, clear, cover, occupied, blocks, dir_counts)
	# Reverse placement order is a valid solution by construction; tools re-validate it anyway.
	var solution := PackedInt32Array()
	for i in range(blocks.size() - 1, -1, -1):
		solution.append(i)
	return {"w": w, "h": h, "b": blocks, "sol": Array(solution), "rules": LevelData.RULES_BASIC,
		"seed": seed_value, "gen": VERSION}

## Deterministic hill climb on arrow directions toward a difficulty target. Only flips that keep
## the board solvable under the exact peel are kept; the stored solution becomes the peel order.
## Returns the tuned level (input is not modified).
static func tune_basic(level: Dictionary, seed_value: int, target: float, iterations: int = 160, max_dir_share: float = 0.42, symmetric: bool = false) -> Dictionary:
	var rng := Prng.new(seed_value)
	var board := BoardState.from_level(level)
	var current := quick_score(board)
	var n := board.size()
	for it in iterations:
		if absf(current - target) < 0.25:
			break
		var id := rng.below(n)
		var old := board.dirs[id]
		var nd := (old + 1 + rng.below(3)) % 4
		board.dirs[id] = nd
		var twin := -1
		var twin_old := -1
		if symmetric:
			twin = board.at(board.width - 1 - board.xs[id], board.height - 1 - board.ys[id])
			if twin == id:
				twin = -1
			elif twin != BoardState.EMPTY:
				twin_old = board.dirs[twin]
				board.dirs[twin] = (nd + 2) % 4
		var peel := LevelValidator.peel(board)
		var keep := false
		if peel["solvable"] and _dir_share(board) <= max_dir_share:
			var score := quick_score(board, peel)
			if absf(score - target) < absf(current - target):
				current = score
				keep = true
		if not keep:
			board.dirs[id] = old
			if twin >= 0:
				board.dirs[twin] = twin_old
	var result := level.duplicate(true)
	for i in n:
		result["b"][i][2] = board.dirs[i]
	result["sol"] = Array(LevelValidator.peel(board)["order"])
	return result

## Cheap proxy of LevelValidator.metrics score used inside the hill climb.
static func quick_score(board: BoardState, peel: Dictionary = {}) -> float:
	if peel.is_empty():
		peel = LevelValidator.peel(board)
	var layers: Array = peel["layers"]
	if layers.is_empty():
		return 0.0
	var free_ratio := float(layers[0].size()) / maxf(1.0, board.alive_count)
	return layers.size() * 1.1 + (1.0 - free_ratio) * 3.5 + board.alive_count * 0.05

static func _dir_share(board: BoardState) -> float:
	var counts := [0, 0, 0, 0]
	for d in board.dirs:
		counts[d] += 1
	return float(counts.max()) / maxf(1.0, board.size())

static func _place(x: int, y: int, d: int, w: int, h: int, clear: Array[PackedByteArray], cover: PackedInt32Array,
		occupied: PackedByteArray, blocks: Array, dir_counts: Array) -> void:
	occupied[y * w + x] = 1
	dir_counts[d] += 1
	blocks.append([x, y, d])
	# Every cell whose path in direction k passes through this cell is now blocked for k.
	for k in 4:
		var back := Dir.vec(k) * -1
		var bx := x + back.x
		var by := y + back.y
		while bx >= 0 and by >= 0 and bx < w and by < h:
			clear[k][by * w + bx] = 0
			bx += back.x
			by += back.y
	# This block's own exit path is now covered.
	var step := Dir.vec(d)
	var px := x + step.x
	var py := y + step.y
	while px >= 0 and py >= 0 and px < w and py < h:
		cover[py * w + px] += 1
		px += step.x
		py += step.y

static func _exit_len(x: int, y: int, d: int, w: int, h: int) -> int:
	match d:
		Dir.UP: return y + 1
		Dir.RIGHT: return w - x
		Dir.DOWN: return h - y
		_: return x + 1

## Random small switch board; solvability is decided afterwards by SwitchSolver.
## params: w, h, n, switches, links_max, shape
static func build_switch(seed_value: int, params: Dictionary) -> Dictionary:
	var rng := Prng.new(seed_value)
	var w: int = params["w"]
	var h: int = params["h"]
	var n: int = params["n"]
	var mask := shape_mask(str(params.get("shape", "rect")), w, h)
	var free_cells := PackedInt32Array()
	for c in w * h:
		if mask[c] == 1:
			free_cells.append(c)
	# Fisher-Yates with the deterministic stream.
	for i in range(free_cells.size() - 1, 0, -1):
		var j := rng.below(i + 1)
		var tmp := free_cells[i]
		free_cells[i] = free_cells[j]
		free_cells[j] = tmp
	var blocks: Array = []
	for i in mini(n, free_cells.size()):
		var c := free_cells[i]
		blocks.append([c % w, c / w, rng.below(4), 0, []])
	var switch_count: int = mini(params.get("switches", 1), blocks.size() / 3)
	var links_max: int = params.get("links_max", 2)
	var chosen := {}
	while chosen.size() < switch_count:
		chosen[rng.below(blocks.size())] = true
	for s in chosen:
		blocks[s][3] = BoardState.KIND_SWITCH
	for s in chosen:
		var link_count := rng.range_int(1, links_max)
		var guard := 0
		while blocks[s][4].size() < link_count and guard < 40:
			guard += 1
			var t := rng.below(blocks.size())
			if t == s or chosen.has(t) or blocks[s][4].has(t):
				continue
			blocks[s][4].append(t)
	for entry in blocks:
		entry[4].sort()
		if entry[3] == 0:
			entry.resize(3)
	return {"w": w, "h": h, "b": blocks, "rules": LevelData.RULES_SWITCH, "seed": seed_value, "gen": VERSION}

## Shape signature for repetition checks: occupancy + arrows, compared under all 8 symmetries.
static func similarity(a: Dictionary, b: Dictionary) -> float:
	if int(a["w"]) * int(a["h"]) == 0 or int(b["w"]) * int(b["h"]) == 0:
		return 0.0
	var best := 0.0
	var cells_a := {}
	for e in a["b"]:
		cells_a[Vector2i(int(e[0]), int(e[1]))] = int(e[2])
	for sym in 8:
		var transformed := _transform(b, sym)
		if transformed.is_empty():
			continue
		var same_cell := 0
		var same_dir := 0
		for key in transformed:
			if cells_a.has(key):
				same_cell += 1
				if cells_a[key] == transformed[key]:
					same_dir += 1
		var union := cells_a.size() + transformed.size() - same_cell
		var score := (same_cell + same_dir) * 0.5 / maxf(1.0, union)
		best = maxf(best, score)
	return best

static func _transform(level: Dictionary, sym: int) -> Dictionary:
	var w := int(level["w"])
	var h := int(level["h"])
	var result := {}
	for e in level["b"]:
		var x := int(e[0])
		var y := int(e[1])
		var d := int(e[2])
		var p := Vector2i(x, y)
		var turns := sym % 4
		var cw := w
		var ch := h
		for t in turns:
			p = Vector2i(ch - 1 - p.y, p.x)
			var tmp := cw
			cw = ch
			ch = tmp
			d = Dir.cw(d)
		if sym >= 4:
			p = Vector2i(cw - 1 - p.x, p.y)
			if d == Dir.LEFT or d == Dir.RIGHT:
				d = (d + 2) % 4
		result[p] = d
	return result
