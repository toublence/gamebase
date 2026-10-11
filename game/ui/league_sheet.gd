class_name LeagueSheet
extends ModalView
## The personal weekly league. It says plainly that there are no other players: the ladder shows
## the five tiers with their fixed goal lines, where the player stands this week, last week's result
## and best week, how points are earned and which arrow colors each tier unlocks.

func _ready() -> void:
	super._ready()
	var p := Palette.colors()
	var lg := Progress.league()
	body.add_child(Design.title("LEAGUE_TITLE", 28))
	var honest := Design.label("LEAGUE_HONEST", 15, true, 650)
	body.add_child(honest)
	var bar := LeagueBar.new()
	body.add_child(bar)
	var left := LeagueRules.seconds_left(int(Time.get_unix_time_from_system()))
	var ends := Design.label(tr("LEAGUE_ENDS_IN") % [left / 86400, (left % 86400) / 3600], 15, true, 650)
	ends.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(ends)
	# Ladder: top tier first.
	var ladder := Design.column(6)
	body.add_child(ladder)
	var last: Dictionary = lg["last"]
	for tier in range(LeagueRules.TOP, -1, -1):
		ladder.add_child(_rung(tier, tier == int(lg["tier"]), not last.is_empty() and int(last.get("tier_after", -1)) == tier,
			tier == int(lg["best_tier"])))
	var record := Design.row(10)
	record.alignment = BoxContainer.ALIGNMENT_CENTER
	if not last.is_empty():
		record.add_child(Widgets.pill(tr("LEAGUE_LAST_WEEK_POINTS") % int(last.get("points", 0)), Color(p["muted"], 0.16), p["ink"], 14))
	record.add_child(Widgets.pill(tr("LEAGUE_BEST_POINTS") % int(lg["best_points"]), Color(p["gold"], 0.18), p["ink"], 14))
	body.add_child(record)
	body.add_child(Design.label("LEAGUE_HOW_TITLE", 18, false, 800))
	for line in ["LEAGUE_HOW_GOLD", "LEAGUE_HOW_HARD", "LEAGUE_HOW_PERFECT", "LEAGUE_HOW_FIRST", "LEAGUE_HOW_WEEKLY"]:
		body.add_child(Design.label(line, 15, true, 650))
	body.add_child(Design.label("LEAGUE_REWARDS_TITLE", 18, false, 800))
	var rewards := HFlowContainer.new()
	rewards.add_theme_constant_override("h_separation", 8)
	rewards.add_theme_constant_override("v_separation", 8)
	for skin_id in Scenery.SKIN_ORDER:
		var tier := int(Scenery.SKINS[skin_id]["tier"])
		if tier == 0:
			continue
		var owned := Progress.has_skin(skin_id)
		var text := tr("LEAGUE_REWARD_SKIN") % [tr(LeagueRules.tier_name(tier)), tr(Scenery.SKINS[skin_id]["name"])]
		rewards.add_child(Widgets.pill(text, Color(LeagueRules.tier_color(tier), 0.22 if owned else 0.1), p["ink"] if owned else p["muted"], 14))
	body.add_child(rewards)
	body.add_child(Design.button("CLOSE", close))

func _rung(tier: int, current: bool, last_week: bool, best: bool) -> Control:
	var p := Palette.colors()
	var panel := PanelContainer.new()
	var style := Design.box(Color(LeagueRules.tier_color(tier), 0.18) if current else Color(p["face"], 0.6), 14, 0, Color.TRANSPARENT, 8.0)
	if current:
		style.border_width_left = 3
		style.border_color = LeagueRules.tier_color(tier)
	panel.add_theme_stylebox_override("panel", style)
	var row := Design.row(10)
	panel.add_child(row)
	var medal := LeagueMedal.new()
	medal.tier = tier
	medal.custom_minimum_size = Vector2(34, 34)
	medal.dim = tier > int(Progress.league()["best_tier"])
	row.add_child(medal)
	var name := Design.label(LeagueRules.tier_name(tier), 17, false, 800)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name)
	var rules := ""
	if tier < LeagueRules.TOP:
		rules = tr("LEAGUE_RULE_PROMOTE") % LeagueRules.PROMOTE[tier]
	if LeagueRules.KEEP[tier] > 0:
		rules += ("  ·  " if not rules.is_empty() else "") + tr("LEAGUE_RULE_KEEP") % LeagueRules.KEEP[tier]
	var rule_label := Design.label(rules, 13, true, 650)
	rule_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rule_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(rule_label)
	if current:
		row.add_child(Widgets.pill("LEAGUE_YOU", LeagueRules.tier_color(tier), Color.WHITE, 13))
	elif last_week:
		row.add_child(Widgets.pill("LEAGUE_LAST_WEEK", Color(p["muted"], 0.2), p["ink"], 13))
	elif best and tier > int(Progress.league()["tier"]):
		row.add_child(Widgets.pill("LEAGUE_BEST", Color(p["gold"], 0.2), p["ink"], 13))
	return panel

## Last week's settled result, shown once on the home screen.
static func show_week_result(result: Dictionary) -> void:
	var modal := ModalView.new()
	UI.push_modal(modal)
	var body := modal.body
	body.add_child(Design.title("LEAGUE_WEEK_RESULT", 26))
	var medal := LeagueMedal.new()
	medal.tier = int(result.get("tier_after", 0))
	medal.custom_minimum_size = Vector2(84, 84)
	body.add_child(Widgets.centered(medal))
	var key := "LEAGUE_RESULT_DROPPED" if str(result.get("result", "")) == "dropped" else "LEAGUE_RESULT_KEPT"
	var tier_name := String(TranslationServer.translate(LeagueRules.tier_name(int(result.get("tier_after", 0)))))
	var line := Design.label(String(TranslationServer.translate(key)) % tier_name, 19, false, 800)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(line)
	var points := Design.label(String(TranslationServer.translate("LEAGUE_LAST_WEEK_POINTS")) % int(result.get("points", 0)), 16, true, 650)
	points.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(points)
	body.add_child(Design.button("OK", modal.close))
