extends Node
## JSON-only extension data. One writer, atomic replacement, previous good backup.
signal save_failed(reason: String)
const SCHEMA := 2
const MAX_BYTES := 2097152
var storage_path := "user://save.json"
var data: Dictionary = {}
var read_only := false
var last_status := "new"
var _primary_valid := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Isolated storage only for the excluded, explicitly launched verification scene.
	if OS.is_debug_build() and "--verify-base" in OS.get_cmdline_user_args():
		storage_path = "user://verification/save.json"
	load_save()

func defaults() -> Dictionary:
	return {"version": SCHEMA, "settings": {"music": true, "sound": true, "voice": true, "arrow_colors": false,
		"haptic": true, "reduced_motion": false, "master_volume": 1.0,
		"music_volume": 0.45, "sfx_volume": 0.8, "language": "system"},
		"common": {"first_run": true, "total_play_sessions": 0}, "games": {}}

func load_save() -> void:
	data = defaults()
	read_only = false
	_primary_valid = false
	last_status = "new"
	for path in [storage_path, storage_path + ".bak", storage_path + ".tmp"]:
		var candidate := _read(path)
		if candidate.is_empty():
			continue
		var version: Variant = candidate.get("version", 1)
		if not (version is int or version is float) or not is_finite(float(version)):
			continue
		if int(version) > SCHEMA:
			read_only = true
			last_status = "future_version"
			return # Never overwrite a newer save, even if the backup is older.
		if int(version) < 1:
			continue
		data = _normalize(_migrate(candidate, int(version)))
		_primary_valid = path == storage_path
		last_status = "loaded" if _primary_valid else "recovered"
		return
	if FileAccess.file_exists(storage_path):
		last_status = "corrupt"

func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES:
		return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return {}
	return parser.data

func _migrate(source: Dictionary, version: int) -> Dictionary:
	var result := source.duplicate(true)
	if version == 1 and result.get("settings") is Dictionary:
		var settings: Dictionary = result["settings"]
		if settings.has("sfx"):
			settings["sound"] = settings["sfx"]
			settings.erase("sfx")
	result["version"] = SCHEMA
	return result

func _normalize(source: Dictionary) -> Dictionary:
	var result := defaults()
	var settings: Variant = source.get("settings", {})
	if settings is Dictionary:
		for key in result["settings"]:
			var value: Variant = settings.get(key)
			var fallback: Variant = result["settings"][key]
			if fallback is bool and value is bool:
				result["settings"][key] = value
			elif fallback is float and (value is float or value is int) and is_finite(float(value)):
				result["settings"][key] = clampf(float(value), 0.0, 1.0)
			elif fallback is String and value is String:
				result["settings"][key] = value
	var common: Variant = source.get("common", {})
	if common is Dictionary:
		if common.get("first_run") is bool:
			result["common"]["first_run"] = common["first_run"]
		var count: Variant = common.get("total_play_sessions", 0)
		if (count is int or count is float) and is_finite(float(count)):
			result["common"]["total_play_sessions"] = maxi(0, int(count))
	if source.get("games") is Dictionary:
		result["games"] = source["games"].duplicate(true)
	return result

func flush() -> bool:
	if read_only:
		return _fail("future_version")
	var text := JSON.stringify(data)
	if text.to_utf8_buffer().size() > MAX_BYTES:
		return _fail("too_large")
	var absolute := ProjectSettings.globalize_path(storage_path)
	if DirAccess.make_dir_recursive_absolute(absolute.get_base_dir()) != OK:
		return _fail("directory")
	var file := FileAccess.open(storage_path + ".tmp", FileAccess.WRITE)
	if file == null:
		return _fail("open")
	file.store_string(text)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return _fail("write")
	if FileAccess.file_exists(storage_path):
		if _primary_valid:
			if FileAccess.file_exists(storage_path + ".bak"):
				if DirAccess.remove_absolute(absolute + ".bak") != OK:
					return _fail("backup_remove")
			if DirAccess.rename_absolute(absolute, absolute + ".bak") != OK:
				return _fail("backup")
		else:
			if DirAccess.remove_absolute(absolute) != OK:
				return _fail("replace_corrupt")
	if DirAccess.rename_absolute(absolute + ".tmp", absolute) != OK:
		return _fail("replace")
	_primary_valid = true
	return true

func _fail(reason: String) -> bool:
	last_status = reason
	save_failed.emit(reason)
	return false

func get_game_data(game_key: String) -> Dictionary:
	var value: Variant = data["games"].get(game_key, {})
	return value.duplicate(true) if value is Dictionary else {}

func set_game_data(game_key: String, value: Dictionary) -> bool:
	if read_only or game_key.is_empty() or not _json_safe(value):
		return false
	data["games"][game_key] = value.duplicate(true)
	return flush()

## Updates the in-memory namespace without writing. The next flush (explicit, background, or any
## immediate set_game_data) persists it atomically together with everything else.
func stage_game_data(game_key: String, value: Dictionary) -> bool:
	if read_only or game_key.is_empty() or not _json_safe(value):
		return false
	data["games"][game_key] = value.duplicate(true)
	return true

func _json_safe(value: Variant, depth: int = 0) -> bool:
	if depth > 32:
		return false
	if value == null or value is bool or value is String or value is int:
		return true
	if value is float:
		return is_finite(value)
	if value is Array:
		for child in value:
			if not _json_safe(child, depth + 1):
				return false
		return true
	if value is Dictionary:
		for key in value:
			if not key is String or not _json_safe(value[key], depth + 1):
				return false
		return true
	return false

func mark_session_started() -> void:
	data["common"]["total_play_sessions"] += 1
	flush()

func mark_booted() -> void:
	if data["common"]["first_run"]:
		data["common"]["first_run"] = false
		flush()
