class_name ResultWidgets
extends RefCounted
## Pieces of the clear sheet: the star rating that fills in one star at a time, a score that counts
## up, the path of the next stages (grades in their colors) and the lantern of the daily streak.

## Stars earned on a board: 3, minus one for any mistake (or a continue), minus one for any hint.
static func stars_for(session: ArrowSession) -> int:
	var stars := 3
	if session.mistakes > 0 or session.continues_used > 0:
		stars -= 1
	if session.hints_used > 0:
		stars -= 1
	return maxi(1, stars)

## Score: 10 per arrow, a bonus per star, and a speed bonus against the board's estimated solve time.
static func score_for(session: ArrowSession, stars: int) -> int:
	var arrows := session.board.size()
	var seconds := session.active_ms / 1000.0
	var par := float(session.level.get("m", {}).get("est_seconds", arrows * 1.5)) * 1.5
	var speed := clampi(int((par - seconds) * 3.0), 0, arrows * 5)
	return arrows * 10 + stars * arrows * 3 + speed

class Stars:
	extends Control
	var count := 3
	var _fill := [0.0, 0.0, 0.0]

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, 74)

	func play() -> void:
		if SettingsManager.get_value("reduced_motion"):
			for i in count:
				_fill[i] = 1.0
			queue_redraw()
			return
		var tween := create_tween()
		for i in count:
			tween.tween_interval(0.12)
			tween.tween_method(func(v: float):
				_fill[i] = v
				queue_redraw(), 0.0, 1.0, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tween.tween_callback(func(): Feel.star(i))

	func _draw() -> void:
		var spacing := 70.0
		var start := size.x * 0.5 - spacing
		for i in 3:
			var big := 1.25 if i == 1 else 1.0
			var c := Vector2(start + spacing * i, size.y * 0.5 + (0.0 if i == 1 else 6.0))
			var r := 26.0 * big
			_star(c, r, Color(0.55, 0.5, 0.45, 0.25))
			if _fill[i] > 0.0:
				_star(c, r * _fill[i], Scenery.GOLD)
				_star(c + Vector2(-r * 0.12, -r * 0.14) * _fill[i], r * 0.45 * _fill[i], Scenery.GOLD_LIGHT)

	func _star(c: Vector2, r: float, color: Color) -> void:
		var pts := PackedVector2Array()
		for k in 10:
			var a := -PI / 2.0 + k * PI / 5.0
			pts.append(c + Vector2.from_angle(a) * (r if k % 2 == 0 else r * 0.45))
		draw_colored_polygon(pts, color)

## A number that counts up from 0 (or appears at once with reduced motion).
class CountUp:
	extends Label
	var target := 0

	func play() -> void:
		if SettingsManager.get_value("reduced_motion"):
			text = str(target)
			return
		var tween := create_tween()
		tween.tween_method(func(v: float): text = str(int(v)), 0.0, float(target), 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## The next stages as a row of dots: the cleared one checked, the rest numbered in their grade color,
## milestones ringed in gold.
class Path:
	extends Control
	var from_index := 1

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, 46)

	func _draw() -> void:
		var last := mini(Levels.campaign_count(), from_index + 4)
		var n := last - from_index + 1
		if n <= 0:
			return
		var gap := minf(64.0, (size.x - 40.0) / maxf(1.0, n - 1))
		var start := size.x * 0.5 - gap * (n - 1) * 0.5
		var y := size.y * 0.5
		draw_line(Vector2(start, y), Vector2(start + gap * (n - 1), y), Color(0.55, 0.5, 0.45, 0.35), 3.0, true)
		var font := Design.font(800)
		for k in n:
			var index := from_index + k
			var level := Levels.campaign(index)
			var grade := Grades.of(level)
			var c := Vector2(start + gap * k, y)
			var fill: Color = Palette.c("accent") if grade == 0 else Grades.plate(grade)
			if bool(level.get("hard", false)):
				draw_circle(c, 19.0, Scenery.GOLD, true, -1.0, true)
			draw_circle(c, 16.0 if k > 0 else 18.0, fill, true, -1.0, true)
			var label := "✓" if k == 0 else str(index)
			var fs := 15
			var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, c + Vector2(-tw * 0.5, fs * 0.36), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				Grades.INK if grade > 0 else Color.WHITE)

## One day of the week on the streak card: a lit flame dot or an empty ring.
class Dot:
	extends Control
	var lit := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(22, 22)

	func _draw() -> void:
		var c := size * 0.5
		if lit:
			draw_circle(c, 9.0, Scenery.GOLD, true, -1.0, true)
			draw_circle(c, 4.0, Scenery.GOLD_LIGHT, true, -1.0, true)
		else:
			draw_arc(c, 8.0, 0.0, TAU, 24, Color(0.55, 0.5, 0.45, 0.45), 2.0, true)

## The daily-streak lantern: a small lamp whose flame grows with the streak.
class Lantern:
	extends Control
	var count := 1

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(110, 110)

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		for k in 5:
			draw_circle(c, r * (1.0 - k * 0.14), Color(Scenery.GOLD_LIGHT, 0.06 + k * 0.04), true, -1.0, true)
		var body := Rect2(c + Vector2(-r * 0.32, -r * 0.42), Vector2(r * 0.64, r * 0.84))
		draw_style_box(Design.box(Color("2C4475"), int(r * 0.16), 0, Color.TRANSPARENT, 0.0), body)
		draw_style_box(Design.box(Color("FFF4D6"), int(r * 0.12), 0, Color.TRANSPARENT, 0.0), body.grow(-r * 0.08))
		var flame := minf(1.0, 0.45 + count * 0.08)
		var base := c + Vector2(0, r * 0.22)
		draw_colored_polygon(PackedVector2Array([base + Vector2(-r * 0.16, 0), base + Vector2(0, -r * 0.62 * flame),
			base + Vector2(r * 0.16, 0)]), Color("F29A2E"))
		draw_circle(base + Vector2(0, -r * 0.05), r * 0.13, Scenery.GOLD, true, -1.0, true)
		draw_rect(Rect2(c + Vector2(-r * 0.2, -r * 0.52), Vector2(r * 0.4, r * 0.1)), Color("2C4475"))
