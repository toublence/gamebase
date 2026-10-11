class_name Backdrop
extends Control
## Animated scene behind a screen. Everything is drawn procedurally (no image assets): a soft
## vertical sky plus slow decorations that never compete with the board — a morning sun, drifting
## clouds and motes; a low sun and flowing ribbons at sunset; twinkling stars, a moon, a sweeping
## lighthouse beam and water glints at night.
##
## Cost control: decorations redraw at ~30 fps only while visible. Reduced motion draws one still
## frame. If the device cannot keep up (frames slower than 1/40 s for about three seconds), the
## backdrop switches to the still frame by itself and logs it, so play never stutters for it.
const FPS := 30.0
const SLOW_FRAME := 1.0 / 40.0
const SLOW_LIMIT := 90

var scene_id := "morning"
## Calm: sky only, no decorations or motion (behind the puzzle, where nothing should compete with
## the maze).
var calm := false
var _from_id := ""
var _blend := 1.0
var _time := 0.0
var _since_draw := 0.0
var _slow_frames := 0
var _fallback := false
var _stars: Array = [] # [x, y, size, speed, phase] in unit coordinates
var _motes: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var rng := Prng.new(0xBAC0D)
	for i in 46:
		_stars.append([rng.next_float(), rng.next_float() * 0.78, 0.8 + rng.next_float() * 1.6, 0.6 + rng.next_float() * 1.6, rng.next_float() * TAU])
	for i in 14:
		_motes.append([rng.next_float(), rng.next_float(), 1.2 + rng.next_float() * 1.8, 6.0 + rng.next_float() * 10.0, rng.next_float() * TAU])
	resized.connect(queue_redraw)
	SettingsManager.changed.connect(_on_setting)

func _on_setting(key: String, _value: Variant) -> void:
	if key == "reduced_motion":
		queue_redraw()

func set_scene(id: String, animated: bool = true) -> void:
	if id == scene_id or not Scenery.SCENES.has(id):
		return
	if animated and is_visible_in_tree() and not _still():
		_from_id = scene_id
		_blend = 0.0
		var tween := create_tween()
		tween.tween_property(self, "_blend", 1.0, 0.8).set_trans(Tween.TRANS_SINE)
		tween.tween_callback(func(): _from_id = "")
	scene_id = id
	queue_redraw()

func is_dark() -> bool:
	return bool(Scenery.scene(scene_id)["dark"])

func _still() -> bool:
	return calm or _fallback or bool(SettingsManager.get_value("reduced_motion"))

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if _still() and _from_id.is_empty():
		return
	_time += delta
	_since_draw += delta
	if not _fallback:
		_slow_frames = _slow_frames + 1 if delta > SLOW_FRAME else 0
		if _slow_frames > SLOW_LIMIT:
			_fallback = true
			Diagnostics.log_event("perf", "backdrop_static", {"reason": "slow_frames", "delta_ms": int(delta * 1000.0)})
	if _since_draw >= 1.0 / FPS or not _from_id.is_empty():
		_since_draw = 0.0
		queue_redraw()

func _draw() -> void:
	var t := 0.0 if _still() else _time
	if not _from_id.is_empty() and _blend < 1.0:
		_draw_scene(_from_id, t, 1.0)
		_draw_scene(scene_id, t, _blend)
	else:
		_draw_scene(scene_id, t, 1.0)

func _draw_scene(id: String, t: float, alpha: float) -> void:
	var s := Scenery.scene(id)
	_draw_sky(s["sky"], alpha)
	if calm:
		return
	match id:
		"morning": _draw_morning(s, t, alpha)
		"sunset": _draw_sunset(s, t, alpha)
		"harbor": _draw_harbor(s, t, alpha)

func _draw_sky(sky: Array, alpha: float) -> void:
	var w := size.x
	var h := size.y
	var top: Color = sky[0]
	var mid: Color = sky[1]
	var bottom: Color = sky[2]
	top.a *= alpha
	mid.a *= alpha
	bottom.a *= alpha
	var m := h * 0.5
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, m), Vector2(0, m)]),
		PackedColorArray([top, top, mid, mid]))
	draw_polygon(PackedVector2Array([Vector2(0, m), Vector2(w, m), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([mid, mid, bottom, bottom]))

func _glow(center: Vector2, radius: float, color: Color, strength: float, rings: int = 7) -> void:
	for i in rings:
		var k := float(rings - i) / rings
		draw_circle(center, radius * (0.45 + k * 1.1), Color(color, strength * (1.0 - k) * 0.5 + 0.02), true, -1.0, true)

func _draw_morning(s: Dictionary, t: float, alpha: float) -> void:
	var w := size.x
	var h := size.y
	var sun := Vector2(w * 0.84, h * 0.1)
	_glow(sun, w * 0.3, s["glow"], 0.55 * alpha)
	var sun_core: Color = s["glow"]
	draw_circle(sun, w * 0.075, Color(sun_core.lightened(0.3), 0.9 * alpha), true, -1.0, true)
	var sky_mid: Color = s["sky"][1]
	var cloud := sky_mid.lerp(s["deco"], 0.72)
	cloud.a = 0.92 * alpha
	for k in 3:
		var r := w * (0.07 + 0.02 * k)
		var y: float = h * float([0.075, 0.2, 0.9][k])
		var span := w + r * 6.0
		var x: float = fposmod(w * float([0.1, 0.62, 0.35][k]) + t * (5.0 + 2.5 * k), span) - r * 3.0
		_cloud(Vector2(x, y), r, cloud)
	var glow: Color = s["glow"]
	var mote := Color(glow, 0.5 * alpha)
	for m in _motes:
		var y := h - fposmod(float(m[1]) * h + t * float(m[3]), h + 20.0)
		var x := float(m[0]) * w + sin(t * 0.5 + float(m[4])) * 8.0
		draw_circle(Vector2(x, y), float(m[2]), mote, true, -1.0, true)

func _cloud(at: Vector2, r: float, color: Color) -> void:
	for puff in [[0.0, 0.0, 1.0], [0.95, -0.35, 0.82], [1.8, 0.05, 0.7], [-0.85, 0.12, 0.62]]:
		draw_circle(at + Vector2(puff[0], puff[1]) * r, r * float(puff[2]), color, true, -1.0, true)
	draw_rect(Rect2(at + Vector2(-0.85 * r, 0.0), Vector2(2.65 * r, r * 0.62)), color)

func _draw_sunset(s: Dictionary, t: float, alpha: float) -> void:
	var w := size.x
	var h := size.y
	var sun := Vector2(w * 0.2, h * 0.16)
	_glow(sun, w * 0.42, s["glow"], 0.6 * alpha)
	draw_circle(sun, w * 0.12, Color(s["glow"], 0.85 * alpha), true, -1.0, true)
	for i in 5:
		var base_y := h * (0.66 + i * 0.065)
		var amp := 9.0 + i * 3.0
		var phase := t * (0.22 + i * 0.05) + i * 1.3
		var points := PackedVector2Array()
		for k in 25:
			var x := w * (k / 24.0) * 1.1 - w * 0.05
			points.append(Vector2(x, base_y + sin(x / w * TAU * 1.2 + phase) * amp))
		var color: Color = s["deco"].lerp(s["sky"][2], i / 5.0)
		color.a = (0.22 - i * 0.025) * alpha
		draw_polyline(points, color, 26.0 + i * 6.0, true)

func _draw_harbor(s: Dictionary, t: float, alpha: float) -> void:
	var w := size.x
	var h := size.y
	for star in _stars:
		var twinkle := 0.5 + 0.5 * sin(t * float(star[3]) + float(star[4]))
		draw_circle(Vector2(float(star[0]) * w, float(star[1]) * h), float(star[2]),
			Color(1, 1, 1, (0.25 + 0.6 * twinkle) * alpha), true, -1.0, true)
	var moon := Vector2(w * 0.2, h * 0.1)
	_glow(moon, w * 0.16, s["glow"], 0.35 * alpha)
	draw_circle(moon, w * 0.05, Color(s["glow"], 0.95 * alpha), true, -1.0, true)
	var shade: Color = s["sky"][0]
	draw_circle(moon + Vector2(w * 0.018, -w * 0.012), w * 0.043, Color(shade, 0.55 * alpha), true, -1.0, true)
	# Lighthouse on the right edge with a slowly sweeping beam.
	var base := Vector2(w * 0.93, h * 0.9)
	var sky_top: Color = s["sky"][0]
	var tower := Color(sky_top.darkened(0.3), alpha)
	draw_colored_polygon(PackedVector2Array([base + Vector2(-9, 0), base + Vector2(9, 0), base + Vector2(5, -54), base + Vector2(-5, -54)]), tower)
	var lamp := base + Vector2(0, -60)
	draw_circle(lamp, 6.0, Color(s["deco"], 0.95 * alpha), true, -1.0, true)
	var angle := deg_to_rad(-158.0 + sin(t * 0.33) * 22.0)
	var reach := w * 1.5
	var a := lamp + Vector2.from_angle(angle - 0.07) * reach
	var b := lamp + Vector2.from_angle(angle + 0.07) * reach
	draw_polygon(PackedVector2Array([lamp, a, b]), PackedColorArray([Color(s["deco"], 0.22 * alpha), Color(s["deco"], 0.0), Color(s["deco"], 0.0)]))
	# Water glints along the bottom.
	var glint: Color = Color("8FB8E8")
	for i in 18:
		var y := h * (0.88 + (i % 6) * 0.02)
		var x := fposmod(w * fmod(i * 0.137, 1.0) + t * (4.0 + (i % 3) * 2.0), w + 40.0) - 20.0
		var shimmer := 0.5 + 0.5 * sin(t * 1.4 + i)
		draw_line(Vector2(x, y), Vector2(x + 14.0 + (i % 4) * 6.0, y), Color(glint, (0.08 + 0.2 * shimmer) * alpha), 2.0, true)
