class_name StoryCard
extends ModalView
## One story beat: Grandma Moa's portrait (a drawn lighthouse badge), her name, and the beat's lines
## shown one at a time. Each line types in quickly (instantly with reduced motion); tapping the
## button finishes the line or moves to the next one. Emits `finished` once, when closed.
signal finished

var beat := ""
var _lines: Array = []
var _index := 0
var _text: Label
var _button: BaseButtonView
var _typing: Tween

static func show_beat(beat_id: String) -> StoryCard:
	var card := StoryCard.new()
	card.beat = beat_id
	UI.push_modal(card)
	return card

func _ready() -> void:
	super._ready()
	close_on_back = false
	_lines = Story.BEATS.get(beat, [])
	var head := Design.row(14)
	body.add_child(head)
	var portrait := Portrait.new()
	portrait.custom_minimum_size = Vector2(72, 72)
	head.add_child(portrait)
	var names := Design.column(0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(names)
	names.add_child(Design.label(Story.SPEAKER, 19, false, 800))
	names.add_child(Design.label("STORY_PLACE", 14, true, 650))
	_text = Design.label("", 19, false, 650)
	_text.custom_minimum_size.y = 96
	body.add_child(_text)
	_button = Design.button("NEXT", _advance)
	body.add_child(_button)
	_show_line()
	closed.connect(func(): finished.emit())

func _show_line() -> void:
	_text.text = tr(_lines[_index]) if _index < _lines.size() else ""
	_button.text = tr("STORY_START") if _index >= _lines.size() - 1 else tr("NEXT")
	if SettingsManager.get_value("reduced_motion"):
		_text.visible_ratio = 1.0
		return
	_text.visible_ratio = 0.0
	_typing = create_tween()
	_typing.tween_property(_text, "visible_ratio", 1.0, clampf(_text.text.length() * 0.025, 0.25, 1.2))

func _advance() -> void:
	if _typing != null and _typing.is_valid() and _text.visible_ratio < 1.0:
		_typing.kill()
		_text.visible_ratio = 1.0
		return
	_index += 1
	if _index >= _lines.size():
		Progress.mark_story(beat)
		close()
		return
	_show_line()

## Grandma Moa as a lighthouse badge: a warm disc, a striped tower and a lit lamp.
class Portrait:
	extends Control
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := minf(size.x, size.y) * 0.5
		var c := size * 0.5
		draw_circle(c, r, Color("1E2D52"), true, -1.0, true)
		draw_circle(c, r * 0.9, Color("2C4475"), true, -1.0, true)
		var lamp := c + Vector2(0, -r * 0.42)
		for k in 4:
			draw_circle(lamp, r * (0.5 - k * 0.1), Color(Scenery.GOLD_LIGHT, 0.08 + k * 0.05), true, -1.0, true)
		var base_y := c.y + r * 0.55
		var tower := PackedVector2Array([Vector2(c.x - r * 0.24, base_y), Vector2(c.x + r * 0.24, base_y),
			Vector2(c.x + r * 0.14, lamp.y + r * 0.12), Vector2(c.x - r * 0.14, lamp.y + r * 0.12)])
		draw_colored_polygon(tower, Color("F4EFE6"))
		for k in 2:
			var y := lerpf(base_y, lamp.y + r * 0.12, 0.3 + k * 0.33)
			var half := lerpf(r * 0.24, r * 0.14, 0.3 + k * 0.33)
			draw_rect(Rect2(Vector2(c.x - half, y - r * 0.06), Vector2(half * 2.0, r * 0.12)), Color("E2543E"))
		draw_circle(lamp, r * 0.13, Scenery.GOLD, true, -1.0, true)
		draw_rect(Rect2(Vector2(c.x - r * 0.62, base_y), Vector2(r * 1.24, r * 0.1)), Color("8FB8E8"))
