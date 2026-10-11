extends SceneTree
## Level builder for rules "arrow-path-2" (schema 2). Development only; tools/ is never exported.
##
##   godot --headless --path . -s res://tools/build_arrow_levels.gd -- build
##   godot --headless --path . -s res://tools/build_arrow_levels.gd -- pick SPEC_JSON OUT_PREFIX [ids...]
##
## build: merges the authored sources below (in id order), re-validates every board with the real
## rule, picks golden arrows, checks the chapter's rhythm (rhythm_problems: milestone peaks, a
## breather after each, rising in between), and writes game/data/v2/campaign.json.
##   tools/levels_src/chapter1_hand.txt  — stage 1, hand designed
##   tools/levels_src/a005_hard.txt      — stage 5, the first HARD board, kept on its own so it can
##                                          be played and edited directly
##   tools/levels_src/chapter1_gen.txt   — stages 2-4 and 6-20, picked from seeded candidates and frozen
##                                          (tools/select_chain.py)
## pick: for each spec in SPEC_JSON (tools/levels_src/chapter1_specs.json) generates seeded
## candidates with the shaped generator, tightens HARD boards, filters by the spec's bands, writes
## OUT_PREFIX.json (for tools/preview_arrows.py) and OUT_PREFIX.txt (authoring blocks to freeze).
const CONTENT_VERSION := "2026.10.10-rhythm"
## Raised when the campaign is redesigned so saved stage progress no longer matches the boards.
const PROGRESS_EPOCH := 5
## Difficulty grades shown on graded stages; the first stage of each grade is a milestone.
const GRADES := ["", "HARD", "EXPERT", "MASTER", "LEGEND"]
const SOURCES := ["res://tools/levels_src/chapter1_hand.txt", "res://tools/levels_src/a005_hard.txt",
	"res://tools/levels_src/chapter1_gen.txt"]
const OUT := "res://game/data/v2/campaign.json"
const PICK_SEED := 0x0A770003

var _errors: Array[String] = []

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	match args[0] if args.size() > 0 else "build":
		"pick": _pick(args[1], args[2], args.slice(3))
		"candidates": _candidates(args[1], args[2], args.slice(3))
		_: _build()
	quit(1 if not _errors.is_empty() else 0)

# --- build ---------------------------------------------------------------------------------------

func _build() -> void:
	var entries: Array = []
	for source in SOURCES:
		entries.append_array(_read(source))
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
	var levels: Array = []
	for entry in entries:
		var level := ArrowLevel.parse_authoring(entry["w"], entry["h"], entry["tokens"])
		level["id"] = entry["id"]
		level["tag"] = entry["tag"]
		level["seed"] = int(entry.get("seed", 0))
		level["gen"] = str(entry.get("gen", "hand-3"))
		if entry["soft"]:
			level["soft"] = true
		level["grade"] = int(entry.get("grade", 0))
		# "hard" marks a milestone: the first stage of a grade (intro plate, HARD music, league bonus).
		if entry["milestone"]:
			level["hard"] = true
		if entry["final"]:
			level["final"] = true
		# "grace=N": the first N blocked taps of an attempt are explained instead of costing a heart.
		if entry.has("grace"):
			level["grace"] = int(entry["grace"])
		for key in ["coach", "shape", "theme"]:
			if not str(entry.get(key, "")).is_empty():
				level[key] = entry[key]
		var problems := ArrowLevel.check_structure(level)
		for problem in problems:
			_errors.append("%s: %s" % [level["id"], problem])
		if not problems.is_empty():
			continue
		var board := ArrowBoard.from_level(level)
		var peel := ArrowSolver.peel(board)
		if not peel["solvable"]:
			_errors.append("%s: not solvable" % level["id"])
			continue
		level["sol"] = Array(peel["order"])
		var mask := PackedByteArray()
		if level.has("shape"):
			if not Silhouettes.SHAPES.has(str(level["shape"])):
				_errors.append("%s: unknown shape %s" % [level["id"], level["shape"]])
				continue
			mask = Silhouettes.mask(str(level["shape"]), level["w"], level["h"])
			var outside := 0
			for id in board.size():
				for c in board.cells_of(id):
					if mask[c.y * board.width + c.x] == 0:
						outside += 1
						mask[c.y * board.width + c.x] = 1
			if outside > 0:
				print("%s: %d arrow cells lie outside the %s outline; the outline was widened to cover them" % [level["id"], outside, level["shape"]])
			level["mask"] = _mask_string(mask)
		level["m"] = ArrowSolver.metrics(board, mask)
		level["gold"] = _golden(board, peel, entry, level)
		level["hash"] = ArrowLevel.content_hash(level)
		if not ArrowSolver.replay(ArrowBoard.from_level(level), PackedInt32Array(level["sol"])):
			_errors.append("%s: stored solution fails" % level["id"])
		levels.append(level)
	for i in range(1, levels.size()):
		levels[i]["m"]["similar_prev"] = snappedf(ArrowGenerator.similarity(levels[i - 1], levels[i]), 0.01)
		if int(levels[i]["grade"]) < int(levels[i - 1]["grade"]):
			_errors.append("%s has a lower grade than %s" % [levels[i]["id"], levels[i - 1]["id"]])
	_errors.append_array(rhythm_problems(levels))
	var shapes := {}
	for level in levels:
		var shape := str(level.get("shape", ""))
		if not shape.is_empty():
			if shapes.has(shape):
				_errors.append("%s repeats the %s outline of %s" % [level["id"], shape, shapes[shape]])
			shapes[shape] = level["id"]
	if not _errors.is_empty():
		for e in _errors:
			printerr(e)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://game/data/v2"))
	var file := FileAccess.open(OUT, FileAccess.WRITE)
	file.store_string(JSON.stringify({"pack": "campaign", "schema": ArrowLevel.SCHEMA, "rules": ArrowBoard.RULES,
		"content_version": CONTENT_VERSION, "progress_epoch": PROGRESS_EPOCH, "generator_version": ArrowGenerator.VERSION_SHAPED,
		"levels": levels}, "", false))
	file.close()
	for level in levels:
		var m: Dictionary = level["m"]
		print("%s g%d %-10s %2dx%-2d n=%3d len=%.1f±%.1f s/m/l=%d/%d/%d bends=%d free=%d vis=%d layers=%2d keys=%d fan=%d est=%5.1fs gold=%s" % [
			level["id"], level["grade"], str(level.get("shape", "-")), level["w"], level["h"], m["n"], m["avg_len"], m["len_std"],
			m["short"], m["medium"], m["long"], m["bends"], m["initial_free"], m["visible_free"], m["layers"], m["keys"],
			m["fanout"], m["est_seconds"], str(level["gold"])])
	print("BUILD_OK %d levels" % levels.size())

## The chapter's rhythm (ArrowSolver.challenge, "c" below): milestones (stages marked "hard": 5, 10,
## 15, 20) are the peaks, each above the one before; the stage right after a milestone is a breather
## at most 75 % of it; every other stage is at least 2 % above the one before it.
static func rhythm_problems(levels: Array) -> Array[String]:
	var problems: Array[String] = []
	var last_peak := -1.0
	for i in levels.size():
		var c := float(levels[i]["m"]["challenge"])
		var milestone := bool(levels[i].get("hard", false))
		if i > 0:
			var prev := float(levels[i - 1]["m"]["challenge"])
			var after_peak := bool(levels[i - 1].get("hard", false))
			if after_peak and not milestone and c > prev * 0.75:
				problems.append("%s should be a breather after %s (c %.0f -> %.0f, max %.0f)" % [levels[i]["id"], levels[i - 1]["id"], prev, c, prev * 0.75])
			elif not after_peak and c < prev * 1.02:
				problems.append("%s is not harder than %s (c %.0f -> %.0f)" % [levels[i]["id"], levels[i - 1]["id"], prev, c])
		if milestone:
			if c <= last_peak:
				problems.append("%s peaks lower than the previous milestone (c %.0f <= %.0f)" % [levels[i]["id"], c, last_peak])
			last_peak = c
	return problems

## Golden arrows to collect: from stage 4 on — one per board, two from stage 10, three on stage 20 —
## medium-or-long arrows that are not free at the start and leave in the second half of the solve,
## so finding them is part of the journey. Authoring may fix them with "gold=3,17".
func _golden(board: ArrowBoard, peel: Dictionary, entry: Dictionary, level: Dictionary) -> Array:
	if entry.has("gold"):
		return entry["gold"]
	var index := int(str(level["id"]).substr(1))
	if index < 4:
		return []
	var want := 3 if index >= 20 else (2 if index >= 10 else 1)
	var order: PackedInt32Array = peel["order"]
	var free := board.escapable_ids()
	var picks: Array = []
	var start := order.size() / 2
	for i in range(start, order.size()):
		var id := order[i]
		if free.has(id) or board.length(id) < 4:
			continue
		picks.append(id)
		if picks.size() >= want:
			break
	return picks

## "@ id tag [soft] [milestone] [final] [grade=N] [grace=N] [coach=KEY] [shape=NAME] [theme=NAME] [seed=N] [gen=V] [gold=a,b]",
## "size W H", then one arrow token per line ("x,y:MOVES").
func _read(path: String) -> Array:
	var result: Array = []
	if not FileAccess.file_exists(path):
		return result
	var current := {}
	for raw in FileAccess.get_file_as_string(path).split("\n"):
		var line := raw.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		if line.begins_with("@"):
			if not current.is_empty():
				result.append(current)
			var parts := line.substr(1).strip_edges().split(" ", false)
			current = {"id": parts[0], "tag": parts[1], "soft": parts.has("soft"), "final": parts.has("final"),
				"milestone": parts.has("milestone"), "tokens": PackedStringArray()}
			for part in parts:
				var kv := part.split("=")
				if kv.size() != 2:
					continue
				match kv[0]:
					"seed": current["seed"] = int(kv[1])
					"grade": current["grade"] = int(kv[1])
					"gold":
						var ids: Array = []
						for v in kv[1].split(","):
							ids.append(int(v))
						current["gold"] = ids
					_: current[kv[0]] = kv[1]
		elif line.begins_with("size"):
			var dims := line.split(" ", false)
			current["w"] = int(dims[1])
			current["h"] = int(dims[2])
		else:
			current["tokens"].append(line)
	if not current.is_empty():
		result.append(current)
	return result

# --- pick ----------------------------------------------------------------------------------------

## Spec fields: id, tag, grade, milestone, final, shape ("" = rectangle), w + h or cells + aspect
## (the smallest board whose outline has that many cells), lengths [[min,max,weight]...], modes {},
## turn, max_bends, fill, tries, free [min,max], layers [min,max], n [min,max], est [min,max],
## tighten (max free), min_visible, min_long, coach, theme, soft.
## The chapter's rhythm across stages is chosen later (tools/select_chain.py) and checked by build.
func _pick(spec_path: String, out_prefix: String, only: Array) -> void:
	var specs: Array = JSON.parse_string(FileAccess.get_file_as_string(spec_path))
	var blocks := PackedStringArray()
	var previews: Array = []
	var previous := {}
	for spec in specs:
		if not only.is_empty() and not only.has(spec["id"]):
			continue
		if spec.has("cells"):
			for w in range(5, 81):
				var h := maxi(5, int(round(w * float(spec.get("aspect", 1.25)))))
				if Silhouettes.cell_count(Silhouettes.mask(str(spec.get("shape", "")), w, h)) >= int(spec["cells"]):
					spec["w"] = w
					spec["h"] = h
					break
		var mask := Silhouettes.mask(str(spec.get("shape", "")), int(spec["w"]), int(spec["h"]))
		var found: Array = []
		for t in int(spec.get("tries", 160)):
			var seed_value := Prng.derive(PICK_SEED, "%s-%d" % [spec["id"], t])
			var params: Dictionary = spec.duplicate(true)
			params["mask"] = mask
			var level := ArrowGenerator.build_shaped(seed_value, params)
			if spec.has("tighten"):
				var longest := 0
				for band in spec.get("lengths", [[2, 12, 1.0]]):
					longest = maxi(longest, int(band[1]))
				level = ArrowGenerator.tighten(level, seed_value ^ 0x51ED, int(spec["tighten"]), int(spec.get("min_free", 2)),
					int(spec.get("max_len", longest + 4)), mask)
			level["id"] = "%s_%d" % [spec["id"], t]
			if not ArrowLevel.check_structure(level).is_empty():
				continue
			var board := ArrowBoard.from_level(level)
			if not ArrowSolver.replay(board, PackedInt32Array(level["sol"])):
				_errors.append("%s: generated solution does not replay" % level["id"])
				continue
			var m := ArrowSolver.metrics(board, mask)
			if not _in(m["initial_free"], spec.get("free", [0, 999])) or not _in(m["layers"], spec.get("layers", [0, 999])):
				continue
			if not _in(m["n"], spec.get("n", [0, 999])) or not _in(m["est_seconds"], spec.get("est", [0, 9999])):
				continue
			if m["visible_free"] < int(spec.get("min_visible", 1)) or m["long"] < int(spec.get("min_long", 0)):
				continue
			if not previous.is_empty() and ArrowGenerator.similarity(previous, level) > 0.45:
				continue
			level["m"] = m
			level["shape"] = spec.get("shape", "")
			if not str(spec.get("shape", "")).is_empty():
				level["mask"] = _mask_string(mask)
			# Rank: deeper solves, longer arrows, more key moves; near the spec's est midpoint.
			var est_band: Array = spec.get("est", [0, 9999])
			var mid: float = (float(est_band[0]) + float(est_band[1])) * 0.5 if float(est_band[1]) < 9000.0 else float(m["est_seconds"])
			level["rank"] = float(m["layers"]) * 0.6 + float(m["keys"]) * 0.5 + float(m["avg_len"]) * 0.8 + float(m["len_std"]) * 0.5 \
				- absf(float(m["est_seconds"]) - mid) * 0.05
			found.append(level)
		found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["rank"]) > float(b["rank"]))
		print("%s (%s %dx%d): %d candidates in band" % [spec["id"], spec.get("shape", ""), spec["w"], spec["h"], found.size()])
		var keep := found.slice(0, int(spec.get("keep", 3)))
		if keep.is_empty():
			blocks.append("# %s: NO CANDIDATE" % spec["id"])
			continue
		previous = keep[0]
		for k in keep.size():
			var level: Dictionary = keep[k]
			previews.append(level)
			var m: Dictionary = level["m"]
			blocks.append("# candidate %d of %s: n=%d len=%.1f±%.1f free=%d vis=%d layers=%d keys=%d est=%.0fs flips=%d dropped=%d" % [
				k, spec["id"], m["n"], m["avg_len"], m["len_std"], m["initial_free"], m["visible_free"], m["layers"], m["keys"],
				m["est_seconds"], level.get("flips", 0), level.get("dropped", 0)])
			var header := "@ %s %s seed=%d gen=%s grade=%d" % [spec["id"], spec["tag"], level["seed"], level["gen"], int(spec.get("grade", 0))]
			if not str(spec.get("shape", "")).is_empty():
				header += " shape=%s" % spec["shape"]
			for flag in ["soft", "milestone", "final"]:
				if spec.get(flag, false):
					header += " " + flag
			for key in ["coach", "theme"]:
				if spec.has(key):
					header += " %s=%s" % [key, spec[key]]
			blocks.append(header)
			blocks.append("size %d %d" % [level["w"], level["h"]])
			blocks.append("\n".join(ArrowLevel.to_authoring(level)))
			blocks.append("")
	var json := FileAccess.open(out_prefix + ".json", FileAccess.WRITE)
	json.store_string(JSON.stringify(previews))
	json.close()
	var txt := FileAccess.open(out_prefix + ".txt", FileAccess.WRITE)
	txt.store_string("\n".join(blocks))
	txt.close()

func _in(value: Variant, band: Array) -> bool:
	return float(value) >= float(band[0]) and float(value) <= float(band[1])

func _mask_string(mask: PackedByteArray) -> String:
	var s := ""
	for v in mask:
		s += "1" if v == 1 else "0"
	return s


# --- candidates (for chain selection) -------------------------------------------------------------

## Like pick, but keeps every candidate inside the spec's bands (no ranking, no comparison with the
## previous stage) and writes them as JSON: [{id, tag, seed, gen, w, h, tokens, m}]. Several of these
## runs can work on different stages in parallel; tools/select_chain.py then picks one candidate per
## stage so the whole chapter gets harder at every stage.
func _candidates(spec_path: String, out_path: String, only: Array) -> void:
	var specs: Array = JSON.parse_string(FileAccess.get_file_as_string(spec_path))
	var out: Array = []
	for spec in specs:
		if not only.is_empty() and not only.has(spec["id"]):
			continue
		if spec.has("cells"):
			for w in range(5, 81):
				var h := maxi(5, int(round(w * float(spec.get("aspect", 1.25)))))
				if Silhouettes.cell_count(Silhouettes.mask(str(spec.get("shape", "")), w, h)) >= int(spec["cells"]):
					spec["w"] = w
					spec["h"] = h
					break
		var mask := Silhouettes.mask(str(spec.get("shape", "")), int(spec["w"]), int(spec["h"]))
		var kept := 0
		var offset := int(spec.get("seed_offset", 0))
		for t in int(spec.get("tries", 160)):
			var seed_value := Prng.derive(PICK_SEED, "%s-%d" % [spec["id"], t + offset])
			var params: Dictionary = spec.duplicate(true)
			params["mask"] = mask
			var level := ArrowGenerator.build_shaped(seed_value, params)
			if spec.has("tighten"):
				var longest := 0
				for band in spec.get("lengths", [[2, 12, 1.0]]):
					longest = maxi(longest, int(band[1]))
				level = ArrowGenerator.tighten(level, seed_value ^ 0x51ED, int(spec["tighten"]), int(spec.get("min_free", 2)),
					int(spec.get("max_len", longest + 4)), mask)
			level["id"] = spec["id"]
			if not ArrowLevel.check_structure(level).is_empty():
				continue
			var board := ArrowBoard.from_level(level)
			if not ArrowSolver.replay(board, PackedInt32Array(level["sol"])):
				continue
			var m := ArrowSolver.metrics(board, mask)
			if not _in(m["initial_free"], spec.get("free", [0, 999])) or not _in(m["n"], spec.get("n", [0, 999])):
				continue
			if m["visible_free"] < int(spec.get("min_visible", 1)):
				continue
			out.append({"id": spec["id"], "tag": spec["tag"], "seed": level["seed"], "gen": level["gen"], "w": level["w"],
				"h": level["h"], "tokens": Array(ArrowLevel.to_authoring(level)), "m": m})
			kept += 1
		print("%s (%s %dx%d): %d candidates" % [spec["id"], spec.get("shape", ""), spec["w"], spec["h"], kept])
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(out))
	file.close()
