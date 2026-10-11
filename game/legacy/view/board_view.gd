class_name BoardView
extends Control
## Draws the board, owns BlockViews and turns touches into taps. It never decides outcomes: the
## module resolves a tap with PuzzleSession first and then asks this view to play the result.
signal tapped(id: int)
signal touch_down(id: int)
signal preview_shown(id: int)

const MAX_CELL := 96.0
const MIN_CELL := 36.0
## A press becomes a tap only if the finger stays within this fraction of a cell.
const TAP_SLOP := 0.5
const PREVIEW_DELAY := 0.24

var board: BoardState
var input_enabled := true
var cell := 56.0
var origin := Vector2.ZERO
var panel_rect := Rect2()
var blocks := {} # id -> BlockView
var fx: FxLayer

var _style := {"pattern": "dots", "detail": "plain"}
var _labels := {}
var _root: Node2D
var _pointer: PointerInput
var _press_id := -1
var _press_pointer := -999
var _press_start := Vector2.ZERO
var _preview_id := -1
var _preview_timer: Timer
var _moving := {} # id -> {"cells": Dictionary, "until": int}
var _hint_id := -1
var _ripple := 0.0:
	set(value):
		_ripple = value
		queue_redraw()
var _blocked_line := {} # {"from", "to", "alpha"}
var _blocked_alpha := 0.0:
	set(value):
		_blocked_alpha = value
		queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root = Node2D.new()
	add_child(_root)
	fx = FxLayer.new()
	add_child(fx)
	_pointer = PointerInput.new()
	add_child(_pointer)
	_pointer.pressed.connect(_on_pressed)
	_pointer.dragged.connect(_on_dragged)
	_pointer.released.connect(_on_released)
	_pointer.cancelled.connect(_on_cancelled)
	_preview_timer = Timer.new()
	_preview_timer.one_shot = true
	_preview_timer.timeout.connect(_show_preview)
	add_child(_preview_timer)
	resized.connect(_layout)
	Progress.theme_changed.connect(func(_id: String): _redraw_all())

func setup(level_board: BoardState, style: Dictionary, labels: Dictionary, animate_in: bool) -> void:
	board = level_board
	_style = style
	_labels = labels
	for child in _root.get_children():
		child.queue_free()
	blocks.clear()
	_moving.clear()
	_hint_id = -1
	_preview_id = -1
	_press_id = -1
	fx.clear_all()
	_blocked_line = {}
	_layout()
	var order := 0
	for id in board.live_ids():
		var view := _make_block(id)
		if animate_in:
			# Stagger by distance from the board center so the board "assembles" quickly.
			var c := board.cell_of(id)
			var dist := Vector2(c.x - (board.width - 1) * 0.5, c.y - (board.height - 1) * 0.5).length()
			view.appear(0.02 + dist * 0.035 + order * 0.002)
		order += 1
	queue_redraw()

func _make_block(id: int) -> BlockView:
	var view := BlockView.new()
	var label: Dictionary = _labels.get(id, {})
	view.switch_label = str(label.get("switch", ""))
	view.target_labels = str(label.get("targets", ""))
	view.configure(id, board.kinds[id], board.dirs[id], cell, str(_style.get("detail", "plain")))
	view.home = cell_center(board.cell_of(id))
	view.position = view.home
	_root.add_child(view)
	blocks[id] = view
	return view

func _layout() -> void:
	if board == null or size.x <= 0.0 or size.y <= 0.0:
		return
	var pad_ratio := 0.32
	var fit_w := size.x / (board.width + pad_ratio * 2.0)
	var fit_h := size.y / (board.height + pad_ratio * 2.0)
	cell = floorf(clampf(minf(fit_w, fit_h), MIN_CELL, MAX_CELL))
	var pad := cell * pad_ratio
	var grid_size := Vector2(board.width, board.height) * cell
	panel_rect = Rect2((size - grid_size) * 0.5 - Vector2(pad, pad), grid_size + Vector2(pad, pad) * 2.0)
	origin = panel_rect.position + Vector2(pad, pad)
	for id in blocks:
		var view: BlockView = blocks[id]
		view.cell = cell
		view.home = cell_center(board.cell_of(id))
		if not view.moving:
			view.position = view.home
		view.queue_redraw()
	queue_redraw()

func cell_center(c: Vector2i) -> Vector2:
	return origin + (Vector2(c) + Vector2(0.5, 0.5)) * cell

func id_at(local: Vector2) -> int:
	if board == null:
		return -1
	var rel := (local - origin) / cell
	var x := int(floor(rel.x))
	var y := int(floor(rel.y))
	if not board.in_bounds(x, y):
		return -1
	var id := board.at(x, y)
	return id if blocks.has(id) and not (blocks[id] as BlockView).moving else -1

func _redraw_all() -> void:
	for id in blocks:
		(blocks[id] as BlockView).queue_redraw()
	queue_redraw()

# --- drawing -----------------------------------------------------------------------------------

func _draw() -> void:
	if board == null:
		return
	var p := Palette.colors()
	var panel := Design.box(p["board"], int(cell * 0.42), 0, Color.TRANSPARENT, 0.0)
	panel.border_width_left = 2
	panel.border_width_top = 2
	panel.border_width_right = 2
	panel.border_width_bottom = 5
	panel.border_color = p["board_line"]
	draw_style_box(panel, panel_rect)
	var pattern := str(_style.get("pattern", "dots"))
	if pattern == "hatch":
		var step := cell * 0.5
		var x := panel_rect.position.x - panel_rect.size.y
		while x < panel_rect.end.x:
			var a := Vector2(maxf(x, panel_rect.position.x), panel_rect.position.y + maxf(0.0, panel_rect.position.x - x))
			var b := Vector2(minf(x + panel_rect.size.y, panel_rect.end.x), panel_rect.position.y + minf(panel_rect.size.y, panel_rect.end.x - x))
			draw_line(a + Vector2(6, 6), b - Vector2(6, 6), Color(p["board_line"], 0.35), 1.5, true)
			x += step
	for y in board.height:
		for x in board.width:
			var center := cell_center(Vector2i(x, y))
			var dist := center.distance_to(panel_rect.get_center()) / maxf(1.0, panel_rect.size.length() * 0.5)
			var lift := 0.0
			if _ripple > 0.0:
				lift = clampf(1.0 - absf(dist - _ripple) * 4.0, 0.0, 1.0)
			var dot_color: Color = p["dot"].lerp(p["accent"], lift * 0.8)
			var r := cell * (0.055 + lift * 0.05)
			match pattern:
				"grid":
					var cell_box := Design.box(Color(p["board_line"], 0.0), int(cell * 0.2), 0, Color.TRANSPARENT, 0.0)
					cell_box.draw_center = false
					cell_box.set_border_width_all(1)
					cell_box.border_color = Color(p["board_line"], 0.6)
					draw_style_box(cell_box, Rect2(center - Vector2(cell, cell) * 0.4, Vector2(cell, cell) * 0.8))
					draw_circle(center, r * 0.8, dot_color, true, -1.0, true)
				"rings":
					draw_arc(center, r * 1.8, 0, TAU, 20, Color(dot_color, 0.9), 1.6, true)
				"stars":
					draw_line(center - Vector2(r * 1.6, 0), center + Vector2(r * 1.6, 0), dot_color, 1.6, true)
					draw_line(center - Vector2(0, r * 1.6), center + Vector2(0, r * 1.6), dot_color, 1.6, true)
				_:
					draw_circle(center, r, dot_color, true, -1.0, true)
	_draw_links(p)
	if not _blocked_line.is_empty() and _blocked_alpha > 0.0:
		_dashed(_blocked_line["from"], _blocked_line["to"], Color(p["coral"], _blocked_alpha), maxf(3.0, cell * 0.06))

func _draw_links(p: Dictionary) -> void:
	for id in blocks:
		if board.kinds[id] != BoardState.KIND_SWITCH:
			continue
		var from := cell_center(board.cell_of(id))
		var strong: bool = id == _preview_id
		for target in board.links[id]:
			if not blocks.has(target):
				continue
			var to := cell_center(board.cell_of(target))
			_dashed(from, to, Color(p["accent"], 0.9 if strong else 0.32), maxf(2.0, cell * (0.06 if strong else 0.04)))

func _dashed(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var length := from.distance_to(to)
	if length < 1.0:
		return
	var dir := (to - from) / length
	var dash := maxf(6.0, cell * 0.14)
	var t := 0.0
	while t < length:
		var a := from + dir * t
		var b := from + dir * minf(length, t + dash)
		draw_line(a, b, color, width, true)
		t += dash * 1.8

# --- input -------------------------------------------------------------------------------------

func _local(viewport_pos: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * viewport_pos

func _on_pressed(pointer: int, at: Vector2) -> void:
	if not input_enabled or _press_id != -1:
		return # one finger at a time; extra touches never become taps
	var id := id_at(_local(at))
	if id == -1:
		return
	_press_id = id
	_press_pointer = pointer
	_press_start = at
	(blocks[id] as BlockView).press(true)
	touch_down.emit(id)
	if board.kinds[id] == BoardState.KIND_SWITCH:
		_preview_timer.start(PREVIEW_DELAY)

func _on_dragged(pointer: int, at: Vector2, _delta: Vector2) -> void:
	if pointer != _press_pointer or _press_id == -1:
		return
	var scale_factor := get_global_transform_with_canvas().get_scale().x
	if at.distance_to(_press_start) > cell * TAP_SLOP * scale_factor:
		_release_press()

func _on_released(pointer: int, at: Vector2, displacement: Vector2, _seconds: float) -> void:
	if pointer != _press_pointer or _press_id == -1:
		return
	var id := _press_id
	var scale_factor := get_global_transform_with_canvas().get_scale().x
	var on_block := id_at(_local(at)) == id
	_release_press()
	if input_enabled and on_block and displacement.length() <= cell * TAP_SLOP * scale_factor:
		tapped.emit(id)

func _on_cancelled(pointer: int) -> void:
	if pointer == _press_pointer:
		_release_press()

func _release_press() -> void:
	_preview_timer.stop()
	if blocks.has(_press_id):
		(blocks[_press_id] as BlockView).press(false)
	hide_preview()
	_press_id = -1
	_press_pointer = -999

## Called when the board must ignore any finger still down (transitions, panels, ads).
func cancel_input() -> void:
	_pointer.cancel_all()
	_release_press()

func _show_preview() -> void:
	if _press_id == -1 or board.kinds[_press_id] != BoardState.KIND_SWITCH:
		return
	_preview_id = _press_id
	var preview := MoveResolver.preview_rotation(board, _press_id)
	for target in preview:
		if blocks.has(target):
			(blocks[target] as BlockView).preview_dir = preview[target]
	queue_redraw()
	preview_shown.emit(_press_id)

func hide_preview() -> void:
	if _preview_id == -1:
		return
	for id in blocks:
		(blocks[id] as BlockView).preview_dir = -1
	_preview_id = -1
	queue_redraw()

# --- playback ----------------------------------------------------------------------------------

func _path_cells(id: int) -> Dictionary:
	var cells := {}
	var step := Dir.vec(board.dirs[id])
	var c := board.cell_of(id)
	while board.in_bounds(c.x, c.y):
		cells[c] = true
		c += step
	return cells

## Plays a resolved escape. Returns seconds until the block is fully gone.
func play_escape(event: Dictionary) -> float:
	var id: int = event["id"]
	if not blocks.has(id):
		return 0.0
	var view: BlockView = blocks[id]
	blocks.erase(id)
	if id == _hint_id:
		_hint_id = -1
	var now := Time.get_ticks_msec()
	var cells := _path_cells(id)
	var delay := 0.0
	for other in _moving.keys():
		var entry: Dictionary = _moving[other]
		if int(entry["until"]) <= now:
			_moving.erase(other)
			continue
		for c in cells:
			if entry["cells"].has(c):
				# Wait for the earlier block to clear the crossing; capped so taps stay snappy.
				delay = maxf(delay, minf(0.22, (int(entry["until"]) - now) / 1000.0 * 0.7))
				break
	var direction := Vector2(Dir.vec(board.dirs[id]))
	var distance := (MoveResolver.exit_distance(board, id) + 0.75) * cell
	var total := view.escape(direction, distance, delay)
	_moving[id] = {"cells": cells, "until": now + int(total * 1000.0)}
	var edge := cell_center(board.cell_of(id)) + direction * (MoveResolver.exit_distance(board, id) - 0.5) * cell
	var puff := create_tween()
	puff.tween_interval(delay + total * 0.55)
	puff.tween_callback(func(): fx.exit_puff(edge, direction, cell))
	var rotated: PackedInt32Array = event.get("rotated", PackedInt32Array())
	for target in rotated:
		if blocks.has(target):
			(blocks[target] as BlockView).rotate_to(board.dirs[target], delay + 0.05)
	queue_redraw()
	return total

func play_blocked(event: Dictionary) -> void:
	var id: int = event["id"]
	var blocker: int = event["blocker"]
	if not blocks.has(id):
		return
	var direction := Vector2(Dir.vec(board.dirs[id]))
	(blocks[id] as BlockView).bump(direction, int(event.get("gap", 0)))
	if blocks.has(blocker):
		(blocks[blocker] as BlockView).nudge(direction, clampf(0.05 + int(event.get("gap", 0)) * 0.03, 0.05, 0.16))
	# Show what stopped it: a short dashed line along the arrow to the blocker.
	_blocked_line = {"from": cell_center(board.cell_of(id)) + direction * cell * 0.45,
		"to": cell_center(board.cell_of(blocker)) - direction * cell * 0.45}
	_blocked_alpha = 0.9
	var tween := create_tween()
	tween.tween_interval(0.35)
	tween.tween_property(self, "_blocked_alpha", 0.0, 0.4)

func play_undo(event: Dictionary) -> void:
	var id: int = event["id"]
	var view := _make_block(id)
	var direction := Vector2(Dir.vec(board.dirs[id]))
	view.return_from(direction, (MoveResolver.exit_distance(board, id) + 0.75) * cell)
	for target in event.get("rotated", PackedInt32Array()):
		if blocks.has(target):
			(blocks[target] as BlockView).set_direction(board.dirs[target])
	queue_redraw()

func show_hint(id: int) -> void:
	clear_hint()
	if blocks.has(id):
		_hint_id = id
		(blocks[id] as BlockView).set_hint(true)

func clear_hint() -> void:
	if blocks.has(_hint_id):
		(blocks[_hint_id] as BlockView).set_hint(false)
	_hint_id = -1

func celebrate() -> void:
	fx.confetti(panel_rect, cell)
	if SettingsManager.get_value("reduced_motion"):
		return
	var tween := create_tween()
	tween.tween_property(self, "_ripple", 1.2, 0.6).from(0.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "_ripple", 0.0, 0.0)

func combo(at_id_cell: Vector2i, combo_count: int) -> void:
	var strength := 1 if combo_count < 6 else (2 if combo_count < 10 else 3)
	var at := cell_center(at_id_cell)
	fx.combo_burst(at, cell, strength)
	fx.float_label(panel_rect.position + Vector2(panel_rect.size.x * 0.5, -cell * 0.1),
		tr("COMBO_N") % combo_count, Palette.c("gold").darkened(0.15), int(clampf(cell * 0.42, 18, 30)))
