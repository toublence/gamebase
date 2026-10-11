extends Node
## Debug-only screen capture for design review (needs a real renderer, so it runs windowed):
##   godot --path . res://tests/capture/capture_screens.tscn -- --verify-base --out=/abs/dir
## Uses the isolated verification save. Writes PNG screenshots of the key screens.
var out_dir := ""

func _ready() -> void:
	if not OS.is_debug_build() or "--verify-base" not in OS.get_cmdline_user_args():
		get_tree().quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.substr(6)
	DisplayServer.window_set_size(Vector2i(540, 1170))
	get_tree().current_scene = null
	_run.call_deferred()

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(out_dir.path_join(name + ".png"))
	print("CAPTURED ", name)

func _game() -> Node:
	return get_tree().get_first_node_in_group("outtap_game")

func _run() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.storage_path + suffix))
	SaveManager.load_save()
	Progress.reload()
	SettingsManager.set_value("language", "ko")
	SettingsManager.set_value("music", false)
	SettingsManager.set_value("sound", false)
	for beat in Story.BEATS:
		Progress.mark_story(beat)
	await _wait(0.3)
	SceneManager.go_to("menu")
	await SceneManager.transition_finished
	await _wait(0.8)
	await _shot("01_home")
	Nav.play_campaign(1)
	await SceneManager.transition_finished
	await _wait(1.0)
	await _shot("02_stage1")
	Nav.play_campaign(4)
	await SceneManager.transition_finished
	await _wait(1.0)
	await _shot("03_stage4_star")
	Nav.play_campaign(5)
	await SceneManager.transition_finished
	await _wait(0.45)
	await _shot("04_stage5_hard_intro")
	await _wait(2.4)
	await _shot("05_stage5_board")
	var game := _game()
	var view: ArrowBoardView = game._board_view
	view.animate_zoom(view.max_zoom(), view.get_global_transform_with_canvas() * (view.size * Vector2(0.35, 0.55)))
	await _wait(0.6)
	await _shot("06_stage5_zoomed")
	view.reset_zoom()
	await _wait(0.5)
	game._on_hint()
	await _wait(0.4)
	await _shot("07_stage5_hint")
	Progress.note_play_day(int(Time.get_unix_time_from_system())) # today's lantern already lit: straight to the stars
	var sol: Array = game.session.level["sol"]
	for i in sol.size() / 2:
		game._on_tapped(int(sol[i]))
	await _wait(0.12)
	await _shot("08_stage5_escaping")
	for i in range(sol.size() / 2, sol.size()):
		game._on_tapped(int(sol[i]))
	for k in 50:
		if game._overlay.is_open():
			break
		await _wait(0.2)
	await _wait(0.9)
	await _shot("09_stage5_clear_card")
	for index in [8, 10, 13, 15, 18, 20]:
		Nav.play_campaign(index)
		await SceneManager.transition_finished
		await _wait(2.6)
		await _shot("%02d_stage%d" % [10 + index, index])
	Nav.levels("campaign")
	await SceneManager.transition_finished
	await _wait(0.8)
	await _shot("29_stage_list")
	AppManager.return_to_menu()
	await SceneManager.transition_finished
	await _wait(0.6)
	await _shot("30_home_after")
	var card := StoryCard.new()
	card.beat = "grade_1"
	UI.push_modal(card)
	await _wait(1.6)
	await _shot("34_story")
	card.close()
	await _wait(0.3)
	UI.push_modal(TownSheet.new())
	await _wait(0.6)
	await _shot("35_town")
	UI.push_modal(LeagueSheet.new())
	await _wait(0.6)
	await _shot("31_league")
	get_tree().call_group("modal", "close")
	UI.push_modal(ThemePicker.new())
	await _wait(0.6)
	await _shot("32_style")
	UI.show_settings()
	await _wait(0.6)
	await _shot("33_settings")
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.storage_path + suffix))
	get_tree().quit(0)
