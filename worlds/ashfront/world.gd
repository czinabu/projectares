extends WorldDef
## Ashfront: an open battlefield under a red storm sky, strewn with the wrecks
## of war machines. Two bot armies, the Legion and the Tide, fight over its
## landmarks and each other; players fight everyone. Always-on PvP, full
## loot, no safe zones.

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
	{"id": "frame_runner", "weight": 2.5},
	{"id": "frame_trooper", "weight": 2.5},
	{"id": "boots_thruster", "weight": 2.5},
	{"id": "chip_barrier", "weight": 2.5},
	{"id": "helm_spotter", "weight": 2.0},
	{"id": "helm_seeker", "weight": 2.0},
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
	{"id": "frame_bulwark", "weight": 8.0},
	{"id": "jetpack_mk2", "weight": 7.0},
	{"id": "wings_glide", "weight": 7.0},
	{"id": "chip_blink", "weight": 7.0},
	{"id": "chip_pulse", "weight": 7.0},
	{"id": "helm_spotter_mk2", "weight": 6.0},
	{"id": "helm_seeker_mk2", "weight": 6.0},
]

## Abandoned bikes parked around the field. Anyone can ride one out.
const VEHICLE_TABLE := [
	{"id": "bike_scrapper", "weight": 75.0},
	{"id": "bike_raider", "weight": 25.0},
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
const HEAVY_CHANCE := 0.25

const BOT_TABLE := [
	{"id": "scrap_metal", "weight": 45.0},
	{"id": "circuit_board", "weight": 25.0},
	{"id": "medkit", "weight": 18.0},
	{"id": "power_cell", "weight": 12.0},
]


func _init() -> void:
	id = "ashfront"
	display_name = "Ashfront"
	description = "Open battlefield where two armies fight over the wrecks. Always-on PvP, full loot, no safe zones."
	# A garrison of four at each of the five landmarks, and patrols between them.
	# Thirty to an army: two garrisons of four, patrols, and a camp at the rim.
	bot_count = 60
	# A hot war draws in up to this many more.
	war_reinforcements = 60
	max_players = 32
	bots_contest_sites = true
	depot_hold_time = 4.0


func create_map() -> Node3D:
	return MapScript.new()


func starter_loadout() -> Array[String]:
	return ["rifle_scrap", "blade_scrap", "pistol_service", "jetpack_mk1", "plate_light", "visor_scav",
			"field_dressing"]


func roll_loot(source: String, rng: RandomNumberGenerator) -> Array[String]:
	var table := CACHE_TABLE
	var count := rng.randi_range(2, 4)
	match source:
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
	if not ARMIES.has(bot.faction):
		bot.faction = "legion" if coin < 0.5 else "tide"
	var army: Dictionary = ARMIES[bot.faction]
	var heavy := rng.randf() < HEAVY_CHANCE
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
		bot.health.max_health = 120.0
		bot.health.health = 120.0
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
	bot.health.max_health = 80.0
	bot.health.health = 80.0
	# Their rifles are worn out: weaker, less accurate, and break when they die.
	var gun := Gun.new()
	gun.display_name = kind["weapon"]
	gun.damage = 6.0
	gun.spread_deg = 3.0
	gun.fire_interval = 0.16
	gun.reserve_ammo = 600
	bot.equip_weapon(gun)
