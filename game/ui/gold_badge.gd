class_name GoldBadge
extends HBoxContainer
## Golden arrows collected on this board ("1/2"). Hidden when the board has none. Each collection
## pops the icon so the player sees the arrow arrive.
var _icon: GoldArrowIcon
var _label: Label
var _count := 0
var _total := 0

func _ready() -> void:
	add_theme_constant_override("separation", 4)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_CENTER
	_icon = GoldArrowIcon.new()
	_icon.custom_minimum_size = Vector2(22, 22)
	_icon.pivot_offset = Vector2(11, 11)
	add_child(_icon)
	_label = Design.label("", 16, false, 800)
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	add_child(_label)
	set_ink(Color("8A5E0E"))

func set_ink(color: Color) -> void:
	if _label != null:
		_label.add_theme_color_override("font_color", color)

func set_count(count: int, total: int, animate: bool = false) -> void:
	_count = count
	_total = total
	visible = total > 0
	if _label == null:
		return
	_label.text = "%d/%d" % [count, total]
	accessibility_name = tr("GOLD_COUNT") % [count, total]
	if animate and not SettingsManager.get_value("reduced_motion"):
		_icon.scale = Vector2(1.6, 1.6)
		var tween := _icon.create_tween()
		tween.tween_property(_icon, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Canvas position of the icon (where flying golden sparks land).
func target_point() -> Vector2:
	return _icon.get_global_transform_with_canvas() * (_icon.size * 0.5) if _icon != null else Vector2.ZERO
