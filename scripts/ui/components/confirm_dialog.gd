class_name ConfirmDialogView
extends ModalView
var title_key := "CONFIRM"
var message_key := ""
var action: Callable
var confirm_key := "CONFIRM"

func _ready() -> void:
	super._ready()
	body.add_child(Design.title(title_key, 28))
	body.add_child(Design.label(message_key, 18, true))
	body.add_child(Design.button(confirm_key, _accept))
	var cancel := Design.button("CANCEL", close, true)
	body.add_child(cancel)
	cancel.grab_focus.call_deferred()

func _accept() -> void:
	close()
	if action.is_valid():
		action.call()
