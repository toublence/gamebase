class_name Prng
extends RefCounted
## Mulberry32. Engine RandomNumberGenerator is not used for content so that a seed produces the
## same board on every Godot version and in the Python cross-check (tools/validate_levels.py).
const MASK := 0xFFFFFFFF
var state := 0

func _init(seed_value: int = 0) -> void:
	state = seed_value & MASK

func next_u32() -> int:
	state = (state + 0x6D2B79F5) & MASK
	var t := state
	t = _imul(t ^ (t >> 15), t | 1)
	t ^= (t + _imul(t ^ (t >> 7), t | 61)) & MASK
	return (t ^ (t >> 14)) & MASK

func next_float() -> float:
	return float(next_u32()) / 4294967296.0

## Uniform integer in [0, n).
func below(n: int) -> int:
	return int(next_float() * n) if n > 0 else 0

func range_int(low: int, high: int) -> int:
	return low + below(high - low + 1)

func chance(p: float) -> bool:
	return next_float() < p

func pick_weighted(weights: PackedFloat32Array) -> int:
	var total := 0.0
	for w in weights:
		total += w
	if total <= 0.0:
		return -1
	var roll := next_float() * total
	for i in weights.size():
		roll -= weights[i]
		if roll < 0.0:
			return i
	return weights.size() - 1

static func _imul(a: int, b: int) -> int:
	# 32-bit multiply with wraparound, matching JavaScript Math.imul and the Python mirror.
	# Split into 16-bit halves so the intermediate never overflows a signed 64-bit int.
	a &= MASK
	b &= MASK
	var a_lo := a & 0xFFFF
	var b_lo := b & 0xFFFF
	var cross := ((a >> 16) * b_lo + a_lo * (b >> 16)) & 0xFFFF
	return ((cross << 16) + a_lo * b_lo) & MASK

## Derives an independent stream seed from a base seed and a label (FNV-1a over UTF-8).
static func derive(base: int, label: String) -> int:
	var h := (0x811C9DC5 ^ (base & MASK)) & MASK
	for byte in label.to_utf8_buffer():
		h = ((h ^ byte) * 0x01000193) & MASK
	return h
