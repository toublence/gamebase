class_name MiniBoard
extends Control
## Static picture of an "arrow-path-2" level (home card, style picker). One _draw, no child nodes.
## Draws the level's silhouette when it has one, in the colors of `scene_id` and the arrow skin.
var level: Dictionary = {}
var scene_id := ""
var skin_id := ""
var _board: ArrowBoard
var _mask := PackedByteArray()

func set_level(data: Dictionary) -> void:
	level = data
	_board = ArrowBoard.from_level(data) if not data.is_empty() and data.has("a") else null
	_mask = PackedByteArray()
	var text := str(data.get("mask", ""))
	if _board != null and text.length() == _board.width * _board.height:
		_mask.resize(text.length())
		for i in text.length():
			_mask[i] = 1 if text[i] == "1" else 0
	queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	if _board == null:
		return
	var scene := Scenery.scene(scene_id if not scene_id.is_empty() else Scenery.for_level(level))
	var inks := Scenery.inks(str(scene["id"]), skin_id)
	var cell := floorf(minf(size.x / (_board.width + 0.6), size.y / (_board.height + 0.6)) * 4.0) / 4.0
	var grid := Vector2(_board.width, _board.height) * cell
	var pad := cell * 0.3
	var panel := Rect2((size - grid) * 0.5 - Vector2(pad, pad), grid + Vector2(pad, pad) * 2.0)
	var origin := panel.position + Vector2(pad, pad)
	# The picture sits on a soft card so it reads on any backdrop.
	draw_style_box(Design.box(Color(scene["board"], 0.85), int(maxf(8.0, cell)), 0, Color.TRANSPARENT, 0.0), panel.grow(minf(cell * 0.6, 14.0)))
	var gold := {}
	for id in level.get("gold", []):
		gold[int(id)] = true
	var color_mode: bool = SettingsManager.get_value("arrow_colors") == true
	var ink := Scenery.ink(str(scene["id"]), skin_id)
	for id in _board.live_ids():
		var points := PackedVector2Array()
		for c in _board.cells_of(id):
			points.append(origin + (Vector2(c) + Vector2(0.5, 0.5)) * cell)
		var color: Color = Scenery.GOLD if gold.has(id) else (inks[id % inks.size()] if color_mode else ink)
		ArrowStyle.draw(self, points, Vector2(Dir.vec(_board.dirs[id])), cell, color, 1.1)
