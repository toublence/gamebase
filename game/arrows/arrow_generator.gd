class_name ArrowGenerator
extends RefCounted
## Development-time generator for "arrow-path-2" boards (tools/build_arrow_levels.gd); the game
## itself never generates during play.
##
## Reverse construction: an arrow may be placed only if its way out (head → edge) is clear of the
## arrows already on the board. Removing arrows in reverse placement order is therefore a valid
## solution. Every result is still re-validated with the real rules before it is kept.
const VERSION := "arrow-gen-1"
const VERSION_SHAPED := "arrow-gen-2-shaped"
const MODES := ["straight", "L", "U", "stair", "hook", "wander"]
const SHAPES := ["rect", "oval", "diamond", "heart", "plus", "ring", "arch", "hourglass"]

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
				"oval": on = dx * dx + dy * dy <= 1.12
				"diamond": on = absf(dx) + absf(dy) <= 1.2
				"heart":
					var u := dx * 1.05
					var v := dy * 1.05
					var lobe := minf(Vector2(u + 0.48, v + 0.42).length(), Vector2(u - 0.48, v + 0.42).length())
					on = lobe <= 0.58 or (v >= -0.45 and absf(u) <= (1.0 - (v + 0.45) / 1.5) * 1.05)
				"plus": on = absf(dx) < 0.5 or absf(dy) < 0.45
				"ring": on = not (absf(dx) < 0.32 and absf(dy) < 0.26)
				"arch": on = not (absf(dx) < 0.34 and dy > 0.15)
				"hourglass": on = absf(dx) <= absf(dy) + 0.45
				_: on = true
			mask[y * w + x] = 1 if on else 0
	return mask

## params: w, h, shape, fill (share of mask cells to cover), len_min, len_max, turn (0..1 chance to
## bend at each body step), max_bends, cover (how strongly a new arrow should block arrows that are
## still free), tries (candidate arrows evaluated per placement), max_arrows.
##
## Free arrows at the start are exactly the arrows whose way out no later arrow blocks. Each step
## evaluates several candidate arrows and prefers the one whose body blocks the most still-free
## arrows, which keeps the opening small and builds chains of dependencies.
static func build(seed_value: int, params: Dictionary) -> Dictionary:
	var rng := Prng.new(seed_value)
	var w: int = params["w"]
	var h: int = params["h"]
	var mask := shape_mask(str(params.get("shape", "rect")), w, h)
	var fill: float = params.get("fill", 0.8)
	var len_min: int = params.get("len_min", 2)
	var len_max: int = params.get("len_max", 7)
	var turn: float = params.get("turn", 0.35)
	var max_bends: int = params.get("max_bends", 3)
	var cover_weight: float = params.get("cover", 2.0)
	var tries: int = params.get("tries", 10)
	var max_arrows: int = params.get("max_arrows", 999)
	var cells := w * h
	var mask_cells := 0
	for v in mask:
		mask_cells += v
	var target := int(mask_cells * fill)
	var owner := PackedInt32Array()
	owner.resize(cells)
	owner.fill(-1)
	# clear[d][c] == 1 when every cell from c (exclusive) to the edge in direction d is empty.
	var clear: Array[PackedByteArray] = []
	for d in 4:
		var row := PackedByteArray()
		row.resize(cells)
		row.fill(1)
		clear.append(row)
	var rays: Array = [] # per arrow: cell indices on its way out
	var still_free: Array[bool] = [] # no later arrow blocks it yet
	var free_on_cell := PackedInt32Array() # how many still-free arrows have their way out through this cell
	free_on_cell.resize(cells)
	var arrows: Array = []
	var covered := 0
	var stalls := 0
	while covered < target and stalls < 6 and arrows.size() < max_arrows:
		var heads := PackedInt32Array()
		var weights := PackedFloat32Array()
		for c in cells:
			if owner[c] != -1 or mask[c] == 0:
				continue
			var x := c % w
			var y := c / w
			for d in 4:
				if clear[d][c] == 0:
					continue
				var back := Vector2i(x, y) - Dir.vec(d)
				if back.x < 0 or back.y < 0 or back.x >= w or back.y >= h:
					continue
				var bi := back.y * w + back.x
				if owner[bi] != -1 or mask[bi] == 0:
					continue
				heads.append(c * 4 + d)
				weights.append(1.0 + cover_weight * minf(free_on_cell[c] + free_on_cell[bi], 4))
		if heads.is_empty():
			break
		var best: Array[Vector2i] = []
		var best_score := -INF
		var best_ray := PackedInt32Array()
		for t in tries:
			var pick := heads[rng.pick_weighted(weights)]
			var candidate := _grow(rng, pick, w, h, mask, owner, free_on_cell, len_min, len_max, turn, max_bends, cover_weight)
			if candidate.is_empty():
				continue
			var blocks := {}
			for c in candidate["body"]:
				var ci: int = c.y * w + c.x
				if free_on_cell[ci] > 0:
					for i in rays.size():
						if still_free[i] and (rays[i] as PackedInt32Array).has(ci):
							blocks[i] = true
			var score: float = blocks.size() * cover_weight + candidate["body"].size() * 0.25 + rng.next_float() * 0.8
			if score > best_score:
				best_score = score
				best = candidate["body"]
				best_ray = candidate["ray"]
		if best.is_empty():
			stalls += 1
			continue
		stalls = 0
		var id := arrows.size()
		var flat: Array = []
		for c in best:
			var ci := c.y * w + c.x
			flat.append(c.x)
			flat.append(c.y)
			owner[ci] = id
			covered += 1
			# Arrows whose way out runs through this cell are blocked from now on.
			if free_on_cell[ci] > 0:
				for i in rays.size():
					if still_free[i] and (rays[i] as PackedInt32Array).has(ci):
						still_free[i] = false
						for rc in rays[i]:
							free_on_cell[rc] -= 1
			for d in 4:
				var b := c - Dir.vec(d)
				while b.x >= 0 and b.y >= 0 and b.x < w and b.y < h:
					clear[d][b.y * w + b.x] = 0
					b -= Dir.vec(d)
		rays.append(best_ray)
		still_free.append(true)
		for rc in best_ray:
			free_on_cell[rc] += 1
		arrows.append(flat)
	var sol: Array = []
	for i in range(arrows.size() - 1, -1, -1):
		sol.append(i)
	return {"w": w, "h": h, "a": arrows, "sol": sol, "rules": ArrowBoard.RULES, "schema": ArrowLevel.SCHEMA,
		"seed": seed_value, "gen": VERSION}

## Dense construction: tile the board with random snake paths first, choose a head end for each,
## then repair until the real rules clear the board. Repair flips which end is the head (the drawn
## path stays the same) for arrows that are still stuck after peeling, keeping a flip only when it
## does not increase the stuck count; as a last resort a stuck arrow is removed. The result is
## always re-validated by peeling; the returned solution is the peel order.
static func build_dense(seed_value: int, params: Dictionary) -> Dictionary:
	var rng := Prng.new(seed_value)
	var w: int = params["w"]
	var h: int = params["h"]
	var mask := shape_mask(str(params.get("shape", "rect")), w, h)
	var fill: float = params.get("fill", 0.9)
	var len_min: int = params.get("len_min", 3)
	var len_max: int = params.get("len_max", 8)
	var turn: float = params.get("turn", 0.35)
	var max_bends: int = params.get("max_bends", 3)
	var cells := w * h
	var owner := PackedInt32Array()
	owner.resize(cells)
	owner.fill(-1)
	var mask_cells := 0
	for v in mask:
		mask_cells += v
	var snakes: Array = []
	var covered := 0
	var order := PackedInt32Array()
	for c in cells:
		if mask[c] == 1:
			order.append(c)
	for i in range(order.size() - 1, 0, -1):
		var j := rng.below(i + 1)
		var t := order[i]
		order[i] = order[j]
		order[j] = t
	for start in order:
		if covered >= int(mask_cells * fill):
			break
		if owner[start] != -1:
			continue
		var goal := rng.range_int(len_min, len_max)
		var path: Array[Vector2i] = [Vector2i(start % w, start / w)]
		var used := {path[0]: true}
		var walk := rng.below(4)
		var bends := 0
		# Grow from one end, then try the other end if it stalls.
		for end in 2:
			while path.size() < goal:
				var cur: Vector2i = path[path.size() - 1]
				var options := PackedInt32Array()
				var option_weights := PackedFloat32Array()
				for k in 4:
					if path.size() > 1 and k == (walk + 2) % 4:
						continue
					if path.size() > 1 and k != walk and bends >= max_bends:
						continue
					var n := cur + Dir.vec(k)
					if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h:
						continue
					var ni := n.y * w + n.x
					if owner[ni] != -1 or mask[ni] == 0 or used.has(n):
						continue
					options.append(k)
					option_weights.append((1.0 - turn) if k == walk else turn * 0.5)
				if options.is_empty():
					break
				var k := options[rng.pick_weighted(option_weights)]
				if path.size() > 1 and k != walk:
					bends += 1
				walk = k
				var next := cur + Dir.vec(k)
				path.append(next)
				used[next] = true
			if path.size() >= goal or end == 1:
				break
			path.reverse()
			if path.size() > 1:
				walk = ArrowBoard.direction_between(path[path.size() - 2], path[path.size() - 1])
		if path.size() < len_min:
			continue
		for c in path:
			owner[c.y * w + c.x] = snakes.size()
		covered += path.size()
		snakes.append(path)
	# Head choice: either end, skipping ends whose way out runs into the arrow itself.
	var board := ArrowBoard.empty(w, h)
	for path in snakes:
		var flipped: Array[Vector2i] = path.duplicate()
		flipped.reverse()
		var options: Array = []
		if not _self_blocked(path, w, h):
			options.append(path)
		if not _self_blocked(flipped, w, h):
			options.append(flipped)
		if options.is_empty():
			continue
		board.add_arrow(options[rng.below(options.size())])
	var repairs := 0
	var removed := 0
	var stuck := _stuck(board)
	var guard := 0
	while not stuck.is_empty() and guard < 4000:
		guard += 1
		var id := stuck[rng.below(stuck.size())]
		var cells_now := board.cells_of(id)
		cells_now.reverse()
		if not _self_blocked(cells_now, w, h):
			var before := stuck.size()
			var backup := board.duplicate_board()
			_reorient(board, id, cells_now)
			var after := _stuck(board)
			if after.size() <= before and (after.size() < before or rng.chance(0.5)):
				stuck = after
				repairs += 1
				continue
			board = backup
		if guard % 25 == 0:
			# Still stuck after many flips: drop one stuck arrow (leaves a hole).
			board.remove(id)
			removed += 1
			stuck = _stuck(board)
	var arrows: Array = []
	for id in board.live_ids():
		var flat: Array = []
		for c in board.cells_of(id):
			flat.append(c.x)
			flat.append(c.y)
		arrows.append(flat)
	var level := {"w": w, "h": h, "a": arrows, "rules": ArrowBoard.RULES, "schema": ArrowLevel.SCHEMA,
		"seed": seed_value, "gen": VERSION + "-dense", "repairs": repairs, "dropped": removed}
	level["sol"] = Array(ArrowSolver.peel(ArrowBoard.from_level(level))["order"])
	return level

static func _self_blocked(path: Array[Vector2i], w: int, h: int) -> bool:
	var d := path[path.size() - 1] - path[path.size() - 2]
	var c := path[path.size() - 1] + d
	while c.x >= 0 and c.y >= 0 and c.x < w and c.y < h:
		if path.has(c):
			return true
		c += d
	return false

static func _stuck(board: ArrowBoard) -> PackedInt32Array:
	var copy := board.duplicate_board()
	while true:
		var free := copy.escapable_ids()
		if free.is_empty():
			break
		for id in free:
			copy.remove(id)
	return copy.live_ids()

static func _reorient(board: ArrowBoard, id: int, cells: Array[Vector2i]) -> void:
	var packed := PackedInt32Array()
	for c in cells:
		packed.append(board.index(c.x, c.y))
	board.paths[id] = packed
	board.dirs[id] = ArrowBoard.direction_between(cells[cells.size() - 2], cells[cells.size() - 1])

## Grows one candidate arrow backwards from a head. Returns {body (tail → head), ray} or {}.
static func _grow(rng: Prng, pick: int, w: int, h: int, mask: PackedByteArray, owner: PackedInt32Array,
		free_on_cell: PackedInt32Array, len_min: int, len_max: int, turn: float, max_bends: int, cover_weight: float) -> Dictionary:
	var head := Vector2i((pick / 4) % w, (pick / 4) / w)
	var dir := pick % 4
	var own_ray := {}
	var ray := PackedInt32Array()
	var r := head + Dir.vec(dir)
	while r.x >= 0 and r.y >= 0 and r.x < w and r.y < h:
		own_ray[r] = true
		ray.append(r.y * w + r.x)
		r += Dir.vec(dir)
	var body: Array[Vector2i] = [head, head - Dir.vec(dir)]
	var in_body := {head: true, head - Dir.vec(dir): true}
	var walk := (dir + 2) % 4 # walking from the head toward the tail
	var goal := rng.range_int(len_min, len_max)
	var bends := 0
	while body.size() < goal:
		var cur: Vector2i = body[body.size() - 1]
		var options := PackedInt32Array()
		var option_weights := PackedFloat32Array()
		for k in 4:
			if k == (walk + 2) % 4 or (k != walk and bends >= max_bends):
				continue
			var n := cur + Dir.vec(k)
			if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h:
				continue
			var ni := n.y * w + n.x
			if owner[ni] != -1 or mask[ni] == 0 or in_body.has(n) or own_ray.has(n):
				continue
			var weight := (1.0 - turn) if k == walk else turn * 0.5
			weight *= 1.0 + cover_weight * minf(free_on_cell[ni], 3)
			options.append(k)
			option_weights.append(maxf(weight, 0.02))
		if options.is_empty():
			break
		var k := options[rng.pick_weighted(option_weights)]
		if k != walk:
			bends += 1
		walk = k
		var next := cur + Dir.vec(k)
		body.append(next)
		in_body[next] = true
	if body.size() < len_min:
		return {}
	body.reverse()
	return {"body": body, "ray": ray}

## Shaped construction (v2). Tiles a silhouette mask with snake paths drawn in a mix of shape
## modes (straight, L, U, stair, hook, free wander) and a mix of short / medium / long lengths, picks a
## head end for each, then repairs until the real rule clears the board:
##   peel everything that can leave; when stuck, flip (swap head and tail of) a stuck arrow whose
##   reversed way out is clear in the stuck position — that always makes progress because an
##   arrow's orientation never changes which cells are occupied — and only if no flip helps,
##   delete one stuck arrow (it becomes a hole).
## The stored solution is that peel order; callers re-validate with the real rule anyway.
## params: w, h, shape (Silhouettes name) or mask, fill, lengths [[min, max, weight], ...],
##         modes {mode: weight}, turn (wander bend chance), max_bends.
static func build_shaped(seed_value: int, params: Dictionary) -> Dictionary:
	var rng := Prng.new(seed_value)
	var w: int = params["w"]
	var h: int = params["h"]
	var mask: PackedByteArray = params["mask"] if params.has("mask") else Silhouettes.mask(str(params.get("shape", "pebble")), w, h)
	var fill: float = params.get("fill", 0.93)
	var lengths: Array = params.get("lengths", [[2, 3, 0.25], [4, 7, 0.45], [8, 12, 0.3]])
	var modes: Dictionary = params.get("modes", {"straight": 0.12, "L": 0.2, "U": 0.16, "stair": 0.14, "hook": 0.1, "wander": 0.28})
	var turn: float = params.get("turn", 0.32)
	var max_bends: int = params.get("max_bends", 5)
	var cells := w * h
	var owner := PackedInt32Array()
	owner.resize(cells)
	owner.fill(-1)
	var target := int(Silhouettes.cell_count(mask) * fill)
	var order := PackedInt32Array()
	for c in cells:
		if mask[c] == 1:
			order.append(c)
	for i in range(order.size() - 1, 0, -1):
		var j := rng.below(i + 1)
		var t := order[i]
		order[i] = order[j]
		order[j] = t
	var mode_names: Array = modes.keys()
	var mode_weights := PackedFloat32Array()
	for m in mode_names:
		mode_weights.append(float(modes[m]))
	# Long arrows first (they need room), then medium, then short ones fill what is left. Each band's
	# weight is its share of the covered cells.
	var sorted_bands := lengths.duplicate()
	sorted_bands.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) > int(b[0]))
	var total_weight := 0.0
	for band in sorted_bands:
		total_weight += float(band[2])
	var paths: Array = []
	var covered := 0
	var budget := 0
	for band in sorted_bands:
		budget += int(target * float(band[2]) / maxf(0.001, total_weight))
		var band_min := int(band[0])
		for start in order:
			if covered >= budget:
				break
			if owner[start] != -1:
				continue
			var goal := rng.range_int(band_min, int(band[1]))
			var mode: String = mode_names[rng.pick_weighted(mode_weights)]
			var path := _walk(rng, Vector2i(start % w, start / w), goal, mode, turn, max_bends, w, h, mask, owner)
			if path.size() < mini(band_min, 3) or path.size() < 2:
				continue
			for c in path:
				owner[c.y * w + c.x] = paths.size()
			covered += path.size()
			paths.append(path)
	for start in order: # leftovers become short arrows where two cells fit
		if covered >= target or owner[start] != -1:
			continue
		var path := _walk(rng, Vector2i(start % w, start / w), rng.range_int(2, 3), "wander", turn, max_bends, w, h, mask, owner)
		if path.size() < 2:
			continue
		for c in path:
			owner[c.y * w + c.x] = paths.size()
		covered += path.size()
		paths.append(path)
	# Head end: mostly the end that points into the picture (so few arrows start free); never an end
	# whose way out runs into the arrow itself. Repair below flips only where needed.
	var inward_bias: float = params.get("inward", 0.8)
	var center := Vector2(w - 1, h - 1) * 0.5
	var board := ArrowBoard.empty(w, h)
	for path in paths:
		var forward: Array[Vector2i] = path
		var backward: Array[Vector2i] = path.duplicate()
		backward.reverse()
		var options: Array = []
		if not _self_blocked(forward, w, h):
			options.append(forward)
		if not _self_blocked(backward, w, h):
			options.append(backward)
		if options.is_empty():
			continue
		var pick: Array = options[rng.below(options.size())]
		if options.size() == 2 and rng.chance(inward_bias):
			# Prefer the end whose way out is already blocked by another arrow of the full tiling, so
			# the board starts with few free arrows; break ties toward the picture's interior.
			var blocked_a := _ray_hits_other(options[0], owner, w, h)
			var blocked_b := _ray_hits_other(options[1], owner, w, h)
			if blocked_a != blocked_b:
				pick = options[0] if blocked_a else options[1]
			else:
				pick = options[0] if _inwardness(options[0], center) >= _inwardness(options[1], center) else options[1]
		board.add_arrow(pick)
	var repair := repair_until_solvable(board, rng)
	var arrows: Array = []
	var id_map := {}
	for id in repair["board"].live_ids():
		id_map[id] = arrows.size()
		var flat: Array = []
		for c in repair["board"].cells_of(id):
			flat.append(c.x)
			flat.append(c.y)
		arrows.append(flat)
	var sol: Array = []
	for id in repair["order"]:
		sol.append(id_map[id])
	return {"w": w, "h": h, "a": arrows, "sol": sol, "rules": ArrowBoard.RULES, "schema": ArrowLevel.SCHEMA,
		"seed": seed_value, "gen": VERSION_SHAPED, "shape": str(params.get("shape", "")), "flips": repair["flips"], "dropped": repair["dropped"]}

static func _ray_hits_other(path: Array, owner: PackedInt32Array, w: int, h: int) -> bool:
	var head: Vector2i = path[path.size() - 1]
	var d: Vector2i = head - path[path.size() - 2]
	var mine := owner[head.y * w + head.x]
	var c := head + d
	while c.x >= 0 and c.y >= 0 and c.x < w and c.y < h:
		var o := owner[c.y * w + c.x]
		if o != -1 and o != mine:
			return true
		c += d
	return false

static func _inwardness(path: Array, center: Vector2) -> float:
	var head: Vector2i = path[path.size() - 1]
	var d := Vector2(head - path[path.size() - 2])
	var to_center := center - Vector2(head)
	return d.dot(to_center.normalized()) if to_center.length() > 0.01 else 0.0

## Grows one snake from `start` following a shape mode; falls back to any free step when the plan
## is blocked. Never enters occupied, masked-out or already used cells.
static func _walk(rng: Prng, start: Vector2i, goal: int, mode: String, turn: float, max_bends: int, w: int, h: int,
		mask: PackedByteArray, owner: PackedInt32Array) -> Array[Vector2i]:
	var path: Array[Vector2i] = [start]
	var used := {start: true}
	var dir := rng.below(4)
	var bends := 0
	var side := 1 if rng.chance(0.5) else -1 # +1 = turn right, -1 = turn left
	var leg := 0 # cells walked since the last bend
	var leg_target := maxi(1, goal / 2)
	match mode:
		"U": leg_target = maxi(2, goal / 3)
		"stair": leg_target = rng.range_int(1, 2)
		"hook": leg_target = maxi(2, goal - 3)
	var u_turns := 0
	while path.size() < goal:
		var cur: Vector2i = path[path.size() - 1]
		var want := dir
		var planned_turn := false
		match mode:
			"straight":
				pass
			"L":
				if bends == 0 and leg >= leg_target:
					want = (dir + side + 4) % 4
					planned_turn = true
			"U":
				if u_turns < 2 and leg >= (leg_target if u_turns == 0 else rng.range_int(1, 2)):
					want = (dir + side + 4) % 4
					planned_turn = true
			"stair":
				if leg >= leg_target:
					want = (dir + side + 4) % 4
					planned_turn = true
			"hook":
				if bends < 2 and leg >= (leg_target if bends == 0 else 1):
					want = (dir + side + 4) % 4
					planned_turn = true
			_:
				if path.size() > 1 and rng.chance(turn):
					want = (dir + (1 if rng.chance(0.5) else -1) + 4) % 4
					planned_turn = true
		var options: Array[int] = [want]
		if planned_turn:
			options.append(dir) # plan blocked: keep straight
		else:
			options.append((dir + 1) % 4)
			options.append((dir + 3) % 4)
			if rng.chance(0.5):
				var a: int = options[1]
				options[1] = options[2]
				options[2] = a
		var moved := false
		for k in options:
			if path.size() > 1 and k == (dir + 2) % 4:
				continue
			if k != dir and path.size() > 1 and bends >= max_bends:
				continue
			var n: Vector2i = cur + Dir.vec(k)
			if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h:
				continue
			var ni := n.y * w + n.x
			if mask[ni] == 0 or owner[ni] != -1 or used.has(n):
				continue
			if k != dir and path.size() > 1:
				bends += 1
				leg = 0
				if mode == "stair":
					side = -side
					leg_target = rng.range_int(1, 2)
				elif mode == "U":
					u_turns += 1
			else:
				leg += 1
			dir = k
			path.append(n)
			used[n] = true
			moved = true
			break
		if not moved:
			break
	return path

## Peel; whenever stuck, flip a stuck arrow that can then leave, else delete one. Mutates and
## returns {board, order, flips, dropped}.
static func repair_until_solvable(board: ArrowBoard, rng: Prng) -> Dictionary:
	var state := board.duplicate_board()
	var order := PackedInt32Array()
	var flips := 0
	var dropped := 0
	while state.alive_count > 0:
		var free := state.escapable_ids()
		if not free.is_empty():
			for id in free:
				state.remove(id)
				order.append(id)
			continue
		var stuck := state.live_ids()
		var flippable := PackedInt32Array()
		for id in stuck:
			var reversed := state.cells_of(id)
			reversed.reverse()
			if _self_blocked(reversed, state.width, state.height):
				continue
			if _ray_clear(state, reversed):
				flippable.append(id)
		if not flippable.is_empty():
			# Prefer a flip whose new way out is still blocked on the full starting board: it can
			# leave later in the solve but does not add another free arrow at the start.
			var hidden := PackedInt32Array()
			for candidate in flippable:
				var turned := state.cells_of(candidate)
				turned.reverse()
				if not _ray_clear(board, turned):
					hidden.append(candidate)
			var pool := hidden if not hidden.is_empty() else flippable
			var id := pool[rng.below(pool.size())]
			var reversed := state.cells_of(id)
			reversed.reverse()
			_reorient(state, id, reversed)
			_reorient(board, id, reversed)
			flips += 1
			continue
		# Nothing can move even when flipped: drop the stuck arrow that blocks the most others.
		var victim := stuck[0]
		var most := -1
		for id in stuck:
			var blocks := 0
			for other in stuck:
				if other != id and state.first_obstacle(other) == id:
					blocks += 1
			if blocks > most:
				most = blocks
				victim = id
		state.remove(victim)
		board.remove(victim)
		dropped += 1
	return {"board": board, "order": order, "flips": flips, "dropped": dropped}

static func _ray_clear(board: ArrowBoard, cells: Array[Vector2i]) -> bool:
	var d := cells[cells.size() - 1] - cells[cells.size() - 2]
	var c := cells[cells.size() - 1] + d
	while board.in_bounds(c.x, c.y):
		if board.at(c.x, c.y) != ArrowBoard.EMPTY:
			return false
		c += d
	return true

## Hard-level tuning on a finished, solvable board: lowers the number of arrows that can leave at
## the start to at most `max_free` (keeping at least `min_free`) while the board stays solvable.
## Moves, in order of preference:
##   flip  — turn a free arrow around so its head points into the picture;
##   join  — join a free arrow end to end with a neighbouring arrow into one longer arrow (never
##           longer than `max_len`), keeping the joined arrow's head blocked;
##   shift — hand the free arrow's head cell to a touching neighbour, take a neighbour's end cell, or
##           grow into an empty cell of the picture, so the head moves or turns;
##   pair  — flip a free arrow together with one arrow of the deadlock that flip alone would cause.
## Cell occupancy never changes, so other arrows keep their blockers; every accepted move strictly
## lowers the free count and is re-checked for solvability with the exact solver.
static func tighten(level: Dictionary, seed_value: int, max_free: int, min_free: int = 2, max_len: int = 18,
		mask: PackedByteArray = PackedByteArray()) -> Dictionary:
	var rng := Prng.new(seed_value)
	var w: int = level["w"]
	var h: int = level["h"]
	var source := ArrowBoard.from_level(level)
	var paths: Array = []
	for id in source.size():
		paths.append(source.cells_of(id))
	var free := _board_of(paths, w, h).escapable_ids().size()
	var stats := {"flip": 0, "join": 0, "shift": 0, "pair": 0}
	var guard := 0
	while free > max_free and guard < 200:
		guard += 1
		var candidates := _board_of(paths, w, h).escapable_ids()
		for i in range(candidates.size() - 1, 0, -1):
			var j := rng.below(i + 1)
			var t := candidates[i]
			candidates[i] = candidates[j]
			candidates[j] = t
		var next: Array = []
		var kind := ""
		for id in candidates:
			next = _try_flip(paths, id, w, h, free, min_free)
			kind = "flip"
			if next.is_empty():
				next = _try_join(paths, id, w, h, free, min_free, max_len)
				kind = "join"
			if next.is_empty():
				next = _try_shift(paths, id, w, h, free, min_free, max_len, mask)
				kind = "shift"
			if not next.is_empty():
				break
		if next.is_empty():
			for id in candidates:
				next = _try_pair(paths, id, w, h, free, min_free)
				kind = "pair"
				if not next.is_empty():
					break
		if next.is_empty():
			break
		paths = next
		stats[kind] += 1
		free = _board_of(paths, w, h).escapable_ids().size()
	var result := level.duplicate(true)
	var arrows: Array = []
	for path in paths:
		var flat: Array = []
		for c in path:
			flat.append(c.x)
			flat.append(c.y)
		arrows.append(flat)
	result["a"] = arrows
	result["sol"] = Array(ArrowSolver.peel(_board_of(paths, w, h))["order"])
	result["tighten"] = stats
	return result

static func _board_of(paths: Array, w: int, h: int) -> ArrowBoard:
	var board := ArrowBoard.empty(w, h)
	for path in paths:
		board.add_arrow(path)
	return board

static func _reversed(path: Array[Vector2i]) -> Array[Vector2i]:
	var copy: Array[Vector2i] = path.duplicate()
	copy.reverse()
	return copy

## Accepts `candidate` (a full path list) when it is solvable and its free count is lower than
## `free` but not below `min_free`.
static func _accept(candidate: Array, w: int, h: int, free: int, min_free: int) -> bool:
	var board := _board_of(candidate, w, h)
	var now := board.escapable_ids().size()
	return now < free and now >= min_free and ArrowSolver.is_solvable(board)

static func _try_flip(paths: Array, id: int, w: int, h: int, free: int, min_free: int) -> Array:
	var turned := _reversed(paths[id])
	if _self_blocked(turned, w, h):
		return []
	var candidate := paths.duplicate()
	candidate[id] = turned
	return candidate if _accept(candidate, w, h, free, min_free) else []

static func _try_join(paths: Array, id: int, w: int, h: int, free: int, min_free: int, max_len: int) -> Array:
	var mine: Array[Vector2i] = paths[id]
	var owner := {}
	for k in paths.size():
		if k == id:
			continue
		var other: Array[Vector2i] = paths[k]
		owner[other[0]] = k
		owner[other[other.size() - 1]] = k
	var best: Array = []
	var best_len := 0
	for end in [mine[0], mine[mine.size() - 1]]:
		for d in 4:
			var n: Vector2i = end + Dir.vec(d)
			if not owner.has(n):
				continue
			var k: int = owner[n]
			var other: Array[Vector2i] = paths[k]
			if mine.size() + other.size() > max_len:
				continue
			var first: Array[Vector2i] = mine if end == mine[mine.size() - 1] else _reversed(mine)
			var second: Array[Vector2i] = other if n == other[0] else _reversed(other)
			var joined: Array[Vector2i] = first.duplicate()
			joined.append_array(second)
			for option in [joined, _reversed(joined)]:
				if _self_blocked(option, w, h):
					continue
				var candidate: Array = []
				for q in paths.size():
					if q == id:
						continue
					candidate.append(option if q == k else paths[q])
				if option.size() > best_len and _accept(candidate, w, h, free, min_free):
					best = candidate
					best_len = option.size()
	return best

static func _try_shift(paths: Array, id: int, w: int, h: int, free: int, min_free: int, max_len: int,
		mask: PackedByteArray) -> Array:
	var mine: Array[Vector2i] = paths[id]
	var head: Vector2i = mine[mine.size() - 1]
	var ends := {} # end cell -> [arrow, is_head]
	var used := {}
	for k in paths.size():
		var other: Array[Vector2i] = paths[k]
		for c in other:
			used[c] = true
		if k != id:
			ends[other[0]] = [k, false]
			ends[other[other.size() - 1]] = [k, true]
	var options: Array = [] # [[arrow, new path], ...]
	for d in 4:
		var n: Vector2i = head + Dir.vec(d)
		if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h:
			continue
		if ends.has(n):
			var k: int = ends[n][0]
			var other: Array[Vector2i] = paths[k]
			# Give our head cell to the neighbour whose end touches it.
			if mine.size() >= 3 and other.size() < max_len:
				var shrunk: Array[Vector2i] = mine.slice(0, mine.size() - 1)
				var grown: Array[Vector2i] = []
				if ends[n][1]:
					grown = other.duplicate()
					grown.append(head)
				else:
					grown = [head]
					grown.append_array(other)
				options.append([[id, shrunk], [k, grown]])
			# Take the neighbour's end cell: our head steps (and maybe turns) into it.
			if other.size() >= 3 and mine.size() < max_len:
				var longer: Array[Vector2i] = mine.duplicate()
				longer.append(n)
				var rest: Array[Vector2i] = other.slice(0, other.size() - 1) if ends[n][1] else other.slice(1)
				options.append([[id, longer], [k, rest]])
		elif not mask.is_empty() and mask[n.y * w + n.x] == 1 and not used.has(n) and mine.size() < max_len:
			var longer: Array[Vector2i] = mine.duplicate()
			longer.append(n)
			options.append([[id, longer]])
	for option in options:
		var candidate := paths.duplicate()
		var ok := true
		for change in option:
			var path: Array[Vector2i] = change[1]
			if path.size() < 2 or _self_blocked(path, w, h):
				ok = false
				break
			candidate[change[0]] = path
		if ok and _accept(candidate, w, h, free, min_free):
			return candidate
	return []

static func _try_pair(paths: Array, id: int, w: int, h: int, free: int, min_free: int) -> Array:
	var turned := _reversed(paths[id])
	if _self_blocked(turned, w, h):
		return []
	var flipped := paths.duplicate()
	flipped[id] = turned
	var stuck := ArrowSolver.stuck_ids(_board_of(flipped, w, h))
	for other in stuck:
		if other == id:
			continue
		var second := _reversed(flipped[other])
		if _self_blocked(second, w, h):
			continue
		var candidate := flipped.duplicate()
		candidate[other] = second
		if _accept(candidate, w, h, free, min_free):
			return candidate
	return []

static func _ray_len(x: int, y: int, d: int, w: int, h: int) -> int:
	match d:
		Dir.UP: return y
		Dir.RIGHT: return w - 1 - x
		Dir.DOWN: return h - 1 - y
		_: return x

## Structural repetition check under 8 symmetries: the share of cells whose path flows the same way
## (each cell keyed by the direction toward the next cell of its arrow, heads by their direction).
## Two unrelated dense boards land around 0.25-0.35; near copies approach 1.
static func similarity(a: Dictionary, b: Dictionary) -> float:
	var sig_a := _signature(a, 0)
	var best := 0.0
	for sym in 8:
		var sig_b := _signature(b, sym)
		var shared := 0
		for key in sig_b:
			if sig_a.has(key) and sig_a[key] == sig_b[key]:
				shared += 1
		best = maxf(best, float(shared) / maxf(1.0, maxf(sig_a.size(), sig_b.size())))
	return best

static func _signature(level: Dictionary, sym: int) -> Dictionary:
	var board := ArrowBoard.from_level(level)
	var result := {}
	for id in board.size():
		var cells := board.cells_of(id)
		for i in cells.size():
			var flow := board.dirs[id] + 4 if i == cells.size() - 1 else ArrowBoard.direction_between(cells[i], cells[i + 1])
			result[_map(cells[i], board.width, board.height, sym)] = _map_dir(flow % 4, sym) + (4 if flow >= 4 else 0)
	return result

static func _map_dir(d: int, sym: int) -> int:
	var r := (d + sym % 4) % 4
	if sym >= 4 and (r == Dir.LEFT or r == Dir.RIGHT):
		r = (r + 2) % 4
	return r

static func _map(c: Vector2i, w: int, h: int, sym: int) -> Vector2i:
	var p := c
	var cw := w
	var ch := h
	for i in sym % 4:
		p = Vector2i(ch - 1 - p.y, p.x)
		var t := cw
		cw = ch
		ch = t
	if sym >= 4:
		p = Vector2i(cw - 1 - p.x, p.y)
	return p
