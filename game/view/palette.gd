class_name Palette
extends RefCounted
## Interface colors (cards, buttons, text on cards). Scenes behind the board and the arrow inks live
## in Scenery. "coral" is reserved for mistakes and hearts so it never means anything else.
const THEMES := {
	"paper": {"name": "THEME_PAPER", "bg": "F5EFE4", "bg_deep": "ECE3D3", "board": "EAE0CF", "board_line": "DBCDB5",
		"dot": "CDBEA4", "face": "FFFCF6", "side": "D3C4AA", "ink": "23314A", "ink_soft": "56607A", "muted": "8C8676",
		"accent": "1E8A84", "accent_deep": "13675F", "accent_soft": "D2ECE8", "switch_face": "E2F2EF",
		"coral": "E2654B", "coral_soft": "F9D9D0", "gold": "DDA22E", "shadow": "5A4526"},
}
## Board pattern and block detail per campaign chapter (1-based). Switch and daily use their own.
const CHAPTERS := [
	{"pattern": "dots", "detail": "plain"},
	{"pattern": "grid", "detail": "bevel"},
	{"pattern": "hatch", "detail": "corners"},
	{"pattern": "rings", "detail": "double"},
	{"pattern": "stars", "detail": "sheen"},
]
const SWITCH_STYLE := {"pattern": "grid", "detail": "bevel"}
const DAILY_STYLE := {"pattern": "rings", "detail": "plain"}

static var _cache := {}

static func colors(theme_id: String = "") -> Dictionary:
	var id := theme_id if THEMES.has(theme_id) else _current_id()
	if not _cache.has(id):
		var result := {}
		var source: Dictionary = THEMES[id]
		for key in source:
			if key != "name":
				result[key] = Color(str(source[key]))
		result["name"] = source["name"]
		_cache[id] = result
	return _cache[id]

static func c(key: String) -> Color:
	return colors()[key]

static func _current_id() -> String:
	return "paper"

static func chapter_style(chapter: int) -> Dictionary:
	return CHAPTERS[clampi(chapter, 1, CHAPTERS.size()) - 1]
