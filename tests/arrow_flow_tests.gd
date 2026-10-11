extends Node
## Integration test on the real scenes and autoloads (headless). Launched by tools/verify.py:
##   godot --headless --path . res://tests/arrow_flow_tests.tscn -- --verify-base
## Uses the isolated verification save (user://verification/).
var checks := 0
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	if not OS.is_debug_build() or "--verify-base" not in OS.get_cmdline_user_args():
		get_tree().quit(2)
		return
	get_tree().current_scene = null
	_run.call_deferred()

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout

func _module() -> Node:
	return get_tree().get_first_node_in_group("outtap_game")

## Stars, score, the daily streak and story beats.
func _test_loop_and_story() -> void:
	var level := ArrowLevel.parse_authoring(5, 5, PackedStringArray(["2,4:UUUU", "0,2:R", "4,1:L"]))
	level["m"] = {"est_seconds": 10.0}
	var clean := ArrowSession.create(level, "campaign", "s1", 0)
	check(ResultWidgets.stars_for(clean) == 3, "no mistakes and no hints: three stars")
	clean.mistakes = 1
	check(ResultWidgets.stars_for(clean) == 2, "a mistake costs a star")
	clean.hints_used = 1
	check(ResultWidgets.stars_for(clean) == 1, "a mistake and a hint leave one star")
	var fast := ArrowSession.create(level, "campaign", "s2", 0)
	fast.active_ms = 1000
	var slow := ArrowSession.create(level, "campaign", "s3", 0)
	slow.active_ms = 120000
	check(ResultWidgets.score_for(fast, 3) > ResultWidgets.score_for(slow, 3), "a faster clear scores higher")
	var day0 := 1791000000
	var first := Progress.note_play_day(day0)
	var again := Progress.note_play_day(day0 + 600)
	var next := Progress.note_play_day(day0 + 86400)
	check(bool(first["new_day"]) and not bool(again["new_day"]) and int(next["count"]) == int(first["count"]) + 1, "streak counts consecutive days once a day")
	var gap := Progress.note_play_day(day0 + 86400 * 3)
	check(int(gap["count"]) == 1 and int(gap["best"]) >= 2, "a missed day restarts the streak and keeps the best")
	check(Story.beat_before(1, Levels.campaign(1)) == "", "no story card stands before the first board")
	check(Story.beat_before(5, Levels.campaign(5)) == "grade_1" and Story.beat_before(6, Levels.campaign(6)) == "", "milestones open a story beat")
	Progress.mark_story("grade_1")
	check(Story.beat_before(5, Levels.campaign(5)) == "", "a story beat shows once")
	check(Story.PIECES.size() == Levels.campaign_count(), "one town piece per stage")

## A touch on an arrow picks it; a touch exactly between two arrows is ambiguous (no action, no heart).
func _test_touch_pick() -> void:
	var view := ArrowBoardView.new()
	add_child(view)
	view.size = Vector2(400, 400)
	var board := ArrowBoard.from_level(ArrowLevel.parse_authoring(4, 4, PackedStringArray(["0,0:DDD", "1,0:DDD"])))
	view.setup(board, {"scene": "morning"}, false)
	check(view.pick(view.canvas_point(Vector2(0, 1))) == 0, "touch on an arrow picks it")
	var between := (view.canvas_point(Vector2(0, 1)) + view.canvas_point(Vector2(1, 1))) * 0.5
	check(view.pick(between) == ArrowBoardView.AMBIGUOUS, "touch exactly between two arrows is ambiguous")
	check(view.pick(view.canvas_point(Vector2(3, 3))) == -1, "touch on empty space picks nothing")
	check(view.max_zoom() >= 1.6, "zoom always allows at least 1.6x")
	# A blocked arrow right next to a free one: a touch between them that leans to the blocked one
	# is not charged as a blocked tap (the player probably meant the free arrow).
	var pair := ArrowBoard.from_level(ArrowLevel.parse_authoring(4, 4, PackedStringArray(["0,3:UU", "1,0:DD", "2,3:L"])))
	view.size = Vector2(110, 110) # phone-like cells (about 25 px)
	view.setup(pair, {"scene": "morning"}, false)
	check(not pair.can_escape(1) and pair.can_escape(0), "pair: arrow 1 blocked, arrow 0 free")
	var lean := view.canvas_point(Vector2(0.62, 1.2))
	check(view.pick(lean) == ArrowBoardView.AMBIGUOUS, "near-tie between a blocked and a free arrow is ambiguous")
	check(view.pick(view.canvas_point(Vector2(0, 2))) == 0, "a touch on the free arrow still picks it")
	# Camera: small cells get a play zoom; boards that already read well in the overview do not.
	var big := ArrowBoard.empty(30, 36)
	big.add_arrow([Vector2i(0, 0), Vector2i(1, 0)] as Array[Vector2i])
	view.size = Vector2(440, 640)
	view.setup(big, {"scene": "morning"}, false)
	check(view.cell < ArrowBoardView.READABLE_CELL and view.has_play_zoom() and is_equal_approx(view.play_zoom(), ArrowBoardView.PLAY_CELL / view.cell),
		"small overview cells: a play zoom of PLAY_CELL")
	view.setup(pair, {"scene": "morning"}, false)
	view.size = Vector2(440, 640)
	check(view.cell >= ArrowBoardView.READABLE_CELL and not view.has_play_zoom(), "readable overview: no glide")
	view.queue_free()

## Voice cheers are the English takes in every language; the setting off uses effects only.
func _test_voice_fallback() -> void:
	for lang in ["ko", "de", "en"]:
		SettingsManager.set_value("language", lang)
		var stream := Feel.voice_stream("wow")
		check(stream != null and stream.resource_path.contains("/voice/en/"), "English cheers in " + lang)
	SettingsManager.set_value("voice", false)
	check(not Feel.voice("great"), "voice setting off: no cheer")
	SettingsManager.set_value("voice", true)
	SettingsManager.set_value("language", "system")

func _run() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.storage_path + suffix))
	SaveManager.load_save()
	Progress.reload()
	SettingsManager.set_value("reduced_motion", false)
	# Levels load and validate.
	check(Levels.campaign_count() == 20 and Levels.replaced.is_empty(), "20 valid arrow levels loaded")
	check(Levels.campaign(1)["rules"] == ArrowBoard.RULES, "campaign uses arrow-path-2")
	# Legacy progress migrates without being reinterpreted.
	var legacy := {"schema": 1, "reached": 37, "cleared": {"c001": {"perfect": true}}, "active": {"v": 1, "level_id": "c037"},
		"themes": ["paper", "mint"], "theme": "mint", "rewards": ["tx-old"]}
	SaveManager.set_game_data(Progress.KEY, legacy)
	Progress.reload()
	check(Progress.reached() == 1 and Progress.data["cleared"].is_empty() and Progress.active_attempt().is_empty(), "legacy progress not mapped to new levels")
	check(Progress.data["legacy_v1"]["reached"] == 37, "legacy progress backed up")
	check(Progress.scene_choice() == Scenery.DEFAULT and Progress.has_scene("morning") and Progress.data["rewards"].has("tx-old"), "scene defaults set and reward ledger carried over")
	check(Progress.flag("migrated_from_v1"), "migration flagged")
	# A campaign redesign (new progress epoch) restarts stage progress once, with a backup.
	var old_v2 := {"schema": 2, "epoch": 0, "reached": 7, "cleared": {"a001": {"perfect": true, "best": 0, "n": 1}}, "rewards": ["tx-2"]}
	SaveManager.set_game_data(Progress.KEY, old_v2)
	Progress.reload()
	check(Progress.reached() == 1 and int(Progress.data["previous_campaign"]["reached"]) == 7 and Progress.flag("campaign_redesigned"), "redesign restarts stage progress with a backup")
	check(Progress.data["rewards"].has("tx-2") and int(Progress.data["epoch"]) == Levels.progress_epoch(), "redesign keeps rewards and records the epoch")
	Progress.reload()
	check(Progress.reached() == 1 and int(Progress.data["previous_campaign"]["reached"]) == 7, "redesign applies once")
	Progress.reset_progress()
	_test_loop_and_story()
	for beat in Story.BEATS:
		Progress.mark_story(beat)
	_test_touch_pick()
	_test_voice_fallback()
	# Play stage 1 through the real game screen.
	check(Nav.play_campaign(1), "navigate to stage 1")
	await SceneManager.transition_finished
	var game := _module()
	check(game != null and game.session != null and game.session.level_id() == "a001", "stage 1 mounted")
	check(AudioManager.current_music() != null and AudioManager.current_music().resource_path == Feel.MUSIC_TENSE, "tense music plays on a normal stage")
	# The HUD sits inside the host's safe-area rect (the module is a plain Node, so it must follow it).
	var hud: Control = game.get_child(0)
	var host: Control = game.get_parent()
	check(hud.global_position.is_equal_approx(host.global_position) and hud.size.is_equal_approx(host.size) and host.global_position.x > 0.0,
		"game HUD follows the safe-area rect")
	var order: Array = game.session.level["sol"]
	# Rapid duplicate taps on the same arrow: removed once.
	var first: int = order[0]
	game._on_tapped(first)
	game._on_tapped(first)
	game._on_tapped(first)
	check(game.session.history.size() == 1 and game.session.board.alive_count == game.session.board.size() - 1, "rapid duplicate taps remove once")
	for i in range(1, order.size()):
		game._on_tapped(order[i])
	check(game.session.status == ArrowSession.Status.CLEARED, "stage 1 cleared by solution taps")
	game._on_tapped(order[0])
	check(Progress.data["stats"]["clears"] == 1, "clear recorded exactly once")
	await _wait(1.6)
	check(game._overlay.is_open(), "clear sheet shown")
	check(Progress.is_cleared("a001") and Progress.reached() == 2, "progress saved and stage 2 unlocked")
	check(int(Progress.league()["points"]) == 2, "a mistake-free first clear of stage 1 pays two league points")
	game._on_next()
	game._on_next()
	await _wait(0.2)
	check(game.session.level_id() == "a002" and not game._overlay.is_open(), "next stage starts once (double tap safe)")
	# Blocked arrow on a hearts level: one heart per tap, the same arrow inside the grace is free.
	check(Nav.play_campaign(4), "open stage 4 from a game screen")
	await SceneManager.transition_finished
	game = _module()
	var board: ArrowBoard = game.session.board
	var blocked := -1
	for id in board.live_ids():
		if not board.can_escape(id):
			blocked = id
			break
	check(blocked != -1, "stage 4 has a blocked arrow")
	game._on_tapped(blocked)
	game._on_tapped(blocked)
	check(game.session.lives == 2 and game.session.mistakes == 1, "one heart for a double tap on a blocked arrow")
	check(game._board_view._canvas.wrong.has(blocked) and game._board_view._canvas.color_of(blocked) == ArrowStyle.BLOCKED,
		"the wrongly tapped arrow is drawn red")
	# Save / restore mid-board.
	var free := board.escapable_ids()
	game._on_tapped(free[0])
	Progress.flush_now()
	var snapshot: ArrowBoard = game.session.board.duplicate_board()
	AppManager.return_to_menu()
	await SceneManager.transition_finished
	SaveManager.load_save()
	Progress.reload()
	check(Nav.continue_game(), "continue from home")
	await SceneManager.transition_finished
	game = _module()
	check(game.session.level_id() == "a004" and game.session.board.equals(snapshot) and game.session.lives == 2, "attempt restored exactly")
	check(game._board_view._canvas.wrong.has(blocked), "the red wrong pick is still red after leaving and coming back")
	# Fail → free restart.
	board = game.session.board
	for k in 3:
		for id in board.live_ids():
			if not board.can_escape(id):
				game.session._last_blocked.clear()
				game._on_tapped(id)
				break
	check(game.session.status == ArrowSession.Status.FAILED, "three mistakes fail")
	await _wait(1.2)
	check(game._overlay.is_open(), "fail sheet shown")
	AdsManager.last_skip = {"format": "", "reason": "", "ms": 0}
	game._on_restart()
	check(str(AdsManager.last_skip["reason"]) != "", "restart from the fail sheet is an interstitial opportunity")
	check(game.session.status == ArrowSession.Status.PLAYING and game.session.lives == 3 and game.session.board.alive_count == game.session.board.size(), "free restart")
	check(AudioManager.current_music().resource_path == Feel.MUSIC_TENSE, "restart brings back the tense music")
	for k in 2:
		for id in board.live_ids():
			if not game.session.board.can_escape(id):
				game.session._last_blocked.clear()
				game._on_tapped(id)
				break
	check(game.session.lives == 1 and AudioManager.current_music().resource_path == Feel.MUSIC_HARD, "the last heart switches to the faster music")
	# Natural break never shows during the first five stages (no provider in headless anyway).
	AdsManager.interstitial_opportunity("level_complete", {"level_index": 3, "mode": "campaign"}, func(): pass)
	check(AdsManager.last_skip["reason"] in ["UNSUPPORTED_PLATFORM", "FIRST_LEVEL_GRACE"], "interstitial skipped early")
	check(AdsManager.policy.interstitial_block_reason({"placement": "level_complete", "level_index": 9, "mode": "campaign",
		"next_hard": true, "total_play_ms": 99999999, "new_clears_since_fullscreen": 9}) == "HARD_AHEAD", "no interstitial right before a HARD stage")
	# First HARD: overview first, then the play zoom; the first blocked tap is only a warning; the
	# checkpoint at half; a fail offers it for free, without an ad; home says Retry.
	check(Nav.play_campaign(5), "open stage 5 (first HARD)")
	await SceneManager.transition_finished
	game = _module()
	var view5: ArrowBoardView = game._board_view
	check(view5.zoom <= 1.001, "stage 5 opens on the whole board")
	var glides := view5.has_play_zoom() # depends on the test window's size (phones: 21 px cells, glides)
	await _wait(4.4)
	if glides:
		check(view5.zoom > 1.1 and game._fit_button.visible and game._fit_button.icon == Widgets.icon("fit"),
			"after the overview the camera glides to the play zoom; the button now shows the whole board")
		view5.toggle_camera()
		await _wait(0.5)
		check(view5.zoom <= 1.001 and game._fit_button.visible and game._fit_button.icon == Widgets.icon("zoom"), "camera button: back to the overview")
	else:
		check(view5.zoom <= 1.001 and not game._fit_button.visible, "readable board: stays on the overview")
	board = game.session.board
	var stuck := -1
	for id in board.live_ids():
		if not board.can_escape(id):
			stuck = id
			break
	game._on_tapped(stuck)
	check(game.session.lives == 3 and game.session.mistakes == 0 and game._coach_key == "BLOCK_WARNING", "first blocked tap on stage 5: warning, no heart lost")
	var half := ceili(board.size() * ArrowSession.CHECKPOINT_SHARE)
	while game.session.history.size() < half:
		game._on_tapped(game.session.board.escapable_ids()[0])
	check(game.session.has_checkpoint() and game._coach_key == "CHECKPOINT_SAVED", "checkpoint reached at half the arrows")
	var checkpoint_board: ArrowBoard = game.session.board.duplicate_board()
	game._on_tapped(game.session.board.escapable_ids()[0])
	AdsManager.last_skip = {"format": "", "reason": "", "ms": 0}
	for k in 3:
		for id in game.session.board.live_ids():
			if not game.session.board.can_escape(id):
				game.session._last_blocked.clear()
				game._on_tapped(id)
				break
	check(game.session.status == ArrowSession.Status.FAILED, "stage 5 failed")
	await _wait(1.2)
	check(game._overlay.is_open() and _has_button_prefix(game._overlay.body, tr("CHECKPOINT_RESTORE").split("(")[0].strip_edges()),
		"fail sheet offers the free checkpoint")
	check(str(AdsManager.last_skip["reason"]) == "", "no interstitial is considered after a fail")
	game._go_home()
	await SceneManager.transition_finished
	var menu := get_tree().current_scene
	check(_has_button_text(menu, tr("RETRY")) and not _has_button_text(menu, tr("CONTINUE")), "home shows Retry for a failed attempt")
	check(Nav.continue_game(), "retry from home")
	await SceneManager.transition_finished
	game = _module()
	await _wait(0.3)
	check(game.session.status == ArrowSession.Status.FAILED and game._overlay.is_open(), "retry reopens the fail choices")
	game._on_checkpoint()
	check(game.session.status == ArrowSession.Status.PLAYING and game.session.lives == 3 and game.session.board.equals(checkpoint_board)
		and not game._overlay.is_open(), "free checkpoint restores the exact half-way board with full hearts")
	check(not game.session.can_restore_checkpoint(), "checkpoint restore used once")
	game._on_restart()
	check(game.session.history.is_empty() and game.session.lives == 3 and not game.session.has_checkpoint(), "free restart from the start is always there")
	# Then a clean solve: golden arrow, milestone points, the big-board clear sheet.
	var backdrop: Node = get_tree().get_first_node_in_group("backdrop")
	check(bool(game.session.level.get("hard", false)), "stage 5 is the first HARD stage")
	check(not _has_text(game, ["HARD", "EXPERT", "MASTER", "LEGEND"]), "no grade name shown on stage 5")
	check(backdrop != null and backdrop.scene_id == "harbor", "stage 5 shows the night harbor scene")
	check(AudioManager.current_music() != null and AudioManager.current_music().resource_path == Feel.MUSIC_HARD, "HARD music plays on a HARD stage")
	check(game._gold_badge.visible and game.session.gold_total() == 1, "one golden arrow on stage 5")
	var points_before := int(Progress.league()["points"])
	for id in game.session.level["sol"]:
		game._on_tapped(int(id))
	check(game.session.status == ArrowSession.Status.CLEARED and game.session.gold_collected() == 1, "stage 5 cleared with its golden arrow")
	check(int(Progress.league()["points"]) - points_before == 5, "milestone clear pays golden + HARD + perfect + first clear")
	check(Progress.flag("first_hard_started") and Progress.flag("first_hard_completed"), "first HARD start and completion recorded")
	check(Progress.has_scene("harbor"), "night harbor unlocked by stage 5")
	for k in 40:
		if game._overlay.is_open():
			break
		await _wait(0.2)
	check(game._overlay.is_open() and _has_text(game._overlay.body, [tr("BIG_CLEAR")]), "big-board clear sheet shown")
	check(game._overlay.body.find_children("*", "LeagueBar", true, false).is_empty() and not _has_text(game._overlay.body, [tr("STREAK_TITLE")]),
		"the clear sheet carries no league, streak or town panels")
	AppManager.return_to_menu()
	await SceneManager.transition_finished
	print("ARROW_FLOW_TESTS: %d checks, %d failures" % [checks, failures.size()])
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.storage_path + suffix))
	AudioManager.play_music(null)
	await get_tree().create_timer(0.15, true).timeout
	get_tree().quit(0 if failures.is_empty() else 1)

func _has_button_text(node: Node, text: String) -> bool:
	for child in node.find_children("*", "Button", true, false):
		if (child as Button).is_visible_in_tree() and tr((child as Button).text) == text:
			return true
	return false

func _has_button_prefix(node: Node, prefix: String) -> bool:
	for child in node.find_children("*", "Button", true, false):
		if (child as Button).is_visible_in_tree() and tr((child as Button).text).begins_with(prefix):
			return true
	return false

## Whether any visible Label under node shows one of words.
func _has_text(node: Node, words: Array) -> bool:
	for child in node.find_children("*", "Label", true, false):
		var label := child as Label
		if label.is_visible_in_tree() and words.has(label.text.strip_edges()):
			return true
	return false
