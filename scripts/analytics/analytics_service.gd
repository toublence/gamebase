extends Node
var _adapter: AnalyticsAdapter = AnalyticsAdapter.new()

func _ready() -> void:
	SettingsManager.changed.connect(func(key: String, value: Variant): settings_changed(key, value))

func set_adapter(adapter: AnalyticsAdapter) -> void:
	_adapter = adapter if adapter != null else AnalyticsAdapter.new()

func track(event: StringName, parameters: Dictionary = {}) -> void:
	_adapter.record(event, parameters.duplicate(true))

func game_start() -> void:
	track(&"game_start")
func game_end() -> void:
	track(&"game_end")
func game_restart() -> void:
	track(&"game_restart")
func settings_changed(key: String, value: Variant) -> void:
	track(&"settings_changed", {"setting": key, "value": value})
func ad_impression(format: String) -> void:
	track(&"ad_impression", {"format": format})
func rewarded_completed() -> void:
	track(&"rewarded_completed")
