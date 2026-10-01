class_name VolumeSlider
extends HSlider
var setting_key := ""
var _dragging := false

func _ready() -> void:
	custom_minimum_size.y = Design.TOUCH
	min_value = 0.0
	max_value = 1.0
	step = 0.05
	scrollable = false
	value = float(SettingsManager.get_value(setting_key))
	editable = not SaveManager.read_only
	drag_started.connect(func(): _dragging = true)
	drag_ended.connect(_commit_drag)
	value_changed.connect(_changed)

func _commit_drag(_changed_value: bool) -> void:
	_dragging = false
	SettingsManager.set_value(setting_key, value)

func _changed(new_value: float) -> void:
	if not _dragging:
		SettingsManager.set_value(setting_key, new_value)

func _exit_tree() -> void:
	if _dragging:
		SettingsManager.set_value(setting_key, value)
