class_name Grades
extends RefCounted
## Difficulty grades. Every stage is harder than the one before it; the grade names the band a stage
## belongs to (stages 5-9 HARD, 10-14 EXPERT, 15-19 MASTER, 20 LEGEND). The first stage of a grade
## is a milestone (level "hard": intro plate, HARD music, league bonus).
const NAMES := ["", "HARD", "EXPERT", "MASTER", "LEGEND"]
const PLATES := ["2A1B4D", "2A1B4D", "4A1530", "0F2E3D", "3B2A05"]
const EDGES := ["150D2B", "150D2B", "2A0A1B", "071A24", "1E1502"]
const INK := Color("FFD36B")

static func of(level: Dictionary) -> int:
	return clampi(int(level.get("grade", 1 if level.get("hard", false) else 0)), 0, NAMES.size() - 1)

static func name_of(level: Dictionary) -> String:
	return NAMES[of(level)]

static func plate(grade: int) -> Color:
	return Color(PLATES[clampi(grade, 0, PLATES.size() - 1)])

static func edge(grade: int) -> Color:
	return Color(EDGES[clampi(grade, 0, EDGES.size() - 1)])
