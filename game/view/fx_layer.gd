class_name FxLayer
extends Node2D
## Fixed pool of lightweight particles drawn in one _draw call. _process runs only while
## something is alive, so an idle board costs nothing.
const POOL := 96
const SOFT_DOT := preload("res://assets/art/soft_dot.svg")

var _pos := PackedVector2Array()
var _vel := PackedVector2Array()
var _life := PackedFloat32Array()
var _max_life := PackedFloat32Array()
var _size := PackedFloat32Array()
var _spin := PackedFloat32Array()
var _angle := PackedFloat32Array()
var _color := PackedColorArray()
var _shape := PackedByteArray() # 0 dot, 1 square (confetti), 2 ring, 3 four-point sparkle
var _gravity := PackedFloat32Array()
var _alive := 0
var _labels: Array[Dictionary] = []

func _ready() -> void:
	for array in [_pos, _vel]:
		array.resize(POOL)
	for array in [_life, _max_life, _size, _spin, _angle, _gravity]:
		array.resize(POOL)
	_color.resize(POOL)
	_shape.resize(POOL)
	set_process(false)

func _reduced() -> bool:
	return bool(SettingsManager.get_value("reduced_motion"))

func _spawn(at: Vector2, velocity: Vector2, life: float, size: float, color: Color, shape: int, gravity: float = 0.0, spin: float = 0.0) -> void:
	var slot := -1
	for i in POOL:
		if _life[i] <= 0.0:
			slot = i
			break
	if slot == -1:
		return
	_pos[slot] = at
	_vel[slot] = velocity
	_life[slot] = life
	_max_life[slot] = life
	_size[slot] = size
	_color[slot] = color
	_shape[slot] = shape
	_gravity[slot] = gravity
	_spin[slot] = spin
	_angle[slot] = randf() * TAU
	_alive += 1
	set_process(true)

## Small puff where a block crosses the board edge.
func exit_puff(at: Vector2, direction: Vector2, cell: float) -> void:
	if _reduced():
		return
	var p := Palette.colors()
	for i in 6:
		var spread := direction.rotated(randf_range(-0.9, 0.9)) * randf_range(0.6, 1.3) * cell * 1.6
		_spawn(at, spread, randf_range(0.28, 0.42), cell * randf_range(0.07, 0.12), Color(p["side"], 0.9), 0)
	_spawn(at, Vector2.ZERO, 0.32, cell * 0.5, Color(p["accent"], 0.35), 2)

## Ring + sparkles at a combo milestone.
func combo_burst(at: Vector2, cell: float, strength: int) -> void:
	if _reduced():
		return
	var p := Palette.colors()
	_spawn(at, Vector2.ZERO, 0.45, cell * (0.8 + strength * 0.15), Color(p["gold"], 0.6), 2)
	for i in 6 + strength * 2:
		var v := Vector2.UP.rotated(TAU * i / float(6 + strength * 2)) * cell * randf_range(1.6, 2.4)
		_spawn(at, v, randf_range(0.35, 0.5), cell * 0.08, Color(p["gold"], 0.95), 0)

## Short contact mark where a blocked head stopped: a small coral ring and two specks.
func collision(at: Vector2, cell: float) -> void:
	var p := Palette.colors()
	_spawn(at, Vector2.ZERO, 0.28, cell * 0.42, Color(p["coral"], 0.75), 2)
	if _reduced():
		return
	for i in 4:
		var v := Vector2.UP.rotated(TAU * i / 4.0 + 0.6) * cell * randf_range(1.0, 1.6)
		_spawn(at, v, randf_range(0.18, 0.26), cell * 0.06, Color(p["coral"], 0.9), 0)

## Golden arrow collected: a warm ring and a few twinkling sparkles (reduced motion: the ring only).
func gold_burst(at: Vector2, cell: float) -> void:
	_spawn(at, Vector2.ZERO, 0.5, cell * 0.9, Color(Scenery.GOLD, 0.8), 2)
	if _reduced():
		return
	for i in 8:
		var v := Vector2.UP.rotated(TAU * i / 8.0 + randf() * 0.4) * cell * randf_range(1.4, 2.6)
		_spawn(at, v, randf_range(0.45, 0.7), cell * randf_range(0.16, 0.26), Color(Scenery.GOLD_LIGHT, 1.0), 3, 0.0, randf_range(-4, 4))

## Confetti from the top of the board for a clear.
func confetti(area: Rect2, cell: float, count: int = 34) -> void:
	if _reduced():
		return
	var p := Palette.colors()
	var colors: Array[Color] = [p["accent"], p["gold"], p["coral"], p["ink_soft"], p["accent_soft"].darkened(0.1)]
	for i in count:
		var at := Vector2(randf_range(area.position.x, area.end.x), area.position.y - randf_range(0, cell))
		var v := Vector2(randf_range(-0.6, 0.6), randf_range(-2.4, -0.6)) * cell * 2.0
		_spawn(at, v, randf_range(1.0, 1.5), cell * randf_range(0.1, 0.16), colors[i % colors.size()], 1, cell * 9.0, randf_range(-8, 8))

func float_label(at: Vector2, text: String, color: Color, size: int) -> void:
	_labels.append({"pos": at, "text": text, "color": color, "size": size, "life": 0.9, "max": 0.9})
	set_process(true)

func clear_all() -> void:
	for i in POOL:
		_life[i] = 0.0
	_alive = 0
	_labels.clear()
	queue_redraw()
	set_process(false)

func _process(delta: float) -> void:
	_alive = 0
	for i in POOL:
		if _life[i] <= 0.0:
			continue
		_life[i] -= delta
		if _life[i] <= 0.0:
			continue
		_alive += 1
		_vel[i] = (_vel[i] * (1.0 - 2.4 * delta)) + Vector2(0, _gravity[i] * delta)
		_pos[i] += _vel[i] * delta
		_angle[i] += _spin[i] * delta
	for label in _labels:
		label["life"] -= delta
		label["pos"] += Vector2(0, -38.0 * delta)
	_labels = _labels.filter(func(l: Dictionary) -> bool: return l["life"] > 0.0)
	queue_redraw()
	if _alive == 0 and _labels.is_empty():
		set_process(false)

func _draw() -> void:
	for i in POOL:
		if _life[i] <= 0.0:
			continue
		var t := _life[i] / _max_life[i]
		var c := _color[i]
		match _shape[i]:
			0:
				draw_circle(_pos[i], _size[i] * (0.5 + 0.5 * t), Color(c, c.a * t), true, -1.0, true)
			1:
				draw_set_transform(_pos[i], _angle[i])
				var s := _size[i]
				draw_rect(Rect2(Vector2(-s, -s * 0.55), Vector2(s * 2.0, s * 1.1)), Color(c, minf(1.0, t * 2.0)))
				draw_set_transform(Vector2.ZERO, 0.0)
			2:
				var radius := _size[i] * (1.0 - t * 0.6)
				draw_arc(_pos[i], radius, 0, TAU, 40, Color(c, c.a * t), maxf(2.0, _size[i] * 0.1 * t), true)
			3:
				draw_set_transform(_pos[i], _angle[i])
				var r := _size[i] * (0.4 + 0.6 * t)
				var k := r * 0.28
				draw_colored_polygon(PackedVector2Array([Vector2(0, -r), Vector2(k, -k), Vector2(r, 0), Vector2(k, k), Vector2(0, r),
					Vector2(-k, k), Vector2(-r, 0), Vector2(-k, -k)]), Color(c, c.a * minf(1.0, t * 1.6)))
				draw_set_transform(Vector2.ZERO, 0.0)
	for label in _labels:
		var t: float = label["life"] / label["max"]
		var font := Design.font(800)
		var width := font.get_string_size(label["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, label["size"]).x
		draw_string(font, label["pos"] - Vector2(width * 0.5, 0), label["text"], HORIZONTAL_ALIGNMENT_LEFT, -1,
			label["size"], Color(label["color"], minf(1.0, t * 2.2)))
