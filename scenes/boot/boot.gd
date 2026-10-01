extends BasePage
func _ready() -> void:
	super._ready()
	body.add_child(Design.label("BRAND", 16, true))
	body.add_child(Design.label("APP_TITLE", 36))
	body.add_child(LoadingIndicator.new())
	_boot.call_deferred()

func _boot() -> void:
	SaveManager.mark_booted()
	await get_tree().process_frame
	SceneManager.go_to("menu")
	if SaveManager.last_status in ["corrupt", "recovered", "future_version"]:
		UI.toast("SAVE_RECOVERY")
