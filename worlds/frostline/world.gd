extends WorldDef
## Frostline: a frozen river valley where the war ended long ago, climbing to
## the Stilled Engine, the terraforming drum that once kept the world warm.
## The co-op expedition world (DESIGN.md section 2): no PvP, and two hostile
## factions that fight each other as readily as you: the Engine's Warden
## automata, still on guard, and packs of Feral stalkers.

const MapScript := preload("res://worlds/frostline/map.gd")

## Share of bots that are Feral stalkers; the rest are Wardens.
const FERAL_CHANCE := 0.45
## The cold (DESIGN.md "Frostline"): body heat lost a second in the open in
## each zone, from the river mouth to the glacier head, and how much faster
## it goes high up in the wind (on a rim or in the air, `EXPOSED_OVER`
## metres over the valley floor).
const ZONE_COLD := [0.7, 1.0, 1.4]
const EXPOSED_OVER := 22.0
const EXPOSED_MULT := 1.5

## Frostline is the gentle world, so its gear is the basic tier. Rare and
## better gear only drops in the PvP world. What it pays instead is parts
## (DESIGN.md "Frostline"): Cryo Cores on the floor, Glacial Alloy up on the
## rims and at the glacier head, Engine Coils only at the Engine, which every
## Mk2 and Mk3 craft needs; its own blueprints for new options (never a
## higher Mk); and a trickle of upgrade data from the hardest places.
const CACHE_TABLE := [
	{"id": "scrap_metal", "weight": 30.0},
	{"id": "circuit_board", "weight": 24.0},
	{"id": "frost_cryo_cell", "weight": 18.0},
	{"id": "cryo_core", "weight": 10.0},
	{"id": "medkit", "weight": 12.0},
	{"id": "power_cell", "weight": 10.0},
	{"id": "smg_stinger", "weight": 3.0},
	{"id": "knife_gutter", "weight": 2.5},
	{"id": "pistol_machine", "weight": 2.5},
	{"id": "rifle_carbine", "weight": 3.0},
	{"id": "frame_runner", "weight": 3.0},
	{"id": "boots_thruster", "weight": 2.5},
	{"id": "optic_reflex", "weight": 2.0},
	{"id": "grip_vertical", "weight": 1.5},
	{"id": "mag_extended", "weight": 1.5},
]

## Outpost roofs need a flight rig to reach.
const ROOFTOP_TABLE := [
	{"id": "frost_cryo_cell", "weight": 30.0},
	{"id": "power_cell", "weight": 22.0},
	{"id": "alloy_ingot", "weight": 12.0},
	{"id": "cryo_core", "weight": 12.0},
	{"id": "glacial_alloy", "weight": 12.0},
	{"id": "hammer_breaker", "weight": 9.0},
	{"id": "axe_splitter", "weight": 7.0},
	{"id": "frame_trooper", "weight": 8.0},
	{"id": "chip_barrier", "weight": 6.0},
	{"id": "boots_thruster", "weight": 5.0},
	{"id": "muzzle_compensator", "weight": 5.0},
	{"id": "grip_angled", "weight": 4.0},
	{"id": "mag_quick", "weight": 4.0},
	{"id": "muzzle_booster", "weight": 3.0},
	{"id": "helm_spotter", "weight": 5.0},
	{"id": "helm_seeker", "weight": 5.0},
	{"id": "helm_warden", "weight": 5.0},
	{"id": "helm_ember", "weight": 5.0},
	{"id": "bp_frame_thermal", "weight": 1.5},
	{"id": "bp_grip_glacier", "weight": 1.5},
	{"id": "upgrade_data", "weight": 2.0},
]

## The top of the relay mast: the best and most exposed loot on the map, and
## the only place Frostline's own Ice Axe and Signal Core turn up, and the
## surest place for Engine Coils and the valley's blueprints.
const RELAY_TABLE := [
	{"id": "frost_signal_core", "weight": 30.0},
	{"id": "frost_ice_axe", "weight": 25.0},
	{"id": "engine_coil", "weight": 18.0},
	{"id": "glacial_alloy", "weight": 18.0},
	{"id": "alloy_ingot", "weight": 20.0},
	{"id": "upgrade_data", "weight": 8.0},
	{"id": "bp_frame_thermal", "weight": 4.0},
	{"id": "bp_grip_glacier", "weight": 4.0},
	{"id": "frame_trooper", "weight": 13.0},
	{"id": "chip_barrier", "weight": 12.0},
]

const WARDEN_DROPS := [
	{"id": "circuit_board", "weight": 40.0},
	{"id": "power_cell", "weight": 30.0},
	{"id": "frost_cryo_cell", "weight": 20.0},
	{"id": "cryo_core", "weight": 10.0},
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
	description = "A frozen valley climbing to a buried engine. Wardens and Ferals fight each other and you. Co-op, no PvP, you keep your equipped gear when you die."
	keep_gear_on_death = true
	# Co-op: the raiders take and hold strongpoints together.
	players_allied = true
	# The quiet world: its mood never shifts.
	war_scale = 0.0
	# Power weapons belong to the war worlds. A world where you keep your
	# gear on death would hand them out without the stakes.
	power_weapon_rate = 0.0
	# Artifacts too: rare gear stays in the full-loot war worlds for now.
	warlord_artifact_chance = 0.0
	pod_artifact_chance = 0.0
	bot_count = 9
	depot_hold_time = 6.0
	# The cold: about two and a half minutes from warm to empty at the
	# river mouth, a minute and a quarter at the glacier head.
	cold = ZONE_COLD[0]
	cold_damage = 4.0
	# Getting out: only at a warm beacon, which a group powers up faster
	# (DESIGN.md "Frostline", "Getting out").
	sign_out_at_beacons = true
	# The snow keeps a trail: footprints and wheel tracks, for a few minutes.
	tracks = true
	# Still, cold air: a shot carries twice as far (DESIGN.md "Frostline").
	shot_carry = 2.0
	# The middle of the lake is thin ice: a bike or a person crosses, a
	# rover or a mech that lingers goes through.
	thin_ice = true
	# The gentle world: a vehicle that goes through is pulled back out by
	# the watch (Caleb's call); the soaking is the price.
	ice_keeps_vehicle = true


func register_items() -> void:
	ItemDB.register("frost_cryo_cell", "Cryo Cell", ItemDB.Rarity.UNCOMMON, 140, ["material"], {},
			"Station coolant cartridge. Still frosted over.")
	ItemDB.register("frost_signal_core", "Signal Core", ItemDB.Rarity.EPIC, 1200, ["material"], {},
			"The heart of the relay mast. Hums when you hold it.")
	ItemDB.register("frost_ice_axe", "Ice Axe", ItemDB.Rarity.RARE, 750, ["weapon", "melee", "one_handed", "axe"],
			{"light_damage": 30.0, "heavy_damage": 80.0, "heavy_lunge": 12.0, "slam_damage": 70.0,
			"reach": 2.9, "swing_style": "chop", "swing_scale": 0.9},
			"Long heavy lunge and a hard dive slam. Built for closing distance on open ice.")


func create_map() -> Node3D:
	return MapScript.new()


## The zones run along the valley: the river mouth is the outer ring, the
## Narrows and the lake the middle, the glacier head and the Engine the core.
func zone_at(pos: Vector3) -> int:
	if pos.z <= MapScript.CORE_FROM_Z:
		return 2
	if pos.z <= MapScript.MIDDLE_FROM_Z:
		return 1
	return 0


## Colder further up the valley, and colder still up in the wind.
func cold_at(pos: Vector3) -> float:
	var rate: float = ZONE_COLD[clampi(zone_at(pos), 0, 2)]
	if pos.y - MapScript.floor_at(pos.z) > EXPOSED_OVER:
		rate *= EXPOSED_MULT
	return rate


## The middle of the frozen lake, where the ice is thin.
func thin_ice_at(pos: Vector3) -> bool:
	return MapScript.lake_reach(pos.x, pos.z) < MapScript.THIN_ICE and pos.y < MapScript.floor_at(pos.z) + 1.0


func zone_name(tier: int) -> String:
	return ["River mouth", "Mid-valley", "Glacier head"][tier] if tier >= 0 and tier <= 2 else ""


func starter_loadout() -> Array[String]:
	return ["rifle_scrap", "blade_scrap", "pistol_service", "jetpack_mk1", "plate_light", "visor_scav",
			"field_dressing"]


func roll_loot(source: String, rng: RandomNumberGenerator) -> Array[String]:
	var table := CACHE_TABLE
	var count := rng.randi_range(2, 3)
	match source:
		"rooftop", "cache_core":
			# The rims and the glacier head pay the same: both are the hard
			# places to reach.
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


## A bot from a marker that names its faction (a Warden post, a Feral den)
## is one of those; any other is a Warden or a Feral by chance.
func equip_bot(bot: Actor, rng: RandomNumberGenerator) -> void:
	var feral := rng.randf() < FERAL_CHANCE
	if bot.faction == "warden" or bot.faction == "feral":
		feral = bot.faction == "feral"
	if feral:
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
	gun.headshot_mult = 1.0
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
