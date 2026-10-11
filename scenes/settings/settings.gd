extends ModalView
## Settings. Every row works; privacy options appear only when the consent SDK requires them.
const LANGUAGE_NAMES := ["SYSTEM_LANGUAGE", "English", "한국어", "Deutsch", "Español", "Français", "日本語", "العربية", "简体中文", "繁體中文"]

func _ready() -> void:
	super._ready()
	_build()
	SettingsManager.changed.connect(_on_setting_changed)

func _on_setting_changed(key: String, _value: Variant) -> void:
	if key == "language" and is_inside_tree():
		for child in body.get_children():
			child.queue_free()
		_build.call_deferred()

func _build() -> void:
	body.add_child(Design.title("SETTINGS", 30))
	for pair in [["music", "MUSIC"], ["sound", "SOUND"], ["voice", "VOICE"], ["haptic", "HAPTIC"], ["reduced_motion", "REDUCED_MOTION"], ["arrow_colors", "ARROW_COLORS"]]:
		body.add_child(_toggle_row(pair[0], pair[1]))
		if pair[0] == "voice":
			body.add_child(Design.label("VOICE_NOTE", 14, true, 600))
	var language := OptionButton.new()
	language.custom_minimum_size.y = Design.TOUCH
	for language_name in LANGUAGE_NAMES:
		language.add_item(language_name)
	language.selected = maxi(0, SettingsManager.LOCALES.find(SettingsManager.get_value("language")))
	language.item_selected.connect(func(index: int): SettingsManager.set_value("language", SettingsManager.LOCALES[index]))
	language.disabled = SaveManager.read_only
	var row := SettingsRow.new()
	row.configure("LANGUAGE", language)
	body.add_child(row)
	body.add_child(Design.space(0.5))
	body.add_child(Design.label("PRIVACY_SECTION", 17, false, 800))
	if AdsManager.privacy_options_required():
		body.add_child(Design.button("PRIVACY_OPTIONS", AdsManager.show_privacy_options, true))
	var privacy_note := Design.label("PRIVACY_NOTE", 15, true)
	body.add_child(privacy_note)
	body.add_child(Design.button("RESET_PROGRESS", _confirm_reset, true))
	if AdsManager.diagnostics_available():
		body.add_child(Design.button("AD_DIAGNOSTICS", func(): UI.push_modal(load("res://scenes/debug/ads_diagnostics.gd").new()), true))
	body.add_child(Design.space(0.5))
	body.add_child(Design.label("CREDITS", 17, false, 800))
	for key in ["CREDITS_VOICE", "CREDITS_AUDIO", "CREDITS_FONT"]:
		body.add_child(Design.label(key, 14, true, 600))
	var version := Design.label(tr("VERSION_LABEL") % [ProjectSettings.get_setting("application/config/version", "0.1.0"), Levels.content_version], 13, true)
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(version)
	var done_button := Design.button("DONE", close)
	body.add_child(done_button)
	done_button.grab_focus.call_deferred()

func _toggle_row(key: String, label_key: String) -> Control:
	var row := Design.row(12)
	row.custom_minimum_size.y = Design.TOUCH
	var label := Design.label(label_key, 19, false, 700)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var toggle := SwitchToggle.new()
	toggle.button_pressed = bool(SettingsManager.get_value(key))
	toggle.disabled = SaveManager.read_only
	toggle.accessibility_name = label_key
	toggle.toggled.connect(func(value: bool):
		SettingsManager.set_value(key, value)
		if key in ["music", "sound"]:
			AnalyticsService.track(&"sound_settings_changed", {"setting": key, "value": value})
		elif key == "voice":
			AnalyticsService.track(&"voice_settings_changed", {"value": value}))
	row.add_child(toggle)
	return row

func _confirm_reset() -> void:
	UI.confirm("RESET_TITLE", "RESET_BODY", func():
		UI.confirm("RESET_CONFIRM_TITLE", "RESET_CONFIRM_BODY", _reset, "RESET_CONFIRM_ACTION"), "RESET_NEXT")

func _reset() -> void:
	var ok := Progress.reset_progress()
	UI.toast("RESET_DONE" if ok else "SAVE_ERROR")
	UI.close_all()
	get_tree().paused = false
	if SceneManager.current_route == "game":
		AppManager.state = AppManager.State.PLAYING
		AppManager.return_to_menu()
	else:
		SceneManager.go_to("menu")
