extends WorldDef
## The Basalt Rift, the sky fight (DESIGN.md "More worlds", "Basalt Rift"):
## a small, tall PvP world over a sea of lava where flight rigs decide the
## fights. Everything you stand on is basalt rising out of the lava (the
## map's mesas, bridges and perches); the lava burns whoever goes in
## (`molten_level`), and updrafts over its vents carry anyone in the air up
## past their rig's ceiling (`updraft_at`), the only way onto the Crown.
## Ashfront's death rule: the fallen drop scrip, not gear. Part one (Caleb's
## call): the world, its map, the lava and the updrafts. Part two: the Sky
## Leviathan, an armoured airship that drifts across the rift now and then
## as a world event (`airship_vehicle`, Caleb's call: "a world event that
## fights and falls"), its turrets shooting at flyers, weak spots at three
## heights that drop salvage as they break, and a crash with a big haul.
## The rig rewards (upgrade data, rig cosmetics) come in part three.

const MapScript := preload("map.gd")

## The enemy roster: each kind of bot this world sends, as data. `equip_bot`
## rolls one by `chance` (out of their sum) and builds it from its row:
## `look` is a skin from `Look.SKINS`, `weapon` "gun" or "blade". Add a kind
## by adding a row; give a kind its own senses or way of fighting with the
## metas in docs/systems/bots.md ("sight", "fov", "reach", "burst", ...).
const ROSTER := {
	"grunt": {"name": "Rift Cutthroat", "look": "scavenger", "chance": 6.0, "health": 100.0, "armor": 0.0,
			"walk": 4.8, "sprint": 7.4, "weapon": "gun", "gun": "Worn Rifle", "damage": 11.0, "spread": 3.2,
			"interval": 0.16},
	"marksman": {"name": "Spire Marksman", "look": "raider", "chance": 2.0, "health": 90.0, "armor": 20.0,
			"walk": 4.2, "sprint": 6.6, "weapon": "gun", "gun": "Long Rifle", "damage": 28.0, "spread": 0.8,
			"interval": 0.9, "metas": {"sight": 90.0, "range": 45.0, "burst": Vector2(0.1, 1.4)}},
	"brute": {"name": "Slag Brute", "look": "heavy", "chance": 1.5, "health": 260.0, "armor": 40.0,
			"walk": 5.0, "sprint": 8.6, "weapon": "blade", "blade": "Cleaver", "damage": 30.0, "windup": 0.55,
			"reach": 2.6},
}
## The Sky Leviathan (DESIGN.md "Basalt Rift"): its weak spots at three
## heights, each a bot on one of the ship's seats (its "part", the bot's
## `boss` meta, built by `equip_bot`): four engine pods hung low under the
## hull, two spine plates on its back (soft to a dive from above: `rear`
## multiplies hits from steeply above) and two turrets on top of
## its bridge tower, which fight. `radius` and `height` are the body's.
const LEVIATHAN := "rift_leviathan"
const LEVIATHAN_GUN := "rift_leviathan_gun"
const LEVIATHAN_FACTION := "leviathan"
const LEVIATHAN_PARTS := {
	"leviathan_pod": {"name": "Engine Pod", "health": 420.0, "armor": 0.0, "radius": 1.5, "height": 3.0},
	"leviathan_spine": {"name": "Spine Plate", "health": 650.0, "armor": 50.0, "radius": 1.3, "height": 2.6,
			"rear": 2.5},
	"leviathan_turret": {"name": "Leviathan Turret", "health": 320.0, "armor": 30.0, "radius": 1.1,
			"height": 2.2, "metas": {"sight": 90.0, "range": 75.0, "fov": 360.0}},
}
## Where the weak spots sit on the ship: [part, look of its piece, seat
## (feet) on the ship, turned round].
const LEVIATHAN_SEATS := [
	["leviathan_pod", "pod", Vector3(-8.5, -2.5, -9.0), false],
	["leviathan_pod", "pod", Vector3(8.5, -2.5, -9.0), false],
	["leviathan_pod", "pod", Vector3(-8.5, -2.5, 9.0), false],
	["leviathan_pod", "pod", Vector3(8.5, -2.5, 9.0), false],
	["leviathan_spine", "plate", Vector3(0.0, 8.4, -8.5), false],
	["leviathan_spine", "plate", Vector3(0.0, 8.4, 8.5), false],
	["leviathan_turret", "turret", Vector3(0.0, 13.5, -2.6), false],
	["leviathan_turret", "turret", Vector3(0.0, 13.5, 2.6), true],
]
## What a broken weak spot drops under the ship, and what is in its hold
## when it crashes (with a supply pod's war loot on top).
const LEVIATHAN_PART_TABLE := [
	{"id": "alloy_ingot", "weight": 30.0},
	{"id": "power_cell", "weight": 30.0},
	{"id": "circuit_board", "weight": 20.0},
	{"id": "targeting_chip", "weight": 10.0},
	{"id": "reactor_core", "weight": 5.0},
]
const LEVIATHAN_HOLD_TABLE := [
	{"id": "reactor_core", "weight": 12.0},
	{"id": "targeting_chip", "weight": 12.0},
	{"id": "alloy_ingot", "weight": 12.0},
	{"id": "boots_thruster", "weight": 6.0},
	{"id": "wings_glide", "weight": 6.0},
	{"id": "rifle_carbine", "weight": 5.0},
	{"id": "frame_runner", "weight": 5.0},
	{"id": "helm_spotter", "weight": 4.0},
]

## What the lava does to whoever goes in, four times a second (armor is no
## help): about half a second for anyone.
const LAVA_DAMAGE := 50.0

## The faction every roster kind fights for. A second army is a second
## faction on some "spawn_bot" markers (their meta "faction").
const FACTION := "rift"

## Loot tables by source (`roll_loot`): weighted item ids from `ItemDB`.
## A PvP world's caches: real gear, and the rigs that fly best here (the
## boots and wings) now and then.
const CACHE_TABLE := [
	{"id": "scrap_metal", "weight": 34.0},
	{"id": "circuit_board", "weight": 20.0},
	{"id": "medkit", "weight": 16.0},
	{"id": "power_cell", "weight": 12.0},
	{"id": "alloy_ingot", "weight": 6.0},
	{"id": "targeting_chip", "weight": 3.0},
	{"id": "reactor_core", "weight": 1.0},
	{"id": "rifle_carbine", "weight": 3.0},
	{"id": "smg_stinger", "weight": 3.0},
	{"id": "knife_gutter", "weight": 2.5},
	{"id": "frame_runner", "weight": 2.5},
	{"id": "boots_thruster", "weight": 3.0},
	{"id": "wings_glide", "weight": 2.0},
	{"id": "optic_reflex", "weight": 2.5},
	{"id": "helm_spotter", "weight": 2.0},
]
const BOT_TABLE := [
	{"id": "scrap_metal", "weight": 40.0},
	{"id": "medkit", "weight": 15.0},
	{"id": "power_cell", "weight": 10.0},
]

## The world's own contracts, counted only here (`contract_tag`). Each must
## be doable alone, and none may count player kills (docs/systems/
## economy-and-progression.md, "Contracts").
const CONTRACTS := {
	"rift_caches": {"title": "Loot 3 caches in the Basalt Rift", "stat": "cache:cache", "goal": 3, "kind": "daily",
			"scrip": 150},
	"rift_raiders": {"title": "Bring down 10 of the Rift's soldiers", "stat": "kills:rift", "goal": 10,
			"kind": "weekly", "scrip": 700},
}


func _init() -> void:
	# The planet first (DESIGN.md "Planet kit"): it sets the sky, ground and
	# the rule defaults (cold, shot carry, grip) the lines below may change.
	take_planet("basalt")
	id = "rift"
	display_name = "Basalt Rift"
	description = "Basalt columns over a sea of lava. Always-on PvP where flight rigs decide the fights: ride the updrafts above your rig's ceiling, and do not touch the lava. The fallen drop scrip, not gear."
	bot_count = 14
	contract_tag = "rift"
	# Ashfront's death rule (DESIGN.md "More worlds"): deaths drop scrip,
	# not gear.
	death_drops_scrip = true
	war_scale = 0.5
	# The lava sea (the map's `LAVA_Y`): it burns whoever goes in.
	molten_level = MapScript.LAVA_Y
	molten_damage = LAVA_DAMAGE
	# The Sky Leviathan, along the map's `airship_routes`.
	airship_vehicle = LEVIATHAN
	airship_faction = LEVIATHAN_FACTION
	airship_passes = 3


## Items only this world adds. Ids are global, so prefix them with the
## world's id: ItemDB.register("rift_trophy", ...).
func register_items() -> void:
	ItemDB.register(LEVIATHAN, "Sky Leviathan", ItemDB.Rarity.RELIC, 0, ["airship"],
			{"model": "airship", "max_speed": 5.0, "accel": 1.5, "turn_rate": 0.22, "climb_rate": 2.5,
			"climb_accel": 1.2, "gravity": 6.0, "max_fall_speed": 16.0, "coast_decel": 0.5, "lean_amount": 0.08,
			"body_size": Vector3(9.0, 12.0, 34.0), "body_color": Color(0.56, 0.5, 0.45),
			"passenger_seat": true, "seats": _leviathan_seats()},
			"An armoured airship of the rift's warlords. Its turrets shoot at anything in the air; break its "
			+ "engine pods, spine plates and turrets and it comes down with its hold.")
	ItemDB.register(LEVIATHAN_GUN, "Leviathan Turret Gun", ItemDB.Rarity.RARE, 0, ["mounted"],
			{"damage": 9.0, "headshot_mult": 1.0, "fire_interval": 0.14, "mag_size": 60, "ammo_in_mag": 60,
			"reserve_ammo": 9999, "reload_time": 2.5, "spread_deg": 1.8, "bloom_per_shot": 0.03, "max_bloom": 1.2,
			"recoil_kick_deg": 0.0, "max_range": 150.0, "tracer_color": Color(1.0, 0.45, 0.2)},
			"A Sky Leviathan's turret gun, never carried off.")


## The ship's seats, one for each weak spot (`Vehicle.seats`; the
## anchors only matter for a pose nobody sees, the part bots being hidden).
static func _leviathan_seats() -> Array:
	var out: Array = []
	for row: Array in LEVIATHAN_SEATS:
		var at: Vector3 = row[2]
		var seat := {"offset": at, "point": at + Vector3(0, 0.8, 0),
				"grips": [at + Vector3(-0.2, 1.2, -0.3), at + Vector3(0.2, 1.2, -0.3)] as Array[Vector3],
				"pegs": [at + Vector3(-0.15, 0.4, 0.0), at + Vector3(0.15, 0.4, 0.0)] as Array[Vector3],
				"lean": 0.0, "exit": at, "part": row[0], "piece": row[1], "turn": PI if row[3] else 0.0}
		if row[0] == "leviathan_turret":
			seat["gun"] = LEVIATHAN_GUN
		out.append(seat)
	return out


func create_map() -> Node3D:
	var map := MapScript.new()
	map.planet = planet_type()
	return map


## The map's ground, worked out ahead of a visit on a worker thread.
func prepare_map() -> void:
	var map: Node3D = MapScript.new()
	map.call("prepare_shared")
	map.free()


## Three rings from the landing at the south edge (outer) to the far north
## (core), split where the map says.
func zone_at(pos: Vector3) -> int:
	if pos.z <= MapScript.CORE_FROM_Z:
		return 2
	if pos.z <= MapScript.MIDDLE_FROM_Z:
		return 1
	return 0


func zone_name(tier: int) -> String:
	return ["The Gate Shelf", "The Stacks", "The Crown"][tier] if tier >= 0 and tier <= 2 else ""


## The vents' updrafts (the map's `VENTS`).
func updraft_at(pos: Vector3) -> float:
	return MapScript.updraft_at(pos)


## A rig is the point here: the starter kit flies.
func starter_loadout() -> Array[String]:
	return ["rifle_scrap", "blade_scrap", "pistol_service", "jetpack_mk1", "plate_light", "visor_scav",
			"field_dressing"]


func roll_loot(source: String, rng: RandomNumberGenerator) -> Array[String]:
	var table: Array = CACHE_TABLE
	var count := rng.randi_range(2, 4)
	match source:
		"bot":
			table = BOT_TABLE
			count = rng.randi_range(1, 2)
		"airship_part":
			table = LEVIATHAN_PART_TABLE
			count = rng.randi_range(1, 2)
		"airship_hold":
			table = LEVIATHAN_HOLD_TABLE
			count = rng.randi_range(3, 5)
	var out: Array[String] = []
	for i in count:
		out.append(ItemDB.roll(table, rng))
	return out


func contract_jobs() -> Dictionary:
	return CONTRACTS


## Builds a bot from its roster row. Only from `rng` and the bot's metas,
## so a client building the same seed gets the same bot.
func equip_bot(bot: Actor, rng: RandomNumberGenerator) -> void:
	if LEVIATHAN_PARTS.has(str(bot.get_meta("boss", ""))):
		_make_leviathan_part(bot)
		return
	var kind := _roll_kind(rng)
	var row: Dictionary = ROSTER[kind]
	if bot.faction == "":
		bot.faction = FACTION
	bot.set_meta("kind", kind)
	bot.display_name = row["name"]
	bot.set_meta("look", row["look"])
	bot.walk_speed = row["walk"]
	bot.sprint_speed = row["sprint"]
	# Further in is tougher (the Raid sets "zone" before this).
	var tier := clampi(int(bot.get_meta("zone", 0)), 0, 2)
	var tough := 1.0 + tier * 0.25
	bot.health.max_health = float(row["health"]) * tough
	bot.health.health = bot.health.max_health
	bot.health.set_armor(float(row["armor"]) * tough)
	var metas: Dictionary = row.get("metas", {})
	for key: String in metas:
		bot.set_meta(key, metas[key])
	for id in roll_loot("bot", rng):
		bot.inventory.add_item(id)
	if row["weapon"] == "blade":
		var blade := MeleeWeapon.new()
		blade.display_name = row["blade"]
		blade.light_damage = row["damage"]
		blade.light_windup = row["windup"]
		blade.heavy_damage = float(row["damage"]) * 1.6
		blade.light_stamina = 0.0
		blade.reach = row["reach"]
		bot.equip_weapon(blade)
	else:
		var gun := Gun.new()
		gun.display_name = row["gun"]
		gun.damage = row["damage"]
		gun.spread_deg = row["spread"]
		gun.fire_interval = row["interval"]
		gun.reserve_ammo = 600
		gun.headshot_mult = 1.0
		bot.equip_weapon(gun)


## One of the Sky Leviathan's weak spots, from its row: no body you see
## (the ship's model is its body), nothing carried (its salvage falls when
## it breaks, `Raid._on_airship_part_died`), and a turret's gun is the
## seat's own. Free of randomness, so a client builds the same.
func _make_leviathan_part(bot: Actor) -> void:
	var kind := str(bot.get_meta("boss"))
	var row: Dictionary = LEVIATHAN_PARTS[kind]
	bot.faction = LEVIATHAN_FACTION
	bot.set_meta("kind", kind)
	bot.display_name = row["name"]
	bot.set_meta("look", "ship_part")
	bot.set_stand_height(row["height"], 0.3)
	bot.set_body_radius(row["radius"])
	bot.health.max_health = row["health"]
	bot.health.health = bot.health.max_health
	bot.health.set_armor(row["armor"])
	# Soft only to a dive from steeply above, never from behind.
	bot.rear_damage_mult = float(row.get("rear", 1.0))
	bot.rear_arc_deg = 0.0
	var metas: Dictionary = row.get("metas", {})
	for key: String in metas:
		bot.set_meta(key, metas[key])


func _roll_kind(rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for kind: String in ROSTER:
		total += float(ROSTER[kind]["chance"])
	var pick := rng.randf() * total
	for kind: String in ROSTER:
		pick -= float(ROSTER[kind]["chance"])
		if pick <= 0.0:
			return kind
	return ROSTER.keys()[0]


## A warlord (a world event, or a "spawn_boss" marker) is a fight of its own:
## more health, real armor, a better gun. Keep this free of randomness:
## clients build the same warlord from it.
func make_warlord(bot: Actor) -> void:
	bot.display_name = "Lord of the Crown"
	bot.health.max_health = 900.0
	bot.health.health = 900.0
	bot.health.set_armor(120.0)
