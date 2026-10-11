extends SceneTree
## Property tests for the arrow-path-2 generators over many seeds:
##   godot --headless --path . -s res://tests/arrow_generator_property_tests.gd -- [COUNT]
## Mix per 10 boards: 2 reverse builds, 4 dense builds (+ repair), 4 silhouette builds (the method used
## for chapter content; half of them also go through the HARD tightening pass).
## Every board must have connected, in-bounds, non-overlapping paths of ≥2 cells, no head pointing
## into its own body, a stored solution the real rule replays, exact-peel solvability, agreement of
## the linear solver with peeling (also on deliberately perturbed copies that may deadlock), arrows
## inside the silhouette, bounded generation time, determinism for the same seed, and few duplicates.
const SIZES := [[5, 7], [6, 8], [7, 9], [8, 10], [8, 12], [9, 13]]
const SHAPED_SIZES := [[10, 12], [12, 16], [14, 18], [16, 20], [18, 24], [20, 24]]
var checks := 0
var failures := 0

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var count := int(args[0]) if args.size() > 0 else 10000
	var t0 := Time.get_ticks_msec()
	var slowest := 0
	var repeats := 0
	var seen := {}
	var dense_count := 0
	var free_sum := 0.0
	var arrows_sum := 0
	var shaped_count := 0
	var shaped_free := 0.0
	var tight_count := 0
	var tight_free := 0.0
	var perturbed := 0
	var shape_names: Array = Silhouettes.SHAPES.keys()
	for i in count:
		var kind := i % 10
		var seed_value := Prng.derive(0xA770, "p%d" % i)
		var level := {}
		var mask := PackedByteArray()
		var start := Time.get_ticks_usec()
		var params := {}
		if kind < 6:
			var size: Array = SIZES[i % SIZES.size()]
			var shape: String = ArrowGenerator.SHAPES[(i / SIZES.size()) % ArrowGenerator.SHAPES.size()]
			params = {"w": size[0], "h": size[1], "shape": shape, "fill": 0.85 + (i % 4) * 0.04,
				"len_min": 3, "len_max": 6 + i % 5, "turn": 0.3 + (i % 3) * 0.08, "max_bends": 2 + i % 3}
			level = ArrowGenerator.build(seed_value, params) if kind < 2 else ArrowGenerator.build_dense(seed_value, params)
		else:
			var size: Array = SHAPED_SIZES[i % SHAPED_SIZES.size()]
			mask = Silhouettes.mask(str(shape_names[(i / 10) % shape_names.size()]), size[0], size[1])
			params = {"w": size[0], "h": size[1], "mask": mask, "lengths": [[6 + i % 5, 12 + i % 4, 0.5], [3, 5, 0.4], [2, 2, 0.1]],
				"turn": 0.25 + (i % 3) * 0.05, "max_bends": 3 + i % 4}
			level = ArrowGenerator.build_shaped(seed_value, params)
			if kind >= 8:
				level = ArrowGenerator.tighten(level, seed_value ^ 0x51ED, 5, 2, 18, mask)
		var elapsed := Time.get_ticks_usec() - start
		slowest = maxi(slowest, elapsed)
		_check(elapsed < 1500000, "seed %d generation took %d us" % [seed_value, elapsed])
		level["id"] = "p%d" % i
		var problems := ArrowLevel.check_structure(level)
		_check(problems.is_empty(), "seed %d structure %s" % [seed_value, problems])
		if not problems.is_empty():
			continue
		var board := ArrowBoard.from_level(level)
		_check(ArrowSolver.replay(board, PackedInt32Array(level["sol"])), "seed %d stored solution replays" % seed_value)
		var solvable: bool = ArrowSolver.peel(board)["solvable"]
		_check(solvable, "seed %d solvable" % seed_value)
		_check(ArrowSolver.is_solvable(board) == solvable, "seed %d linear solver agrees with peeling" % seed_value)
		_check(board.size() >= 1, "seed %d has arrows" % seed_value)
		if not mask.is_empty():
			var inside := true
			for id in board.size():
				for c in board.cells_of(id):
					if mask[c.y * board.width + c.x] != 1:
						inside = false
			_check(inside, "seed %d arrows inside the silhouette" % seed_value)
			if kind >= 8:
				tight_count += 1
				tight_free += board.escapable_ids().size()
			else:
				shaped_count += 1
				shaped_free += board.escapable_ids().size()
		elif kind >= 2:
			dense_count += 1
			free_sum += float(board.escapable_ids().size()) / maxf(1.0, board.size())
		arrows_sum += board.size()
		# A perturbed copy (some arrows turned around) may deadlock; both solvers must still agree.
		if i % 7 == 0:
			var copy := board.duplicate_board()
			var rng := Prng.new(seed_value)
			for k in 3:
				var id := rng.below(copy.size())
				var turned := copy.cells_of(id)
				turned.reverse()
				if not ArrowGenerator._self_blocked(turned, copy.width, copy.height):
					ArrowGenerator._reorient(copy, id, turned)
			perturbed += 1
			_check(ArrowSolver.is_solvable(copy) == bool(ArrowSolver.peel(copy)["solvable"]), "seed %d perturbed: solvers agree" % seed_value)
		var key := ArrowLevel.content_hash(level)
		if seen.has(key):
			repeats += 1
		seen[key] = true
		if i % 250 == 0 or i % 250 == 7:
			var again := {}
			if kind < 6:
				again = ArrowGenerator.build(seed_value, params) if kind < 2 else ArrowGenerator.build_dense(seed_value, params)
			else:
				again = ArrowGenerator.build_shaped(seed_value, params)
				if kind >= 8:
					again = ArrowGenerator.tighten(again, seed_value ^ 0x51ED, 5, 2, 18, mask)
			again["id"] = level["id"]
			_check(JSON.stringify(again) == JSON.stringify(level), "seed %d deterministic" % seed_value)
	_check(float(repeats) / count < 0.01, "too many identical boards: %d" % repeats)
	print("ARROW_GENERATOR_PROPERTIES: boards=%d checks=%d failures=%d duplicates=%d avg_arrows=%.1f dense_avg_initial_free=%.2f shaped_avg_free=%.1f tightened_avg_free=%.1f perturbed=%d slowest=%dms total=%ds" % [
		count, checks, failures, repeats, float(arrows_sum) / count, free_sum / maxf(1.0, dense_count),
		shaped_free / maxf(1.0, shaped_count), tight_free / maxf(1.0, tight_count), perturbed, slowest / 1000, (Time.get_ticks_msec() - t0) / 1000])
	quit(0 if failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		if failures < 20:
			printerr("FAIL: " + message)
