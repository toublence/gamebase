extends Node
signal state_changed(state: int)
signal backgrounded
signal foregrounded

enum State { BOOT, MENU, PLAYING, PAUSED, RESULT }
var state := State.BOOT
var is_backgrounded := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().auto_accept_quit = false
	get_tree().quit_on_go_back = false
	Engine.max_fps = 60
	GameSession.finished.connect(_on_finished)

func set_state(value: State) -> void:
	state = value
	state_changed.emit(state)

func pause_game() -> void:
	if state != State.PLAYING:
		return
	GameSession.pause()
	get_tree().paused = true
	set_state(State.PAUSED)
	UI.show_pause()

func resume_game() -> void:
	if state != State.PAUSED or is_backgrounded or SceneManager.is_transitioning or AdsManager.is_presenting():
		return
	UI.close_all()
	get_tree().paused = false
	set_state(State.PLAYING)
	GameSession.resume()

func restart_game() -> void:
	if SceneManager.is_transitioning or AdsManager.is_presenting():
		return
	GameSession.restart()
	SceneManager.go_to("game")

func return_to_menu() -> void:
	if SceneManager.is_transitioning or AdsManager.is_presenting():
		return
	GameSession.stop()
	SceneManager.go_to("menu")

func _on_finished(_result: Dictionary) -> void:
	SceneManager.go_to("result")

func handle_back() -> void:
	if SceneManager.is_transitioning or AdsManager.is_presenting():
		return
	if UI.handle_back():
		return
	match state:
		State.PLAYING: pause_game()
		State.PAUSED: resume_game()
		State.RESULT: return_to_menu()
		State.MENU: UI.confirm("QUIT_TITLE", "QUIT_BODY", request_quit)

func request_quit() -> void:
	SaveManager.flush()
	get_tree().quit()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		handle_back()
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		is_backgrounded = true
		pause_game()
		SaveManager.flush()
		AudioManager.set_suspended(true)
		backgrounded.emit()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		is_backgrounded = false
		AudioManager.set_suspended(AdsManager.is_presenting())
		foregrounded.emit()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		handle_back()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		request_quit()
