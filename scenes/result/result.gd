extends BasePage
func _ready() -> void:
	super._ready()
	AudioManager.play_music(UI.config.menu_music)
	HapticManager.success()
	body.add_child(Design.label("RESULT", 16, true))
	var card := ResultCard.new()
	card.configure(GameSession.result)
	body.add_child(card)
	var replay_button := Design.button("REPLAY", AppManager.restart_game)
	body.add_child(replay_button)
	body.add_child(Design.button("MAIN_MENU", AppManager.return_to_menu, true))
	replay_button.grab_focus.call_deferred()
	SceneManager.transition_finished.connect(_after_transition, CONNECT_ONE_SHOT)

func _after_transition(route: String) -> void:
	if route == "result":
		AdsManager.show_interstitial_on_natural_break()
