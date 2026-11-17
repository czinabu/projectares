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

## The two armies that fight over the field, and each other. Most of each
## army are soldiers with rifles, and one in a few of those is a heavy with
## a blade. Beside them march exo troopers (a person in powered armor) and,
## further in, the rare Kiln Walker (DESIGN.md "Heavy units").
const ARMIES := {
	"legion": {
		"name": "the Legion",
		"soldier": {"name": "Legionnaire", "look": "legionary", "color": Color(0.3, 0.45, 0.7), "weapon": "Service Rifle"},
		"heavy": {"name": "Legion Vanguard", "look": "sentinel", "color": Color(0.2, 0.3, 0.55), "weapon": "Breaching Blade"},
		"exo": {"name": "Legion Exo Trooper", "look": "exo", "color": Color(0.3, 0.6, 1.0), "weapon": "Support Rifle"},
		"walker": {"name": "Kiln Walker", "look": "walker", "color": Color(0.3, 0.6, 1.0), "weapon": "Kiln Cannon"},
	},
	"tide": {
		"name": "the Tide",
		"soldier": {"name": "Tide Raider", "look": "tide", "color": Color(0.85, 0.3, 0.2), "weapon": "Worn Rifle"},
		"heavy": {"name": "Tide Brute", "look": "heavy", "color": Color(0.5, 0.1, 0.12), "weapon": "Rusted Cleaver"},
		"exo": {"name": "Tide Exo Trooper", "look": "exo", "color": Color(1.0, 0.35, 0.15), "weapon": "Support Rifle"},
		"walker": {"name": "Kiln Walker", "look": "walker", "color": Color(1.0, 0.35, 0.15), "weapon": "Kiln Cannon"},
	},
}
## The spawn mix by the risk zone a bot arrived in (outer ring, middle,
## core): the share that are exo troopers and walkers. The rest are the
## armies' people, soldiers and blade heavies.
const EXO_CHANCE := [0.09, 0.18, 0.22]
const WALKER_CHANCE := [0.0, 0.04, 0.08]
## How likely one of the armies' people is a heavy, and its health, by the
## risk zone it arrived in: outer ring, middle, core.
const HEAVY_CHANCE := [0.1, 0.25, 0.4]
const SOLDIER_HEALTH := [125.0, 135.0, 140.0]
const HEAVY_HEALTH := [250.0, 260.0, 270.0]
## Army rifles, one round in every zone. Harder than a carbine so a hit gets
## through a mid kit's plates, and looser and a little slower. Toward the core
## the soldier changes (more health, higher aim skill), not the cartridge.
const GUN_DAMAGE := [28.0, 28.0, 28.0]
const GUN_SPREAD := [1.32, 1.28, 1.4]
const GUN_INTERVAL := [0.12, 0.12, 0.12]
## A heavy's swing. Slow and telegraphed (the parry drill). Two hits leave a
## mid kit nearly dead, and a third ends it, so missing the parry is the loss.
const HEAVY_DAMAGE := [48.0, 48.0, 48.0]
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
	# The PvP world is where blueprints and upgrade data come from.
	warlord_blueprint_chance = 0.5
	pod_blueprint_chance = 0.25
	warlord_upgrade_data = 2
	pod_upgrade_data = 1
	# Rival raiders, so the field never feels empty of people.
	raider_count = 4
	# An equal to the bench's mid kit (skill 0.5), not a cut above it. Flight
	# and a real kit already make the fight even; aiming like a veteran on
	# top of that won them most duels.
	raider_skill = Vector2(0.26, 0.44)


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
	var tier := clampi(int(bot.get_meta("zone", 1)), 0, 2)
	var mix := rng.randf()
	var kind := "soldier"
	if mix < WALKER_CHANCE[tier]:
		kind = "walker"
	elif mix < WALKER_CHANCE[tier] + EXO_CHANCE[tier]:
		kind = "exo"
	elif rng.randf() < HEAVY_CHANCE[tier]:
		kind = "heavy"
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
			blade.light_stamina = 0.0
			blade.reach = 2.6
			bot.equip_weapon(blade)
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
	return gun


## A warlord is not a soldier with more health. The same worn rifle could not
## kill a mid kit before the carbine chewed through the extra plates, so the
## boss carries a kept gun (or a cleaver that lands) and real armor. Health is
## a fixed pool: a heavy's and a rifleman's warlord are the same fight's
## length, and which weapon they rolled still decides how it feels.
func make_warlord(bot: Actor) -> void:
	bot.display_name = "Warlord"
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
