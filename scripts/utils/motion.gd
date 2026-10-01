class_name Motion
extends RefCounted
static func duration(seconds: float) -> float:
	return 0.0 if SettingsManager.get_value("reduced_motion") else seconds

static func fade(node: Control, alpha: float, seconds: float = 0.18) -> Tween:
	var tween := node.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(node, "modulate:a", alpha, duration(seconds)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return tween

static func pop(node: Control) -> Tween:
	node.pivot_offset = node.size * 0.5
	node.scale = Vector2.ONE if SettingsManager.get_value("reduced_motion") else Vector2(0.96, 0.96)
	return scale_to(node, Vector2.ONE)

static func scale_to(node: Control, target: Vector2, seconds: float = 0.16) -> Tween:
	var tween := node.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(node, "scale", target, duration(seconds)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return tween

static func slide(node: Control, offset: Vector2, seconds: float = 0.18) -> Tween:
	# Use a wrapper Control outside Container layout ownership.
	var destination := node.position
	if not SettingsManager.get_value("reduced_motion"):
		node.position += offset
	var tween := node.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(node, "position", destination, duration(seconds)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return tween

static func bounce(node: Control) -> Tween:
	var tween := node.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	node.pivot_offset = node.size * 0.5
	tween.tween_property(node, "scale", Vector2(1.025, 1.025), duration(0.08))
	tween.tween_property(node, "scale", Vector2.ONE, duration(0.12)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return tween
