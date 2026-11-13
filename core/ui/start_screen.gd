class_name StartScreen
extends Control
## The first thing you see when the game launches: the title and Start, set
## low and to the left over the lane between worlds (`TitleBackdrop`, built
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
const QUIET := Color(0.74, 0.76, 0.82)
const FAINT := Color(0.6, 0.64, 0.74, 0.75)

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
## Left margin and bottom margin of the title block, in pixels.
var margin := Vector2(96, 84)

var start_button: Button
var _curtain: ColorRect
var _rule: ColorRect
var _marker: ColorRect
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
		var corner := _label(location_text.to_upper(), 14, FAINT, 3)
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
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = margin.x
	box.offset_right = margin.x + 900
	box.offset_top = -margin.y - 260
	box.offset_bottom = -margin.y
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	var title := _label(title_text, 84, INK, 10)
	box.add_child(title)
	_reveal.append(title)
	# A short amber rule under the title: the one accent on the screen.
	_rule = ColorRect.new()
	_rule.color = UiTheme.ACCENT
	_rule.custom_minimum_size = Vector2(72, 3)
	_rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_rule)
	var tagline := _label(tagline_text, 20, QUIET, 1)
	box.add_child(tagline)
	_reveal.append(tagline)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 30)
	box.add_child(gap)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	_reveal.append(row)
	# A small bar that lights and slides in when Start has focus or the mouse.
	var mark_slot := Control.new()
	mark_slot.custom_minimum_size = Vector2(16, 0)
	mark_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(mark_slot)
	_marker = ColorRect.new()
	_marker.color = UiTheme.ACCENT
	_marker.size = Vector2(4, 20)
	_marker.position = Vector2(0, 13)
	_marker.modulate.a = 0.0
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark_slot.add_child(_marker)
	start_button = Button.new()
	start_button.text = "START"
	start_button.flat = true
	start_button.focus_mode = Control.FOCUS_ALL
	start_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	start_button.custom_minimum_size = Vector2(0, 46)
	var empty := StyleBoxEmpty.new()
	for state: String in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		start_button.add_theme_stylebox_override(state, empty)
	start_button.add_theme_font_override("font", _spaced(6))
	start_button.add_theme_font_size_override("font_size", 26)
	start_button.add_theme_color_override("font_color", UiTheme.ACCENT.lerp(INK, 0.35))
	start_button.add_theme_color_override("font_focus_color", UiTheme.ACCENT)
	start_button.add_theme_color_override("font_hover_color", UiTheme.ACCENT.lightened(0.25))
	start_button.add_theme_color_override("font_pressed_color", Color.WHITE)
	start_button.add_theme_color_override("font_disabled_color", UiTheme.ACCENT)
	start_button.pressed.connect(press_start)
	start_button.focus_entered.connect(_mark.bind(true))
	start_button.focus_exited.connect(_mark.bind(false))
	start_button.mouse_entered.connect(_mark.bind(true))
	start_button.mouse_exited.connect(func() -> void: _mark(start_button.has_focus()))
	row.add_child(start_button)
	var hint := _label("ENTER", 14, FAINT, 4)
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(hint)


## The title block comes in once the scene is up: the black lifts, then the
## title, rule, tagline and Start rise into place one after another.
func _play_intro() -> void:
	var tween := create_tween().set_parallel()
	tween.tween_property(_curtain, "color:a", 0.0, fade_in_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var delay := reveal_delay
	for item in _reveal:
		item.modulate.a = 0.0
		tween.tween_property(item, "modulate:a", 1.0, 0.7).set_delay(delay)
		delay += reveal_step
	_rule.custom_minimum_size.x = 0.0
	tween.tween_property(_rule, "custom_minimum_size:x", 72.0, 0.8) \
			.set_delay(reveal_delay + reveal_step).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _mark(on: bool) -> void:
	if _marker == null:
		return
	var tween := create_tween().set_parallel()
	tween.tween_property(_marker, "position:x", 8.0 if on else 0.0, 0.18)
	tween.tween_property(_marker, "modulate:a", 1.0 if on else 0.0, 0.18)


## A soft dark band along the bottom so the type reads over whatever plays
## behind it. Kept low and faint: it is there for legibility, not as a look.
func _add_shade() -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.01, 0.01, 0.03, 0.0))
	gradient.set_color(1, Color(0.01, 0.01, 0.03, 0.7))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(0, 1)
	var shade := TextureRect.new()
	shade.texture = texture
	shade.anchor_right = 1.0
	shade.anchor_top = 0.5
	shade.anchor_bottom = 1.0
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)


func _label(text: String, size: int, color: Color, spacing: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", _spaced(spacing))
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 0)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
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
