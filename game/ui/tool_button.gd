class_name ToolButton
extends BaseButtonView
## Bottom-bar control: icon over a short label, with an optional corner badge (count or "AD").
var _icon_rect: TextureRect
var _label: Label
var _badge: PanelContainer
var _badge_label: Label
var _badge_icon: TextureRect

func setup(texture: Texture2D, label_key: String) -> void:
	theme_type_variation = &"SecondaryButton"
	custom_minimum_size = Vector2(96, 76)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	accessibility_name = label_key
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_bottom = -Design.LIP
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	_icon_rect = TextureRect.new()
	_icon_rect.texture = texture
	_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_rect.custom_minimum_size = Vector2(28, 28)
	_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_icon_rect)
	_label = Design.label(label_key, 16, false, 700)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(_label)
	_badge = PanelContainer.new()
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_badge.position = Vector2(-10, -8)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.add_child(row)
	_badge_icon = TextureRect.new()
	_badge_icon.texture = Widgets.icon("ad")
	_badge_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_badge_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_badge_icon.custom_minimum_size = Vector2(18, 18)
	_badge_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_badge_icon)
	_badge_label = Design.label("", 14, false, 800)
	_badge_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(_badge_label)
	add_child(_badge)
	_badge.hide()
	_apply_colors()
	Progress.theme_changed.connect(_on_theme_changed)

func _on_theme_changed(_id: String) -> void:
	_apply_colors()

## Icon-only square variant (top bar).
func compact() -> void:
	custom_minimum_size = Vector2(Design.TOUCH, Design.TOUCH)
	size_flags_horizontal = Control.SIZE_SHRINK_END
	_label.visible = false
	_icon_rect.custom_minimum_size = Vector2(30, 30)

func _apply_colors() -> void:
	var p := Palette.colors()
	_icon_rect.modulate = p["ink"]
	_label.add_theme_color_override("font_color", p["ink"])
	var style := Design.box(p["accent"], 12, 0, Color.TRANSPARENT, 4.0)
	style.content_margin_left = 8
	style.content_margin_right = 8
	_badge.add_theme_stylebox_override("panel", style)
	_badge_label.add_theme_color_override("font_color", Color.WHITE)
	_badge_icon.modulate = Color.WHITE

func set_label(key: String) -> void:
	_label.text = key

## count >= 0 shows a number; ad=true shows the ad marker (with optional text such as "+1").
func set_badge(count: int, ad: bool = false, text: String = "") -> void:
	if count < 0 and not ad:
		_badge.hide()
		return
	_badge.show()
	_badge_icon.visible = ad
	_badge_label.text = text if ad else str(count)
	_badge_label.visible = not _badge_label.text.is_empty()
	_badge.reset_size()
	_badge.position = Vector2(size.x - _badge.size.x + 6, -10)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _badge != null:
		_badge.position = Vector2(size.x - _badge.size.x + 6, -10)
