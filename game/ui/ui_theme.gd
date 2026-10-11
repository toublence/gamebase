class_name UiTheme
extends RefCounted
## Builds the Godot Theme from the active palette. Buttons are tactile: a darker lip under the face
## that compresses when pressed, so every press visibly "clicks" down.

static func build() -> Theme:
	var p := Palette.colors()
	var theme := Theme.new()
	theme.default_font = Design.font(650)
	theme.default_font_size = 20
	_button(theme, &"Button", p["face"], p["side"], p["ink"], p["accent"])
	_button(theme, &"SecondaryButton", p["face"], p["side"], p["ink"], p["accent"])
	_button(theme, &"PrimaryButton", p["accent"], p["accent_deep"], Color.WHITE, p["accent_deep"])
	_button(theme, &"CoralButton", p["coral"], p["coral"].darkened(0.22), Color.WHITE, p["coral"].darkened(0.3))
	_button(theme, &"GhostButton", Color(p["face"], 0.0), Color(p["face"], 0.0), p["ink_soft"], p["accent"], 0)
	for variation in [&"SecondaryButton", &"PrimaryButton", &"CoralButton", &"GhostButton"]:
		theme.set_type_variation(variation, &"Button")
	theme.set_font(&"font", &"PrimaryButton", Design.font(800))
	theme.set_font(&"font", &"CoralButton", Design.font(800))
	theme.set_font_size(&"font_size", &"PrimaryButton", 22)
	# Panels
	theme.set_stylebox(&"panel", &"PanelContainer", Design.box(p["face"], 22, Design.LIP, p["side"], 20.0, 10.0))
	theme.set_type_variation(&"ModalPanel", &"PanelContainer")
	theme.set_stylebox(&"panel", &"ModalPanel", Design.box(p["face"], 28, Design.LIP, p["side"], 26.0, 18.0))
	theme.set_type_variation(&"CardPanel", &"PanelContainer")
	theme.set_stylebox(&"panel", &"CardPanel", Design.box(p["face"], 24, Design.LIP, p["side"], 20.0, 8.0))
	theme.set_type_variation(&"FlatPanel", &"PanelContainer")
	theme.set_stylebox(&"panel", &"FlatPanel", Design.box(p["bg_deep"], 18, 0, Color.TRANSPARENT, 14.0))
	# Text
	theme.set_color(&"font_color", &"Label", p["ink"])
	# Option button + popup
	var option := Design.box(p["face"], 16, 4, p["side"], 16.0)
	theme.set_stylebox(&"normal", &"OptionButton", option)
	theme.set_stylebox(&"hover", &"OptionButton", option)
	theme.set_stylebox(&"pressed", &"OptionButton", option)
	theme.set_stylebox(&"focus", &"OptionButton", _focus(p["accent"]))
	theme.set_color(&"font_color", &"OptionButton", p["ink"])
	theme.set_color(&"font_hover_color", &"OptionButton", p["ink"])
	theme.set_color(&"font_pressed_color", &"OptionButton", p["ink"])
	theme.set_stylebox(&"panel", &"PopupMenu", Design.box(p["face"], 16, 0, Color.TRANSPARENT, 10.0, 12.0))
	theme.set_stylebox(&"hover", &"PopupMenu", Design.box(p["accent_soft"], 10, 0, Color.TRANSPARENT, 8.0))
	theme.set_color(&"font_color", &"PopupMenu", p["ink"])
	theme.set_color(&"font_hover_color", &"PopupMenu", p["ink"])
	theme.set_font_size(&"font_size", &"PopupMenu", 20)
	theme.set_constant(&"v_separation", &"PopupMenu", 18)
	# Scroll bars stay slim; content scrolls by touch.
	var grabber := Design.box(Color(p["ink"], 0.18), 4, 0, Color.TRANSPARENT, 0.0)
	theme.set_stylebox(&"grabber", &"VScrollBar", grabber)
	theme.set_stylebox(&"grabber_highlight", &"VScrollBar", grabber)
	theme.set_stylebox(&"grabber_pressed", &"VScrollBar", grabber)
	theme.set_stylebox(&"scroll", &"VScrollBar", StyleBoxEmpty.new())
	# Slider
	theme.set_stylebox(&"slider", &"HSlider", Design.box(p["bg_deep"], 6, 0, Color.TRANSPARENT, 4.0))
	theme.set_stylebox(&"grabber_area", &"HSlider", Design.box(p["accent"], 6, 0, Color.TRANSPARENT, 4.0))
	theme.set_stylebox(&"grabber_area_highlight", &"HSlider", Design.box(p["accent"], 6, 0, Color.TRANSPARENT, 4.0))
	return theme

static func _button(theme: Theme, type: StringName, face: Color, lip: Color, text: Color, focus: Color, lip_size: int = Design.LIP) -> void:
	var normal := Design.box(face, Design.RADIUS, lip_size, lip, 14.0)
	normal.content_margin_left = 20
	normal.content_margin_right = 20
	var hover := normal.duplicate()
	hover.bg_color = face.lightened(0.04) if face.a > 0.0 else Color(text, 0.06)
	var pressed := normal.duplicate()
	# The face sinks into its lip: less lip below, more margin above.
	pressed.border_width_bottom = maxi(0, lip_size - 3)
	pressed.content_margin_top = normal.content_margin_top + 3
	pressed.content_margin_bottom = normal.content_margin_bottom - 3
	pressed.expand_margin_top = -3
	pressed.bg_color = face.darkened(0.04) if face.a > 0.0 else Color(text, 0.1)
	var disabled := normal.duplicate()
	disabled.bg_color = Color(face, 0.55) if face.a > 0.0 else face
	disabled.border_color = Color(lip, 0.45)
	theme.set_stylebox(&"normal", type, normal)
	theme.set_stylebox(&"hover", type, hover)
	theme.set_stylebox(&"pressed", type, pressed)
	theme.set_stylebox(&"hover_pressed", type, pressed)
	theme.set_stylebox(&"disabled", type, disabled)
	theme.set_stylebox(&"focus", type, _focus(focus))
	for state in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color", &"font_hover_pressed_color"]:
		theme.set_color(state, type, text)
	theme.set_color(&"font_disabled_color", type, Color(text, 0.45))
	theme.set_color(&"icon_normal_color", type, text)
	theme.set_color(&"icon_hover_color", type, text)
	theme.set_color(&"icon_pressed_color", type, text)
	theme.set_color(&"icon_focus_color", type, text)
	theme.set_color(&"icon_disabled_color", type, Color(text, 0.45))
	theme.set_constant(&"h_separation", type, 10)
	theme.set_constant(&"icon_max_width", type, 30)

static func _focus(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.set_border_width_all(3)
	style.border_color = Color(color, 0.7)
	style.set_corner_radius_all(Design.RADIUS + 3)
	style.expand_margin_left = 3
	style.expand_margin_right = 3
	style.expand_margin_top = 3
	style.expand_margin_bottom = 3
	style.anti_aliasing = true
	return style
