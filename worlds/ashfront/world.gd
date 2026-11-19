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

## Abandoned vehicles parked around the field. Anyone can ride one out, and
## signing out on one takes it home, so the rare ones are placed by risk like
## the loot: a Scrapper at the quiet rim and in the camps (to get moving, not
## a prize), sometimes a Raider by the ramps, and the best odds of a Raider
## or a rover at the strongpoints. The mech and the jet are never found lying
## about: they are crafted from blueprints. The odds are first guesses.
const VEHICLE_TABLE := [
	{"id": "bike_scrapper", "weight": 80.0},
	{"id": "bike_raider", "weight": 20.0},
]
const VEHICLE_RIM_TABLE := [
	{"id": "bike_scrapper", "weight": 1.0},
]
const VEHICLE_SITE_TABLE := [
	{"id": "bike_scrapper", "weight": 60.0},
	{"id": "bike_raider", "weight": 25.0},
	{"id": "rover_warden", "weight": 15.0},
]

## The two armies that fight over the field, and each other. Most of each
## army are soldiers with rifles, and one in a few of those is a heavy with
## a blade. Beside them march exo troopers (a person in powered armor) and,
## further in, the rare Kiln Walker (DESIGN.md "Heavy units").
const ARMIES := {
	"legion": {
		"name": "the Legion",
		"soldier": {"name": "Legionnaire", "look": "legionary", "color": Color(0.3, 0.45, 0.7), "weapon": "Service Rifle"},
		"heavy": {"name": "Legion Vanguard", "look": "sentinel", "color": Color(0.2, 0.3, 0.55), "weapon": "Breaching Blade"},
		"marksman": {"name": "Legion Marksman", "look": "legionary", "color": Color(0.22, 0.36, 0.6), "weapon": "Marksman Rifle"},
		"exo": {"name": "Legion Exo Trooper", "look": "exo", "color": Color(0.3, 0.6, 1.0), "weapon": "Support Rifle"},
		"walker": {"name": "Kiln Walker", "look": "walker", "color": Color(0.3, 0.6, 1.0), "weapon": "Kiln Cannon"},
	},
	"tide": {
		"name": "the Tide",
		"soldier": {"name": "Tide Raider", "look": "tide", "color": Color(0.85, 0.3, 0.2), "weapon": "Worn Rifle"},
		"heavy": {"name": "Tide Brute", "look": "heavy", "color": Color(0.5, 0.1, 0.12), "weapon": "Rusted Cleaver"},
		"runner": {"name": "Tide Runner", "look": "tide", "color": Color(0.95, 0.42, 0.2), "weapon": "Hook Knife"},
		"exo": {"name": "Tide Exo Trooper", "look": "exo", "color": Color(1.0, 0.35, 0.15), "weapon": "Support Rifle"},
		"walker": {"name": "Kiln Walker", "look": "walker", "color": Color(1.0, 0.35, 0.15), "weapon": "Kiln Cannon"},
	},
}
## How each army fights (DESIGN.md "The enemy AI pass", step 3), set on its
## bots as metas `BotBrain` reads. The Legion holds ground: its riflemen
## fight from 30 m and further, see further, and one in a few of them is a
## marksman; more of it are exo troopers, fewer blades. The Tide swarms:
## more blades and its runners, closing to 10 m, a pincer of two flankers,
## one more hunter on a person, and a fireteam that loses a third of itself
## breaks off. "exo" and "heavy" scale the zone's chances; "special" is the
## army's own kind, rolled among its riflemen at "special_chance" by zone.
const DOCTRINE := {
	"legion": {"range": 30.0, "reach": 55.0, "sight": 48.0, "exo": 1.35, "heavy": 0.6,
			"special": "marksman", "special_chance": [0.12, 0.16, 0.2]},
	"tide": {"range": 10.0, "reach": 30.0, "sight": 38.0, "exo": 0.65, "heavy": 1.35,
			"special": "runner", "special_chance": [0.15, 0.2, 0.25],
			"flankers": 2, "hunters": 1, "breaks_at": 0.33},
}
## The Legion marksman: a rifleman with a long, slow, hard-hitting rifle who
## keeps back, sees far and fires single aimed rounds. Plain soldier health:
## close the distance and it is the easiest Legion kill.
const MARKSMAN_DAMAGE := [50.0, 52.0, 54.0]
const MARKSMAN_SPREAD := [0.35, 0.32, 0.3]
const MARKSMAN_INTERVAL := 0.75
const MARKSMAN_SIGHT := 70.0
const MARKSMAN_REACH := 70.0
const MARKSMAN_RANGE := 45.0
const MARKSMAN_BURST := Vector2(0.12, 0.9)
## The Tide runner: fast, lightly built, a quick hooked knife. It arrives
## first and dies first; its swing is short but still telegraphed.
const RUNNER_HEALTH := [150.0, 160.0, 175.0]
const RUNNER_DAMAGE := [34.0, 36.0, 38.0]
const RUNNER_WINDUP := 0.32
const RUNNER_WALK := 5.6
const RUNNER_SPRINT := 10.5
const RUNNER_DASH := 0.7
## The spawn mix by the risk zone a bot arrived in (outer ring, middle,
## core): the share that are exo troopers and walkers. The rest are the
## armies' people, soldiers and blade heavies.
const EXO_CHANCE := [0.09, 0.18, 0.22]
const WALKER_CHANCE := [0.0, 0.04, 0.08]
## How likely one of the armies' people is a heavy, and its health, by the
## risk zone it arrived in: outer ring, middle, core.
const HEAVY_CHANCE := [0.1, 0.25, 0.4]
const SOLDIER_HEALTH := [115.0, 135.0, 140.0]
const HEAVY_HEALTH := [225.0, 260.0, 270.0]
## Army rifles, one round in every zone. Harder than a carbine so a hit gets
## through a mid kit's plates, and looser and a little slower. Toward the core
## the soldier changes (more health, higher aim skill), not the cartridge.
const GUN_DAMAGE := [28.0, 28.0, 28.0]
const GUN_SPREAD := [1.32, 1.28, 1.4]
const GUN_INTERVAL := [0.12, 0.12, 0.12]
## A heavy's swing. Slow and telegraphed (the parry drill). Two hits leave a
## mid kit nearly dead, and a third ends it, so missing the parry is the loss.
const HEAVY_DAMAGE := [48.0, 48.0, 48.0]
## A heavy's own heavy (bots hold one now and then, DESIGN.md "Melee bots"):
## slower to come still, so it is the easiest swing of all to parry or step
## away from, and a quarter harder when it lands.
const HEAVY_HEAVY_WINDUP := 0.9
const HEAVY_HEAVY_MULT := 1.25
## Exo troopers: an ordinary soldier in a mechanical exoskeleton suit. More health and real plates,
## a little slower, and a support rifle that fires longer bursts. No blade.
const EXO_HEALTH := [160.0, 165.0, 170.0]
const EXO_ARMOR := [45.0, 55.0, 70.0]
const EXO_DAMAGE := [23.0, 22.0, 22.0]
const EXO_SPREAD := [1.25, 1.2, 1.25]
const EXO_INTERVAL := [0.1, 0.1, 0.1]
## How likely an exo trooper carries a spare frame, and which.
const EXO_FRAME_CHANCE := 0.12
const EXO_FRAMES := [
	{"id": "frame_trooper", "weight": 75.0},
	{"id": "frame_bulwark", "weight": 25.0},
]
## The Kiln Walker: a 3 m war machine, slow on its feet and slow to turn,
## with a hitscan support cannon that leads fliers well. Its power plant is
## on its back: hits from behind or above do `WALKER_REAR_MULT` times as
## much. Meant for two players, or one who keeps behind it. Middle and core
## only, one at each landmark (`bot_allowed`).
const WALKER_HEALTH := [360.0, 360.0, 400.0]
const WALKER_ARMOR := [60.0, 60.0, 80.0]
const WALKER_HEIGHT := 3.0
const WALKER_WALK := 3.2
const WALKER_SPRINT := 3.6
const WALKER_DAMAGE := [32.0, 32.0, 34.0]
const WALKER_SPREAD := [0.5, 0.5, 0.45]
const WALKER_INTERVAL := [0.55, 0.55, 0.5]
const WALKER_REAR_MULT := 2.0
## How fast its aim (and so its body) comes round, degrees a second at
## average skill (soldiers turn at 200), and how well it leads a target.
const WALKER_TURN := 70.0
const WALKER_TRACK_LAG := 0.1
const WALKER_AIR_ERROR := 0.6
## Seconds its tracking beam must hold a target in sight before the cannon
## fires, so a flier who sees the beam can break the line (`BotBrain.lock_time`).
const WALKER_LOCK := 1.0
## A core walker's chance of carrying upgrade data.
const WALKER_UPGRADE_CHANCE := 0.15
## Gun aim skill by risk zone (`BotBrain.skill`): the outer ring is where new
## players learn, the core is where the armies' veterans fight. The top of
## the outer band can match a mid kit, which is where the upset comes from.
const BOT_SKILL := [Vector2(0.36, 0.56), Vector2(0.42, 0.66), Vector2(0.48, 0.72)]
## Damage a second the Foundry's molten ground does to whoever stands in it.
const CORE_BURN := 2.0

## The warzone's own jobs (DESIGN.md "Challenge and balance data": goals at
## every level), from grab and go at the rim to holding the line, counted
## only from Ashfront (`contract_tag` "warzone"). Each daily is one outing
## at its ring's risk; the weeklies pay upgrade data for the long fights.
const CONTRACTS := {
	"war_rim": {"title": "Loot 3 caches in the outer ring", "stat": "cache:cache_outer", "goal": 3,
			"kind": "daily", "scrip": 120},
	"war_landmarks": {"title": "Loot 3 caches at the landmarks", "stat": "cache:cache", "goal": 3,
			"kind": "daily", "scrip": 180},
	"war_foundry": {"title": "Loot a cache in the burning Foundry", "stat": "cache:cache_core", "goal": 1,
			"kind": "daily", "scrip": 250},
	"war_bank": {"title": "Bank loot at a depot twice", "stat": "banks", "goal": 2, "kind": "daily",
			"scrip": 150},
	"war_hold": {"title": "Hold a strongpoint for 3 minutes", "stat": "hold_seconds", "goal": 180,
			"kind": "daily", "scrip": 220},
	"war_line": {"title": "Hold strongpoints for 15 minutes", "stat": "hold_seconds", "goal": 900,
			"kind": "weekly", "scrip": 850, "items": ["upgrade_data"]},
	"war_furnace": {"title": "Loot 5 caches in the Foundry", "stat": "cache:cache_core", "goal": 5,
			"kind": "weekly", "scrip": 900, "items": ["upgrade_data"]},
}

## Rival raiders' kits, a pick from each list. Base-level gear only (no Mk2
## rigs or helmets: those are crafted), so killing one pays like a player
## who came in geared, not like a warlord.
const RAIDER_PRIMARY := [
	{"id": "rifle_carbine", "weight": 35.0},
	{"id": "smg_stinger", "weight": 30.0},
	{"id": "shotgun_breacher", "weight": 15.0},
	{"id": "dmr_longshot", "weight": 10.0},
]
const RAIDER_SIDEARM := [
	{"id": "pistol_machine", "weight": 70.0},
	{"id": "pistol_hand_cannon", "weight": 30.0},
]
const RAIDER_MELEE := [
	{"id": "knife_gutter", "weight": 30.0},
	{"id": "axe_splitter", "weight": 30.0},
	{"id": "hammer_breaker", "weight": 15.0},
	{"id": "blade_arc", "weight": 15.0},
	{"id": "spear_lancer", "weight": 10.0},
]
## Raiders fly: most wear a jetpack, some thruster boots, a few wings.
const RAIDER_RIG := [
	{"id": "jetpack_mk1", "weight": 60.0},
	{"id": "boots_thruster", "weight": 30.0},
	{"id": "wings_glide", "weight": 10.0},
]
const RAIDER_FRAME := [
	{"id": "frame_runner", "weight": 45.0},
	{"id": "frame_trooper", "weight": 40.0},
	{"id": "frame_bulwark", "weight": 15.0},
]
const RAIDER_HELMET := [
	{"id": "helm_spotter", "weight": 25.0},
	{"id": "helm_seeker", "weight": 25.0},
	{"id": "helm_warden", "weight": 25.0},
	{"id": "helm_ember", "weight": 25.0},
]
## How likely a raider wears a helmet.
const RAIDER_HELMET_CHANCE := 0.6

const BOT_TABLE := [
	{"id": "scrap_metal", "weight": 45.0},
	{"id": "circuit_board", "weight": 25.0},
	{"id": "medkit", "weight": 18.0},
	{"id": "power_cell", "weight": 12.0},
]


func _init() -> void:
	# The Ashland (DESIGN.md "Planet kit"): its sky, ground and horizon.
	take_planet("ashland")
	id = "ashfront"
	# Deaths drop scrip, not gear (Caleb's call, DESIGN.md "Scrip piles").
	death_drops_scrip = true
	display_name = "Ashfront"
	description = "Open battlefield where two armies fight over the wrecks. Always-on PvP. The fallen drop scrip, not gear. Safe only at the gate outposts; the burning core pays best."
	# A garrison of four at each of the five landmarks, and patrols between them.
	# Thirty to an army: two garrisons of four, patrols, and a camp at the rim.
	bot_count = 60
	# A hot war draws in up to this many more.
	war_reinforcements = 60
	max_players = 32
	bots_contest_sites = true
	# Each army remembers who has been killing its soldiers, for one life.
	grudge_factions.assign(["legion", "tide"])
	# Battles follow the ground (DESIGN.md "The enemy AI pass", step 4).
	ground_styles = GROUND_STYLES
	line_share = 0.2
	siege_time = 40.0
	elite_kinds.assign(["exo", "walker"])
	depot_hold_time = 4.0
	# The PvP world is where blueprints and upgrade data come from.
	warlord_blueprint_chance = 0.5
	pod_blueprint_chance = 0.25
	warlord_upgrade_data = 2
	pod_upgrade_data = 1
	# The Warlord armor paint is earned here and nowhere else (Caleb's
	# call: special paints come from the hardest fights).
	warlord_paint = "paint_warlord"
	warlord_paint_chance = 0.08
	# Rival raiders, so the field never feels empty of people.
	raider_count = 4
	# An equal to the bench's mid kit (skill 0.5), not a cut above it. Flight
	# and a real kit already make the fight even; aiming like a veteran on
	# top of that won them most duels.
	raider_skill = Vector2(0.26, 0.44)
	# Ash storms cross the field now and then (DESIGN.md "Weather: ash
	# storms"): sight down to half in the thick of it, gone by 70 m, and the
	# armies push a site a storm covers.
	contract_tag = "warzone"
	# The scrap kit and a piece or two is fresh; a full mid kit is about
	# 2,000, crafted Mk2 and a heavy about 5,000.
	fresh_gear_value = 1500
	strong_gear_value = 4500
	weather_kind = "ash"
	weather_name = "Ash storm"
	weather_pushes = true
	weather_field = 276.0
	# The war's artillery (DESIGN.md "Shelling"): salvos walk across the
	# field near the fighting, marked in red before they land.
	shelling = 1.0


func faction_title(faction: String) -> String:
	return str(ARMIES[faction].name) if ARMIES.has(faction) else super(faction)


func contract_jobs() -> Dictionary:
	return CONTRACTS


func create_map() -> Node3D:
	var map := MapScript.new()
	map.planet = planet_type()
	return map


func prepare_map() -> void:
	var map: Node3D = MapScript.new()
	map.call("prepare_shared")
	map.free()


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
		"vehicle_rim":
			table = VEHICLE_RIM_TABLE
			count = 1
		"vehicle_site":
			table = VEHICLE_SITE_TABLE
			count = 1
	var out: Array[String] = []
	for i in count:
		out.append(ItemDB.roll(table, rng))
	return out


## A rival raider comes in geared like a player who has been here before:
## a gun, a sidearm, a blade, a rig and a frame, often a helmet, and a
## medkit or two.
func raider_kit(rng: RandomNumberGenerator) -> Array[String]:
	var kit: Array[String] = [ItemDB.roll(RAIDER_PRIMARY, rng), ItemDB.roll(RAIDER_SIDEARM, rng),
			ItemDB.roll(RAIDER_MELEE, rng), ItemDB.roll(RAIDER_RIG, rng), ItemDB.roll(RAIDER_FRAME, rng)]
	if rng.randf() < RAIDER_HELMET_CHANCE:
		kit.append(ItemDB.roll(RAIDER_HELMET, rng))
	for i in rng.randi_range(1, 2):
		kit.append("medkit")
	return kit


## Bots further in aim better. A warlord aims like the core's best, and a
## little past them: the fight is the weapon and the plates, not an aimbot.
func bot_skill_range(bot: Actor, warlord: bool) -> Vector2:
	if warlord:
		return Vector2(0.62, 0.85)
	return BOT_SKILL[clampi(int(bot.get_meta("zone", 1)), 0, 2)]


## How each kind of ground fights (`ground_at`, DESIGN.md "The enemy AI
## pass", step 4). The rim is quiet patrols that chase little; the open
## field is where fireteams meet, as they are; a trench line ("line") and a
## siege ring hold their ground and trade fire from further off; a
## landmark's defenders keep to it; the Works is close quarters, nearer and
## quicker to react; the Foundry, fought over by elites in a hot war,
## hunts harder.
const GROUND_STYLES := {
	"rim": {"hunters": -1, "leash": 22.0},
	"field": {},
	"line": {"range": 1.4, "leash": 8.0, "hunters": -2},
	"front": {"range": 1.2, "leash": 16.0},
	"siege": {"range": 1.3, "leash": 12.0},
	"landmark": {"leash": 24.0},
	"works": {"range": 0.55, "leash": 26.0, "notice": 0.85},
	"foundry": {"hunters": 1},
}
## How near a trench line counts as the front.
const FRONT_REACH := 9.0


## The kind of ground at a point: the Works, the Foundry, a landmark, the
## front's trenches, the rim or the open field.
func ground_at(pos: Vector3) -> String:
	var at := Vector2(pos.x, pos.z)
	if absf(at.x) < MapScript.WORKS_REACH + 2.0 and at.y > MapScript.WORKS_TO - 2.0 \
			and at.y < MapScript.WORKS_FROM + 2.0:
		return "works"
	if at.length() <= MapScript.CORE_RADIUS:
		return "foundry"
	for site: Dictionary in MapScript.SITES:
		if site["kind"] != "foundry" and at.distance_to(site["at"]) <= float(site["radius"]) * 1.4:
			return "landmark"
	for index: int in MapScript.FRONT_LINES:
		var line: Array = MapScript.TRENCHES[index]
		for i in line.size() - 1:
			if at.distance_to(Geometry2D.get_closest_point_to_segment(at, line[i], line[i + 1])) < FRONT_REACH:
				return "front"
	return "rim" if zone_at(pos) == 0 else "field"


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
## What kind it is ("soldier", "heavy", "exo", "walker") goes in its meta
## "kind"; every machine rolls the same from the seed.
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
	var doctrine: Dictionary = DOCTRINE[dress]
	var tier := clampi(int(bot.get_meta("zone", 1)), 0, 2)
	var mix := rng.randf()
	var kind := "soldier"
	if mix < WALKER_CHANCE[tier]:
		kind = "walker"
	elif mix < WALKER_CHANCE[tier] + EXO_CHANCE[tier] * float(doctrine["exo"]):
		kind = "exo"
	elif rng.randf() < HEAVY_CHANCE[tier] * float(doctrine["heavy"]):
		kind = "heavy"
	elif rng.randf() < float(doctrine["special_chance"][tier]):
		kind = str(doctrine["special"])
	_take_doctrine(bot, doctrine, kind)
	var def: Dictionary = army[kind]
	bot.set_meta("kind", kind)
	bot.display_name = def["name"]
	bot.set_meta("look", def["look"])
	bot.body_color = def["color"]
	if bot.body_mesh:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = bot.body_color
		bot.body_mesh.material_override = mat
	for id in roll_loot("bot", rng):
		bot.inventory.add_item(id)
	match kind:
		"heavy":
			# A heavy charges with a blade. Its swings are slow and telegraphed,
			# which makes it the enemy to practice parrying on.
			bot.walk_speed = 5.2
			bot.sprint_speed = 9.0
			_set_health(bot, HEAVY_HEALTH[tier], 0.0)
			bot.set_meta("melee_tempo", 0.85)
			var blade := MeleeWeapon.new()
			blade.display_name = def["weapon"]
			blade.light_damage = HEAVY_DAMAGE[tier]
			blade.light_windup = 0.5
			blade.heavy_windup = HEAVY_HEAVY_WINDUP
			blade.heavy_damage = HEAVY_DAMAGE[tier] * HEAVY_HEAVY_MULT
			blade.light_stamina = 0.0
			blade.reach = 2.6
			bot.equip_weapon(blade)
		"marksman":
			bot.walk_speed = 4.3
			bot.sprint_speed = 6.8
			_set_health(bot, SOLDIER_HEALTH[tier], 0.0)
			bot.set_meta("sight", MARKSMAN_SIGHT)
			bot.set_meta("reach", MARKSMAN_REACH)
			bot.set_meta("range", MARKSMAN_RANGE)
			bot.set_meta("burst", MARKSMAN_BURST)
			# Its short burst is one aimed round a pull.
			bot.equip_weapon(_army_gun(def["weapon"], MARKSMAN_DAMAGE[tier], MARKSMAN_SPREAD[tier], MARKSMAN_INTERVAL))
		"runner":
			# First in and first down: a quick knife, little health.
			bot.walk_speed = RUNNER_WALK
			bot.sprint_speed = RUNNER_SPRINT
			_set_health(bot, RUNNER_HEALTH[tier], 0.0)
			bot.set_meta("melee_tempo", 1.1)
			# It closes the last few metres in a dash-strike, at the rim too.
			bot.set_meta("dash", RUNNER_DASH)
			var knife := MeleeWeapon.new()
			knife.display_name = def["weapon"]
			knife.light_damage = RUNNER_DAMAGE[tier]
			knife.light_windup = RUNNER_WINDUP
			knife.heavy_damage = RUNNER_DAMAGE[tier] * 1.6
			knife.light_stamina = 0.0
			knife.reach = 2.2
			bot.equip_weapon(knife)
		"exo":
			# A soldier in a mechanical exoskeleton: armor that soaks a
			# carbine, a heavier step, and a support rifle. The suit is drawn
			# by the skin ("exo"); the frame it may carry is loot, not worn.
			bot.walk_speed = 4.0
			bot.sprint_speed = 6.2
			_set_health(bot, EXO_HEALTH[tier], EXO_ARMOR[tier])
			if rng.randf() < EXO_FRAME_CHANCE:
				bot.inventory.add_item(ItemDB.roll(EXO_FRAMES, rng))
			bot.equip_weapon(_army_gun(def["weapon"], EXO_DAMAGE[tier], EXO_SPREAD[tier], EXO_INTERVAL[tier]))
		"walker":
			# A machine 3 m tall: the capsule, hit tests and eyes (its cannon) go with it.
			bot.set_stand_height(WALKER_HEIGHT, 0.25)
			bot.walk_speed = WALKER_WALK
			bot.sprint_speed = WALKER_SPRINT
			_set_health(bot, WALKER_HEALTH[tier], WALKER_ARMOR[tier])
			bot.rear_damage_mult = WALKER_REAR_MULT
			bot.set_meta("aim_turn", WALKER_TURN)
			bot.set_meta("track_lag", WALKER_TRACK_LAG)
			bot.set_meta("air_error", WALKER_AIR_ERROR)
			bot.set_meta("lock_time", WALKER_LOCK)
			# What a walker runs on.
			for i in rng.randi_range(1, 2):
				bot.inventory.add_item("power_cell")
			bot.inventory.add_item("alloy_ingot")
			if tier == 2 and rng.randf() < WALKER_UPGRADE_CHANCE:
				bot.inventory.add_item("upgrade_data")
			var cannon := _army_gun(def["weapon"], WALKER_DAMAGE[tier], WALKER_SPREAD[tier], WALKER_INTERVAL[tier])
			cannon.mag_size = 12
			cannon.ammo_in_mag = 12
			bot.equip_weapon(cannon)
		_:
			bot.walk_speed = 4.5
			bot.sprint_speed = 7.0
			_set_health(bot, SOLDIER_HEALTH[tier], 0.0)
			# Harder-hitting than a carbine and looser, and they break when the
			# soldier dies. A burst through a mid kit's plates can end the fight.
			bot.equip_weapon(_army_gun(def["weapon"], GUN_DAMAGE[tier], GUN_SPREAD[tier], GUN_INTERVAL[tier]))


## Sets the army's way of fighting on one of its bots. Riflemen keep the
## army's distance; the Tide's people (not its exos or walkers) pincer, hunt
## and break.
func _take_doctrine(bot: Actor, doctrine: Dictionary, kind: String) -> void:
	if kind == "soldier":
		bot.set_meta("range", doctrine["range"])
		bot.set_meta("reach", doctrine["reach"])
		bot.set_meta("sight", doctrine["sight"])
	if kind in ["soldier", "heavy", "runner"]:
		for key in ["flankers", "hunters", "breaks_at"]:
			if doctrine.has(key):
				bot.set_meta(key, doctrine[key])


## Dresses `actor` as one of an army's riflemen, the way `equip_bot` does,
## and nothing more: the scenery army (`battle.gd`) takes its far copies of
## the soldiers from one of these. View only, never a bot.
func dress_extra(actor: Actor, faction: String) -> void:
	var def: Dictionary = ARMIES[faction if ARMIES.has(faction) else "legion"]["soldier"]
	actor.faction = faction
	actor.set_meta("kind", "soldier")
	actor.set_meta("look", def["look"])
	actor.body_color = def["color"]
	actor.equip_weapon(_army_gun(def["weapon"], GUN_DAMAGE[0], GUN_SPREAD[0], GUN_INTERVAL[0]))


## One walker at each landmark: a new one is turned away while another walker
## is alive nearest the same landmark, and no warlord is a walker. Checked
## on the authority only (the `Raid` rolls a turned-away bot again).
func bot_allowed(bot: Actor, raid: Node) -> bool:
	if bot.get_meta("kind", "") != "walker":
		return true
	var r := raid as Raid
	if r == null:
		return true
	if r.warlords.has(bot):
		return false
	var home := _nearest_landmark(r, bot.global_position)
	if home < 0:
		return true
	for other in r.bots:
		if other == bot or not is_instance_valid(other) or other.is_dead:
			continue
		if other.get_meta("kind", "") == "walker" and _nearest_landmark(r, other.global_position) == home:
			return false
	return true


func _nearest_landmark(raid: Raid, at: Vector3) -> int:
	var best := -1
	var best_distance := INF
	for point in raid.strongpoints:
		var d := Vector2(point.global_position.x - at.x, point.global_position.z - at.z).length()
		if d < best_distance:
			best_distance = d
			best = point.index
	return best


func _set_health(bot: Actor, health: float, armor: float) -> void:
	bot.health.max_health = health
	bot.health.health = health
	bot.health.set_armor(armor)


## An army gun: rounds that break when the bot dies, plenty of them.
func _army_gun(gun_name: String, damage: float, spread: float, interval: float) -> Gun:
	var gun := Gun.new()
	gun.display_name = gun_name
	gun.damage = damage
	gun.spread_deg = spread
	gun.fire_interval = interval
	gun.reserve_ammo = 600
	# Soldiers aim at the chest; a stray round on the head is no bonus.
	gun.headshot_mult = 1.0
	return gun


## A warlord is not a soldier with more health. The same worn rifle could not
## kill a mid kit before the carbine chewed through the extra plates, so the
## boss carries a kept gun (or a cleaver that lands) and real armor. Health is
## a fixed pool: a heavy's and a rifleman's warlord are the same fight's
## length, and which weapon they rolled still decides how it feels.
func make_warlord(bot: Actor) -> void:
	bot.display_name = "Warlord"
	# A warlord fights for itself, not by its army's doctrine, and an army's
	# own kind keeps only its weapon's sort (`DOCTRINE`, `_take_doctrine`).
	for key in ["range", "reach", "sight", "burst", "flankers", "hunters", "breaks_at", "dash"]:
		bot.remove_meta(key)
	if str(bot.get_meta("kind", "")) in ["marksman", "runner"]:
		bot.walk_speed = 4.5
		bot.sprint_speed = 7.0
	bot.health.max_health = 280.0
	bot.health.health = 280.0
	bot.health.set_armor(48.0)
	var gun := bot.get_active_weapon() as Gun
	if gun:
		gun.damage = 27.0
		gun.spread_deg = 0.25
		gun.fire_interval = 0.12
	var blade := bot.get_active_weapon() as MeleeWeapon
	if blade:
		blade.light_damage = 44.0
		blade.reach = 2.8
