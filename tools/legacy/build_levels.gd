extends SceneTree
## Level content builder. Development only; tools/ is excluded from every export.
##   godot --headless --path . -s res://tools/legacy/build_levels.gd -- build
##   godot --headless --path . -s res://tools/legacy/build_levels.gd -- candidates W H N SHAPE COUNT [MIN MAX]
##   godot --headless --path . -s res://tools/legacy/build_levels.gd -- masks
## Output (bundled, versioned): game/data/campaign.json, switch.json, daily.json.
## The same generator version + seed always produces the same board; bump CONTENT_VERSION and
## LevelGenerator.VERSION together when content changes so saved attempts are discarded safely.
const CONTENT_VERSION := "2026.10.1"
const HANDMADE := "res://tools/levels_src/legacy/campaign_handmade.txt"
const SWITCH_HANDMADE := "res://tools/levels_src/legacy/switch_handmade.txt"
const OUT_DIR := "res://game/data/legacy/"
const CAMPAIGN_SEED := 0x0711A9
const DAILY_SEED := 0xDA11E5
const SWITCH_SEED := 0x5317C4
const DAILY_COUNT := 365
const OFFSETS := {"easy": -2.0, "medium": 0.0, "hard": 2.2, "relief": -3.5}
const DENSITY := {"easy": 0.62, "medium": 0.68, "hard": 0.72, "relief": 0.8}
const TAG_CYCLE := ["easy", "medium", "hard", "relief"]

var _errors: Array[String] = []

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var command := args[0] if args.size() > 0 else "build"
	match command:
		"candidates": _candidates(args)
		"masks": _print_masks()
		_: _build()
	quit(1 if not _errors.is_empty() else 0)

# --- build -----------------------------------------------------------------------------------

func _build() -> void:
	var t0 := Time.get_ticks_msec()
	var campaign: Array = []
	for entry in _read_authored(HANDMADE):
		campaign.append(_finalize_basic(entry, 0, "hand"))
	for index in range(campaign.size() + 1, 101):
		campaign.append(_generate_campaign(index, campaign))
	print("campaign: %d levels in %ds" % [campaign.size(), (Time.get_ticks_msec() - t0) / 1000])
	var switches: Array = []
	for entry in _read_authored(SWITCH_HANDMADE):
		switches.append(_finalize_switch(entry, 0, "hand"))
	for index in range(switches.size() + 1, 21):
		switches.append(_generate_switch(index, switches))
	print("switch: %d levels in %ds" % [switches.size(), (Time.get_ticks_msec() - t0) / 1000])
	var daily: Array = []
	for index in range(1, DAILY_COUNT + 1):
		daily.append(_generate_daily(index))
	print("daily: %d levels in %ds" % [daily.size(), (Time.get_ticks_msec() - t0) / 1000])
	for pack in [["campaign", campaign], ["switch", switches], ["daily", daily]]:
		_self_check(pack[0], pack[1])
	if not _errors.is_empty():
		for e in _errors:
			printerr(e)
		return
	_write("campaign", campaign)
	_write("switch", switches)
	_write("daily", daily)
	_print_curve(campaign, switches)
	print("BUILD_OK %ds" % ((Time.get_ticks_msec() - t0) / 1000))

func _write(pack: String, levels: Array) -> void:
	var data := {"pack": pack, "content_version": CONTENT_VERSION, "generator_version": LevelGenerator.VERSION,
		"ruleset_version": LevelData.RULES_SWITCH if pack == "switch" else LevelData.RULES_BASIC, "levels": levels}
	var file := FileAccess.open(OUT_DIR + pack + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "", false))
	file.close()

## Parses "@ id tag [soft] [coach=KEY]" headers followed by ASCII rows.
func _read_authored(path: String) -> Array:
	var result: Array = []
	var text := FileAccess.get_file_as_string(path)
	var current := {}
	var rows := PackedStringArray()
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("#"):
			continue
		if line.begins_with("@"):
			if not current.is_empty():
				current["ascii"] = "\n".join(rows)
				result.append(current)
			var parts := line.substr(1).strip_edges().split(" ", false)
			current = {"id": parts[0], "tag": parts[1], "soft": parts.has("soft"), "coach": ""}
			for part in parts:
				if part.begins_with("coach="):
					current["coach"] = part.substr(6)
			rows = PackedStringArray()
		elif not line.is_empty():
			rows.append(line)
	if not current.is_empty():
		current["ascii"] = "\n".join(rows)
		result.append(current)
	return result

func _finalize_basic(entry: Dictionary, seed_value: int, source: String) -> Dictionary:
	var level := LevelData.parse_ascii(entry["ascii"])
	level["rules"] = LevelData.RULES_BASIC
	return _decorate(level, entry, seed_value, source)

func _decorate(level: Dictionary, entry: Dictionary, seed_value: int, source: String) -> Dictionary:
	level["id"] = entry["id"]
	level["seed"] = seed_value
	level["gen"] = LevelGenerator.VERSION if source == "gen" else "hand-1"
	level["src"] = source
	level["tag"] = entry["tag"]
	if entry.get("soft", false):
		level["soft"] = true
	if not str(entry.get("coach", "")).is_empty():
		level["coach"] = entry["coach"]
	if entry.has("shape"):
		level["shape"] = entry["shape"]
	var board := BoardState.from_level(level)
	if level["rules"] == LevelData.RULES_BASIC:
		var peel := LevelValidator.peel(board)
		if not peel["solvable"]:
			_errors.append("%s: not solvable" % level["id"])
		level["sol"] = Array(peel["order"])
		level["m"] = LevelValidator.metrics(board)
	else:
		var a := SwitchSolver.analyze(board)
		if a["status"] != "solvable":
			_errors.append("%s: switch status %s" % [level["id"], a["status"]])
		level["sol"] = Array(a.get("solution", PackedInt32Array()))
		level["m"] = {"n": board.size(), "random_win": a.get("random_win", 0.0), "traps": a.get("trap_first_moves", 0),
			"states": a.get("states", 0), "dead_states": a.get("dead_states", 0), "first_moves": a.get("first_moves", 0),
			"switches": _count_switches(level), "needs_switch": _needs_switch(level)}
	level["hash"] = LevelData.content_hash(level)
	return level

# --- campaign generation -----------------------------------------------------------------------

func _campaign_spec(index: int) -> Dictionary:
	var chapter := (index - 1) / 20 # 1..4 for generated levels
	var position := (index - 1) % 20
	var tag: String = TAG_CYCLE[position % 4]
	var sizes := [[6, 7], [6, 8], [7, 8], [7, 9], [7, 9]]
	var size: Array = sizes[clampi(chapter - 1 + (position / 10), 0, sizes.size() - 1)]
	var shape: String = LevelGenerator.SHAPES[(index * 5 + chapter) % LevelGenerator.SHAPES.size()]
	if tag == "relief" and shape in ["ring", "twin", "arch", "wave"]:
		shape = ["oval", "heart", "diamond", "rect"][index % 4]
	var base := 9.0 + (index - 21) * 0.11
	return {"id": "c%03d" % index, "tag": tag, "w": size[0], "h": size[1], "shape": shape,
		"target": base + OFFSETS[tag], "density": DENSITY[tag], "symmetric": index % 3 != 0,
		"seed": Prng.derive(CAMPAIGN_SEED, "c%03d" % index)}

func _generate_campaign(index: int, previous: Array) -> Dictionary:
	var spec := _campaign_spec(index)
	var best := _best_basic(spec, previous, 0.58, 70)
	if best.is_empty():
		best = _best_basic(spec, previous, 0.75, 120)
	if best.is_empty():
		spec["shape"] = "rect"
		best = _best_basic(spec, previous, 1.1, 200)
	return best

func _best_basic(spec: Dictionary, previous: Array, max_similarity: float, tries: int) -> Dictionary:
	var mask := LevelGenerator.shape_mask(spec["shape"], spec["w"], spec["h"])
	var cells := 0
	for v in mask:
		cells += v
	var n := int(round(cells * float(spec["density"])))
	var best := {}
	var best_gap := 999.0
	for attempt in tries:
		var seed_value := Prng.derive(spec["seed"], "try%d" % attempt)
		var params := {"w": spec["w"], "h": spec["h"], "n": n, "shape": spec["shape"], "block_bias": 1.0,
			"path_bias": 0.8, "symmetry": "rot180" if spec["symmetric"] else ""}
		var raw := LevelGenerator.build_basic(seed_value, params)
		if raw["b"].size() < n - 3:
			continue
		var tuned := LevelGenerator.tune_basic(raw, seed_value ^ 0x5bd1e995, spec["target"], 220, 0.42, spec["symmetric"])
		var m := LevelValidator.metrics(BoardState.from_level(tuned))
		if m["dir_share"] > 0.42:
			continue
		if spec["tag"] == "relief" and (m["free_ratio"] < 0.4 or m["cascade"] < 2):
			continue
		if spec["tag"] == "hard" and m["long_blocks"] > maxi(3, int(m["n"] * 0.18)):
			continue # far blockers are hard to read, not hard to solve
		var similar := 0.0
		for i in range(maxi(0, previous.size() - 8), previous.size()):
			similar = maxf(similar, LevelGenerator.similarity(previous[i], tuned))
		if similar > max_similarity:
			continue
		var gap: float = absf(m["score"] - float(spec["target"]))
		if gap < best_gap:
			best_gap = gap
			tuned["seed"] = seed_value
			best = tuned
		if gap < 0.3:
			break
	if best.is_empty():
		return best
	return _decorate(best, {"id": spec["id"], "tag": spec["tag"], "shape": spec["shape"]}, best["seed"], "gen")

func _generate_daily(index: int) -> Dictionary:
	var seed_base := Prng.derive(DAILY_SEED, "d%03d" % index)
	var rng := Prng.new(seed_base)
	var sizes := [[6, 7], [6, 8], [7, 8]]
	var size: Array = sizes[rng.below(sizes.size())]
	var tag: String = ["medium", "medium", "hard", "relief"][rng.below(4)]
	var spec := {"id": "d%03d" % index, "tag": tag, "w": size[0], "h": size[1],
		"shape": LevelGenerator.SHAPES[rng.below(LevelGenerator.SHAPES.size())],
		"target": 11.5 + OFFSETS[tag] * 0.6, "density": DENSITY[tag], "symmetric": rng.chance(0.6), "seed": seed_base}
	var best := _best_basic(spec, [], 1.1, 30)
	if best.is_empty():
		spec["shape"] = "rect"
		best = _best_basic(spec, [], 1.1, 80)
	return best

# --- switch generation -------------------------------------------------------------------------

func _finalize_switch(entry: Dictionary, seed_value: int, source: String) -> Dictionary:
	var level := LevelData.parse_ascii(entry["ascii"])
	level["rules"] = LevelData.RULES_SWITCH
	return _decorate(level, entry, seed_value, source)

func _switch_spec(index: int) -> Dictionary:
	var t := float(index - 4) / 16.0 # 0..1 across generated switch levels
	var sizes := [[4, 4], [4, 5], [5, 5], [5, 5], [5, 6]]
	var size: Array = sizes[mini(int(t * sizes.size()), sizes.size() - 1)]
	return {"id": "s%03d" % index, "w": size[0], "h": size[1], "n": 7 + int(round(t * 5)),
		"switches": 1 + int(t * 2.4), "random_win": lerpf(0.55, 0.12, t), "tag": TAG_CYCLE[(index - 1) % 4],
		"seed": Prng.derive(SWITCH_SEED, "s%03d" % index)}

func _generate_switch(index: int, previous: Array) -> Dictionary:
	var spec := _switch_spec(index)
	var best := {}
	var best_gap := 999.0
	for attempt in 2500:
		var seed_value := Prng.derive(spec["seed"], "try%d" % attempt)
		var level := LevelGenerator.build_switch(seed_value, {"w": spec["w"], "h": spec["h"], "n": spec["n"],
			"switches": spec["switches"], "links_max": 2, "shape": "rect"})
		if _count_switches(level) < spec["switches"]:
			continue
		var board := BoardState.from_level(level)
		var a := SwitchSolver.analyze(board, 60000)
		if a["status"] != "solvable" or a["trap_first_moves"] < 1 or a["first_moves"] < 2:
			continue
		if not _needs_switch(level):
			continue # every challenge must depend on at least one rotation
		var similar := 0.0
		for p in previous:
			similar = maxf(similar, LevelGenerator.similarity(p, level))
		if similar > 0.6:
			continue
		var gap := absf(float(a["random_win"]) - float(spec["random_win"]))
		if gap < best_gap:
			best_gap = gap
			level["seed"] = seed_value
			best = level
		if gap < 0.03:
			break
	if best.is_empty():
		_errors.append("%s: no switch candidate" % spec["id"])
		return {}
	return _decorate(best, {"id": spec["id"], "tag": spec["tag"]}, best["seed"], "gen")

func _count_switches(level: Dictionary) -> int:
	var count := 0
	for e in level["b"]:
		if e.size() > 3 and int(e[3]) == BoardState.KIND_SWITCH:
			count += 1
	return count

## True when the board cannot be cleared if switches were ordinary blocks.
func _needs_switch(level: Dictionary) -> bool:
	var plain := level.duplicate(true)
	for e in plain["b"]:
		e.resize(3)
	return not LevelValidator.peel(BoardState.from_level(plain))["solvable"]

# --- verification ------------------------------------------------------------------------------

func _self_check(pack: String, levels: Array) -> void:
	var ids := {}
	for level in levels:
		if level.is_empty():
			_errors.append("%s: empty level" % pack)
			continue
		var id: String = level["id"]
		if ids.has(id):
			_errors.append("%s: duplicate %s" % [pack, id])
		ids[id] = true
		for e in LevelValidator.check_structure(level):
			_errors.append("%s %s: %s" % [pack, id, e])
		if not LevelValidator.replay(BoardState.from_level(level), PackedInt32Array(level["sol"])):
			_errors.append("%s %s: stored solution fails" % [pack, id])
		if level["hash"] != LevelData.content_hash(level):
			_errors.append("%s %s: hash mismatch" % [pack, id])

func _print_curve(campaign: Array, switches: Array) -> void:
	for level in campaign:
		var m: Dictionary = level["m"]
		print("%s %-6s %dx%d n=%2d score=%5.2f layers=%2d free=%.2f long=%d shape=%s" % [level["id"], level["tag"],
			level["w"], level["h"], m["n"], m["score"], m["layers"], m["free_ratio"], m["long_blocks"], level.get("shape", "-")])
	for level in switches:
		var m: Dictionary = level["m"]
		print("%s %-6s %dx%d n=%2d switches=%d win=%.3f traps=%d states=%d" % [level["id"], level["tag"], level["w"],
			level["h"], m["n"], m["switches"], m["random_win"], m["traps"], m["states"]])

# --- authoring helpers -------------------------------------------------------------------------

func _candidates(args: PackedStringArray) -> void:
	var w := int(args[1])
	var h := int(args[2])
	var n := int(args[3])
	var shape := args[4]
	var count := int(args[5])
	var low := float(args[6]) if args.size() > 6 else -99.0
	var high := float(args[7]) if args.size() > 7 else 99.0
	var shown := 0
	for s in range(1, 4000):
		var level := LevelGenerator.build_basic(s * 7919, {"w": w, "h": h, "n": n, "shape": shape, "block_bias": 1.0, "path_bias": 0.8, "symmetry": "rot180"})
		if level["b"].size() < n - 2:
			continue
		var m := LevelValidator.metrics(BoardState.from_level(level))
		if m["score"] < low or m["score"] > high:
			continue
		print("# seed %d %s" % [s * 7919, JSON.stringify(m)])
		print(LevelData.to_ascii(level), "\n")
		shown += 1
		if shown >= count:
			break

func _print_masks() -> void:
	for shape in LevelGenerator.SHAPES:
		for size in [Vector2i(5, 6), Vector2i(7, 9)]:
			var mask := LevelGenerator.shape_mask(shape, size.x, size.y)
			var lines := PackedStringArray()
			for y in size.y:
				var row := ""
				for x in size.x:
					row += "#" if mask[y * size.x + x] == 1 else "."
				lines.append(row)
			print("%s %dx%d\n%s\n" % [shape, size.x, size.y, "\n".join(lines)])
