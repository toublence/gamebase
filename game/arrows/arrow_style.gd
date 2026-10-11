class_name ArrowStyle
extends RefCounted
## The maze look: every arrow is a thin line of one ink with a solid head, square bends and round
## joints, so neighbouring arrows read as one tangled maze and following a line is part of the
## puzzle. Head and body must never be confused, even in the overview: the body is drawn a little
## lighter (BODY_ALPHA) than the full-strength head, the head is large, and a thin cut-out in the
## board color (`halo`) separates every head from lines passing next to it. Color is kept for
## feedback only: green while an arrow escapes, red for the arrow tapped while blocked, purple for
## the arrow in its way, cyan for a hint, gold for golden arrows.
const WIDTH := 0.2 # line width in cells
const HEAD_LENGTH := 0.56
const HEAD_HALF := 0.36
const BODY_ALPHA := 0.7
const HALO := 0.09 # head cut-out width in cells
const MIN_WIDTH := 1.4 # logical px
const ESCAPE := Color("2FB868")
const BLOCKED := Color("E2543E")
const BLOCKER := Color("B57BFF")
const HINT := Color("22C7E8")

static func width(cell: float, scale: float = 1.0) -> float:
	return maxf(MIN_WIDTH, cell * WIDTH * scale)

## Cell-center polyline of a resting arrow (board pixels, origin at cell (0,0)'s corner).
static func points_of(cells: Array[Vector2i], cell: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for c in cells:
		points.append((Vector2(c) + Vector2(0.5, 0.5)) * cell)
	return points

## Draws one arrow: the line (joints filled so bends stay crisp at any width) and the head.
## `halo` (alpha > 0) cuts a thin board-colored outline around the head.
static func draw(ci: CanvasItem, points: PackedVector2Array, forward: Vector2, cell: float, color: Color, scale: float = 1.0,
		halo: Color = Color(0, 0, 0, 0)) -> void:
	if points.size() < 2:
		return
	var w := width(cell, scale)
	var body := Color(color, color.a * BODY_ALPHA)
	# The body stops at the head's base so the lighter line never shows through the head.
	var line := points.duplicate()
	line[line.size() - 1] = points[points.size() - 1] - forward * minf(cell * 0.12, w)
	ci.draw_polyline(line, body, w, true)
	if w >= 3.0:
		# Joints (hairlines skip them: invisible at that width, and big mazes draw hundreds).
		ci.draw_circle(points[0], w * 0.5, body, true, -1.0, true)
		for i in range(1, points.size() - 1):
			var a := points[i] - points[i - 1]
			var b := points[i + 1] - points[i]
			if absf(a.cross(b)) > 0.001:
				ci.draw_circle(points[i], w * 0.5, body, true, -1.0, true)
	_draw_head(ci, points, forward, cell, color, scale, w, halo)

static func head_triangle(head: Vector2, forward: Vector2, cell: float, scale: float, w: float, grow: float = 0.0) -> PackedVector2Array:
	var side := Vector2(-forward.y, forward.x)
	var half := maxf(w * 1.6, cell * HEAD_HALF * minf(scale, 1.4)) + grow
	var length := maxf(w * 2.2, cell * HEAD_LENGTH * minf(scale, 1.4)) + grow * 1.6
	var base := head - forward * (length * 0.2 + grow * 0.6)
	return PackedVector2Array([base + forward * length, base + side * half, base - side * half])

static func _draw_head(ci: CanvasItem, points: PackedVector2Array, forward: Vector2, cell: float, color: Color, scale: float, w: float,
		halo: Color) -> void:
	var head := points[points.size() - 1]
	if halo.a > 0.0:
		ci.draw_colored_polygon(head_triangle(head, forward, cell, scale, w, maxf(1.0, cell * HALO)), halo)
	ci.draw_colored_polygon(head_triangle(head, forward, cell, scale, w), color)

## A soft wide underlay (hint glow, golden halo).
static func draw_glow(ci: CanvasItem, points: PackedVector2Array, cell: float, color: Color) -> void:
	if points.size() >= 2:
		ci.draw_polyline(points, color, cell * 0.62, true)
