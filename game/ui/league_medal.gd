class_name LeagueMedal
extends Control
## A league tier medal: a coin in the tier color with a raised rim and an arrow emblem.
var tier := 0:
	set(value):
		tier = clampi(value, 0, LeagueRules.TOP)
		queue_redraw()
var dim := false:
	set(value):
		dim = value
		queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var r := minf(size.x, size.y) * 0.5
	var c := size * 0.5
	var base := LeagueRules.tier_color(tier)
	if dim:
		base = base.lerp(Color(0.6, 0.6, 0.6), 0.65)
	draw_circle(c + Vector2(0, r * 0.08), r * 0.98, Color(0, 0, 0, 0.18), true, -1.0, true)
	draw_circle(c, r * 0.98, base.darkened(0.28), true, -1.0, true)
	draw_circle(c, r * 0.82, base, true, -1.0, true)
	draw_arc(c, r * 0.7, PI * 1.1, PI * 1.75, 24, Color(1, 1, 1, 0.45), r * 0.08, true)
	# Emblem: a bent arrow, one more bend per tier step looks busier, so keep one shape for all.
	var w := r * 0.2
	var pts := PackedVector2Array([c + Vector2(-0.38, 0.4) * r, c + Vector2(-0.38, -0.05) * r, c + Vector2(0.12, -0.05) * r])
	var ink := Color(1, 1, 1, 0.95)
	draw_polyline(pts, ink, w, true)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0.46, -0.05) * r, c + Vector2(0.1, -0.33) * r, c + Vector2(0.1, 0.23) * r]), ink)
	if tier >= 3:
		# Platinum and diamond get a small sparkle.
		var sp := c + Vector2(0.42, -0.52) * r
		var k := r * 0.16
		draw_colored_polygon(PackedVector2Array([sp + Vector2(0, -k * 2), sp + Vector2(k * 0.5, -k * 0.5), sp + Vector2(k * 2, 0),
			sp + Vector2(k * 0.5, k * 0.5), sp + Vector2(0, k * 2), sp + Vector2(-k * 0.5, k * 0.5), sp + Vector2(-k * 2, 0),
			sp + Vector2(-k * 0.5, -k * 0.5)]), Color(1, 1, 1, 0.9))
