extends BasePage
## First launch goes straight to stage 1 (no menu tour). Later launches open Home, where an
## in-progress board is one tap away.

func _ready() -> void:
	super._ready()
	var title := Design.label("APP_TITLE", 44, false, 900)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(title)
	_boot.call_deferred()

func _boot() -> void:
	Levels.campaign_count() # loads and verifies the bundled packs before anything reads them
	var first_open := not Progress.flag("first_open_logged")
	SaveManager.mark_booted()
	if first_open:
		Progress.set_flag("first_open_logged")
		AnalyticsService.track(&"first_open", {"content_version": Levels.content_version})
	await get_tree().process_frame
	var fresh := Progress.campaign_cleared_count() == 0 and Progress.active_attempt().is_empty()
	if fresh:
		Nav.play_campaign(1)
	else:
		SceneManager.go_to("menu")
	if SaveManager.last_status in ["corrupt", "recovered", "future_version"]:
		UI.toast("SAVE_RECOVERY")
	if not Levels.replaced.is_empty():
		UI.toast("LEVEL_DATA_REPAIRED")
