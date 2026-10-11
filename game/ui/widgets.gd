class_name Widgets
extends RefCounted
## Small reusable pieces for Outtap screens.
const ICONS := {
	"pause": preload("res://assets/icons/pause.svg"), "hint": preload("res://assets/icons/hint.svg"),
	"undo": preload("res://assets/icons/undo.svg"), "restart": preload("res://assets/icons/restart.svg"),
	"home": preload("res://assets/icons/home.svg"), "settings": preload("res://assets/icons/settings.svg"),
	"theme": preload("res://assets/icons/theme.svg"), "lock": preload("res://assets/icons/lock.svg"),
	"check": preload("res://assets/icons/check.svg"), "play": preload("res://assets/icons/play.svg"),
	"calendar": preload("res://assets/icons/calendar.svg"), "grid": preload("res://assets/icons/grid.svg"),
	"switch": preload("res://assets/icons/switch.svg"), "heart": preload("res://assets/icons/heart.svg"),
	"heart_empty": preload("res://assets/icons/heart_empty.svg"), "close": preload("res://assets/icons/close.svg"),
	"back": preload("res://assets/icons/back.svg"), "star": preload("res://assets/icons/star.svg"),
	"ad": preload("res://assets/icons/ad.svg"), "info": preload("res://assets/icons/info.svg"),
	"chart": preload("res://assets/icons/chart.svg"), "zoom": preload("res://assets/icons/zoom.svg"),
	"fit": preload("res://assets/icons/fit.svg"), "flag": preload("res://assets/icons/flag.svg"),
}

static func icon(name: String) -> Texture2D:
	return ICONS[name]

## Square icon button with an accessible name.
static func icon_button(name: String, accessible_key: String, callback: Callable, variation: StringName = &"SecondaryButton") -> BaseButtonView:
	var button := BaseButtonView.new()
	button.icon = icon(name)
	button.theme_type_variation = variation
	button.tooltip_text = accessible_key
	button.accessibility_name = accessible_key
	button.custom_minimum_size = Vector2(Design.TOUCH, Design.TOUCH)
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.expand_icon = false
	button.add_theme_constant_override("icon_max_width", 30)
	button.pressed.connect(callback)
	return button

## Icon + label button; `badge` shows a small count or "AD" marker in the corner.
static func tool_button(name: String, label_key: String, callback: Callable) -> ToolButton:
	var button := ToolButton.new()
	button.setup(icon(name), label_key)
	button.pressed.connect(callback)
	return button

static func pill(text: String, color: Color, text_color: Color, size: int = 16) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := Design.box(color, 14, 0, Color.TRANSPARENT, 6.0)
	style.content_margin_left = 12
	style.content_margin_right = 12
	panel.add_theme_stylebox_override("panel", style)
	var label := Design.label(text, size, false, 750)
	label.add_theme_color_override("font_color", text_color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	panel.add_child(label)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return panel

static func texture(name: String, size: float, color: Color) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = icon(name)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(size, size)
	rect.modulate = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

static func centered(node: Control) -> CenterContainer:
	var center := CenterContainer.new()
	center.add_child(node)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return center
