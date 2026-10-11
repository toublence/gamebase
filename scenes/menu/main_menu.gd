extends BasePage
## Home: the current stage's board as the hero picture, one big Continue button, and stage select.
## No stat cards. A banner (when available) sits under the content, never over it.

func _ready() -> void:
	super._ready()
	AudioManager.play_music(UI.config.menu_music)
	body.add_theme_constant_override("separation", 14)
	_build()
	use_banner()
	Progress.league_changed.connect(_on_league_changed)

func _on_theme_changed(id: String) -> void:
	super._on_theme_changed(id)
	_rebuild()

func _on_league_changed() -> void:
	_rebuild()

func _rebuild() -> void:
	for child in body.get_children():
		child.queue_free()
	_build()
	tint_for_scene.call_deferred()

func _build() -> void:
	var header := Design.row(8)
	body.add_child(header)
	var word := Design.label("APP_TITLE", 34, false, 900)
	word.autowrap_mode = TextServer.AUTOWRAP_OFF
	word.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(word)
	header.add_child(Widgets.icon_button("theme", "STYLE", func(): UI.push_modal(ThemePicker.new())))
	header.add_child(Widgets.icon_button("settings", "SETTINGS", UI.show_settings))
	var tagline := Design.label("STORY_CHAPTER1", 16, true, 650)
	body.add_child(tagline)
	var active := Progress.active_attempt()
	var resume_level := Levels.by_id(str(active.get("level_id", ""))) if not active.is_empty() else {}
	var stage := Levels.index_of(str(resume_level.get("id", ""))) if not resume_level.is_empty() else Progress.reached()
	var all_done := Progress.campaign_cleared_count() >= Levels.campaign_count()
	var preview := MiniBoard.new()
	preview.custom_minimum_size = Vector2(0, 420)
	preview.set_level(resume_level if not resume_level.is_empty() else Levels.campaign(stage))
	body.add_child(preview)
	var heading := Design.title(tr("STAGE_N") % stage, 34)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(heading)
	var chapter := Levels.chapter_of(stage)
	var caption := Design.label(tr("CHAPTER_PROGRESS") % [chapter, Progress.chapter_cleared_count(chapter),
		mini(Levels.CHAPTER_SIZE, Levels.campaign_count() - (chapter - 1) * Levels.CHAPTER_SIZE)], 16, true, 650)
	# A saved attempt that ran out of hearts is not "in progress": it waits for a retry.
	var failed := not resume_level.is_empty() and int(active.get("status", 0)) == ArrowSession.Status.FAILED
	if failed:
		caption.text = tr("RETRY_CAPTION")
	elif not resume_level.is_empty():
		caption.text = tr("IN_PROGRESS")
	elif all_done:
		caption.text = tr("ALL_DONE_SHORT")
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(caption)
	var started := Progress.campaign_cleared_count() > 0 or not active.is_empty()
	var play := Design.button("RETRY" if failed else ("CONTINUE" if started else "START"), Nav.continue_game)
	play.icon = Widgets.icon("restart" if failed else "play")
	play.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	play.custom_minimum_size.y = 78
	play.add_theme_font_size_override("font_size", 26)
	body.add_child(play)
	play.grab_focus.call_deferred()
	var stages := Design.button(tr("STAGES") + "  ·  " + tr("STAGES_PROGRESS") % [Progress.campaign_cleared_count(), Levels.campaign_count()],
		func(): Nav.levels("campaign"), true)
	stages.icon = Widgets.icon("grid")
	body.add_child(stages)
	var town := Design.button(tr("TOWN_HOME") % [Progress.restored_count(), Story.PIECES.size()],
		func(): UI.push_modal(TownSheet.new()), true)
	town.icon = Widgets.icon("star")
	body.add_child(town)
	body.add_child(_league_button())
	if Progress.flag("migrated_from_v1") and not Progress.flag("migration_notice_shown"):
		Progress.set_flag("migration_notice_shown")
		UI.toast.call_deferred("MIGRATION_NOTICE")
	elif Progress.flag("campaign_redesigned") and not Progress.flag("redesign_notice_shown"):
		Progress.set_flag("redesign_notice_shown")
		UI.toast.call_deferred("REDESIGN_NOTICE")
	var week := Progress.take_league_result()
	if not week.is_empty():
		LeagueSheet.show_week_result.call_deferred(week)

## The personal league at a glance; opens the league sheet.
func _league_button() -> BaseButtonView:
	var lg := Progress.league()
	var button := Design.button(tr("LEAGUE_HOME") % [tr(LeagueRules.tier_name(int(lg["tier"]))), int(lg["points"])],
		func(): UI.push_modal(LeagueSheet.new()), true)
	var medal := LeagueMedal.new()
	medal.tier = int(lg["tier"])
	medal.custom_minimum_size = Vector2(34, 34)
	medal.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	medal.position = Vector2(16, -17)
	button.add_child(medal)
	button.accessibility_name = "LEAGUE_TITLE"
	return button
