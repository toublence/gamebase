class_name SettingsRow
extends VBoxContainer
## Vertical grouping remains usable at narrow widths and with translated labels.
func configure(label_key: String, control: Control) -> void:
	add_theme_constant_override("separation", Design.UNIT)
	add_child(Design.label(label_key, 17))
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(control)
