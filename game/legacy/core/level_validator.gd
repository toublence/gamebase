class_name LevelValidator
extends RefCounted
## Basic rules are monotone: removing an escapable block only frees cells, so peeling every
## escapable block layer by layer is an exact solvability test. Switch rules are not monotone and
## use SwitchSolver instead.

## Peels the board. Returns {solvable, order, layers}. Does not mutate the input.
static func peel(source: BoardState) -> Dictionary:
	var board := source.duplicate_board()
	var order := PackedInt32Array()
	var layers: Array[PackedInt32Array] = []
	while board.alive_count > 0:
		var layer := MoveResolver.escapable_ids(board)
		if layer.is_empty():
			break
		for id in layer:
			board.remove(id)
			order.append(id)
		layers.append(layer)
	return {"solvable": board.alive_count == 0, "order": order, "layers": layers}

## Replays an explicit solution with the real game rules (switch rotation included).
static func replay(source: BoardState, order: PackedInt32Array) -> bool:
	var board := source.duplicate_board()
	for id in order:
		if not MoveResolver.can_escape(board, id):
			return false
		MoveResolver.apply_escape(board, id)
	return board.is_cleared()

## Structural sanity independent of solvability.
static func check_structure(level: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var w := int(level.get("w", 0))
	var h := int(level.get("h", 0))
	if w < 2 or h < 2 or w > 9 or h > 11:
		errors.append("board size %dx%d out of range" % [w, h])
		return errors
	var seen := {}
	var blocks: Array = level.get("b", [])
	if blocks.is_empty():
		errors.append("no blocks")
	for i in blocks.size():
		var entry: Array = blocks[i]
		if entry.size() < 3:
			errors.append("block %d malformed" % i)
			continue
		var x := int(entry[0])
		var y := int(entry[1])
		var d := int(entry[2])
		if x < 0 or y < 0 or x >= w or y >= h:
			errors.append("block %d outside board" % i)
		if d < 0 or d > 3:
			errors.append("block %d invalid direction" % i)
		var key := Vector2i(x, y)
		if seen.has(key):
			errors.append("block %d overlaps block %d" % [i, seen[key]])
		seen[key] = i
		if entry.size() > 3 and int(entry[3]) == BoardState.KIND_SWITCH:
			var targets: Array = entry[4] if entry.size() > 4 else []
			if targets.is_empty():
				errors.append("switch %d has no targets" % i)
			for target in targets:
				if int(target) < 0 or int(target) >= blocks.size() or int(target) == i:
					errors.append("switch %d invalid target" % i)
	return errors

## Difficulty signals for the basic ruleset. Every normal solve takes exactly n moves, so this
## measures discovery effort (how hidden the next free block is), not path length.
static func metrics(source: BoardState) -> Dictionary:
	var n := source.alive_count
	var result := peel(source)
	var layers: Array = result["layers"]
	var board := source.duplicate_board()
	var choices := PackedInt32Array()
	var opened := PackedInt32Array()
	var free := MoveResolver.escapable_ids(board)
	var initial_free := free.size()
	var long_blocks := 0
	var dir_counts := [0, 0, 0, 0]
	for id in board.live_ids():
		dir_counts[board.dirs[id]] += 1
		var blocker := MoveResolver.first_obstacle(board, id)
		if blocker != BoardState.EMPTY and MoveResolver.gap_to(board, id, blocker) >= 2:
			long_blocks += 1
	# Canonical play: always take the free block in reading order. Measures how narrow the funnel is.
	while board.alive_count > 0 and not free.is_empty():
		choices.append(free.size())
		var pick := free[0]
		board.remove(pick)
		var next := MoveResolver.escapable_ids(board)
		opened.append(maxi(0, next.size() - (free.size() - 1)))
		free = next
	var narrow := 0
	var choice_sum := 0
	for i in choices.size():
		choice_sum += choices[i]
		if choices[i] <= 2 and choices.size() - i > 3:
			narrow += 1
	var cascade := 0
	var open_sum := 0
	for value in opened:
		cascade = maxi(cascade, value)
		open_sum += value
	var max_dir := 0
	for count in dir_counts:
		max_dir = maxi(max_dir, count)
	var avg_choices := float(choice_sum) / maxf(1.0, choices.size())
	var free_ratio := float(initial_free) / maxf(1.0, n)
	var density := float(n) / float(source.width * source.height)
	var score := layers.size() * 1.1 + (1.0 - free_ratio) * 3.5 + narrow * 0.35 \
		+ long_blocks * 0.12 + n * 0.05 - minf(avg_choices, 8.0) * 0.18
	return {
		"n": n, "layers": layers.size(), "initial_free": initial_free,
		"free_ratio": snappedf(free_ratio, 0.001), "avg_choices": snappedf(avg_choices, 0.01),
		"narrow_steps": narrow, "cascade": cascade, "avg_open": snappedf(float(open_sum) / maxf(1.0, opened.size()), 0.01),
		"long_blocks": long_blocks, "dir_share": snappedf(float(max_dir) / maxf(1.0, n), 0.001),
		"density": snappedf(density, 0.001), "score": snappedf(score, 0.01),
	}
