class_name MoveResolver
extends RefCounted
## Deterministic escape rules. A block escapes when every cell from it to the board edge in its
## arrow direction is empty. Otherwise it stays and the nearest live block on that path blocks it.

## Returns the nearest blocking block id, or BoardState.EMPTY when the path to the edge is clear.
static func first_obstacle(board: BoardState, id: int) -> int:
	var step := Dir.vec(board.dirs[id])
	var x := board.xs[id] + step.x
	var y := board.ys[id] + step.y
	while x >= 0 and y >= 0 and x < board.width and y < board.height:
		var other := board.grid[y * board.width + x]
		if other != BoardState.EMPTY:
			return other
		x += step.x
		y += step.y
	return BoardState.EMPTY

static func can_escape(board: BoardState, id: int) -> bool:
	return board.is_alive(id) and first_obstacle(board, id) == BoardState.EMPTY

## Number of empty cells between the block and its blocker (0 when adjacent).
static func gap_to(board: BoardState, id: int, blocker: int) -> int:
	return maxi(0, absi(board.xs[blocker] - board.xs[id]) + absi(board.ys[blocker] - board.ys[id]) - 1)

## Cells the block travels through before leaving the board.
static func exit_distance(board: BoardState, id: int) -> int:
	match board.dirs[id]:
		Dir.UP: return board.ys[id] + 1
		Dir.RIGHT: return board.width - board.xs[id]
		Dir.DOWN: return board.height - board.ys[id]
		_: return board.xs[id] + 1

static func escapable_ids(board: BoardState) -> PackedInt32Array:
	var result := PackedInt32Array()
	for id in board.alive.size():
		if board.alive[id] == 1 and first_obstacle(board, id) == BoardState.EMPTY:
			result.append(id)
	return result

## Applies one escape as a single logical action. Returns the ids whose arrows turned clockwise.
## Removed switch targets are skipped. Caller must check can_escape first.
static func apply_escape(board: BoardState, id: int) -> PackedInt32Array:
	assert(can_escape(board, id))
	board.remove(id)
	var rotated := PackedInt32Array()
	if board.kinds[id] == BoardState.KIND_SWITCH:
		for target in board.links[id]:
			if board.is_alive(target):
				board.dirs[target] = Dir.cw(board.dirs[target])
				rotated.append(target)
	return rotated

## Exact inverse of apply_escape for undo.
static func revert_escape(board: BoardState, id: int, rotated: PackedInt32Array) -> void:
	for target in rotated:
		board.dirs[target] = Dir.ccw(board.dirs[target])
	board.restore(id)

## Directions the switch would produce, for the press-and-hold preview. Does not mutate.
static func preview_rotation(board: BoardState, id: int) -> Dictionary:
	var result := {}
	if board.kinds[id] != BoardState.KIND_SWITCH:
		return result
	for target in board.links[id]:
		if board.is_alive(target):
			result[target] = Dir.cw(board.dirs[target])
	return result
