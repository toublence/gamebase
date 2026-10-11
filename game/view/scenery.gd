class_name Scenery
extends RefCounted
## The three original scenes behind the board — Soft Morning, Sunset Flow and Night Harbor. A scene
## sets the sky, the board panel, the text that sits directly on the sky ("hud") and which ink set
## the arrows use so they stay readable on that board. Each level names its scene ("theme" in the
## level data); the player can keep "auto" (follow the level) or pin one unlocked scene.
##
## Arrows are drawn in one ink (the maze look). The scene gives the classic ink; a skin (a personal-
## league reward) swaps it for its own "ink" pair [on light scenes, on the night scene]. The optional
## "arrow_colors" setting uses the skin's full light/dark sets, one color per arrow.
## Coral (mistakes) and gold (golden arrows) are reserved and never used as inks.
const ORDER := ["morning", "sunset", "harbor"]
const AUTO := "auto"
const SCENES := {
	"morning": {"name": "SCENE_MORNING", "dark": false,
		"sky": ["FBE6D1", "F8EEE3", "DDECEE"], "glow": "FFE1AE", "deco": "FFFFFF",
		"board": "FCF7EE", "board_edge": "E3D3B9", "dot": "D9C9AE", "shadow": "6B5232", "ink": "5A4029",
		"hud_ink": "263252", "hud_soft": "5B6580"},
	"sunset": {"name": "SCENE_SUNSET", "dark": false,
		"sky": ["FCDDBE", "F5BDAA", "B8A2D4"], "glow": "FFF0D2", "deco": "FFE3CC",
		"board": "FFF8F2", "board_edge": "E9CBBB", "dot": "E2BFB0", "shadow": "5E3446", "ink": "4E2A42",
		"hud_ink": "3A2340", "hud_soft": "6A4F6C"},
	"harbor": {"name": "SCENE_HARBOR", "dark": true,
		"sky": ["0A1430", "122449", "1B3A5F"], "glow": "F4E9C8", "deco": "FFE9A8",
		"board": "16253F", "board_edge": "0A1426", "dot": "2E4A72", "shadow": "000000", "ink": "E4ECFA",
		"hud_ink": "EEF3FF", "hud_soft": "A8B5D6"},
}
## First campaign stage whose clear unlocks pinning the scene (it already shows on its own levels).
const UNLOCK := {"morning": 0, "sunset": 4, "harbor": 0}
## The default look: the night scene (dark backdrop, light maze ink), chosen after play testing.
const DEFAULT := "harbor"

const SKIN_ORDER := ["classic", "candy", "ocean", "neon", "aurora"]
const SKINS := {
	"classic": {"name": "SKIN_CLASSIC", "tier": 0,
		"light": ["26365A", "1F8079", "7B3F6E", "B4532E", "557A2B", "3E63B8", "6A4FA3", "7A5534"],
		"dark": ["F3EFE4", "6FE3D2", "FF8DB3", "93B4FF", "B5EB8D", "FFA66B", "CFA4FF", "7FD0FF"]},
	"candy": {"name": "SKIN_CANDY", "tier": 1, "ink": ["B5375E", "FF8FB1"],
		"light": ["D9466F", "2E9CCB", "E07A2C", "7457CF", "24A174", "C9449F", "4A6FE3", "8F5B3A"],
		"dark": ["FF7FA3", "6CCBF2", "FFB070", "B49CFF", "6FE0B2", "FF8AD8", "8FA9FF", "E7C9A9"]},
	"ocean": {"name": "SKIN_OCEAN", "tier": 2, "ink": ["1D5C8A", "8ED1FC"],
		"light": ["0F4C75", "1B7F99", "3282B8", "136F63", "2A9D8F", "264653", "4A7FB0", "5E60CE"],
		"dark": ["8ED1FC", "6FE3D2", "A0C4FF", "9BF6FF", "56CFE1", "BDE0FE", "72EFDD", "CDB4DB"]},
	"neon": {"name": "SKIN_NEON", "tier": 3, "ink": ["6A1FD1", "5CF2B5"],
		"light": ["E0005F", "7A2FE0", "2F74F0", "05936E", "E04E00", "B0003A", "6A0DAD", "0077B6"],
		"dark": ["FF4D9D", "B388FF", "5CC8FF", "45F59A", "FF9F43", "F72585", "4CC9F0", "C3F73A"]},
	"aurora": {"name": "SKIN_AURORA", "tier": 4, "ink": ["2D6A4F", "B7E4C7"],
		"light": ["2D6A4F", "40916C", "5E548E", "8E6FB8", "3D5A80", "52796F", "6D597A", "355070"],
		"dark": ["95D5B2", "B7E4C7", "CDB4DB", "A2D2FF", "BDB2FF", "80FFDB", "E0AAFF", "64DFDF"]},
}
const GOLD := Color("E9B23A")
const GOLD_LIGHT := Color("FFE6A0")
const CORAL := Color("E2654B")

static var _cache := {}

## Parsed colors of a scene: every hex string becomes a Color; "sky" stays a 3-color array.
static func scene(id: String) -> Dictionary:
	var key := id if SCENES.has(id) else "morning"
	if not _cache.has(key):
		var source: Dictionary = SCENES[key]
		var result := {"id": key}
		for field in source:
			var value: Variant = source[field]
			if value is Array:
				var colors: Array[Color] = []
				for hex in value:
					colors.append(Color(str(hex)))
				result[field] = colors
			elif value is String and field != "name":
				result[field] = Color(str(value))
			else:
				result[field] = value
		_cache[key] = result
	return _cache[key]

## The scene a level shows: the player's pinned scene when unlocked, otherwise the level's own.
static func for_level(level: Dictionary) -> String:
	var choice := Progress.scene_choice()
	if choice != AUTO and Progress.has_scene(choice):
		return choice
	var own := str(level.get("theme", "morning"))
	return own if SCENES.has(own) else "morning"

## Scene for screens without a level (home, stage list): the pinned scene, or the next stage's.
static func for_menu() -> String:
	var choice := Progress.scene_choice()
	if choice != AUTO and Progress.has_scene(choice):
		return choice
	var next := Levels.campaign(Progress.reached()) if Levels.campaign_count() > 0 else {}
	var own := str(next.get("theme", "morning"))
	# The night scene is kept for play; menus stay on a light scene unless the player pins it.
	return "morning" if own == "harbor" or not SCENES.has(own) else own

## The single maze ink for a scene and the selected skin.
static func ink(scene_id: String, skin_id: String = "") -> Color:
	var skin: Dictionary = SKINS.get(skin_id if not skin_id.is_empty() else Progress.skin(), SKINS["classic"])
	var s := scene(scene_id)
	if skin.has("ink"):
		return Color(str(skin["ink"][1 if bool(s["dark"]) else 0]))
	return s["ink"]

static func inks(scene_id: String, skin_id: String = "") -> Array[Color]:
	var skin_key := skin_id if not skin_id.is_empty() else Progress.skin()
	var skin: Dictionary = SKINS.get(skin_key, SKINS["classic"])
	var variant := "dark" if bool(scene(scene_id)["dark"]) else "light"
	var cache_key := "%s|%s" % [skin_key, variant]
	if not _cache.has(cache_key):
		var colors: Array[Color] = []
		for hex in skin[variant]:
			colors.append(Color(str(hex)))
		_cache[cache_key] = colors
	return _cache[cache_key]
