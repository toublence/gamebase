extends Node
signal changed(key: String, value: Variant)
const LOCALES := ["system", "en", "ko", "de", "es", "fr", "ja", "ar", "zh_CN", "zh_TW"]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_language(str(get_value("language")))

func get_value(key: String) -> Variant:
	return SaveManager.data["settings"].get(key)

func set_value(key: String, value: Variant) -> bool:
	if SaveManager.read_only or not SaveManager.data["settings"].has(key):
		return false
	var old: Variant = get_value(key)
	if old is bool and not value is bool:
		return false
	if old is float:
		if not (value is float or value is int) or not is_finite(float(value)):
			return false
		value = clampf(float(value), 0.0, 1.0)
	if key == "language" and value not in LOCALES:
		return false
	if old == value:
		return true
	SaveManager.data["settings"][key] = value
	var saved := SaveManager.flush()
	if key == "language":
		_apply_language(str(value))
	changed.emit(key, value)
	return saved

func _apply_language(locale: String) -> void:
	TranslationServer.set_locale(OS.get_locale() if locale == "system" else locale)
