class_name Hub
extends Control
## The between-raids screen: your stash, your loadout, the last raid's result,
## and a deploy button for every world the registry found.

signal deploy_requested(world_id: String)
## Start a server on this machine running `world_id`, then join it.
signal host_requested(world_id: String)
## Join the server at `address` ("host" or "host:port").
signal join_requested(address: String)

const MasteryPanel := preload("res://core/progression/mastery_panel.gd")

var _result: Label
var _stash: Label
var _loadout_box: VBoxContainer
var _pickers := {}
var _details := {}
var _mastery: MasteryPanel
var _online_status: Label
var _name_edit: LineEdit
var _address_edit: LineEdit
var _host_world: OptionButton


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := TextureRect.new()
	bg.texture = Look.backdrop()
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Scrolls when the hub is taller than the window, centered otherwise.
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(820, 0)
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)

	box.add_child(_text("PROJECT ARES", 40, Color(1.0, 0.55, 0.25)))
	box.add_child(_text("The Junction: pick your gear, drop in, get out with the loot.", 16, Color(0.8, 0.8, 0.8)))

	_result = _text("", 18, Color.WHITE)
	box.add_child(_result)

	box.add_child(_text("LOADOUT", 20, Color(1.0, 0.55, 0.25)))
	box.add_child(_text(
		"Gear you equip leaves your stash when you deploy. Extract and it comes back. Die and it is gone.\n"
		+ "Empty slots use the free scrap kit, which costs nothing and can never be stashed.",
		13, Color(0.65, 0.65, 0.65)))
	_loadout_box = VBoxContainer.new()
	_loadout_box.add_theme_constant_override("separation", 4)
	box.add_child(_loadout_box)
	for slot: String in Loadout.SLOTS:
		var row := HBoxContainer.new()
		var name_label := _text(Loadout.SLOT_NAMES[slot], 16, Color(0.85, 0.85, 0.85))
		name_label.custom_minimum_size = Vector2(170, 0)
		name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.add_child(name_label)
		var picker := OptionButton.new()
		picker.custom_minimum_size = Vector2(330, 0)
		picker.item_selected.connect(_on_picked.bind(slot))
		row.add_child(picker)
		var detail := _text("", 13, Color(0.65, 0.65, 0.65))
		detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(detail)
		_loadout_box.add_child(row)
		_pickers[slot] = picker
		_details[slot] = detail

	_mastery = MasteryPanel.new()
	box.add_child(_mastery)

	box.add_child(_text("STASH", 20, Color(1.0, 0.55, 0.25)))
	_stash = _text("", 15, Color(0.85, 0.85, 0.85))
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

	_build_online(box)

	var quit := Button.new()
	quit.text = "Quit"
	quit.pressed.connect(func() -> void: get_tree().quit())
	box.add_child(quit)
	refresh({})


func refresh(last_result: Dictionary) -> void:
	match last_result.get("outcome", ""):
		"extracted":
			var kept: Array = last_result.get("kept_gear", [])
			var left: Array = last_result.get("lost", [])
			_result.text = "Extracted with %s (worth %d). Kills: %d.%s%s" % [
				ItemDB.summarize(last_result.loot), last_result.loot_value, last_result.kills,
				"\nGear brought home: %s." % ItemDB.summarize(kept) if not kept.is_empty() else "",
				"\nLeft behind: %s." % ItemDB.summarize(left) if not left.is_empty() else ""]
			_result.modulate = Color(0.45, 1.0, 0.6)
		"died":
			var cause: String = last_result.get("cause", "")
			var how := "The storm took you" if cause == "storm" else "You died"
			_result.text = "%s and lost %s." % [how, ItemDB.summarize(last_result.lost)]
			_result.modulate = Color(1.0, 0.45, 0.4)
		_:
			_result.text = ""
	_mastery.show_result(last_result)
	Profile.validate_loadout()
	_refresh_loadout()
	_stash.text = "%s\nStash value %d   Raids %d   Extractions %d   Kills %d" % [
		ItemDB.summarize(Profile.stash), Profile.stash_value(),
		Profile.raids_played, Profile.raids_extracted, Profile.kills]


## Item ids in the stash that fit a slot, best first, without duplicates.
func options_for(slot: String) -> Array[String]:
	var out: Array[String] = []
	for id in Profile.stash:
		if ItemDB.has_tag(id, Loadout.SLOTS[slot]) and id not in out:
			out.append(id)
	out.sort_custom(func(a: String, b: String) -> bool: return ItemDB.item_value(a) > ItemDB.item_value(b))
	return out


func _refresh_loadout() -> void:
	for slot: String in Loadout.SLOTS:
		var picker: OptionButton = _pickers[slot]
		picker.clear()
		picker.add_item("None" if slot in Loadout.OPTIONAL_SLOTS else "Scrap kit (free)")
		picker.set_item_metadata(0, "")
		var equipped := Profile.equipped(slot)
		var selected := 0
		for id in options_for(slot):
			picker.add_item("%s  [%s]  x%d" % [ItemDB.item_name(id), ItemDB.rarity_name(id), Profile.stash.count(id)])
			var index := picker.item_count - 1
			picker.set_item_metadata(index, id)
			if id == equipped:
				selected = index
		picker.select(selected)
		var detail: Label = _details[slot]
		detail.text = ItemDB.item_description(equipped) if equipped != "" else "Nothing at risk."
	_mastery.refresh()


func _on_picked(index: int, slot: String) -> void:
	var id: String = _pickers[slot].get_item_metadata(index)
	if id == "":
		Profile.unequip(slot)
	else:
		Profile.equip(slot, id)
	_refresh_loadout()


func _text(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


## The online section: your name, hosting a raid on this machine, joining one.
func _build_online(box: VBoxContainer) -> void:
	box.add_child(_text("ONLINE (EARLY TEST)", 20, Color(1.0, 0.55, 0.25)))
	box.add_child(_text(
		"Play the same raid with other people. Host starts a server on this computer and joins it.\n"
		+ "Others on your network join with your computer's address. Loot and vehicles are not online yet.",
		13, Color(0.65, 0.65, 0.65)))
	var name_row := HBoxContainer.new()
	var name_label := _text("Your name", 16, Color(0.85, 0.85, 0.85))
	name_label.custom_minimum_size = Vector2(170, 0)
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_row.add_child(name_label)
	_name_edit = LineEdit.new()
	_name_edit.text = Profile.player_name
	_name_edit.max_length = 20
	_name_edit.custom_minimum_size = Vector2(330, 0)
	_name_edit.text_changed.connect(func(text: String) -> void: Profile.player_name = text)
	name_row.add_child(_name_edit)
	box.add_child(name_row)

	var host_row := HBoxContainer.new()
	_host_world = OptionButton.new()
	_host_world.custom_minimum_size = Vector2(170, 0)
	for world in Worlds.all():
		_host_world.add_item(world.display_name)
		_host_world.set_item_metadata(_host_world.item_count - 1, world.id)
	host_row.add_child(_host_world)
	var host := Button.new()
	host.text = "Host a raid and join it"
	host.custom_minimum_size = Vector2(330, 40)
	host.pressed.connect(func() -> void:
		Profile.save()
		host_requested.emit(_host_world.get_item_metadata(_host_world.selected)))
	host_row.add_child(host)
	box.add_child(host_row)

	var join_row := HBoxContainer.new()
	_address_edit = LineEdit.new()
	_address_edit.text = Profile.last_server
	_address_edit.placeholder_text = "Server address"
	_address_edit.custom_minimum_size = Vector2(170, 0)
	join_row.add_child(_address_edit)
	var join := Button.new()
	join.text = "Join a raid at this address"
	join.custom_minimum_size = Vector2(330, 40)
	join.pressed.connect(func() -> void:
		Profile.last_server = _address_edit.text.strip_edges()
		Profile.save()
		join_requested.emit(Profile.last_server))
	join_row.add_child(join)
	box.add_child(join_row)
	_online_status = _text("", 14, Color(1.0, 0.8, 0.4))
	box.add_child(_online_status)


func set_online_status(text: String) -> void:
	if _online_status:
		_online_status.text = text
