class_name BasePage
extends Control
var _safe: SafeArea
var body: VBoxContainer
var _center: CenterContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Design.PAPER
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	_safe = SafeArea.new()
	_safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_safe)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_safe.add_child(scroll)
	_center = CenterContainer.new()
	_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(_center)
	body = Design.column(20)
	_center.add_child(body)
	get_viewport().size_changed.connect(_fit_width)
	_safe.insets_changed.connect(_fit_width)
	_fit_width.call_deferred()

func _fit_width() -> void:
	body.custom_minimum_size.x = minf(Design.MAX_CONTENT, maxf(0, get_viewport_rect().size.x - _safe.get_theme_constant("margin_left") - _safe.get_theme_constant("margin_right")))
