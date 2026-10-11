class_name SafeArea
extends MarginContainer
signal insets_changed
@export var padding_units := 2.5
## Extra bottom space in logical units (e.g. an anchored banner drawn by the native layer).
var extra_bottom := 0.0:
	set(value):
		if not is_equal_approx(extra_bottom, value):
			extra_bottom = value
			_update_insets()

func _ready() -> void:
	get_viewport().size_changed.connect(_update_insets)
	AppManager.foregrounded.connect(_update_insets)
	_update_insets.call_deferred()

## Physical safe-area insets converted to logical units (left, top, right, bottom).
static func logical_insets(viewport: Viewport) -> Vector4:
	var insets := Vector4.ZERO
	if OS.get_name() in ["Android", "iOS"] and DisplayServer.get_name() != "headless":
		var safe := Rect2(DisplayServer.get_display_safe_area())
		var window := Vector2(DisplayServer.window_get_size())
		if safe.has_area() and window.x > 0 and window.y > 0:
			var ratio := viewport.get_visible_rect().size / window
			insets = Vector4(maxf(0, safe.position.x) * ratio.x, maxf(0, safe.position.y) * ratio.y,
				maxf(0, window.x - safe.end.x) * ratio.x, maxf(0, window.y - safe.end.y) * ratio.y)
	return insets

func _update_insets() -> void:
	if not is_inside_tree():
		return
	var insets := Vector4.ZERO
	if OS.get_name() in ["Android", "iOS"] and DisplayServer.get_name() != "headless":
		var safe := Rect2(DisplayServer.get_display_safe_area())
		var window := Vector2(DisplayServer.window_get_size())
		if safe.has_area() and window.x > 0 and window.y > 0:
			var ratio := get_viewport_rect().size / window
			insets = Vector4(maxf(0, safe.position.x) * ratio.x,
				maxf(0, safe.position.y) * ratio.y,
				maxf(0, window.x - safe.end.x) * ratio.x,
				maxf(0, window.y - safe.end.y) * ratio.y)
	var gap := int(padding_units * Design.UNIT)
	add_theme_constant_override("margin_left", gap + ceili(insets.x))
	add_theme_constant_override("margin_top", gap + ceili(insets.y))
	add_theme_constant_override("margin_right", gap + ceili(insets.z))
	add_theme_constant_override("margin_bottom", gap + ceili(insets.w) + ceili(extra_bottom))
	insets_changed.emit()
