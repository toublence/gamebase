class_name Dir
extends RefCounted
## Grid directions in clockwise order, so a 90° clockwise turn is (d + 1) % 4.
## Puzzle directions are absolute screen directions and never mirror for RTL locales.
const UP := 0
const RIGHT := 1
const DOWN := 2
const LEFT := 3
const VECTORS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const SYMBOLS := ["^", ">", "v", "<"]

static func vec(d: int) -> Vector2i:
	return VECTORS[d]

static func cw(d: int) -> int:
	return (d + 1) % 4

static func ccw(d: int) -> int:
	return (d + 3) % 4

static func angle(d: int) -> float:
	# Art is authored pointing up.
	return d * PI * 0.5

static func from_symbol(symbol: String) -> int:
	return SYMBOLS.find(symbol)
