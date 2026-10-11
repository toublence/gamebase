class_name HardBanner
extends CanvasLayer
## The short HARD intro shown when a HARD stage starts: a gold "HARD" plate on deep violet that
## settles in, holds, and fades by itself (about two seconds). It never blocks touches. Reduced
## motion shows it without movement.
var _root: Control
var _plate: PanelContainer
var _title: Label
var _sub: Label
var _style: StyleBoxFlat

func _ready() -> void:
	layer = 18
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	_plate = PanelContainer.new()
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := Design.box(Color("2A1B4D", 0.94), 28, 6, Color("150D2B"), 22.0)
	_style = style
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_color = Scenery.GOLD
	style.content_margin_left = 34
	style.content_margin_right = 34
	_plate.add_theme_stylebox_override("panel", style)
	center.add_child(_plate)
	var column := Design.column(4)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.add_child(column)
	_title = Design.label("HARD", 58, false, 900)
	_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_color", Grades.INK)
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	_title.add_theme_constant_override("shadow_offset_y", 3)
	column.add_child(_title)
	_sub = Design.label("", 17, false, 700)
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.add_theme_color_override("font_color", Color("E9E2FF"))
	column.add_child(_sub)
	_root.visible = false

func play(subtitle_key: String, grade: int = 1) -> void:
	_sub.text = subtitle_key
	# No grade name on screen: the plate carries only the "big board" line.
	_title.visible = false
	_style.bg_color = Color(Grades.plate(grade), 0.94)
	_style.border_width_bottom = 6
	_style.border_color = Scenery.GOLD
	# A fixed plate width so the subtitle wraps into lines instead of one letter per line.
	_plate.custom_minimum_size.x = minf(400.0, _root.get_viewport_rect().size.x - 48.0)
	_root.visible = true
	_plate.pivot_offset = _plate.size * 0.5
	var reduced := bool(SettingsManager.get_value("reduced_motion"))
	var tween := create_tween()
	if reduced:
		_root.modulate.a = 1.0
		tween.tween_interval(1.8)
	else:
		_root.modulate.a = 0.0
		_plate.scale = Vector2(0.82, 0.82)
		tween.tween_property(_root, "modulate:a", 1.0, 0.18)
		tween.parallel().tween_property(_plate, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_interval(1.25)
	tween.tween_property(_root, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func(): _root.visible = false)
	# The plate sizes itself after the first frame; recenter the pivot then.
	await get_tree().process_frame
	_plate.pivot_offset = _plate.size * 0.5

func hide_now() -> void:
	_root.visible = false
