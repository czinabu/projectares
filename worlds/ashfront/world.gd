extends WorldDef
## Ashfront: an open battlefield under a red storm sky, strewn with the wrecks
## of war machines. Two bot armies, the Legion and the Tide, fight over its
## landmarks and each other; players fight everyone. Always-on PvP, full
## loot. The field is split into risk zones (DESIGN.md section 2): an outer
## ring of basic soldiers and common loot, a middle of tougher patrols and
## the four landmarks, and the molten Foundry at the core, which burns,
## is held by a warlord and pays the best. Four gate outposts on the rim are
## the only safe ground.

const MapScript := preload("res://worlds/ashfront/map.gd")

const CACHE_TABLE := [
	{"id": "scrap_metal", "weight": 40.0},
	{"id": "circuit_board", "weight": 22.0},
	{"id": "medkit", "weight": 14.0},
	{"id": "power_cell", "weight": 12.0},
	{"id": "alloy_ingot", "weight": 7.0},
	{"id": "targeting_chip", "weight": 4.0},
	{"id": "reactor_core", "weight": 1.0},
	{"id": "rifle_carbine", "weight": 3.0},
	{"id": "smg_stinger", "weight": 3.0},
	{"id": "pistol_machine", "weight": 2.5},
	{"id": "hammer_breaker", "weight": 2.5},
	{"id": "knife_gutter", "weight": 3.0},
	{"id": "axe_splitter", "weight": 2.5},
	{"id": "frame_runner", "weight": 2.5},
	{"id": "frame_trooper", "weight": 2.5},
	{"id": "boots_thruster", "weight": 2.5},
	{"id": "chip_barrier", "weight": 2.5},
	{"id": "optic_reflex", "weight": 2.5},
	{"id": "muzzle_compensator", "weight": 2.0},
	{"id": "grip_vertical", "weight": 2.0},
	{"id": "grip_angled", "weight": 2.0},
	{"id": "mag_extended", "weight": 2.0},
	{"id": "mag_quick", "weight": 1.5},
	{"id": "muzzle_booster", "weight": 1.5},
	{"id": "helm_spotter", "weight": 2.0},
	{"id": "helm_seeker", "weight": 2.0},
	{"id": "helm_warden", "weight": 2.0},
	{"id": "helm_ember", "weight": 2.0},
]

## Rooftops need the jetpack to reach, so they pay better.
const ROOFTOP_TABLE := [
	{"id": "power_cell", "weight": 30.0},
	{"id": "alloy_ingot", "weight": 28.0},
	{"id": "targeting_chip", "weight": 22.0},
	{"id": "reactor_core", "weight": 15.0},
	{"id": "lattice_shard", "weight": 5.0},
	{"id": "dmr_longshot", "weight": 9.0},
	{"id": "pistol_hand_cannon", "weight": 7.0},
	{"id": "shotgun_breacher", "weight": 9.0},
	{"id": "blade_arc", "weight": 9.0},
	{"id": "spear_lancer", "weight": 8.0},
	{"id": "frame_bulwark", "weight": 8.0},
	# Rigs and helmets drop at Mk1 only: Mk2 and up are crafted from
	# blueprints (DESIGN.md section 10), never found.
	{"id": "wings_glide", "weight": 7.0},
	{"id": "boots_thruster", "weight": 5.0},
	{"id": "chip_blink", "weight": 7.0},
	{"id": "chip_pulse", "weight": 7.0},
	{"id": "optic_scope", "weight": 7.0},
	{"id": "muzzle_suppressor", "weight": 6.0},
	{"id": "mag_drum", "weight": 6.0},
	{"id": "optic_longscope", "weight": 2.5},
	{"id": "helm_spotter", "weight": 4.0},
	{"id": "helm_seeker", "weight": 4.0},
	{"id": "helm_warden", "weight": 4.0},
	{"id": "helm_ember", "weight": 4.0},
	# Blueprints for rigs and guns, and the upgrade data that steps a rig up
	# (DESIGN.md section 10). Vehicle blueprints only come from world events.
	{"id": "upgrade_data", "weight": 8.0},
	{"id": "bp_jetpack", "weight": 2.0},
	{"id": "bp_boots_thruster", "weight": 2.0},
	{"id": "bp_wings_glide", "weight": 2.0},
	{"id": "bp_dmr_longshot", "weight": 2.0},
	{"id": "bp_shotgun_breacher", "weight": 2.0},
]

## Abandoned vehicles parked around the field. Anyone can ride one out. The
## mech and the jet are not found lying about.
const VEHICLE_TABLE := [
	{"id": "bike_scrapper", "weight": 70.0},
	{"id": "bike_raider", "weight": 22.0},
	{"id": "rover_warden", "weight": 8.0},
]

## The two armies that fight over the field, and each other. Soldiers carry
## rifles; one in a few is a heavy with a blade.
const ARMIES := {
	"legion": {
		"name": "the Legion",
		"soldier": {"name": "Legionnaire", "look": "stalker", "color": Color(0.3, 0.45, 0.7), "weapon": "Service Rifle"},
		"heavy": {"name": "Legion Vanguard", "look": "sentinel", "color": Color(0.2, 0.3, 0.55), "weapon": "Breaching Blade"},
	},
	"tide": {
		"name": "the Tide",
		"soldier": {"name": "Tide Raider", "look": "scavenger", "color": Color(0.85, 0.3, 0.2), "weapon": "Worn Rifle"},
		"heavy": {"name": "Tide Brute", "look": "heavy", "color": Color(0.5, 0.1, 0.12), "weapon": "Rusted Cleaver"},
	},
}
## How likely a soldier is a heavy, and its health, by the risk zone it
## arrived in: outer ring, middle, core.
const HEAVY_CHANCE := [0.1, 0.25, 0.4]
const SOLDIER_HEALTH := [65.0, 80.0, 95.0]
const HEAVY_HEALTH := [100.0, 120.0, 140.0]
## Damage a second the Foundry's molten ground does to whoever stands in it.
const CORE_BURN := 1.5

const BOT_TABLE := [
	{"id": "scrap_metal", "weight": 45.0},
	{"id": "circuit_board", "weight": 25.0},
	{"id": "medkit", "weight": 18.0},
	{"id": "power_cell", "weight": 12.0},
]


func _init() -> void:
	id = "ashfront"
	display_name = "Ashfront"
	description = "Open battlefield where two armies fight over the wrecks. Always-on PvP, full loot. Safe only at the gate outposts; the burning core pays best."
	# A garrison of four at each of the five landmarks, and patrols between them.
	# Thirty to an army: two garrisons of four, patrols, and a camp at the rim.
	bot_count = 60
	# A hot war draws in up to this many more.
	war_reinforcements = 60
	max_players = 32
	bots_contest_sites = true
	depot_hold_time = 4.0
	# The open battlefield is big enough to fly a jet over.
	open_skies = true
	# The PvP world is where blueprints and upgrade data come from.
	warlord_blueprint_chance = 0.5
	pod_blueprint_chance = 0.35
	warlord_upgrade_data = 2
	pod_upgrade_data = 1


func create_map() -> Node3D:
	return MapScript.new()


func starter_loadout() -> Array[String]:
	return ["rifle_scrap", "blade_scrap", "pistol_service", "jetpack_mk1", "plate_light", "visor_scav",
			"field_dressing"]


func roll_loot(source: String, rng: RandomNumberGenerator) -> Array[String]:
	var table := CACHE_TABLE
	var count := rng.randi_range(2, 4)
	match source:
		"cache_outer":
			# The outer ring: mostly materials, now and then a piece of gear.
			var outer: Array[String] = [ItemDB.roll(CACHE_TABLE, rng)]
			for i in rng.randi_range(1, 2):
				outer.append(ItemDB.roll(BOT_TABLE, rng))
			return outer
		"cache_core":
			# The core: the rooftop haul on the ground, and a chance at a blueprint.
			var core: Array[String] = []
			for i in rng.randi_range(3, 4):
				core.append(ItemDB.roll(ROOFTOP_TABLE, rng))
			core.append_array(roll_crafting_loot(rng, 0.15, 0))
			return core
		"rooftop":
			table = ROOFTOP_TABLE
			count = rng.randi_range(2, 3)
		"bot":
			table = BOT_TABLE
			count = rng.randi_range(1, 3)
		"vehicle":
			table = VEHICLE_TABLE
			count = 1
	var out: Array[String] = []
	for i in count:
		out.append(ItemDB.roll(table, rng))
	return out


## Risk zones by distance from the middle of the field.
func zone_at(pos: Vector3) -> int:
	var out := Vector2(pos.x, pos.z).length()
	if out <= MapScript.CORE_RADIUS:
		return 2
	if out <= MapScript.MIDDLE_RADIUS:
		return 1
	return 0


## The Foundry's slag burns anyone in it, and its heat rises over the roofs:
## the best loot in the world is on a timer.
func hazard_at(pos: Vector3) -> float:
	return CORE_BURN if Vector2(pos.x, pos.z).length() <= MapScript.CORE_RADIUS else 0.0


## Everyone can hurt everyone, except that soldiers of the same army do not
## shoot each other.
func can_damage(attacker: Node, target: Node, _info: DamageInfo) -> bool:
	if attacker == target:
		return false
	var a := attacker as Actor
	var t := target as Actor
	if a and t and ARMIES.has(a.faction) and a.faction == t.faction:
		return false
	return true


## A soldier of one of the two armies. The map's spawn points say which (the
## Raid sets `bot.faction` first); a bot from anywhere else is dealt one.
func equip_bot(bot: Actor, rng: RandomNumberGenerator) -> void:
	var coin := rng.randf()
	# Dressed as one of the armies; a bot of another side (the core's
	# warlord) keeps its own faction and fights both.
	var dress := bot.faction
	if not ARMIES.has(dress):
		dress = "legion" if coin < 0.5 else "tide"
		if bot.faction == "":
			bot.faction = dress
	var army: Dictionary = ARMIES[dress]
	var tier := clampi(int(bot.get_meta("zone", 1)), 0, 2)
	var heavy: bool = rng.randf() < HEAVY_CHANCE[tier]
	var kind: Dictionary = army["heavy"] if heavy else army["soldier"]
	bot.display_name = kind["name"]
	bot.set_meta("look", kind["look"])
	bot.body_color = kind["color"]
	if bot.body_mesh:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = bot.body_color
		bot.body_mesh.material_override = mat
	for id in roll_loot("bot", rng):
		bot.inventory.add_item(id)
	if heavy:
		# A heavy charges with a blade. Its swings are slow and telegraphed,
		# which makes it the enemy to practice parrying on.
		bot.walk_speed = 5.0
		bot.sprint_speed = 8.2
		bot.health.max_health = HEAVY_HEALTH[tier]
		bot.health.health = HEAVY_HEALTH[tier]
		var blade := MeleeWeapon.new()
		blade.display_name = kind["weapon"]
		blade.light_damage = 22.0
		blade.light_windup = 0.5
		blade.light_stamina = 0.0
		blade.reach = 2.6
		bot.equip_weapon(blade)
		return
	bot.walk_speed = 4.5
	bot.sprint_speed = 7.0
	bot.health.max_health = SOLDIER_HEALTH[tier]
	bot.health.health = SOLDIER_HEALTH[tier]
	# Their rifles are worn out: weaker, less accurate, and break when they die.
	var gun := Gun.new()
	gun.display_name = kind["weapon"]
	gun.damage = 6.0
	gun.spread_deg = 3.0
	gun.fire_interval = 0.16
	gun.reserve_ammo = 600
	bot.equip_weapon(gun)
