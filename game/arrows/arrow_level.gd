class_name ArrowLevel
extends RefCounted
## Level schema 2 for rules "arrow-path-2":
##   {id, schema: 2, rules: "arrow-path-2", w, h, a: [[x0, y0, x1, y1, ...] tail → head, ...],
##    sol: [arrow ids in a valid removal order], m: {metrics}, hash, seed, gen, tag, coach?, soft?}
## Legacy single-tile levels (rules "basic-1" / "switch-1") are a different schema and are never
## interpreted by these rules.
const SCHEMA := 2
const MOVES := {"U": Vector2i(0, -1), "R": Vector2i(1, 0), "D": Vector2i(0, 1), "L": Vector2i(-1, 0)}

## Authoring: one arrow per token "x,y:MOVES" — tail cell then the moves toward the head, e.g.
## "1,5:UUURR" starts at (1,5), goes up three cells and right two; the head points right.
static func parse_authoring(w: int, h: int, tokens: PackedStringArray) -> Dictionary:
	var arrows: Array = []
	for token in tokens:
		var parts := token.strip_edges().split(":")
		var start := parts[0].split(",")
		var c := Vector2i(int(start[0]), int(start[1]))
		var flat: Array = [c.x, c.y]
		for move in parts[1]:
			c += MOVES[move]
			flat.append(c.x)
			flat.append(c.y)
		arrows.append(flat)
	return {"w": w, "h": h, "a": arrows, "rules": ArrowBoard.RULES, "schema": SCHEMA}

static func to_authoring(level: Dictionary) -> PackedStringArray:
	var tokens := PackedStringArray()
	for flat in level["a"]:
		var moves := ""
		for i in range(2, flat.size() - 1, 2):
			var d := Vector2i(int(flat[i]) - int(flat[i - 2]), int(flat[i + 1]) - int(flat[i - 1]))
			for key in MOVES:
				if MOVES[key] == d:
					moves += key
		tokens.append("%d,%d:%s" % [int(flat[0]), int(flat[1]), moves])
	return tokens

static func canonical(level: Dictionary) -> String:
	var parts := PackedStringArray()
	for flat in level["a"]:
		var values := PackedStringArray()
		for v in flat:
			values.append(str(int(v)))
		parts.append(".".join(values))
	return "%s|%d|%d|%s" % [ArrowBoard.RULES, int(level["w"]), int(level["h"]), ";".join(parts)]

static func content_hash(level: Dictionary) -> String:
	return canonical(level).sha256_text().substr(0, 16)

## Structural rules every bundled level must satisfy. Returns human-readable problems.
static func check_structure(level: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if str(level.get("rules", "")) != ArrowBoard.RULES:
		errors.append("rules must be %s" % ArrowBoard.RULES)
		return errors
	var w := int(level.get("w", 0))
	var h := int(level.get("h", 0))
	if w < 3 or h < 3 or w > 80 or h > 100:
		errors.append("board %dx%d out of range" % [w, h])
		return errors
	var arrows: Array = level.get("a", [])
	if arrows.is_empty():
		errors.append("no arrows")
	var owner := {}
	for id in arrows.size():
		var flat: Array = arrows[id]
		if flat.size() < 4 or flat.size() % 2 != 0:
			errors.append("arrow %d needs at least two cells" % id)
			continue
		var cells: Array[Vector2i] = []
		for i in range(0, flat.size(), 2):
			cells.append(Vector2i(int(flat[i]), int(flat[i + 1])))
		for i in cells.size():
			var c := cells[i]
			if c.x < 0 or c.y < 0 or c.x >= w or c.y >= h:
				errors.append("arrow %d leaves the board at %s" % [id, c])
			if owner.has(c):
				errors.append("arrow %d overlaps arrow %d at %s" % [id, owner[c], c])
			owner[c] = id
			if i > 0 and absi(c.x - cells[i - 1].x) + absi(c.y - cells[i - 1].y) != 1:
				errors.append("arrow %d is not a connected path at %s" % [id, c])
	if not errors.is_empty():
		return errors
	# A head whose way out runs through its own body could never leave; such arrows are not allowed.
	var board := ArrowBoard.from_level(level)
	for id in board.size():
		for c in board.ray(id):
			if board.at(c.x, c.y) == id:
				errors.append("arrow %d points into its own body" % id)
				break
	return errors

## Plain-text picture for reviews: each arrow gets a letter; heads are drawn as ^ > v <.
static func to_text(level: Dictionary) -> String:
	var board := ArrowBoard.from_level(level)
	var letters := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	var lines := PackedStringArray()
	for y in board.height:
		var row := ""
		for x in board.width:
			var id := board.at(x, y)
			if id == ArrowBoard.EMPTY:
				row += " ."
			elif board.head(id) == Vector2i(x, y):
				row += " " + Dir.SYMBOLS[board.dirs[id]]
			else:
				row += " " + letters[id % letters.length()]
		lines.append(row)
	return "\n".join(lines)
