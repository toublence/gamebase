class_name Silhouettes
extends RefCounted
## Original board outlines for Outtap levels. Every level uses a different picture so each new
## board reads as a new object. Shapes are built from simple primitives in normalized coordinates
## (u, v in [-1, 1], v pointing down) and rasterized onto the level grid, then cleaned so every
## kept cell has at least two neighbours (arrows need two cells) and only the largest connected
## region remains.
##
## Ops: ["+"|"-", kind, ...] applied in order. Kinds:
##   "ellipse" cx cy rx ry | "circle" cx cy r | "rect" x0 y0 x1 y1 | "poly" [x, y, x, y, ...]
const SHAPES := {
	"pebble": [["+", "ellipse", 0.0, 0.0, 1.0, 1.0], ["+", "rect", -0.85, -0.7, 0.85, 0.7]],
	"leaf": [["+", "poly", [0.0, -1.0, 0.75, -0.45, 0.9, 0.15, 0.55, 0.7, 0.0, 0.95, -0.55, 0.7, -0.9, 0.15, -0.75, -0.45]],
		["-", "rect", -0.06, 0.55, 0.06, 1.0]],
	"cloud": [["+", "circle", -0.45, 0.2, 0.55], ["+", "circle", 0.1, -0.15, 0.65], ["+", "circle", 0.55, 0.25, 0.48],
		["+", "rect", -0.9, 0.2, 0.95, 0.72]],
	"sailboat": [["+", "poly", [-0.95, 0.45, 0.95, 0.45, 0.6, 0.95, -0.6, 0.95]], ["+", "poly", [0.1, -1.0, 0.1, 0.4, 0.92, 0.4]],
		["+", "poly", [-0.1, -0.72, -0.1, 0.4, -0.8, 0.4]], ["+", "rect", -0.12, -1.0, 0.12, 0.5]],
	"fish": [["+", "ellipse", -0.2, 0.0, 0.72, 0.62], ["+", "poly", [0.35, 0.0, 1.0, -0.6, 1.0, 0.6]], ["-", "circle", -0.55, -0.18, 0.1]],
	"lighthouse": [["+", "poly", [-0.32, -0.62, 0.32, -0.62, 0.48, 0.72, -0.48, 0.72]], ["+", "rect", -0.42, -0.86, 0.42, -0.62],
		["+", "poly", [-0.25, -1.0, 0.25, -1.0, 0.0, -1.0]], ["+", "rect", -0.95, 0.72, 0.95, 1.0], ["+", "rect", -0.22, -1.0, 0.22, -0.86]],
	"crescent": [["+", "circle", 0.0, 0.0, 1.0], ["-", "circle", 0.42, -0.25, 0.78]],
	"star": [["+", "poly", [0.0, -1.0, 0.24, -0.33, 0.95, -0.31, 0.38, 0.12, 0.59, 0.81, 0.0, 0.4, -0.59, 0.81, -0.38, 0.12, -0.95, -0.31, -0.24, -0.33]]],
	"mountain": [["+", "poly", [-1.0, 1.0, -0.35, -0.55, 0.0, 0.0, 0.35, -0.95, 1.0, 1.0]]],
	"whale": [["+", "ellipse", -0.1, 0.15, 0.85, 0.55], ["+", "poly", [0.55, 0.0, 1.0, -0.65, 0.95, -0.15, 1.0, 0.35]],
		["+", "rect", -0.95, 0.15, 0.6, 0.7], ["-", "circle", -0.55, 0.0, 0.08]],
	"mushroom": [["+", "ellipse", 0.0, -0.3, 1.0, 0.62], ["-", "rect", -1.0, -0.05, 1.0, 1.0], ["+", "rect", -0.32, -0.08, 0.32, 1.0],
		["+", "rect", -0.95, -0.3, 0.95, -0.02]],
	"apple": [["+", "circle", -0.3, 0.15, 0.68], ["+", "circle", 0.3, 0.15, 0.68], ["+", "rect", -0.08, -1.0, 0.1, -0.5],
		["+", "ellipse", 0.32, -0.78, 0.3, 0.14]],
	"house": [["+", "poly", [-1.0, -0.15, 0.0, -1.0, 1.0, -0.15]], ["+", "rect", -0.78, -0.2, 0.78, 1.0], ["-", "rect", -0.18, 0.45, 0.18, 1.0]],
	"tree": [["+", "circle", 0.0, -0.35, 0.68], ["+", "circle", -0.45, 0.05, 0.5], ["+", "circle", 0.45, 0.05, 0.5],
		["+", "rect", -0.16, 0.3, 0.16, 1.0], ["+", "rect", -0.6, 0.85, 0.6, 1.0]],
	"bird": [["+", "ellipse", 0.0, 0.15, 0.72, 0.55], ["+", "circle", 0.55, -0.35, 0.35], ["+", "poly", [0.85, -0.42, 1.0, -0.3, 0.85, -0.22]],
		["+", "poly", [-0.55, 0.0, -1.0, -0.4, -0.95, 0.25]], ["-", "circle", 0.6, -0.42, 0.07]],
	"anchor": [["+", "ellipse", 0.0, 0.3, 0.98, 0.68], ["-", "ellipse", 0.0, 0.12, 0.62, 0.55], ["+", "rect", -0.22, -0.72, 0.22, 0.98],
		["+", "circle", 0.0, -0.78, 0.3], ["-", "circle", 0.0, -0.78, 0.11], ["+", "rect", -0.62, -0.5, 0.62, -0.28]],
	"heart": [["+", "circle", -0.48, -0.38, 0.55], ["+", "circle", 0.48, -0.38, 0.55], ["+", "poly", [-1.0, -0.22, 1.0, -0.22, 0.0, 1.0]]],
	"rocket": [["+", "ellipse", 0.0, -0.1, 0.42, 0.9], ["+", "poly", [-0.42, 0.25, -0.85, 0.95, -0.3, 0.65]],
		["+", "poly", [0.42, 0.25, 0.85, 0.95, 0.3, 0.65]], ["-", "circle", 0.0, -0.35, 0.14]],
	"turtle": [["+", "ellipse", 0.0, 0.05, 0.78, 0.6], ["+", "circle", 0.0, -0.7, 0.28], ["+", "circle", -0.72, -0.4, 0.2],
		["+", "circle", 0.72, -0.4, 0.2], ["+", "circle", -0.72, 0.55, 0.2], ["+", "circle", 0.72, 0.55, 0.2]],
	"cat": [["+", "ellipse", 0.0, 0.2, 0.9, 0.75], ["+", "poly", [-0.85, -0.05, -0.75, -1.0, -0.2, -0.45]],
		["+", "poly", [0.85, -0.05, 0.75, -1.0, 0.2, -0.45]], ["-", "circle", -0.35, 0.1, 0.1], ["-", "circle", 0.35, 0.1, 0.1]],
	"key": [["+", "circle", 0.0, -0.55, 0.45], ["-", "circle", 0.0, -0.55, 0.18], ["+", "rect", -0.14, -0.15, 0.14, 1.0],
		["+", "rect", 0.0, 0.45, 0.48, 0.6], ["+", "rect", 0.0, 0.78, 0.38, 0.93]],
	"wave": [["+", "func_wave"]],
	"ring": [["+", "ellipse", 0.0, 0.0, 1.0, 1.0], ["-", "ellipse", 0.0, 0.0, 0.42, 0.38]],
}

## Rasterized, cleaned mask (1 = cells arrows may use).
static func mask(shape: String, w: int, h: int) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(w * h)
	var ops: Array = SHAPES.get(shape, [["+", "rect", -1.0, -1.0, 1.0, 1.0]])
	for y in h:
		for x in w:
			var u := ((x + 0.5) / w) * 2.0 - 1.0
			var v := ((y + 0.5) / h) * 2.0 - 1.0
			var inside := false
			for op in ops:
				if _hit(op, u, v):
					inside = op[0] == "+"
			result[y * w + x] = 1 if inside else 0
	return _clean(result, w, h)

static func _hit(op: Array, u: float, v: float) -> bool:
	match str(op[1]):
		"ellipse":
			var dx := (u - float(op[2])) / float(op[4])
			var dy := (v - float(op[3])) / float(op[5])
			return dx * dx + dy * dy <= 1.0
		"circle":
			return Vector2(u - float(op[2]), v - float(op[3])).length() <= float(op[4])
		"rect":
			return u >= float(op[2]) and v >= float(op[3]) and u <= float(op[4]) and v <= float(op[5])
		"poly":
			var pts: Array = op[2]
			var polygon := PackedVector2Array()
			for i in range(0, pts.size(), 2):
				polygon.append(Vector2(float(pts[i]), float(pts[i + 1])))
			return Geometry2D.is_point_in_polygon(Vector2(u, v), polygon)
		"func_wave":
			return absf(v - sin(u * 3.0) * 0.32) < 0.62
	return false

## Drops cells that cannot host an arrow end-to-end and keeps the largest connected region.
static func _clean(source: PackedByteArray, w: int, h: int) -> PackedByteArray:
	var m := source.duplicate()
	var changed := true
	while changed:
		changed = false
		for y in h:
			for x in w:
				if m[y * w + x] == 0:
					continue
				var n := 0
				for d in 4:
					var c := Vector2i(x, y) + Dir.vec(d)
					if c.x >= 0 and c.y >= 0 and c.x < w and c.y < h and m[c.y * w + c.x] == 1:
						n += 1
				if n < 1 or (n < 2 and _row_or_col_alone(m, x, y, w, h)):
					m[y * w + x] = 0
					changed = true
	var best := PackedInt32Array()
	var seen := PackedByteArray()
	seen.resize(w * h)
	for start in w * h:
		if m[start] == 0 or seen[start] == 1:
			continue
		var region := PackedInt32Array([start])
		seen[start] = 1
		var i := 0
		while i < region.size():
			var c := region[i]
			i += 1
			for d in 4:
				var n := Vector2i(c % w, c / w) + Dir.vec(d)
				if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h:
					continue
				var ni := n.y * w + n.x
				if m[ni] == 1 and seen[ni] == 0:
					seen[ni] = 1
					region.append(ni)
		if region.size() > best.size():
			best = region
	var out := PackedByteArray()
	out.resize(w * h)
	for c in best:
		out[c] = 1
	return out

## A one-neighbour cell at the tip of a one-cell-wide spike.
static func _row_or_col_alone(m: PackedByteArray, x: int, y: int, w: int, h: int) -> bool:
	var count := 0
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var cx: int = x + dx
			var cy: int = y + dy
			if cx >= 0 and cy >= 0 and cx < w and cy < h and m[cy * w + cx] == 1:
				count += 1
	return count <= 1

static func cell_count(mask_data: PackedByteArray) -> int:
	var n := 0
	for v in mask_data:
		n += v
	return n
