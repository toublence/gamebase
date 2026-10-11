extends Node
## Launched only by tools/verify.py. Never referenced by production resources.
var failures: Array[String] = []
var checks := 0

func _ready() -> void:
	if not OS.is_debug_build() or "--verify-base" not in OS.get_cmdline_user_args():
		get_tree().quit(2)
		return
	get_tree().current_scene = null # Keep the runner alive across real scene changes.
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _write_save(value: String) -> void:
	var file := FileAccess.open(SaveManager.storage_path, FileAccess.WRITE)
	file.store_string(value)
	file.close()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://verification"))
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.storage_path + suffix))
	SaveManager.load_save()
	check(SaveManager.data["common"]["first_run"], "new save defaults")
	check(SettingsManager.set_value("sound", false), "settings write")
	SaveManager.load_save()
	check(SettingsManager.get_value("sound") == false, "settings survives reload")
	check(SaveManager.set_game_data("integration", {"value": 12, "nested": [true, "text"]}), "extension write")
	SaveManager.load_save()
	check(SaveManager.get_game_data("integration").get("value") == 12, "extension roundtrip")
	check(not SaveManager.set_game_data("bad", {"value": Vector2.ONE}), "reject non-JSON save values")
	check(not SettingsManager.set_value("music_volume", "invalid"), "reject wrong setting type")
	check(not SettingsManager.set_value("language", "invalid"), "reject unsupported locale")
	SaveManager.flush()
	_write_save("{broken")
	SaveManager.load_save()
	check(SaveManager.last_status == "recovered", "corrupt primary recovers backup")
	check(SaveManager.get_game_data("integration").get("value") == 12, "backup data retained")
	check(SaveManager.flush(), "recovered save can be committed")
	_write_save('{"version":1,"settings":{"sfx":false,"music_volume":8},"common":{"total_play_sessions":-1}}')
	SaveManager.load_save()
	check(SaveManager.data["version"] == 2 and not SettingsManager.get_value("sound"), "v1 migration")
	check(SettingsManager.get_value("music_volume") == 1.0, "volume clamp")
	check(SaveManager.data["common"]["total_play_sessions"] == 0, "counter sanitization")
	_write_save('{"version":999,"settings":{}}')
	SaveManager.load_save()
	check(SaveManager.read_only and not SaveManager.flush(), "future schema blocks writes")
	check(not SettingsManager.set_value("sound", true), "future schema blocks settings mutation")
	_write_save('{"version":2,"settings":[],"common":null,"games":7}')
	SaveManager.load_save()
	check(SettingsManager.get_value("sound") == true and SaveManager.data["games"].is_empty(), "malformed sections default safely")
	SettingsManager.set_value("reduced_motion", true)
	for locale in SettingsManager.LOCALES:
		if locale == "system":
			continue
		TranslationServer.set_locale(locale)
		check(TranslationServer.translate("SETTINGS") != "SETTINGS", "locale loaded: " + locale)
	TranslationServer.set_locale("en")
	SettingsManager.set_value("music", false)
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "music mute bus")
	SettingsManager.set_value("sound", false)
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "SFX mute bus")
	SettingsManager.set_value("master_volume", 0.5)
	check(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(0)), 0.5), "master volume bus")
	SettingsManager.set_value("sound", true)
	SettingsManager.set_value("music", true)
	AudioManager.play_music(null)
	AudioManager.play_sfx(null)
	HapticManager.light()
	HapticManager.medium()
	HapticManager.strong()
	HapticManager.success()
	check(AdsManager.rewarded_offer_state() == "unavailable", "rewarded unavailable without a provider")
	var rewards: Array[bool] = []
	AdsManager.show_rewarded("hint", "verify", func(_tx: String): rewards.append(true),
		func(result: Dictionary): rewards.append(bool(result["granted"])))
	check(rewards == [false], "unavailable rewarded callback completes without reward")
	# A returning player boots to Home (a first launch goes straight to stage 1; see arrow_flow_tests).
	Progress.reload()
	Progress.record_clear("a001", "campaign", true, 0)
	check(get_tree().change_scene_to_file("res://scenes/boot/boot.tscn") == OK, "boot scene loads")
	await SceneManager.transition_finished
	check(SceneManager.current_route == "menu", "boot to menu")
	check(not SaveManager.data["common"]["first_run"], "first run persisted")
	for dimensions in [Vector2i(360, 780), Vector2i(900, 420), Vector2i(1024, 1366)]:
		get_window().size = dimensions
		await get_tree().process_frame
		await get_tree().process_frame
		var page: BasePage = get_tree().current_scene
		check(page.body.size.x <= page.get_viewport_rect().size.x, "menu width at " + str(dimensions))
	UI.show_settings()
	await get_tree().process_frame
	check(UI.handle_back(), "settings back closes modal")
	await get_tree().process_frame
	check(SceneManager.go_to("game"), "game navigation accepted")
	check(not SceneManager.go_to("menu"), "duplicate navigation rejected")
	await SceneManager.transition_finished
	check(GameSession.state == GameSession.State.ACTIVE, "host session started")
	var shown := [0]
	AdsManager.interstitial_opportunity("pause", {"level_index": 9}, func(): shown[0] += 1)
	check(shown[0] == 1 and AdsManager.last_skip["reason"] != "", "no interstitial outside a natural break; play continues")
	AppManager.pause_game()
	check(get_tree().paused and GameSession.state == GameSession.State.PAUSED, "pause stops scene tree")
	UI.show_settings()
	await get_tree().process_frame
	UI.handle_back()
	check(get_tree().paused, "closing nested settings preserves pause")
	AppManager.resume_game()
	check(not get_tree().paused and GameSession.state == GameSession.State.ACTIVE, "resume restores session")
	AppManager._notification(NOTIFICATION_APPLICATION_PAUSED)
	check(GameSession.state == GameSession.State.PAUSED, "background pauses gameplay")
	AppManager._notification(NOTIFICATION_APPLICATION_RESUMED)
	check(GameSession.state == GameSession.State.PAUSED, "foreground waits for explicit resume")
	AppManager.resume_game()
	GameSession.finish({"title": "SESSION_COMPLETE", "value": "42", "best": "84"})
	await SceneManager.transition_finished
	check(SceneManager.current_route == "result" and GameSession.result["value"] == "42", "finish displays injected result")
	AppManager.restart_game()
	await SceneManager.transition_finished
	check(GameSession.state == GameSession.State.ACTIVE and GameSession.result.is_empty(), "replay starts fresh")
	AppManager.return_to_menu()
	await SceneManager.transition_finished
	check(SceneManager.current_route == "menu" and GameSession.state == GameSession.State.IDLE, "return to menu")
	TranslationServer.set_locale("ar")
	await get_tree().process_frame
	check(get_tree().current_scene.is_layout_rtl(), "Arabic layout direction")
	TranslationServer.set_locale("en")
	await get_tree().process_frame
	Progress.reset_progress()
	print("BASE_VERIFY: %d checks, %d failures" % [checks, failures.size()])
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.storage_path + suffix))
	AudioManager.play_music(null)
	await get_tree().create_timer(0.15, true).timeout
	get_tree().quit(0 if failures.is_empty() else 1)
