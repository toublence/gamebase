class_name LoadingIndicator
extends Label
var _tween: Tween

func _ready() -> void:
	text = "LOADING"
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if not SettingsManager.get_value("reduced_motion"):
		_tween = create_tween().set_loops()
		_tween.tween_property(self, "modulate:a", 0.4, 0.55)
		_tween.tween_property(self, "modulate:a", 1.0, 0.55)
