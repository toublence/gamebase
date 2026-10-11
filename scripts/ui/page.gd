class_name BasePage
extends Control
## Base screen: an animated scene behind (Backdrop), safe-area padding and a centered, scrollable
## column. Text placed directly on the scene follows the scene's ink; cards and buttons keep theirs.
var _safe: SafeArea
var body: VBoxContainer
var _center: CenterContainer
var _background: Backdrop

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_background = Backdrop.new()
	_background.scene_id = Scenery.for_menu()
	Progress.theme_changed.connect(_on_theme_changed)
	add_child(_background)
	_safe = SafeArea.new()
	_safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_safe)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_safe.add_child(scroll)
	_center = CenterContainer.new()
	_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(_center)
	body = Design.column(20)
	_center.add_child(body)
	get_viewport().size_changed.connect(_fit_width)
	_safe.insets_changed.connect(_fit_width)
	_fit_width.call_deferred()
	tint_for_scene.call_deferred()

func _on_theme_changed(_id: String) -> void:
	_background.set_scene(Scenery.for_menu())
	tint_for_scene.call_deferred()

## Labels outside cards and buttons take the scene's text colors (light ink on the night scene).
func tint_for_scene() -> void:
	if not is_inside_tree():
		return
	_tint(body, Scenery.scene(_background.scene_id))

func _tint(node: Node, scene: Dictionary) -> void:
	for child in node.get_children():
		if child is PanelContainer or child is BaseButton or child is ModalView:
			continue
		if child is Label and child.has_meta("muted"):
			(child as Label).add_theme_color_override("font_color", scene["hud_soft"] if bool(child.get_meta("muted")) else scene["hud_ink"])
		_tint(child, scene)

## Pages that host an anchored banner reserve its height under their content.
func use_banner() -> void:
	AdsManager.banner_layout_changed.connect(_on_banner_layout)
	_on_banner_layout(AdsManager.banner_height_logical())
	AdsManager.request_banner(self, true)

func _on_banner_layout(height: float) -> void:
	_safe.extra_bottom = height

func _exit_tree() -> void:
	if AdsManager.banner_layout_changed.is_connected(_on_banner_layout):
		AdsManager.banner_layout_changed.disconnect(_on_banner_layout)
		AdsManager.request_banner(self, false)

func _fit_width() -> void:
	body.custom_minimum_size.x = minf(Design.MAX_CONTENT, maxf(0, get_viewport_rect().size.x - _safe.get_theme_constant("margin_left") - _safe.get_theme_constant("margin_right")))
