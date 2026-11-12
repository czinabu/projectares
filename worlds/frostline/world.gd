extends WorldDef
## Frostline: a dead listening station on a glacier shelf, buried in whiteout.
## Two hostile factions share the ice and fight each other as readily as you:
## the station's Warden automata and packs of Feral stalkers.

const MapScript := preload("res://worlds/frostline/map.gd")

## Share of bots that are Feral stalkers; the rest are Wardens.
const FERAL_CHANCE := 0.45

## Frostline is the gentle world, so its gear is the basic tier. Rare and
## better gear only drops in the PvP world.
const CACHE_TABLE := [
	{"id": "scrap_metal", "weight": 30.0},
	{"id": "circuit_board", "weight": 24.0},
	{"id": "frost_cryo_cell", "weight": 18.0},
	{"id": "medkit", "weight": 12.0},
	{"id": "power_cell", "weight": 10.0},
	{"id": "smg_stinger", "weight": 3.0},
	{"id": "rifle_carbine", "weight": 3.0},
	{"id": "frame_runner", "weight": 3.0},
	{"id": "boots_thruster", "weight": 2.5},
]

## Outpost roofs need a flight rig to reach.
const ROOFTOP_TABLE := [
	{"id": "frost_cryo_cell", "weight": 30.0},
	{"id": "power_cell", "weight": 22.0},
	{"id": "alloy_ingot", "weight": 12.0},
	{"id": "hammer_breaker", "weight": 9.0},
	{"id": "frame_trooper", "weight": 8.0},
	{"id": "chip_barrier", "weight": 6.0},
	{"id": "boots_thruster", "weight": 5.0},
	{"id": "helm_spotter", "weight": 5.0},
	{"id": "helm_seeker", "weight": 5.0},
]

## The top of the relay mast: the best and most exposed loot on the map, and
## the only place Frostline's own Ice Axe and Signal Core turn up.
const RELAY_TABLE := [
	{"id": "frost_signal_core", "weight": 30.0},
	{"id": "frost_ice_axe", "weight": 25.0},
	{"id": "alloy_ingot", "weight": 20.0},
	{"id": "frame_trooper", "weight": 13.0},
	{"id": "chip_barrier", "weight": 12.0},
]

const WARDEN_DROPS := [
	{"id": "circuit_board", "weight": 40.0},
	{"id": "power_cell", "weight": 30.0},
	{"id": "frost_cryo_cell", "weight": 20.0},
	{"id": "targeting_chip", "weight": 5.0},
]

## Ferals carry whatever they scavenged.
const FERAL_DROPS := [
	{"id": "scrap_metal", "weight": 50.0},
	{"id": "medkit", "weight": 30.0},
	{"id": "frost_cryo_cell", "weight": 15.0},
]


func _init() -> void:
	id = "frostline"
	display_name = "Frostline"
	description = "Whiteout glacier station. Wardens and Ferals fight each other and you. No PvP, you keep your equipped gear when you die, and the loot is basic."
	keep_gear_on_death = true
	# Co-op: the raiders take and hold strongpoints together.
	players_allied = true
	# The quiet world: its mood never shifts.
	war_scale = 0.0
	bot_count = 9
	depot_hold_time = 6.0


func register_items() -> void:
	ItemDB.register("frost_cryo_cell", "Cryo Cell", ItemDB.Rarity.UNCOMMON, 140, ["material"], {},
			"Station coolant cartridge. Still frosted over.")
	ItemDB.register("frost_signal_core", "Signal Core", ItemDB.Rarity.EPIC, 1200, ["material"], {},
			"The heart of the relay mast. Hums when you hold it.")
	ItemDB.register("frost_ice_axe", "Ice Axe", ItemDB.Rarity.RARE, 750, ["weapon", "melee"],
			{"light_damage": 30.0, "heavy_damage": 80.0, "heavy_lunge": 12.0, "slam_damage": 70.0,
			"reach": 2.9},
			"Long heavy lunge and a hard dive slam. Built for closing distance on open ice.")


func create_map() -> Node3D:
	return MapScript.new()


func starter_loadout() -> Array[String]:
	return ["rifle_scrap", "blade_scrap", "jetpack_mk1", "plate_light", "visor_scav", "field_dressing"]


func roll_loot(source: String, rng: RandomNumberGenerator) -> Array[String]:
	var table := CACHE_TABLE
	var count := rng.randi_range(2, 3)
	match source:
		"rooftop":
			table = ROOFTOP_TABLE
			count = rng.randi_range(2, 3)
		"relay":
			table = RELAY_TABLE
			count = rng.randi_range(3, 4)
		"warden", "bot":
			table = WARDEN_DROPS
			count = rng.randi_range(1, 3)
		"feral":
			table = FERAL_DROPS
			count = rng.randi_range(1, 2)
	var out: Array[String] = []
	for i in count:
		out.append(ItemDB.roll(table, rng))
	return out


## A PvE world: nobody can hurt their own faction, and every player is in the
## same one. Wardens and Ferals hunt each other, so a fight between them is a
## chance to slip past or third-party.
func can_damage(attacker: Node, target: Node, _info: DamageInfo) -> bool:
	if attacker == target:
		return false
	var a := attacker as Actor
	var t := target as Actor
	if a and t and a.faction == t.faction:
		return false
	return true


func equip_bot(bot: Actor, rng: RandomNumberGenerator) -> void:
	if rng.randf() < FERAL_CHANCE:
		_make_feral(bot, rng)
	else:
		_make_warden(bot, rng)


## Station automata: slow and tough, with accurate long-range rifles.
func _make_warden(bot: Actor, rng: RandomNumberGenerator) -> void:
	bot.faction = "warden"
	bot.display_name = "Warden"
	bot.set_meta("look", "sentinel")
	_paint(bot, Color(0.55, 0.8, 0.95))
	bot.walk_speed = 3.6
	bot.sprint_speed = 5.2
	bot.health.max_health = 110.0
	bot.health.health = 110.0
	bot.health.set_armor(20.0)
	for item in roll_loot("warden", rng):
		bot.inventory.add_item(item)
	var gun := Gun.new()
	gun.display_name = "Warden Repeater"
	gun.damage = 11.0
	gun.spread_deg = 1.2
	gun.fire_interval = 0.45
	gun.max_range = 160.0
	gun.reserve_ammo = 400
	bot.equip_weapon(gun)


## Fast, fragile pack hunters with hooked blades.
func _make_feral(bot: Actor, rng: RandomNumberGenerator) -> void:
	bot.faction = "feral"
	bot.display_name = "Feral Stalker"
	bot.set_meta("look", "stalker")
	_paint(bot, Color(0.18, 0.2, 0.26))
	bot.walk_speed = 6.0
	bot.sprint_speed = 9.0
	bot.health.max_health = 65.0
	bot.health.health = 65.0
	for item in roll_loot("feral", rng):
		bot.inventory.add_item(item)
	var blade := MeleeWeapon.new()
	blade.display_name = "Hooked Blade"
	blade.light_damage = 14.0
	blade.light_windup = 0.35
	blade.light_stamina = 0.0
	blade.reach = 2.4
	bot.equip_weapon(blade)


func _paint(bot: Actor, color: Color) -> void:
	bot.body_color = color
	if bot.body_mesh:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		bot.body_mesh.material_override = mat
