extends SceneTree
## Property tests over many seeds. Run:
##   godot --headless --path . -s res://tests/legacy/generator_property_tests.gd -- [COUNT]
## Every generated board must have unique in-bounds cells, valid arrows, a stored solution that
## clears it under the real rules, bounded generation time, and tuned difficulty near its target.
const SIZES := [[5, 6], [6, 7], [6, 8], [7, 8], [7, 9]]
var failures := 0
var checks := 0

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var count := int(args[0]) if args.size() > 0 else 10000
	var t0 := Time.get_ticks_msec()
	var slowest := 0
	var shortfall := 0
	var tuned_gap_sum := 0.0
	var tuned_count := 0
	var repeats := 0
	var seen := {}
	var previous := {}
	for i in count:
		var size: Array = SIZES[i % SIZES.size()]
		var shape: String = LevelGenerator.SHAPES[(i / SIZES.size()) % LevelGenerator.SHAPES.size()]
		var symmetric := i % 2 == 0
		var mask := LevelGenerator.shape_mask(shape, size[0], size[1])
		var cells := 0
		for v in mask:
			cells += v
		var n := int(cells * (0.55 + (i % 5) * 0.06))
		var seed_value := Prng.derive(0xC0FFEE, "p%d" % i)
		var start := Time.get_ticks_usec()
		var level := LevelGenerator.build_basic(seed_value, {"w": size[0], "h": size[1], "n": n, "shape": shape,
			"block_bias": 1.0, "path_bias": 0.8, "symmetry": "rot180" if symmetric else ""})
		var target := 6.0 + (i % 7) * 2.0
		var tuned := i % 4 == 0
		var before_gap := absf(LevelGenerator.quick_score(BoardState.from_level(level)) - target)
		if tuned:
			level = LevelGenerator.tune_basic(level, seed_value ^ 7, target, 220, 0.42, symmetric)
		var elapsed := Time.get_ticks_usec() - start
		slowest = maxi(slowest, elapsed)
		_check(elapsed < 250000, "seed %d generation over 250ms (%dus)" % [seed_value, elapsed])
		if level["b"].size() < n - 3:
			shortfall += 1
		_check(LevelValidator.check_structure(level).is_empty(), "seed %d structure %s" % [seed_value, LevelValidator.check_structure(level)])
		for e in level["b"]:
			_check(mask[int(e[1]) * size[0] + int(e[0])] == 1, "seed %d block outside mask" % seed_value)
		var board := BoardState.from_level(level)
		_check(LevelValidator.replay(board, PackedInt32Array(level["sol"])), "seed %d solution replay" % seed_value)
		_check(LevelValidator.peel(board)["solvable"], "seed %d peel" % seed_value)
		if tuned:
			var after_gap := absf(LevelGenerator.quick_score(board) - target)
			_check(after_gap <= before_gap + 0.0001, "seed %d tuning moved away from target" % seed_value)
			tuned_gap_sum += after_gap
			tuned_count += 1
		var key := LevelData.content_hash(level)
		if seen.has(key):
			repeats += 1
		seen[key] = true
		if i % 500 == 0 and i > 0:
			# Same seed + same version must reproduce the identical board.
			var again := LevelGenerator.build_basic(seed_value, {"w": size[0], "h": size[1], "n": n, "shape": shape,
				"block_bias": 1.0, "path_bias": 0.8, "symmetry": "rot180" if symmetric else ""})
			if tuned:
				again = LevelGenerator.tune_basic(again, seed_value ^ 7, target, 220, 0.42, symmetric)
			_check(JSON.stringify(again) == JSON.stringify(level), "seed %d not deterministic" % seed_value)
	var avg_gap := tuned_gap_sum / maxf(1.0, tuned_count)
	_check(float(repeats) / count < 0.01, "too many identical boards: %d" % repeats)
	# Targets span 6..18 on every mask size; small masks cannot reach the top, so this bound is loose.
	_check(avg_gap < 2.5, "tuned difficulty misses target by %.2f on average" % avg_gap)
	print("GENERATOR_PROPERTIES: boards=%d checks=%d failures=%d duplicates=%d short_of_target_n=%d tuned=%d avg_target_gap=%.2f slowest=%dms total=%ds" % [
		count, checks, failures, repeats, shortfall, tuned_count, avg_gap, slowest / 1000, (Time.get_ticks_msec() - t0) / 1000])
	quit(0 if failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		if failures < 20:
			printerr("FAIL: " + message)
