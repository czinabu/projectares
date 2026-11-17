extends VBoxContainer
## The fabricator's screen on the gunsmith bench: every recipe, what it
## costs against what the stash holds, and a button to craft it. Recipes
## whose blueprint is not known yet are listed dim, so there is something to
## hunt for.
##
## Solo it crafts with the local `Profile`. Online, set `account` to the
## server's snapshot: the panel then only asks (`craft_requested`) and shows
## whatever the server sends back.
##
## Load with `const CraftPanel := preload("res://core/progression/craft_panel.gd")`.

const Crafting := preload("res://core/progression/crafting.gd")

const TITLE_COLOR := Color(1.0, 0.55, 0.25)
const SCRIP_COLOR := Color(1.0, 0.85, 0.4)

## Online: the server decides, so nothing changes until `account` is updated.
signal craft_requested(item_id: String)
## Solo: the local profile's stash or scrip changed.
signal changed

## Online: the server's account snapshot. Null means the local profile.
var account: Variant = null

var _scrip: Label
var _known: Label
var _rows: VBoxContainer
var _message: Label


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	var head := HBoxContainer.new()
	var title := _label("BLUEPRINTS", 20, TITLE_COLOR)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_scrip = _label("", 18, SCRIP_COLOR)
	head.add_child(_scrip)
	add_child(head)
	add_child(_label(
		"Bring a blueprint home and it is yours for good. Each craft takes parts from your stash and a fee, "
		+ "and a Mk2 or Mk3 takes upgrade data. What you craft is ordinary gear: lose it and you craft another.",
		13, Color(0.65, 0.65, 0.65), true))
	_known = _label("", 14, Color(0.85, 0.85, 0.85), true)
	add_child(_known)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 3)
	add_child(_rows)
	_message = _label("", 14, Color(1.0, 0.8, 0.4))
	_message.visible = false
	add_child(_message)
	refresh()


func scrip() -> int:
	return int(account.get("scrip", 0)) if account != null else Profile.scrip


func stash_items() -> Array:
	return account.get("stash", []) if account != null else Profile.stash


## The blueprints known: the server's account's, or the profile's.
func blueprints() -> Array:
	return account.get("blueprints", []) if account != null else Profile.blueprints


## Why `item_id` cannot be crafted right now, or "".
func blocked(item_id: String) -> String:
	return Crafting.blocked(stash_items(), blueprints(), scrip(), item_id)


## What a craft costs, with what the stash holds of each part:
## "3 Upgrade Data (have 1), 2 Power Cell (have 4), 400 scrip".
func cost_text(item_id: String) -> String:
	var parts: Array[String] = []
	var need := Crafting.needs(item_id)
	for part: String in need:
		parts.append("%d %s (have %d)" % [need[part], ItemDB.item_name(part), stash_items().count(part)])
	parts.append("%d scrip" % Crafting.fee(item_id))
	return ", ".join(parts)


## Crafts one item: asks the server online, crafts with the profile solo.
func craft(item_id: String) -> void:
	if account != null:
		craft_requested.emit(item_id)
		return
	var result := Profile.craft(item_id)
	show_message("Crafted %s. It is in your stash." % ItemDB.item_name(item_id) if result.ok
			else str(result.get("error", "")))
	refresh()
	if result.ok:
		changed.emit()


func show_message(text: String) -> void:
	if _message:
		_message.text = text
		_message.visible = text != ""


func refresh() -> void:
	if _rows == null:
		return
	_scrip.text = "%d scrip" % scrip()
	_known.text = "Blueprints known: %d of %d.   Upgrade data: %d." % [
			blueprints().size(), Crafting.blueprints().size(), stash_items().count(Crafting.UPGRADE_DATA)]
	for child in _rows.get_children():
		# Taken out at once, so the new rows can keep their names.
		_rows.remove_child(child)
		child.queue_free()
	for id in Crafting.ids():
		var known: bool = Crafting.blueprint_of(id) in blueprints()
		var why := blocked(id)
		var row := HBoxContainer.new()
		row.name = "Recipe_%s" % id
		var name_label := _label(ItemDB.item_name(id), 15, ItemDB.RARITY_COLORS[ItemDB.item_rarity(id)])
		name_label.custom_minimum_size = Vector2(190, 0)
		row.add_child(name_label)
		var detail := _label(cost_text(id) if known else "Blueprint not found yet. It is out there in the war.",
				13, Color(0.7, 0.7, 0.7), true)
		detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(detail)
		var button := Button.new()
		button.name = "Craft"
		button.text = "Craft" if known else "Unknown"
		button.tooltip_text = why
		button.disabled = why != ""
		button.custom_minimum_size = Vector2(130, 0)
		button.pressed.connect(craft.bind(id))
		row.add_child(button)
		row.modulate = Color.WHITE if known else Color(1, 1, 1, 0.5)
		_rows.add_child(row)


func _label(text: String, font_size: int, color: Color, wrap := false) -> Label:
	var label := Label.new()
	label.text = text
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
