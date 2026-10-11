class_name LeagueBar
extends VBoxContainer
## The personal league at a glance: tier medal and name, this week's points, a progress bar toward
## the next tier and one line saying what the bar means.
var _medal: LeagueMedal
var _name: Label
var _points: Label
var _bar: ProgressBar
var _note: Label
var _fill: StyleBoxFlat

func _ready() -> void:
	add_theme_constant_override("separation", 8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := Design.row(12)
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	_medal = LeagueMedal.new()
	_medal.custom_minimum_size = Vector2(52, 52)
	top.add_child(_medal)
	var names := Design.column(0)
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(names)
	_name = Design.label("", 20, false, 800)
	_name.autowrap_mode = TextServer.AUTOWRAP_OFF
	names.add_child(_name)
	_points = Design.label("", 15, true, 650)
	_points.autowrap_mode = TextServer.AUTOWRAP_OFF
	names.add_child(_points)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(0, 16)
	_bar.show_percentage = false
	_bar.max_value = 1.0
	_bar.step = 0.001
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := Design.box(Color(Palette.c("muted"), 0.22), 8, 0, Color.TRANSPARENT, 0.0)
	_fill = Design.box(LeagueRules.tier_color(0), 8, 0, Color.TRANSPARENT, 0.0)
	_bar.add_theme_stylebox_override("background", back)
	_bar.add_theme_stylebox_override("fill", _fill)
	add_child(_bar)
	_note = Design.label("", 15, true, 650)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_note)
	refresh(false)

## Reads the current league state from Progress. `from_progress` (0..1) animates the bar from there.
func refresh(animate: bool = true, from_progress: float = -1.0) -> void:
	if _bar == null:
		return
	var lg := Progress.league()
	var tier := int(lg["tier"])
	_medal.tier = tier
	_name.text = tr(LeagueRules.tier_name(tier))
	_points.text = tr("LEAGUE_POINTS_WEEK") % int(lg["points"])
	_fill.bg_color = LeagueRules.tier_color(tier)
	var goal := Progress.league_goal()
	if tier >= LeagueRules.TOP:
		_note.text = tr("LEAGUE_TOP_KEEP") % LeagueRules.KEEP[tier]
	else:
		_note.text = tr("LEAGUE_TO_NEXT") % [goal, tr(LeagueRules.tier_name(tier + 1))]
	var target := Progress.league_progress()
	if animate and from_progress >= 0.0 and not SettingsManager.get_value("reduced_motion"):
		_bar.value = from_progress
		var tween := create_tween()
		tween.tween_property(_bar, "value", target, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		_bar.value = target
