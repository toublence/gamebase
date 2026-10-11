class_name ArrowView
extends Node2D
## One arrow in motion (escaping or bumping), drawn in the maze style. Its shape is a window
## [s, s + length - 1] on a track of cells (its own cells tail → head, then straight on past the
## edge). Moving `s` forward slides the whole body along the path it already occupies, head first:
## exactly the path-following escape the rules describe. Resting arrows are drawn by ArrowCanvas;
## this node exists only while an arrow moves. Pure presentation.
const HINT := ArrowStyle.HINT

var id := -1
var cell := 48.0
var color := Color.BLACK
var track: Array[Vector2i] = []
var length := 2
var head_dir := 0
var moving := true

## Position along the track in cells (0 = resting on its own cells).
var s := 0.0:
	set(value):
		s = value
		queue_redraw()

func setup(arrow_id: int, cells: Array[Vector2i], dir: int, cell_size: float, ink: Color) -> void:
	id = arrow_id
	track = cells.duplicate()
	length = cells.size()
	head_dir = dir
	cell = cell_size
	color = ink
	queue_redraw()

func extend_track(cells: Array[Vector2i]) -> void:
	track = cells.duplicate()
	queue_redraw()

func set_cell_size(size: float) -> void:
	cell = size
	queue_redraw()

func set_color(ink: Color) -> void:
	color = ink
	queue_redraw()

## Point on the track at a fractional index, in local pixels (cell centers).
func _at(t: float) -> Vector2:
	var i := clampi(int(floor(t)), 0, track.size() - 1)
	var j := mini(i + 1, track.size() - 1)
	var f := clampf(t - floor(t), 0.0, 1.0)
	var a := (Vector2(track[i]) + Vector2(0.5, 0.5)) * cell
	var b := (Vector2(track[j]) + Vector2(0.5, 0.5)) * cell
	return a.lerp(b, f)

func window_points() -> PackedVector2Array:
	var tail := s
	var head := s + length - 1
	var points := PackedVector2Array([_at(tail)])
	for k in range(int(floor(tail)) + 1, int(ceil(head))):
		points.append(_at(k))
	var head_point := _at(head)
	if points[points.size() - 1].distance_squared_to(head_point) > 0.01:
		points.append(head_point)
	return points

func _draw() -> void:
	if track.size() < 2:
		return
	var points := window_points()
	if points.size() < 2:
		points.insert(0, points[0] - Vector2(Dir.vec(head_dir)) * 0.01)
	ArrowStyle.draw(self, points, Vector2(Dir.vec(head_dir)), cell, color, 1.15)

## Kept for older callers; motion arrows are always drawn in their feedback color.
static func _round_corners(points: PackedVector2Array, _radius: float) -> PackedVector2Array:
	return points
