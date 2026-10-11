class_name ArrowSolver
extends RefCounted
## Solver and difficulty signals for "arrow-path-2". The basic ruleset is monotone: removing an
## arrow only frees cells, so peeling every escapable arrow layer by layer is an exact test.

static func peel(source: ArrowBoard) -> Dictionary:
	var board := source.duplicate_board()
	var order := PackedInt32Array()
	var layers: Array[PackedInt32Array] = []
	while board.alive_count > 0:
		var layer := board.escapable_ids()
		if layer.is_empty():
			break
		for id in layer:
			board.remove(id)
			order.append(id)
		layers.append(layer)
	return {"solvable": board.alive_count == 0, "order": order, "layers": layers}

## Exact solvability with the same answer as peel, in time linear in the total ray length: an arrow
## becomes free once every occupied cell on its way out has been vacated. Returns the arrows that
## can never leave (empty when the board is solvable).
static func stuck_ids(source: ArrowBoard) -> PackedInt32Array:
	var w := source.width
	var h := source.height
	var watchers: Array = []
	watchers.resize(w * h)
	var blocked := PackedInt32Array()
	blocked.resize(source.size())
	var queue := PackedInt32Array()
	for id in source.size():
		if not source.is_alive(id):
			continue
		var step := Dir.vec(source.dirs[id])
		var c := source.head(id) + step
		var count := 0
		while c.x >= 0 and c.y >= 0 and c.x < w and c.y < h:
			var i := c.y * w + c.x
			if source.grid[i] != ArrowBoard.EMPTY:
				count += 1
				if watchers[i] == null:
					watchers[i] = []
				watchers[i].append(id)
			c += step
		blocked[id] = count
		if count == 0:
			queue.append(id)
	var gone := PackedByteArray()
	gone.resize(source.size())
	var k := 0
	while k < queue.size():
		var id := queue[k]
		k += 1
		gone[id] = 1
		for i in source.paths[id]:
			if watchers[i] == null:
				continue
			for other in watchers[i]:
				blocked[other] -= 1
				if blocked[other] == 0:
					queue.append(other)
	var stuck := PackedInt32Array()
	for id in source.size():
		if source.is_alive(id) and gone[id] == 0:
			stuck.append(id)
	return stuck

static func is_solvable(source: ArrowBoard) -> bool:
	return stuck_ids(source).is_empty()

## Replays a removal order with the real escape rule.
static func replay(source: ArrowBoard, order: PackedInt32Array) -> bool:
	var board := source.duplicate_board()
	for id in order:
		if not board.can_escape(id):
			return false
		board.remove(id)
	return board.is_cleared()

## Discovery effort, not move count: every solve removes each arrow exactly once.
## `mask` (optional) marks the silhouette so "visible starts" can be judged: a free arrow whose way
## out runs only through empty space outside the picture is easy to spot.
static func metrics(source: ArrowBoard, mask: PackedByteArray = PackedByteArray()) -> Dictionary:
	var n := source.alive_count
	var peel_result := peel(source)
	var layers: Array = peel_result["layers"]
	var board := source.duplicate_board()
	var total_len := 0
	var max_len := 0
	var total_bends := 0
	var max_bends := 0
	var straight := 0
	var multi_bend := 0
	var bands := [0, 0, 0] # ≤3, 4-7, ≥8 cells
	var lengths: Array[int] = []
	var far_blocks := 0
	var blocked_by := {}
	for id in board.live_ids():
		var length := board.length(id)
		lengths.append(length)
		total_len += length
		max_len = maxi(max_len, length)
		var b := board.bends(id)
		total_bends += b
		max_bends = maxi(max_bends, b)
		if b == 0:
			straight += 1
		if b >= 3:
			multi_bend += 1
		bands[0 if length <= 3 else (1 if length <= 7 else 2)] += 1
		var blocker := board.first_obstacle(id)
		if blocker != ArrowBoard.EMPTY:
			blocked_by[blocker] = int(blocked_by.get(blocker, 0)) + 1
			if board.gap_to_obstacle(id) >= 3:
				far_blocks += 1
	var fanout := 0
	for k in blocked_by:
		fanout = maxi(fanout, int(blocked_by[k]))
	var avg_len := float(total_len) / maxf(1.0, n)
	var variance := 0.0
	for length in lengths:
		variance += pow(length - avg_len, 2)
	var len_std := sqrt(variance / maxf(1.0, n))
	var contacts := 0
	for y in board.height:
		for x in board.width:
			var a := board.at(x, y)
			if a == ArrowBoard.EMPTY:
				continue
			for d in [Vector2i(1, 0), Vector2i(0, 1)]:
				var o := board.at(x + d.x, y + d.y)
				if o != ArrowBoard.EMPTY and o != a:
					contacts += 1
	var free := board.escapable_ids()
	var initial_free := free.size()
	var visible_free := 0
	for id in free:
		if mask.is_empty() or _exit_outside(board, id, mask):
			visible_free += 1
	var choices := PackedInt32Array()
	var cascade := 0
	var opened_total := 0
	var keys := 0
	var est := 0.0
	while board.alive_count > 0 and not free.is_empty():
		choices.append(free.size())
		# Heuristic search cost: more live arrows and fewer options take longer to scan.
		est += 0.25 + 0.45 * log(1.0 + float(board.alive_count) / free.size()) / log(2.0)
		board.remove(free[0])
		var next := board.escapable_ids()
		var opened := maxi(0, next.size() - (free.size() - 1))
		cascade = maxi(cascade, opened)
		opened_total += opened
		if opened >= 2:
			keys += 1
		free = next
	var narrow := 0
	var choice_sum := 0
	for i in choices.size():
		choice_sum += choices[i]
		if choices[i] <= 2 and choices.size() - i > 2:
			narrow += 1
	var free_ratio := float(initial_free) / maxf(1.0, n)
	var avg_choices := float(choice_sum) / maxf(1.0, choices.size())
	var score := layers.size() * 1.0 + (1.0 - free_ratio) * 4.0 + narrow * 0.4 + far_blocks * 0.15 \
		+ n * 0.12 + total_bends * 0.05 - minf(avg_choices, 6.0) * 0.2
	return {"n": n, "cells": total_len, "density": snappedf(float(total_len) / float(source.width * source.height), 0.001),
		"avg_len": snappedf(avg_len, 0.01), "len_std": snappedf(len_std, 0.01), "max_len": max_len,
		"short": bands[0], "medium": bands[1], "long": bands[2], "bends": total_bends, "max_bends": max_bends,
		"straight": straight, "multi_bend": multi_bend, "layers": layers.size(), "initial_free": initial_free,
		"visible_free": visible_free, "free_ratio": snappedf(free_ratio, 0.001), "avg_choices": snappedf(avg_choices, 0.01),
		"narrow": narrow, "cascade": cascade, "keys": keys, "fanout": fanout,
		"avg_open": snappedf(float(opened_total) / maxf(1.0, choices.size()), 0.01), "far_blocks": far_blocks,
		"contacts": contacts, "est_seconds": snappedf(est, 0.1), "score": snappedf(score, 0.01),
		"challenge": snappedf(challenge(est, initial_free, layers.size(), source.width, source.height), 0.1)}

## Logical px a board can use on a phone in portrait (480-wide layout minus margins and HUD).
const PHONE_BOARD := Vector2(460.0, 820.0)

## One number for how demanding a board is to play, used for the chapter's rhythm (not shown to
## players). Arrow count alone is not difficulty: it starts from the estimated search time (which
## grows with live arrows and shrinks with free choices) and multiplies in
## - entry: fewer ways in at the start (+8 % for each free arrow under 6),
## - depth: the removal chain (+1 % per layer),
## - reading: overview cells under 22 px on a phone (up to +60 %, the effort of zooming/panning).
static func challenge(est: float, initial_free: int, layers: int, w: int, h: int) -> float:
	var cell := minf(PHONE_BOARD.x / (w + 0.64), PHONE_BOARD.y / (h + 0.64))
	var entry := 1.0 + 0.08 * maxf(0.0, 6.0 - minf(float(initial_free), 6.0))
	var depth := 1.0 + layers / 100.0
	var reading := 1.0 + 0.6 * maxf(0.0, (22.0 - cell) / 22.0)
	return est * entry * depth * reading

## The arrow's way out crosses only cells outside the silhouette (easy to see).
static func _exit_outside(board: ArrowBoard, id: int, mask: PackedByteArray) -> bool:
	for c in board.ray(id):
		if mask[c.y * board.width + c.x] == 1:
			return false
	return true

## Suggests the escapable arrow that frees the most others (read-only).
static func best_hint(board: ArrowBoard) -> int:
	var free := board.escapable_ids()
	var best := -1
	var best_score := -1
	for id in free:
		var score := 0
		for other in board.live_ids():
			if other != id and board.first_obstacle(other) == id:
				score += 1
		if score > best_score:
			best_score = score
			best = id
	return best
