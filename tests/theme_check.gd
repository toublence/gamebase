extends Node
func _ready() -> void:
	await get_tree().process_frame
	var b := Widgets.icon_button("pause", "PAUSE", func(): pass)
	add_child(b)
	var p := Design.button("NEXT_STAGE", func(): pass)
	p.icon = Widgets.icon("play")
	add_child(p)
	await get_tree().process_frame
	print("secondary icon color ", b.get_theme_color("icon_normal_color"), " max ", b.get_theme_constant("icon_max_width"), " var ", b.theme_type_variation)
	print("primary icon color ", p.get_theme_color("icon_normal_color"), " max ", p.get_theme_constant("icon_max_width"), " font ", p.get_theme_color("font_color"))
	print("root theme set ", get_tree().root.theme != null, " has variation ", get_tree().root.theme.get_type_variation_base(&"SecondaryButton"))
	print("theme icon color direct ", get_tree().root.theme.get_color(&"icon_normal_color", &"SecondaryButton"))
	print("icon size ", Widgets.icon("pause").get_size())
	get_tree().quit()
