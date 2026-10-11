extends CanvasLayer
var config: BaseConfig
var _root: Control
var _modals: Array[ModalView] = []
var _curtain: ColorRect
var _toast: Label
var _toast_timer: Timer
var _focus_before_modal: WeakRef

func _ready() -> void:
	config = load("res://resources/base_config.tres")
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = preload("res://resources/base_theme.tres")
	add_child(_root)
	_curtain = ColorRect.new()
	_curtain.color = Design.PAPER
	_curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_curtain.modulate.a = 0.0
	_curtain.visible = false
	_root.add_child(_curtain)
	var safe := SafeArea.new()
	safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(safe)
	_toast = Design.label("", 16)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_toast.size_flags_vertical = Control.SIZE_SHRINK_END
	_toast.add_theme_stylebox_override("normal", preload("res://resources/base_theme.tres").get_stylebox("panel", "PanelContainer"))
	_toast.visible = false
	safe.add_child(_toast)
	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.timeout.connect(func(): _toast.hide())
	add_child(_toast_timer)
	SaveManager.save_failed.connect(func(_reason: String): toast("SAVE_ERROR"))

func push_modal(modal: ModalView) -> void:
	if not _modals.is_empty():
		_modals.back().hide()
	else:
		var focus := get_viewport().gui_get_focus_owner()
		if focus != null:
			_focus_before_modal = weakref(focus)
	_modals.append(modal)
	modal.closed.connect(_modal_closed.bind(modal))
	_root.add_child(modal)
	_root.move_child(_curtain, -1)


func _modal_closed(modal: ModalView) -> void:
	_modals.erase(modal)
	if not _modals.is_empty():
		_modals.back().show()
	elif _focus_before_modal != null:
		var focus: Variant = _focus_before_modal.get_ref()
		if is_instance_valid(focus):
			focus.grab_focus.call_deferred()

func show_pause() -> void:
	push_modal(load("res://scenes/pause/pause_overlay.tscn").instantiate())

func show_settings() -> void:
	push_modal(load("res://scenes/settings/settings.tscn").instantiate())

func confirm(title_key: String, message_key: String, action: Callable) -> void:
	var modal := ConfirmDialogView.new()
	modal.title_key = title_key
	modal.message_key = message_key
	modal.action = action
	push_modal(modal)

func handle_back() -> bool:
	if _modals.is_empty():
		return false
	var modal: ModalView = _modals.back()
	if modal.close_on_back:
		modal.close()
	else:
		AppManager.resume_game()
	return true

func close_all() -> void:
	for modal in _modals:
		modal.queue_free()
	_modals.clear()

func toast(key: String) -> void:
	_toast.text = key
	_toast.show()
	_toast_timer.start(3.0)

func fade_transition(covered: bool) -> void:
	_curtain.visible = true
	_curtain.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.move_child(_curtain, -1)
	await Motion.fade(_curtain, 1.0 if covered else 0.0, 0.14).finished
	if not covered:
		_curtain.hide()
