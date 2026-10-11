extends Control
## Mounts the configured GameModule inside the safe area. The Outtap module draws its own HUD; the
## host only shows the edge-to-edge animated scene and wires the GameSession lifecycle.
var _module: GameModule
var _content: Control
var _background: Backdrop

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The module picks each stage's scene through the "backdrop" group.
	_background = Backdrop.new()
	_background.scene_id = Scenery.for_menu()
	_background.calm = true
	_background.add_to_group("backdrop")
	add_child(_background)
	var safe := SafeArea.new()
	safe.padding_units = 1.5
	safe.mouse_filter = Control.MOUSE_FILTER_PASS
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(safe)
	_content = Control.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_child(_content)
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
			_content.add_child(Design.label("MODULE_ERROR", 20))
	AudioManager.play_music(UI.config.game_music)
	GameSession.start()

func _finish(result: Dictionary) -> void:
	GameSession.finish(result)

func _stop_module(_result: Dictionary) -> void:
	if is_instance_valid(_module):
		_module.stop_session()

func _exit_tree() -> void:
	# Disconnect so a freed module never receives lifecycle signals.
	if is_instance_valid(_module):
		for pair in [[GameSession.started, _module.start_session], [GameSession.paused, _module.pause_session],
				[GameSession.resumed, _module.resume_session], [GameSession.stopped, _module.stop_session]]:
			if pair[0].is_connected(pair[1]):
				pair[0].disconnect(pair[1])
		if GameSession.finished.is_connected(_stop_module):
			GameSession.finished.disconnect(_stop_module)
