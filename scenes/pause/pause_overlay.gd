extends ModalView
## Pause. The board waits underneath; nothing advances until Resume.

func _ready() -> void:
	super._ready()
	close_on_back = false
	body.add_child(Design.title("PAUSED", 30))
	body.add_child(Design.label("PAUSE_DESCRIPTION", 18, true))
	var resume_button := Design.button("RESUME", AppManager.resume_game)
	resume_button.icon = Widgets.icon("play")
	body.add_child(resume_button)
	body.add_child(Design.button("RESTART_LEVEL", _restart, true))
	body.add_child(Design.button("SETTINGS", UI.show_settings, true))
	body.add_child(Design.button("HOME", AppManager.return_to_menu, true))
	resume_button.grab_focus.call_deferred()

func _restart() -> void:
	AppManager.resume_game()
	var module := get_tree().get_first_node_in_group("outtap_game")
	if module != null and module.has_method("restart_from_pause"):
		module.restart_from_pause()
