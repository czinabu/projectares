extends RefCounted
## The game's UI theme, built in code and merged into Godot's default theme by
## `Look`. Every Control picks it up wherever it sits in the tree, so the HUD
## and hub need no styling of their own.

## Loaded at runtime, not preloaded: a preload fails to parse on a fresh
## checkout before Godot has imported the font.
const FONT_PATH := "res://assets/fonts/Rajdhani-SemiBold.ttf"

const ACCENT := Color(1.0, 0.62, 0.22)
const INK := Color(0.9, 0.88, 0.84)
const PANEL := Color(0.07, 0.065, 0.06, 0.88)
const EDGE := Color(0.38, 0.34, 0.3, 0.9)


static func apply() -> void:
	var base := ThemeDB.get_default_theme()
	var ours := build()
	base.merge_with(ours)
	if ours.default_font:
		base.default_font = ours.default_font
		ThemeDB.fallback_font = ours.default_font
	base.default_font_size = ours.default_font_size


static func build() -> Theme:
	var theme := Theme.new()
	var font := load(FONT_PATH) as Font
	if font:
		theme.default_font = font
	theme.default_font_size = 17

	theme.set_color("font_color", "Label", INK)
	theme.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.75))
	theme.set_constant("outline_size", "Label", 5)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.5))
	theme.set_constant("shadow_offset_x", "Label", 0)
	theme.set_constant("shadow_offset_y", "Label", 2)

	for type: String in ["Button", "OptionButton"]:
		theme.set_stylebox("normal", type, _box(PANEL, EDGE, 1))
		theme.set_stylebox("hover", type, _box(Color(0.16, 0.12, 0.08, 0.95), ACCENT, 1))
		theme.set_stylebox("pressed", type, _box(Color(0.3, 0.18, 0.06, 0.95), ACCENT, 2))
		theme.set_stylebox("focus", type, _box(Color(0, 0, 0, 0), ACCENT, 1))
		theme.set_stylebox("disabled", type, _box(Color(0.06, 0.06, 0.06, 0.6), Color(0.2, 0.2, 0.2, 0.6), 1))
		theme.set_color("font_color", type, INK)
		theme.set_color("font_hover_color", type, ACCENT.lightened(0.3))
		theme.set_color("font_pressed_color", type, Color.WHITE)
		theme.set_color("font_focus_color", type, INK)
		theme.set_color("font_disabled_color", type, Color(0.45, 0.45, 0.45))

	theme.set_stylebox("panel", "PanelContainer", _box(PANEL, EDGE, 1))
	theme.set_stylebox("panel", "PopupMenu", _box(Color(0.06, 0.055, 0.05, 0.98), EDGE, 1))
	theme.set_stylebox("hover", "PopupMenu", _box(Color(0.3, 0.18, 0.06), ACCENT, 0))
	theme.set_stylebox("panel", "TooltipPanel", _box(Color(0.05, 0.05, 0.05, 0.96), ACCENT, 1))
	theme.set_color("font_color", "TooltipLabel", INK)

	var back := _box(Color(0, 0, 0, 0.55), Color(0, 0, 0, 0.8), 1)
	back.set_content_margin_all(0)
	theme.set_stylebox("background", "ProgressBar", back)
	var fill := StyleBoxFlat.new()
	fill.bg_color = ACCENT
	theme.set_stylebox("fill", "ProgressBar", fill)
	return theme


static func _box(fill: Color, edge: Color, border: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(border)
	box.set_corner_radius_all(2)
	box.set_content_margin_all(8)
	box.content_margin_left = 14
	box.content_margin_right = 14
	return box
