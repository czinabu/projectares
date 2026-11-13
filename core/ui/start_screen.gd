class_name StartScreen
extends Control
## The first thing you see when the game launches: the title and Start,
## centred in the lower third under the lane between worlds (`TitleBackdrop`, built
## by `core/start.gd`).
##
## `start_pressed` fires once, then `leave()` fades out while the lane jumps,
## and the game scene loads (`main.gd` takes over in your home
## base). Nothing else lives here on purpose: no options, no menu.

signal start_pressed

const UiTheme := preload("res://core/visual/ui_theme.gd")
## Used when there is no scene behind the screen.
const BACKDROP_COLOR := Color(0.035, 0.03, 0.04)
const INK := Color(0.94, 0.93, 0.9)
const QUIET := Color(0.84, 0.86, 0.9)
const FAINT := Color(0.72, 0.76, 0.84, 0.9)
## Text on a lit (amber) button.
const INK_DARK := Color(0.06, 0.05, 0.04)

var title_text := "PROJECT ARES"
var tagline_text := "Take what you can carry. Get out alive."
## Small caps in the bottom right corner. Empty hides it.
var location_text := ""
## True when a 3D scene plays behind the screen; false draws a flat backdrop.
var over_scene := false
## Seconds the black takes to lift, and the stagger of the title coming in.
var fade_in_time := 1.6
var reveal_delay := 0.9
var reveal_step := 0.18
var leave_time := 0.8
## What the screen fades to on Start, after `leave_delay` seconds.
var leave_color := Color.BLACK
var leave_delay := 0.0
## Side and bottom margins of the corner text and the hint, in pixels.
var margin := Vector2(96, 36)

var start_button: Button
var _curtain: ColorRect
var _rule: ColorRect
var _reveal: Array[Control] = []
var _started := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if over_scene:
		_add_shade()
	else:
		var back := ColorRect.new()
		back.color = BACKDROP_COLOR
		back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(back)
	_build_title_block()
	if location_text != "":
		var corner := _label(location_text.to_upper(), 16, FAINT, 3)
		corner.anchor_left = 1.0
		corner.anchor_right = 1.0
		corner.anchor_top = 1.0
		corner.anchor_bottom = 1.0
		corner.offset_left = -560
		corner.offset_right = -margin.x
		corner.offset_top = -margin.y - 22
		corner.offset_bottom = -margin.y
		corner.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		add_child(corner)
		_reveal.append(corner)
	_curtain = ColorRect.new()
	_curtain.color = Color.BLACK
	_curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_curtain)
	start_button.grab_focus()
	_play_intro()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER or event.keycode == KEY_SPACE):
		press_start()
		get_viewport().set_input_as_handled()


## Starts the game. Only the first press counts.
func press_start() -> void:
	if _started:
		return
	_started = true
	start_button.disabled = true
	start_pressed.emit()


## Fades the screen to black. Returns once it is black.
func leave() -> void:
	var tween := create_tween().set_parallel()
	_curtain.color = Color(leave_color, 0.0)
	tween.tween_property(_curtain, "color:a", 1.0, leave_time).set_delay(leave_delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	for item: Control in _reveal + [_rule]:
		tween.tween_property(item, "modulate:a", 0.0, leave_time * 0.5)
	await tween.finished


func _build_title_block() -> void:
	var box := VBoxContainer.new()
	# Centred left to right, in the lower third: the lane's vanishing point
	# stays clear above it, and the type sits on the dark band at the bottom.
	box.anchor_left = 0.0
	box.anchor_right = 1.0
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_top = -margin.y - 400
	box.offset_bottom = -margin.y - 62
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", 10)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	var title := _label(title_text, 84, INK, 12)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_reveal.append(title)
	# A short amber rule under the title: the one accent on the screen.
	_rule = ColorRect.new()
	_rule.color = UiTheme.ACCENT
	_rule.custom_minimum_size = Vector2(72, 3)
	_rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_rule)
	var tagline := _label(tagline_text, 24, QUIET, 1)
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(tagline)
	_reveal.append(tagline)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 22)
	box.add_child(gap)
	start_button = Button.new()
	start_button.text = "START"
	start_button.focus_mode = Control.FOCUS_ALL
	start_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	start_button.custom_minimum_size = Vector2(240, 52)
	start_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var dim := UiTheme.ACCENT
	start_button.add_theme_stylebox_override("normal", _frame(Color(0.02, 0.025, 0.05, 0.75), dim, 2))
	start_button.add_theme_stylebox_override("focus", _frame(Color(0, 0, 0, 0), dim, 2))
	start_button.add_theme_stylebox_override("hover", _frame(dim, dim, 2))
	start_button.add_theme_stylebox_override("hover_pressed", _frame(dim.lightened(0.2), dim, 2))
	start_button.add_theme_stylebox_override("pressed", _frame(dim.lightened(0.2), dim, 2))
	start_button.add_theme_stylebox_override("disabled", _frame(dim, dim, 2))
	start_button.add_theme_font_override("font", _spaced(8))
	start_button.add_theme_font_size_override("font_size", 28)
	start_button.add_theme_color_override("font_color", INK)
	start_button.add_theme_color_override("font_focus_color", INK)
	start_button.add_theme_color_override("font_hover_color", INK_DARK)
	start_button.add_theme_color_override("font_pressed_color", INK_DARK)
	start_button.add_theme_color_override("font_hover_pressed_color", INK_DARK)
	start_button.add_theme_color_override("font_disabled_color", INK_DARK)
	start_button.pressed.connect(press_start)
	box.add_child(start_button)
	_reveal.append(start_button)
	# How to start, along the bottom: "PRESS [SPACE] OR CLICK START".
	var hint := HBoxContainer.new()
	hint.anchor_left = 0.0
	hint.anchor_right = 1.0
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_top = -margin.y - 34
	hint.offset_bottom = -margin.y
	hint.alignment = BoxContainer.ALIGNMENT_CENTER
	hint.add_theme_constant_override("separation", 12)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)
	_reveal.append(hint)
	# Kept faint: it is a reminder, the button is what to look at.
	hint.set_meta("faint", 0.45)
	var press := _label("PRESS", 16, QUIET, 3)
	press.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hint.add_child(press)
	var key := PanelContainer.new()
	var cap := _frame(Color(0.02, 0.025, 0.05, 0.6), QUIET, 1)
	cap.content_margin_left = 12
	cap.content_margin_right = 12
	cap.content_margin_top = 3
	cap.content_margin_bottom = 3
	key.add_theme_stylebox_override("panel", cap)
	key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key.add_child(_label("SPACE", 16, INK, 3))
	hint.add_child(key)
	var or_click := _label("OR CLICK START", 16, QUIET, 3)
	or_click.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hint.add_child(or_click)


## The title block comes in once the scene is up: the black lifts, then the
## title, rule, tagline and Start rise into place one after another.
func _play_intro() -> void:
	var tween := create_tween().set_parallel()
	tween.tween_property(_curtain, "color:a", 0.0, fade_in_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var delay := reveal_delay
	for item in _reveal:
		item.modulate.a = 0.0
		tween.tween_property(item, "modulate:a", item.get_meta("faint", 1.0), 0.7).set_delay(delay)
		delay += reveal_step
	_rule.custom_minimum_size.x = 0.0
	tween.tween_property(_rule, "custom_minimum_size:x", 72.0, 0.8) \
			.set_delay(reveal_delay + reveal_step).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _frame(fill: Color, edge: Color, border: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(border)
	box.set_corner_radius_all(2)
	box.content_margin_left = 28
	box.content_margin_right = 28
	return box


## Dark washes under the title block so the type reads over whatever plays
## behind it: a band along the bottom and a pool behind the title.
func _add_shade() -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.01, 0.01, 0.03, 0.0))
	gradient.set_color(1, Color(0.01, 0.01, 0.03, 0.85))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(0, 1)
	var shade := TextureRect.new()
	shade.texture = texture
	shade.anchor_right = 1.0
	shade.anchor_top = 0.4
	shade.anchor_bottom = 1.0
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	# And a soft pool of shadow behind the title block in the middle, so the
	# lane dims there. Radial, so it has no edge to spot.
	var pool := Gradient.new()
	pool.set_color(0, Color(0.01, 0.01, 0.03, 0.75))
	pool.set_color(1, Color(0.01, 0.01, 0.03, 0.0))
	var pool_texture := GradientTexture2D.new()
	pool_texture.gradient = pool
	pool_texture.fill = GradientTexture2D.FILL_RADIAL
	pool_texture.fill_from = Vector2(0.5, 0.5)
	pool_texture.fill_to = Vector2(1.0, 0.5)
	var wash := TextureRect.new()
	wash.texture = pool_texture
	wash.anchor_left = 0.15
	wash.anchor_right = 0.85
	wash.anchor_top = 0.45
	wash.anchor_bottom = 1.05
	wash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wash.stretch_mode = TextureRect.STRETCH_SCALE
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wash)


func _label(text: String, size: int, color: Color, spacing: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", _spaced(spacing))
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.02, 0.55))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## The game's font, tracked out by `spacing` pixels a letter.
func _spaced(spacing: int) -> FontVariation:
	var font := FontVariation.new()
	font.base_font = ThemeDB.fallback_font
	var own := load(UiTheme.FONT_PATH) as Font
	if own:
		font.base_font = own
	font.spacing_glyph = spacing
	return font
