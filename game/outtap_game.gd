extends GameModule
## Outtap game screen (rules "arrow-path-2"). Owns one ArrowSession and plays its results on the
## ArrowBoardView. Flow: start → taps → clear / fail sheet → next stage (natural ad break) or free
## restart. The board takes every pixel the thin HUD leaves.
##
## Each stage shows its own scene behind the board (Soft Morning, Sunset Flow, Night Harbor) unless
## the player pinned one. Milestone stages open with a short "big board" plate and the faster music.
## Every board opens on the whole picture, then glides to a readable play zoom when its cells are
## small (the camera button switches between the two). Golden arrows on the board are collected as
## they leave and pay personal-league points on the clear (see LeagueRules).
##
## Failing shows the fail sheet straight away (no ad): the free checkpoint (once per attempt, see
## ArrowSession), a restart and the rewarded continue. Only "restart" from that sheet is an
## interstitial opportunity (policy placement "level_failed").
const STREAK_MARKS := [5, 10, 15, 20, 30]
const CLOCK_FLUSH_MS := 5000.0
## A single move that frees this many arrows at once is a "wow" moment.
const WOW_OPENED := 3
const HARD_INTRO_SECONDS := 2.0

var session: ArrowSession
var mode := "campaign"
var index := 1

var _board_view: ArrowBoardView
var _hearts: HeartsView
var _practice: PanelContainer
var _title: Label
var _subtitle: Label
var _gold_badge: GoldBadge
var _coach: PanelContainer
var _coach_label: Label
var _coach_key := ""
var _coach_timer: SceneTreeTimer
var _fit_button: BaseButtonView
var _hint_button: ToolButton
var _overlay: GameOverlay
var _continue_button: BaseButtonView
var _continue_note: Label
var _hard_banner: HardBanner
var _pinch: PinchHint

var _clock_ms := 0.0
var _paused := false
var _ended := false
var _stage_hard := false
var _transitioning := false
var _ad_busy := false
var _retries := {}
var _scene_id := "morning"
var _zoom_used := false
var _touch_misses := 0
var _ambiguous_coached := false
var _intro_serial := 0
## Seconds since the last escape while playing; a gentle hint offer appears when it gets long.
var _idle := 0.0
var _idle_offers := 0
const IDLE_OFFER_SECONDS := 14.0
## The play clock (results, analytics) stops when the board has not been touched for this long, so
## a device left on the board (or a locked desktop window) does not count as play.
const CLOCK_AWAY_MS := 90000
var _last_touch_ms := 0

func _ready() -> void:
	add_to_group("outtap_game")
	_build()
	AppManager.game_back_handler = _handle_back
	AdsManager.rewarded_changed.connect(_refresh_buttons)
	AdsManager.rewarded_changed.connect(_refresh_continue)
	Progress.theme_changed.connect(_on_look_changed)

func _exit_tree() -> void:
	if AppManager.game_back_handler == Callable(self, "_handle_back"):
		AppManager.game_back_handler = Callable()

# --- GameModule lifecycle ----------------------------------------------------------------------

func start_session() -> void:
	super.start_session()
	var request: Dictionary = Progress.request.duplicate()
	Progress.request = {}
	_start_from_request(request)

func pause_session() -> void:
	super.pause_session()
	_paused = true
	_board_view.cancel_input()
	_flush_clock()
	_save_attempt(true)

func resume_session() -> void:
	super.resume_session()
	_paused = false

func stop_session() -> void:
	super.stop_session()
	_flush_clock()
	_save_attempt(true)

# --- UI ----------------------------------------------------------------------------------------

func _build() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	# This module is a plain Node, so its Controls would span the whole viewport: follow the host's
	# safe-area rect instead (status bar, rounded corners and the gesture bar stay clear).
	var host := get_parent() as Control
	if host != null:
		root.set_anchors_preset(Control.PRESET_TOP_LEFT)
		var follow := func():
			root.position = host.global_position
			root.size = host.size
		host.item_rect_changed.connect(follow)
		follow.call()
	var layout := Design.column(6)
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(layout)
	# Top: pause · stage (+HARD) · hearts
	var top := Design.row(8)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(top)
	var left := HBoxContainer.new()
	left.custom_minimum_size = Vector2(118, Design.TOUCH)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(Widgets.icon_button("pause", "PAUSE", AppManager.pause_game))
	top.add_child(left)
	var titles := Design.column(0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.alignment = BoxContainer.ALIGNMENT_CENTER
	titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(titles)
	var title_row := Design.row(6)
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titles.add_child(title_row)
	_title = Design.title("", 26)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title_row.add_child(_title)
	var sub_row := Design.row(10)
	sub_row.alignment = BoxContainer.ALIGNMENT_CENTER
	sub_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titles.add_child(sub_row)
	_subtitle = Design.label("", 14, true, 650)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_OFF
	sub_row.add_child(_subtitle)
	_gold_badge = GoldBadge.new()
	var right := HBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_END
	right.custom_minimum_size = Vector2(118, Design.TOUCH)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(right)
	_hint_button = Widgets.tool_button("hint", "HINT", _on_hint)
	_hint_button.compact()
	right.add_child(_hint_button)
	# Second row: hearts (or the practice tag) on the left, golden arrows on the right.
	var status := Design.row(8)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(status)
	_hearts = HeartsView.new()
	status.add_child(_hearts)
	_practice = Widgets.pill("PRACTICE", Palette.c("accent_soft"), Palette.c("accent_deep"), 15)
	_practice.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	status.add_child(_practice)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.add_child(spacer)
	# Board: everything between the bars. Coach, pinch hint and fit button float above it.
	var stage := Control.new()
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(stage)
	_board_view = ArrowBoardView.new()
	_board_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_board_view.tapped.connect(_on_tapped)
	_board_view.touch_down.connect(func(_id: int): Feel.tap())
	_board_view.touched.connect(func(): _last_touch_ms = Time.get_ticks_msec())
	_board_view.touch_missed.connect(_on_touch_missed)
	_board_view.zoom_changed.connect(_on_camera_changed)
	_board_view.zoom_used.connect(_on_zoom_used)
	_board_view.gold_collected.connect(_on_gold_collected)
	stage.add_child(_board_view)
	_pinch = PinchHint.new()
	_pinch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(_pinch)
	_coach = PanelContainer.new()
	_coach.add_theme_stylebox_override("panel", Design.box(Color(Palette.c("face"), 0.96), 18, 3, Palette.c("side"), 12.0, 8.0))
	_coach.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_coach.offset_left = 10
	_coach.offset_right = -10
	_coach.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(_coach)
	_coach_label = Design.label("", 17, false, 700)
	_coach_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_coach.add_child(_coach_label)
	_coach.modulate.a = 0.0
	_fit_button = Widgets.icon_button("zoom", "ZOOM_IN", func(): _board_view.toggle_camera())
	stage.add_child(_fit_button)
	stage.resized.connect(func(): _fit_button.position = stage.size - Vector2(Design.TOUCH + 6, Design.TOUCH + 6))
	_fit_button.visible = false
	status.add_child(_gold_badge)
	_overlay = GameOverlay.new()
	add_child(_overlay)
	_hard_banner = HardBanner.new()
	add_child(_hard_banner)

## The camera button shows what it will do next: zoom in from the overview, or show the whole board.
func _on_camera_changed(zoomed: bool) -> void:
	if _fit_button == null:
		return
	_fit_button.visible = zoomed or _board_view.has_play_zoom()
	_fit_button.icon = Widgets.icon("fit" if zoomed else "zoom")
	var key := "FIT_BOARD" if zoomed else "ZOOM_IN"
	_fit_button.tooltip_text = key
	_fit_button.accessibility_name = key

func _set_coach(key: String, seconds: float = 0.0) -> void:
	_coach_key = key
	var reduced := bool(SettingsManager.get_value("reduced_motion"))
	var tween := create_tween()
	if key.is_empty():
		tween.tween_property(_coach, "modulate:a", 0.0, 0.0 if reduced else 0.2)
		return
	_coach_label.text = key
	tween.tween_property(_coach, "modulate:a", 1.0, 0.0 if reduced else 0.22)
	if seconds > 0.0:
		var shown := key
		get_tree().create_timer(seconds, false).timeout.connect(func():
			if is_inside_tree() and _coach_key == shown:
				_set_coach(""))

## Text on the backdrop follows the scene (dark ink on morning/sunset, light ink at night).
func _apply_scene(scene_id: String) -> void:
	_scene_id = scene_id
	get_tree().call_group("backdrop", "set_scene", scene_id, true)
	var s := Scenery.scene(scene_id)
	_title.add_theme_color_override("font_color", s["hud_ink"])
	_subtitle.add_theme_color_override("font_color", s["hud_soft"])
	_gold_badge.set_ink(Color("FFD36B") if bool(s["dark"]) else Color("8A5E0E"))

func _on_look_changed(_id: String) -> void:
	if session != null:
		_apply_scene(Scenery.for_level(session.level))
		_board_view.scene_id = _scene_id
		_board_view._restyle_all()

static func _pill_style(color: Color) -> StyleBoxFlat:
	var style := Design.box(color, 14, 0, Color.TRANSPARENT, 6.0)
	style.content_margin_left = 12
	style.content_margin_right = 12
	return style

static func mask_of(level: Dictionary) -> PackedByteArray:
	var text := str(level.get("mask", ""))
	var result := PackedByteArray()
	if text.length() != int(level.get("w", 0)) * int(level.get("h", 0)):
		return result
	result.resize(text.length())
	for i in text.length():
		result[i] = 1 if text[i] == "1" else 0
	return result

# --- level flow --------------------------------------------------------------------------------

func _start_from_request(request: Dictionary) -> void:
	var resume_data := {}
	var level := {}
	if bool(request.get("resume", false)):
		resume_data = Progress.active_attempt()
		level = Levels.by_id(str(resume_data.get("level_id", "")))
	if level.is_empty():
		resume_data = {}
		index = clampi(int(request.get("index", Progress.reached())), 1, Levels.campaign_count())
		level = Levels.campaign(index)
	else:
		index = Levels.index_of(str(level.get("id", "")))
	mode = "campaign"
	_begin_level(level, resume_data)

func _begin_level(level: Dictionary, resume_data: Dictionary) -> void:
	_ended = false
	_transitioning = false
	_overlay.close()
	_hard_banner.hide_now()
	_pinch.stop()
	_clock_ms = 0.0
	_last_touch_ms = Time.get_ticks_msec()
	_zoom_used = false
	_idle = 0.0
	_idle_offers = 0
	_touch_misses = 0
	_ambiguous_coached = false
	_intro_serial += 1
	var level_id := str(level.get("id", ""))
	var hard := bool(level.get("hard", false))
	var restored: ArrowSession = null
	if not resume_data.is_empty():
		restored = ArrowSession.from_save(level, resume_data)
		if restored == null:
			Diagnostics.log_event("game", "attempt_discarded", {"level_id": level_id, "reason": "rules_or_content_changed"})
			UI.toast("ATTEMPT_RESET")
	var fresh := true
	if restored != null and restored.status != ArrowSession.Status.CLEARED:
		session = restored
		fresh = session.history.is_empty()
	else:
		session = ArrowSession.create(level, mode, _new_attempt_id(), int(_retries.get(level_id, 0)))
		_track_level("level_started", {})
		if index == 1 and not Progress.flag("tutorial_started"):
			Progress.set_flag("tutorial_started")
			AnalyticsService.track(&"tutorial_started", {"level_id": level_id})
		if hard and not Progress.flag("first_hard_started"):
			Progress.set_flag("first_hard_started")
			AnalyticsService.track(&"first_hard_started", _level_params({}))
	_apply_scene(Scenery.for_level(level))
	_board_view.input_enabled = true
	_board_view.setup(session.board, {"scene": _scene_id, "mask": mask_of(level), "gold": level.get("gold", []),
		"wrong": session.wrong.keys()}, true)
	_on_camera_changed.call_deferred(false)
	_title.text = tr("STAGE_N") % index
	_subtitle.text = tr("CHAPTER_N") % Levels.chapter_of(index)
	var grade := Grades.of(level)
	_gold_badge.set_count(session.gold_collected(), session.gold_total())
	_hearts.set_lives(session.lives, false)
	_hearts.visible = not session.soft_mistakes
	_practice.visible = session.soft_mistakes
	_stage_hard = hard
	_update_music()
	_refresh_buttons()
	var coach := str(level.get("coach", ""))
	var show_coach := not coach.is_empty() and (session.soft_mistakes or not Progress.coach_seen(coach))
	if coach == "COACH_TAP" and session.history.is_empty():
		var free := session.board.escapable_ids()
		if not free.is_empty():
			_board_view.show_hint(free[0]) # tutorial pointer; not a charged hint
	if session.hint_target != -1:
		_board_view.show_hint(session.hint_target)
	_save_attempt(true)
	if session.status == ArrowSession.Status.FAILED:
		_show_fail_card()
		return
	_intro_sequence(level, hard, fresh, grade, coach, show_coach)

## Before play: the chapter's story card when this stage starts a new part of the story, then the
## plate on milestones, then the stage's coach line. Meanwhile the whole board stays in view and the
## camera glides to the play zoom afterwards (longest on the very first big board).
func _intro_sequence(level: Dictionary, hard: bool, fresh: bool, grade: int, coach: String, show_coach: bool) -> void:
	var serial := _intro_serial
	var beat := Story.beat_before(index, level) if fresh and mode == "campaign" else ""
	if not beat.is_empty():
		_set_coach("")
		_board_view.input_enabled = false
		var card := StoryCard.show_beat(beat)
		await card.finished
		if not is_inside_tree() or serial != _intro_serial or _ended:
			return
		_board_view.input_enabled = true
		AnalyticsService.track(&"story_beat_seen", {"beat": beat, "level_id": session.level_id()})
	if hard and fresh and session.status == ArrowSession.Status.PLAYING:
		_set_coach("")
		_hard_banner.play("HARD_INTRO_BODY", maxi(1, grade))
		Feel.hard_intro()
		await get_tree().create_timer(HARD_INTRO_SECONDS, false).timeout
		if is_inside_tree() and serial == _intro_serial and not _ended:
			_board_view.overview_then_play(1.2 if not Progress.flag("first_hard_completed") else 0.6)
			_after_hard_intro(coach, show_coach)
	else:
		_board_view.overview_then_play(0.9 if fresh else 0.4)
		_set_coach(coach if show_coach else "")
		if coach == "COACH_ZOOM" and show_coach and not Progress.flag("zoom_coached"):
			_pinch.play()

func _after_hard_intro(coach: String, show_coach: bool) -> void:
	if show_coach:
		_set_coach(coach)
	if coach == "COACH_ZOOM" and not Progress.flag("zoom_coached") and not _zoom_used:
		_pinch.play()

func _new_attempt_id() -> String:
	return "%x-%s" % [int(Time.get_unix_time_from_system()), Crypto.new().generate_random_bytes(6).hex_encode()]

# --- input -------------------------------------------------------------------------------------

func _on_tapped(id: int) -> void:
	if session == null or _ended or _transitioning or _paused or _ad_busy or AdsManager.is_presenting():
		return
	var head := session.board.head(id)
	var event := session.tap(id, Time.get_ticks_msec())
	match event["type"]:
		"escape":
			_idle = 0.0
			var exit_seconds := _board_view.play_escape(event)
			var opened := int(event.get("opened", 0))
			Feel.escape(int(event["streak"]), int(event["length"]), opened)
			AnalyticsService.track(&"arrow_escaped", {"level_id": session.level_id(), "length": int(event["length"]),
				"opened": opened, "streak": int(event["streak"]), "golden": bool(event.get("golden", false)),
				"remaining": int(event["remaining"])})
			if opened >= WOW_OPENED and not event["cleared"] and Feel.wow():
				_board_view.streak_mark(head, 2)
				_board_view.fx.float_label(_board_view.cell_center(Vector2(head)), tr("WOW_TEXT"), Scenery.GOLD, 26)
			elif int(event["streak"]) in STREAK_MARKS:
				_board_view.streak_mark(head, 1 if int(event["streak"]) < 10 else 2)
				Feel.streak(int(event["streak"]))
			if _coach_key in ["COACH_TAP", "COACH_OPEN", "COACH_LOOK", "COACH_BLOCKED", "COACH_CHAIN", "COACH_HEARTS", "TOUCH_AMBIGUOUS", "STUCK_HINT",
					"BLOCK_WARNING", "CHECKPOINT_BACK"]:
				_set_coach("")
			if event["cleared"]:
				_on_cleared(exit_seconds)
				return
			if bool(event.get("checkpoint", false)):
				_set_coach("CHECKPOINT_SAVED", 3.0)
				Feel.unlock()
				_track_level("checkpoint_reached", {"remaining": int(event["remaining"])})
		"blocked":
			var warned := bool(event.get("warned", false))
			_board_view.play_blocked(event, warned)
			Feel.bump(event["life_lost"])
			_hearts.set_lives(session.lives)
			_update_music()
			if warned:
				_set_coach("BLOCK_WARNING", 4.5)
				_track_level("block_warning", {})
			elif session.soft_mistakes:
				_set_coach("COACH_BLOCKED")
			if event["failed"]:
				_on_failed()
				return
		_:
			return
	_refresh_buttons()
	_save_attempt(false)

## A touch between two arrows: nothing moves and no heart is lost; the first time, say why.
## Stage music: the tense loop, or the faster HARD loop on milestone stages and on the last heart
## (the music speeds up when one more mistake would end the board).
func _update_music() -> void:
	var crisis := session != null and not session.soft_mistakes and session.lives == 1
	Feel.music_for(_stage_hard or crisis)

func _on_touch_missed(kind: String) -> void:
	_touch_misses += 1
	if kind == "ambiguous" and not _ambiguous_coached and not _ended:
		_ambiguous_coached = true
		_set_coach("TOUCH_AMBIGUOUS", 3.0)

func _on_zoom_used(method: String) -> void:
	if _zoom_used or session == null:
		return
	_zoom_used = true
	_pinch.stop()
	Progress.set_flag("zoom_coached")
	if _coach_key == "COACH_ZOOM":
		_set_coach("")
	AnalyticsService.track(&"zoom_used", _level_params({"method": method}))

func _on_gold_collected(_id: int, _at: Vector2) -> void:
	if session == null:
		return
	Feel.gold()
	_gold_badge.set_count(session.gold_collected(), session.gold_total(), true)

# --- tools -------------------------------------------------------------------------------------

func _refresh_buttons() -> void:
	if session == null:
		return
	var playing := session.status == ArrowSession.Status.PLAYING and not _ended
	_hint_button.disabled = not playing
	if session.hints_left() > 0:
		_hint_button.set_badge(session.hints_left())
	elif AdsManager.rewarded_offer_state() != "unavailable":
		_hint_button.set_badge(-1, true, "+1")
	else:
		_hint_button.set_badge(-1)

func _on_hint() -> void:
	if session == null or _ended or _transitioning or _ad_busy:
		return
	var result := session.request_hint()
	match result["kind"]:
		"arrow":
			_board_view.show_hint(result["id"])
			Feel.hint()
			if result.get("charged", false):
				AnalyticsService.track(&"hint_used", _level_params({"source": "reward" if session.hints_used > ArrowSession.FREE_HINTS else "free"}))
			_refresh_buttons()
			_save_attempt(false)
		_:
			if str(result.get("reason", "")) == "no_hints":
				_offer_reward("hint")

func restart_from_pause() -> void:
	_on_restart()

func _on_restart() -> void:
	if session == null or _transitioning or _ad_busy:
		return
	if session.status == ArrowSession.Status.FAILED and _overlay.is_open():
		# Restarting a lost board is a natural break: a full-screen ad (if ready and allowed by the
		# policy's grace and frequency limits) plays before the fresh board. The fail sheet itself and
		# the free checkpoint never show one. The continuation runs exactly once, ad or not.
		_transitioning = true
		AdsManager.interstitial_opportunity("level_failed", {"level_index": index, "mode": mode}, func():
			_transitioning = false
			if is_inside_tree() and session != null and session.status == ArrowSession.Status.FAILED:
				_restart_now())
		return
	_restart_now()

func _restart_now() -> void:
	_track_level("level_restarted", {})
	_flush_clock()
	_retries[session.level_id()] = int(_retries.get(session.level_id(), 0)) + 1
	Progress.clear_active()
	_begin_level(session.level, {})

# --- rewarded ----------------------------------------------------------------------------------

func _offer_reward(kind: String) -> void:
	var state := AdsManager.rewarded_offer_state()
	if state == "unavailable":
		UI.toast("AD_UNAVAILABLE")
		return
	if state != "ready":
		UI.toast("AD_LOADING")
		AdsManager.retry_rewarded()
		return
	var title: String = {"hint": "REWARD_HINT_TITLE", "continue": "REWARD_CONTINUE_TITLE"}[kind]
	var body: String = {"hint": "REWARD_HINT_BODY", "continue": "REWARD_CONTINUE_BODY"}[kind]
	UI.confirm(title, body, func(): _watch_reward(kind), "WATCH_AD")

func _watch_reward(kind: String) -> void:
	if session == null or _ad_busy:
		return
	var attempt := session.attempt_id
	_ad_busy = true
	_board_view.cancel_input()
	var started := AdsManager.show_rewarded(kind, attempt,
		func(transaction_id: String): _on_reward_earned(kind, attempt, transaction_id),
		func(result: Dictionary): _on_reward_closed(kind, attempt, result))
	if not started:
		_ad_busy = false

## From the SDK's earned-reward callback (possibly while the ad is still showing). The grant is
## applied to the attempt it was earned for and saved immediately.
func _on_reward_earned(kind: String, attempt: String, transaction_id: String) -> void:
	if session == null or session.attempt_id != attempt:
		Diagnostics.log_event("ads", "reward_orphaned", {"kind": kind, "attempt_id": attempt, "tx": transaction_id})
		return
	if session.applied_rewards.has(transaction_id):
		return
	session.applied_rewards.append(transaction_id)
	match kind:
		"hint": session.grant_bonus_hint()
		"continue": session.continue_with_life()
	_save_attempt(true)

func _on_reward_closed(kind: String, attempt: String, result: Dictionary) -> void:
	_ad_busy = false
	if session == null or session.attempt_id != attempt:
		return
	if not bool(result.get("granted", false)):
		UI.toast("REWARD_NOT_EARNED" if str(result.get("reason", "")) == "dismissed_early" else "AD_UNAVAILABLE")
		_refresh_buttons()
		return
	match kind:
		"hint":
			_on_hint()
		"continue":
			_overlay.close()
			_ended = false
			_board_view.input_enabled = true
			_hearts.set_lives(session.lives)
			_set_coach("CONTINUE_NOTICE")
	_refresh_buttons()

# --- clear / fail ------------------------------------------------------------------------------

func _on_cleared(last_exit_seconds: float) -> void:
	_ended = true
	_board_view.input_enabled = false
	_board_view.clear_hint()
	_pinch.stop()
	_flush_clock()
	var level := session.level
	var level_id := session.level_id()
	var hard := bool(level.get("hard", false))
	var final := bool(level.get("final", false))
	var perfect := session.is_perfect()
	var stars := ResultWidgets.stars_for(session)
	var score := ResultWidgets.score_for(session, stars)
	var record := Progress.record_clear(level_id, mode, perfect, session.mistakes, "", stars, score)
	record["stars"] = stars
	record["score"] = score
	var streak := Progress.note_play_day(int(Time.get_unix_time_from_system()))
	var league := Progress.award_league(level, perfect, bool(record["first_clear"])) if mode == "campaign" else {}
	Progress.clear_active()
	var coach := str(level.get("coach", ""))
	if not coach.is_empty():
		Progress.mark_coach(coach)
	_track_level("level_completed", {"perfect": perfect, "first_clear": record["first_clear"],
		"league_points": int(league.get("total", 0)), "gold": session.gold_collected(), "stars": stars, "score": score})
	if hard and not Progress.flag("first_hard_completed"):
		Progress.set_flag("first_hard_completed")
		AnalyticsService.track(&"first_hard_completed", _level_params({}))
	if index == 4 and not Progress.flag("tutorial_completed"):
		Progress.set_flag("tutorial_completed")
		AnalyticsService.track(&"tutorial_completed", {"level_id": level_id})
	for scene_id in record["new_scenes"]:
		AnalyticsService.track(&"scene_unlocked", {"scene": scene_id, "level_id": level_id})
	for promoted in league.get("promotions", []):
		AnalyticsService.track(&"league_promoted", {"tier": LeagueRules.TIERS[int(promoted)], "points": int(league["points"])})
	_refresh_buttons()
	var reduced := bool(SettingsManager.get_value("reduced_motion"))
	# 1) the last arrow finishes leaving, 2) the camera pulls back and the empty picture answers,
	# 3) the result sheet.
	await get_tree().create_timer(0.05 if reduced else maxf(0.12, last_exit_seconds * 0.85), false).timeout
	if not is_inside_tree():
		return
	_board_view.reset_zoom()
	_board_view.celebrate(session.board.size(), hard)
	Feel.clear(session.board.size(), hard, perfect, final)
	_set_coach("")
	await get_tree().create_timer(0.1 if reduced else (0.9 if hard else 0.5), false).timeout
	if not is_inside_tree():
		return
	if final and not Progress.story_seen("ending"):
		var card := StoryCard.show_beat("ending")
		await card.finished
		if not is_inside_tree():
			return
	# The day streak, league and town are recorded above and shown at home, not in this flow.
	if bool(streak["new_day"]):
		AnalyticsService.track(&"play_day", {"streak": int(streak["count"])})
	_show_clear_card(record)

## The result sheet stays on the win and the next stage: a milestone ribbon (big boards only), the
## stars, one line, anything newly unlocked, and the big Next button.
func _show_clear_card(record: Dictionary) -> void:
	var body := _overlay.body
	_overlay.clear_content()
	var p := Palette.colors()
	var milestone := bool(session.level.get("hard", false))
	var stars := int(record.get("stars", 3))
	if milestone:
		var ribbon := Widgets.pill(tr("BIG_CLEAR"), Grades.plate(maxi(1, Grades.of(session.level))), Grades.INK, 18)
		ribbon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		body.add_child(ribbon)
	var star_row := ResultWidgets.Stars.new()
	star_row.count = stars
	body.add_child(star_row)
	var heading := Design.title("RATING_%d" % stars, 34 if milestone else 30)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(heading)
	var stage_label := Design.label(tr("STAGE_CLEAR") % index, 17, true, 700)
	stage_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	stage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(stage_label)
	if not record["new_scenes"].is_empty():
		var badges := HFlowContainer.new()
		badges.alignment = FlowContainer.ALIGNMENT_CENTER
		badges.add_theme_constant_override("h_separation", 8)
		for scene_id in record["new_scenes"]:
			badges.add_child(Widgets.pill(tr("SCENE_UNLOCKED") % tr(Scenery.SCENES[scene_id]["name"]), p["accent_soft"], p["accent_deep"], 16))
		body.add_child(badges)
		Feel.unlock()
	if index < Levels.campaign_count():
		var next_button := Design.button("NEXT_STAGE", _on_next)
		next_button.icon = Widgets.icon("play")
		next_button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		next_button.custom_minimum_size.y = 78
		next_button.add_theme_font_size_override("font_size", 24)
		body.add_child(next_button)
		next_button.grab_focus.call_deferred()
	else:
		var done := Design.label("CHAPTER1_DONE_BODY", 18, true)
		done.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.add_child(done)
		body.add_child(Design.button("TOWN_OPEN", func(): UI.push_modal(TownSheet.new())))
	body.add_child(Design.button("HOME", _go_home, true))
	_overlay.open()
	star_row.play.call_deferred()

func _on_next() -> void:
	# Only from a finished board's result sheet, once: a second tap in the same frame is ignored.
	if _transitioning or session == null or session.status != ArrowSession.Status.CLEARED or not _overlay.is_open():
		return
	_transitioning = true
	_refresh_buttons()
	var next_index := index + 1
	var next_hard := bool(Levels.campaign(next_index).get("hard", false)) if next_index <= Levels.campaign_count() else false
	# Natural break: an ad (if ready and allowed) shows now or never. Continuation runs once.
	AdsManager.interstitial_opportunity("level_complete", {"level_index": index, "mode": mode, "next_hard": next_hard},
		func(): _go_next(next_index))

func _go_next(next_index: int) -> void:
	if not is_inside_tree():
		return
	index = clampi(next_index, 1, Levels.campaign_count())
	_begin_level(Levels.campaign(index), {})

func _on_failed() -> void:
	_ended = true
	_board_view.input_enabled = false
	_board_view.clear_hint()
	_pinch.stop()
	_flush_clock()
	_track_level("level_failed", {})
	_save_attempt(true)
	Feel.fail()
	# No ad after a fail: the retry choice comes straight away (the blocked mark stays readable first).
	await get_tree().create_timer(0.9, false).timeout
	if is_inside_tree() and session != null and session.status == ArrowSession.Status.FAILED:
		_show_fail_card()

func _show_fail_card() -> void:
	_ended = true
	_board_view.input_enabled = false
	var body := _overlay.body
	_overlay.clear_content()
	var heading := Design.title("OUT_OF_HEARTS", 28)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(heading)
	var reason := Design.label("FAIL_REASON_ARROWS", 18, true, 600)
	reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(reason)
	body.add_child(Design.space(0.5))
	var first: BaseButtonView = null
	if session.can_restore_checkpoint():
		first = Design.button("CHECKPOINT_RESTORE", _on_checkpoint)
		first.icon = Widgets.icon("flag")
		first.custom_minimum_size.y = 72
		body.add_child(first)
		var left := Design.label(tr("CHECKPOINT_LEFT") % session.checkpoint_remaining(), 15, true, 650)
		left.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.add_child(left)
	var restart := Design.button("RESTART_FREE", _on_restart, first != null)
	restart.icon = Widgets.icon("restart")
	restart.custom_minimum_size.y = 72 if first == null else 60
	body.add_child(restart)
	if first == null:
		first = restart
	_continue_button = null
	_continue_note = null
	if session.can_continue() and AdsManager.rewarded_offer_state() != "unavailable":
		_continue_button = Design.button("CONTINUE_AD", func(): _offer_reward("continue"), true)
		_continue_button.icon = Widgets.icon("ad")
		body.add_child(_continue_button)
		_continue_note = Design.label("", 15, true, 600)
		_continue_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.add_child(_continue_note)
		_refresh_continue()
	body.add_child(Design.button("HOME", _go_home, true))
	first.grab_focus.call_deferred()
	_overlay.open()

## Fail sheet: back to the checkpoint board with full hearts (free, once per attempt).
func _on_checkpoint() -> void:
	if session == null or _transitioning or _ad_busy or not session.can_restore_checkpoint():
		return
	_flush_clock()
	if not session.restore_checkpoint():
		Diagnostics.log_event("game", "checkpoint_rejected", {"level_id": session.level_id()})
		UI.toast("ATTEMPT_RESET")
		return
	_track_level("checkpoint_restored", {"remaining": session.board.alive_count})
	_overlay.close()
	_ended = false
	_idle = 0.0
	_board_view.input_enabled = true
	_board_view.setup(session.board, {"scene": _scene_id, "mask": mask_of(session.level), "gold": session.level.get("gold", []),
		"wrong": session.wrong.keys()}, true)
	_on_camera_changed.call_deferred(false)
	_board_view.overview_then_play(0.6)
	_hearts.set_lives(session.lives, false)
	_gold_badge.set_count(session.gold_collected(), session.gold_total())
	_update_music()
	_refresh_buttons()
	_save_attempt(true)
	_set_coach("CHECKPOINT_BACK", 3.5)

func _refresh_continue() -> void:
	if _continue_button == null or not is_instance_valid(_continue_button):
		return
	var state := AdsManager.rewarded_offer_state()
	_continue_button.disabled = state != "ready"
	_continue_note.text = "" if state == "ready" else ("AD_LOADING" if state == "loading" else "AD_RETRY_LATER")
	_continue_note.visible = state != "ready"

# --- navigation & back -------------------------------------------------------------------------

func _go_home() -> void:
	if _ad_busy:
		return
	_flush_clock()
	if session != null and not _ended and session.status == ArrowSession.Status.PLAYING and not session.history.is_empty():
		_track_level("level_abandoned", {"remaining": session.board.alive_count})
	_save_attempt(true)
	AppManager.return_to_menu()

func _handle_back() -> bool:
	if _ad_busy:
		return true
	if _overlay.is_open():
		_go_home()
		return true
	return false

# --- persistence / clock / analytics -----------------------------------------------------------

func _save_attempt(immediate: bool) -> void:
	if session == null or session.status == ArrowSession.Status.CLEARED:
		return
	if immediate:
		Progress.save_active_now(session.to_save())
	else:
		Progress.stage_active(session.to_save())

func _process(delta: float) -> void:
	# Story cards hold the board (input off): neither the clock nor the idle hint runs behind them.
	if session == null or _ended or _paused or AdsManager.is_presenting() or session.status != ArrowSession.Status.PLAYING \
			or not _board_view.input_enabled:
		return
	if Time.get_ticks_msec() - _last_touch_ms < CLOCK_AWAY_MS:
		_clock_ms += delta * 1000.0
	if _clock_ms >= CLOCK_FLUSH_MS:
		_flush_clock()
	# Stuck for a while: offer the hint (twice per board at most), and nudge the bulb.
	_idle += delta
	if _idle >= IDLE_OFFER_SECONDS and _idle_offers < 2 and (_coach_key.is_empty() or _coach_key == "STUCK_HINT"):
		_idle = 0.0
		_idle_offers += 1
		_set_coach("STUCK_HINT", 4.0)
		if not SettingsManager.get_value("reduced_motion"):
			_hint_button.pivot_offset = _hint_button.size * 0.5
			var nudge := create_tween()
			nudge.tween_property(_hint_button, "scale", Vector2(1.18, 1.18), 0.14)
			nudge.tween_property(_hint_button, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK)

func _flush_clock() -> void:
	if session == null or _clock_ms < 1.0:
		return
	var chunk := int(_clock_ms)
	_clock_ms -= chunk
	session.active_ms += chunk
	Progress.add_play_ms(chunk)

## Shared parameters of every level event: which board, how hard, how long, how it went.
func _level_params(extra: Dictionary) -> Dictionary:
	var params := {"level_id": session.level_id(), "difficulty": str(session.level.get("tag", "")),
		"hard": bool(session.level.get("hard", false)), "ruleset": ArrowBoard.RULES, "seed": int(session.level.get("seed", 0)),
		"attempt_id": session.attempt_id, "mode": mode, "active_play_time": session.active_ms,
		"arrow_count": session.board.size(), "mistakes": session.mistakes, "collisions": session.blocked_taps,
		"touch_misses": _touch_misses, "hints_used": session.hints_used, "retry_count": session.retry_count,
		"zoom_used": _zoom_used}
	params.merge(extra, true)
	return params

func _track_level(event: String, extra: Dictionary) -> void:
	AnalyticsService.track(StringName(event), _level_params(extra))
