class_name ResultCard
extends PanelContainer
func configure(payload: Dictionary) -> void:
	var column := Design.column(12)
	add_child(column)
	column.add_child(Design.label(str(payload.get("title", "SESSION_COMPLETE")), 30))
	if payload.has("value"):
		column.add_child(Design.label(str(payload["value"]), 44))
	if payload.has("best"):
		column.add_child(Design.label("BEST_VALUE", 16, true))
		column.add_child(Design.label(str(payload["best"]), 24))
	if payload.has("message"):
		column.add_child(Design.label(str(payload["message"]), 18, true))
