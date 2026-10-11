class_name GoldArrowIcon
extends Control
## A small bent golden arrow drawn with the same tube look as the board's golden arrows.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	var points := PackedVector2Array([o + Vector2(0.2, 0.82) * s, o + Vector2(0.2, 0.42) * s, o + Vector2(0.62, 0.42) * s])
	var width := s * 0.2
	draw_polyline(points, Color(0, 0, 0, 0.18), width, true)
	draw_polyline(points, Scenery.GOLD, width, true)
	var shine := PackedVector2Array([points[0] + Vector2(-width * 0.12, -width * 0.1), points[1] + Vector2(-width * 0.12, -width * 0.16),
		points[2] + Vector2(-width * 0.5, -width * 0.16)])
	draw_polyline(shine, Color(Scenery.GOLD_LIGHT, 0.85), width * 0.28, true)
	var tip := o + Vector2(0.9, 0.42) * s
	draw_colored_polygon(PackedVector2Array([tip, o + Vector2(0.58, 0.18) * s, o + Vector2(0.58, 0.66) * s]), Scenery.GOLD)
	draw_circle(points[0], width * 0.5, Scenery.GOLD, true, -1.0, true)
