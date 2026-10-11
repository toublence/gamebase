class_name Story
extends RefCounted
## Chapter 1, "Pathfinder of Lumen Bay" (original story). A storm tangled the wind-arrows that guide
## Lumen Bay, and the town's treasures got caught inside knots of arrows. The player, apprentice to
## Grandma Moa the lighthouse keeper, frees one treasure per stage; each cleared stage returns that
## piece to the town (shown in the town view), and the lighthouse shines again after the final knot.
##
## Beats are short cards shown once: before stages 5, 10, 15 and 20, and after stage 20. The opening
## ("intro") is never in the way of the first board: the rules are taught by playing stage 1, and
## the opening can be read any time from the town sheet.
const SPEAKER := "STORY_MOA"
const BEATS := {
	"intro": ["STORY_INTRO_1", "STORY_INTRO_2", "STORY_INTRO_3"],
	"grade_1": ["STORY_HARD_1", "STORY_HARD_2"],
	"grade_2": ["STORY_EXPERT_1", "STORY_EXPERT_2"],
	"grade_3": ["STORY_MASTER_1", "STORY_MASTER_2"],
	"grade_4": ["STORY_LEGEND_1", "STORY_LEGEND_2"],
	"ending": ["STORY_END_1", "STORY_END_2", "STORY_END_3"],
}
## The treasure each stage frees (stage 1 first).
const PIECES := ["OBJ_SIGN", "OBJ_LANE", "OBJ_FISH", "OBJ_STAR", "OBJ_APPLE", "OBJ_MUSHROOM", "OBJ_WHALE",
	"OBJ_LIGHTHOUSE", "OBJ_ANCHOR", "OBJ_CAT", "OBJ_SAILBOAT", "OBJ_HILL", "OBJ_TURTLE", "OBJ_CLOUD", "OBJ_LEAF",
	"OBJ_HOUSE", "OBJ_WAVE", "OBJ_TREE", "OBJ_BEACH", "OBJ_HEART"]

## The beat to show before starting `index`, or "" (already seen or none).
static func beat_before(index: int, level: Dictionary) -> String:
	var beat := ""
	if bool(level.get("hard", false)) and index > 1:
		beat = "grade_%d" % clampi(int(level.get("grade", 1)), 1, 4)
	if beat.is_empty() or Progress.story_seen(beat):
		return ""
	return beat

static func piece(index: int) -> String:
	return PIECES[clampi(index, 1, PIECES.size()) - 1]
