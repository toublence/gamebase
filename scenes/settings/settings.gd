extends ModalView
const LANGUAGE_NAMES := ["SYSTEM_LANGUAGE", "English", "한국어", "Deutsch", "Español", "Français", "日本語", "العربية", "简体中文", "繁體中文"]

func _ready() -> void:
	super._ready()
	body.add_child(Design.label("SETTINGS", 30))
	for pair in [["music", "MUSIC"], ["sound", "SOUND"], ["haptic", "HAPTIC"], ["reduced_motion", "REDUCED_MOTION"]]:
		_add_toggle(pair[0], pair[1])
	for pair in [["master_volume", "MASTER_VOLUME"], ["music_volume", "MUSIC_VOLUME"], ["sfx_volume", "SFX_VOLUME"]]:
		_add_volume(pair[0], pair[1])
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
	body.add_child(Design.button("PREVIEW_SOUND", func(): AudioManager.play_sfx(UI.config.ui_click), true))
	body.add_child(Design.button("PREVIEW_HAPTIC", HapticManager.medium, true))
	if AdsManager.privacy_options_required():
		body.add_child(Design.button("PRIVACY_OPTIONS", AdsManager.show_privacy_options, true))
	body.add_child(Design.label("SETTINGS_SAVED", 15, true))
	var done_button := Design.button("DONE", close)
	body.add_child(done_button)
	done_button.grab_focus.call_deferred()

func _add_toggle(key: String, label_key: String) -> void:
	var toggle := ToggleView.new()
	toggle.button_pressed = bool(SettingsManager.get_value(key))
	toggle.disabled = SaveManager.read_only
	toggle.toggled.connect(func(value: bool): SettingsManager.set_value(key, value))
	var row := SettingsRow.new()
	row.configure(label_key, toggle)
	body.add_child(row)

func _add_volume(key: String, label_key: String) -> void:
	var slider := VolumeSlider.new()
	slider.setting_key = key
	var row := SettingsRow.new()
	row.configure(label_key, slider)
	body.add_child(row)
