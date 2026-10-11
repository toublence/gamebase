class_name SwitchSolver
extends RefCounted
## Exhaustive solver for the switch ruleset. Positions never move, so the remaining-block set fully
## determines every arrow (a live block was turned once per fired switch linked to it).
## A search that exceeds the state budget reports unknown, never solvable.
const DEFAULT_BUDGET := 250000

var _board: BoardState
var _win := {} # alive mask -> probability that uniformly random legal play clears from here
var _next := {} # alive mask -> a move on a winning line, or -1 for dead states
var _visited := 0
var _budget := DEFAULT_BUDGET
var exhausted := false

static func mask_of(board: BoardState) -> int:
	var mask := 0
	for id in board.alive.size():
		if board.alive[id] == 1:
			mask |= 1 << id
	return mask

## Returns {status: "solvable"|"unsolvable"|"unknown", solution, states, dead_states,
## random_win, first_moves, trap_first_moves}.
static func analyze(source: BoardState, budget: int = DEFAULT_BUDGET) -> Dictionary:
	assert(source.size() <= 60)
	var solver := SwitchSolver.new()
	solver._board = source.duplicate_board()
	solver._budget = budget
	var start := mask_of(solver._board)
	var p: float = solver._explore(start)
	if solver.exhausted:
		return {"status": "unknown", "solution": PackedInt32Array(), "states": solver._visited}
	var dead := 0
	for value in solver._next.values():
		if value == -1:
			dead += 1
	var first_moves := MoveResolver.escapable_ids(solver._board)
	var traps := 0
	for id in first_moves:
		if solver._next.get(start & ~(1 << id), -1) == -1 and (start & ~(1 << id)) != 0:
			traps += 1
	return {
		"status": "solvable" if solver._next.get(start, -1) != -1 or start == 0 else "unsolvable",
		"solution": solver._line(start), "states": solver._next.size(), "dead_states": dead,
		"random_win": snappedf(p, 0.0001), "first_moves": first_moves.size(), "trap_first_moves": traps,
	}

## Next move on a winning line from the given live state, -1 if the state cannot be cleared,
## -2 if the search was too large to decide.
static func next_move(source: BoardState, budget: int = DEFAULT_BUDGET) -> int:
	var solver := SwitchSolver.new()
	solver._board = source.duplicate_board()
	solver._budget = budget
	var start := mask_of(solver._board)
	solver._explore(start)
	if solver.exhausted:
		return -2
	return solver._next.get(start, -1)

func _explore(mask: int) -> float:
	if _win.has(mask):
		return _win[mask]
	if mask == 0:
		_win[mask] = 1.0
		_next[mask] = -3 # cleared marker; never read as a move
		return 1.0
	_visited += 1
	if _visited > _budget:
		exhausted = true
		return 0.0
	var moves := MoveResolver.escapable_ids(_board)
	if moves.is_empty():
		_win[mask] = 0.0
		_next[mask] = -1
		return 0.0
	var total := 0.0
	var best := -1
	for id in moves:
		var rotated := MoveResolver.apply_escape(_board, id)
		var child := mask & ~(1 << id)
		var p := _explore(child)
		MoveResolver.revert_escape(_board, id, rotated)
		if exhausted:
			return 0.0
		total += p
		if best == -1 and (child == 0 or _next.get(child, -1) != -1):
			best = id
	var result := total / moves.size()
	_win[mask] = result
	_next[mask] = best
	return result

func _line(start: int) -> PackedInt32Array:
	var line := PackedInt32Array()
	var mask := start
	while mask != 0:
		var move: int = _next.get(mask, -1)
		if move < 0:
			return PackedInt32Array()
		line.append(move)
		mask &= ~(1 << move)
	return line
