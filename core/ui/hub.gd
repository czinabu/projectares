class_name Hub
extends Control
## The screens behind the stations of your home base, and the travel screen
## between places. The game never opens on this: it opens in your home base,
## and each station there (`STATIONS`) shows one part of it on its own screen
## in the room (`Main` puts this in a viewport shown on a `WorldScreen`):
## the locker your loadout, the mastery bench your variants, the records
## board your stash and last life, and the trader the shops. The wardrobe is
## a mirror, not a screen: it opens the phone's Mirror app, which scrolls
## through `character` (kept here, never shown). Going online is the
## phone's Servers app, not a station. There is no deploy screen: you
## leave for a world through a squad portal opened from the watch.
##
## It also keeps what is on show: the local profile, or the account a server
## keeps for you while you are in its lobby (`enter_lobby`).

## In a server's lobby: change the loadout or a mastery pick there.
signal online_equip_requested(slot: String, item_id: String)
signal online_pick_requested(track: String, variant_id: String)
## In a server's lobby: buy from a hub shop, or sell stash items ("" sells all loot).
signal online_buy_requested(shop_id: String, item_id: String)
signal online_sell_requested(item_id: String, count: int)
## In a server's lobby: craft one item at the gunsmith bench.
signal online_craft_requested(item_id: String)
## In a server's lobby: "insure" a stash item or "cancel" the policy.
signal online_insure_requested(action: String, item_id: String)
## The line on going online changed (`set_online_status`). The phone's
## Servers app shows it too.
signal online_status_changed(text: String)
## A station screen was put away (Esc or the button).
signal closed
## The player changed how their character looks.
signal look_changed(appearance: Dictionary)

const StashRules := preload("res://core/account/stash_rules.gd")
const MasteryPanel := preload("res://core/progression/mastery_panel.gd")
const CharacterPanel := preload("res://core/ui/character_panel.gd")
const MasteryBook := preload("res://core/progression/mastery_book.gd")
const RenownLedger := preload("res://core/progression/renown_ledger.gd")
const ShopPanel := preload("res://core/economy/shop_panel.gd")
const Economy := preload("res://core/economy/economy.gd")
const CraftPanel := preload("res://core/progression/craft_panel.gd")
const InsurePanel := preload("res://core/economy/insure_panel.gd")
const ItemCard := preload("res://core/ui/item_card.gd")
const TerminalStyle := preload("res://core/ui/terminal_style.gd")
const SafetyNets := preload("res://core/economy/safety_nets.gd")

## How wide a station's screen is laid out: the list and the item card.
const SCREEN_WIDTH := 1180.0

## Which sections of this screen each home base station shows. The stations
## themselves, with their titles, are `HomeBase.STATIONS`.
const STATIONS := {
	"locker": {"sections": ["loadout"]},
	"mastery": {"sections": ["mastery"]},
	"records": {"sections": ["records"]},
	"trader": {"sections": ["shop"]},
	# The fabricator on the gunsmith bench (`HomeBase.CraftConsole`).
	# Insurance is taken out there too, beside the crafting (`InsurePanel`).
	"craft": {"sections": ["craft", "insure"], "title": "Fabricator", "prompt": "Craft from your blueprints"},
}

## Your account on the server you are connected to (see
## `StashService.snapshot`). Empty when not in a lobby: the hub then shows
## the local profile.
var account := {}

var _result: Label
var _stash: Label
var _loadout_box: VBoxContainer
var _pickers := {}
## The locker's rows by slot, and the card beside them.
var _slot_rows := {}
var _locker_card: ItemCard
## The records board's stash list and its card.
var _stash_rows: VBoxContainer
var _stash_card: ItemCard
var _mastery: MasteryPanel
var _shop: ShopPanel
var _craft: CraftPanel
var _insure: InsurePanel
var character: CharacterPanel
var _online_status: Label
var _stash_title: Label
## What the base's door says while in a server's lobby (`set_leave_text`).
var _leave_text := "Leave the server"
## The station whose screen is open, or "".
var station := ""
var _sections := {}
var _title: Label
var _backdrop: TextureRect
var _shade: Control
## The small line over the title: where this screen is.
var _kicker: Label
var _close_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Travel: a full-screen backdrop. At a station: the screen's dark glass.
	_backdrop = TextureRect.new()
	_backdrop.texture = Look.backdrop()
	_backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_backdrop)
	# At a station: a lit terminal's glass, in the house style.
	theme = TerminalStyle.theme()
	_shade = TerminalStyle.Backdrop.new()
	add_child(_shade)

	# Scrolls when the screen is taller than the window, centered otherwise,
	# with the way out kept in view under it.
	var frame := VBoxContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Clear of the glass's edge and its corner brackets.
	frame.offset_top = 18
	frame.add_theme_constant_override("separation", 8)
	add_child(frame)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(SCREEN_WIDTH, 0)
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)

	_kicker = _text("", 13, TerminalStyle.CYAN)
	_kicker.visible = false
	box.add_child(_kicker)
	_title = _text("VERGE", 40, Color(1.0, 0.55, 0.25))
	box.add_child(_title)

	var records := _section(box, "records")
	_result = _text("", 18, Color.WHITE)
	records.add_child(_result)
	_stash_title = _text("STASH", 20, Color(1.0, 0.55, 0.25))
	records.add_child(_stash_title)
	_stash = _text("", 15, Color(0.85, 0.85, 0.85))
	records.add_child(_stash)
	var stash_split := _split(records, 300.0)
	_stash_rows = stash_split[0]
	_stash_card = stash_split[1]
	_stash_card.notes = _stash_notes
	_stash_card.empty_text = "Your stash is empty. Bring loot home to fill it."

	var locker := _section(box, "loadout")
	locker.add_child(_text("LOADOUT", 20, Color(1.0, 0.55, 0.25)))
	locker.add_child(_text(
		"Gear you equip leaves your stash when you deploy. Die and it is gone. Sign out alive (L) and it comes back.\n"
		+ "Bank loot at a depot to send it here without leaving.\n"
		+ "Scrap gear is free to equip, costs nothing to lose and can never be stashed. An empty slot goes without.",
		13, Color(0.65, 0.65, 0.65)))
	var locker_split := _split(locker, 430.0)
	_loadout_box = locker_split[0]
	_locker_card = locker_split[1]
	_locker_card.notes = _locker_notes
	_locker_card.empty_text = "Nothing in this slot: you go without one."
	var group := ""
	for slot: String in Loadout.SLOTS:
		# The attachments go under their own heading, after the gear.
		var heading := "ATTACHMENTS FOR THE PRIMARY" if slot in Loadout.ATTACHMENT_SLOTS else "GEAR"
		if heading != group:
			group = heading
			_loadout_box.add_child(_text(heading, 14, Color(1.0, 0.55, 0.25)))
		var row := HBoxContainer.new()
		row.name = "Slot_%s" % slot
		var name_label := _text(Loadout.SLOT_NAMES[slot], 16, Color(0.85, 0.85, 0.85))
		name_label.custom_minimum_size = Vector2(170, 0)
		name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.add_child(name_label)
		var picker := OptionButton.new()
		picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		picker.custom_minimum_size = Vector2(330, 0)
		picker.item_selected.connect(_on_picked.bind(slot))
		# Browsing the list shows each choice on the card before it is picked.
		picker.get_popup().id_focused.connect(func(option: int) -> void:
			var index := picker.get_item_index(option)
			if index >= 0:
				_locker_card.show_item(str(picker.get_item_metadata(index))))
		row.add_child(picker)
		_loadout_box.add_child(row)
		_pickers[slot] = picker
		_slot_rows[slot] = row

	_mastery = MasteryPanel.new()
	_mastery.pick_requested.connect(func(track: String, variant_id: String) -> void:
		online_pick_requested.emit(track, variant_id))
	_section(box, "mastery").add_child(_mastery)

	character = CharacterPanel.new()
	character.appearance = Profile.appearance
	character.changed.connect(func(appearance: Dictionary) -> void: look_changed.emit(appearance))
	_section(box, "character").add_child(character)

	_shop = ShopPanel.new()
	_shop.buy_requested.connect(func(shop_id: String, item_id: String) -> void:
		online_buy_requested.emit(shop_id, item_id))
	_shop.sell_requested.connect(func(item_id: String, count: int) -> void:
		online_sell_requested.emit(item_id, count))
	_shop.changed.connect(_refresh_gear)
	_section(box, "shop").add_child(_shop)

	_craft = CraftPanel.new()
	_craft.craft_requested.connect(func(item_id: String) -> void: online_craft_requested.emit(item_id))
	_craft.changed.connect(_refresh_gear)
	_section(box, "craft").add_child(_craft)

	_insure = InsurePanel.new()
	_insure.insure_requested.connect(func(action: String, item_id: String) -> void:
		online_insure_requested.emit(action, item_id))
	_insure.changed.connect(_refresh_gear)
	_section(box, "insure").add_child(_insure)

	_online_status = _text("", 14, Color(1.0, 0.8, 0.4))
	_section(box, "status").add_child(_online_status)

	var foot := CenterContainer.new()
	frame.add_child(foot)
	_close_button = Button.new()
	_close_button.text = "Step away  (Esc)"
	_close_button.custom_minimum_size = Vector2(SCREEN_WIDTH, 44)
	_close_button.pressed.connect(close)
	foot.add_child(_close_button)
	var under := Control.new()
	under.custom_minimum_size = Vector2(0, 6)
	frame.add_child(under)
	refresh({})
	TerminalStyle.dress(self)
	close()


## A titled part of the screen that a station shows on its own.
func _section(box: VBoxContainer, id: String) -> VBoxContainer:
	var section := VBoxContainer.new()
	section.name = id.capitalize()
	section.add_theme_constant_override("separation", 10)
	box.add_child(section)
	_sections[id] = section
	return section


## A list that scrolls on the left of `parent` and an item card on its
## right: [the list's box, the card].
func _split(parent: Control, height: float) -> Array:
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 14)
	parent.add_child(split)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, height)
	split.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var card := ItemCard.new()
	split.add_child(card)
	return [list, card]


## Opens what a station in the home base offers (a key of `STATIONS`) on
## this screen. Esc or the button steps away again.
## `also` names other stations whose sections this console shows as well (a
## starter base's shared consoles, see `HomeBase.also_shows`).
func open_station(id: String, also: Array = []) -> void:
	if not STATIONS.has(id):
		return
	station = id
	_craft.show_message("")
	_insure.show_message("")
	var sections: Array = STATIONS[id]["sections"].duplicate()
	var names: Array[String] = [str(HomeBase.STATIONS[id]["title"]) if HomeBase.STATIONS.has(id)
			else str(STATIONS[id].get("title", id))]
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
	var prompt := str(HomeBase.STATIONS.get(id, STATIONS[id]).get("prompt", STATIONS[id].get("prompt", "")))
	_kicker.text = "HOME BASE  //  %s" % prompt.to_upper() if prompt != "" else "HOME BASE"
	_kicker.visible = true
	_backdrop.visible = false
	_shade.visible = true
	_close_button.visible = true
	visible = true


## The screen between places (connecting, travelling): the backdrop and a
## line on what is happening. Set the line with `set_online_status`.
func show_travel() -> void:
	station = ""
	_show_only(["status"])
	_title.text = "VERGE"
	_title.add_theme_font_size_override("font_size", 40)
	_kicker.visible = false
	_backdrop.visible = true
	_shade.visible = false
	_close_button.visible = false
	visible = true


## Puts the screen away: back to the world.
func close() -> void:
	var was := station
	station = ""
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
	_stash.text = "Stash value %d   Drops %d   Left alive %d   Kills %d\n%s" % [
		ItemDB.total_value(stash_items()),
		record.get("raids_played"), record.get("raids_extracted"), record.get("kills"),
		renown_text(lifetime)]
	_refresh_stash_list()
	_shop.refresh()
	_craft.refresh()
	_insure.refresh()
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
	for id: String in StashRules.equippable(stash_items()):
		if Loadout.fits(slot, id) and id not in out:
			out.append(id)
	out.sort_custom(func(a: String, b: String) -> bool: return ItemDB.item_value(a) > ItemDB.item_value(b))
	return out


func _refresh_loadout() -> void:
	for slot: String in Loadout.SLOTS:
		var picker: OptionButton = _pickers[slot]
		picker.clear()
		picker.add_item("None")
		picker.set_item_metadata(0, "")
		var worn := equipped(slot)
		var selected := 0
		for id in options_for(slot):
			var have := "free" if StashRules.is_free(id) else "x%d" % stash_items().count(id)
			picker.add_item("%s  [%s]  %s" % [ItemDB.item_name(id), ItemDB.rarity_name(id), have])
			var index := picker.item_count - 1
			picker.set_item_metadata(index, id)
			if id == worn:
				selected = index
		picker.select(selected)
		_locker_card.track(_slot_rows[slot], worn)
	if _locker_card.item_id == "" or _locker_card.item_id not in current_loadout().values():
		_locker_card.show_item(equipped("primary"))
	else:
		_locker_card.redraw()
	_mastery.refresh()


## What the locker's card says about an item: whether you wear it, how many
## you have, and what it risks.
func _locker_notes(id: String) -> Array:
	var out: Array = []
	var slot := Loadout.slot_of(id)
	if slot != "" and equipped(slot) == id:
		out.append(["Equipped. It goes with you on your next deploy.", ItemCard.GOOD])
	else:
		out.append(["Pick it in the %s list to equip it." % str(Loadout.SLOT_NAMES.get(slot, "slot")).to_lower(),
				ItemCard.MUTED])
	if StashRules.is_free(id):
		out.append(["Free scrap kit: you always have one.", ItemCard.MUTED])
	else:
		out.append(["In your stash: %d" % stash_items().count(id), ItemCard.GOOD])
		if str(_insured_item()) == id:
			out.append(["Insured: it comes home if you die with it.", ItemCard.GOOD])
		else:
			out.append(["Die with it and it drops in your bag.", ItemCard.WARN])
	return out


## The item your insurance covers, or "".
func _insured_item() -> String:
	var held: Dictionary = SafetyNets.clean(account.get("insurance", {})) if in_lobby() else Profile.insurance_policy()
	return str(held.get("item", ""))


## The records board's stash, one row an item kind, rarest first.
func _refresh_stash_list() -> void:
	for child in _stash_rows.get_children():
		_stash_rows.remove_child(child)
		child.queue_free()
	_stash_card.clear_rows()
	var counts := {}
	for id: Variant in stash_items():
		if typeof(id) == TYPE_STRING:
			counts[id] = int(counts.get(id, 0)) + 1
	var ids: Array = counts.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		if ItemDB.item_rarity(a) != ItemDB.item_rarity(b):
			return ItemDB.item_rarity(a) > ItemDB.item_rarity(b)
		return ItemDB.item_value(a) > ItemDB.item_value(b) if ItemDB.item_value(a) != ItemDB.item_value(b) else a < b)
	if ids.is_empty():
		_stash_rows.add_child(_text("Nothing stashed yet.", 15, Color(0.7, 0.7, 0.7)))
	for id: String in ids:
		var row := HBoxContainer.new()
		row.name = "Stash_%s" % id
		var name_label := _text(ItemDB.item_name(id), 15, ItemDB.RARITY_COLORS[ItemDB.item_rarity(id)])
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var count := _text("x%d" % counts[id], 15, Color(0.85, 0.85, 0.85))
		count.custom_minimum_size = Vector2(60, 0)
		row.add_child(count)
		var worth := _text("%d" % (ItemDB.item_value(id) * int(counts[id])), 15, Color(1.0, 0.85, 0.4))
		worth.custom_minimum_size = Vector2(80, 0)
		worth.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(worth)
		_stash_rows.add_child(row)
		_stash_card.track(row, id)
	_stash_card.settle()


## What the records board's card says about a stashed item.
func _stash_notes(id: String) -> Array:
	var have := stash_items().count(id)
	var out: Array = [["In your stash: %d, worth %d scrip." % [have, ItemDB.item_value(id) * have], ItemCard.GOOD]]
	var slot := Loadout.slot_of(id)
	if slot != "" and equipped(slot) == id:
		out.append(["Equipped in your loadout.", ItemCard.GOOD])
	return out


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


## What the base's door says in a server's lobby: it leads back to the plaza
## when the server has one.
func set_leave_text(text: String) -> void:
	_leave_text = text


func leave_text() -> String:
	return _leave_text


func in_lobby() -> bool:
	return not account.is_empty()


## Switches the hub to the account a server keeps for you. `world` is the
## world that server runs.
func enter_lobby(p_account: Dictionary, _world: WorldDef) -> void:
	update_account(p_account)


## Shows a fresh copy of the server's account.
func update_account(p_account: Dictionary) -> void:
	account = p_account
	var book := MasteryBook.new()
	book.load_dict(account.get("mastery", {}))
	_mastery.book = book
	_mastery.loadout = account.get("loadout", {})
	_shop.account = account
	_craft.account = account
	_insure.account = account
	_show_sections()
	_refresh_gear()


## Back to the local profile.
func leave_lobby() -> void:
	account = {}
	_mastery.book = null
	_mastery.loadout = null
	_shop.account = null
	_craft.account = null
	_insure.account = null
	_show_sections()
	_refresh_gear()


func _show_sections() -> void:
	_stash_title.text = "STASH ON THIS SERVER" if in_lobby() else "STASH"


func stash_items() -> Array:
	return account.get("stash", []) if in_lobby() else Profile.stash


## The home base upgrades on show: the server's account's, or the profile's.
func base_upgrades() -> Array:
	return account.get("base_upgrades", []) if in_lobby() else Profile.base_upgrades


## Which room stands in which socket of the base (`BasePlan`): the server's
## account in a lobby, the profile otherwise.
func base_plan() -> Dictionary:
	return account.get("base_plan", {}) if in_lobby() else Profile.base_plan


## The blueprints known: the server's account's, or the profile's.
func blueprints() -> Array:
	return account.get("blueprints", []) if in_lobby() else Profile.blueprints


## The scrip on show: the server's account's, or the profile's.
func scrip() -> int:
	return int(account.get("scrip", 0)) if in_lobby() else Profile.scrip


func equipped(slot: String) -> String:
	return account.get("loadout", {}).get(slot, "") if in_lobby() else Profile.equipped(slot)


## The line `set_online_status` last set.
func online_status() -> String:
	return _online_status.text if _online_status else ""


func set_online_status(text: String) -> void:
	if _online_status:
		_online_status.text = text
	online_status_changed.emit(text)
