class_name BoardState
extends RefCounted
## Pure, deterministic board data. Views read it; they never own puzzle truth.
## Blocks are addressed by their index in the level data. A cell holds -1 or one live block.
const EMPTY := -1
const KIND_NORMAL := 0
const KIND_SWITCH := 1

var width := 0
var height := 0
var xs := PackedInt32Array()
var ys := PackedInt32Array()
var dirs := PackedInt32Array()
var kinds := PackedInt32Array()
var alive := PackedByteArray()
var links: Array[PackedInt32Array] = []
var grid := PackedInt32Array()
var alive_count := 0

static func from_level(level: Dictionary) -> BoardState:
	var board := BoardState.new()
	board.width = int(level["w"])
	board.height = int(level["h"])
	board.grid.resize(board.width * board.height)
	board.grid.fill(EMPTY)
	for entry in level["b"]:
		board.add_block(int(entry[0]), int(entry[1]), int(entry[2]),
			int(entry[3]) if entry.size() > 3 else KIND_NORMAL,
			PackedInt32Array(entry[4]) if entry.size() > 4 else PackedInt32Array())
	return board

static func empty(w: int, h: int) -> BoardState:
	var board := BoardState.new()
	board.width = w
	board.height = h
	board.grid.resize(w * h)
	board.grid.fill(EMPTY)
	return board

func add_block(x: int, y: int, d: int, kind: int = KIND_NORMAL, targets: PackedInt32Array = PackedInt32Array()) -> int:
	assert(in_bounds(x, y) and grid[index(x, y)] == EMPTY and d >= 0 and d < 4)
	var id := xs.size()
	xs.append(x)
	ys.append(y)
	dirs.append(d)
	kinds.append(kind)
	alive.append(1)
	links.append(targets)
	grid[index(x, y)] = id
	alive_count += 1
	return id

func size() -> int:
	return xs.size()

func index(x: int, y: int) -> int:
	return y * width + x

func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height

func is_alive(id: int) -> bool:
	return id >= 0 and id < alive.size() and alive[id] == 1

func at(x: int, y: int) -> int:
	return grid[index(x, y)] if in_bounds(x, y) else EMPTY

func cell_of(id: int) -> Vector2i:
	return Vector2i(xs[id], ys[id])

func remove(id: int) -> void:
	assert(is_alive(id))
	alive[id] = 0
	grid[index(xs[id], ys[id])] = EMPTY
	alive_count -= 1

func restore(id: int) -> void:
	assert(not is_alive(id) and grid[index(xs[id], ys[id])] == EMPTY)
	alive[id] = 1
	grid[index(xs[id], ys[id])] = id
	alive_count += 1

func is_cleared() -> bool:
	return alive_count == 0

func live_ids() -> PackedInt32Array:
	var result := PackedInt32Array()
	for id in alive.size():
		if alive[id] == 1:
			result.append(id)
	return result

func duplicate_board() -> BoardState:
	var copy := BoardState.new()
	copy.width = width
	copy.height = height
	copy.xs = xs.duplicate()
	copy.ys = ys.duplicate()
	copy.dirs = dirs.duplicate()
	copy.kinds = kinds.duplicate()
	copy.alive = alive.duplicate()
	copy.links = links.duplicate()
	copy.grid = grid.duplicate()
	copy.alive_count = alive_count
	return copy

## Stable textual fingerprint of the live state (positions never change; only life and direction do).
func state_key() -> String:
	var parts := PackedStringArray()
	for id in alive.size():
		parts.append(str(dirs[id]) if alive[id] == 1 else "x")
	return "".join(parts)

func equals(other: BoardState) -> bool:
	return width == other.width and height == other.height and xs == other.xs and ys == other.ys \
		and kinds == other.kinds and alive == other.alive and grid == other.grid \
		and state_key() == other.state_key()
