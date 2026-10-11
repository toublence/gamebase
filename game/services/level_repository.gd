extends Node
## Autoload "Levels". Bundled "arrow-path-2" levels (schema 2) from game/data/v2/. Every level is
## re-checked on first load (structure, content hash, stored solution replayed with the real rule);
## a failing entry is replaced by the nearest earlier valid level so a damaged install never shows
## a broken board.
##
## Legacy single-tile packs (game/data/legacy/, rules basic-1/switch-1) are never loaded or
## reinterpreted. Daily challenge and switch mode stay hidden until boards built and validated for
## the new rules exist for them.
const CAMPAIGN := "res://game/data/v2/campaign.json"
const CHAPTER_SIZE := 20
const ID_PREFIX := "a"

var content_version := ""
var _progress_epoch := 0
var rules := ArrowBoard.RULES
var _campaign: Array = []
var _loaded := false
var _by_id := {}
var replaced: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CAMPAIGN))
	if not parsed is Dictionary or not parsed.get("levels") is Array or str(parsed.get("rules", "")) != ArrowBoard.RULES:
		Diagnostics.error("levels", "pack_unreadable", {"pack": CAMPAIGN})
		return
	content_version = str(parsed.get("content_version", ""))
	_progress_epoch = int(parsed.get("progress_epoch", 0))
	for raw in parsed["levels"]:
		if raw is Dictionary:
			_campaign.append(_normalize(raw))
	for i in _campaign.size():
		if not _valid(_campaign[i]):
			var id := str(_campaign[i].get("id", "?"))
			replaced.append(id)
			var fallback := _fallback(i)
			Diagnostics.error("levels", "level_replaced", {"id": id, "with": fallback.get("id", "")})
			fallback = fallback.duplicate(true)
			fallback["id"] = id
			_campaign[i] = fallback
	for level in _campaign:
		_by_id[str(level["id"])] = level

## JSON numbers arrive as floats; coordinates are integers.
func _normalize(raw: Dictionary) -> Dictionary:
	var level := raw.duplicate(true)
	level["w"] = int(level.get("w", 0))
	level["h"] = int(level.get("h", 0))
	var arrows: Array = []
	for flat in level.get("a", []):
		var cells: Array = []
		for v in flat:
			cells.append(int(v))
		arrows.append(cells)
	level["a"] = arrows
	var sol: Array = []
	for id in level.get("sol", []):
		sol.append(int(id))
	level["sol"] = sol
	var gold: Array = []
	for id in level.get("gold", []):
		gold.append(int(id))
	level["gold"] = gold
	return level

func _valid(level: Dictionary) -> bool:
	if not ArrowLevel.check_structure(level).is_empty():
		return false
	if str(level.get("hash", "")) != ArrowLevel.content_hash(level):
		return false
	return ArrowSolver.replay(ArrowBoard.from_level(level), PackedInt32Array(level.get("sol", [])))

func _fallback(index: int) -> Dictionary:
	for i in range(index - 1, -1, -1):
		if _valid(_campaign[i]):
			return _campaign[i]
	var tiny := ArrowLevel.parse_authoring(5, 6, PackedStringArray(["0,5:UUUU", "2,5:UURR", "1,0:RRR"]))
	tiny["sol"] = [0, 1, 2]
	tiny["tag"] = "easy"
	tiny["hash"] = ArrowLevel.content_hash(tiny)
	return tiny

## Raised by the level builder when stage ids get new boards (see Progress._apply_content_epoch).
func progress_epoch() -> int:
	_ensure()
	return _progress_epoch

func campaign_count() -> int:
	_ensure()
	return _campaign.size()

func campaign(index: int) -> Dictionary:
	_ensure()
	return _campaign[clampi(index, 1, _campaign.size()) - 1]

func campaign_id(index: int) -> String:
	return "%s%03d" % [ID_PREFIX, index]

func by_id(id: String) -> Dictionary:
	_ensure()
	return _by_id.get(id, {})

## 1-based campaign index from a level id, 0 when unknown (including legacy ids).
func index_of(id: String) -> int:
	if id.length() == 4 and id.begins_with(ID_PREFIX) and id.substr(1).is_valid_int():
		return int(id.substr(1))
	return 0

func chapter_of(index: int) -> int:
	return (maxi(1, index) - 1) / CHAPTER_SIZE + 1

func chapter_count() -> int:
	return ceili(float(campaign_count()) / CHAPTER_SIZE)

## Not available until daily boards validated for the new rules exist.
func daily_available() -> bool:
	return false

func switch_count() -> int:
	return 0

static func today_key() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [d["year"], d["month"], d["day"]]
