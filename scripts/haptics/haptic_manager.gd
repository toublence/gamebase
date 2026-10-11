extends Node
func light() -> void:
	_pulse(18, 0.35)
func medium() -> void:
	_pulse(32, 0.6)
func strong() -> void:
	_pulse(50, 1.0)
func success() -> void:
	_pulse(65, 0.65)

## Game-specific pattern (duration ms, amplitude 0..1). Respects the haptic setting.
func pulse(duration: int, amplitude: float) -> void:
	_pulse(duration, amplitude)

func _pulse(duration: int, amplitude: float) -> void:
	if not SettingsManager.get_value("haptic"):
		return
	if OS.get_name() in ["Android", "iOS"]:
		Input.vibrate_handheld(duration, amplitude)
