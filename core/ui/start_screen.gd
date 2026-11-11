class_name StartScreen
extends Control
## The first thing you see when the game launches: the title and Start.
##
## `core/start.gd` (the project's main scene) shows it. `start_pressed` fires
## once, then the game scene loads and `main.gd` takes over (the game opens in your home base). Nothing else
## lives here on purpose: no options, no menu.
##

signal start_pressed

const TITLE_COLOR := Color(1.0, 0.62, 0.22)
const BACKDROP_COLOR := Color(0.035, 0.03, 0.04)

var title_text := "PROJECT ARES"
var tagline_text := "Take what you can carry. Get out alive."
## Seconds for one slow pulse of the ember glow behind the title.
var pulse_period := 4.0

var start_button: Button
var _glow: ColorRect
var _time := 0.0
var _started := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var back := ColorRect.new()
	back.color = BACKDROP_COLOR
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	_glow = ColorRect.new()
	_glow.color = Color(0.9, 0.35, 0.08, 0.10)
	_glow.anchor_left = 0.0
	_glow.anchor_right = 1.0
	_glow.anchor_top = 0.62
	_glow.anchor_bottom = 1.0
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_glow)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	add_child(box)
	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", TITLE_COLOR)
	box.add_child(title)
	var tagline := Label.new()
	tagline.text = tagline_text
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.add_theme_font_size_override("font_size", 18)
	tagline.add_theme_color_override("font_color", Color(0.7, 0.67, 0.64))
	box.add_child(tagline)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 30)
	box.add_child(gap)
	start_button = Button.new()
	start_button.text = "Start game"
	start_button.custom_minimum_size = Vector2(260, 52)
	start_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	start_button.add_theme_font_size_override("font_size", 22)
	start_button.pressed.connect(press_start)
	box.add_child(start_button)
	start_button.grab_focus()


func _process(delta: float) -> void:
	_time += delta
	if _glow:
		var wave := 0.5 + 0.5 * sin(_time * TAU / pulse_period)
		_glow.color.a = lerpf(0.05, 0.16, wave)


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
	start_pressed.emit()
