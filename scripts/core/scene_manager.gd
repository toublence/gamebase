extends Node
signal transition_finished(route: String)
const ROUTES := {"menu": "res://scenes/menu/main_menu.tscn",
	"game": "res://scenes/game/game_host.tscn", "result": "res://scenes/result/result.tscn"}
var is_transitioning := false
var current_route := "boot"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func go_to(route: String) -> bool:
	if is_transitioning or not ROUTES.has(route):
		return false
	var scene := load(ROUTES[route]) as PackedScene
	if scene == null:
		UI.toast("SCENE_ERROR")
		return false
	is_transitioning = true
	_transition(scene, route)
	return true

func _transition(scene: PackedScene, route: String) -> void:
	await UI.fade_transition(true)
	UI.close_all()
	get_tree().paused = false
	var error := get_tree().change_scene_to_packed(scene)
	if error != OK:
		await UI.fade_transition(false)
		is_transitioning = false
		UI.toast("SCENE_ERROR")
		return
	await get_tree().scene_changed
	current_route = route
	match route:
		"menu": AppManager.set_state(AppManager.State.MENU)
		"game": AppManager.set_state(AppManager.State.PLAYING)
		"result": AppManager.set_state(AppManager.State.RESULT)
	if AppManager.is_backgrounded:
		AppManager.pause_game()
	await UI.fade_transition(false)
	is_transitioning = false
	transition_finished.emit(route)
