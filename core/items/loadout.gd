class_name Loadout
extends RefCounted
## Loadout slots, and turning a list of item ids into equipped gear on an Actor.
## New weapon and rig types get wired in here.

## Slot name -> the item tag that fits it. Order is the weapon order in a raid.
const SLOTS := {
	"primary": "firearm",
	"melee": "melee",
	"sidearm": "sidearm",
	"rig": "flight_rig",
	"frame": "armor",
	"helmet": "helmet",
	"ability": "ability",
	"vehicle": "vehicle",
	# One artifact per outing, carried on the watch (DESIGN.md section 6).
	"artifact": "artifact",
	# Attachments for the primary. Each slot's tag is also the attachment's
	# second tag in ItemDB.
	"optic": "optic",
	"muzzle": "muzzle",
	"grip": "grip",
	"magazine": "magazine",
}
const SLOT_NAMES := {
	"primary": "Primary weapon",
	"melee": "Melee weapon",
	"sidearm": "Sidearm",
	"rig": "Flight rig",
	"frame": "Armor frame",
	"helmet": "Helmet",
	"ability": "Ability",
	"vehicle": "Vehicle",
	"artifact": "Artifact",
	"optic": "Optic",
	"muzzle": "Muzzle",
	"grip": "Grip",
	"magazine": "Magazine",
}
## Slots that hold an attachment for the primary weapon.
const ATTACHMENT_SLOTS := ["optic", "muzzle", "grip", "magazine"]
## Slots with no free scrap item. Left empty, you deploy without one.
const OPTIONAL_SLOTS := ["ability", "vehicle", "artifact", "optic", "muzzle", "grip", "magazine"]
## How many healing items are taken from the stash on deploy.
const MAX_HEAL_ITEMS := 2
## Seconds a weapon takes to materialize out of the pack through the watch,
## by the first of these tags it carries (heavier is slower). An item's own
## `summon_time` stat wins.
const SUMMON_TIMES := [["sidearm", 0.5], ["one_handed", 0.6], ["two_handed", 1.1], ["marksman", 1.3],
		["firearm", 0.9]]
## The watch's wait after a summon, as a multiple of the materialize time.
const SUMMON_COOLDOWN_MULT := 6.0


## True if item `id` can go in loadout slot `slot`. A sidearm is a firearm
## too, but only the sidearm slot takes it.
static func fits(slot: String, id: String) -> bool:
	if not SLOTS.has(slot) or not ItemDB.has_tag(id, SLOTS[slot]):
		return false
	# Attachment slots take attachments only: a Spotter helmet is tagged
	# "optic" too, but it is a helmet.
	if slot in ATTACHMENT_SLOTS and not ItemDB.has_tag(id, "attachment"):
		return false
	return slot != "primary" or not ItemDB.has_tag(id, "sidearm")


static func equip(actor: Actor, item_ids: Array) -> void:
	var frames: Array[String] = []
	# Attachments go on the primary, so they are gathered first: the gun's
	# model is built with them on when it is equipped.
	var fittings: Array[String] = []
	for id: String in item_ids:
		if ItemDB.has_tag(id, "attachment") and fittings.all(func(other: String) -> bool:
				return attachment_slot(other) != attachment_slot(id)):
			fittings.append(id)
	var primary_done := false
	for id: String in item_ids:
		var stats := ItemDB.item_stats(id)
		if ItemDB.has_tag(id, "attachment"):
			# Carried on the gun: lost with it, home with it.
			if id in fittings:
				actor.gear_items.append(id)
			else:
				actor.inventory.add_item(id)
		elif ItemDB.has_tag(id, "firearm"):
			var gun := Gun.new()
			gun.is_sidearm = ItemDB.has_tag(id, "sidearm")
			_setup_weapon(gun, id, stats)
			if not primary_done and is_primary(id):
				primary_done = true
				gun.fit(fittings)
			actor.equip_weapon(gun)
			actor.gear_items.append(id)
		elif ItemDB.has_tag(id, "melee"):
			var blade := MeleeWeapon.new()
			_setup_weapon(blade, id, stats)
			actor.equip_weapon(blade)
			actor.gear_items.append(id)
		elif ItemDB.has_tag(id, "flight_rig"):
			actor.flight.enabled = true
			actor.flight.item_id = id
			actor.flight.display_name = ItemDB.item_name(id)
			_apply_stats(actor.flight, stats)
			actor.gear_items.append(id)
		elif ItemDB.has_tag(id, "ability"):
			actor.ability.enabled = true
			actor.ability.item_id = id
			actor.ability.display_name = ItemDB.item_name(id)
			_apply_stats(actor.ability, stats)
			actor.gear_items.append(id)
		elif ItemDB.has_tag(id, "artifact"):
			# One per outing: any other is only carried, as loot.
			if actor.artifact.enabled:
				actor.inventory.add_item(id)
			else:
				_apply_stats(actor.artifact, stats)
				actor.artifact.attune(id)
				actor.gear_items.append(id)
		elif ItemDB.has_tag(id, "helmet"):
			actor.visor.enabled = true
			actor.visor.item_id = id
			actor.visor.display_name = ItemDB.item_name(id)
			_apply_stats(actor.visor, stats)
			actor.gear_items.append(id)
		elif ItemDB.has_tag(id, "armor"):
			frames.append(id)
		elif ItemDB.has_tag(id, "vehicle"):
			# A vehicle is not carried. The Raid parks it next to its owner.
			pass
		else:
			actor.inventory.add_item(id)
	# Frames go last because they scale what the other gear set up.
	for id in frames:
		var stats := ItemDB.item_stats(id)
		actor.health.set_armor(stats.get("armor", 0.0))
		var speed: float = stats.get("speed_mult", 1.0)
		actor.walk_speed *= speed
		actor.sprint_speed *= speed
		var heat_mult: float = stats.get("heat_mult", 1.0)
		if actor.flight.heavy_lift:
			# A jetpack carries heavy armor without running hotter.
			heat_mult = minf(heat_mult, 1.0)
		actor.flight.heat_per_sec *= heat_mult
		actor.flight.burst_heat *= heat_mult
		actor.flight.pulse_heat *= heat_mult
		actor.flight.air_dash_heat *= heat_mult
		actor.flight.glide_boost_heat *= heat_mult
		actor.heat_signature *= stats.get("heat_signature", 1.0)
		actor.frame_name = ItemDB.item_name(id)
		actor.gear_items.append(id)


## True for a primary that takes attachments: a firearm in the primary slot
## (not a sidearm), and not a power weapon, which comes as it is.
static func is_primary(id: String) -> bool:
	return fits("primary", id) and not ItemDB.has_tag(id, "power")


## The attachment slot an item fits, or "" if it is not an attachment.
static func attachment_slot(id: String) -> String:
	if not ItemDB.has_tag(id, "attachment"):
		return ""
	for slot: String in ATTACHMENT_SLOTS:
		if ItemDB.has_tag(id, SLOTS[slot]):
			return slot
	return ""


## Index in `actor.weapons` of the power weapon (an item tagged "power"),
## or -1 if the actor carries none. It is a fourth weapon next to the
## primary, sidearm and melee weapon, and only ever comes from a power rack.
static func power_index(actor: Actor) -> int:
	for i in actor.weapons.size():
		var gun := actor.weapons[i] as Gun
		if gun and gun.is_power():
			return i
	return -1


## Puts power weapon `id` in the actor's power slot mid-raid and in hand, or
## with "" takes the power weapon away. `mag` and `reserve` restore one that
## was put down part used (below 0 means full). Returns what was given up,
## as {"id", "mag", "reserve", "spent"}, with "id" empty if the slot was
## empty. Emits `Actor.power_changed` so `NetSession` can tell clients.
static func set_power(actor: Actor, id: String, mag := -1, reserve := -1) -> Dictionary:
	var given := {"id": "", "mag": -1, "reserve": -1, "spent": false}
	if id != "" and not ItemDB.has_tag(id, "power"):
		return given
	var index := power_index(actor)
	if index >= 0:
		var old := actor.weapons[index] as Gun
		given = {"id": old.item_id, "mag": old.ammo_in_mag, "reserve": old.reserve_ammo, "spent": old.is_spent()}
		actor.gear_items.erase(old.item_id)
	if id == "":
		if index >= 0:
			actor.remove_weapon(index)
		actor.power_changed.emit("", -1, -1)
		return given
	var gun := Gun.new()
	_setup_weapon(gun, id, ItemDB.item_stats(id))
	if mag >= 0:
		gun.ammo_in_mag = mini(mag, gun.mag_size)
	if reserve >= 0:
		gun.reserve_ammo = reserve
	if index >= 0:
		actor.replace_weapon(index, gun)
	else:
		actor.equip_weapon(gun)
		index = actor.weapons.size() - 1
	actor.gear_items.append(id)
	# What you just picked up is what you hold.
	actor.draw_weapon(index)
	actor.power_changed.emit(id, gun.ammo_in_mag, gun.reserve_ammo)
	return given


## True if `id` is a weapon the watch can materialize out of the pack: a gun
## or a melee weapon. Power weapons never sit in a pack.
static func summonable(id: String) -> bool:
	return ItemDB.has_item(id) and not ItemDB.has_tag(id, "power") \
			and (ItemDB.has_tag(id, "firearm") or ItemDB.has_tag(id, "melee"))


## Seconds weapon `id` takes to materialize in the hand. Heavier is slower.
static func summon_time(id: String) -> float:
	var stats := ItemDB.item_stats(id)
	if stats.has("summon_time"):
		return float(stats["summon_time"])
	for entry: Array in SUMMON_TIMES:
		if ItemDB.has_tag(id, entry[0]):
			return entry[1]
	return 0.9


## Seconds the watch waits after materializing weapon `id`.
static func summon_cooldown(id: String) -> float:
	return summon_time(id) * SUMMON_COOLDOWN_MULT


## The weapon slot a summonable item takes: "primary", "sidearm" or "melee".
static func weapon_slot(id: String) -> String:
	if ItemDB.has_tag(id, "melee"):
		return "melee"
	return "sidearm" if ItemDB.has_tag(id, "sidearm") else "primary"


## Index in `actor.weapons` of the weapon worn in `slot` ("primary",
## "sidearm", "melee"), or -1.
static func worn_index(actor: Actor, slot: String) -> int:
	for i in actor.weapons.size():
		var worn := actor.weapons[i]
		if worn.item_id != "" and not ItemDB.has_tag(worn.item_id, "power") and weapon_slot(worn.item_id) == slot:
			return i
	return -1


## Materializes weapon `id` in the actor's hand in place of the one worn in
## its slot (the watch's summon). `mag` and `reserve` restore a gun put away
## part used (below 0 means as it comes). Only the weapons and the gear list
## change here: the caller moves the items in and out of the pack. Returns
## what was put away as {"id", "mag", "reserve"}, "id" empty if the slot was
## empty or `id` cannot be summoned. Emits `Actor.weapon_swapped`.
static func swap_weapon(actor: Actor, id: String, mag := -1, reserve := -1) -> Dictionary:
	var given := {"id": "", "mag": -1, "reserve": -1}
	if not summonable(id):
		return given
	var index := worn_index(actor, weapon_slot(id))
	var weapon: Weapon
	if ItemDB.has_tag(id, "melee"):
		weapon = MeleeWeapon.new()
	else:
		var gun := Gun.new()
		gun.is_sidearm = ItemDB.has_tag(id, "sidearm")
		weapon = gun
	_setup_weapon(weapon, id, ItemDB.item_stats(id))
	var new_gun := weapon as Gun
	if new_gun:
		if is_primary(id):
			# The attachments stay on the watch's rail and fit the new gun.
			var fittings: Array[String] = []
			for other in actor.gear_items:
				if ItemDB.has_tag(other, "attachment"):
					fittings.append(other)
			new_gun.fit(fittings)
		if mag >= 0:
			new_gun.ammo_in_mag = mini(mag, new_gun.mag_size)
		if reserve >= 0:
			new_gun.reserve_ammo = reserve
	if index >= 0:
		var old := actor.weapons[index]
		var old_gun := old as Gun
		given = {"id": old.item_id, "mag": old_gun.ammo_in_mag if old_gun else -1,
				"reserve": old_gun.reserve_ammo if old_gun else -1}
		actor.gear_items.erase(old.item_id)
		actor.replace_weapon(index, weapon)
	else:
		actor.equip_weapon(weapon)
		index = actor.weapons.size() - 1
	actor.gear_items.append(id)
	actor.draw_weapon(index)
	actor.materialize_time = summon_time(id)
	actor.materialize_left = actor.materialize_time
	actor.weapon_swapped.emit(id, new_gun.ammo_in_mag if new_gun else -1, new_gun.reserve_ammo if new_gun else -1)
	return given


static func _setup_weapon(weapon: Weapon, id: String, stats: Dictionary) -> void:
	weapon.item_id = id
	weapon.display_name = ItemDB.item_name(id)
	_apply_stats(weapon, stats)


## Copies item stats onto matching properties. A stat with no matching
## property is a typo in ItemDB, so it is reported.
static func _apply_stats(target: Object, stats: Dictionary) -> void:
	for key: String in stats:
		if key in target:
			target.set(key, stats[key])
		else:
			push_warning("Loadout: %s has no property '%s'" % [target.get_class(), key])
