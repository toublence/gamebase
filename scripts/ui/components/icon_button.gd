class_name IconButtonView
extends BaseButtonView
func configure(texture: Texture2D, accessible_key: String, callback: Callable) -> void:
	icon = texture
	tooltip_text = accessible_key
	accessibility_name = accessible_key
	theme_type_variation = &"SecondaryButton"
	custom_minimum_size = Vector2(Design.TOUCH, Design.TOUCH)
	pressed.connect(callback)
