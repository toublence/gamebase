class_name LevelData
extends RefCounted
## Level dictionaries as stored in game/data/*.json:
## {id, seed, gen, rules, w, h, b: [[x, y, dir, kind?, [targets]?]], sol, m, hash}
const RULES_BASIC := "basic-1"
const RULES_SWITCH := "switch-1"

static func canonical(level: Dictionary) -> String:
	var parts := PackedStringArray()
	for entry in level["b"]:
		var kind := int(entry[3]) if entry.size() > 3 else 0
		var targets := PackedStringArray()
		if entry.size() > 4:
			for t in entry[4]:
				targets.append(str(int(t)))
		parts.append("%d,%d,%d,%d,%s" % [int(entry[0]), int(entry[1]), int(entry[2]), kind, ".".join(targets)])
	return "%s|%d|%d|%s" % [str(level.get("rules", RULES_BASIC)), int(level["w"]), int(level["h"]), ";".join(parts)]

static func content_hash(level: Dictionary) -> String:
	return canonical(level).sha256_text().substr(0, 16)

## Parses an authoring grid. Tokens are separated by spaces; "." is empty.
## Arrow ^ > v < followed by an uppercase letter marks a switch with that label; lowercase letters
## link the block to the switches with the matching labels. Example: ">A . va" — switch A turns the
## down arrow.
static func parse_ascii(text: String) -> Dictionary:
	var rows: Array[PackedStringArray] = []
	for raw in text.strip_edges().split("\n"):
		var line := raw.strip_edges()
		if line.is_empty():
			continue
		rows.append(line.split(" ", false))
	var h := rows.size()
	var w := rows[0].size() if h > 0 else 0
	var blocks: Array = []
	var switch_ids := {}
	var wanted: Array = [] # [block id, labels]
	for y in h:
		assert(rows[y].size() == w, "ragged authoring row %d" % y)
		for x in w:
			var token: String = rows[y][x]
			if token == ".":
				continue
			var d := Dir.from_symbol(token.substr(0, 1))
			assert(d >= 0, "bad token " + token)
			var id := blocks.size()
			var kind := 0
			var labels := ""
			for c in token.substr(1):
				if c == c.to_upper():
					kind = BoardState.KIND_SWITCH
					switch_ids[c] = id
				else:
					labels += c.to_upper()
			blocks.append([x, y, d, kind, []])
			if not labels.is_empty():
				wanted.append([id, labels])
	for pair in wanted:
		for label in pair[1]:
			assert(switch_ids.has(label), "unknown switch label " + label)
			blocks[switch_ids[label]][4].append(pair[0])
	for entry in blocks:
		if entry[3] == 0:
			entry.resize(3)
	return {"w": w, "h": h, "b": blocks}

static func to_ascii(level: Dictionary) -> String:
	var board := BoardState.from_level(level)
	var lines := PackedStringArray()
	for y in board.height:
		var row := PackedStringArray()
		for x in board.width:
			var id := board.at(x, y)
			row.append("." if id == BoardState.EMPTY else Dir.SYMBOLS[board.dirs[id]])
		lines.append(" ".join(row))
	return "\n".join(lines)
