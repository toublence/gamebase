extends ModalView
func _ready() -> void:
	super._ready()
	close_on_back = false
	body.add_child(Design.label("PAUSED", 32))
	body.add_child(Design.label("PAUSE_DESCRIPTION", 18, true))
	var resume_button := Design.button("RESUME", AppManager.resume_game)
	body.add_child(resume_button)
	body.add_child(Design.button("RESTART", func(): UI.confirm("RESTART", "RESTART_BODY", AppManager.restart_game), true))
	body.add_child(Design.button("SETTINGS", UI.show_settings, true))
	body.add_child(Design.button("MAIN_MENU", func(): UI.confirm("MAIN_MENU", "LEAVE_BODY", AppManager.return_to_menu), true))
	resume_button.grab_focus.call_deferred()
