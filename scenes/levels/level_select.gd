extends BasePage
## Stage select for the campaign (chapters of 20) and the switch challenge.
const COLUMNS := 5
var _tab := "campaign"
var _list: VBoxContainer
var _tabs: HBoxContainer

func _ready() -> void:
	super._ready()
	_tab = "campaign"
	body.add_theme_constant_override("separation", 14)
	var header := Design.row(10)
	body.add_child(header)
	header.add_child(Widgets.icon_button("back", "BACK", Nav.home))
	var title := Design.title("STAGES", 28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(title)
	_tabs = Design.row(10)
	body.add_child(_tabs)
	_list = Design.column(18)
	body.add_child(_list)
	_render()
	use_banner()

func _render() -> void:
	for child in _tabs.get_children():
		child.queue_free()
	for child in _list.get_children():
		child.queue_free()
	# Switch mode stays hidden until it is rebuilt and validated for the arrow rules.
	if true:
		for chapter in range(1, Levels.chapter_count() + 1):
			var first := (chapter - 1) * Levels.CHAPTER_SIZE + 1
			var last := mini(chapter * Levels.CHAPTER_SIZE, Levels.campaign_count())
			_list.add_child(_section(tr("CHAPTER_N") % chapter,
				tr("CHAPTER_CLEARED") % [Progress.chapter_cleared_count(chapter), last - first + 1], Levels.ID_PREFIX, first, last, Progress.reached()))

func _tab_button(tab: String, key: String, enabled: bool) -> BaseButtonView:
	var button := Design.button(key, func():
		if not enabled:
			UI.toast(tr("SWITCH_LOCKED") % Progress.SWITCH_UNLOCK_LEVEL)
			return
		_tab = tab
		Progress.levels_tab = tab
		_render(), _tab != tab)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not enabled:
		button.icon = Widgets.icon("lock")
		button.modulate = Color(1, 1, 1, 0.65)
	return button

func _section(title: String, note: String, prefix: String, first: int, last: int, reached: int) -> Control:
	var column := Design.column(10)
	var head := Design.row(8)
	column.add_child(head)
	var label := Design.label(title, 21, false, 800)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(label)
	var note_label := Design.label(note, 15, true, 650)
	note_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	note_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(note_label)
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	column.add_child(grid)
	for i in range(first, last + 1):
		grid.add_child(_tile(prefix, i, reached))
	return column

func _tile(prefix: String, number: int, reached: int) -> BaseButtonView:
	var p := Palette.colors()
	var id := "%s%03d" % [prefix, number]
	var unlocked := number <= reached
	var info := Progress.clear_info(id)
	var cleared := not info.is_empty()
	var current := unlocked and not cleared and number == reached
	var button := BaseButtonView.new()
	button.custom_minimum_size = Vector2(Design.TOUCH, Design.TOUCH + 6)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.theme_type_variation = &"PrimaryButton" if current else &"SecondaryButton"
	button.text = str(number)
	button.add_theme_font_size_override("font_size", 21)
	button.accessibility_name = tr("STAGE_N") % number
	var grade := Grades.of(Levels.campaign(number))
	if grade > 0:
		# Graded stages are dark tiles in their grade's color (no grade name), even while locked,
		# so the rising difficulty is visible ahead.
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			var style := Design.box(Grades.plate(grade), Design.RADIUS, Design.LIP, Grades.edge(grade), 6.0)
			if state == "focus":
				style.draw_center = false
				style.set_border_width_all(3)
				style.border_color = Color("FFD36B")
			button.add_theme_stylebox_override(state, style)
		for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			button.add_theme_color_override(color_name, Color("FFD36B"))
	if not unlocked:
		button.text = ""
		button.icon = Widgets.icon("lock")
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.modulate = Color(1, 1, 1, 0.72)
		button.pressed.connect(func(): UI.toast("STAGE_LOCKED"))
		return button
	button.pressed.connect(func(): Nav.play_campaign(number))
	if cleared:
		var mark := Widgets.texture("star" if bool(info.get("perfect", false)) else "check", 16,
			p["gold"] if bool(info.get("perfect", false)) else p["accent"])
		mark.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		mark.position = Vector2(-20, 4)
		button.add_child(mark)
		button.resized.connect(func(): mark.position = Vector2(button.size.x - 20, 4))
	return button
