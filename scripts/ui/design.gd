class_name Design
extends RefCounted
## Logical design units, not device pixels. Override the shared Theme in each game.
const UNIT := 8
const TOUCH := 56
const MAX_CONTENT := 560
const INK := Color("223a35")
const MUTED := Color("65746e")
const PAPER := Color("f3f4ef")
const SURFACE := Color("ffffff")
const ACCENT := Color("2b6454")

static func label(key: String, size: int = 18, muted: bool = false) -> Label:
	var node := Label.new()
	node.text = key
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", MUTED if muted else INK)
	return node

static func button(key: String, callback: Callable, secondary: bool = false) -> BaseButtonView:
	var node := BaseButtonView.new()
	node.text = key
	node.theme_type_variation = &"SecondaryButton" if secondary else &"PrimaryButton"
	node.pressed.connect(callback)
	return node

static func column(gap: int = 16) -> VBoxContainer:
	var node := VBoxContainer.new()
	node.add_theme_constant_override("separation", gap)
	return node

static func space(units: float = 1.0) -> Control:
	var node := Control.new()
	node.custom_minimum_size.y = UNIT * units
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

## Variable font at a given weight (100-900). Use the integer OpenType tag: a String key such as
## {"wght": 800} is silently ignored and the font's default instance (often Thin) is used.
static func variable_font(base: Font, weight: int) -> FontVariation:
	var variation := FontVariation.new()
	variation.base_font = base
	variation.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	return variation
