class_name Hub
extends Control
## The screens behind the stations of your home base, and the travel screen
## between places. The game never opens on this: it opens in your home base,
## and each station there (`STATIONS`) shows one part of it on its own screen
## in the room (`Main` puts this in a viewport shown on a `WorldScreen`):
## the locker your loadout, the mastery bench your variants, the wardrobe the
## customizer, the records board your stash and last life, the trader the
## shops, the launch pad a deploy button for every world, and the uplink the
## online section.
##
## It also keeps what is on show: the local profile, or the account a server
## keeps for you while you are in its lobby (`enter_lobby`).

signal deploy_requested(world_id: String)
## Start a server on this machine running `world_id`, then join it.
signal host_requested(world_id: String)
## Join the server at `address` ("host" or "host:port").
signal join_requested(address: String)
## In a server's lobby: change the loadout or a mastery pick there, deploy
## into its world, or disconnect.
signal online_equip_requested(slot: String, item_id: String)
signal online_pick_requested(track: String, variant_id: String)
signal online_deploy_requested
## In a server's lobby: buy from a hub shop, or sell stash items ("" sells all loot).
signal online_buy_requested(shop_id: String, item_id: String)
signal online_sell_requested(item_id: String, count: int)
signal online_leave_requested
## A station screen was put away (Esc or the button).
signal closed
## The player changed how their character looks.
signal look_changed(appearance: Dictionary)

const MasteryPanel := preload("res://core/progression/mastery_panel.gd")
const CharacterPanel := preload("res://core/ui/character_panel.gd")
const MasteryBook := preload("res://core/progression/mastery_book.gd")
const RenownLedger := preload("res://core/progression/renown_ledger.gd")
const ShopPanel := preload("res://core/economy/shop_panel.gd")
const Economy := preload("res://core/economy/economy.gd")

## Which sections of this screen each home base station shows. The stations
## themselves, with their titles, are `HomeBase.STATIONS`.
const STATIONS := {
	"launch": {"sections": ["deploy", "status"]},
	"locker": {"sections": ["loadout"]},
	"mastery": {"sections": ["mastery"]},
	"wardrobe": {"sections": ["character"]},
	"records": {"sections": ["records"]},
	"trader": {"sections": ["shop"]},
	"uplink": {"sections": ["online", "status"]},
}

## Your account on the server you are connected to (see
## `StashService.snapshot`). Empty when not in a lobby: the hub then shows
## the local profile.
var account := {}

var _result: Label
var _stash: Label
var _loadout_box: VBoxContainer
var _pickers := {}
var _details := {}
var _mastery: MasteryPanel
var _shop: ShopPanel
var character: CharacterPanel
var _online_status: Label
var _name_edit: LineEdit
var _address_edit: LineEdit
var _host_world: OptionButton
var _stash_title: Label
var _solo_box: VBoxContainer
var _connect_box: VBoxContainer
var _lobby_box: VBoxContainer
var _lobby_title: Label
var _lobby_deploy: Button
var _lobby_leave: Button
## The station whose screen is open, or "".
var station := ""
var _sections := {}
var _title: Label
var _backdrop: TextureRect
var _shade: ColorRect
var _close_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Travel: a full-screen backdrop. At a station: the screen's dark glass.
	_backdrop = TextureRect.new()
	_backdrop.texture = Look.backdrop()
	_backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_backdrop)
	_shade = ColorRect.new()
	_shade.color = Color(0.025, 0.03, 0.035)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_shade)

	# Scrolls when the screen is taller than the window, centered otherwise.
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

	_title = _text("PROJECT ARES", 40, Color(1.0, 0.55, 0.25))
	box.add_child(_title)

	var records := _section(box, "records")
	_result = _text("", 18, Color.WHITE)
	records.add_child(_result)
	_stash_title = _text("STASH", 20, Color(1.0, 0.55, 0.25))
	records.add_child(_stash_title)
	_stash = _text("", 15, Color(0.85, 0.85, 0.85))
	records.add_child(_stash)

	var locker := _section(box, "loadout")
	locker.add_child(_text("LOADOUT", 20, Color(1.0, 0.55, 0.25)))
	locker.add_child(_text(
		"Gear you equip leaves your stash when you deploy. Die and it is gone. Sign out alive (L) and it comes back.\n"
		+ "Bank loot at a depot to send it here without leaving.\n"
		+ "Empty slots use the free scrap kit, which costs nothing and can never be stashed.",
		13, Color(0.65, 0.65, 0.65)))
	_loadout_box = VBoxContainer.new()
	_loadout_box.add_theme_constant_override("separation", 4)
	locker.add_child(_loadout_box)
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
	_mastery.pick_requested.connect(func(track: String, variant_id: String) -> void:
		online_pick_requested.emit(track, variant_id))
	_section(box, "mastery").add_child(_mastery)

	character = CharacterPanel.new()
	character.appearance = Profile.appearance
	character.changed.connect(func(appearance: Dictionary) -> void: look_changed.emit(appearance))
	# The wardrobe opens the customizer itself; finishing there steps away.
	character.customizer_closed.connect(func() -> void:
		if station == "wardrobe":
			close())
	_section(box, "character").add_child(character)

	_shop = ShopPanel.new()
	_shop.buy_requested.connect(func(shop_id: String, item_id: String) -> void:
		online_buy_requested.emit(shop_id, item_id))
	_shop.sell_requested.connect(func(item_id: String, count: int) -> void:
		online_sell_requested.emit(item_id, count))
	_shop.changed.connect(_refresh_gear)
	_section(box, "shop").add_child(_shop)

	var deploy := _section(box, "deploy")
	_solo_box = VBoxContainer.new()
	_solo_box.add_theme_constant_override("separation", 10)
	deploy.add_child(_solo_box)
	_solo_box.add_child(_text("DEPLOY", 20, Color(1.0, 0.55, 0.25)))
	for world in Worlds.raid_worlds():
		var button := Button.new()
		button.text = "Deploy to %s" % world.display_name
		button.tooltip_text = world.description
		button.custom_minimum_size = Vector2(0, 52)
		button.add_theme_font_size_override("font_size", 22)
		button.pressed.connect(func() -> void: deploy_requested.emit(world.id))
		_solo_box.add_child(button)
		_solo_box.add_child(_text(world.description, 14, Color(0.65, 0.65, 0.65)))
	_build_lobby(deploy)

	var online := _section(box, "online")
	_connect_box = VBoxContainer.new()
	_connect_box.add_theme_constant_override("separation", 10)
	online.add_child(_connect_box)
	_build_online(_connect_box)
	_lobby_leave = Button.new()
	_lobby_leave.text = "Leave the server"
	_lobby_leave.custom_minimum_size = Vector2(0, 44)
	_lobby_leave.visible = false
	_lobby_leave.pressed.connect(func() -> void: online_leave_requested.emit())
	online.add_child(_lobby_leave)

	_online_status = _text("", 14, Color(1.0, 0.8, 0.4))
	_section(box, "status").add_child(_online_status)

	_close_button = Button.new()
	_close_button.text = "Step away  (Esc)"
	_close_button.custom_minimum_size = Vector2(0, 44)
	_close_button.pressed.connect(close)
	box.add_child(_close_button)
	refresh({})
	close()


## A titled part of the screen that a station shows on its own.
func _section(box: VBoxContainer, id: String) -> VBoxContainer:
	var section := VBoxContainer.new()
	section.name = id.capitalize()
	section.add_theme_constant_override("separation", 10)
	box.add_child(section)
	_sections[id] = section
	return section


## Opens what a station in the home base offers (a key of `STATIONS`) on
## this screen. Esc or the button steps away again.
## `also` names other stations whose sections this console shows as well (a
## starter base's shared consoles, see `HomeBase.also_shows`).
func open_station(id: String, also: Array = []) -> void:
	if not STATIONS.has(id):
		return
	station = id
	var sections: Array = STATIONS[id]["sections"].duplicate()
	var names: Array[String] = [str(HomeBase.STATIONS[id]["title"]) if HomeBase.STATIONS.has(id) else id]
	for other: Variant in also:
		if not STATIONS.has(other):
			continue
		names.append(str(HomeBase.STATIONS[other]["title"]) if HomeBase.STATIONS.has(other) else str(other))
		for section: String in STATIONS[other]["sections"]:
			if section not in sections:
				sections.append(section)
	_show_only(sections)
	_title.text = " AND ".join(names).to_upper()
	_title.add_theme_font_size_override("font_size", 30)
	_backdrop.visible = false
	_shade.visible = true
	_close_button.visible = true
	visible = true
	if id == "wardrobe":
		character.show_customizer()


## The screen between places (connecting, travelling): the backdrop and a
## line on what is happening. Set the line with `set_online_status`.
func show_travel() -> void:
	station = ""
	character.hide_customizer()
	_show_only(["status"])
	_title.text = "PROJECT ARES"
	_title.add_theme_font_size_override("font_size", 40)
	_backdrop.visible = true
	_shade.visible = false
	_close_button.visible = false
	visible = true


## Puts the screen away: back to the world.
func close() -> void:
	var was := station
	station = ""
	if character:
		character.hide_customizer()
	visible = false
	if was != "":
		closed.emit()


func is_open() -> bool:
	return visible


func _show_only(ids: Array) -> void:
	for id: String in _sections:
		_sections[id].visible = id in ids


func _unhandled_input(event: InputEvent) -> void:
	if station != "" and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()


## How the last life ended, in a line or two. "" when there is nothing to say.
func result_text() -> String:
	return _result.text if _result else ""


func refresh(last_result: Dictionary) -> void:
	match last_result.get("outcome", ""):
		"left":
			var kept: Array = last_result.get("kept_gear", [])
			var left: Array = last_result.get("lost", [])
			_result.text = "Left alive with %s (worth %d). Kills: %d.%s%s" % [
				ItemDB.summarize(last_result.loot), last_result.loot_value, last_result.kills,
				"\nGear brought home: %s." % ItemDB.summarize(kept) if not kept.is_empty() else "",
				"\nLeft behind: %s." % ItemDB.summarize(left) if not left.is_empty() else ""]
			_result.modulate = Color(0.45, 1.0, 0.6)
		"died":
			var by: String = last_result.get("killed_by", "")
			var how := "%s killed you" % by if by != "" else "You died"
			var saved: Array = last_result.get("kept_gear", [])
			_result.text = "%s and you lost %s.%s" % [how, ItemDB.summarize(last_result.lost),
				"\nYour equipped gear came home: %s." % ItemDB.summarize(saved) if not saved.is_empty() else ""]
			_result.modulate = Color(1.0, 0.45, 0.4)
		_:
			_result.text = ""
	var bounty := Economy.payout(last_result)
	if bounty > 0:
		_result.text += "\nScrip brought home: +%d scrip." % bounty
	_mastery.show_result(last_result)
	_refresh_gear()


## Redraws the loadout and stash, keeping the last raid's result on screen.
func refresh_gear() -> void:
	_refresh_gear()


## The loadout on show: slot -> item id. The server's while in a lobby.
func current_loadout() -> Dictionary:
	return account.get("loadout", {}) if in_lobby() else Profile.loadout


func _refresh_gear() -> void:
	if not in_lobby():
		Profile.validate_loadout()
	_refresh_loadout()
	var record: Variant = account if in_lobby() else Profile
	var lifetime := int(record.get("renown")) if record.get("renown") != null else 0
	_stash.text = "%s\nStash value %d   Drops %d   Left alive %d   Kills %d\n%s" % [
		ItemDB.summarize(stash_items()), ItemDB.total_value(stash_items()),
		record.get("raids_played"), record.get("raids_extracted"), record.get("kills"),
		renown_text(lifetime)]
	_shop.refresh()
	# Clothing in the stash unlocks its outfits in the customizer.
	character.owned = Economy.unlocked_outfits(stash_items())
	character.set_appearance(Profile.appearance)


## Rank and lifetime renown, as shown under the stash.
static func renown_text(lifetime: int) -> String:
	var rank := RenownLedger.rank_name(RenownLedger.rank_for(lifetime))
	var more := RenownLedger.to_next_rank(lifetime)
	if more <= 0:
		return "Rank %s   Renown %d" % [rank, lifetime]
	return "Rank %s   Renown %d   (%d to %s)" % [rank, lifetime, more,
			RenownLedger.rank_name(RenownLedger.rank_for(lifetime) + 1)]


## Item ids in the stash that fit a slot, best first, without duplicates.
func options_for(slot: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in stash_items():
		if Loadout.fits(slot, id) and id not in out:
			out.append(id)
	out.sort_custom(func(a: String, b: String) -> bool: return ItemDB.item_value(a) > ItemDB.item_value(b))
	return out


func _refresh_loadout() -> void:
	for slot: String in Loadout.SLOTS:
		var picker: OptionButton = _pickers[slot]
		picker.clear()
		picker.add_item("None" if slot in Loadout.OPTIONAL_SLOTS else "Scrap kit (free)")
		picker.set_item_metadata(0, "")
		var worn := equipped(slot)
		var selected := 0
		for id in options_for(slot):
			picker.add_item("%s  [%s]  x%d" % [ItemDB.item_name(id), ItemDB.rarity_name(id), stash_items().count(id)])
			var index := picker.item_count - 1
			picker.set_item_metadata(index, id)
			if id == worn:
				selected = index
		picker.select(selected)
		var detail: Label = _details[slot]
		detail.text = ItemDB.item_description(worn) if worn != "" else "Nothing at risk."
	_mastery.refresh()


func _on_picked(index: int, slot: String) -> void:
	var id: String = _pickers[slot].get_item_metadata(index)
	if in_lobby():
		# The server decides. The hub redraws when the account comes back.
		online_equip_requested.emit(slot, id)
		return
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
		"Fight in the same world as other people. Host starts a server on this computer and joins it.\n"
		+ "Others on your network join with your computer's address.",
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
	for world in Worlds.raid_worlds():
		_host_world.add_item(world.display_name)
		_host_world.set_item_metadata(_host_world.item_count - 1, world.id)
	host_row.add_child(_host_world)
	var host := Button.new()
	host.text = "Host a world and join it"
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
	join.text = "Join a world at this address"
	join.custom_minimum_size = Vector2(330, 40)
	join.pressed.connect(func() -> void:
		Profile.last_server = _address_edit.text.strip_edges()
		Profile.save()
		join_requested.emit(Profile.last_server))
	join_row.add_child(join)
	box.add_child(join_row)


## The lobby part of the launch pad, shown instead of the solo deploy
## buttons while connected to a server.
func _build_lobby(box: VBoxContainer) -> void:
	_lobby_box = VBoxContainer.new()
	_lobby_box.add_theme_constant_override("separation", 10)
	_lobby_box.visible = false
	box.add_child(_lobby_box)
	_lobby_title = _text("", 20, Color(1.0, 0.55, 0.25))
	_lobby_box.add_child(_lobby_title)
	_lobby_box.add_child(_text(
		"The gear in this base is the stash this server keeps for you. "
		+ "It is separate from your solo stash.", 13, Color(0.65, 0.65, 0.65)))
	_lobby_deploy = Button.new()
	_lobby_deploy.custom_minimum_size = Vector2(0, 52)
	_lobby_deploy.add_theme_font_size_override("font_size", 22)
	_lobby_deploy.pressed.connect(func() -> void: online_deploy_requested.emit())
	_lobby_box.add_child(_lobby_deploy)


## What the lobby's leave button says: it leads back to the plaza when the
## server has one.
func set_leave_text(text: String) -> void:
	_lobby_leave.text = text


func leave_text() -> String:
	return _lobby_leave.text


func in_lobby() -> bool:
	return not account.is_empty()


## Switches the hub to the account a server keeps for you. `world` is the
## world that server runs.
func enter_lobby(p_account: Dictionary, world: WorldDef) -> void:
	_lobby_title.text = "CONNECTED AS %s" % str(p_account.get("name", "")).to_upper()
	_lobby_deploy.text = "Deploy online to %s" % world.display_name
	_lobby_deploy.tooltip_text = world.description
	update_account(p_account)


## Shows a fresh copy of the server's account.
func update_account(p_account: Dictionary) -> void:
	account = p_account
	var book := MasteryBook.new()
	book.load_dict(account.get("mastery", {}))
	_mastery.book = book
	_mastery.loadout = account.get("loadout", {})
	_shop.account = account
	_show_sections()
	_refresh_gear()


## Back to the local profile.
func leave_lobby() -> void:
	account = {}
	_mastery.book = null
	_mastery.loadout = null
	_shop.account = null
	_show_sections()
	_refresh_gear()


func _show_sections() -> void:
	_lobby_box.visible = in_lobby()
	_solo_box.visible = not in_lobby()
	_connect_box.visible = not in_lobby()
	_lobby_leave.visible = in_lobby()
	_stash_title.text = "STASH ON THIS SERVER" if in_lobby() else "STASH"


func stash_items() -> Array:
	return account.get("stash", []) if in_lobby() else Profile.stash


## The home base upgrades on show: the server's account's, or the profile's.
func base_upgrades() -> Array:
	return account.get("base_upgrades", []) if in_lobby() else Profile.base_upgrades


## The scrip on show: the server's account's, or the profile's.
func scrip() -> int:
	return int(account.get("scrip", 0)) if in_lobby() else Profile.scrip


func equipped(slot: String) -> String:
	return account.get("loadout", {}).get(slot, "") if in_lobby() else Profile.equipped(slot)


func set_online_status(text: String) -> void:
	if _online_status:
		_online_status.text = text
