class_name ThemePicker
extends ModalView
## "Style": which scene sits behind the board (Auto follows each stage) and which arrow colors are
## used. Locked entries say exactly what unlocks them (a stage clear for scenes, a league tier for
## arrow colors).
const SAMPLE := ["0,3:UUUR", "1,2:RR", "3,0:D", "1,3:RR"]

func _ready() -> void:
	super._ready()
	body.add_child(Design.title("STYLE", 28))
	body.add_child(Design.label("STYLE_SCENES", 18, false, 800))
	var scenes := GridContainer.new()
	scenes.columns = 2
	scenes.add_theme_constant_override("h_separation", 12)
	scenes.add_theme_constant_override("v_separation", 12)
	body.add_child(scenes)
	scenes.add_child(_scene_card(Scenery.AUTO))
	for scene_id in Scenery.ORDER:
		scenes.add_child(_scene_card(scene_id))
	body.add_child(Design.label("STYLE_ARROWS", 18, false, 800))
	var skins := GridContainer.new()
	skins.columns = 2
	skins.add_theme_constant_override("h_separation", 12)
	skins.add_theme_constant_override("v_separation", 12)
	body.add_child(skins)
	for skin_id in Scenery.SKIN_ORDER:
		skins.add_child(_skin_card(skin_id))
	body.add_child(Design.button("DONE", close))

func _card(selected: bool) -> BaseButtonView:
	var p := Palette.colors()
	var button := BaseButtonView.new()
	button.theme_type_variation = &"SecondaryButton"
	button.custom_minimum_size = Vector2(0, 156)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var normal := Design.box(p["face"], Design.RADIUS, Design.LIP, p["side"], 10.0)
	if selected:
		normal.border_width_left = 3
		normal.border_width_top = 3
		normal.border_width_right = 3
		normal.border_color = p["accent"]
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", normal)
	return button

func _column(button: Control) -> VBoxContainer:
	var column := Design.column(4)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 10
	column.offset_right = -10
	column.offset_top = 8
	column.offset_bottom = -12
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(column)
	return column

func _scene_card(scene_id: String) -> BaseButtonView:
	var auto := scene_id == Scenery.AUTO
	var unlocked := auto or Progress.has_scene(scene_id)
	var selected := Progress.scene_choice() == scene_id
	var button := _card(selected)
	var name_key: String = "SCENE_AUTO" if auto else Scenery.SCENES[scene_id]["name"]
	button.accessibility_name = name_key
	var column := _column(button)
	var preview := ScenePreview.new()
	preview.scenes = Scenery.ORDER.duplicate() if auto else [scene_id]
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(preview)
	var name := Design.label(name_key, 16, false, 800)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(name)
	var note_key := ""
	if not unlocked:
		preview.modulate = Color(1, 1, 1, 0.35)
		note_key = tr("SCENE_LOCKED") % Scenery.UNLOCK[scene_id]
		button.pressed.connect(func(): UI.toast(tr("SCENE_LOCKED") % Scenery.UNLOCK[scene_id]))
	elif selected:
		note_key = "THEME_IN_USE"
	else:
		note_key = "SCENE_AUTO_NOTE" if auto else ""
		button.pressed.connect(func():
			Progress.set_scene_choice(scene_id)
			AnalyticsService.track(&"scene_selected", {"scene": scene_id})
			close())
	if not note_key.is_empty():
		var note := Design.label(note_key, 13, true, 650)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(note)
	return button

func _skin_card(skin_id: String) -> BaseButtonView:
	var unlocked := Progress.has_skin(skin_id)
	var selected := Progress.skin() == skin_id
	var button := _card(selected)
	button.accessibility_name = Scenery.SKINS[skin_id]["name"]
	var column := _column(button)
	var preview := MiniBoard.new()
	preview.scene_id = "morning"
	preview.skin_id = skin_id
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.set_level(ArrowLevel.parse_authoring(4, 4, PackedStringArray(SAMPLE)))
	column.add_child(preview)
	var name := Design.label(Scenery.SKINS[skin_id]["name"], 16, false, 800)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(name)
	var tier := int(Scenery.SKINS[skin_id]["tier"])
	if not unlocked:
		preview.modulate = Color(1, 1, 1, 0.35)
		var note := Design.label(tr("SKIN_LOCKED") % tr(LeagueRules.tier_name(tier)), 13, true, 650)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(note)
		button.pressed.connect(func(): UI.toast(tr("SKIN_LOCKED") % tr(LeagueRules.tier_name(tier))))
	elif selected:
		var note := Design.label("THEME_IN_USE", 13, false, 750)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note.add_theme_color_override("font_color", Palette.c("accent_deep"))
		column.add_child(note)
	else:
		button.pressed.connect(func():
			Progress.set_skin(skin_id)
			AnalyticsService.track(&"skin_selected", {"skin": skin_id})
			close())
	return button

## A still of one or more scenes' skies with a tiny board on top.
class ScenePreview:
	extends Control
	var scenes: Array = ["morning"]

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)
		clip_contents = true

	func _draw() -> void:
		var band := size.x / scenes.size()
		for i in scenes.size():
			var s := Scenery.scene(str(scenes[i]))
			var sky: Array = s["sky"]
			var x0 := band * i
			var x1 := band * (i + 1)
			draw_polygon(PackedVector2Array([Vector2(x0, 0), Vector2(x1, 0), Vector2(x1, size.y), Vector2(x0, size.y)]),
				PackedColorArray([sky[0], sky[0], sky[2], sky[2]]))
			var panel := Rect2(Vector2(x0 + band * 0.22, size.y * 0.22), Vector2(band * 0.56, size.y * 0.56))
			draw_style_box(Design.box(s["board"], 8, 0, Color.TRANSPARENT, 0.0), panel)
			var inks := Scenery.inks(str(scenes[i]))
			var c := panel.get_center()
			var r := minf(panel.size.x, panel.size.y)
			draw_polyline(PackedVector2Array([c + Vector2(-0.3, 0.25) * r, c + Vector2(-0.3, -0.15) * r, c + Vector2(0.1, -0.15) * r]),
				inks[0], r * 0.12, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0.3, -0.15) * r, c + Vector2(0.1, -0.29) * r, c + Vector2(0.1, -0.01) * r]), inks[0])
			draw_line(c + Vector2(-0.05, 0.25) * r, c + Vector2(0.2, 0.25) * r, inks[1], r * 0.12, true)
