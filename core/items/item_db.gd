extends Node
## Autoload `ItemDB`: every item definition in the game.
##
## Items are plain data with tags. Worlds decide which tags they allow, which is
## what lets one stash work across very different worlds later.

enum Rarity { COMMON, UNCOMMON, RARE, EPIC, RELIC }

const RARITY_NAMES := ["Common", "Uncommon", "Rare", "Epic", "Relic"]
const RARITY_COLORS := [
	Color(0.75, 0.75, 0.75),
	Color(0.35, 0.8, 0.4),
	Color(0.3, 0.55, 1.0),
	Color(0.7, 0.35, 0.95),
	Color(1.0, 0.65, 0.15),
]

var _items := {}


func _ready() -> void:
	# Free scrap kit. Tagged "starter": it fills empty loadout slots, and it
	# can never be stashed, so it cannot be farmed.
	register("rifle_scrap", "Scrap Rifle", Rarity.COMMON, 0, ["weapon", "firearm", "starter"], {},
			"Worn automatic rifle.")
	register("blade_scrap", "Scrap Blade", Rarity.COMMON, 0, ["weapon", "melee", "starter"], {},
			"A sharpened strip of plating.")
	register("jetpack_mk1", "Mk1 Jetpack", Rarity.COMMON, 0, ["flight_rig", "starter"], {},
			"Basic jetpack. Overheats quickly.")
	register("plate_light", "Scrap Plate", Rarity.COMMON, 0, ["armor", "starter"],
			{"armor": 30.0}, "30 armor.")
	register("field_dressing", "Field Dressing", Rarity.COMMON, 0, ["consumable", "heal", "starter"],
			{"heal": 30.0}, "Heals 30.")

	# Firearms
	register("rifle_carbine", "Ashfront Carbine", Rarity.UNCOMMON, 450, ["weapon", "firearm"],
			{"damage": 24.0, "fire_interval": 0.1, "spread_deg": 0.9, "reserve_ammo": 150},
			"Reliable automatic. Harder hitting and tighter than the scrap rifle.")
	register("smg_stinger", "Stinger SMG", Rarity.UNCOMMON, 420, ["weapon", "firearm"],
			{"damage": 14.0, "fire_interval": 0.065, "mag_size": 40, "ammo_in_mag": 40,
			"reserve_ammo": 200, "spread_deg": 1.9, "recoil_kick_deg": 0.3, "max_range": 80.0},
			"Very fast fire and light recoil. Best up close.")
	register("dmr_longshot", "Longshot DMR", Rarity.RARE, 900, ["weapon", "firearm"],
			{"damage": 55.0, "fire_interval": 0.42, "mag_size": 12, "ammo_in_mag": 12,
			"reserve_ammo": 60, "spread_deg": 0.25, "recoil_kick_deg": 1.7, "bloom_per_shot": 0.9,
			"max_range": 220.0},
			"Slow, precise, and heavy hitting. Two shots drop most targets.")
	register("shotgun_breacher", "Breacher Shotgun", Rarity.RARE, 850, ["weapon", "firearm"],
			{"damage": 11.0, "pellets": 8, "fire_interval": 0.75, "mag_size": 6, "ammo_in_mag": 6,
			"reserve_ammo": 36, "spread_deg": 4.5, "recoil_kick_deg": 2.4, "reload_time": 2.4,
			"max_range": 40.0},
			"Eight pellets a shot. Devastating in reach of a blade.")

	# Melee
	register("blade_arc", "Arc Blade", Rarity.RARE, 800, ["weapon", "melee"],
			{"light_damage": 34.0, "heavy_damage": 72.0, "light_recover": 0.22, "parry_window": 0.26},
			"Faster swings and a more forgiving parry.")
	register("hammer_breaker", "Breaker Hammer", Rarity.UNCOMMON, 500, ["weapon", "melee"],
			{"light_damage": 42.0, "heavy_damage": 95.0, "light_windup": 0.22, "light_recover": 0.45,
			"heavy_windup": 0.55, "light_stamina": 16.0, "heavy_stamina": 36.0, "reach": 3.1,
			"slam_damage": 85.0, "slam_radius": 5.5},
			"Slow and brutal. Its dive slam hits a wide area.")

	# Armor frames
	register("frame_runner", "Runner Frame", Rarity.UNCOMMON, 400, ["armor"],
			{"armor": 45.0, "speed_mult": 1.12, "heat_mult": 0.8},
			"Light: 45 armor, 12% faster, jetpack runs cooler.")
	register("frame_trooper", "Trooper Frame", Rarity.UNCOMMON, 450, ["armor"],
			{"armor": 85.0},
			"Medium: 85 armor, no penalties.")
	register("frame_bulwark", "Bulwark Frame", Rarity.RARE, 900, ["armor"],
			{"armor": 140.0, "speed_mult": 0.86, "heat_mult": 1.25},
			"Heavy: 140 armor, 14% slower, jetpack runs hotter.")

	# Flight rigs
	register("jetpack_mk2", "Mk2 Jetpack", Rarity.RARE, 950, ["flight_rig"],
			{"thrust_accel": 42.0, "max_rise_speed": 11.0, "heat_per_sec": 25.0},
			"Stronger thrust and a third more air time.")

	# Consumables
	register("medkit", "Medkit", Rarity.COMMON, 60, ["consumable", "heal"], {"heal": 50.0}, "Heals 50.")

	# Loot
	register("scrap_metal", "Scrap Metal", Rarity.COMMON, 25, ["material"])
	register("circuit_board", "Circuit Board", Rarity.UNCOMMON, 70, ["material"])
	register("power_cell", "Power Cell", Rarity.UNCOMMON, 110, ["material"])
	register("alloy_ingot", "Alloy Ingot", Rarity.RARE, 240, ["material"])
	register("targeting_chip", "Targeting Chip", Rarity.RARE, 320, ["augment"])
	register("reactor_core", "Reactor Core", Rarity.EPIC, 900, ["material"])
	register("lattice_shard", "Lattice Shard", Rarity.RELIC, 2500, ["relic"])


## `stats` are applied to the weapon, rig or actor when the item is equipped.
func register(id: String, display_name: String, rarity: Rarity, value: int, tags: Array,
		stats: Dictionary = {}, description: String = "") -> void:
	_items[id] = {
		"id": id,
		"name": display_name,
		"rarity": rarity,
		"value": value,
		"tags": tags,
		"stats": stats,
		"description": description,
	}


func has_item(id: String) -> bool:
	return _items.has(id)


func get_item(id: String) -> Dictionary:
	return _items.get(id, {})


func item_name(id: String) -> String:
	return get_item(id).get("name", id)


func item_value(id: String) -> int:
	return get_item(id).get("value", 0)


func item_rarity(id: String) -> int:
	return get_item(id).get("rarity", Rarity.COMMON)


func has_tag(id: String, tag: String) -> bool:
	return tag in get_item(id).get("tags", [])


func item_stats(id: String) -> Dictionary:
	return get_item(id).get("stats", {})


func item_description(id: String) -> String:
	return get_item(id).get("description", "")


func rarity_name(id: String) -> String:
	return RARITY_NAMES[item_rarity(id)]


func total_value(ids: Array) -> int:
	var total := 0
	for id: String in ids:
		total += item_value(id)
	return total


## Picks one item id from a weighted table: [{ "id": String, "weight": float }].
func roll(table: Array, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for entry: Dictionary in table:
		total += entry.weight
	if total <= 0.0:
		return ""
	var pick := rng.randf() * total
	for entry: Dictionary in table:
		pick -= entry.weight
		if pick <= 0.0:
			return entry.id
	return table.back().id


## "3x Scrap Metal, 1x Power Cell" style summary, most valuable first.
func summarize(ids: Array) -> String:
	if ids.is_empty():
		return "nothing"
	var counts := {}
	for id: String in ids:
		counts[id] = counts.get(id, 0) + 1
	var keys := counts.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return item_value(a) > item_value(b))
	var parts: Array[String] = []
	for id: String in keys:
		parts.append("%dx %s" % [counts[id], item_name(id)])
	return ", ".join(parts)
