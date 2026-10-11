class_name ArrowCanvas
extends Node2D
## Draws every resting arrow of a board in one pass (so a 300-arrow maze costs one canvas item), and
## owns two helper layers: Dots under the arrows (a faint dot in every empty picture cell; cells an
## arrow just left flash green and fade, so the picture visibly wears away) and Overlay above them
## (only the few arrows in a special state: hint glow, pressed, blocked flash, golden). The base layer
## redraws only when the board changes; the overlay redraws while its states animate.
var board: ArrowBoard
var cell := 20.0
var ink := Color.BLACK
var inks := {} # arrow id -> Color when per-arrow colors are on; empty = one ink
var gold := {} # arrow id -> true
var held := {} # arrow id -> true while a moving ArrowView draws it
## Arrows tapped while blocked in this attempt: drawn red until they leave or the board ends.
var wrong := {} # arrow id -> true
## Board color: a thin cut-out around every head so heads stand clear of neighbouring lines.
var halo := Color(0, 0, 0, 0)
var overlay: Overlay
var dots: Dots

func _init() -> void:
	dots = Dots.new()
	overlay = Overlay.new()
	overlay.canvas = self
	dots.canvas = self

## Call after adding to the tree: the helper layers become siblings below/above this node.
func attach(parent: Node) -> void:
	parent.add_child(dots)
	parent.add_child(self)
	parent.add_child(overlay)

func configure(level_board: ArrowBoard, cell_size: float, ink_color: Color, colors: Dictionary, golden: Dictionary,
		mask: PackedByteArray, dot_color: Color) -> void:
	board = level_board
	cell = cell_size
	ink = ink_color
	inks = colors
	gold = golden
	held.clear()
	dots.mask = mask
	dots.dot_color = dot_color
	dots.fresh.clear()
	overlay.clear_states()
	refresh()

func set_cell(cell_size: float) -> void:
	cell = cell_size
	refresh()

func set_position_all(pos: Vector2) -> void:
	position = pos
	dots.position = pos
	overlay.position = pos

func refresh() -> void:
	queue_redraw()
	dots.queue_redraw()
	overlay.queue_redraw()

func color_of(id: int) -> Color:
	if wrong.has(id):
		return ArrowStyle.BLOCKED
	if gold.has(id):
		return Scenery.GOLD
	return inks.get(id, ink)

func hide_arrow(id: int) -> void:
	held[id] = true
	overlay.erase(id)
	refresh()

## Cells an arrow just left start their green fade.
func vacate(cells: Array[Vector2i]) -> void:
	var now := Time.get_ticks_msec()
	for c in cells:
		dots.fresh[c] = now
	dots.set_process(true)

func _draw() -> void:
	if board == null:
		return
	for id in board.live_ids():
		if held.has(id) or gold.has(id):
			continue
		ArrowStyle.draw(self, ArrowStyle.points_of(board.cells_of(id), cell), Vector2(Dir.vec(board.dirs[id])), cell, color_of(id),
			1.0, halo)

class Overlay:
	extends Node2D
	var canvas: ArrowCanvas
	var states := {} # arrow id -> {glow, emph, flash}
	## The latest blocked tap: {tapped, blocker, from, to (board px), until_ms, fade_ms}; empty when none.
	var block := {}
	var _time := 0.0

	func clear_states() -> void:
		states.clear()
		block = {}
		queue_redraw()

	## Shows the wrongly tapped arrow in red and the arrow in its way in purple, with the dashed
	## path from the tapped head (`from`) to the cell it hits (`to`), for `hold` seconds, then fades.
	func mark_block(tapped: int, blocker: int, from: Vector2, to: Vector2, hold: float) -> void:
		var now := Time.get_ticks_msec()
		block = {"tapped": tapped, "blocker": blocker, "from": from, "to": to, "until_ms": now + int(hold * 1000.0), "fade_ms": 450}
		set_process(true)
		queue_redraw()

	func _block_strength() -> float:
		if block.is_empty():
			return 0.0
		var now := Time.get_ticks_msec()
		var left := int(block["until_ms"]) - now
		if left >= 0:
			return 1.0
		return clampf(1.0 + float(left) / float(block["fade_ms"]), 0.0, 1.0)

	func erase(id: int) -> void:
		states.erase(id)
		queue_redraw()

	func set_value(id: int, key: String, value: float) -> void:
		var state: Dictionary = states.get(id, {"glow": 0.0, "emph": 0.0, "flash": 0.0})
		state[key] = value
		if state["glow"] <= 0.001 and state["emph"] <= 0.001 and state["flash"] <= 0.001:
			states.erase(id)
		else:
			states[id] = state
		queue_redraw()

	func _ready() -> void:
		set_process(true)

	func _process(delta: float) -> void:
		_time += delta
		if not block.is_empty():
			if _block_strength() <= 0.0:
				block = {}
			queue_redraw()
		# Golden arrows shimmer; redraw a few times a second only while some are left.
		if canvas != null and canvas.board != null and not canvas.gold.is_empty() and not SettingsManager.get_value("reduced_motion"):
			if fmod(_time, 1.0 / 30.0) < delta:
				queue_redraw()

	func _draw() -> void:
		if canvas == null or canvas.board == null:
			return
		var board := canvas.board
		var cell := canvas.cell
		var strength := _block_strength()
		var blocker := int(block.get("blocker", -1)) if strength > 0.0 else -1
		var tapped := int(block.get("tapped", -1)) if strength > 0.0 else -1
		if blocker != -1 and board.is_alive(blocker) and not canvas.held.has(blocker):
			ArrowStyle.draw_glow(self, ArrowStyle.points_of(board.cells_of(blocker), cell), cell, Color(ArrowStyle.BLOCKER, 0.42 * strength))
		if tapped != -1 and board.is_alive(tapped) and not canvas.held.has(tapped):
			ArrowStyle.draw_glow(self, ArrowStyle.points_of(board.cells_of(tapped), cell), cell, Color(ArrowStyle.BLOCKED, 0.42 * strength))
		for id in canvas.gold:
			if not board.is_alive(id) or canvas.held.has(id):
				continue
			var points := ArrowStyle.points_of(board.cells_of(id), cell)
			var pulse := 0.5 + 0.5 * sin(_time * 3.0 + id)
			ArrowStyle.draw_glow(self, points, cell, Color(Scenery.GOLD, 0.16 + 0.12 * pulse))
		for id in states:
			if not board.is_alive(id) or canvas.held.has(id):
				continue
			var state: Dictionary = states[id]
			var points := ArrowStyle.points_of(board.cells_of(id), cell)
			if state["glow"] > 0.001:
				ArrowStyle.draw_glow(self, points, cell, Color(ArrowStyle.HINT, 0.5 * state["glow"]))
		for id in canvas.gold:
			if board.is_alive(id) and not canvas.held.has(id) and not states.has(id):
				var points := ArrowStyle.points_of(board.cells_of(id), cell)
				ArrowStyle.draw(self, points, Vector2(Dir.vec(board.dirs[id])), cell, canvas.color_of(id), 1.2, canvas.halo)
		for id in states:
			if not board.is_alive(id) or canvas.held.has(id):
				continue
			var state: Dictionary = states[id]
			var base := canvas.color_of(id)
			var color := base.lerp(ArrowStyle.BLOCKED, clampf(state["flash"], 0.0, 1.0))
			if state["glow"] > 0.001:
				color = color.lerp(ArrowStyle.HINT.darkened(0.25), 0.55 * state["glow"])
			var thick: float = 1.0 + 0.5 * float(state["emph"]) + (0.2 if canvas.gold.has(id) else 0.0)
			ArrowStyle.draw(self, ArrowStyle.points_of(board.cells_of(id), cell), Vector2(Dir.vec(board.dirs[id])), cell, color, thick,
				canvas.halo)
		if blocker != -1 and board.is_alive(blocker) and not canvas.held.has(blocker) and not states.has(blocker):
			ArrowStyle.draw(self, ArrowStyle.points_of(board.cells_of(blocker), cell), Vector2(Dir.vec(board.dirs[blocker])), cell,
				canvas.color_of(blocker).lerp(ArrowStyle.BLOCKER, strength), 1.25, canvas.halo)
		if tapped != -1 and board.is_alive(tapped) and not canvas.held.has(tapped) and not states.has(tapped):
			ArrowStyle.draw(self, ArrowStyle.points_of(board.cells_of(tapped), cell), Vector2(Dir.vec(board.dirs[tapped])), cell,
				canvas.color_of(tapped).lerp(ArrowStyle.BLOCKED, strength), 1.15, canvas.halo)
		if strength > 0.0:
			_draw_block_path(cell, strength)

	## Red dashed line from the tapped head to the hit point, and a purple ring on the arrow in the way.
	func _draw_block_path(cell: float, strength: float) -> void:
		var from: Vector2 = block["from"]
		var to: Vector2 = block["to"]
		var color := Color(ArrowStyle.BLOCKED, 0.9 * strength)
		var w := maxf(2.0, cell * 0.11)
		if from.distance_to(to) > 1.0:
			draw_dashed_line(from, to, color, w, maxf(4.0, cell * 0.28), true, true)
		draw_arc(to, maxf(5.0, cell * 0.34), 0.0, TAU, 28, Color(ArrowStyle.BLOCKER, 0.95 * strength), w, true)

class Dots:
	extends Node2D
	const FADE_MS := 900.0
	var canvas: ArrowCanvas
	var mask := PackedByteArray()
	var dot_color := Color(0.8, 0.75, 0.65)
	var fresh := {} # Vector2i -> ms the cell was vacated
	var ripple_color := ArrowStyle.ESCAPE
	var ripple := 0.0:
		set(value):
			ripple = value
			queue_redraw()

	func _ready() -> void:
		set_process(false)

	func _process(_delta: float) -> void:
		var now := Time.get_ticks_msec()
		for c in fresh.keys():
			if now - int(fresh[c]) > FADE_MS:
				fresh.erase(c)
		queue_redraw()
		if fresh.is_empty():
			set_process(false)

	func _draw() -> void:
		if canvas == null or canvas.board == null:
			return
		var board := canvas.board
		var cell := canvas.cell
		var now := Time.get_ticks_msec()
		var w := board.width
		var reach := Vector2(board.width, board.height).length() * 0.5
		var center := Vector2(board.width, board.height) * 0.5
		var radius := maxf(1.0, cell * 0.07)
		var lift_any := ripple > 0.0
		for y in board.height:
			for x in w:
				if not mask.is_empty() and mask[y * w + x] == 0:
					continue
				var occupant := board.at(x, y)
				if occupant != ArrowBoard.EMPTY and not canvas.held.has(occupant):
					continue
				var c := Vector2i(x, y)
				var color := dot_color
				var r := radius
				if fresh.has(c):
					var t := clampf((now - int(fresh[c])) / FADE_MS, 0.0, 1.0)
					color = ArrowStyle.ESCAPE.lerp(dot_color, t)
					r = radius * (1.9 - 0.9 * t)
				if ripple > 0.0:
					var lift := clampf(1.0 - absf((Vector2(c) + Vector2(0.5, 0.5)).distance_to(center) / reach - ripple) * 5.0, 0.0, 1.0)
					color = color.lerp(ripple_color, lift)
					r *= 1.0 + lift
				var at := (Vector2(c) + Vector2(0.5, 0.5)) * cell
				if fresh.has(c) or lift_any:
					draw_circle(at, r, color, true, -1.0, true)
				else:
					# Thousands of resting dots: two triangles each, not a 64-point circle.
					draw_rect(Rect2(at - Vector2(r, r), Vector2(r, r) * 2.0), color)
