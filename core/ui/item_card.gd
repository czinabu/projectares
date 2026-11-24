extends PanelContainer
## The card beside every list of items on a screen in the world: the shops
## (the base's trader and the Concourse's storefronts), the locker, the
## fabricator, insurance, the market kiosk and the records board's stash.
## It shows the item you point at: its model in a small lit window
## (`Preview`, view only, drag to turn it), its name and what kind of thing
## it is, what it is for in plain words (`about_text`), its numbers
## (`facts`) and whatever the screen adds about it here (`notes`: a price,
## how many you own, what you are short of).
##
## A screen hands it its rows with `track(row, id)`: pointing at a row, or
## tabbing onto its button, shows that item, and the row picked stays lit.
## Nothing here asks for anything or changes any state.
##
## Load with `const ItemCard := preload("res://core/ui/item_card.gd")`.

const SkinScript := preload("res://core/visual/actor_skin.gd")
const VehicleScript := preload("res://core/vehicle/vehicle.gd")
const RigModel := preload("res://core/visual/rig_model.gd")
const Crafting := preload("res://core/progression/crafting.gd")
const Economy := preload("res://core/economy/economy.gd")
const TerminalStyle := preload("res://core/ui/terminal_style.gd")

const WIDTH := 360.0
const MUTED := Color(0.68, 0.68, 0.68)
const FACT := Color(0.86, 0.86, 0.84)
## A note in this colour is something in the way (short of scrip, of parts).
const WARN := Color(1.0, 0.7, 0.35)
## A note in this colour is good news (you own it, it is what you wear).
const GOOD := Color(0.5, 0.95, 0.6)
const PICKED := Color(1.0, 0.62, 0.22, 0.14)

## What the screen says about an item here, asked each time one is shown:
## a Callable taking the item id and returning an Array of notes, each a
## String or [String, Color].
var notes := Callable()
## The item on show, or "".
var item_id := ""
## Shown while nothing is picked.
var empty_text := "Point at an item to see it here."

var preview: Preview
var _name: Label
var _kind: Label
var _about: Label
var _facts: VBoxContainer
var _notes: VBoxContainer
var _empty: Label
var _bay: Bay
var _body: VBoxContainer
## Row -> item id, for the rows the screen handed over.
var _rows := {}


func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	add_theme_stylebox_override("panel", TerminalStyle.card_plate(TerminalStyle.EDGE))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	# The model stands in a lit bay: a glow in the item's colour, a grid
	# and corner brackets behind it.
	_bay = Bay.new()
	box.add_child(_bay)
	preview = Preview.new()
	preview.build = model_for
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bay.add_child(preview)
	_empty = _label(empty_text, 14, MUTED)
	box.add_child(_empty)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 4)
	box.add_child(_body)
	_name = _label("", 22, Color.WHITE)
	_body.add_child(_name)
	_kind = _label("", 14, MUTED)
	_body.add_child(_kind)
	_about = _label("", 15, Color(0.92, 0.92, 0.9))
	_body.add_child(_about)
	# What it costs here and what is in the way come first, then its numbers.
	_notes = VBoxContainer.new()
	_notes.add_theme_constant_override("separation", 2)
	_body.add_child(_notes)
	_facts = VBoxContainer.new()
	_facts.add_theme_constant_override("separation", 1)
	_body.add_child(_facts)
	show_item(item_id)


## Shows `id` ("" for nothing) with the screen's notes on it, and lights
## its row.
func show_item(id: String) -> void:
	item_id = id
	if _body == null:
		return
	_body.visible = id != ""
	_empty.visible = id == ""
	_empty.text = empty_text
	preview.show_item(id)
	for row: Variant in _rows.keys():
		if is_instance_valid(row):
			(row as CanvasItem).queue_redraw()
		else:
			_rows.erase(row)
	var tint: Color = ItemDB.RARITY_COLORS[ItemDB.item_rarity(id)] if id != "" else TerminalStyle.EDGE
	add_theme_stylebox_override("panel", TerminalStyle.card_plate(tint))
	_bay.tint = tint
	_bay.queue_redraw()
	if id == "":
		return
	_name.text = ItemDB.item_name(id)
	_name.add_theme_color_override("font_color", ItemDB.RARITY_COLORS[ItemDB.item_rarity(id)])
	_kind.text = kind_text(id)
	_about.text = about_text(id)
	_fill(_facts, facts(id).map(func(line: String) -> Array: return [line, FACT]))
	var extra: Array = notes.call(id) if notes.is_valid() else []
	_fill(_notes, extra.map(func(note: Variant) -> Array:
		return note if typeof(note) == TYPE_ARRAY else [str(note), GOOD]))


## Shows the same item again, with fresh notes (after a buy or an equip).
func redraw() -> void:
	show_item(item_id)


## Lines the card shows now (facts and notes), for tests.
func lines() -> Array[String]:
	var out: Array[String] = []
	for box: VBoxContainer in [_notes, _facts]:
		for child in box.get_children():
			if child is Label and not child.is_queued_for_deletion():
				out.append((child as Label).text)
	return out


## Forgets the rows handed over: call before a screen builds new ones.
func clear_rows() -> void:
	_rows.clear()


## Hands the card a row of the screen's list for item `id`: pointing at it,
## or tabbing onto a button in it, shows the item, and it is lit while
## picked. `row` is any Control; its own children are left alone. A row
## handed over again (a list that keeps its rows) only changes its item.
func track(row: Control, id: String) -> void:
	_rows[row] = id
	row.set_meta("card_item", id)
	if row.has_meta("card_tracked"):
		row.queue_redraw()
		return
	row.set_meta("card_tracked", true)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	# Room for the rarity strip down the row's left.
	var strip := Control.new()
	strip.name = "Strip"
	strip.custom_minimum_size = Vector2(8, 0)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(strip)
	row.move_child(strip, 0)
	var pick := func() -> void:
		var now := str(row.get_meta("card_item", ""))
		if item_id != now or now == "":
			show_item(now)
	row.mouse_entered.connect(pick)
	for child in row.find_children("*", "BaseButton", true, false):
		var button := child as BaseButton
		button.mouse_entered.connect(pick)
		button.focus_entered.connect(pick)
	row.draw.connect(func() -> void:
		var shown := str(row.get_meta("card_item", ""))
		var lit := _rows.has(row) and item_id == shown and item_id != ""
		if lit:
			row.draw_rect(Rect2(Vector2(0, -1), row.size + Vector2(4, 2)), PICKED)
		# A strip of the item's rarity colour down its left, brighter picked,
		# and a faint rule under the row.
		if shown != "" and ItemDB.has_item(shown):
			var tint: Color = ItemDB.RARITY_COLORS[ItemDB.item_rarity(shown)]
			row.draw_rect(Rect2(0, 2, 3, row.size.y - 4), Color(tint, 1.0 if lit else 0.55))
		row.draw_line(Vector2(0, row.size.y + 1), Vector2(row.size.x, row.size.y + 1), Color(1, 1, 1, 0.05)))


## Keeps the item on show if a row still has it, else shows the first row's
## (or nothing). Call once a screen has handed over its new rows.
func settle() -> void:
	var ids: Array = _rows.values()
	if item_id != "" and item_id in ids:
		show_item(item_id)
	else:
		show_item(str(ids[0]) if not ids.is_empty() else "")


func _fill(box: VBoxContainer, rows: Array) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	for row: Array in rows:
		box.add_child(_label(str(row[0]), 14, row[1]))


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


# --- What an item is, in plain words -------------------------------------

## What kinds of thing the tags name, first match wins.
const KINDS := [
	["power", "heavy weapon"], ["mounted", "mounted gun"], ["railgun", "rail gun"], ["marksman", "marksman rifle"],
	["shotgun", "shotgun"], ["smg", "submachine gun"], ["machine_pistol", "machine pistol"],
	["hand_cannon", "revolver"], ["pistol", "pistol"], ["rifle", "assault rifle"],
	["knife", "knife"], ["axe", "axe"], ["hammer", "two-handed hammer"], ["spear", "spear"],
	["blade", "sword"], ["frame_light", "light armor frame"], ["frame_medium", "medium armor frame"],
	["frame_heavy", "heavy armor frame"], ["helmet", "helmet"], ["attachment", "weapon attachment"],
	["ability", "ability chip"], ["artifact", "artifact"], ["backpack", "backpack"], ["vehicle", "vehicle"], ["airship", "airship"],
	["blueprint", "blueprint"], ["upgrade_data", "crafting data"], ["heal", "healing item"],
	["paint", "armor paint"], ["trail", "thruster trail"], ["cosmetic", "clothing"], ["decor", "decoration"], ["furniture", "furniture"],
	["relic", "relic"], ["trophy", "trophy"], ["augment", "salvage"], ["material", "crafting material"],
]


## "Rare marksman rifle, for the primary weapon slot."
static func kind_text(id: String) -> String:
	var text := short_kind(id)
	var slot := Loadout.slot_of(id)
	if ItemDB.has_tag(id, "starter"):
		text += ", free scrap kit"
	if slot != "":
		text += ", for the %s slot" % str(Loadout.SLOT_NAMES[slot]).to_lower()
	return text + "."


## "Rare marksman rifle": the rarity and what kind of thing it is, for a
## list's rows.
static func short_kind(id: String) -> String:
	var kind := "item"
	if ItemDB.has_tag(id, "flight_rig"):
		kind = {"jetpack": "jetpack", "boots": "pair of thruster boots", "wings": "set of glide wings"}.get(
				RigModel.kind_for(id), "flight rig")
	else:
		for entry: Array in KINDS:
			if ItemDB.has_tag(id, entry[0]):
				kind = entry[1]
				break
	return "%s %s" % [ItemDB.rarity_name(id), kind]


## What the item is for, in a sentence or two: its own description, or one
## worked out from its tags for items that have none (loot and parts).
static func about_text(id: String) -> String:
	var own := ItemDB.item_description(id)
	if own != "":
		return own
	var used := _used_in(id)
	if not used.is_empty():
		return "A part for crafting at the fabricator. Bring it home and keep it, or sell it to the trader."
	if ItemDB.has_tag(id, "relic"):
		return "A rare find worth a lot to the trader. It does nothing on its own."
	return "Loot. It does nothing on its own: sell it to the trader for scrip."


## The item's numbers, one plain line each.
static func facts(id: String) -> Array[String]:
	var out: Array[String] = []
	var stats := ItemDB.item_stats(id)
	if ItemDB.has_tag(id, "firearm") or ItemDB.has_tag(id, "mounted"):
		out.append_array(_gun_facts(id, stats))
	elif ItemDB.has_tag(id, "melee"):
		out.append_array(_melee_facts(id, stats))
	elif ItemDB.has_tag(id, "armor"):
		out.append("Armor: %d" % int(stats.get("armor", 0.0)))
		var speed := float(stats.get("speed_mult", 1.0))
		if not is_equal_approx(speed, 1.0):
			out.append("You move %d%% %s" % [roundi(absf(speed - 1.0) * 100.0), "faster" if speed > 1.0 else "slower"])
		if stats.has("insulation"):
			out.append("Keeps out %d%% of the cold" % roundi(float(stats.insulation) * 100.0))
		var heat := float(stats.get("heat_signature", 1.0))
		if not is_equal_approx(heat, 1.0):
			out.append("%s on thermal" % ("Dim" if heat < 1.0 else "Bright"))
	elif ItemDB.has_tag(id, "helmet"):
		var mode := str(stats.get("mode", ""))
		out.append("Visor: %s" % {"zoom": "binoculars and tagging", "scan": "scan pulse", "threat": "tactical readouts",
				"thermal": "thermal sight"}.get(mode, "health readout only"))
		if int(stats.get("tier", 1)) > 1:
			out.append("Mk%d: crafted, never sold or dropped" % int(stats.get("tier", 1)))
	elif ItemDB.has_tag(id, "flight_rig"):
		out.append("Flies up to %d m over the ground" % roundi(float(stats.get("ceiling", 0.0))))
		var fall := float(stats.get("fall_damage_mult", 1.0))
		out.append("Fall damage: %s" % ("none" if fall <= 0.0 else "%d%%" % roundi(fall * 100.0)))
		if stats.has("scan_range"):
			out.append("Shows on scans and thermal out to %d m" % roundi(float(stats.scan_range)))
	elif ItemDB.has_tag(id, "vehicle"):
		var top := float(stats.get("max_speed", 0.0)) * 3.6
		var boost := float(stats.get("boost_speed", 0.0)) * 3.6
		out.append("Top speed %d km/h, %d boosting" % [roundi(top), roundi(boost)])
		var seats := 1
		if stats.has("seats"):
			seats = 1 + (stats.seats as Array).size()
		elif stats.get("passenger_seat", false):
			seats = 2
		out.append("Seats %d" % seats)
		if ItemDB.has_tag(id, "aircraft"):
			out.append("Flies, in worlds with open skies")
		out.append("Rides on your watch as a toy: throw it to unpack it")
		if stats.has("watch_recharge"):
			out.append("The watch needs %d s before the next throw" % roundi(float(stats.watch_recharge)))
	elif ItemDB.has_tag(id, "airship"):
		out.append("A world event: it drifts across the map, never yours to ride")
		var parts := (stats.get("seats", []) as Array).filter(func(seat: Dictionary) -> bool: return seat.has("part"))
		out.append("%d weak spots; break them all and it comes down with its hold" % parts.size())
	elif ItemDB.has_tag(id, "backpack"):
		out.append("Pack room: %d slots, against %d with none" % [int(stats.get("capacity", Loadout.FIELD_PACK)), Loadout.FIELD_PACK])
		out.append("Sprint %d%% slower" % roundi((1.0 - float(stats.get("sprint_mult", 1.0))) * 100.0))
		out.append("Worn on your back: it drops with you")
	elif ItemDB.has_tag(id, "ability"):
		out.append("Cooldown %d s" % roundi(float(stats.get("cooldown", 0.0))))
	elif ItemDB.has_tag(id, "artifact"):
		var charges := int(stats.get("charges", 1))
		out.append("Uses per outing: %s" % ("no limit" if charges <= 0 else str(charges)))
		if float(stats.get("cooldown", 0.0)) > 0.0:
			out.append("Cooldown %d s" % roundi(float(stats.cooldown)))
		out.append("Used from the watch. One artifact per outing")
	elif ItemDB.has_tag(id, "attachment"):
		out.append("Fits any primary weapon, in its %s slot" % str(Loadout.SLOT_NAMES.get(
				Loadout.attachment_slot(id), "")).to_lower())
		if float(stats.get("zoom", 1.0)) > 1.0:
			out.append("Zoom %sx when aimed" % str(snappedf(float(stats.zoom), 0.1)).trim_suffix(".0"))
		out.append("Fitted at the gunsmith bench")
	elif ItemDB.has_tag(id, "heal"):
		out.append("Heals %d" % int(stats.get("heal", 0.0)))
	elif ItemDB.has_tag(id, "blueprint"):
		var made: Array[String] = []
		for made_id in Crafting.made_from(id):
			made.append(ItemDB.item_name(made_id))
		if not made.is_empty():
			out.append("Crafts: %s" % ", ".join(made))
		out.append("Learned for good once it reaches your stash")
	elif ItemDB.has_tag(id, "paint"):
		out.append("Paints armor frames, picked at your base's armor stands")
		out.append("Looks only: no armor, speed or stats change")
		if ItemDB.item_rarity(id) == ItemDB.Rarity.RELIC:
			out.append("Earned only: never sold or traded")
	elif ItemDB.has_tag(id, "trail"):
		out.append("Colours every flight rig's flames, picked at your base's rig stands")
		out.append("Looks only: no thrust, speed or stats change")
		if ItemDB.item_rarity(id) == ItemDB.Rarity.RELIC:
			out.append("Earned only: never sold or traded")
	elif ItemDB.has_tag(id, "cosmetic"):
		out.append("Unlocks %d outfit%s in the wardrobe" % [(stats.get("outfits", []) as Array).size(),
				"" if (stats.get("outfits", []) as Array).size() == 1 else "s"])
	elif ItemDB.has_tag(id, "furniture"):
		out.append("Goes on show in your home base")
	elif ItemDB.has_tag(id, "trophy"):
		out.append("A keepsake: never traded or sold")
	var used := _used_in(id)
	if not used.is_empty():
		var shown := used.slice(0, 3)
		out.append("Used to craft: %s%s" % [", ".join(shown), " and %d more" % (used.size() - 3) if used.size() > 3 else ""])
	var sells := Economy.sell_price(id)
	if sells > 0:
		out.append("The trader pays %d scrip for one" % sells)
	if ItemDB.has_tag(id, "starter"):
		out.append("Free: costs nothing to lose")
	return out


## The names of the recipes that take `id` as a part.
static func _used_in(id: String) -> Array[String]:
	var out: Array[String] = []
	for recipe in Crafting.ids():
		if Crafting.needs(recipe).has(id):
			out.append(ItemDB.item_name(recipe))
	return out


static func _gun_facts(_id: String, stats: Dictionary) -> Array[String]:
	var gun := Gun.new()
	for key: String in stats:
		if key in gun:
			gun.set(key, stats[key])
	var out: Array[String] = []
	if gun.pellets > 1:
		out.append("Damage: %d pellets of %d" % [gun.pellets, roundi(gun.damage)])
	else:
		out.append("Damage: %d a hit" % roundi(gun.damage))
	if gun.splash_radius > 0.0:
		out.append("Blast: %d damage across %d m" % [roundi(gun.splash_damage), roundi(gun.splash_radius)])
	if gun.charge_time > 0.0:
		out.append("Hold %.1f s to charge each shot" % gun.charge_time)
	var per_minute := roundi(60.0 / maxf(gun.fire_interval, 0.01))
	out.append("Fire rate: %d a minute, %s" % [per_minute, "one shot a pull" if gun.semi_auto else "hold to fire"])
	if ItemDB.has_tag(_id, "power"):
		out.append("Shots: %d, then it is spent" % (gun.mag_size + gun.reserve_ammo))
	else:
		out.append("Magazine: %d, reload %.1f s" % [gun.mag_size, gun.reload_time])
	if gun.falloff_end > 0.0:
		out.append("Range: full damage to %d m, %d%% by %d m" % [roundi(gun.falloff_start), roundi(gun.falloff_min * 100.0),
				roundi(gun.falloff_end)])
	else:
		out.append("Range: full damage to %d m" % roundi(gun.max_range))
	if gun.headshot_mult > 1.0:
		out.append("Headshots: x%s" % str(snappedf(gun.headshot_mult, 0.05)))
	if gun.armor_pierce > 0.0:
		out.append("%d%% of each hit goes past armor" % roundi(gun.armor_pierce * 100.0))
	if gun.pierce > 0:
		out.append("Goes through %d bodies%s" % [gun.pierce, " and %d walls" % gun.wall_pierce if gun.wall_pierce > 0 else ""])
	out.append("Recoil: %s" % {"climb": "climbs straight up", "climb_right": "climbs up and right",
			"climb_left": "climbs up and left", "sway": "sways side to side", "kick": "one sharp kick a shot"}.get(
			gun.recoil_pattern, gun.recoil_pattern))
	gun.free()
	return out


static func _melee_facts(id: String, stats: Dictionary) -> Array[String]:
	var blade := MeleeWeapon.new()
	for key: String in stats:
		if key in blade:
			blade.set(key, stats[key])
	var out: Array[String] = []
	out.append("Damage: %d a quick hit, %d held" % [roundi(blade.light_damage), roundi(blade.heavy_damage)])
	out.append("Reach: %.1f m" % blade.reach)
	out.append("Two-handed: heavies stagger and break armor" if MeleeWeapon.is_two_handed_id(id)
			else "One-handed: quick to swing")
	if blade.backstab_mult > 1.0:
		out.append("Hits from behind x%s" % str(snappedf(blade.backstab_mult, 0.1)))
	if stats.has("guard_crush"):
		out.append("Breaks guards: blocking it costs x%s stamina" % str(snappedf(float(stats.guard_crush), 0.1)))
	out.append("Silent: bots never hear a blade")
	blade.free()
	return out


# --- The model --------------------------------------------------------

## The model an item is shown as: the gear's own model where it has one, a
## small stand-in shape for loot, parts and the rest. Null on a headless
## server. Front toward +Z where it has one (the preview turns it so).
static func model_for(id: String) -> Node3D:
	if DisplayServer.get_name() == "headless" or id == "":
		return null
	var color: Color = ItemDB.RARITY_COLORS[ItemDB.item_rarity(id)]
	var stats := ItemDB.item_stats(id)
	if ItemDB.has_tag(id, "firearm") or ItemDB.has_tag(id, "melee"):
		var weapon: Weapon = MeleeWeapon.new() if ItemDB.has_tag(id, "melee") else Gun.new()
		weapon.item_id = id
		var model := Look.weapon_model(weapon)
		weapon.free()
		return model
	if ItemDB.has_tag(id, "helmet"):
		return SkinScript.build_helmet(str(stats.get("mode", "")), stats.get("glass_color", Color.WHITE),
				Vector3(0.27, 0.31, 0.31), Color(0.22, 0.23, 0.25), int(stats.get("tier", 1)))
	if ItemDB.has_tag(id, "armor"):
		return SkinScript.build_frame(id)
	if ItemDB.has_tag(id, "flight_rig"):
		var root := Node3D.new()
		var back := RigModel.build_back(id)
		if back:
			if back.has_node("WingL"):
				RigModel.set_wing_spread(back, 0.55)
			root.add_child(back)
		else:
			for side: float in [-1.0, 1.0]:
				var boot := RigModel.build_boot(id, side)
				if boot:
					boot.position = Vector3(side * 0.16, 0.0, 0.0)
					root.add_child(boot)
		return root
	if ItemDB.has_tag(id, "vehicle"):
		var toy: Node3D = VehicleScript.toy_model(id)
		toy.scale = Vector3.ONE
		return toy
	if ItemDB.has_tag(id, "attachment"):
		return Gun.build_attachment(id)
	return _stand_in(id, color)


## A small shape for an item with no model of its own, lit in its rarity's
## colour: a slate for a blueprint, a chip for data and abilities, an orb
## for an artifact, a case with a cross for healing, a crate for the rest.
static func _stand_in(id: String, color: Color) -> Node3D:
	var root := Node3D.new()
	var dark := Color(0.12, 0.13, 0.15)
	if ItemDB.has_tag(id, "blueprint"):
		root.add_child(_box(Vector3(0.6, 0.02, 0.42), Vector3.ZERO, Color(0.08, 0.16, 0.26)))
		for i in 4:
			root.add_child(_box(Vector3(0.5, 0.004, 0.008), Vector3(0, 0.012, -0.15 + i * 0.1), Color(0.4, 0.8, 1.0), true))
		root.add_child(_box(Vector3(0.2, 0.004, 0.16), Vector3(0.12, 0.014, 0.0), Color(0.4, 0.8, 1.0), true))
		root.rotation.x = 0.5
	elif ItemDB.has_tag(id, "upgrade_data") or ItemDB.has_tag(id, "ability") or ItemDB.has_tag(id, "augment"):
		root.add_child(_box(Vector3(0.4, 0.05, 0.28), Vector3.ZERO, dark))
		root.add_child(_box(Vector3(0.18, 0.02, 0.12), Vector3(0, 0.035, 0), color, true))
		for i in 6:
			root.add_child(_box(Vector3(0.02, 0.012, 0.05), Vector3(-0.15 + i * 0.06, 0.0, 0.16), Color(0.7, 0.6, 0.3)))
		root.rotation.x = 0.45
	elif ItemDB.has_tag(id, "artifact") or ItemDB.has_tag(id, "relic"):
		var orb := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.16
		sphere.height = 0.32
		sphere.material = _mat(color, true)
		orb.mesh = sphere
		root.add_child(orb)
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.22
		torus.outer_radius = 0.25
		torus.material = _mat(dark)
		ring.mesh = torus
		ring.rotation = Vector3(0.9, 0.0, 0.3)
		root.add_child(ring)
	elif ItemDB.has_tag(id, "heal"):
		root.add_child(_box(Vector3(0.36, 0.24, 0.14), Vector3.ZERO, Color(0.85, 0.85, 0.82)))
		root.add_child(_box(Vector3(0.16, 0.05, 0.01), Vector3(0, 0, 0.075), Color(1.0, 0.25, 0.2), true))
		root.add_child(_box(Vector3(0.05, 0.16, 0.01), Vector3(0, 0, 0.075), Color(1.0, 0.25, 0.2), true))
	elif ItemDB.has_tag(id, "paint"):
		# A tin of the paint: its plate colour, a band of its lit accent.
		var colours := ArmorPaint.colours(str(ItemDB.item_stats(id).get("paint", "")))
		if not colours.is_empty():
			root.add_child(_box(Vector3(0.3, 0.34, 0.3), Vector3.ZERO, colours["plate"]))
			root.add_child(_box(Vector3(0.31, 0.06, 0.31), Vector3(0, 0.05, 0), colours["accent"], true))
			root.add_child(_box(Vector3(0.24, 0.03, 0.24), Vector3(0, 0.185, 0), colours["plate2"]))
	elif ItemDB.has_tag(id, "trail"):
		# A nozzle burning in the trail: a dark bell, its glow and hot core.
		var colours := RigTrail.colours(str(ItemDB.item_stats(id).get("trail", "")))
		root.add_child(_box(Vector3(0.2, 0.16, 0.2), Vector3(0, 0.16, 0), dark))
		root.add_child(_box(Vector3(0.16, 0.3, 0.16), Vector3(0, -0.07, 0), colours["glow"], true))
		root.add_child(_box(Vector3(0.07, 0.2, 0.07), Vector3(0, -0.02, 0.05), colours["core"], true))
	elif ItemDB.has_tag(id, "cosmetic"):
		for i in 3:
			root.add_child(_box(Vector3(0.44, 0.05, 0.32), Vector3(0, i * 0.055, 0), Color(0.3, 0.32, 0.36).lerp(color, 0.25 * i)))
	else:
		root.add_child(_box(Vector3(0.46, 0.3, 0.3), Vector3.ZERO, dark))
		root.add_child(_box(Vector3(0.47, 0.03, 0.31), Vector3(0, 0.06, 0), color, true))
		root.add_child(_box(Vector3(0.12, 0.08, 0.02), Vector3(0, -0.04, 0.16), Color(0.3, 0.31, 0.33)))
	return root


static func _box(size: Vector3, at: Vector3, color: Color, lit := false) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _mat(color, lit)
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = at
	return part


static func _mat(color: Color, lit := false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.4
	mat.roughness = 0.5
	if lit:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 1.5
	return mat


## The lit bay the preview stands in: a dark well with a glow of the item's
## colour rising from the floor, a faint grid and amber corner brackets.
class Bay:
	extends Control

	var tint := Color(0.5, 0.5, 0.5)

	func _init() -> void:
		name = "Bay"
		custom_minimum_size = Preview.SIZE
		mouse_filter = Control.MOUSE_FILTER_PASS

	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_rect(Rect2(0, 0, w, h), Color(0.015, 0.02, 0.026))
		var bands := 32
		for i in bands:
			var a := float(i) / bands
			# The glow, rising from the floor and fading upward.
			draw_rect(Rect2(0, h * (0.3 + 0.7 * a), w, h * 0.7 / bands + 1), Color(tint, 0.07 * a * a))
		var x := 24.0
		while x < w:
			draw_line(Vector2(x, 0), Vector2(x, h), Color(1, 1, 1, 0.025), 1.0)
			x += 24.0
		var y := 24.0
		while y < h:
			draw_line(Vector2(0, y), Vector2(w, y), Color(1, 1, 1, 0.025), 1.0)
			y += 24.0
		var arm := 14.0
		for corner: Vector2 in [Vector2(1, 1), Vector2(w - 1, 1), Vector2(1, h - 1), Vector2(w - 1, h - 1)]:
			var sx := 1.0 if corner.x < w * 0.5 else -1.0
			var sy := 1.0 if corner.y < h * 0.5 else -1.0
			draw_line(corner, corner + Vector2(arm * sx, 0), TerminalStyle.AMBER, 2.0)
			draw_line(corner, corner + Vector2(0, arm * sy), TerminalStyle.AMBER, 2.0)


## The item's model in a small lit window of its own world, framed to fit,
## seen from three quarters. It stays still (Caleb's call: nothing on show
## turns by itself); drag across it to turn it. View only.
class Preview:
	extends SubViewportContainer

	const SIZE := Vector2(336, 170)
	## How the model is turned to start with: three quarters on, a little
	## from above.
	const START_TURN := 0.6
	const TILT := 0.32

	var viewport: SubViewport
	var item_id := ""
	## Makes the model for an item id (the card's `model_for`).
	var build := Callable()
	var _pivot: Node3D
	var _turn := START_TURN

	func _init() -> void:
		name = "Preview"
		stretch = true
		custom_minimum_size = SIZE
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_DRAG
		viewport = SubViewport.new()
		viewport.own_world_3d = true
		viewport.transparent_bg = true
		viewport.msaa_3d = Viewport.MSAA_4X
		viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
		add_child(viewport)
		var env := Environment.new()
		env.background_mode = Environment.BG_CLEAR_COLOR
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.55, 0.58, 0.62)
		env.ambient_light_energy = 0.7
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		var world := WorldEnvironment.new()
		world.environment = env
		viewport.add_child(world)
		var key := DirectionalLight3D.new()
		key.rotation = Vector3(-0.7, 0.6, 0.0)
		key.light_energy = 1.6
		viewport.add_child(key)
		var rim := DirectionalLight3D.new()
		rim.rotation = Vector3(-0.3, PI + 0.8, 0.0)
		rim.light_energy = 0.9
		rim.light_color = Color(0.6, 0.8, 1.0)
		viewport.add_child(rim)
		var camera := Camera3D.new()
		camera.fov = 30.0
		camera.position = Vector3(0, -0.12, 4.2)
		camera.current = true
		viewport.add_child(camera)
		_pivot = Node3D.new()
		_pivot.name = "Pivot"
		viewport.add_child(_pivot)

	func show_item(id: String) -> void:
		if id == item_id and _pivot.get_child_count() > 0:
			return
		item_id = id
		_turn = START_TURN
		for child in _pivot.get_children():
			_pivot.remove_child(child)
			child.queue_free()
		var model: Node3D = build.call(id) if id != "" and build.is_valid() else null
		if model == null:
			return
		var fitted := _frame(model, id)
		_pivot.add_child(fitted)
		_pivot.add_child(_plinth(ItemDB.RARITY_COLORS[ItemDB.item_rarity(id)]))
		_place()

	## A ring of light the model hovers over, in its rarity's colour, like
	## the lit mounts in the armory.
	static func _plinth(color: Color) -> Node3D:
		var ring := MeshInstance3D.new()
		ring.name = "Plinth"
		var torus := TorusMesh.new()
		torus.inner_radius = 0.95
		torus.outer_radius = 1.0
		torus.ring_segments = 6
		torus.rings = 64
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = color
		torus.material = mat
		ring.mesh = torus
		ring.scale = Vector3(0.85, 0.25, 0.85)
		ring.position = Vector3(0, -0.82, 0)
		var disc := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.95
		cylinder.bottom_radius = 0.95
		cylinder.height = 0.01
		var glass := StandardMaterial3D.new()
		glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glass.albedo_color = Color(color, 0.12)
		cylinder.material = glass
		disc.mesh = cylinder
		ring.add_child(disc)
		return ring

	## The model centred on the pivot and scaled to fill the window, laid
	## so it shows its best side: a long weapon side on, gear facing you.
	static func _frame(model: Node3D, id: String) -> Node3D:
		var lay := Node3D.new()
		lay.add_child(model)
		var box := _bounds(model, lay)
		var gear := ItemDB.has_tag(id, "firearm") or ItemDB.has_tag(id, "melee")
		if gear:
			# Its length across the window.
			match box.get_longest_axis_index():
				Vector3.AXIS_Y:
					lay.rotation = Vector3(0.0, 0.0, -PI * 0.5)
				Vector3.AXIS_Z:
					lay.rotation = Vector3(0.0, PI * 0.5, 0.0)
		elif ItemDB.has_tag(id, "helmet") or ItemDB.has_tag(id, "armor") or ItemDB.has_tag(id, "vehicle"):
			# Built facing -Z: turned round to face the camera.
			lay.rotation.y = PI
		model.position -= box.get_center()
		var holder := Node3D.new()
		holder.add_child(lay)
		var longest := maxf(box.get_longest_axis_size(), 0.01)
		holder.scale = Vector3.ONE * (2.5 if gear else 1.55) / longest
		return holder

	static func _bounds(model: Node3D, top: Node3D) -> AABB:
		var box := AABB()
		var first := true
		for node in model.find_children("*", "VisualInstance3D", true, false):
			var part := node as VisualInstance3D
			if part is GeometryInstance3D:
				(part as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var at := Transform3D.IDENTITY
			var walk: Node = part
			while walk != null and walk != top:
				if walk is Node3D:
					at = (walk as Node3D).transform * at
				walk = walk.get_parent()
			var placed := at * part.get_aabb()
			box = placed if first else box.merge(placed)
			first = false
		return box

	func _place() -> void:
		_pivot.rotation = Vector3(TILT, _turn, 0.0)

	func _gui_input(event: InputEvent) -> void:
		var drag := event as InputEventMouseMotion
		if drag and drag.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_turn += drag.relative.x * 0.012
			_place()
			accept_event()
