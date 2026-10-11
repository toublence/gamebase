class_name BlockView
extends Node2D
## One block. Pure presentation: it never decides whether it may move.
## Origin is the cell center. Redraws only when its look changes; movement is transform tweens.
const ARROW := preload("res://assets/art/arrow.svg")
const ARROW_OUTLINE := preload("res://assets/art/arrow_outline.svg")
const ROTATE_BADGE := preload("res://assets/art/rotate_badge.svg")

var id := -1
var kind := 0
var cell := 56.0
var detail := "plain"
var switch_label := ""
var target_labels := ""
var moving := false

var arrow_angle := 0.0:
	set(value):
		arrow_angle = value
		queue_redraw()
var pressed := false:
	set(value):
		if pressed != value:
			pressed = value
			queue_redraw()
var flash := 0.0:
	set(value):
		flash = value
		queue_redraw()
var hint_pulse := 0.0:
	set(value):
		hint_pulse = value
		queue_redraw()
var trail := 0.0:
	set(value):
		trail = value
		queue_redraw()
var preview_dir := -1:
	set(value):
		if preview_dir != value:
			preview_dir = value
			queue_redraw()
var dimmed := false:
	set(value):
		if dimmed != value:
			dimmed = value
			queue_redraw()

var _hint_tween: Tween
var _rotate_tween: Tween
var _move_tween: Tween
var _flash_tween: Tween
var _target_angle := 0.0
var _trail_dir := Vector2.ZERO

func configure(block_id: int, block_kind: int, dir: int, cell_size: float, chapter_detail: String) -> void:
	id = block_id
	kind = block_kind
	cell = cell_size
	detail = chapter_detail
	_target_angle = Dir.angle(dir)
	arrow_angle = _target_angle
	queue_redraw()

func _reduced() -> bool:
	return bool(SettingsManager.get_value("reduced_motion"))

func _draw() -> void:
	var p := Palette.colors()
	var b := cell * 0.88
	var half := b * 0.5
	var lip := maxf(3.0, b * 0.085)
	var sink := lip * 0.6 if pressed else 0.0
	var radius := int(b * 0.22)
	var face_color: Color = p["switch_face"] if kind == BoardState.KIND_SWITCH else p["face"]
	face_color = face_color.lerp(p["coral_soft"], clampf(flash, 0.0, 1.0))
	if dimmed:
		face_color = face_color.lerp(p["board"], 0.35)
	# Motion trail behind an escaping block.
	if trail > 0.01 and _trail_dir != Vector2.ZERO:
		var length := b * 1.3 * trail
		var back := -_trail_dir
		var r := Rect2(Vector2(-half, -half), Vector2(b, b - lip))
		if back.x != 0.0:
			r = Rect2(Vector2(minf(-half, -half + back.x * length), -half + b * 0.12), Vector2(b + length, b - lip - b * 0.24))
		else:
			r = Rect2(Vector2(-half + b * 0.12, minf(-half, -half + back.y * length)), Vector2(b - b * 0.24, b - lip + length))
		draw_style_box(_box(Color(p["face"], 0.32 * trail), radius), r)
	# Shadow + lip (thickness), then the face that sinks when pressed.
	var side := _box(p["side"], radius)
	side.shadow_color = Color(p["shadow"], 0.13)
	side.shadow_size = int(maxf(2.0, b * 0.07))
	side.shadow_offset = Vector2(0, b * 0.05)
	draw_style_box(side, Rect2(Vector2(-half, -half + lip), Vector2(b, b - lip)))
	var face_rect := Rect2(Vector2(-half, -half + sink), Vector2(b, b - lip))
	draw_style_box(_box(face_color, radius), face_rect)
	_draw_detail(face_rect, p, radius)
	var center := face_rect.get_center()
	# Switch dial: ring + filled letter badge. Linked blocks: outlined letter badge + turn mark.
	if kind == BoardState.KIND_SWITCH:
		draw_arc(center, b * 0.405, 0, TAU, 48, Color(p["accent"], 0.85), maxf(2.0, b * 0.05), true)
		_badge(center + Vector2(-half + b * 0.17, -half + b * 0.17), switch_label, p, true, b)
	if not target_labels.is_empty():
		_badge(center + Vector2(half - b * 0.17, -half + b * 0.17), target_labels, p, false, b)
		var mark := b * 0.2
		draw_texture_rect(ROTATE_BADGE, Rect2(center + Vector2(half - b * 0.08 - mark, half - lip - b * 0.06 - mark), Vector2(mark, mark)), false, Color(p["accent"], 0.9))
	# Arrow (vector art), dimmed under a rotation preview.
	var arrow_size := b * (0.5 if kind == BoardState.KIND_SWITCH else 0.58)
	var arrow_color: Color = p["ink"].lerp(p["coral"], clampf(flash * 1.4, 0.0, 1.0))
	if preview_dir >= 0:
		arrow_color = Color(arrow_color, 0.25)
	draw_set_transform(center, arrow_angle)
	draw_texture_rect(ARROW, Rect2(Vector2(-arrow_size, -arrow_size) * 0.5, Vector2(arrow_size, arrow_size)), false, arrow_color)
	if preview_dir >= 0:
		draw_set_transform(center, Dir.angle(preview_dir))
		draw_texture_rect(ARROW_OUTLINE, Rect2(Vector2(-arrow_size, -arrow_size) * 0.5, Vector2(arrow_size, arrow_size)), false, p["accent"])
	draw_set_transform(Vector2.ZERO, 0.0)
	# Hint ring: pulses outside the block, never covers the arrow.
	if hint_pulse > 0.0:
		var ring := StyleBoxFlat.new()
		ring.draw_center = false
		ring.set_border_width_all(int(maxf(3.0, b * 0.06)))
		ring.border_color = Color(p["accent"], 0.45 + 0.55 * hint_pulse)
		ring.set_corner_radius_all(radius + 6)
		ring.anti_aliasing = true
		var grow := 4.0 + 5.0 * hint_pulse
		draw_style_box(ring, Rect2(Vector2(-half - grow, -half - grow + sink), Vector2(b + grow * 2, b + grow * 2)))

func _draw_detail(face: Rect2, p: Dictionary, radius: int) -> void:
	match detail:
		"bevel":
			draw_line(face.position + Vector2(radius, 3), Vector2(face.end.x - radius, face.position.y + 3), Color(1, 1, 1, 0.9), 2.0, true)
		"corners":
			var inset := face.size.x * 0.16
			for corner in [Vector2(inset, inset), Vector2(face.size.x - inset, inset), Vector2(inset, face.size.y - inset), Vector2(face.size.x - inset, face.size.y - inset)]:
				draw_circle(face.position + corner, face.size.x * 0.028, Color(p["side"], 0.8), true, -1.0, true)
		"double":
			var inner := StyleBoxFlat.new()
			inner.draw_center = false
			inner.set_border_width_all(2)
			inner.border_color = Color(p["side"], 0.55)
			inner.set_corner_radius_all(maxi(2, radius - 5))
			inner.anti_aliasing = true
			draw_style_box(inner, face.grow(-face.size.x * 0.08))
		"sheen":
			var a := face.position + Vector2(face.size.x * 0.18, face.size.y)
			var b := face.position + Vector2(face.size.x * 0.62, 0)
			draw_line(a, b, Color(1, 1, 1, 0.45), face.size.x * 0.1, true)

func _badge(at: Vector2, text: String, p: Dictionary, filled: bool, b: float) -> void:
	var r := b * 0.13
	if filled:
		draw_circle(at, r, p["accent"], true, -1.0, true)
	else:
		draw_circle(at, r, p["face"], true, -1.0, true)
		draw_circle(at, r, p["accent"], false, maxf(1.5, b * 0.03), true)
	var font := Design.font(800)
	var size := int(r * 1.35)
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, at + Vector2(-width * 0.5, size * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size,
		Color.WHITE if filled else p["accent"])

func _box(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.anti_aliasing = true
	style.anti_aliasing_size = 0.8
	return style

# --- animation ---------------------------------------------------------------------------------

func press(on: bool) -> void:
	pressed = on
	if _reduced():
		scale = Vector2.ONE
		return
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2(0.95, 0.95) if on else Vector2.ONE, 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

## Leaves the board along its arrow. Starts after `delay` (used to avoid crossing a block that is
## still visibly leaving). Returns the duration.
func escape(direction: Vector2, distance_px: float, delay: float) -> float:
	moving = true
	pressed = false
	finish_rotation()
	set_hint(false)
	_kill(_move_tween)
	_trail_dir = direction
	if _reduced():
		_move_tween = create_tween()
		_move_tween.tween_interval(delay)
		_move_tween.tween_property(self, "modulate:a", 0.0, 0.1)
		_move_tween.tween_callback(queue_free)
		return delay + 0.1
	var duration := clampf(0.13 + distance_px / cell * 0.024, 0.15, 0.3)
	var start := position
	_move_tween = create_tween()
	_move_tween.tween_interval(delay)
	# Tiny anticipation, then accelerate out.
	_move_tween.tween_property(self, "position", start - direction * cell * 0.07, 0.045).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_move_tween.parallel().tween_property(self, "scale", Vector2.ONE * 0.97, 0.045)
	_move_tween.tween_property(self, "position", start + direction * distance_px, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_move_tween.parallel().tween_property(self, "scale", Vector2.ONE, duration * 0.4)
	_move_tween.parallel().tween_property(self, "trail", 1.0, duration * 0.5)
	_move_tween.parallel().tween_property(self, "modulate:a", 0.0, duration * 0.35).set_delay(duration * 0.65)
	_move_tween.tween_callback(queue_free)
	return delay + 0.045 + duration

## Bumps toward the blocker, stops in front of it and springs back.
func bump(direction: Vector2, gap_cells: int) -> void:
	finish_rotation()
	_kill(_move_tween)
	position = _home()
	flash_blocked()
	if _reduced():
		return
	var reach := (gap_cells + 0.16) * cell
	var travel := clampf(0.05 + gap_cells * 0.03, 0.05, 0.16)
	_move_tween = create_tween()
	_move_tween.tween_property(self, "position", _home() + direction * reach, travel).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_move_tween.tween_property(self, "position", _home(), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## The blocker answers with a small nudge in the push direction.
func nudge(direction: Vector2, delay: float) -> void:
	if _reduced() or moving:
		return
	_kill(_move_tween)
	position = _home()
	_move_tween = create_tween()
	_move_tween.tween_interval(delay)
	_move_tween.tween_property(self, "position", _home() + direction * cell * 0.06, 0.05)
	_move_tween.tween_property(self, "position", _home(), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func flash_blocked() -> void:
	_kill(_flash_tween)
	flash = 1.0
	_flash_tween = create_tween()
	_flash_tween.tween_interval(0.12)
	_flash_tween.tween_property(self, "flash", 0.0, 0.3)

func rotate_to(dir: int, delay: float = 0.0) -> void:
	_kill(_rotate_tween)
	var target := Dir.angle(dir)
	# Always turn clockwise for a switch turn.
	while target < arrow_angle - 0.001:
		target += TAU
	_target_angle = target
	if _reduced():
		arrow_angle = _target_angle
		return
	_rotate_tween = create_tween()
	_rotate_tween.tween_interval(delay)
	_rotate_tween.tween_property(self, "arrow_angle", _target_angle, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func set_direction(dir: int) -> void:
	_kill(_rotate_tween)
	_target_angle = Dir.angle(dir)
	arrow_angle = _target_angle

## Snaps any running turn to its final angle so input never races the animation.
func finish_rotation() -> void:
	if _rotate_tween != null and _rotate_tween.is_valid():
		_rotate_tween.kill()
		arrow_angle = _target_angle

func set_hint(on: bool) -> void:
	_kill(_hint_tween)
	if not on:
		hint_pulse = 0.0
		return
	hint_pulse = 1.0
	if _reduced():
		return
	_hint_tween = create_tween().set_loops()
	_hint_tween.tween_property(self, "hint_pulse", 0.25, 0.55).set_trans(Tween.TRANS_SINE)
	_hint_tween.tween_property(self, "hint_pulse", 1.0, 0.55).set_trans(Tween.TRANS_SINE)

## Undo: the block flies back in from where it left.
func return_from(direction: Vector2, distance_px: float) -> void:
	moving = false
	_kill(_move_tween)
	trail = 0.0
	if _reduced():
		position = _home()
		modulate.a = 1.0
		return
	position = _home() + direction * distance_px
	modulate.a = 0.0
	_move_tween = create_tween()
	_move_tween.tween_property(self, "position", _home(), 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_move_tween.parallel().tween_property(self, "modulate:a", 1.0, 0.12)

func appear(delay: float) -> void:
	if _reduced():
		return
	scale = Vector2(0.6, 0.6)
	modulate.a = 0.0
	var tween := create_tween()
	tween.tween_interval(delay)
	tween.tween_property(self, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "modulate:a", 1.0, 0.12)

var home := Vector2.ZERO
func _home() -> Vector2:
	return home

func _kill(tween: Tween) -> void:
	if tween != null and tween.is_valid():
		tween.kill()
