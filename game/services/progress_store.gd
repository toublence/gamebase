extends Node
## Autoload "Progress". Outtap's save namespace inside the base SaveManager (atomic temp → backup →
## rename, with backup recovery). Clears, unlocks and rewards are written immediately; the
## in-progress board and play time are staged and flushed shortly after, on background, and on exit.
signal changed
## The look changed (scene choice or arrow skin). Name kept from the theme era for listeners.
signal theme_changed(theme_id: String)
signal league_changed

const KEY := "outtap"
## 2 = progress for rules "arrow-path-2". Schema 1 was the single-tile game; its progress is backed
## up under "legacy_v1" on first launch of this version and never mapped onto the new levels.
const SCHEMA := 2
const SWITCH_UNLOCK_LEVEL := 30
const STAGED_FLUSH_SECONDS := 1.5
const REWARD_HISTORY := 64

var data: Dictionary = {}
## Launch request for the next game screen (see Nav). Not persisted.
var request: Dictionary = {}
var levels_tab := "campaign"
var _flush_timer: Timer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_flush_timer = Timer.new()
	_flush_timer.one_shot = true
	_flush_timer.timeout.connect(flush_now)
	add_child(_flush_timer)
	AppManager.backgrounded.connect(flush_now)
	reload()

func reload() -> void:
	data = _normalize(_migrate(SaveManager.get_game_data(KEY)))
	_apply_content_epoch()
	data["stats"]["launches"] = int(data["stats"]["launches"]) + 1
	if int(data["stats"]["first_open_unix"]) == 0:
		data["stats"]["first_open_unix"] = int(Time.get_unix_time_from_system())
	roll_week(int(Time.get_unix_time_from_system()))
	_stage()

## A campaign redesign (pack "progress_epoch" raised) changes what the stage ids mean, so stage
## progress made on the old boards is backed up under "previous_campaign" and the campaign starts
## over once. Scenes, skins, the league, rewards, play time and ad counters carry over.
func _apply_content_epoch() -> void:
	var epoch := Levels.progress_epoch()
	if int(data["epoch"]) >= epoch:
		return
	var had_progress: bool = int(data["reached"]) > 1 or not (data["cleared"] as Dictionary).is_empty()
	if had_progress:
		data["previous_campaign"] = {"epoch": data["epoch"], "reached": data["reached"], "cleared": data["cleared"].duplicate(true)}
		data["reached"] = 1
		data["cleared"] = {}
		data["active"] = {}
		data["coach_seen"] = []
		data["flags"]["campaign_redesigned"] = true
		data["flags"]["redesign_notice_shown"] = false
		Diagnostics.log_event("save", "campaign_redesigned", {"from_epoch": data["previous_campaign"]["epoch"], "to_epoch": epoch})
	data["epoch"] = epoch

## Schema 1 (single-tile rules) → 2. Gameplay progress, the in-progress board and tutorial marks
## belonged to boards that no longer exist, so they are backed up untouched and the campaign starts
## over. Settings live in the base save and are not affected. Unlocked themes, the reward ledger,
## play time and ad pacing counters carry over.
func _migrate(source: Dictionary) -> Dictionary:
	if source.is_empty() or int(source.get("schema", 0)) != 1:
		return source
	var migrated := source.duplicate(true)
	migrated["legacy_v1"] = {"reached": source.get("reached", 1), "cleared": source.get("cleared", {}),
		"switch_cleared": source.get("switch_cleared", {}), "daily": source.get("daily", {}),
		"active": source.get("active", {}), "coach_seen": source.get("coach_seen", [])}
	migrated["schema"] = SCHEMA
	migrated["reached"] = 1
	for key in ["cleared", "switch_cleared", "daily", "active"]:
		migrated[key] = {}
	migrated["coach_seen"] = []
	var flags: Dictionary = migrated.get("flags", {}) if migrated.get("flags") is Dictionary else {}
	flags["migrated_from_v1"] = true
	flags["tutorial_started"] = false
	flags["tutorial_completed"] = false
	migrated["flags"] = flags
	Diagnostics.log_event("save", "progress_migrated", {"from": 1, "to": SCHEMA,
		"legacy_cleared": (source.get("cleared", {}) as Dictionary).size() if source.get("cleared") is Dictionary else 0})
	return migrated

func defaults() -> Dictionary:
	return {"schema": SCHEMA, "epoch": 0, "reached": 1, "cleared": {}, "switch_cleared": {}, "daily": {}, "active": {},
		"scene": Scenery.DEFAULT, "scenes": ["morning", "harbor"], "skin": "classic", "skins": ["classic"], "coach_seen": [],
		"league": _league_defaults(), "previous_campaign": {}, "story_seen": [],
		"streak": {"last": "", "count": 0, "best": 0, "days": []},
		"stats": {"play_ms": 0, "clears": 0, "perfects": 0, "first_open_unix": 0, "launches": 0},
		"ads": {"play_ms_at_last_fullscreen": 0, "fullscreen_count": 0, "new_clears_since_fullscreen": 0},
		"rewards": [], "flags": {"first_open_logged": false, "tutorial_started": false, "tutorial_completed": false,
			"migrated_from_v1": false, "migration_notice_shown": false, "campaign_redesigned": false,
			"redesign_notice_shown": false, "first_hard_started": false, "first_hard_completed": false,
			"zoom_coached": false, "dark_default": true}, "legacy_v1": {}}

static func _league_defaults() -> Dictionary:
	return {"week": "", "points": 0, "base": 0, "tier": 0, "best_tier": 0, "best_points": 0, "claims": {},
		"last": {}, "pending": {}}

## Rebuilds a valid structure from whatever was stored; wrong types fall back to defaults.
func _normalize(source: Dictionary) -> Dictionary:
	var result := defaults()
	if int(source.get("schema", 0)) > SCHEMA:
		Diagnostics.error("save", "future_progress_schema", {"schema": source.get("schema")})
		return result
	result["reached"] = clampi(int(source.get("reached", 1)) if _is_number(source.get("reached")) else 1, 1, 100000)
	result["epoch"] = maxi(0, int(source.get("epoch", 0))) if _is_number(source.get("epoch")) else 0
	for key in ["cleared", "switch_cleared", "daily", "active", "legacy_v1", "previous_campaign"]:
		if source.get(key) is Dictionary:
			result[key] = source[key].duplicate(true)
	if source.get("streak") is Dictionary:
		var st: Dictionary = source["streak"]
		result["streak"]["last"] = str(st.get("last", ""))
		for key in ["count", "best"]:
			if _is_number(st.get(key)):
				result["streak"][key] = maxi(0, int(st[key]))
		if st.get("days") is Array:
			result["streak"]["days"] = (st["days"] as Array).filter(func(d: Variant) -> bool: return d is String)
	for key in ["scenes", "skins", "coach_seen", "rewards", "story_seen"]:
		if source.get(key) is Array:
			var clean: Array = []
			for value in source[key]:
				if value is String:
					clean.append(value)
			result[key] = clean
	result["scenes"] = result["scenes"].filter(func(id: String) -> bool: return Scenery.SCENES.has(id))
	if not result["scenes"].has("morning"):
		result["scenes"].push_front("morning")
	if not result["scenes"].has(Scenery.DEFAULT):
		result["scenes"].append(Scenery.DEFAULT)
	result["skins"] = result["skins"].filter(func(id: String) -> bool: return Scenery.SKINS.has(id))
	if not result["skins"].has("classic"):
		result["skins"].push_front("classic")
	var scene: Variant = source.get("scene")
	if scene is String and (scene == Scenery.AUTO or result["scenes"].has(scene)):
		result["scene"] = scene
	# Saves from before the dark default kept "auto" without the player choosing it: move them to
	# the dark scene once. A choice made later in the style sheet is kept.
	var flags: Variant = source.get("flags")
	if not (flags is Dictionary and bool(flags.get("dark_default", false))):
		if result["scene"] == Scenery.AUTO:
			result["scene"] = Scenery.DEFAULT
		result["flags"]["dark_default"] = true
	var skin: Variant = source.get("skin")
	if skin is String and result["skins"].has(skin):
		result["skin"] = skin
	result["league"] = _normalize_league(source.get("league"))
	for section in ["stats", "ads", "flags"]:
		var stored: Variant = source.get(section)
		if stored is Dictionary:
			for key in result[section]:
				var value: Variant = stored.get(key)
				if result[section][key] is bool and value is bool:
					result[section][key] = value
				elif result[section][key] is int and _is_number(value):
					result[section][key] = maxi(0, int(value))
	return result

static func _normalize_league(stored: Variant) -> Dictionary:
	var league := _league_defaults()
	if not stored is Dictionary:
		return league
	if stored.get("week") is String:
		league["week"] = stored["week"]
	for key in ["points", "base", "best_points"]:
		if _is_number(stored.get(key)):
			league[key] = maxi(0, int(stored[key]))
	for key in ["tier", "best_tier"]:
		if _is_number(stored.get(key)):
			league[key] = clampi(int(stored[key]), 0, LeagueRules.TOP)
	league["best_tier"] = maxi(league["best_tier"], league["tier"])
	league["base"] = mini(league["base"], league["points"])
	for key in ["claims", "last", "pending"]:
		if stored.get(key) is Dictionary:
			league[key] = stored[key].duplicate(true)
	return league

static func _is_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

# --- persistence --------------------------------------------------------------------------------

func _stage() -> void:
	SaveManager.stage_game_data(KEY, data)
	_flush_timer.start(STAGED_FLUSH_SECONDS)

## Immediate atomic write. Returns false (and the base shows a toast) when storage fails.
func flush_now() -> bool:
	_flush_timer.stop()
	return SaveManager.set_game_data(KEY, data)

func _commit() -> bool:
	var ok := flush_now()
	changed.emit()
	return ok

# --- campaign -----------------------------------------------------------------------------------

func reached() -> int:
	return mini(int(data["reached"]), Levels.campaign_count())

func is_unlocked(index: int) -> bool:
	return index >= 1 and index <= reached()

func is_cleared(level_id: String) -> bool:
	return data["cleared"].has(level_id) or data["switch_cleared"].has(level_id)

func clear_info(level_id: String) -> Dictionary:
	var info: Variant = data["cleared"].get(level_id, data["switch_cleared"].get(level_id, {}))
	return info if info is Dictionary else {}

func campaign_cleared_count() -> int:
	return data["cleared"].size()

func chapter_cleared_count(chapter: int) -> int:
	var count := 0
	for i in range((chapter - 1) * Levels.CHAPTER_SIZE + 1, chapter * Levels.CHAPTER_SIZE + 1):
		if data["cleared"].has(Levels.campaign_id(i)):
			count += 1
	return count

## Switch mode is not offered until it is rebuilt and validated for the arrow rules.
func switch_unlocked() -> bool:
	return Levels.switch_count() > 0 and data["cleared"].has(Levels.campaign_id(SWITCH_UNLOCK_LEVEL))

func switch_reached() -> int:
	var next := 1
	while next <= Levels.switch_count() and data["switch_cleared"].has("s%03d" % next):
		next += 1
	return mini(next, Levels.switch_count())

## Records a finished board once. Returns {first_clear, new_scenes, switch_unlocked, counts_as_new,
## stars_best, score_best}.
func record_clear(level_id: String, mode: String, perfect: bool, mistakes: int, daily_date: String = "",
		stars: int = 0, score: int = 0) -> Dictionary:
	var result := {"first_clear": false, "new_scenes": [], "switch_unlocked": false, "counts_as_new": false,
		"stars_best": stars, "score_best": score}
	var had_switch := switch_unlocked()
	match mode:
		"daily":
			var day: Variant = data["daily"].get(daily_date, {})
			result["first_clear"] = not (day is Dictionary and bool(day.get("done", false)))
			var was_perfect: bool = day is Dictionary and bool(day.get("perfect", false))
			data["daily"][daily_date] = {"id": level_id, "done": true, "perfect": perfect or was_perfect,
				"mistakes": mini(mistakes, int(day.get("mistakes", 99)) if day is Dictionary else 99)}
		_:
			var table: String = "switch_cleared" if mode == "switch" else "cleared"
			var old: Variant = data[table].get(level_id)
			result["first_clear"] = not old is Dictionary
			var info: Dictionary = old if old is Dictionary else {"perfect": false, "best": 99, "n": 0}
			info["perfect"] = bool(info.get("perfect", false)) or perfect
			info["best"] = mini(int(info.get("best", 99)), mistakes)
			info["n"] = int(info.get("n", 0)) + 1
			info["stars"] = maxi(int(info.get("stars", 0)), stars)
			info["score"] = maxi(int(info.get("score", 0)), score)
			result["stars_best"] = info["stars"]
			result["score_best"] = info["score"]
			data[table][level_id] = info
			if mode == "campaign":
				var index := Levels.index_of(level_id)
				data["reached"] = clampi(maxi(int(data["reached"]), index + 1), 1, Levels.campaign_count())
				result["new_scenes"] = _unlock_scenes()
	data["stats"]["clears"] = int(data["stats"]["clears"]) + 1
	if perfect:
		data["stats"]["perfects"] = int(data["stats"]["perfects"]) + 1
	if result["first_clear"]:
		data["ads"]["new_clears_since_fullscreen"] = int(data["ads"]["new_clears_since_fullscreen"]) + 1
		result["counts_as_new"] = true
	result["switch_unlocked"] = switch_unlocked() and not had_switch
	_commit()
	return result

func _unlock_scenes() -> Array:
	var unlocked: Array = []
	for scene_id in Scenery.ORDER:
		var stage: int = Scenery.UNLOCK[scene_id]
		if not data["scenes"].has(scene_id) and (stage == 0 or data["cleared"].has(Levels.campaign_id(stage))):
			data["scenes"].append(scene_id)
			unlocked.append(scene_id)
	return unlocked

# --- active attempt -----------------------------------------------------------------------------

func active_attempt() -> Dictionary:
	var value: Variant = data.get("active", {})
	return value if value is Dictionary else {}

func stage_active(save: Dictionary) -> void:
	data["active"] = save
	_stage()

func save_active_now(save: Dictionary) -> void:
	data["active"] = save
	flush_now()

func clear_active() -> void:
	data["active"] = {}
	flush_now()

# --- daily --------------------------------------------------------------------------------------

func daily_done(date_key: String) -> bool:
	var day: Variant = data["daily"].get(date_key, {})
	return day is Dictionary and bool(day.get("done", false))

func daily_perfect(date_key: String) -> bool:
	var day: Variant = data["daily"].get(date_key, {})
	return day is Dictionary and bool(day.get("perfect", false))

# --- play time / ad counters -------------------------------------------------------------------

func add_play_ms(ms: int) -> void:
	if ms <= 0:
		return
	data["stats"]["play_ms"] = int(data["stats"]["play_ms"]) + ms
	_stage()

func total_play_ms() -> int:
	return int(data["stats"]["play_ms"])

func note_fullscreen_ad_shown() -> void:
	data["ads"]["play_ms_at_last_fullscreen"] = total_play_ms()
	data["ads"]["fullscreen_count"] = int(data["ads"]["fullscreen_count"]) + 1
	data["ads"]["new_clears_since_fullscreen"] = 0
	flush_now()

func ad_counters() -> Dictionary:
	return data["ads"].duplicate()

# --- rewards ------------------------------------------------------------------------------------

## Returns false when this reward transaction was already granted (duplicate callback).
func claim_reward(transaction_id: String) -> bool:
	if transaction_id.is_empty() or data["rewards"].has(transaction_id):
		return false
	data["rewards"].append(transaction_id)
	while data["rewards"].size() > REWARD_HISTORY:
		data["rewards"].pop_front()
	return true

# --- themes / tutorial -------------------------------------------------------------------------

## "auto" (each level shows its own scene) or a pinned, unlocked scene id.
func scene_choice() -> String:
	return str(data["scene"])

func has_scene(scene_id: String) -> bool:
	return data["scenes"].has(scene_id)

func set_scene_choice(scene_id: String) -> bool:
	if scene_id == scene_choice() or (scene_id != Scenery.AUTO and not has_scene(scene_id)):
		return false
	data["scene"] = scene_id
	_commit()
	theme_changed.emit(scene_id)
	return true

func skin() -> String:
	return str(data["skin"])

func has_skin(skin_id: String) -> bool:
	return data["skins"].has(skin_id)

func set_skin(skin_id: String) -> bool:
	if not has_skin(skin_id) or skin_id == skin():
		return false
	data["skin"] = skin_id
	_commit()
	theme_changed.emit(skin_id)
	return true

# --- daily streak (consecutive days with a clear) ------------------------------------------------

## Notes today's first clear. Returns {new_day, count, best, week: [7 bools, Monday first]}.
func note_play_day(now_unix: int) -> Dictionary:
	var st: Dictionary = data["streak"]
	var today := _day_key(now_unix)
	var yesterday := _day_key(now_unix - 86400)
	var new_day := str(st["last"]) != today
	if new_day:
		st["count"] = int(st["count"]) + 1 if str(st["last"]) == yesterday else 1
		st["best"] = maxi(int(st["best"]), int(st["count"]))
		st["last"] = today
		var days: Array = st["days"]
		days.append(today)
		while days.size() > 14:
			days.pop_front()
		_commit()
	var week: Array = []
	var monday := LeagueRules.week_start(now_unix)
	for i in 7:
		week.append((st["days"] as Array).has(_day_key(monday + i * 86400 + 43200)))
	return {"new_day": new_day, "count": st["count"], "best": st["best"], "week": week}

func streak_count(now_unix: int) -> int:
	var st: Dictionary = data["streak"]
	if str(st["last"]) == _day_key(now_unix) or str(st["last"]) == _day_key(now_unix - 86400):
		return int(st["count"])
	return 0

static func _day_key(unix: int) -> String:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var d := Time.get_datetime_dict_from_unix_time(unix + bias)
	return "%04d-%02d-%02d" % [d["year"], d["month"], d["day"]]

# --- story --------------------------------------------------------------------------------------

func story_seen(beat: String) -> bool:
	return data["story_seen"].has(beat)

func mark_story(beat: String) -> void:
	if not story_seen(beat):
		data["story_seen"].append(beat)
		_commit()

## Stages cleared so far count as restored town pieces.
func restored_count() -> int:
	return campaign_cleared_count()

# --- personal league ----------------------------------------------------------------------------

func league() -> Dictionary:
	return data["league"]

## Starts the current week; settles every finished week first (missed weeks count as 0 points).
## The finished week's result is kept in "pending" until the game has shown it.
func roll_week(now_unix: int) -> void:
	var lg: Dictionary = data["league"]
	var key := LeagueRules.week_key(now_unix)
	if str(lg["week"]) == key:
		return
	if not str(lg["week"]).is_empty():
		var before := int(lg["tier"])
		var tier := LeagueRules.settle(before, int(lg["points"]))
		var missed := maxi(0, LeagueRules.weeks_between(str(lg["week"]), key) - 1)
		for i in missed:
			tier = LeagueRules.settle(tier, 0)
		var result := "kept"
		if tier < before:
			result = "dropped"
		lg["last"] = {"week": lg["week"], "points": lg["points"], "tier": before, "tier_after": tier, "result": result,
			"missed": missed}
		if int(lg["points"]) > 0 or tier != before:
			lg["pending"] = lg["last"].duplicate()
		lg["tier"] = tier
		Diagnostics.log_event("league", "week_settled", lg["last"])
	lg["week"] = key
	lg["points"] = 0
	lg["base"] = 0
	lg["claims"] = {}
	_stage()
	league_changed.emit()

## Pays the league points for a finished campaign stage. Returns {parts, total, points, tier,
## promotions, new_skins, goal, progress}.
func award_league(level: Dictionary, perfect: bool, first_clear: bool) -> Dictionary:
	roll_week(int(Time.get_unix_time_from_system()))
	var lg: Dictionary = data["league"]
	var level_id := str(level.get("id", ""))
	var claim: Variant = lg["claims"].get(level_id, {})
	var paid := LeagueRules.clear_points(level, perfect, first_clear, claim if claim is Dictionary else {})
	lg["claims"][level_id] = paid["claim"]
	lg["points"] = int(lg["points"]) + int(paid["total"])
	lg["best_points"] = maxi(int(lg["best_points"]), int(lg["points"]))
	var step := LeagueRules.promote(int(lg["tier"]), int(lg["base"]), int(lg["points"]))
	lg["tier"] = step["tier"]
	lg["base"] = step["base"]
	var new_skins: Array = []
	if int(lg["tier"]) > int(lg["best_tier"]):
		lg["best_tier"] = lg["tier"]
		for skin_id in Scenery.SKIN_ORDER:
			if int(Scenery.SKINS[skin_id]["tier"]) <= int(lg["best_tier"]) and not data["skins"].has(skin_id):
				data["skins"].append(skin_id)
				new_skins.append(skin_id)
	_commit()
	league_changed.emit()
	return {"parts": paid["parts"], "total": paid["total"], "points": lg["points"], "tier": lg["tier"],
		"promotions": step["promotions"], "new_skins": new_skins, "goal": league_goal(), "progress": league_progress()}

## Points still needed this week for the next tier (0 at the top tier).
func league_goal() -> int:
	var lg: Dictionary = data["league"]
	var tier := int(lg["tier"])
	if tier >= LeagueRules.TOP:
		return 0
	return maxi(0, LeagueRules.PROMOTE[tier] - (int(lg["points"]) - int(lg["base"])))

## 0..1 toward the next tier this week (the top tier shows progress toward its keep line).
func league_progress() -> float:
	var lg: Dictionary = data["league"]
	var tier := int(lg["tier"])
	if tier >= LeagueRules.TOP:
		return clampf(float(lg["points"]) / maxf(1.0, LeagueRules.KEEP[tier]), 0.0, 1.0)
	return clampf(float(int(lg["points"]) - int(lg["base"])) / float(LeagueRules.PROMOTE[tier]), 0.0, 1.0)

## The settled result of the previous week, once (empty when nothing to show).
func take_league_result() -> Dictionary:
	var pending: Dictionary = data["league"]["pending"]
	if pending.is_empty():
		return {}
	data["league"]["pending"] = {}
	_stage()
	return pending

func coach_seen(key: String) -> bool:
	return data["coach_seen"].has(key)

func mark_coach(key: String) -> void:
	if not coach_seen(key):
		data["coach_seen"].append(key)
		_stage()

func flag(key: String) -> bool:
	return bool(data["flags"].get(key, false))

func set_flag(key: String) -> void:
	if not flag(key):
		data["flags"][key] = true
		_stage()

## Clears gameplay progress only. Settings, consent state and the reward ledger are kept so a reset
## can never re-grant an old reward.
func reset_progress() -> bool:
	var legacy: Dictionary = data.get("legacy_v1", {}).duplicate(true)
	var previous: Dictionary = data.get("previous_campaign", {}).duplicate(true)
	var rewards: Array = data["rewards"].duplicate()
	var epoch := int(data["epoch"])
	var stats: Dictionary = data["stats"].duplicate()
	var ads: Dictionary = data["ads"].duplicate()
	var flags: Dictionary = data["flags"].duplicate()
	data = defaults()
	data["rewards"] = rewards
	data["stats"]["first_open_unix"] = stats.get("first_open_unix", 0)
	data["stats"]["play_ms"] = stats.get("play_ms", 0)
	data["stats"]["launches"] = stats.get("launches", 0)
	data["ads"] = ads
	data["flags"]["first_open_logged"] = flags.get("first_open_logged", true)
	data["flags"]["migrated_from_v1"] = flags.get("migrated_from_v1", false)
	data["flags"]["migration_notice_shown"] = true
	data["legacy_v1"] = legacy
	data["previous_campaign"] = previous
	data["epoch"] = epoch
	data["flags"]["redesign_notice_shown"] = true
	roll_week(int(Time.get_unix_time_from_system()))
	var ok := _commit()
	theme_changed.emit(scene_choice())
	league_changed.emit()
	return ok
