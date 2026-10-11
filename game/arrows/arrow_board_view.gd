class_name ArrowBoardView
extends Control
## Board presentation for "arrow-path-2": layout, touch, pinch-zoom/pan and motion playback.
## It never decides outcomes. The module resolves a tap in ArrowSession first, then asks this view
## to play the result.
##
## Picture: the board is drawn as the level's silhouette (one soft tile per picture cell, with a
## lip below so it reads as a raised slab) in the colors of the level's scene. Tutorial boards
## without a silhouette use a rounded panel.
##
## Touch: a touch selects the arrow whose drawn path passes closest to the finger, within a radius
## that keeps a comfortable fingertip size at every zoom. When two arrows are almost equally close
## (judged in screen pixels, so small cells get a wider tie band), or when the closest arrow is
## blocked but a free arrow is nearly as close, nothing happens (no heart is lost) and both arrows
## nod, so a fat-finger touch is never charged as a wrong decision.
##
## Camera: every board opens on the whole picture (the overview). When its cells are too small to
## read heads comfortably, overview_then_play() glides to the play zoom (PLAY_CELL on screen) after
## a short look, unless the player already touched the board. toggle_camera() switches between the
## overview and the play zoom (the HUD's camera button); double-tapping empty space does the same at
## the tapped point; pinch zooms (with two-finger pan) up to fingertip-sized cells; one finger pans
## while zoomed and keeps gliding briefly after a flick.
##
## Motion: an escaping arrow slides its window along its track with a fixed speed profile
## (accelerate, then cruise). When a second arrow must cross cells the first is still sliding
## through, its start is delayed by exactly the time needed for the first arrow's tail to clear the
## shared cells before the second head arrives. Logic never waits; only the second picture starts
## a little later, so nothing ever passes through anything on screen.
signal tapped(id: int)
signal touch_down(id: int)
## A touch that hit no single arrow on purpose: "ambiguous" (between two arrows).
signal touch_missed(kind: String)
## Any finger or mouse press on the board (arrow or not).
signal touched
## The camera moved between the overview and a zoomed view (true = zoomed in).
signal zoom_changed(zoomed: bool)
## First zoom on this board ("pinch", "double_tap" or "wheel").
signal zoom_used(method: String)
## A golden arrow left the board at this canvas position.
signal gold_collected(id: int, at: Vector2)

const MIN_CELL := 4.0
## On-screen cell size of the play zoom: heads and bends read clearly at a glance.
const PLAY_CELL := 30.0
## The overview glides to the play zoom only when that enlarges the board at least this much, and
## only for boards whose overview cells are smaller than READABLE_CELL (heads already read well at
## that size, and zooming would only crop the picture).
const PLAY_GAIN := 1.1
const READABLE_CELL := 23.0
const MAX_CELL := 104.0
const PAD := 0.32 # board padding in cells
const ZOOM_CELL := 64.0 # on-screen cell size (logical px) at full zoom
const TOUCH_RADIUS := 24.0 # logical px around the fingertip that still counts as on an arrow
## Two arrows whose distances to the finger differ by less than this (screen px) are a tie.
const TIE_PX := 9.0
## Below this on-screen cell size a touch is never "squarely" on one stroke (at 18 px a finger
## within 0.3 cells is about 5 px from the line).
const SQUARE_MIN_CELL := 18.0
## Flick glide: start speed (px/s) and decay per second.
const FLING_MIN_SPEED := 260.0
const FLING_DECAY := 5.5
const DOUBLE_TAP_MS := 320
const DOUBLE_TAP_SLOP := 40.0
const AMBIGUOUS := -2
## Speed profile in cells/s.
const V0 := 7.0
const ACCEL := 70.0
const VMAX := 30.0
const CROSS_MARGIN_S := 0.03

var board: ArrowBoard
var input_enabled := true
var cell := 48.0
var arrows := {} # resting (not moving) arrow id -> true
var fx: FxLayer
var zoom := 1.0
var scene_id := "morning"
var mask := PackedByteArray()
var golden := {} # arrow id -> true

var _content: Node2D
var _canvas: ArrowCanvas
var _arrows_root: Node2D
var _pointer: PointerInput
var _base_offset := Vector2.ZERO
var _offset := Vector2.ZERO
var _panel_size := Vector2.ZERO
var _touches := {} # pointer id -> viewport position
var _press := {} # {pointer, start, id, cancelled, candidates}
var _pinch := {}
var _moves: Array = [] # {id, start_ms, cells: {Vector2i: track index}, length}
var _movers := {} # arrow id -> ArrowView while it moves
var _hint_id := -1
var _hint_tween: Tween
var _zoom_tween: Tween
var _bumps := {} # id -> Tween
var _last_candidates: Array = []
var _last_empty_tap := {"ms": -100000, "at": Vector2.ZERO}
var _zoom_reported := false
var _camera_serial := 0
var _user_camera := false # the player touched the board since the last overview
var _pan_velocity := Vector2.ZERO
var _last_pan_ms := 0
var _fling := Vector2.ZERO

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content = Node2D.new()
	add_child(_content)
	_arrows_root = Node2D.new()
	_content.add_child(_arrows_root)
	_canvas = ArrowCanvas.new()
	_canvas.attach(_arrows_root)
	fx = FxLayer.new()
	_content.add_child(fx)
	_pointer = PointerInput.new()
	add_child(_pointer)
	_pointer.pressed.connect(_on_pressed)
	_pointer.dragged.connect(_on_dragged)
	_pointer.released.connect(_on_released)
	_pointer.cancelled.connect(_on_cancelled)
	set_process(false)
	resized.connect(_layout)
	Progress.theme_changed.connect(_on_theme_changed)
	SettingsManager.changed.connect(_on_setting_changed)

func _on_theme_changed(_id: String) -> void:
	_restyle_all()

func _on_setting_changed(key: String, _value: Variant) -> void:
	if key == "arrow_colors":
		_restyle_all()

## style: {scene: id, mask: PackedByteArray (empty = whole rectangle), gold: [arrow ids],
## wrong: [arrow ids already tapped while blocked in this attempt (drawn red)]}
func setup(level_board: ArrowBoard, style: Dictionary, animate_in: bool) -> void:
	board = level_board
	scene_id = str(style.get("scene", "morning"))
	mask = style.get("mask", PackedByteArray())
	golden.clear()
	for id in style.get("gold", []):
		golden[int(id)] = true
	_canvas.wrong.clear()
	for id in style.get("wrong", []):
		_canvas.wrong[int(id)] = true
	for id in _movers:
		(_movers[id] as ArrowView).queue_free()
	_movers.clear()
	arrows.clear()
	for id in board.live_ids():
		arrows[id] = true
	_moves.clear()
	for id in _bumps:
		if (_bumps[id] as Tween).is_valid():
			(_bumps[id] as Tween).kill()
	_bumps.clear()
	_hint_id = -1
	_press = {}
	_touches.clear()
	_pinch = {}
	_zoom_reported = false
	if _zoom_tween != null and _zoom_tween.is_valid():
		_zoom_tween.kill()
	fx.clear_all()
	zoom = 1.0
	_offset = Vector2.ZERO
	_camera_serial += 1
	_user_camera = false
	_stop_fling()
	_configure_canvas()
	_layout()
	if animate_in and not SettingsManager.get_value("reduced_motion"):
		_arrows_root.modulate.a = 0.0
		var tween := create_tween()
		tween.tween_property(_arrows_root, "modulate:a", 1.0, 0.35)
	else:
		_arrows_root.modulate.a = 1.0
	zoom_changed.emit(zoom > 1.02)

func _configure_canvas() -> void:
	var s := Scenery.scene(scene_id)
	var colors := _assign_colors() if SettingsManager.get_value("arrow_colors") == true else {}
	_canvas.configure(board, cell, Scenery.ink(scene_id), colors, golden, mask, s["dot"])
	_canvas.halo = s["board"]
	_canvas.refresh()

## Optional per-arrow inks (setting "arrow_colors"): neighbours get different colors.
func _assign_colors() -> Dictionary:
	var inks := Scenery.inks(scene_id)
	var result := {}
	for id in board.size():
		var used := {}
		for c in board.cells_of(id):
			for d in 4:
				var n: Vector2i = c + Dir.vec(d)
				var other := board.at(n.x, n.y)
				if other != ArrowBoard.EMPTY and other != id and result.has(other):
					used[result[other]] = true
		var pick: Color = inks[id % inks.size()]
		for k in inks.size():
			var candidate: Color = inks[(id + k) % inks.size()]
			if not used.has(candidate):
				pick = candidate
				break
		result[id] = pick
	return result

func _layout() -> void:
	if board == null or size.x <= 0.0 or size.y <= 0.0:
		return
	var fit_w := (size.x - 8.0) / (board.width + PAD * 2.0)
	var fit_h := (size.y - 8.0) / (board.height + PAD * 2.0)
	cell = clampf(minf(fit_w, fit_h), MIN_CELL, MAX_CELL)
	if cell >= 12.0:
		cell = floorf(cell)
	_panel_size = (Vector2(board.width, board.height) + Vector2(PAD, PAD) * 2.0) * cell
	_base_offset = (size - _panel_size) * 0.5
	_arrows_root.position = Vector2(PAD, PAD) * cell
	_canvas.set_cell(cell)
	for id in _movers:
		(_movers[id] as ArrowView).set_cell_size(cell)
	_apply_transform()

## Zoom at which a cell is PLAY_CELL on screen (1.0 when the overview is already that big).
func play_zoom() -> float:
	return clampf(PLAY_CELL / maxf(1.0, cell), 1.0, max_zoom())

## Whether this board has a play zoom distinct from its overview.
func has_play_zoom() -> bool:
	return cell < READABLE_CELL and play_zoom() >= PLAY_GAIN

## The opening camera: the whole board stays in view for `hold` seconds, then the camera glides to
## the play zoom around the picture's center. A touch, pinch or camera button press during the hold
## cancels the glide (the player has taken the camera).
func overview_then_play(hold: float) -> void:
	_camera_serial += 1
	_user_camera = false
	var serial := _camera_serial
	await get_tree().create_timer(maxf(0.0, hold), false).timeout
	if serial != _camera_serial or _user_camera or board == null or zoom > 1.02 or not has_play_zoom():
		return
	animate_zoom(play_zoom(), null, 0.6)

## Camera button: overview ↔ play zoom (around the view center).
func toggle_camera() -> void:
	_user_camera = true
	_stop_fling()
	if zoom > 1.02:
		animate_zoom(1.0)
	else:
		# The same play zoom the opening glide uses; small boards without one still get 1.6x.
		animate_zoom(play_zoom() if has_play_zoom() else minf(1.6, max_zoom()))
		_report_zoom("button")

## Largest useful zoom: a cell reaches about fingertip size, never less than 1.6x.
func max_zoom() -> float:
	return clampf(ZOOM_CELL / maxf(1.0, cell), 1.6, 10.0)

func _apply_transform() -> void:
	_content.scale = Vector2(zoom, zoom)
	_content.position = _base_offset * zoom + _offset if zoom > 1.0 else _base_offset
	if zoom > 1.0:
		_content.position = _clamp_position(_content.position)
	_log_layout.call_deferred()

## Debug builds only: where the board sits on screen, so device QA scripts can tap real arrows.
func _log_layout() -> void:
	if not OS.is_debug_build() or board == null or not is_inside_tree():
		return
	var xform := get_global_transform_with_canvas()
	var origin: Vector2 = xform * (_content.position + _arrows_root.position * zoom)
	var window := Vector2(DisplayServer.window_get_size())
	var view := get_viewport().get_visible_rect().size
	Diagnostics.log_event("board", "layout", {"x": snappedf(origin.x, 0.01), "y": snappedf(origin.y, 0.01),
		"cell": snappedf(cell * zoom * xform.get_scale().x, 0.01), "screen_scale": snappedf(window.x / maxf(1.0, view.x), 0.0001),
		"w": board.width, "h": board.height})

func _clamp_position(pos: Vector2) -> Vector2:
	var scaled := _panel_size * zoom
	var result := pos
	for axis in 2:
		if scaled[axis] <= size[axis]:
			result[axis] = (size[axis] - scaled[axis]) * 0.5
		else:
			result[axis] = clampf(pos[axis], size[axis] - scaled[axis] - 24.0, 24.0)
	return result

## Sets zoom keeping the content point under `local_anchor` (view-local px) in place.
func _zoom_about(new_zoom: float, local_anchor: Vector2, content_point: Vector2) -> void:
	zoom = clampf(new_zoom, 1.0, max_zoom())
	if zoom <= 1.0001:
		zoom = 1.0
		_offset = Vector2.ZERO
		_apply_transform()
		return
	_content.scale = Vector2(zoom, zoom)
	_content.position = _clamp_position(local_anchor - content_point * zoom)
	_offset = _content.position - _base_offset * zoom
	_log_layout.call_deferred()

## Smoothly zooms to `target` around a canvas point (or the view center).
func animate_zoom(target: float, at_canvas: Variant = null, seconds_override: float = -1.0) -> void:
	if _zoom_tween != null and _zoom_tween.is_valid():
		_zoom_tween.kill()
	var local_anchor: Vector2 = size * 0.5 if at_canvas == null else get_global_transform_with_canvas().affine_inverse() * (at_canvas as Vector2)
	var content_point := (local_anchor - _content.position) / zoom
	var goal := clampf(target, 1.0, max_zoom())
	var seconds := 0.0 if SettingsManager.get_value("reduced_motion") else (0.28 if seconds_override < 0.0 else seconds_override)
	_zoom_tween = create_tween()
	_zoom_tween.tween_method(func(z: float): _zoom_about(z, local_anchor, content_point), zoom, goal, seconds) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_zoom_tween.tween_callback(func(): zoom_changed.emit(zoom > 1.02))

func reset_zoom() -> void:
	_stop_fling()
	if zoom <= 1.0:
		return
	animate_zoom(1.0)

## Pans (when zoomed in) so the arrow is fully on screen.
func focus_on(id: int) -> void:
	if zoom <= 1.02 or not arrows.has(id):
		return
	var rect := Rect2(Vector2(board.cells_of(id)[0]), Vector2.ONE)
	for c in board.cells_of(id):
		rect = rect.expand(Vector2(c)).expand(Vector2(c) + Vector2.ONE)
	var screen := Rect2(_content.position + (_arrows_root.position + rect.position * cell) * zoom, rect.size * cell * zoom)
	var view := Rect2(Vector2.ZERO, size).grow(-cell * zoom * 0.5)
	if view.encloses(screen):
		return
	var target := _clamp_position(_content.position + size * 0.5 - screen.get_center())
	var tween := create_tween()
	tween.tween_method(func(p: Vector2):
		_content.position = p
		_offset = p - _base_offset * zoom, _content.position, target, 0.0 if SettingsManager.get_value("reduced_motion") else 0.35) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _restyle_all() -> void:
	if board == null:
		return
	_configure_canvas()
	for id in _movers:
		(_movers[id] as ArrowView).set_cell_size(cell)

## Point under a viewport position, in board pixels (cell (0,0) corner at the origin).
func _board_point(viewport_pos: Vector2) -> Vector2:
	var local: Vector2 = get_global_transform_with_canvas().affine_inverse() * viewport_pos
	return (local - _content.position) / zoom - _arrows_root.position

## The arrow a touch selects: the one whose path passes closest to the finger within the touch
## radius; AMBIGUOUS when the finger is not squarely on one stroke and either two arrows are about
## equally close, or the closest arrow is blocked while a free arrow is nearly as close (the player
## probably meant the free one, so a blocked guess must not cost a heart); -1 for empty space.
## Moving arrows are ignored.
func pick(viewport_pos: Vector2) -> int:
	_last_candidates = []
	if board == null:
		return -1
	var p := _board_point(viewport_pos) / cell
	var screen_cell := maxf(1.0, cell * zoom)
	# Never below 0.6 cells, so a touch in the gap between two neighbouring strokes still reaches both.
	var radius := clampf(TOUCH_RADIUS / screen_cell, 0.6, 2.2)
	var tie := clampf(TIE_PX / screen_cell, 0.22, 0.6)
	var near := {}
	var cx := int(floor(p.x))
	var cy := int(floor(p.y))
	var span := int(ceil(radius))
	for y in range(cy - span, cy + span + 1):
		for x in range(cx - span, cx + span + 1):
			var id := board.at(x, y)
			if id != ArrowBoard.EMPTY and arrows.has(id):
				near[id] = true
	var ranked: Array = [] # [distance, id], closest first
	for id in near:
		var d := _distance_to_arrow(p, id)
		if d <= radius:
			ranked.append([d, id])
	if ranked.is_empty():
		return -1
	ranked.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var best: int = ranked[0][1]
	var best_d: float = ranked[0][0]
	# Squarely on a stroke (and big enough on screen to aim at) wins outright.
	if best_d <= WIDTH_HIT and screen_cell >= SQUARE_MIN_CELL:
		return best
	if ranked.size() >= 2 and float(ranked[1][0]) - best_d < tie:
		_last_candidates = [best, ranked[1][1]]
		return AMBIGUOUS
	if not board.can_escape(best):
		for k in range(1, ranked.size()):
			var other: int = ranked[k][1]
			if float(ranked[k][0]) - best_d < tie * 2.0 and board.can_escape(other):
				_last_candidates = [best, other]
				return AMBIGUOUS
	return best

const WIDTH_HIT := 0.3 # cells from the path's center line that count as touching the stroke

func _distance_to_arrow(p: Vector2, id: int) -> float:
	var cells := board.cells_of(id)
	var best := INF
	for i in range(1, cells.size()):
		var a := Vector2(cells[i - 1]) + Vector2(0.5, 0.5)
		var b := Vector2(cells[i]) + Vector2(0.5, 0.5)
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	# The head triangle reaches half a cell past the last center.
	var head := Vector2(cells[cells.size() - 1]) + Vector2(0.5, 0.5)
	var tip := head + Vector2(Dir.vec(board.dirs[id])) * 0.45
	best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, head, tip)))
	return best

func arrow_at(viewport_pos: Vector2) -> int:
	var id := pick(viewport_pos)
	return id if id >= 0 else -1

func cell_center(c: Vector2) -> Vector2:
	return _arrows_root.position + (c + Vector2(0.5, 0.5)) * cell

## Canvas position of a board cell center (for HUD effects that fly from the board).
func canvas_point(c: Vector2) -> Vector2:
	return get_global_transform_with_canvas() * (_content.position + cell_center(c) * zoom)

# --- input -------------------------------------------------------------------------------------

func _slop() -> float:
	return maxf(14.0, cell * zoom * 0.35)

func _on_pressed(pointer: int, at: Vector2) -> void:
	_touches[pointer] = at
	touched.emit()
	_user_camera = true
	_stop_fling()
	if _touches.size() == 1:
		var id := pick(at) if input_enabled else -1
		_press = {"pointer": pointer, "start": at, "id": id, "cancelled": false, "candidates": _last_candidates.duplicate()}
		if id >= 0:
			_emphasize(id, true)
			touch_down.emit(id)
	elif _touches.size() == 2:
		_cancel_press()
		var points: Array = _touches.values()
		_pinch = {"dist": maxf(1.0, (points[0] as Vector2).distance_to(points[1])), "mid": ((points[0] as Vector2) + points[1]) * 0.5,
			"zoom": zoom, "pos": _content.position}

func _on_dragged(pointer: int, at: Vector2, _delta: Vector2) -> void:
	if not _touches.has(pointer):
		return
	var previous: Vector2 = _touches[pointer]
	_touches[pointer] = at
	if _touches.size() >= 2 and not _pinch.is_empty():
		if _zoom_tween != null and _zoom_tween.is_valid():
			_zoom_tween.kill()
		var points: Array = _touches.values()
		var dist := (points[0] as Vector2).distance_to(points[1])
		var mid: Vector2 = ((points[0] as Vector2) + points[1]) * 0.5
		var local_mid: Vector2 = get_global_transform_with_canvas().affine_inverse() * mid
		var start_mid: Vector2 = get_global_transform_with_canvas().affine_inverse() * (_pinch["mid"] as Vector2)
		var anchor: Vector2 = (start_mid - (_pinch["pos"] as Vector2)) / float(_pinch["zoom"])
		_zoom_about(float(_pinch["zoom"]) * dist / float(_pinch["dist"]), local_mid, anchor)
		if zoom > 1.02:
			_report_zoom("pinch")
		zoom_changed.emit(zoom > 1.02)
		return
	if _press.is_empty() or int(_press["pointer"]) != pointer:
		return
	if not _press["cancelled"] and at.distance_to(_press["start"]) > _slop():
		_cancel_press()
	if _press["cancelled"] and zoom > 1.02:
		var scale_factor := get_global_transform_with_canvas().get_scale().x
		var step := (at - previous) / scale_factor
		_content.position = _clamp_position(_content.position + step)
		_offset = _content.position - _base_offset * zoom
		# Smoothed pan speed for the flick glide.
		var now := Time.get_ticks_msec()
		var dt := maxf(0.008, (now - _last_pan_ms) / 1000.0)
		_pan_velocity = _pan_velocity.lerp(step / dt, 0.45) if now - _last_pan_ms < 120 else step / dt
		_last_pan_ms = now

func _on_released(pointer: int, at: Vector2, displacement: Vector2, _seconds: float) -> void:
	_touches.erase(pointer)
	if _touches.size() < 2:
		_pinch = {}
	if _press.is_empty() or int(_press["pointer"]) != pointer:
		# The pressing finger may be gone already: a finger left over from a pinch keeps panning.
		if _press.is_empty() and _touches.size() == 1:
			_hand_off_press()
		_after_touches()
		return
	var id: int = _press["id"]
	var still: bool = not _press["cancelled"] and displacement.length() <= _slop()
	var candidates: Array = _press["candidates"]
	var panned: bool = _press["cancelled"]
	_emphasize(id, false)
	_press = {}
	if _touches.size() == 1:
		_hand_off_press()
	elif panned and _touches.is_empty() and zoom > 1.02 and Time.get_ticks_msec() - _last_pan_ms < 80 \
			and _pan_velocity.length() >= FLING_MIN_SPEED and not SettingsManager.get_value("reduced_motion"):
		_fling = _pan_velocity
		set_process(true)
	if still and input_enabled:
		if id >= 0:
			if pick(at) == id:
				tapped.emit(id)
		elif id == AMBIGUOUS:
			for other in candidates:
				_nod(int(other))
			touch_missed.emit("ambiguous")
		else:
			_empty_tap(at)
	_after_touches()

## After a pinch, the finger still down becomes a panning press (it can never tap).
func _hand_off_press() -> void:
	var remaining: int = _touches.keys()[0]
	_press = {"pointer": remaining, "start": _touches[remaining], "id": -1, "cancelled": true, "candidates": []}
	_last_pan_ms = 0

func _stop_fling() -> void:
	_fling = Vector2.ZERO
	_pan_velocity = Vector2.ZERO
	set_process(false)

func _process(delta: float) -> void:
	if _fling.length() < 30.0 or zoom <= 1.02:
		_stop_fling()
		return
	var before := _content.position
	_content.position = _clamp_position(_content.position + _fling * delta)
	_offset = _content.position - _base_offset * zoom
	# Stop against the edges instead of sliding along them forever.
	if _content.position.is_equal_approx(before):
		_stop_fling()
		return
	_fling *= exp(-FLING_DECAY * delta)

## Two quick taps on empty board space: zoom in there, or back out when already zoomed.
func _empty_tap(at: Vector2) -> void:
	var now := Time.get_ticks_msec()
	if now - int(_last_empty_tap["ms"]) <= DOUBLE_TAP_MS and at.distance_to(_last_empty_tap["at"]) <= DOUBLE_TAP_SLOP:
		_last_empty_tap = {"ms": -100000, "at": Vector2.ZERO}
		_user_camera = true
		if zoom > 1.05:
			animate_zoom(1.0, at)
		else:
			animate_zoom(maxf(play_zoom(), minf(2.0, max_zoom())), at)
			_report_zoom("double_tap")
		return
	_last_empty_tap = {"ms": now, "at": at}

func _report_zoom(method: String) -> void:
	if not _zoom_reported:
		_zoom_reported = true
		zoom_used.emit(method)

func _on_cancelled(pointer: int) -> void:
	_touches.erase(pointer)
	if not _press.is_empty() and int(_press["pointer"]) == pointer:
		_cancel_press()
		_press = {}
	_after_touches()

func _after_touches() -> void:
	if _touches.is_empty() and zoom > 1.0 and zoom < 1.08:
		reset_zoom()

func _cancel_press() -> void:
	if _press.is_empty():
		return
	_emphasize(int(_press["id"]), false)
	_press["cancelled"] = true

func cancel_input() -> void:
	_stop_fling()
	_pointer.cancel_all()
	_cancel_press()
	_press = {}
	_touches.clear()
	_pinch = {}

func _unhandled_input(event: InputEvent) -> void:
	# Desktop convenience: mouse wheel zoom.
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var local: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		if Rect2(Vector2.ZERO, size).has_point(local):
			_user_camera = true
			var anchor := (local - _content.position) / zoom
			_zoom_about(zoom * (1.12 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12), local, anchor)
			if zoom > 1.02:
				_report_zoom("wheel")
			zoom_changed.emit(zoom > 1.02)

func _emphasize(id: int, on: bool) -> void:
	if not arrows.has(id):
		return
	var overlay := _canvas.overlay
	if SettingsManager.get_value("reduced_motion"):
		overlay.set_value(id, "emph", 1.0 if on else 0.0)
		return
	var from: float = overlay.states.get(id, {}).get("emph", 0.0)
	var tween := create_tween()
	tween.tween_method(func(v: float): overlay.set_value(id, "emph", v), from, 1.0 if on else 0.0, 0.06 if on else 0.12)

## A short lift-and-settle on an arrow (ambiguous touch feedback).
func _nod(id: int) -> void:
	if not arrows.has(id):
		return
	var overlay := _canvas.overlay
	var tween := create_tween()
	tween.tween_method(func(v: float): overlay.set_value(id, "emph", v), 0.0, 0.7, 0.07)
	tween.tween_method(func(v: float): overlay.set_value(id, "emph", v), 0.7, 0.0, 0.2)

# --- motion ------------------------------------------------------------------------------------

## Seconds to travel `x` cells from rest with the shared speed profile.
static func travel_time(x: float) -> float:
	if x <= 0.0:
		return 0.0
	var x_acc := (VMAX * VMAX - V0 * V0) / (2.0 * ACCEL)
	if x <= x_acc:
		return (-V0 + sqrt(V0 * V0 + 2.0 * ACCEL * x)) / ACCEL
	return (VMAX - V0) / ACCEL + (x - x_acc) / VMAX

static func distance_at(t: float) -> float:
	var t_acc := (VMAX - V0) / ACCEL
	if t <= t_acc:
		return V0 * t + 0.5 * ACCEL * t * t
	return (VMAX * VMAX - V0 * V0) / (2.0 * ACCEL) + (t - t_acc) * VMAX

## Earliest start (ms) for a new move so its head never reaches a cell before an earlier move's
## tail has left it.
func _earliest_start(cells: Dictionary, length: int, now: int) -> int:
	var start := now
	for move in _moves:
		var finished: int = int(move["start_ms"]) + int(travel_time(float(move["distance"])) * 1000.0)
		if finished <= now:
			continue
		for c in cells:
			if not (move["cells"] as Dictionary).has(c):
				continue
			var k_other: int = move["cells"][c]
			var leaves: int = int(move["start_ms"]) + int(travel_time(k_other + 0.5) * 1000.0)
			var reach := travel_time(maxf(0.0, cells[c] - length - 0.45))
			start = maxi(start, leaves - int(reach * 1000.0) + int(CROSS_MARGIN_S * 1000.0))
	return start

## Plays a resolved escape. Returns seconds until the arrow has fully left.
func play_escape(event: Dictionary) -> float:
	var id: int = event["id"]
	if not arrows.has(id) and not _movers.has(id):
		return 0.0
	arrows.erase(id)
	if _bumps.has(id):
		(_bumps[id] as Tween).kill()
		_bumps.erase(id)
	if _movers.has(id):
		(_movers[id] as ArrowView).queue_free()
		_movers.erase(id)
	if id == _hint_id:
		clear_hint()
	var track: Array[Vector2i] = event["track"]
	var length: int = board.length(id)
	var own: Array[Vector2i] = track.slice(0, length)
	var view := ArrowView.new()
	_arrows_root.add_child(view)
	view.setup(id, own, board.dirs[id], cell, Scenery.GOLD if golden.has(id) else ArrowStyle.ESCAPE)
	view.extend_track(track)
	_movers[id] = view
	_canvas.hide_arrow(id)
	_canvas.vacate(own)
	var ray_len := track.size() - 2 * length - 1
	var distance := float(length + ray_len) + 1.0
	var cells := {}
	for i in track.size():
		if board.in_bounds(track[i].x, track[i].y):
			cells[track[i]] = i
	var now := Time.get_ticks_msec()
	var start := _earliest_start(cells, length, now)
	_moves = _moves.filter(func(m: Dictionary) -> bool: return int(m["start_ms"]) + int(travel_time(float(m["distance"])) * 1000.0) > now)
	_moves.append({"id": id, "start_ms": start, "cells": cells, "length": length, "distance": distance})
	var delay := (start - now) / 1000.0
	var reduced := bool(SettingsManager.get_value("reduced_motion"))
	var duration := travel_time(distance)
	var dir := Vector2(Dir.vec(board.dirs[id]))
	var edge_cell := Vector2(board.head(id)) + dir * (ray_len + 0.5)
	var edge := cell_center(edge_cell)
	var tween := view.create_tween()
	if delay > 0.0:
		tween.tween_interval(delay)
	if reduced:
		tween.tween_property(view, "modulate:a", 0.0, 0.12)
		duration = 0.12
	else:
		tween.tween_method(func(t: float): view.s = distance_at(t), 0.0, duration, duration)
	var exit_at := delay + (0.12 if reduced else travel_time(ray_len + 0.6))
	var puff := create_tween()
	puff.tween_interval(exit_at)
	puff.tween_callback(func():
		if golden.has(id):
			fx.gold_burst(edge, cell)
			gold_collected.emit(id, get_global_transform_with_canvas() * (_content.position + edge * zoom))
		elif not reduced:
			fx.exit_puff(edge, dir, cell))
	tween.tween_callback(func():
		_movers.erase(id)
		view.queue_free())
	return delay + duration

## Blocked: the arrow turns red, slides forward along its own path to the obstacle and springs back,
## and stays red until it leaves or the board ends, so wrong picks stay visible. The arrow in the way turns purple, and a
## dashed line runs from the head to the exact cell where it is hit, held long enough to read
## (longer for the first-HARD warning, `long_mark`).
func play_blocked(event: Dictionary, long_mark: bool = false) -> void:
	var id: int = event["id"]
	if not arrows.has(id):
		return
	if _bumps.has(id):
		(_bumps[id] as Tween).kill()
		_bumps.erase(id)
	if _movers.has(id):
		(_movers[id] as ArrowView).queue_free()
		_movers.erase(id)
	var gap: int = event["gap"]
	var dir := Vector2(Dir.vec(board.dirs[id]))
	var contact := cell_center(Vector2(board.head(id)) + dir * (gap + 0.5))
	var blocker: int = event["blocker"]
	var overlay := _canvas.overlay
	var hold := 2.6 if long_mark else 1.6
	# A wrong pick stays red until it leaves or the board ends.
	_canvas.wrong[id] = true
	_canvas.refresh()
	var tip := cell_center(Vector2(board.head(id))) + dir * cell * 0.45
	overlay.mark_block(id, blocker if arrows.has(blocker) else -1, tip, contact + dir * cell * 0.5, hold)
	if SettingsManager.get_value("reduced_motion"):
		fx.collision(contact, cell)
		return
	var cells := board.cells_of(id)
	var track := cells.duplicate()
	track.append_array(board.ray(id))
	var view := ArrowView.new()
	_arrows_root.add_child(view)
	view.setup(id, cells, board.dirs[id], cell, ArrowStyle.BLOCKED)
	view.extend_track(track)
	_movers[id] = view
	_canvas.held[id] = true
	_canvas.refresh()
	var reach := gap + 0.2
	var forward := clampf(0.06 + gap * 0.035, 0.06, 0.2)
	var tween := view.create_tween()
	tween.tween_method(func(v: float): view.s = v, 0.0, reach, forward).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func(): fx.collision(contact, cell))
	tween.tween_method(func(v: float): view.s = v, reach, 0.0, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.12)
	tween.tween_callback(func():
		_bumps.erase(id)
		_movers.erase(id)
		view.queue_free()
		_canvas.held.erase(id)
		_canvas.refresh())
	_bumps[id] = tween

func show_hint(id: int) -> void:
	clear_hint()
	if not arrows.has(id):
		return
	_hint_id = id
	var overlay := _canvas.overlay
	overlay.set_value(id, "glow", 1.0)
	focus_on(id)
	if SettingsManager.get_value("reduced_motion"):
		return
	_hint_tween = create_tween().set_loops()
	_hint_tween.tween_method(func(v: float): overlay.set_value(id, "glow", v), 1.0, 0.35, 0.6).set_trans(Tween.TRANS_SINE)
	_hint_tween.tween_method(func(v: float): overlay.set_value(id, "glow", v), 0.35, 1.0, 0.6).set_trans(Tween.TRANS_SINE)

func clear_hint() -> void:
	if _hint_tween != null and _hint_tween.is_valid():
		_hint_tween.kill()
	if _hint_id != -1:
		_canvas.overlay.set_value(_hint_id, "glow", 0.0)
	_hint_id = -1

## Small ring + sparkle where a streak milestone arrow left; no score text.
func streak_mark(at_cell: Vector2i, strength: int) -> void:
	fx.combo_burst(cell_center(Vector2(at_cell)), cell, strength)

func celebrate(cleared_cells: int, hard: bool = false) -> void:
	if SettingsManager.get_value("reduced_motion"):
		return
	var dots := _canvas.dots
	# Milestones answer in gold: a slower golden wave over the empty picture.
	dots.ripple_color = Scenery.GOLD if hard else ArrowStyle.ESCAPE
	var tween := create_tween()
	tween.tween_property(dots, "ripple", 1.2, 0.55 if not hard else 0.8).from(0.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(dots, "ripple", 0.0, 0.0)
	# Bigger boards get a little more confetti; small tutorial boards only the ripple and a few.
	var count := clampi(cleared_cells / 3, 6, 34) * (2 if hard else 1)
	fx.confetti(Rect2(Vector2.ZERO, _panel_size), cell, count)
	if hard:
		fx.gold_burst(_panel_size * 0.5, cell * 2.0)
