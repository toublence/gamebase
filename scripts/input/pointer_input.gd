class_name PointerInput
extends Node
## Add under a gameplay Control. UI-consumed presses never start a game pointer.
## Coordinates use viewport units; use Control.get_global_transform_with_canvas().affine_inverse()
## or Node2D.get_global_transform_with_canvas().affine_inverse() for local coordinates.
signal pressed(id: int, position: Vector2)
signal dragged(id: int, position: Vector2, delta: Vector2)
signal released(id: int, position: Vector2, displacement: Vector2, seconds: float)
signal cancelled(id: int)
var _pointers: Dictionary = {}

func _ready() -> void:
	AppManager.backgrounded.connect(cancel_all)
	GameSession.paused.connect(cancel_all)
	GameSession.stopped.connect(cancel_all)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed and not event.canceled:
		_begin(event.index, event.position)
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_begin(-1, event.position)

func _input(event: InputEvent) -> void:
	if event is InputEventScreenDrag:
		_move(event.index, event.position)
	elif event is InputEventScreenTouch and not event.pressed:
		if event.canceled:
			_cancel(event.index)
		else:
			_end(event.index, event.position)
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		_move(-1, event.position)
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_end(-1, event.position)

func _begin(id: int, position: Vector2) -> void:
	_pointers[id] = {"start": position, "last": position, "time": Time.get_ticks_msec()}
	pressed.emit(id, position)
	get_viewport().set_input_as_handled()

func _move(id: int, position: Vector2) -> void:
	if not _pointers.has(id):
		return
	var delta: Vector2 = position - _pointers[id]["last"]
	_pointers[id]["last"] = position
	dragged.emit(id, position, delta)
	get_viewport().set_input_as_handled()

func _end(id: int, position: Vector2) -> void:
	if not _pointers.has(id):
		return
	var pointer: Dictionary = _pointers[id]
	_pointers.erase(id)
	released.emit(id, position, position - pointer["start"], (Time.get_ticks_msec() - pointer["time"]) / 1000.0)
	get_viewport().set_input_as_handled()

func _cancel(id: int) -> void:
	if _pointers.erase(id):
		cancelled.emit(id)

func cancel_all() -> void:
	for id in _pointers.keys():
		_cancel(id)

func _exit_tree() -> void:
	cancel_all()
