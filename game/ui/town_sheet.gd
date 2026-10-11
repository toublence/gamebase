class_name TownSheet
extends ModalView
## Lumen Bay: the panorama with every piece won back so far, the chapter's progress, a list of the
## pieces (still-tangled ones show only their stage number) and the chapter's opening story.

func _ready() -> void:
	super._ready()
	var count := Progress.restored_count()
	var total := Story.PIECES.size()
	body.add_child(Design.title("TOWN_TITLE", 28))
	body.add_child(Design.label("STORY_CHAPTER1", 15, true, 650))
	var view := TownView.new()
	view.custom_minimum_size = Vector2(0, 220)
	view.set_progress(count, count >= total)
	body.add_child(view)
	var progress := Design.label(tr("TOWN_PROGRESS") % [count, total], 17, false, 800)
	progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(progress)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	body.add_child(grid)
	for i in total:
		grid.add_child(_tile(i, i < count))
	body.add_child(Design.button("STORY_READ", func(): StoryCard.show_beat("intro"), true))
	body.add_child(Design.button("CLOSE", close))

func _tile(i: int, done: bool) -> Control:
	var p := Palette.colors()
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", Design.box(Color(p["face"], 0.9) if done else Color(p["muted"], 0.12), 12, 0, Color.TRANSPARENT, 6.0))
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := Design.column(2)
	box.add_child(column)
	var icon := PieceIcon.new()
	icon.key = Story.piece(i + 1)
	icon.done = done
	icon.custom_minimum_size = Vector2(0, 44)
	column.add_child(icon)
	var name := Design.label(Story.piece(i + 1) if done else tr("STAGE_N") % (i + 1), 12, not done, 700)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(name)
	return box

## One piece icon (used by the town list and the clear card).
class PieceIcon:
	extends Control
	var key := ""
	var done := true

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var spec: Array = TownView.LAYOUT.get(key, [0, 0, "", 0.1, "888888"])
		var color := Color(str(spec[4]))
		if color.get_luminance() > 0.85:
			color = color.darkened(0.25)
		TownView.draw_icon(self, key, size * 0.5, minf(size.x, size.y) * 0.9, color, not done)
