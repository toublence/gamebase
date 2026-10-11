class_name TownView
extends Control
## Lumen Bay as a small drawn panorama: sky, hills, shore and sea, the lighthouse on the right. Every
## cleared stage puts its piece back in its place (drawn from the stage's own silhouette, in color);
## pieces still tangled show as faint dotted outlines. After the final stage the lighthouse lamp is lit
## and sweeps a beam over the bay.
## Piece positions in the panorama (normalized), the silhouette used for its icon, its size and tint.
const LAYOUT := {
	"OBJ_SIGN": [0.06, 0.6, "", 0.07, "8A6A45"], "OBJ_LANE": [0.14, 0.62, "", 0.07, "B08A5C"],
	"OBJ_FISH": [0.12, 0.86, "fish", 0.09, "4FA3C7"], "OBJ_STAR": [0.1, 0.14, "star", 0.08, "E9B23A"],
	"OBJ_APPLE": [0.22, 0.55, "apple", 0.09, "D9534F"], "OBJ_MUSHROOM": [0.3, 0.62, "mushroom", 0.07, "C4573A"],
	"OBJ_WHALE": [0.32, 0.86, "whale", 0.14, "3E6FA8"], "OBJ_LIGHTHOUSE": [0.9, 0.46, "lighthouse", 0.16, "F4EFE6"],
	"OBJ_ANCHOR": [0.79, 0.66, "anchor", 0.07, "5B6B7A"], "OBJ_CAT": [0.62, 0.6, "cat", 0.07, "E8A25C"],
	"OBJ_SAILBOAT": [0.55, 0.82, "sailboat", 0.11, "F2F2F2"], "OBJ_HILL": [0.45, 0.42, "mountain", 0.22, "7FA56B"],
	"OBJ_TURTLE": [0.72, 0.88, "turtle", 0.08, "4E9A6A"], "OBJ_CLOUD": [0.38, 0.13, "cloud", 0.13, "FFFFFF"],
	"OBJ_LEAF": [0.69, 0.56, "leaf", 0.06, "58A55C"], "OBJ_HOUSE": [0.4, 0.6, "house", 0.1, "D8875A"],
	"OBJ_WAVE": [0.88, 0.88, "wave", 0.12, "7FC4E8"], "OBJ_TREE": [0.52, 0.56, "tree", 0.1, "3F8E4F"],
	"OBJ_BEACH": [0.82, 0.74, "pebble", 0.1, "E8D2A6"], "OBJ_HEART": [0.66, 0.16, "heart", 0.08, "E2546E"],
}

var restored := 0 # how many stages (in order) have been cleared
var lit := false

static var _masks := {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func set_progress(count: int, lamp_lit: bool) -> void:
	restored = count
	lit = lamp_lit
	queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y
	var sky: Array = Scenery.scene("harbor" if lit else "morning")["sky"]
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(w, 0), Vector2(w, h * 0.7), Vector2(0, h * 0.7)]),
		PackedColorArray([sky[0], sky[0], sky[1], sky[1]]))
	# Hills, shore, sea.
	var hill := PackedVector2Array([Vector2(0, h * 0.62)])
	for k in 13:
		var x := w * k / 12.0
		hill.append(Vector2(x, h * (0.5 + 0.06 * sin(k * 1.3))))
	hill.append(Vector2(w, h * 0.62))
	draw_colored_polygon(hill, Color("A7C99A") if not lit else Color("2C4A3A"))
	draw_rect(Rect2(0, h * 0.62, w, h * 0.1), Color("E8D9B5") if not lit else Color("4A4636"))
	draw_rect(Rect2(0, h * 0.72, w, h * 0.28), Color("8CC8E3") if not lit else Color("16304F"))
	for i in Story.PIECES.size():
		_draw_piece(Story.PIECES[i], i < restored)
	if lit:
		var lamp := Vector2(w * 0.9, h * 0.25)
		draw_polygon(PackedVector2Array([lamp, Vector2(0, h * 0.18), Vector2(0, h * 0.36)]),
			PackedColorArray([Color(Scenery.GOLD_LIGHT, 0.5), Color(Scenery.GOLD_LIGHT, 0.0), Color(Scenery.GOLD_LIGHT, 0.0)]))
		draw_circle(lamp, w * 0.012, Scenery.GOLD_LIGHT, true, -1.0, true)

func _draw_piece(key: String, done: bool) -> void:
	var spec: Array = LAYOUT[key]
	var center := Vector2(spec[0], spec[1]) * size
	var span := float(spec[3]) * size.x
	var color := Color(str(spec[4]))
	draw_icon(self, key, center, span, color if done else Color(1, 1, 1, 0.0), not done)

## Draws a piece's icon (its stage silhouette as small tiles) centered at `center`, `span` px wide.
## `ghost`: a faint dotted outline instead (still tangled).
static func draw_icon(ci: CanvasItem, key: String, center: Vector2, span: float, color: Color, ghost: bool = false) -> void:
	var spec: Array = LAYOUT[key]
	var shape := str(spec[2])
	var grid := 12
	var mask := _mask(shape, grid)
	var px := span / grid
	var origin := center - Vector2(span, span) * 0.5
	for y in grid:
		for x in grid:
			if mask[y * grid + x] == 0:
				continue
			var r := Rect2(origin + Vector2(x, y) * px, Vector2(px, px))
			if ghost:
				if (x + y) % 2 == 0:
					ci.draw_rect(r.grow(-px * 0.3), Color(0.2, 0.2, 0.25, 0.22))
			else:
				ci.draw_rect(r.grow(0.3), color)

static func _mask(shape: String, grid: int) -> PackedByteArray:
	if not _masks.has(shape):
		if shape.is_empty():
			# Signpost: a post and a sideways arrow board.
			var m := PackedByteArray()
			m.resize(grid * grid)
			for y in range(3, grid):
				m[y * grid + 5] = 1
				m[y * grid + 6] = 1
			for x in range(2, 10):
				for y in range(2, 5):
					m[y * grid + x] = 1
			m[3 * grid + 10] = 1
			_masks[shape] = m
		else:
			_masks[shape] = Silhouettes.mask(shape, grid, grid)
	return _masks[shape]
