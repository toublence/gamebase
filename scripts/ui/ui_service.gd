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
	add_child(_root)
	apply_theme()
	Progress.theme_changed.connect(func(_id: String): apply_theme())
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
	_toast.add_theme_color_override("font_color", Color.WHITE)
	var toast_style := Design.box(Color(0.12, 0.14, 0.2, 0.9), 16, 0, Color.TRANSPARENT, 14.0)
	_toast.add_theme_stylebox_override("normal", toast_style)
	_toast.visible = false
	safe.add_child(_toast)
	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.timeout.connect(func(): _toast.hide())
	add_child(_toast_timer)
	SaveManager.save_failed.connect(func(_reason: String): toast("SAVE_ERROR"))

## Builds the Godot Theme from the active palette and applies it app-wide.
func apply_theme() -> void:
	var theme := UiTheme.build()
	_root.theme = theme
	get_tree().root.theme = theme
	# Controls under a plain Node or CanvasLayer (the game module, overlays) do not inherit the
	# window theme; they fall back to the project theme, so it receives the same definitions.
	var project := ThemeDB.get_project_theme()
	if project != null:
		project.merge_with(theme)
		project.default_font = theme.default_font
		project.default_font_size = theme.default_font_size
	if _curtain != null:
		_curtain.color = Palette.c("bg")
	RenderingServer.set_default_clear_color(Palette.c("bg"))

## Debug builds only: logs every visible button (its text key and screen-pixel center) so device QA
## scripts can drive the real UI with adb taps. Never runs in release builds.
func debug_log_buttons(tag: String) -> void:
	if not OS.is_debug_build():
		return
	await get_tree().create_timer(0.45, true).timeout
	var scale := float(DisplayServer.window_get_size().x) / maxf(1.0, get_viewport().get_visible_rect().size.x)
	var found := {}
	_collect_buttons(get_tree().root, found, scale)
	Diagnostics.log_event("ui", "buttons", {"tag": tag, "route": SceneManager.current_route, "buttons": found})

func _collect_buttons(node: Node, found: Dictionary, scale: float) -> void:
	for child in node.get_children():
		if child is BaseButton and (child as Control).is_visible_in_tree() and not (child as BaseButton).disabled:
			var control := child as Control
			var key := str(control.get("text")) if not str(control.get("text")).is_empty() else str(control.accessibility_name)
			if key.is_empty():
				key = control.name
			var center := control.get_global_rect().get_center() * scale
			found[key] = [int(center.x), int(center.y)]
		_collect_buttons(child, found, scale)

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
	debug_log_buttons("modal")


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

func confirm(title_key: String, message_key: String, action: Callable, confirm_key: String = "CONFIRM") -> void:
	var modal := ConfirmDialogView.new()
	modal.title_key = title_key
	modal.message_key = message_key
	modal.action = action
	modal.confirm_key = confirm_key
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
	_toast.text = tr(key)
	_toast.show()
	_toast_timer.start(3.0)

func fade_transition(covered: bool) -> void:
	_curtain.visible = true
	_curtain.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.move_child(_curtain, -1)
	await Motion.fade(_curtain, 1.0 if covered else 0.0, 0.14).finished
	if not covered:
		_curtain.hide()
