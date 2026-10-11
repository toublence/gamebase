class_name HeartsView
extends HBoxContainer
## Hearts for the current board. Lost hearts stay visible as outlines so the count is readable
## without color.
var _hearts: Array[TextureRect] = []
var _shown := -1

func _ready() -> void:
	add_theme_constant_override("separation", 4)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in ArrowSession.MAX_LIVES:
		var heart := Widgets.texture("heart", 30, Palette.c("coral"))
		heart.pivot_offset = Vector2(15, 15)
		_hearts.append(heart)
		add_child(heart)
	Progress.theme_changed.connect(_on_theme_changed)

func _on_theme_changed(_id: String) -> void:
	set_lives(_shown, false)

func set_lives(lives: int, animate: bool = true) -> void:
	var p := Palette.colors()
	for i in _hearts.size():
		var full := i < lives
		_hearts[i].texture = Widgets.icon("heart" if full else "heart_empty")
		_hearts[i].modulate = p["coral"] if full else Color(p["muted"], 0.7)
		if animate and _shown > lives and i == lives and not SettingsManager.get_value("reduced_motion"):
			_hearts[i].scale = Vector2(1.35, 1.35)
			var tween := _hearts[i].create_tween()
			tween.tween_property(_hearts[i], "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if animate and _shown < lives and i < lives and i >= maxi(_shown, 0) and not SettingsManager.get_value("reduced_motion"):
			_hearts[i].scale = Vector2(0.4, 0.4)
			var grow := _hearts[i].create_tween()
			grow.tween_property(_hearts[i], "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_shown = lives
	accessibility_name = tr("HEARTS_LEFT") % lives
