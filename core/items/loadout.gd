class_name Loadout
extends RefCounted
## Loadout slots, and turning a list of item ids into equipped gear on an Actor.
## New weapon and rig types get wired in here.

## Slot name -> the item tag that fits it. Order is the weapon order in a raid.
const SLOTS := {
	"primary": "firearm",
	"melee": "melee",
	"rig": "flight_rig",
	"frame": "armor",
	"ability": "ability",
}
const SLOT_NAMES := {
	"primary": "Primary weapon",
	"melee": "Melee weapon",
	"rig": "Flight rig",
	"frame": "Armor frame",
	"ability": "Ability",
}
## Slots with no free scrap item. Left empty, you deploy without one.
const OPTIONAL_SLOTS := ["ability"]
## How many healing items are taken from the stash on deploy.
const MAX_HEAL_ITEMS := 2


static func equip(actor: Actor, item_ids: Array) -> void:
	var frames: Array[String] = []
	for id: String in item_ids:
		var stats := ItemDB.item_stats(id)
		if ItemDB.has_tag(id, "firearm"):
			var gun := Gun.new()
			_setup_weapon(gun, id, stats)
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
		elif ItemDB.has_tag(id, "armor"):
			frames.append(id)
		else:
			actor.inventory.add_item(id)
	# Frames go last because they scale what the other gear set up.
	for id in frames:
		var stats := ItemDB.item_stats(id)
		actor.health.set_armor(stats.get("armor", 0.0))
		var speed: float = stats.get("speed_mult", 1.0)
		actor.walk_speed *= speed
		actor.sprint_speed *= speed
		actor.flight.heat_per_sec *= stats.get("heat_mult", 1.0)
		actor.flight.burst_heat *= stats.get("heat_mult", 1.0)
		actor.frame_name = ItemDB.item_name(id)
		actor.gear_items.append(id)


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
