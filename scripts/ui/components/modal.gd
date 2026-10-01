class_name ModalView
extends Control
signal closed
var _safe: SafeArea
var body: VBoxContainer
var close_on_back := true
var _panel: PanelContainer
var _center: CenterContainer
var _previous_focus: WeakRef

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null:
		_previous_focus = weakref(focus)
	var shade := ColorRect.new()
	shade.color = Color(0.08, 0.15, 0.13, 0.48)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	_safe = SafeArea.new()
	_safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_safe)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_safe.add_child(scroll)
	_center = CenterContainer.new()
	_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(_center)
	_panel = PanelContainer.new()
	_panel.theme_type_variation = &"ModalPanel"
	_center.add_child(_panel)
	body = Design.column(16)
	_panel.add_child(body)
	get_viewport().size_changed.connect(_fit)
	_safe.insets_changed.connect(_fit)
	_fit.call_deferred()

func _fit() -> void:
	_panel.custom_minimum_size.x = minf(Design.MAX_CONTENT, maxf(0, get_viewport_rect().size.x - _safe.get_theme_constant("margin_left") - _safe.get_theme_constant("margin_right")))

func close() -> void:
	closed.emit()
	queue_free()
	if _previous_focus != null:
		var focus: Variant = _previous_focus.get_ref()
		if is_instance_valid(focus) and focus.is_visible_in_tree():
			focus.grab_focus.call_deferred()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed("ui_focus_next") or event.is_action_pressed("ui_focus_prev"):
		var controls: Array[Control] = []
		_collect_focus(body, controls)
		if not controls.is_empty():
			var current := controls.find(get_viewport().gui_get_focus_owner())
			var direction := -1 if event.is_action_pressed("ui_focus_prev") else 1
			controls[posmod(current + direction, controls.size())].grab_focus()
		get_viewport().set_input_as_handled()

func _collect_focus(node: Node, controls: Array[Control]) -> void:
	for child in node.get_children():
		if child is Control and child.is_visible_in_tree() and child.focus_mode == Control.FOCUS_ALL:
			if not (child is BaseButton and child.disabled):
				controls.append(child)
		_collect_focus(child, controls)
