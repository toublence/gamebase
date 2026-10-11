class_name SwitchToggle
extends Button
## Pill switch with an ON/OFF word inside so the state never depends on color alone.
var _knob := 0.0:
	set(value):
		_knob = value
		queue_redraw()

func _init() -> void:
	# Toggle mode first: a Button ignores button_pressed until it is a toggle, and the settings
	# screen sets the stored state before the switch enters the tree.
	toggle_mode = true

func _ready() -> void:
	toggle_mode = true
	flat = true
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(92, Design.TOUCH)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_knob = 1.0 if button_pressed else 0.0
	toggled.connect(_animate)
	toggled.connect(func(_v: bool):
		HapticManager.light()
		AudioManager.play_sfx(UI.config.ui_click))

func _animate(on: bool) -> void:
	if SettingsManager.get_value("reduced_motion"):
		_knob = 1.0 if on else 0.0
		return
	var tween := create_tween()
	tween.tween_property(self, "_knob", 1.0 if on else 0.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _draw() -> void:
	var p := Palette.colors()
	var track := Rect2(Vector2(4, (size.y - 40) * 0.5), Vector2(size.x - 8, 40))
	var on_color: Color = p["accent"]
	var off_color: Color = p["side"]
	var color := off_color.lerp(on_color, _knob)
	if disabled:
		color = Color(color, 0.45)
	draw_style_box(Design.box(color, 20, 0, Color.TRANSPARENT, 0.0), track)
	var r := 16.0
	var x := lerpf(track.position.x + 4 + r, track.end.x - 4 - r, _knob)
	var center := Vector2(x, track.get_center().y)
	draw_circle(center + Vector2(0, 2), r, Color(p["shadow"], 0.18), true, -1.0, true)
	draw_circle(center, r, p["face"], true, -1.0, true)
	var font := Design.font(800)
	var text := tr("ON") if button_pressed else tr("OFF")
	var fs := 13
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var text_x := track.position.x + 12 if button_pressed else track.end.x - 12 - w
	draw_string(font, Vector2(text_x, track.get_center().y + fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		Color.WHITE if button_pressed else p["ink_soft"])
	if has_focus():
		var ring := StyleBoxFlat.new()
		ring.draw_center = false
		ring.set_border_width_all(3)
		ring.border_color = Color(p["accent"], 0.6)
		ring.set_corner_radius_all(24)
		draw_style_box(ring, track.grow(3))
