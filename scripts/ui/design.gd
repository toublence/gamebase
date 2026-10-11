class_name Design
extends RefCounted
## Logical design units (480-wide portrait canvas, expand). On a 360dp phone 1 unit ≈ 0.75dp, so
## TOUCH (64) keeps every control at or above 48dp.
const UNIT := 8
const TOUCH := 64
const MAX_CONTENT := 520
const RADIUS := 18
const LIP := 5

const FONT_FILE := preload("res://assets/fonts/SUIT-Variable.ttf")
const FALLBACK_FONTS := ["Noto Sans CJK JP", "Noto Sans CJK SC", "Noto Sans CJK TC", "Noto Sans Arabic",
	"Noto Sans", "Roboto", "Hiragino Sans", "PingFang SC", "Apple SD Gothic Neo", "Geeza Pro", "Droid Sans Fallback"]

static var _fonts: Dictionary = {}
static var _fallback: SystemFont

# Legacy base names, now theme-aware.
static var INK: Color:
	get: return Palette.c("ink")
static var MUTED: Color:
	get: return Palette.c("muted")
static var PAPER: Color:
	get: return Palette.c("bg")
static var SURFACE: Color:
	get: return Palette.c("face")
static var ACCENT: Color:
	get: return Palette.c("accent")

## SUIT at the given weight (100-900), with system fallback for scripts SUIT does not cover.
static func font(weight: int = 600) -> FontVariation:
	if _fonts.has(weight):
		return _fonts[weight]
	if _fallback == null:
		_fallback = SystemFont.new()
		_fallback.font_names = PackedStringArray(FALLBACK_FONTS)
	_fonts[weight] = variable_font(FONT_FILE, weight)
	_fonts[weight].fallbacks = [_fallback]
	return _fonts[weight]

static func label(key: String, size: int = 20, muted: bool = false, weight: int = 600) -> Label:
	var node := Label.new()
	node.text = key
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.add_theme_font_override("font", font(weight))
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", MUTED if muted else INK)
	node.set_meta("muted", muted)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

static func title(key: String, size: int = 30) -> Label:
	return label(key, size, false, 800)

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

static func row(gap: int = 12) -> HBoxContainer:
	var node := HBoxContainer.new()
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

static func box(color: Color, radius: int = RADIUS, lip: int = 0, lip_color: Color = Color.TRANSPARENT,
		margin: float = 16.0, shadow: float = 0.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.anti_aliasing = true
	style.anti_aliasing_size = 1.0
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin
	style.content_margin_bottom = margin + lip
	if lip > 0:
		style.border_width_bottom = lip
		style.border_color = lip_color
	if shadow > 0.0:
		style.shadow_color = Color(Palette.c("shadow"), 0.10)
		style.shadow_size = int(shadow)
		style.shadow_offset = Vector2(0, shadow * 0.45)
	return style
