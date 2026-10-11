class_name ArrowBoard
extends RefCounted
## Rules "arrow-path-2". Each arrow is an ordered chain of orthogonally adjacent cells from tail to
## head. The head points along the last step of the chain. Pure data; views never own truth.
##
## Escape rule (path-following): the head moves straight ahead and the body follows the cells the
## head has already passed through, like one connected body. Therefore the arrow can leave the board
## exactly when every cell from the head to the board edge (the "ray") is empty. Because the body
## only ever re-enters cells the arrow itself occupied, nothing else is crossed while it moves.
## Levels never contain an arrow whose ray meets its own body (validated), so self-collision cannot
## occur during an escape.
const EMPTY := -1
const RULES := "arrow-path-2"

var width := 0
var height := 0
var paths: Array[PackedInt32Array] = [] # cell indices, tail → head
var dirs := PackedInt32Array()
var alive := PackedByteArray()
var grid := PackedInt32Array()
var alive_count := 0

static func from_level(level: Dictionary) -> ArrowBoard:
	var board := ArrowBoard.new()
	board.width = int(level["w"])
	board.height = int(level["h"])
	board.grid.resize(board.width * board.height)
	board.grid.fill(EMPTY)
	for flat in level["a"]:
		var cells: Array[Vector2i] = []
		for i in range(0, flat.size() - 1, 2):
			cells.append(Vector2i(int(flat[i]), int(flat[i + 1])))
		board.add_arrow(cells)
	return board

static func empty(w: int, h: int) -> ArrowBoard:
	var board := ArrowBoard.new()
	board.width = w
	board.height = h
	board.grid.resize(w * h)
	board.grid.fill(EMPTY)
	return board

## Adds an arrow (tail → head). Caller guarantees cells are free and adjacent.
func add_arrow(cells: Array[Vector2i]) -> int:
	assert(cells.size() >= 2)
	var id := paths.size()
	var packed := PackedInt32Array()
	for c in cells:
		assert(in_bounds(c.x, c.y) and grid[index(c.x, c.y)] == EMPTY)
		packed.append(index(c.x, c.y))
		grid[index(c.x, c.y)] = id
	paths.append(packed)
	dirs.append(direction_between(cells[cells.size() - 2], cells[cells.size() - 1]))
	alive.append(1)
	alive_count += 1
	return id

static func direction_between(from: Vector2i, to: Vector2i) -> int:
	var d := to - from
	for i in 4:
		if Dir.vec(i) == d:
			return i
	return -1

func size() -> int:
	return paths.size()

func index(x: int, y: int) -> int:
	return y * width + x

func cell(i: int) -> Vector2i:
	return Vector2i(i % width, i / width)

func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height

func at(x: int, y: int) -> int:
	return grid[index(x, y)] if in_bounds(x, y) else EMPTY

func is_alive(id: int) -> bool:
	return id >= 0 and id < alive.size() and alive[id] == 1

func length(id: int) -> int:
	return paths[id].size()

func head(id: int) -> Vector2i:
	return cell(paths[id][paths[id].size() - 1])

func cells_of(id: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for i in paths[id]:
		result.append(cell(i))
	return result

## Number of direction changes along the body.
func bends(id: int) -> int:
	var count := 0
	var cells := cells_of(id)
	for i in range(2, cells.size()):
		if cells[i] - cells[i - 1] != cells[i - 1] - cells[i - 2]:
			count += 1
	return count

func remove(id: int) -> void:
	assert(is_alive(id))
	for i in paths[id]:
		grid[i] = EMPTY
	alive[id] = 0
	alive_count -= 1

func restore(id: int) -> void:
	assert(not is_alive(id))
	for i in paths[id]:
		assert(grid[i] == EMPTY)
		grid[i] = id
	alive[id] = 1
	alive_count += 1

func is_cleared() -> bool:
	return alive_count == 0

func live_ids() -> PackedInt32Array:
	var result := PackedInt32Array()
	for id in alive.size():
		if alive[id] == 1:
			result.append(id)
	return result

func duplicate_board() -> ArrowBoard:
	var copy := ArrowBoard.new()
	copy.width = width
	copy.height = height
	copy.paths = paths.duplicate()
	copy.dirs = dirs.duplicate()
	copy.alive = alive.duplicate()
	copy.grid = grid.duplicate()
	copy.alive_count = alive_count
	return copy

func equals(other: ArrowBoard) -> bool:
	return width == other.width and height == other.height and paths == other.paths and alive == other.alive \
		and grid == other.grid and dirs == other.dirs

# --- rules ---------------------------------------------------------------------------------------

## Cells from the cell ahead of the head to the board edge.
func ray(id: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var step := Dir.vec(dirs[id])
	var c := head(id) + step
	while in_bounds(c.x, c.y):
		result.append(c)
		c += step
	return result

## Nearest occupied cell owner ahead of the head (may be the arrow itself for an invalid level),
## or EMPTY when the way out is clear.
func first_obstacle(id: int) -> int:
	var step := Dir.vec(dirs[id])
	var c := head(id) + step
	while c.x >= 0 and c.y >= 0 and c.x < width and c.y < height:
		var other := grid[c.y * width + c.x]
		if other != EMPTY:
			return other
		c += step
	return EMPTY

func can_escape(id: int) -> bool:
	return is_alive(id) and first_obstacle(id) == EMPTY

## Empty cells between the head and the first obstacle.
func gap_to_obstacle(id: int) -> int:
	var step := Dir.vec(dirs[id])
	var c := head(id) + step
	var gap := 0
	while in_bounds(c.x, c.y) and grid[index(c.x, c.y)] == EMPTY:
		gap += 1
		c += step
	return gap

func escapable_ids() -> PackedInt32Array:
	var result := PackedInt32Array()
	for id in alive.size():
		if alive[id] == 1 and first_obstacle(id) == EMPTY:
			result.append(id)
	return result

## The full track the arrow slides along when it leaves: its own cells (tail → head), then the ray,
## then `beyond` virtual cells past the edge so the tail fully exits. Cell coordinates (may be
## outside the board).
func escape_track(id: int, beyond: int) -> Array[Vector2i]:
	var track := cells_of(id)
	var step := Dir.vec(dirs[id])
	var c := head(id)
	for i in ray(id).size() + beyond:
		c += step
		track.append(c)
	return track
