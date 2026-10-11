extends Node
## Autoload "Diagnostics". Local ring buffer of game, ad and error events. Nothing leaves the device:
## the export writes a text file under user:// and, on request, copies it to the clipboard.
signal logged(entry: Dictionary)
const CAPACITY := 600
const EXPORT_PATH := "user://diagnostics_export.txt"

var _entries: Array[Dictionary] = []
var _start_unix := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_start_unix = Time.get_unix_time_from_system()

func log_event(category: String, event: String, data: Dictionary = {}, level: String = "info") -> void:
	var entry := {"t": Time.get_ticks_msec(), "unix": Time.get_unix_time_from_system(), "cat": category,
		"event": event, "data": data.duplicate(true), "level": level}
	_entries.append(entry)
	if _entries.size() > CAPACITY:
		_entries.pop_front()
	if OS.is_debug_build():
		print("[%s] %s %s" % [category, event, JSON.stringify(data)])
	logged.emit(entry)

func error(category: String, event: String, data: Dictionary = {}) -> void:
	log_event(category, event, data, "error")
	if OS.is_debug_build():
		push_warning("[%s] %s %s" % [category, event, JSON.stringify(data)])

func entries(category: String = "") -> Array[Dictionary]:
	if category.is_empty():
		return _entries.duplicate()
	var result: Array[Dictionary] = []
	for e in _entries:
		if e["cat"] == category:
			result.append(e)
	return result

func last(category: String, event: String) -> Dictionary:
	for i in range(_entries.size() - 1, -1, -1):
		if _entries[i]["cat"] == category and _entries[i]["event"] == event:
			return _entries[i]
	return {}

func format_entry(e: Dictionary) -> String:
	var stamp := Time.get_datetime_string_from_unix_time(int(e["unix"]), true)
	return "%s +%.3fs [%s] %s %s%s" % [stamp, e["t"] / 1000.0, e["cat"], e["event"], JSON.stringify(e["data"]),
		"  !" if e["level"] == "error" else ""]

func export_text(extra: Dictionary = {}) -> String:
	var lines := PackedStringArray()
	lines.append("Outtap diagnostics %s" % Time.get_datetime_string_from_system(true))
	lines.append("engine %s | os %s %s | model %s | debug %s" % [Engine.get_version_info()["string"], OS.get_name(),
		OS.get_version(), OS.get_model_name(), OS.is_debug_build()])
	for key in extra:
		lines.append("%s: %s" % [key, JSON.stringify(extra[key])])
	for e in _entries:
		lines.append(format_entry(e))
	return "\n".join(lines)

## Writes the export file and returns its absolute path ("" on failure).
func save_export(extra: Dictionary = {}) -> String:
	var file := FileAccess.open(EXPORT_PATH, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(export_text(extra))
	file.close()
	return ProjectSettings.globalize_path(EXPORT_PATH)
