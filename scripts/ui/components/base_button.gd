class_name BaseButtonView
extends Button
var _press_tween: Tween

func _ready() -> void:
	# Never below the touch size; larger heights set before entering the tree are kept.
	custom_minimum_size.y = maxf(custom_minimum_size.y, Design.TOUCH)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button_down.connect(_down)
	button_up.connect(_up)
	mouse_exited.connect(_up)
	pressed.connect(_feedback)
	resized.connect(func(): pivot_offset = size * 0.5)

func _down() -> void:
	_animate(Vector2(0.975, 0.975))

func _up() -> void:
	_animate(Vector2.ONE)

func _animate(target: Vector2) -> void:
	if _press_tween != null and _press_tween.is_valid():
		_press_tween.kill()
	if SettingsManager.get_value("reduced_motion"):
		scale = Vector2.ONE
		return
	_press_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_press_tween.tween_property(self, "scale", target, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _feedback() -> void:
	HapticManager.light()
	AudioManager.play_sfx(UI.config.ui_click)
