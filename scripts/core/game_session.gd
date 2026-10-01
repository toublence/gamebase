extends Node
signal started
signal paused
signal resumed
signal finished(result: Dictionary)
signal restarted
signal stopped

enum State { IDLE, ACTIVE, PAUSED, FINISHED }
var state := State.IDLE
var result: Dictionary = {}
var serial := 0

func start() -> bool:
	if state == State.ACTIVE or state == State.PAUSED:
		return false
	state = State.ACTIVE
	result = {}
	serial += 1
	SaveManager.mark_session_started()
	AnalyticsService.game_start()
	started.emit()
	return true

func pause() -> void:
	if state == State.ACTIVE:
		state = State.PAUSED
		paused.emit()

func resume() -> void:
	if state == State.PAUSED:
		state = State.ACTIVE
		resumed.emit()

func finish(payload: Dictionary = {}) -> void:
	if state != State.ACTIVE and state != State.PAUSED:
		return
	state = State.FINISHED
	result = payload.duplicate(true)
	AnalyticsService.game_end()
	finished.emit(result)

func restart() -> void:
	stop()
	AnalyticsService.game_restart()
	restarted.emit()
	# The new host calls start only after mounting the next game instance.

func stop() -> void:
	if state != State.IDLE:
		state = State.IDLE
		stopped.emit()
