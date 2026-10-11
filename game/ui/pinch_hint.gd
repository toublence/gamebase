class_name PinchHint
extends Control
## Gesture hint for zooming: two fingertips spread apart over the board, three times, then fade.
## Shown on the first big HARD board; any zoom by the player removes it at once.
var _t := 0.0
var _running := false
const CYCLE := 1.3
const CYCLES := 3

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	visible = false

func play() -> void:
	_t = 0.0
	_running = true
	visible = true
	modulate.a = 1.0
	if SettingsManager.get_value("reduced_motion"):
		# Reduced motion: one still pose (fingers apart), shown for the same total time.
		_t = CYCLE * 0.7
		queue_redraw()
		get_tree().create_timer(CYCLE * CYCLES, false).timeout.connect(stop)
		return
	set_process(true)

func stop() -> void:
	if not _running:
		return
	_running = false
	set_process(false)
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.25)
	tween.tween_callback(func(): visible = false)

func _process(delta: float) -> void:
	_t += delta
	if _t >= CYCLE * CYCLES:
		stop()
	queue_redraw()

func _draw() -> void:
	var phase := fmod(_t, CYCLE) / CYCLE
	var spread := smoothstep(0.1, 0.75, phase)
	var alpha := 1.0 - smoothstep(0.82, 1.0, phase)
	var c := size * 0.5
	var axis := Vector2(1, -1).normalized()
	var gap := lerpf(18.0, 70.0, spread)
	for sign in [-1.0, 1.0]:
		var p: Vector2 = c + axis * gap * sign
		draw_circle(p + Vector2(0, 4), 19.0, Color(0, 0, 0, 0.18 * alpha), true, -1.0, true)
		draw_circle(p, 19.0, Color(1, 1, 1, 0.92 * alpha), true, -1.0, true)
		draw_arc(p, 19.0, 0, TAU, 32, Color(ArrowView.HINT, 0.9 * alpha), 3.0, true)
		var tip: Vector2 = p + axis * sign * 30.0
		draw_line(p + axis * sign * 22.0, tip, Color(1, 1, 1, 0.85 * alpha), 4.0, true)
		var side := Vector2(-axis.y, axis.x)
		draw_colored_polygon(PackedVector2Array([tip + axis * sign * 9.0, tip + side * 7.0, tip - side * 7.0]), Color(1, 1, 1, 0.85 * alpha))
