class_name GameModule
extends Node
## Extend this in the derived game's root. All result values are supplied by the game.
signal completion_requested(result: Dictionary)
signal session_started
signal session_paused
signal session_resumed
signal session_stopped

func start_session() -> void:
	session_started.emit()

func pause_session() -> void:
	session_paused.emit()

func resume_session() -> void:
	session_resumed.emit()

func stop_session() -> void:
	session_stopped.emit()

func complete(result: Dictionary = {}) -> void:
	completion_requested.emit(result)
