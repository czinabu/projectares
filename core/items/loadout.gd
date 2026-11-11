class_name Loadout
extends RefCounted
## Turns a list of item ids into equipped gear on an Actor.
## New weapon and rig types get wired in here.


static func equip(actor: Actor, item_ids: Array) -> void:
	for id: String in item_ids:
		if ItemDB.has_tag(id, "firearm"):
			var gun := Gun.new()
			gun.item_id = id
			gun.display_name = ItemDB.item_name(id)
			actor.equip_weapon(gun)
			actor.gear_items.append(id)
		elif ItemDB.has_tag(id, "melee"):
			var blade := MeleeWeapon.new()
			blade.item_id = id
			blade.display_name = ItemDB.item_name(id)
			actor.equip_weapon(blade)
			actor.gear_items.append(id)
		elif ItemDB.has_tag(id, "flight_rig"):
			actor.flight.enabled = true
			actor.flight.item_id = id
			actor.flight.display_name = ItemDB.item_name(id)
			actor.gear_items.append(id)
		elif ItemDB.has_tag(id, "armor"):
			actor.health.set_armor(50.0)
			actor.gear_items.append(id)
		else:
			actor.inventory.add_item(id)
