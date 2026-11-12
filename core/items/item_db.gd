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
	register("rifle_scrap", "Scrap Rifle", Rarity.COMMON, 0, ["weapon", "firearm", "rifle", "starter"], {},
			"Worn automatic rifle.")
	register("blade_scrap", "Scrap Blade", Rarity.COMMON, 0, ["weapon", "melee", "blade", "starter"], {},
			"A sharpened strip of plating.")
	register("pistol_service", "Service Pistol", Rarity.COMMON, 0,
			["weapon", "firearm", "sidearm", "pistol", "starter"],
			{"semi_auto": true, "damage": 22.0, "fire_interval": 0.16, "mag_size": 12, "ammo_in_mag": 12,
			"reserve_ammo": 60, "reload_time": 1.1, "spread_deg": 0.6, "bloom_per_shot": 0.5,
			"recoil_kick_deg": 0.7, "max_range": 90.0},
			"Reliable semi-auto sidearm. Accurate, and quick to reload.")
	register("jetpack_mk1", "Mk1 Jetpack", Rarity.COMMON, 0, ["flight_rig", "starter"], {},
			"Basic jetpack. Tap jump in the air to hover and fly anywhere. Overheats quickly.")
	register("plate_light", "Scrap Plate", Rarity.COMMON, 0, ["armor", "frame_light", "starter"],
			{"armor": 30.0}, "30 armor.")
	register("field_dressing", "Field Dressing", Rarity.COMMON, 0, ["consumable", "heal", "starter"],
			{"heal": 30.0}, "Heals 30.")

	# Firearms
	register("rifle_carbine", "Ashfront Carbine", Rarity.UNCOMMON, 450, ["weapon", "firearm", "rifle", "vendor"],
			{"damage": 24.0, "fire_interval": 0.1, "spread_deg": 0.9, "reserve_ammo": 150},
			"Reliable automatic. Harder hitting and tighter than the scrap rifle.")
	register("smg_stinger", "Stinger SMG", Rarity.UNCOMMON, 420, ["weapon", "firearm", "smg", "vendor"],
			{"damage": 14.0, "fire_interval": 0.065, "mag_size": 40, "ammo_in_mag": 40,
			"reserve_ammo": 200, "spread_deg": 1.9, "recoil_kick_deg": 0.3, "max_range": 80.0},
			"Very fast fire and light recoil. Best up close.")
	register("dmr_longshot", "Longshot DMR", Rarity.RARE, 900, ["weapon", "firearm", "marksman"],
			{"damage": 55.0, "fire_interval": 0.42, "mag_size": 12, "ammo_in_mag": 12,
			"reserve_ammo": 60, "spread_deg": 0.25, "recoil_kick_deg": 1.7, "bloom_per_shot": 0.9,
			"max_range": 220.0},
			"Slow, precise, and heavy hitting. Two shots drop most targets.")
	register("shotgun_breacher", "Breacher Shotgun", Rarity.RARE, 850, ["weapon", "firearm", "shotgun"],
			{"damage": 11.0, "pellets": 8, "fire_interval": 0.75, "mag_size": 6, "ammo_in_mag": 6,
			"reserve_ammo": 36, "spread_deg": 4.5, "recoil_kick_deg": 2.4, "reload_time": 2.4,
			"max_range": 40.0},
			"Eight pellets a shot. Devastating in reach of a blade.")

	# Sidearms: worn on the hip and drawn when the primary runs dry.
	register("pistol_machine", "Hornet Machine Pistol", Rarity.UNCOMMON, 380,
			["weapon", "firearm", "sidearm", "machine_pistol", "vendor"],
			{"damage": 9.0, "fire_interval": 0.055, "mag_size": 20, "ammo_in_mag": 20, "reserve_ammo": 100,
			"reload_time": 1.4, "spread_deg": 2.6, "bloom_per_shot": 0.45, "max_bloom": 4.0,
			"recoil_kick_deg": 0.35, "max_range": 45.0},
			"Full-auto spray. Deadly up close, useless at range.")
	register("pistol_hand_cannon", "Warden Hand Cannon", Rarity.RARE, 750,
			["weapon", "firearm", "sidearm", "hand_cannon"],
			{"semi_auto": true, "damage": 48.0, "headshot_mult": 2.0, "fire_interval": 0.55, "mag_size": 6,
			"ammo_in_mag": 6, "reserve_ammo": 30, "reload_time": 2.2, "spread_deg": 0.4,
			"bloom_per_shot": 1.2, "recoil_kick_deg": 2.6, "max_range": 110.0},
			"Slow, heavy revolver. Headshots hit twice as hard.")

	# Attachments for primaries. Each fits one slot on the gun (its second tag:
	# optic, muzzle, grip or magazine) and fits every primary. `Gun.fit` reads
	# the stats: "mult" scales the gun's own tuning values, "zoom" is how far an
	# optic magnifies while aiming, "quiet" hides the shot, and "model" picks the
	# shape built on the gun. Every one trades something away.
	_attachment("optic_reflex", "Reflex Sight", Rarity.UNCOMMON, 260, "optic", true,
			{"model": "reflex", "zoom": 1.35, "mult": {"ads_spread_mult": 0.8}},
			"Red dot in a small window. A little zoom, and steadier when aimed.")
	_attachment("optic_scope", "4x Ranger Scope", Rarity.RARE, 700, "optic", false,
			{"model": "scope", "zoom": 2.6, "mult": {"ads_spread_mult": 0.55, "spread_deg": 1.15}},
			"Four times zoom and very steady when aimed. Looser from the hip.")
	_attachment("optic_longscope", "8x Longscope", Rarity.EPIC, 1400, "optic", false,
			{"model": "longscope", "zoom": 4.6, "mult": {"ads_spread_mult": 0.4, "spread_deg": 1.3}},
			"Eight times zoom for picking off targets across the map. Clumsy up close.")
	_attachment("muzzle_compensator", "Compensator", Rarity.UNCOMMON, 240, "muzzle", true,
			{"model": "compensator", "mult": {"recoil_kick_deg": 0.7, "recoil_side_deg": 0.75, "spread_deg": 1.08}},
			"Vents gas upward: much less kick, slightly wider spread.")
	_attachment("muzzle_booster", "Muzzle Booster", Rarity.UNCOMMON, 300, "muzzle", true,
			{"model": "booster", "mult": {"fire_interval": 0.88, "recoil_kick_deg": 1.15, "bloom_per_shot": 1.15}},
			"Cycles the action faster. Kicks harder for it.")
	_attachment("muzzle_suppressor", "Suppressor", Rarity.RARE, 650, "muzzle", false,
			{"model": "suppressor", "quiet": true, "mult": {"damage": 0.92, "max_range": 0.9}},
			"No tracers, no flash and a much quieter shot. Costs a little damage and range.")
	_attachment("grip_vertical", "Vertical Grip", Rarity.UNCOMMON, 220, "grip", true,
			{"model": "vertical_grip", "mult": {"recoil_kick_deg": 0.8, "max_bloom": 0.8, "reload_time": 1.06}},
			"Holds a spray down. Slightly slower reloads.")
	_attachment("grip_angled", "Angled Grip", Rarity.UNCOMMON, 220, "grip", true,
			{"model": "angled_grip", "mult": {"bloom_recovery": 1.5, "spread_deg": 0.9, "recoil_kick_deg": 1.05}},
			"Tighter shots and spread that settles fast. A touch more kick.")
	_attachment("mag_extended", "Extended Mag", Rarity.UNCOMMON, 280, "magazine", true,
			{"model": "extended_mag", "mult": {"mag_size": 1.5, "reload_time": 1.15}},
			"Half again as many rounds. Slower to reload.")
	_attachment("mag_quick", "Quick Mag", Rarity.UNCOMMON, 260, "magazine", true,
			{"model": "quick_mag", "mult": {"reload_time": 0.65, "mag_size": 0.85}},
			"Pull tabs and a flared well: reloads a third faster, holds a few less.")
	_attachment("mag_drum", "Drum Mag", Rarity.RARE, 750, "magazine", false,
			{"model": "drum", "mult": {"mag_size": 2.2, "reload_time": 1.45, "spread_deg": 1.1}},
			"More than twice the rounds. Heavy: slow reloads and a wider spread.")

	# Melee
	register("blade_arc", "Arc Blade", Rarity.RARE, 800, ["weapon", "melee", "blade"],
			{"light_damage": 34.0, "heavy_damage": 72.0, "light_recover": 0.22, "parry_window": 0.26},
			"Faster swings and a more forgiving parry.")
	register("hammer_breaker", "Breaker Hammer", Rarity.UNCOMMON, 500, ["weapon", "melee", "hammer", "vendor"],
			{"light_damage": 42.0, "heavy_damage": 95.0, "light_windup": 0.22, "light_recover": 0.45,
			"heavy_windup": 0.55, "light_stamina": 16.0, "heavy_stamina": 36.0, "reach": 3.1,
			"slam_damage": 85.0, "slam_radius": 5.5},
			"Slow and brutal. Its dive slam hits a wide area.")

	# Armor frames
	register("frame_runner", "Runner Frame", Rarity.UNCOMMON, 400, ["armor", "frame_light", "vendor"],
			{"armor": 45.0, "speed_mult": 1.12, "heat_mult": 0.8, "heat_signature": 0.7},
			"Light: 45 armor, 12% faster, jetpack runs cooler. Dim on thermal.")
	register("frame_trooper", "Trooper Frame", Rarity.UNCOMMON, 450, ["armor", "frame_medium", "vendor"],
			{"armor": 85.0},
			"Medium: 85 armor, no penalties.")
	register("frame_bulwark", "Bulwark Frame", Rarity.RARE, 900, ["armor", "frame_heavy"],
			{"armor": 140.0, "speed_mult": 0.86, "heat_mult": 1.25, "heat_signature": 1.3},
			"Heavy: 140 armor, 14% slower, jetpack runs hotter. Bright on thermal.")

	# Flight rigs
	register("jetpack_mk2", "Mk2 Jetpack", Rarity.RARE, 950, ["flight_rig"],
			{"thrust_accel": 42.0, "max_rise_speed": 11.0, "heat_per_sec": 25.0},
			"Free flight: hover, strafe, climb and boost head first. Stronger thrust and a third more air time.")
	register("boots_thruster", "Thruster Boots", Rarity.UNCOMMON, 600, ["flight_rig", "vendor"],
			{"thrust_accel": 0.0, "burst_velocity": 10.5, "burst_heat": 30.0, "cool_per_sec": 34.0,
			"cool_delay": 0.3, "burst_push": 9.0},
			"No sustained flight. Press jump in the air for a hard kick up and the way you steer, three in a row. Cools fastest.")
	register("wings_glide", "Glide Wings", Rarity.RARE, 1100, ["flight_rig"],
			{"thrust_accel": 0.0, "burst_velocity": 13.0, "burst_heat": 55.0, "cool_per_sec": 20.0,
			"glide_fall_speed": 1.8, "glide_speed": 16.0},
			"One strong launch, then hold jump to glide. Fastest and furthest of any rig: dive for speed, pull up to climb on it. Cannot hover.")

	# Abilities
	register("chip_blink", "Phase Step", Rarity.RARE, 900, ["ability", "blink"],
			{"effect": "blink", "cooldown": 8.0, "blink_range": 9.0},
			"Step nine meters in the direction you aim. Stops short of walls.")
	register("chip_barrier", "Kinetic Barrier", Rarity.UNCOMMON, 650, ["ability", "barrier"],
			{"effect": "barrier", "cooldown": 20.0, "duration": 4.0, "damage_reduction": 0.6},
			"For four seconds you take 60% less damage from bullets and blades.")
	register("chip_pulse", "Shock Pulse", Rarity.RARE, 850, ["ability", "pulse"],
			{"effect": "pulse", "cooldown": 16.0, "pulse_radius": 6.5, "pulse_damage": 18.0,
			"pulse_stagger": 1.3},
			"A shockwave that hurts and staggers everyone near you.")

	# Helmets. The visor is the wearer's display in first person, and `mode`
	# picks what it can do (see `Visor`). Mk2 helmets are loot only.
	register("visor_scav", "Scav Visor", Rarity.COMMON, 0, ["helmet", "visor_plain", "starter"],
			{"mode": "", "glass_color": Color(0.8, 0.75, 0.6)},
			"A cracked visor. Shows how hurt you are and nothing else.")
	register("helm_spotter", "Spotter Helmet", Rarity.UNCOMMON, 500, ["helmet", "optic", "vendor"],
			{"mode": "zoom", "zoom_levels": [4.0, 8.0], "glass_color": Color(1.0, 0.75, 0.3)},
			"Binoculars at 4x and 8x with a range finder. Fire while zoomed to tag a target. The lens glints.")
	register("helm_spotter_mk2", "Spotter Helmet Mk2", Rarity.RARE, 1100, ["helmet", "optic"],
			{"mode": "zoom", "zoom_levels": [4.0, 10.0], "tag_time": 7.0, "glass_color": Color(1.0, 0.75, 0.3)},
			"Binoculars at 4x and 10x. Tags last two seconds longer.")
	register("helm_seeker", "Seeker Helmet", Rarity.UNCOMMON, 550, ["helmet", "scanner", "vendor"],
			{"mode": "scan", "cooldown": 25.0, "scan_radius": 40.0, "glass_color": Color(0.4, 1.0, 0.8)},
			"A scan pulse shows where everyone within 40 meters stood. They hear it and know where it came from.")
	register("helm_seeker_mk2", "Seeker Helmet Mk2", Rarity.RARE, 1200, ["helmet", "scanner"],
			{"mode": "scan", "cooldown": 21.0, "scan_radius": 48.0, "glass_color": Color(0.4, 1.0, 0.8)},
			"A wider scan pulse, 48 meters, that is ready again sooner.")

	register("helm_warden", "Warden Helmet", Rarity.UNCOMMON, 600, ["helmet", "tactical", "vendor"],
			{"mode": "threat", "cooldown": 30.0, "threat_range": 60.0, "glass_color": Color(0.55, 0.8, 1.0)},
			"Shows where a hit came from, the health of who you aim at, and what is in nearby loot. "
			+ "Threat Sense outlines anyone aiming at you for five seconds.")
	register("helm_warden_mk2", "Warden Helmet Mk2", Rarity.RARE, 1300, ["helmet", "tactical"],
			{"mode": "threat", "cooldown": 26.0, "threat_range": 75.0, "read_range": 40.0,
			"glass_color": Color(0.55, 0.8, 1.0)},
			"Threat Sense reaches 75 meters and is ready sooner. Reads targets out to 40 meters.")
	register("helm_ember", "Ember Helmet", Rarity.UNCOMMON, 580, ["helmet", "thermal", "vendor"],
			{"mode": "thermal", "battery": 12.0, "glass_color": Color(1.0, 0.45, 0.25)},
			"Thermal sight on a twelve second battery. Warm bodies stand out through smoke and storm, "
			+ "never through walls. A hot jetpack shines.")
	register("helm_ember_mk2", "Ember Helmet Mk2", Rarity.RARE, 1250, ["helmet", "thermal"],
			{"mode": "thermal", "battery": 16.0, "battery_refill": 16.0, "glass_color": Color(1.0, 0.45, 0.25)},
			"Thermal sight with a sixteen second battery that refills faster.")

	# Vehicles. Not carried: the Raid parks one next to you when you deploy, and
	# whoever signs out riding it takes it home. Stats tune Vehicle.
	register("bike_scrapper", "Scrapper Bike", Rarity.UNCOMMON, 600, ["vehicle", "vendor"],
			{"max_speed": 22.0, "boost_speed": 29.0, "body_color": Color(0.6, 0.45, 0.3)},
			"Rattly motorbike. Fast, loud, and no cover for the rider.")
	register("bike_raider", "Raider Bike", Rarity.RARE, 1400, ["vehicle"],
			{"max_speed": 27.0, "boost_speed": 37.0, "accel": 18.0, "turn_rate": 2.6,
			"body_color": Color(0.85, 0.2, 0.15)},
			"Tuned motorbike. Quicker off the line and much faster flat out.")

	# Consumables
	register("medkit", "Medkit", Rarity.COMMON, 60, ["consumable", "heal", "vendor"], {"heal": 50.0}, "Heals 50.")

	# Loot
	register("scrap_metal", "Scrap Metal", Rarity.COMMON, 25, ["material"])
	register("circuit_board", "Circuit Board", Rarity.UNCOMMON, 70, ["material"])
	register("power_cell", "Power Cell", Rarity.UNCOMMON, 110, ["material"])
	register("alloy_ingot", "Alloy Ingot", Rarity.RARE, 240, ["material"])
	register("targeting_chip", "Targeting Chip", Rarity.RARE, 320, ["augment"])
	register("reactor_core", "Reactor Core", Rarity.EPIC, 900, ["material"])
	register("lattice_shard", "Lattice Shard", Rarity.RELIC, 2500, ["relic"])

	# Furniture and decorations for a home base. Bought from the Furnisher,
	# kept in the stash, never taken on a raid. "footprint" is the size in
	# meters and "color" the base color, for whatever displays them.
	_furniture("furn_table", "Mess Table", 120, Vector3(1.6, 0.8, 0.9), Color(0.42, 0.36, 0.3),
			"A steel table that has seen a lot of card games.")
	_furniture("furn_bunk", "Steel Bunk", 150, Vector3(2.0, 0.6, 0.9), Color(0.35, 0.38, 0.42),
			"Somewhere to sleep between drops.")
	_furniture("furn_locker", "Gear Locker", 200, Vector3(0.9, 1.9, 0.5), Color(0.3, 0.4, 0.35),
			"Dented, lockable, yours.")
	_furniture("furn_couch", "Salvaged Couch", 250, Vector3(2.0, 0.8, 0.9), Color(0.5, 0.25, 0.2),
			"Pulled from a wreck and surprisingly comfortable.")
	_furniture("furn_workbench", "Workbench", 300, Vector3(1.8, 0.9, 0.8), Color(0.45, 0.4, 0.3),
			"A place to strip, clean and admire your gear.")
	_furniture("furn_armor_stand", "Armor Stand", 300, Vector3(0.7, 1.8, 0.7), Color(0.4, 0.4, 0.45),
			"Shows off a frame at full height.")
	_furniture("furn_weapon_rack", "Weapon Rack", 350, Vector3(1.8, 1.6, 0.4), Color(0.3, 0.3, 0.33),
			"Wall rack for the weapons you are proudest of.")
	_furniture("furn_trophy_case", "Trophy Case", 500, Vector3(1.4, 1.9, 0.5), Color(0.55, 0.45, 0.25),
			"Glass-fronted case for the rarest things you have brought home.", Rarity.UNCOMMON)
	_furniture("decor_lamp", "Work Lamp", 60, Vector3(0.3, 1.5, 0.3), Color(1.0, 0.85, 0.55),
			"Warm light on a tripod.", Rarity.COMMON, true)
	_furniture("decor_plant", "Potted Fern", 70, Vector3(0.5, 0.9, 0.5), Color(0.25, 0.55, 0.3),
			"Something green that is not trying to kill you.", Rarity.COMMON, true)
	_furniture("decor_rug", "Woven Rug", 80, Vector3(2.4, 0.03, 1.6), Color(0.55, 0.3, 0.25),
			"Takes the chill off a concrete floor.", Rarity.COMMON, true)
	_furniture("decor_banner", "War Banner", 100, Vector3(1.0, 1.8, 0.05), Color(0.7, 0.2, 0.15),
			"Hang your colors.", Rarity.COMMON, true)
	_furniture("decor_neon", "Neon Sign", 180, Vector3(1.2, 0.5, 0.1), Color(0.2, 0.9, 1.0),
			"Buzzes a little. Glows a lot.", Rarity.UNCOMMON, true)

	# Clothing. Cosmetic only: an outfit item in the stash unlocks the
	# character customizer outfits listed in its "outfits" stat (the ids the
	# customizer uses, one per body build that has the outfit). It fits no
	# loadout slot, so it never goes on a raid and is never lost.
	_outfit("outfit_scout", "Scout Outfit", 150, ["m_Adventurer"], "Hard-wearing field clothes.")
	_outfit("outfit_punk", "Punk Outfit", 200, ["m_Punk", "f_Punk"], "Loud, torn and proud of it.")
	_outfit("outfit_sellsword", "Sellsword Outfit", 300, ["f_Medieval"], "Old-world leathers for hired blades.",
			Rarity.UNCOMMON)
	_outfit("outfit_envoy", "Envoy Outfit", 350, ["f_Formal"], "Formal wear that says you are not here to shoot.",
			Rarity.UNCOMMON)
	_outfit("outfit_suit", "Suit", 350, ["m_Suit", "f_Suit"], "For when the deal matters more than the fight.",
			Rarity.UNCOMMON)
	_outfit("outfit_trooper", "Trooper Outfit", 400, ["m_Swat", "f_Soldier"], "Fatigues and webbing. Looks the part.",
			Rarity.UNCOMMON)


## Registers a weapon attachment for `slot` (also its tag: see `Loadout.SLOTS`).
func _attachment(id: String, display_name: String, rarity: Rarity, value: int, slot: String, vendor: bool,
		stats: Dictionary, description: String) -> void:
	var tags := ["attachment", slot]
	if vendor:
		tags.append("vendor")
	register(id, display_name, rarity, value, tags, stats, description)


## Registers a clothing item that unlocks the customizer outfits `outfits`.
func _outfit(id: String, display_name: String, value: int, outfits: Array, description: String,
		rarity: Rarity = Rarity.COMMON) -> void:
	register(id, display_name, rarity, value, ["cosmetic", "vendor"], {"outfits": outfits}, description)


## Registers a home base piece. Small pieces are also tagged "decor".
func _furniture(id: String, display_name: String, value: int, footprint: Vector3, color: Color,
		description: String, rarity: Rarity = Rarity.COMMON, decor := false) -> void:
	var tags := ["furniture", "vendor"]
	if decor:
		tags.append("decor")
	register(id, display_name, rarity, value, tags, {"footprint": footprint, "color": color}, description)


## Tags also pick the mastery track an item trains: "rifle", "blink", "frame_heavy"
## and so on (see core/progression/mastery_db.gd).
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


## Every registered item id, in the order they were registered.
func all_ids() -> Array:
	return _items.keys()


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
