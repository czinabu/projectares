extends VBoxContainer
## Hub section for mastery: the level of each gear type in your loadout, a
## picker for its unlocked variants, and what the last raid earned.

const MasteryDB := preload("res://core/progression/mastery_db.gd")

var _earned: Label
var _rows: GridContainer


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	add_child(_label("MASTERY", 20, Color(1.0, 0.55, 0.25)))
	add_child(_label(
		"Using a type of gear levels it and unlocks variants that trade one strength for another. "
		+ "Kept when you die. Hover a variant for details.", 13, Color(0.65, 0.65, 0.65)))
	_earned = _label("", 14, Color(0.6, 0.85, 1.0))
	_earned.visible = false
	add_child(_earned)
	# Two tracks per line keeps the hub on one screen.
	_rows = GridContainer.new()
	_rows.columns = 2
	_rows.add_theme_constant_override("h_separation", 24)
	_rows.add_theme_constant_override("v_separation", 4)
	add_child(_rows)


## Rebuilds the rows for the gear currently in the loadout.
func refresh() -> void:
	for child in _rows.get_children():
		child.queue_free()
	for track in loadout_tracks():
		_rows.add_child(_track_row(track))


## Mastery tracks for each loadout slot: the equipped item, or the free scrap
## item that fills the slot when it is empty.
func loadout_tracks() -> Array[String]:
	var starter: Array[String] = []
	if not Worlds.all().is_empty():
		starter = Worlds.all()[0].starter_loadout()
	var out: Array[String] = []
	for slot: String in Loadout.SLOTS:
		var id := Profile.equipped(slot)
		if id == "":
			for free_id in starter:
				if ItemDB.has_tag(free_id, Loadout.SLOTS[slot]):
					id = free_id
					break
		var track := MasteryDB.track_for_item(id)
		if track != "" and track not in out:
			out.append(track)
	return out


## "Mastery earned: Rifle +120 (level 2!)" for a raid result, or "" for none.
func describe_earned(result: Dictionary) -> String:
	var gained: Dictionary = result.get("mastery_xp", {})
	if gained.is_empty():
		return ""
	var parts: Array[String] = []
	for track: String in gained:
		var now := Profile.mastery.level(track)
		var before := MasteryDB.level_for_xp(Profile.mastery.xp_for(track) - int(gained[track]))
		parts.append("%s +%d%s" % [MasteryDB.track_name(track), gained[track],
				" (level %d!)" % now if now > before else ""])
	return "Mastery earned: %s." % ", ".join(parts)


func show_result(result: Dictionary) -> void:
	_earned.text = describe_earned(result)
	_earned.visible = _earned.text != ""


func _track_row(track: String) -> Control:
	var book = Profile.mastery
	var level: int = book.level(track)
	var row := HBoxContainer.new()
	var progress := "max"
	if level < MasteryDB.max_level():
		progress = "%d/%d" % [book.xp_for(track), MasteryDB.next_level_xp(level)]
	var name_label := _label("%s  Lv %d" % [MasteryDB.track_name(track), level], 15, Color(0.85, 0.85, 0.85))
	name_label.custom_minimum_size = Vector2(170, 0)
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(name_label)
	var xp_label := _label(progress, 12, Color(0.6, 0.6, 0.6))
	xp_label.custom_minimum_size = Vector2(70, 0)
	xp_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	xp_label.tooltip_text = "XP toward the next level"
	xp_label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(xp_label)

	var picker := OptionButton.new()
	picker.custom_minimum_size = Vector2(150, 0)
	picker.add_item("Stock")
	picker.set_item_metadata(0, "")
	picker.set_item_tooltip(0, "No changes.")
	var picked: String = book.picked(track)
	for v: Dictionary in MasteryDB.variants(track):
		var unlocked: bool = book.is_unlocked(track, v.id)
		picker.add_item(v.name if unlocked else "%s (Lv %d)" % [v.name, v.level])
		var index := picker.item_count - 1
		picker.set_item_metadata(index, v.id)
		picker.set_item_disabled(index, not unlocked)
		picker.set_item_tooltip(index, v.desc)
		if v.id == picked:
			picker.select(index)
	picker.tooltip_text = variant_text(track, picked)
	picker.item_selected.connect(func(index: int) -> void:
		var id: String = picker.get_item_metadata(index)
		Profile.mastery.pick(track, id)
		Profile.save()
		picker.tooltip_text = variant_text(track, id))
	row.add_child(picker)
	return row


func variant_text(track: String, variant_id: String) -> String:
	var v := MasteryDB.variant(track, variant_id)
	return "%s: %s" % [v.name, v.desc] if not v.is_empty() else "Stock: no changes."


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
