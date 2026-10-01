class_name AnalyticsAdapter
extends RefCounted
## Override in an optional provider. Default implementation intentionally sends nothing.
func record(_event: StringName, _parameters: Dictionary) -> void:
	return
