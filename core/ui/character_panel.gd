extends VBoxContainer
## Hub section for how your character looks. A button opens the customizer:
## a turning preview beside pickers for the build, each body part, and the
## skin, hair and clothing colours. The choice is cosmetic only. It is kept in
## the local profile, and online it is sent to the server so others see it.

const Human := preload("res://core/visual/human.gd")

## The look changed. The hub's owner saves it and passes it on.
signal changed(appearance: Dictionary)

## The look being edited. Always a valid appearance.
var appearance := {}

var _summary: Label
var _overlay: Control
var _pickers := {}
var _stage: Node3D
var _model: Node3D
var _viewport: SubViewport
var _turn := 0.6


func _ready() -> void:
	appearance = Human.sanitize(appearance)
	add_theme_constant_override("separation", 4)
	add_child(_label("CHARACTER", 20, Color(1.0, 0.55, 0.25)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	_summary = _label("", 15, Color(0.85, 0.85, 0.85))
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_summary)
	var open := Button.new()
	open.text = "Customize"
	open.custom_minimum_size = Vector2(160, 0)
	open.pressed.connect(show_customizer)
	row.add_child(open)
	_refresh_summary()


## Shows a look without announcing a change, e.g. the one loaded from disk.
func set_appearance(p_appearance: Variant) -> void:
	appearance = Human.sanitize(p_appearance)
	_refresh_summary()
	if _overlay:
		_sync_pickers()
		_rebuild_preview()


## What each picker offers, in order: [[value, label], ...]. "build" and the
## part slots hold names; colour keys hold indexes.
func options_for(key: String) -> Array:
	var out := []
	if key == "build":
		for build in Human.BUILDS:
			out.append([build, Human.BUILD_NAMES[build]])
	elif key in Human.SLOTS:
		var outfits: Dictionary = Human.OUTFITS[appearance["build"]]
		for outfit: String in outfits:
			out.append([outfit, outfits[outfit]])
	else:
		var names: Array = Human.COLOR_KEYS[key][1]
		for i in names.size():
			out.append([i, names[i]])
	return out


## Changes one choice. Switching build keeps the colours and resets the parts,
## since each build has its own outfits.
func choose(key: String, value: Variant) -> void:
	var next := appearance.duplicate()
	next[key] = value
	_apply(Human.sanitize(next))


func randomize_look() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var next := Human.random(rng)
	next["top"] = rng.randi() % Human.CLOTH_COLORS.size()
	next["bottom"] = rng.randi() % Human.CLOTH_COLORS.size()
	_apply(Human.sanitize(next))


func _apply(next: Dictionary) -> void:
	if next == appearance:
		return
	appearance = next
	_refresh_summary()
	if _overlay:
		_sync_pickers()
		_rebuild_preview()
	changed.emit(appearance.duplicate())


func _refresh_summary() -> void:
	var outfits: Dictionary = Human.OUTFITS[appearance["build"]]
	var parts: Array[String] = []
	for slot in Human.SLOTS:
		parts.append("%s %s" % [outfits[appearance[slot]], Human.SLOT_NAMES[slot].to_lower()])
	_summary.text = "%s: %s." % [Human.BUILD_NAMES[appearance["build"]], ", ".join(parts)]


func show_customizer() -> void:
	if _overlay == null:
		_build_overlay()
	_sync_pickers()
	_rebuild_preview()
	_overlay.visible = true


func hide_customizer() -> void:
	if _overlay:
		_overlay.visible = false


func is_customizing() -> bool:
	return _overlay != null and _overlay.visible


func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.name = "Customizer"
	_overlay.top_level = true
	_overlay.z_index = 20
	add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.size = get_viewport_rect().size
	get_viewport().size_changed.connect(func() -> void: _overlay.size = get_viewport_rect().size)
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.03, 0.04, 1.0)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 32)
	center.add_child(columns)

	var frame := SubViewportContainer.new()
	frame.custom_minimum_size = Vector2(460, 640)
	frame.stretch = true
	columns.add_child(frame)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	frame.add_child(_viewport)
	_build_stage()

	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(380, 0)
	side.add_theme_constant_override("separation", 8)
	columns.add_child(side)
	side.add_child(_label("YOUR CHARACTER", 28, Color(1.0, 0.55, 0.25)))
	side.add_child(_label("Looks only. Nothing here changes how you play.", 13, Color(0.65, 0.65, 0.65)))
	_add_picker(side, "build", "Build")
	for slot in Human.SLOTS:
		_add_picker(side, slot, Human.SLOT_NAMES[slot])
	for key: String in Human.COLOR_KEYS:
		_add_picker(side, key, Human.COLOR_KEYS[key][0])
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	side.add_child(buttons)
	var shuffle := Button.new()
	shuffle.text = "Randomize"
	shuffle.custom_minimum_size = Vector2(0, 44)
	shuffle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shuffle.pressed.connect(randomize_look)
	buttons.add_child(shuffle)
	var done := Button.new()
	done.text = "Done"
	done.custom_minimum_size = Vector2(0, 44)
	done.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	done.pressed.connect(hide_customizer)
	buttons.add_child(done)


func _add_picker(box: VBoxContainer, key: String, title: String) -> void:
	var row := HBoxContainer.new()
	var name_label := _label(title, 16, Color(0.85, 0.85, 0.85))
	name_label.custom_minimum_size = Vector2(140, 0)
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(name_label)
	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.item_selected.connect(func(index: int) -> void: choose(key, options_for(key)[index][0]))
	row.add_child(picker)
	box.add_child(row)
	_pickers[key] = picker


func _sync_pickers() -> void:
	for key: String in _pickers:
		var picker: OptionButton = _pickers[key]
		picker.clear()
		var options := options_for(key)
		for i in options.size():
			picker.add_item(options[i][1])
			if options[i][0] == appearance[key]:
				picker.select(i)


## A small lit room for the preview: the model on a turntable, a camera, a
## key light and a rim light.
func _build_stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.075, 0.085)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.65)
	env.ambient_light_energy = 0.9
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, -40, 0)
	key.light_energy = 1.6
	_viewport.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 150, 0)
	rim.light_color = Color(0.6, 0.75, 1.0)
	rim.light_energy = 0.8
	_viewport.add_child(rim)
	var camera := Camera3D.new()
	camera.fov = 32.0
	camera.position = Vector3(0, 1.0, 3.9)
	_viewport.add_child(camera)
	camera.look_at(Vector3(0, 0.95, 0))
	_stage = Node3D.new()
	_stage.name = "Turntable"
	_viewport.add_child(_stage)


func _rebuild_preview() -> void:
	if _stage == null or not Look.enabled:
		return
	if _model:
		_model.queue_free()
		_model = null
	var built: Dictionary = Look.character(Look.DEFAULT_SKIN, appearance)
	if built.is_empty():
		return
	_model = built["model"]
	_stage.add_child(_model)
	var player := _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player:
		for anim_name in player.get_animation_list():
			if String(anim_name).get_slice("|", String(anim_name).get_slice_count("|") - 1) == "Idle":
				player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
				player.play(anim_name)
				player.advance(0.0)
	Look.stand_model(_stage, _model, 1.8)


func _process(delta: float) -> void:
	if _stage and is_customizing():
		_turn += delta * 0.5
		_stage.rotation.y = _turn


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
