class_name GameOverlay
extends CanvasLayer
## Full-screen layer for the clear / fail cards inside the game screen (above the board, below the
## shared modal layer). The card slides up from the bottom so the cleared board stays visible.
signal closed

var card: PanelContainer
var body: VBoxContainer
var _scrim: ColorRect
var _safe: SafeArea
var _wrap: Control

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_scrim = ColorRect.new()
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scrim.color = Color(Palette.c("shadow"), 0.0)
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_scrim)
	_safe = SafeArea.new()
	_safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_safe)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_safe.add_child(column)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(center)
	_wrap = Control.new()
	_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_wrap)
	card = PanelContainer.new()
	card.theme_type_variation = &"ModalPanel"
	_wrap.add_child(card)
	body = Design.column(14)
	card.add_child(body)
	_scrim.gui_input.connect(func(_e: InputEvent): pass)
	visible = false

func open(min_width: float = 0.0) -> void:
	visible = true
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var width := minf(Design.MAX_CONTENT, get_viewport().get_visible_rect().size.x - 32.0)
	card.custom_minimum_size.x = maxf(width, min_width)
	card.reset_size()
	_wrap.custom_minimum_size = card.size
	# Wrapped labels settle their height a frame later (notably when the sheet opens while the
	# screen is still being laid out, e.g. a failed attempt reopened from home): measure again.
	_fit_card.call_deferred()
	var reduced := bool(SettingsManager.get_value("reduced_motion"))
	UI.debug_log_buttons("sheet")
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_scrim, "color:a", 0.28, 0.0 if reduced else 0.2)
	if not reduced:
		card.position.y = 120.0
		card.modulate.a = 0.0
		tween.parallel().tween_property(card, "position:y", 0.0, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(card, "modulate:a", 1.0, 0.16)

func _fit_card() -> void:
	await get_tree().process_frame
	if not is_inside_tree() or not visible:
		return
	card.reset_size()
	_wrap.custom_minimum_size = card.size

func clear_content() -> void:
	for child in body.get_children():
		child.queue_free()

func close() -> void:
	if not visible:
		return
	visible = false
	clear_content()
	_scrim.color.a = 0.0
	closed.emit()

func is_open() -> bool:
	return visible
