extends Control
var _module: GameModule
var _content: Control

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var safe := SafeArea.new()
	safe.mouse_filter = Control.MOUSE_FILTER_PASS
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(safe)
	var layout := Design.column(20)
	layout.mouse_filter = Control.MOUSE_FILTER_PASS
	safe.add_child(layout)
	var header := HBoxContainer.new()
	layout.add_child(header)
	var title := Design.label("GAME_HOST", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var pause_button := IconButtonView.new()
	pause_button.configure(preload("res://assets/icons/pause.svg"), "PAUSE", AppManager.pause_game)
	header.add_child(pause_button)
	_content = Control.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(_content)
	if UI.config.game_scene != null:
		var instance := UI.config.game_scene.instantiate()
		if instance is GameModule:
			_module = instance
			_content.add_child(_module)
			_module.completion_requested.connect(_finish)
			GameSession.started.connect(_module.start_session)
			GameSession.paused.connect(_module.pause_session)
			GameSession.resumed.connect(_module.resume_session)
			GameSession.stopped.connect(_module.stop_session)
			GameSession.finished.connect(_stop_module)
		else:
			instance.free()
			_placeholder("MODULE_ERROR")
	else:
		_placeholder("HOST_DESCRIPTION")
	AudioManager.play_music(UI.config.game_music)
	GameSession.start()

func _placeholder(message_key: String) -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var column := Design.column(20)
	panel.add_child(column)
	column.add_child(Design.label("HOST_READY", 30))
	column.add_child(Design.label(message_key, 18, true))
	column.add_child(Design.space(2))
	column.add_child(Design.button("END_SESSION", func(): _finish({"message": "SESSION_ENDED"})))
	_content.resized.connect(func(): panel.custom_minimum_size.x = minf(Design.MAX_CONTENT, _content.size.x))
	panel.custom_minimum_size.x = minf(Design.MAX_CONTENT, get_viewport_rect().size.x - Design.UNIT * 5)

func _finish(result: Dictionary) -> void:
	GameSession.finish(result)

func _stop_module(_result: Dictionary) -> void:
	if is_instance_valid(_module):
		_module.stop_session()
