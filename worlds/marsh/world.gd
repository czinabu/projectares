extends WorldDef
## The Spore Marsh: a drowned basin of moss, black water and fungus forests
## (DESIGN.md "More worlds", "Spore Marsh"). A co-op PvE world with no PvP
## (player melee lives in the Pit, Caleb's call): the enemy is the marsh's
## wildlife, and blades are the natural choice against it. Gunshots wake the
## marsh and guns foul under sustained fire; melee kills stay silent.
## Gentle death: you keep what you wear and drop the pack. It is the main
## source of artifacts (Caleb's call), and pays trophies, melee blueprints
## and marsh cosmetics.

const MapScript := preload("res://worlds/marsh/map.gd")
const Rootway := preload("res://worlds/marsh/rootway.gd")

## How much faster than still air a shot carries here (`WorldDef.shot_carry`):
## the marsh is quiet, and a gunshot wakes everything in earshot.
const SHOT_CARRY := 1.6
## Guns foul in the damp (`WorldDef.gun_fouling`, `Gun.fouling`): spread
## grows under sustained fire and a long burst can jam until a reload.
const FOULING := 1.0
## Rain storms (DESIGN.md "The Spore Marsh", Caleb's call: cover and
## quiet): in the thick of one sight drops to `RAIN_SIGHT`, the rain drowns
## shots and footsteps to `RAIN_CARRY` of their reach, and it washes the
## spores out of the air, so guns foul at `RAIN_FOULING` of the usual
## rate. Light gusts. Down a Rootway is out of it (`sheltered_at`).
const RAIN_SIGHT := 0.6
const RAIN_CARRY := 0.4
const RAIN_FOULING := 0.4
const RAIN_GUST := 2.0

## Stalkers (DESIGN.md "Spore Marsh"): fast, fragile pack hunters that
## circle and feint before they strike (`feint_chance`, over a bot's ring).
const STALKER_HEALTH := 70.0
const STALKER_FEINT := 0.45
## Shellbacks: slow, heavily plated grazers with a soft rear (hits from
## behind do `SHELLBACK_REAR` times), a heavy bash and a slow turn.
const SHELLBACK_HEALTH := 240.0
const SHELLBACK_ARMOR := 80.0
const SHELLBACK_REAR := 3.0
const SHELLBACK_HEIGHT := 1.6
## Bloaters: slow, soft sacs of spores. Killed, one bursts into a cloud
## (`WorldDef.death_burst`) that hurts everyone in it, so a blade kill is a
## step back after the cut.
const BLOATER_HEALTH := 50.0
const BLOATER_HEIGHT := 2.1
const BLOATER_CLOUD := {"radius": 4.5, "damage": 9.0, "seconds": 8.0, "kind": "spores"}
## Lurkers (DESIGN.md "Spore Marsh"): ambushers that lie under the black
## water at a pool's deepest spot ("lies_low"), see only close by and all
## round, lunge and bite hard, and never leave their pool ("leash").
const LURKER_HEALTH := 130.0
const LURKER_HEIGHT := 1.4
const LURKER_SIGHT := 8.0
const LURKER_LEASH := 5.0
## Brood keepers guard the hives, one in each forest but the Matriarch's:
## big, armored and slow to turn. While one stands its hive is sealed and
## spills broodlings at anyone near it (the guard marker's "brood").
const KEEPER_HEALTH := 520.0
const KEEPER_ARMOR := 40.0
const KEEPER_HEIGHT := 2.4
## Broodlings: little stalkers, quick and weak, that come in numbers.
const BROODLING_HEALTH := 22.0
const BROODLING_HEIGHT := 0.9
## The brood's kin: keepers and broodlings are one kind, so neither hurts
## the other, though they are told apart by faction.
const KIN := {"keeper": "brood", "broodling": "brood"}
## The Rootmother (DESIGN.md "The Spore Marsh (the Rootways)"), keeper of
## the Westwood Rootway: the brood's mother, a keeper grown huge, slow and
## heavily armored, with the egg sacs on her back her weak spot. While she
## is above half health broodlings come out of the root sockets in her
## chamber's wall; below it the floor's spore vents open (the Raid's keeper
## machinery, `WorldDef.keeper_*`). Made for one player, tougher with
## company like the Matriarch. Her hooks keep a long windup to parry.
const ROOTMOTHER := "rootmother"
const ROOTMOTHER_HEIGHT := 3.4
const ROOTMOTHER_HEALTH := 1200.0
const ROOTMOTHER_ARMOR := 45.0
const ROOTMOTHER_REAR := 2.0
## The Shellback Elder (Caleb's pick), keeper of the Gillwood Rootway: the
## oldest grazer, its dome grown into a battering ram. It charges: a
## dash-strike that runs its whole length (`MeleeWeapon.dash_through`) on a
## long windup, so a player who steps aside lets it run on, and one that
## rams a snag in its chamber is stuck there `Rootway.SNAG_STUN` seconds,
## its soft rear open. Below half health it charges more often and the
## floor's spore vents open. It calls nothing out of the walls.
const ELDER := "elder"
const ELDER_HEIGHT := 3.2
const ELDER_HEALTH := 1600.0
const ELDER_ARMOR := 120.0
const ELDER_REAR := 2.5
## Its charge: how far it runs, the windup it runs through, what it does to
## whoever it catches, and the least time between charges, by phase.
const ELDER_CHARGE := 16.0
const ELDER_CHARGE_WINDUP := 1.1
const ELDER_CHARGE_DAMAGE := 48.0
const ELDER_CHARGE_EVERY := [6.0, 3.5]
## The Drowned Lurker (Caleb's pick), keeper of the Rotwood Rootway: a
## lurker grown huge in the deep, in a flooded chamber. It dives (the
## Raid's keeper machinery with "boss_pool" markers, `WorldDef.keeper_dive_*`):
## up and fighting a while, then under the black water where nothing hurts
## it, then up again out of the pool nearest one of the players, its pool
## stirring as it rises, and straight into a lunge. Below half health it
## stays up for less and the floor's spore vents open. It sees the whole
## chamber and follows anyone in it.
const DROWNED := "drowned"
const DROWNED_HEIGHT := 2.6
const DROWNED_HEALTH := 1400.0
const DROWNED_ARMOR := 70.0
const DROWNED_SIGHT := 30.0
## A Rootway keeper's vault (Caleb's call on the Engine's: a share for
## everyone who fought it): the marsh's goods, upgrade data, often one of
## its blueprints and now and then an artifact or the Spore paint.
const ROOT_VAULT_ITEMS := Vector2i(3, 4)
const ROOT_VAULT_DATA := Vector2i(1, 2)
const ROOT_VAULT_BLUEPRINT := 0.3
const ROOT_VAULT_ARTIFACT := 0.15
const ROOT_VAULT_PAINT := 0.05
## The Grey Matriarch, the core's boss: the stalker pack's mother, twice a
## person's height, quick for her size, feinting most of the time. Made for
## one player; each other player near her makes her tougher.
const MATRIARCH_HEIGHT := 2.9
const MATRIARCH_HEALTH := 520.0
const MATRIARCH_ARMOR := 30.0
const MATRIARCH_PARTY := 0.6
## The main source of artifacts (Caleb's call): the Matriarch carries one
## more often than not, a world event's warlord or pod now and then, and the
## forests' hollows and caps rarely.
const MATRIARCH_ARTIFACT := 0.6
const POD_ARTIFACT := 0.15
const HOLLOW_ARTIFACT := 0.05
const CAP_ARTIFACT := 0.03
const DEN_ARTIFACT := 0.12
## Her trophy, for the trophy shelf: never traded or sold.
const TROPHY := "trophy_matriarch_fang"
const TROPHY_CHANCE := 0.35
## The marsh's earned paint (DESIGN.md "Armor paints"): Relic loot from the
## Matriarch, never sold.
const PAINT := "paint_spore"
const PAINT_CHANCE := 0.12
## The marsh's own blueprints: melee options, never a higher Mk.
const BLUEPRINTS := ["bp_blade_hook", "bp_spear_reed"]
const WARLORD_BLUEPRINT := 0.15

## The marsh's own contracts, counted only here. Every one can be done alone.
const CONTRACTS := {
	"marsh_hollows": {"title": "Loot 2 forest hollows", "stat": "cache:hollow", "goal": 2, "kind": "daily",
			"scrip": 200},
	"marsh_caps": {"title": "Loot 2 caches up on the caps", "stat": "cache:cap", "goal": 2, "kind": "daily",
			"scrip": 190},
	"marsh_stalkers": {"title": "Bring down 8 stalkers", "stat": "kills:stalker", "goal": 8, "kind": "daily",
			"scrip": 160},
	"marsh_shellbacks": {"title": "Bring down 3 shellbacks", "stat": "kills:shellback", "goal": 3, "kind": "daily",
			"scrip": 170},
	"marsh_sacs": {"title": "Bring home 3 Spore Sacs", "stat": "item:spore_sac", "goal": 3,
			"kind": "daily", "scrip": 170},
	"marsh_keepers": {"title": "Bring down 2 brood keepers", "stat": "kills:keeper", "goal": 2, "kind": "daily",
			"scrip": 220},
	"marsh_lurkers": {"title": "Bring down 3 lurkers", "stat": "kills:lurker", "goal": 3, "kind": "daily",
			"scrip": 180},
	"marsh_matriarch": {"title": "Bring down the Grey Matriarch twice", "stat": "boss:matriarch", "goal": 2,
			"kind": "weekly", "scrip": 900, "items": ["upgrade_data"], "reward_tag": "blueprint"},
	"marsh_glowcaps": {"title": "Bring home 3 Glowcaps", "stat": "item:glowcap", "goal": 3,
			"kind": "weekly", "scrip": 850, "items": ["upgrade_data"], "reward_tag": "blueprint"},
}

## A gentle world's gear is the basic tier; rare gear stays in the war. What
## the marsh pays instead: its materials, its blueprints, artifacts.
const CACHE_TABLE := [
	{"id": "scrap_metal", "weight": 28.0},
	{"id": "chitin_plate", "weight": 20.0},
	{"id": "spore_sac", "weight": 14.0},
	{"id": "medkit", "weight": 14.0},
	{"id": "power_cell", "weight": 10.0},
	{"id": "circuit_board", "weight": 10.0},
	{"id": "knife_gutter", "weight": 3.0},
	{"id": "axe_splitter", "weight": 2.5},
	{"id": "hammer_breaker", "weight": 2.0},
	{"id": "smg_stinger", "weight": 2.0},
	{"id": "frame_runner", "weight": 2.5},
	{"id": "boots_thruster", "weight": 2.0},
]

## The survey stations: what the expeditions left behind.
const STATION_TABLE := [
	{"id": "circuit_board", "weight": 24.0},
	{"id": "power_cell", "weight": 22.0},
	{"id": "medkit", "weight": 18.0},
	{"id": "alloy_ingot", "weight": 10.0},
	{"id": "frame_trooper", "weight": 6.0},
	{"id": "chip_barrier", "weight": 5.0},
	{"id": "optic_reflex", "weight": 4.0},
	{"id": "grip_vertical", "weight": 3.0},
	{"id": "mag_extended", "weight": 3.0},
	{"id": "helm_spotter", "weight": 3.0},
	{"id": "helm_seeker", "weight": 3.0},
]

## The hollows at each forest's heart and the caps over them: the marsh's
## own goods, its blueprints and a trickle of upgrade data.
const HOLLOW_TABLE := [
	{"id": "glowcap", "weight": 22.0},
	{"id": "spore_sac", "weight": 20.0},
	{"id": "chitin_plate", "weight": 18.0},
	{"id": "alloy_ingot", "weight": 12.0},
	{"id": "medkit", "weight": 10.0},
	{"id": "spear_lancer", "weight": 3.0},
	{"id": "blade_arc", "weight": 3.0},
	{"id": "bp_blade_hook", "weight": 2.0},
	{"id": "bp_spear_reed", "weight": 2.0},
	{"id": "upgrade_data", "weight": 2.0},
]

const STALKER_DROPS := [
	{"id": "stalker_fang", "weight": 60.0},
	{"id": "scrap_metal", "weight": 25.0},
	{"id": "medkit", "weight": 15.0},
]
const SHELLBACK_DROPS := [
	{"id": "chitin_plate", "weight": 70.0},
	{"id": "stalker_fang", "weight": 15.0},
	{"id": "medkit", "weight": 15.0},
]
## A hive, once its keeper falls: the brood's store of the marsh's goods,
## and the best of its blueprints and artifacts after the Matriarch's.
const HIVE_TABLE := [
	{"id": "glowcap", "weight": 20.0},
	{"id": "spore_sac", "weight": 20.0},
	{"id": "chitin_plate", "weight": 16.0},
	{"id": "stalker_fang", "weight": 14.0},
	{"id": "alloy_ingot", "weight": 10.0},
	{"id": "bp_blade_hook", "weight": 3.0},
	{"id": "bp_spear_reed", "weight": 3.0},
	{"id": "upgrade_data", "weight": 3.0},
]
const HIVE_ARTIFACT := 0.08
const LURKER_DROPS := [
	{"id": "chitin_plate", "weight": 40.0},
	{"id": "stalker_fang", "weight": 35.0},
	{"id": "medkit", "weight": 25.0},
]
const KEEPER_DROPS := [
	{"id": "chitin_plate", "weight": 40.0},
	{"id": "spore_sac", "weight": 30.0},
	{"id": "glowcap", "weight": 30.0},
]
const BLOATER_DROPS := [
	{"id": "spore_sac", "weight": 80.0},
	{"id": "medkit", "weight": 20.0},
]


## A forest's pack or a station's beasts stand when a player comes this
## near (metres). The basin is small and its forests close, so it is short.
const POCKET_WAKE := 90.0
## The most enemies the marsh holds at once (`WorldDef.enemy_cap`).
const ENEMY_CAP := 12


func _init() -> void:
	# The Spore Marsh planet (DESIGN.md "Planet kit"): its sky, moss and
	# black water, mist and spores. Its rules are a start; the shot's carry
	# below is the marsh's own.
	take_planet("marsh")
	id = "marsh"
	display_name = "Spore Marsh"
	description = "A drowned basin of black water and fungus forests. The wildlife hunts you and each other. Co-op, no PvP, gunshots wake the marsh, you keep your equipped gear when you die."
	keep_gear_on_death = true
	players_allied = true
	war_scale = 0.0
	# Power weapons belong to the war worlds.
	power_weapon_rate = 0.0
	# The main source of artifacts.
	warlord_artifact_chance = MATRIARCH_ARTIFACT
	pod_artifact_chance = POD_ARTIFACT
	warlord_paint = PAINT
	warlord_paint_chance = PAINT_CHANCE
	# The slow route to the war's blueprints, as in every gentle world.
	warlord_blueprint_chance = WARLORD_BLUEPRINT
	warlord_upgrade_data = 1
	boss_party_scale = MATRIARCH_PARTY
	# The wildlife keeps to its ground: packs in the forests, beasts at the
	# stations and hummocks, lurkers in the pools, as encounter pockets
	# (Caleb's call, DESIGN.md "Enemy layout") that stand while a player is
	# near, at most `enemy_cap` at once.
	bot_count = 0
	pocket_wake = POCKET_WAKE
	enemy_cap = ENEMY_CAP
	depot_hold_time = 6.0
	shot_carry = SHOT_CARRY
	gun_fouling = FOULING
	weather_kind = "rain"
	weather_name = "Rain storm"
	weather_radius = 130.0
	weather_speed = 2.5
	weather_gap = Vector2(300.0, 600.0)
	weather_first = Vector2(120.0, 300.0)
	weather_sight = RAIN_SIGHT
	weather_carry = RAIN_CARRY
	weather_fouling = RAIN_FOULING
	weather_gust = RAIN_GUST
	weather_field = 230.0
	contract_tag = "marsh"


func register_items() -> void:
	ItemDB.register(TROPHY, "Matriarch's Fang", ItemDB.Rarity.EPIC, 0, ["trophy"], {},
			"A fang from the Grey Matriarch, longer than a knife. Earned, never sold.")


func create_map() -> Node3D:
	var map := MapScript.new()
	map.planet = planet_type()
	return map


func prepare_map() -> void:
	var map: Node3D = MapScript.new()
	map.call("prepare_shared")
	map.free()


## The zones run from the southern shore (outer) through the drowned
## middle to the Matriarch's forest in the north (core).
func zone_at(pos: Vector3) -> int:
	if pos.z <= MapScript.CORE_FROM_Z:
		return 2
	if pos.z <= MapScript.MIDDLE_FROM_Z:
		return 1
	return 0


func zone_name(tier: int) -> String:
	return ["The shore", "The drowned middle", "The Matriarch's forest"][tier] if tier >= 0 and tier <= 2 else ""


func starter_loadout() -> Array[String]:
	return ["rifle_scrap", "blade_scrap", "pistol_service", "jetpack_mk1", "plate_light", "visor_scav",
			"field_dressing"]


func roll_loot(source: String, rng: RandomNumberGenerator) -> Array[String]:
	var table := CACHE_TABLE
	var count := rng.randi_range(2, 3)
	var relic_chance := 0.0
	match source:
		"station":
			table = STATION_TABLE
		"hollow":
			table = HOLLOW_TABLE
			relic_chance = HOLLOW_ARTIFACT
		"cap":
			table = HOLLOW_TABLE
			relic_chance = CAP_ARTIFACT
		"den":
			table = HOLLOW_TABLE
			count = rng.randi_range(3, 4)
			relic_chance = DEN_ARTIFACT
		"rootway":
			table = HOLLOW_TABLE
			count = 3
			relic_chance = HOLLOW_ARTIFACT
		"hive":
			table = HIVE_TABLE
			count = rng.randi_range(3, 4)
			relic_chance = HIVE_ARTIFACT
		"stalker":
			table = STALKER_DROPS
			count = rng.randi_range(1, 2)
		"lurker":
			table = LURKER_DROPS
			count = rng.randi_range(1, 2)
		"keeper":
			table = KEEPER_DROPS
			count = rng.randi_range(2, 3)
		"shellback":
			table = SHELLBACK_DROPS
			count = rng.randi_range(1, 2)
		"bloater", "bot":
			table = BLOATER_DROPS
			count = 1
	var out: Array[String] = []
	for i in count:
		out.append(ItemDB.roll(table, rng))
	var relic := roll_artifact(rng, relic_chance)
	if relic != "":
		out.append(relic)
	return out


func contract_jobs() -> Dictionary:
	return CONTRACTS


## A PvE world: nobody hurts their own kind, and every player is one kind.
## The wildlife hunts across kinds, so a stalker pack on a shellback is a
## chance to slip past.
## Under the forests' caps the mist shuts sight in to about where the
## view's close air hides a body (Caleb's call: close quarters); out on the
## water the air is clear enough for a bot's own sight.
const FOREST_SIGHT := 38.0
func sight_at(pos: Vector3) -> float:
	if Rootway.inside(pos):
		return FOREST_SIGHT
	var close := MapScript.close_at(pos.x, pos.z)
	if close <= 0.0:
		return INF
	return lerpf(FOREST_SIGHT * 4.0, FOREST_SIGHT, close)


## Down a Rootway is out of the weather.
func sheltered_at(pos: Vector3) -> bool:
	return Rootway.inside(pos)


func can_damage(attacker: Node, target: Node, _info: DamageInfo) -> bool:
	if attacker == target:
		return false
	var a := attacker as Actor
	var t := target as Actor
	if a and t and kin_of(a.faction) == kin_of(t.faction):
		return false
	return true


## The kind a faction belongs to: the brood's keepers and broodlings are one.
static func kin_of(faction: String) -> String:
	return str(KIN.get(faction, faction))


## A bot from a marker that names its kind is one of those; any other is
## picked by chance, stalkers most often.
func equip_bot(bot: Actor, rng: RandomNumberGenerator) -> void:
	var kind := bot.faction
	if not kind in ["stalker", "shellback", "bloater", "lurker", "keeper", "broodling"]:
		var roll := rng.randf()
		kind = "stalker" if roll < 0.5 else ("shellback" if roll < 0.75 else "bloater")
	match kind:
		"shellback":
			_make_shellback(bot, rng)
		"bloater":
			_make_bloater(bot, rng)
		"lurker":
			_make_lurker(bot, rng)
		"keeper":
			_make_keeper(bot, rng)
		"broodling":
			_make_broodling(bot)
		_:
			_make_stalker(bot, rng)


## Fast, fragile pack hunters: they circle just out of reach, feint and dart
## in with hooked claws.
func _make_stalker(bot: Actor, rng: RandomNumberGenerator) -> void:
	bot.faction = "stalker"
	bot.display_name = "Marsh Stalker"
	bot.set_meta("look", "marsh_stalker")
	bot.set_meta("feint_chance", STALKER_FEINT)
	bot.body_color = Color(0.28, 0.34, 0.3)
	bot.walk_speed = 6.2
	bot.sprint_speed = 9.5
	bot.health.max_health = STALKER_HEALTH
	bot.health.health = STALKER_HEALTH
	for item in roll_loot("stalker", rng):
		bot.inventory.add_item(item)
	var claws := MeleeWeapon.new()
	claws.display_name = "Hooked Claws"
	claws.light_damage = 13.0
	claws.light_windup = 0.3
	claws.light_stamina = 0.0
	claws.reach = 2.3
	bot.equip_weapon(claws)


## Slow, armored grazers: a heavy bash from the front, a soft rear behind.
func _make_shellback(bot: Actor, rng: RandomNumberGenerator) -> void:
	bot.faction = "shellback"
	bot.display_name = "Shellback"
	bot.set_meta("look", "shellback")
	bot.set_meta("aim_turn", 90.0)
	bot.body_color = Color(0.42, 0.38, 0.3)
	bot.set_stand_height(SHELLBACK_HEIGHT, 0.4)
	bot.walk_speed = 3.0
	bot.sprint_speed = 4.8
	bot.health.max_health = SHELLBACK_HEALTH
	bot.health.health = SHELLBACK_HEALTH
	bot.health.set_armor(SHELLBACK_ARMOR)
	bot.rear_damage_mult = SHELLBACK_REAR
	for item in roll_loot("shellback", rng):
		bot.inventory.add_item(item)
	var bash := MeleeWeapon.new()
	bash.display_name = "Shell Bash"
	bash.light_damage = 36.0
	bash.light_windup = 0.65
	bash.light_stamina = 0.0
	bash.reach = 2.6
	bot.equip_weapon(bash)


## An ambusher under the black water: it lies low at its post and sees
## only what comes close, then comes up with a lunge and a heavy bite, and
## never follows anyone out of its pool.
func _make_lurker(bot: Actor, rng: RandomNumberGenerator) -> void:
	bot.faction = "lurker"
	bot.display_name = "Lurker"
	bot.set_meta("look", "lurker")
	bot.set_meta("lies_low", true)
	bot.set_meta("sight", LURKER_SIGHT)
	bot.set_meta("fov", 360.0)
	bot.set_meta("leash", LURKER_LEASH)
	bot.set_meta("dash", 0.6)
	bot.body_color = Color(0.16, 0.2, 0.19)
	bot.set_stand_height(LURKER_HEIGHT, 0.4)
	bot.walk_speed = 3.5
	bot.sprint_speed = 7.5
	bot.health.max_health = LURKER_HEALTH
	bot.health.health = LURKER_HEALTH
	bot.health.set_armor(20.0)
	for item in roll_loot("lurker", rng):
		bot.inventory.add_item(item)
	var jaws := MeleeWeapon.new()
	jaws.display_name = "Lurker's Jaws"
	jaws.light_damage = 30.0
	jaws.light_windup = 0.4
	jaws.light_stamina = 0.0
	jaws.reach = 2.8
	bot.equip_weapon(jaws)


## A hive's keeper: big, armored and slow to turn, with long hooked arms.
func _make_keeper(bot: Actor, rng: RandomNumberGenerator) -> void:
	bot.faction = "keeper"
	bot.display_name = "Brood Keeper"
	bot.set_meta("look", "brood_keeper")
	bot.set_meta("aim_turn", 120.0)
	bot.set_meta("feint_chance", 0.25)
	bot.body_color = Color(0.3, 0.27, 0.3)
	bot.set_stand_height(KEEPER_HEIGHT, 0.4)
	bot.walk_speed = 3.4
	bot.sprint_speed = 5.2
	bot.health.max_health = KEEPER_HEALTH
	bot.health.health = KEEPER_HEALTH
	bot.health.set_armor(KEEPER_ARMOR)
	for item in roll_loot("keeper", rng):
		bot.inventory.add_item(item)
	var hooks := MeleeWeapon.new()
	hooks.display_name = "Keeper's Hooks"
	hooks.light_damage = 22.0
	hooks.light_windup = 0.55
	hooks.light_stamina = 0.0
	hooks.reach = 3.2
	bot.equip_weapon(hooks)


## A broodling: a little stalker, quick and weak, carrying nothing.
func _make_broodling(bot: Actor) -> void:
	bot.faction = "broodling"
	bot.display_name = "Broodling"
	bot.set_meta("look", "broodling")
	bot.body_color = Color(0.4, 0.36, 0.34)
	bot.set_stand_height(BROODLING_HEIGHT, 0.2)
	bot.walk_speed = 6.5
	bot.sprint_speed = 9.0
	bot.health.max_health = BROODLING_HEALTH
	bot.health.health = BROODLING_HEALTH
	var bite := MeleeWeapon.new()
	bite.display_name = "Broodling's Bite"
	bite.light_damage = 6.0
	bite.light_windup = 0.3
	bite.light_stamina = 0.0
	bite.reach = 1.7
	bot.equip_weapon(bite)


## Slow sacs of spores with a weak slap. A dead one bursts (`death_burst`).
func _make_bloater(bot: Actor, rng: RandomNumberGenerator) -> void:
	bot.faction = "bloater"
	bot.display_name = "Bloater"
	bot.set_meta("look", "bloater")
	bot.body_color = Color(0.55, 0.62, 0.32)
	bot.set_stand_height(BLOATER_HEIGHT, 0.5)
	bot.walk_speed = 2.0
	bot.sprint_speed = 2.8
	bot.health.max_health = BLOATER_HEALTH
	bot.health.health = BLOATER_HEALTH
	for item in roll_loot("bloater", rng):
		bot.inventory.add_item(item)
	var slap := MeleeWeapon.new()
	slap.display_name = "Spore Slap"
	slap.light_damage = 8.0
	slap.light_windup = 0.8
	slap.light_stamina = 0.0
	slap.reach = 2.1
	bot.equip_weapon(slap)


## A bloater bursts where it dies, into a spore cloud that hurts every
## player and beast in it but other bloaters (`Raid.burst_cloud`).
func death_burst(bot: Actor) -> Dictionary:
	return BLOATER_CLOUD.duplicate() if bot != null and bot.faction == "bloater" else {}


## The Grey Matriarch at her den (its "spawn_boss" marker's meta "boss"),
## else an event's warlord as anywhere. Runs on clients too, so it is free
## of randomness.
func make_warlord(bot: Actor) -> void:
	if bot.get_meta("boss", "") == ROOTMOTHER:
		_make_rootmother(bot)
		return
	if bot.get_meta("boss", "") == ELDER:
		_make_elder(bot)
		return
	if bot.get_meta("boss", "") == DROWNED:
		_make_drowned(bot)
		return
	if bot.get_meta("boss", "") != "matriarch":
		super(bot)
		return
	bot.display_name = "Grey Matriarch"
	bot.set_meta("look", "marsh_stalker")
	bot.body_color = Color(0.32, 0.35, 0.34)
	bot.set_stand_height(MATRIARCH_HEIGHT, 0.4)
	bot.set_meta("feint_chance", 0.6)
	bot.walk_speed = 5.5
	bot.sprint_speed = 8.0
	bot.health.max_health = MATRIARCH_HEALTH
	bot.health.health = MATRIARCH_HEALTH
	bot.health.set_armor(MATRIARCH_ARMOR)
	var claws := bot.get_active_weapon() as MeleeWeapon
	if claws:
		claws.display_name = "Matriarch's Claws"
		claws.light_damage = 26.0
		claws.light_windup = 0.35
		claws.reach = 3.2


## The Rootmother: a brood keeper grown huge (see `ROOTMOTHER`). Free of
## randomness, like every boss.
func _make_rootmother(bot: Actor) -> void:
	bot.display_name = "The Rootmother"
	bot.set_meta("look", "brood_mother")
	bot.set_meta("feint_chance", 0.2)
	bot.set_meta("aim_turn", 90.0)
	bot.body_color = Color(0.26, 0.22, 0.27)
	bot.set_stand_height(ROOTMOTHER_HEIGHT, 0.5)
	bot.walk_speed = 3.0
	bot.sprint_speed = 4.6
	bot.health.max_health = ROOTMOTHER_HEALTH
	bot.health.health = ROOTMOTHER_HEALTH
	bot.health.set_armor(ROOTMOTHER_ARMOR)
	bot.rear_damage_mult = ROOTMOTHER_REAR
	var hooks := bot.get_active_weapon() as MeleeWeapon
	if hooks:
		hooks.display_name = "Rootmother's Hooks"
		hooks.light_damage = 28.0
		hooks.light_windup = 0.65
		hooks.reach = 3.8


## The Shellback Elder: a shellback grown huge (see `ELDER`), made from a
## shellback (its marker's faction) so the grazers are its kin. Free of
## randomness, like every boss.
func _make_elder(bot: Actor) -> void:
	bot.display_name = "The Shellback Elder"
	bot.set_meta("look", "shellback_elder")
	bot.set_meta("feint_chance", 0.0)
	bot.set_meta("aim_turn", 75.0)
	bot.set_meta("dash", 1.0)
	bot.set_meta("dash_every", ELDER_CHARGE_EVERY[0])
	bot.body_color = Color(0.36, 0.33, 0.27)
	bot.set_stand_height(ELDER_HEIGHT, 0.6)
	bot.walk_speed = 2.6
	bot.sprint_speed = 4.4
	bot.health.max_health = ELDER_HEALTH
	bot.health.health = ELDER_HEALTH
	bot.health.set_armor(ELDER_ARMOR)
	bot.rear_damage_mult = ELDER_REAR
	var horns := bot.get_active_weapon() as MeleeWeapon
	if horns:
		horns.display_name = "Elder's Dome"
		horns.light_damage = 30.0
		horns.light_windup = 0.7
		horns.reach = 3.4
		horns.heavy_damage = ELDER_CHARGE_DAMAGE
		horns.heavy_windup = ELDER_CHARGE_WINDUP
		horns.heavy_stamina = 0.0
		horns.dash_range = ELDER_CHARGE
		horns.dash_stamina = 0.0
		horns.dash_through = true


## The Drowned Lurker: a lurker grown huge (see `DROWNED`), made from a
## lurker (its marker's faction) so the lurkers are its kin, but no
## ambusher at a post: the Raid holds it under and lets it up. Free of
## randomness, like every boss.
func _make_drowned(bot: Actor) -> void:
	bot.display_name = "The Drowned Lurker"
	bot.set_meta("look", "drowned_lurker")
	bot.set_meta("lies_low", false)
	bot.set_meta("sight", DROWNED_SIGHT)
	bot.set_meta("leash", 40.0)
	bot.set_meta("dash", 1.0)
	bot.set_meta("feint_chance", 0.15)
	bot.set_meta("aim_turn", 110.0)
	bot.body_color = Color(0.13, 0.17, 0.17)
	bot.set_stand_height(DROWNED_HEIGHT, 0.5)
	bot.walk_speed = 3.4
	bot.sprint_speed = 6.5
	bot.health.max_health = DROWNED_HEALTH
	bot.health.health = DROWNED_HEALTH
	bot.health.set_armor(DROWNED_ARMOR)
	bot.rear_damage_mult = 1.0
	var jaws := bot.get_active_weapon() as MeleeWeapon
	if jaws:
		jaws.display_name = "Drowned Jaws"
		jaws.light_damage = 34.0
		jaws.light_windup = 0.6
		jaws.reach = 3.4
		jaws.heavy_damage = 52.0
		jaws.heavy_windup = 0.8
		jaws.heavy_stamina = 0.0
		jaws.dash_stamina = 0.0


## A share of a Rootway keeper's vault.
func roll_vault(_kind: String, rng: RandomNumberGenerator) -> Array[String]:
	var out: Array[String] = []
	for i in rng.randi_range(ROOT_VAULT_ITEMS.x, ROOT_VAULT_ITEMS.y):
		out.append(ItemDB.roll(HIVE_TABLE, rng))
	for i in rng.randi_range(ROOT_VAULT_DATA.x, ROOT_VAULT_DATA.y):
		out.append("upgrade_data")
	if rng.randf() < ROOT_VAULT_BLUEPRINT:
		out.append(BLUEPRINTS[rng.randi() % BLUEPRINTS.size()])
	var relic := roll_artifact(rng, ROOT_VAULT_ARTIFACT)
	if relic != "":
		out.append(relic)
	if rng.randf() < ROOT_VAULT_PAINT:
		out.append(PAINT)
	return out


func keeper_news(bot: Actor, phase: int) -> String:
	var elder: bool = bot != null and is_instance_valid(bot) and bot.get_meta("boss", "") == ELDER
	var drowned: bool = bot != null and is_instance_valid(bot) and bot.get_meta("boss", "") == DROWNED
	if drowned and phase == 2:
		return "The Drowned Lurker thrashes and the water boils: it surfaces faster now, and the spore vents are venting"
	if drowned and phase == 0:
		return "The Drowned Lurker has fallen: its vault under the Rotwood is open to all who fought it"
	if elder and phase == 2:
		return "The Shellback Elder bellows and the floor cracks: it charges harder, and the spore vents are venting"
	if elder and phase == 0:
		return "The Shellback Elder has fallen: its vault under the Gillwood is open to all who fought it"
	if phase == 2:
		return "The Rootmother tears the floor open: the spore vents are venting, watch your feet"
	if phase == 0:
		return "The Rootmother has fallen: her vault under the Westwood is open to all who fought her"
	return ""


## Hurt below half, the Elder charges more often.
func on_keeper_phase(bot: Actor, phase: int) -> void:
	if bot.get_meta("boss", "") != ELDER:
		return
	var brain := bot.get_node_or_null("Brain") as BotBrain
	if brain != null:
		brain.dash_every = ELDER_CHARGE_EVERY[1] if phase == 2 else ELDER_CHARGE_EVERY[0]


func keeper_snag_news(bot: Actor) -> String:
	if bot != null and bot.get_meta("boss", "") == ELDER:
		return "The Shellback Elder has rammed the roots and is stuck: get behind it"
	return ""


func boss_back_news(bot: Actor, _where: String) -> String:
	if bot != null and bot.get_meta("boss", "") == "matriarch":
		return "The Grey Matriarch is back in her den"
	if bot != null and bot.get_meta("boss", "") == ROOTMOTHER:
		return "The Rootmother stirs again under the Westwood"
	if bot != null and bot.get_meta("boss", "") == ELDER:
		return "The Shellback Elder stirs again under the Gillwood"
	if bot != null and bot.get_meta("boss", "") == DROWNED:
		return "Something huge moves in the water under the Rotwood again"
	return super(bot, _where)


## The Matriarch may carry her trophy, beside what every warlord carries.
## Runs on the authority only (the `Raid` calls it as a bot is made there).
func on_spawn(actor: Actor) -> void:
	if actor == null or actor.get_meta("boss", "") != "matriarch":
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	if rng.randf() < TROPHY_CHANCE:
		actor.inventory.add_item(TROPHY)
