class_name ToggleView
extends BaseButtonView
func _ready() -> void:
	super._ready()
	toggle_mode = true
	theme_type_variation = &"SecondaryButton"
	custom_minimum_size.x = Design.TOUCH * 1.5
	toggled.connect(_reflect)
	_reflect(button_pressed)

func _reflect(enabled: bool) -> void:
	text = "ON" if enabled else "OFF"
