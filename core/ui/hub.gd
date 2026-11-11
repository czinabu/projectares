class_name Hub
extends Control
## The between-raids screen: your stash, the last raid's result, and a deploy
## button for every world the registry found.

signal deploy_requested(world_id: String)

var _result: Label
var _stash: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.06, 0.07)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(720, 0)
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)

	box.add_child(_text("PROJECT ARES", 44, Color(1.0, 0.55, 0.25)))
	box.add_child(_text("The Junction: pick a world, drop in, get out with the loot.", 16, Color(0.8, 0.8, 0.8)))

	_result = _text("", 18, Color.WHITE)
	box.add_child(_result)
	_stash = _text("", 16, Color(0.85, 0.85, 0.85))
	box.add_child(_stash)

	for world in Worlds.all():
		var button := Button.new()
		button.text = "Deploy to %s" % world.display_name
		button.tooltip_text = world.description
		button.custom_minimum_size = Vector2(0, 52)
		button.add_theme_font_size_override("font_size", 22)
		button.pressed.connect(func() -> void: deploy_requested.emit(world.id))
		box.add_child(button)
		box.add_child(_text(world.description, 14, Color(0.65, 0.65, 0.65)))

	box.add_child(_text(
		"You deploy with a free scrap kit: rifle, blade, jetpack, light plate, medkit.\n"
		+ "Loot caches and bodies, then stand in a green exit zone to keep what you carry.\n"
		+ "Die and everything you carried stays in the raid.", 14, Color(0.65, 0.65, 0.65)))

	var quit := Button.new()
	quit.text = "Quit"
	quit.pressed.connect(func() -> void: get_tree().quit())
	box.add_child(quit)
	refresh({})


func refresh(last_result: Dictionary) -> void:
	match last_result.get("outcome", ""):
		"extracted":
			_result.text = "Extracted with %s (worth %d). Kills: %d." % [
				ItemDB.summarize(last_result.loot), last_result.loot_value, last_result.kills]
			_result.modulate = Color(0.45, 1.0, 0.6)
		"died":
			var cause: String = last_result.get("cause", "")
			var how := "The storm took you" if cause == "storm" else "You died"
			_result.text = "%s and lost %s." % [how, ItemDB.summarize(last_result.lost)]
			_result.modulate = Color(1.0, 0.45, 0.4)
		_:
			_result.text = ""
	_stash.text = "Stash: %s\nStash value %d   Raids %d   Extractions %d   Kills %d" % [
		ItemDB.summarize(Profile.stash), Profile.stash_value(),
		Profile.raids_played, Profile.raids_extracted, Profile.kills]


func _text(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
