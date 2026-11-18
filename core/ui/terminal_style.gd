extends RefCounted
## The look of the screens you walk up to and use: the home base's station
## screens (`Hub`) and the Concourse's terminals (`Main.ShopView`). Built in
## code like `UiTheme`, which it sits on top of, in the house style the gear
## wears: graphite plates with cut corners, an amber edge where you can act,
## cyan light where something is shown, and the glass of a lit terminal
## (a faint grid, scanlines and a slow sweep) behind it all. View only: it
## styles Controls and never changes what a screen does.
##
## A screen sets `theme()` on its root, puts a `Backdrop` behind its
## contents and calls `dress(root)` once its contents are built, which turns
## its big titles into lit headings.
##
## Load with `const TerminalStyle := preload("res://core/ui/terminal_style.gd")`.

const AMBER := Color(1.0, 0.62, 0.22)
const CYAN := Color(0.35, 0.85, 1.0)
const INK := Color(0.9, 0.9, 0.88)
const PLATE := Color(0.075, 0.085, 0.095, 0.96)
const PLATE_LIT := Color(0.13, 0.1, 0.07, 0.98)
const EDGE := Color(0.24, 0.27, 0.3)
const GLASS_TOP := Color(0.03, 0.038, 0.046)
const GLASS_BOTTOM := Color(0.012, 0.015, 0.02)
## How far a plate's corners are cut.
const CUT := 7
## Labels at least this big are titles: `dress` lights them as headings.
const HEADING_SIZE := 20

static var _theme: Theme


## The theme for a terminal's controls, made once.
static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	for type: String in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type, plate(PLATE, EDGE, 1, 2))
		t.set_stylebox("hover", type, plate(PLATE_LIT, AMBER, 1, 2, 0.28))
		t.set_stylebox("pressed", type, plate(Color(0.32, 0.17, 0.05, 0.98), AMBER, 1, 3, 0.35))
		t.set_stylebox("hover_pressed", type, plate(Color(0.38, 0.2, 0.06, 0.98), AMBER.lightened(0.2), 1, 3, 0.4))
		t.set_stylebox("focus", type, plate(Color(0, 0, 0, 0), AMBER.darkened(0.2), 1, 1))
		t.set_stylebox("disabled", type, plate(Color(0.05, 0.055, 0.06, 0.7), Color(0.16, 0.17, 0.18), 1, 1))
		t.set_color("font_color", type, INK)
		t.set_color("font_hover_color", type, AMBER.lightened(0.35))
		t.set_color("font_pressed_color", type, Color.WHITE)
		t.set_color("font_hover_pressed_color", type, Color.WHITE)
		t.set_color("font_focus_color", type, INK)
		t.set_color("font_disabled_color", type, Color(0.4, 0.42, 0.44))
	t.set_stylebox("panel", "PopupMenu", plate(Color(0.05, 0.058, 0.066, 0.99), CYAN.darkened(0.45), 1, 1))
	var lit := StyleBoxFlat.new()
	lit.bg_color = Color(0.32, 0.17, 0.05)
	lit.border_color = AMBER
	lit.border_width_left = 3
	t.set_stylebox("hover", "PopupMenu", lit)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_stylebox("panel", "TooltipPanel", plate(Color(0.04, 0.05, 0.06, 0.98), CYAN, 1, 1))
	# Thin lit scroll bars, out of the way.
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.03)
	track.content_margin_left = 3
	track.content_margin_right = 3
	var grab := StyleBoxFlat.new()
	grab.bg_color = CYAN.darkened(0.35)
	grab.set_corner_radius_all(2)
	var grab_lit := grab.duplicate() as StyleBoxFlat
	grab_lit.bg_color = CYAN
	t.set_stylebox("scroll", "VScrollBar", track)
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab_lit)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab_lit)
	# Number boxes (the market's count and price).
	t.set_stylebox("normal", "LineEdit", plate(Color(0.03, 0.035, 0.04, 0.95), EDGE, 1, 1))
	t.set_stylebox("focus", "LineEdit", plate(Color(0, 0, 0, 0), CYAN, 1, 1))
	_theme = t
	return t


## A plate with its top-left and bottom-right corners cut, like the gear's
## panels: `edge` round it, a heavier `under` line along its foot, and a
## soft glow of the edge colour when `glow` is over 0.
static func plate(fill: Color, edge: Color, border := 1, under := 1, glow := 0.0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(border)
	box.border_width_bottom = under
	box.corner_radius_top_left = CUT
	box.corner_radius_bottom_right = CUT
	box.corner_detail = 1
	box.anti_aliasing = true
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	if glow > 0.0:
		box.shadow_color = Color(edge, glow)
		box.shadow_size = 6
	return box


## The card beside a list: a darker plate, edged in `accent` (the item's
## rarity) along its top.
static func card_plate(accent: Color) -> StyleBoxFlat:
	var box := plate(Color(0.04, 0.048, 0.056, 0.97), EDGE, 1, 1)
	box.border_color = Color(accent, 0.85)
	box.border_width_top = 3
	box.corner_radius_top_left = CUT * 2
	box.corner_radius_bottom_right = CUT * 2
	box.set_content_margin_all(12)
	return box


## Lights the titles under `root`: every Label at least `HEADING_SIZE` big
## gets an amber bar beside it and a fading line under it, in its own
## colour. Safe to call again.
static func dress(root: Node) -> void:
	for node in root.find_children("*", "Label", true, false):
		var label := node as Label
		if label.has_meta("terminal_heading"):
			continue
		if label.get_theme_font_size("font_size") < HEADING_SIZE:
			continue
		label.set_meta("terminal_heading", true)
		label.uppercase = true
		var box := StyleBoxEmpty.new()
		box.content_margin_left = 14
		box.content_margin_bottom = 5
		label.add_theme_stylebox_override("normal", box)
		label.draw.connect(_draw_heading.bind(label))
		label.queue_redraw()


static func _draw_heading(label: Label) -> void:
	var tint := label.get_theme_color("font_color")
	var h := label.size.y
	# A bar with a cut top beside the title.
	label.draw_colored_polygon(PackedVector2Array([Vector2(0, 5), Vector2(3, 2), Vector2(5, 2), Vector2(5, h - 6),
			Vector2(0, h - 6)]), tint)
	# A line under it that fades out across the screen.
	var width := label.size.x
	var steps := 12
	for i in steps:
		var a := float(i) / steps
		label.draw_rect(Rect2(14 + (width - 14) * a, h - 2, (width - 14) / steps + 1, 1),
				Color(tint, 0.55 * (1.0 - a)))


## The glass behind a terminal's contents: a dark gradient, a faint grid,
## scanlines, a slow sweep of light down the screen and lit corner brackets.
## Ignores the mouse.
class Backdrop:
	extends Control

	## Seconds the sweep takes to cross the screen.
	const SWEEP_TIME := 7.0
	const GRID := 48.0

	var _sweep := 0.0

	func _init() -> void:
		name = "TerminalGlass"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		_sweep = fmod(_sweep + delta / SWEEP_TIME, 1.0)
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		# The gradient, in bands.
		var bands := 24
		for i in bands:
			var a := float(i) / (bands - 1)
			draw_rect(Rect2(0, h * i / bands, w, h / bands + 1), GLASS_TOP.lerp(GLASS_BOTTOM, a))
		# The grid, brighter toward the middle.
		var x := GRID
		while x < w:
			var mid := 1.0 - absf(x / w - 0.5) * 1.6
			draw_line(Vector2(x, 0), Vector2(x, h), Color(CYAN, 0.025 + 0.02 * mid), 1.0)
			x += GRID
		var y := GRID
		while y < h:
			draw_line(Vector2(0, y), Vector2(w, y), Color(CYAN, 0.03), 1.0)
			y += GRID
		# Scanlines.
		y = 0.0
		while y < h:
			draw_line(Vector2(0, y), Vector2(w, y), Color(0, 0, 0, 0.18), 1.0)
			y += 3.0
		# The sweep: a soft band of light moving down.
		var at := _sweep * (h + 160.0) - 80.0
		for i in 8:
			var a := 1.0 - absf(i - 3.5) / 4.0
			draw_rect(Rect2(0, at + i * 10.0, w, 10.0), Color(CYAN, 0.018 * a))
		# Corner brackets, amber, and a thin edge round the glass.
		draw_rect(Rect2(6, 6, w - 12, h - 12), Color(EDGE, 0.5), false, 1.0)
		var arm := 34.0
		for corner: Vector2 in [Vector2(6, 6), Vector2(w - 6, 6), Vector2(6, h - 6), Vector2(w - 6, h - 6)]:
			var sx := 1.0 if corner.x < w * 0.5 else -1.0
			var sy := 1.0 if corner.y < h * 0.5 else -1.0
			draw_line(corner, corner + Vector2(arm * sx, 0), AMBER, 2.0)
			draw_line(corner, corner + Vector2(0, arm * sy), AMBER, 2.0)
		# A dim vignette at the edges.
		for i in 6:
			var a := 0.08 * (1.0 - i / 6.0)
			draw_rect(Rect2(i * 6, i * 6, w - i * 12, h - i * 12), Color(0, 0, 0, a), false, 6.0)
