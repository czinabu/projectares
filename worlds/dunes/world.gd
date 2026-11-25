extends WorldDef
## The Dune Sea, the haul (DESIGN.md "More worlds", "The Dune Sea"): a
## PvPvE world built round vehicles and cargo, about three times Ashfront's
## width. Its wreck fields hold salvage crates too big for a pack
## (`SalvageCrate`): lifted in both hands and hauled home in a vehicle's
## cargo, banked at a depot. You keep what you wear when you die; the pack
## and every crate you haul drop. It pays vehicle blueprints and parts and
## the most scrip a trip. Part one: the world, its map, the crates and the
## death rule. Part two: sandstorms that bury the wreck fields they cross
## and uncover buried ones elsewhere. Part three: armed convoys driving
## between the yards, and roof guns on the rovers.

const MapScript := preload("map.gd")

## The enemy roster: each kind of bot this world sends, as data. `equip_bot`
## rolls one by `chance` (out of their sum) and builds it from its row:
## `look` is a skin from `Look.SKINS`, `weapon` "gun" or "blade". Add a kind
## by adding a row; give a kind its own senses or way of fighting with the
## metas in docs/systems/bots.md ("sight", "fov", "reach", "burst", ...).
## The Dune Sea's own enemy (Caleb's call: "own rosters"): the raiders of
## the wreck fields, with a Salvage Runner who closes in fast with a knife,
## and the Dune Burrower under the sand (`BURROWER`, built for the map's
## "spawn_guard" markers of faction "burrower").
const ROSTER := {
	"grunt": {"name": "Sand Raider", "look": "scavenger", "chance": 6.0, "health": 100.0, "armor": 0.0,
			"walk": 4.8, "sprint": 7.4, "weapon": "gun", "gun": "Worn Rifle", "damage": 11.0, "spread": 3.2,
			"interval": 0.16},
	"marksman": {"name": "Dune Marksman", "look": "raider", "chance": 2.0, "health": 90.0, "armor": 20.0,
			"walk": 4.2, "sprint": 6.6, "weapon": "gun", "gun": "Long Rifle", "damage": 28.0, "spread": 0.8,
			"interval": 0.9, "metas": {"sight": 70.0, "range": 35.0, "burst": Vector2(0.1, 1.4)}},
	"brute": {"name": "Scrap Brute", "look": "scrap_brute", "chance": 1.5, "health": 260.0, "armor": 40.0,
			"walk": 5.0, "sprint": 8.6, "weapon": "blade", "blade": "Cleaver", "damage": 30.0, "windup": 0.55,
			"reach": 2.6},
	# Light and quick: it runs in on a flank, dodging, while the rifles
	# keep you down, and guts you with a knife.
	"runner": {"name": "Salvage Runner", "look": "salvage_runner", "chance": 2.0, "health": 80.0, "armor": 0.0,
			"walk": 5.6, "sprint": 9.2, "weapon": "blade", "blade": "Salvage Knife", "damage": 16.0, "windup": 0.3,
			"reach": 2.0, "item": "knife_gutter", "metas": {"dash": 0.5, "hunters": 2, "flankers": 2, "feint_chance": 0.3}},
}
## A Dune Burrower: an ambusher that lies under the sand at its post, sees
## (feels) only what comes close, comes up with a lunge and a heavy bite,
## and keeps near its post, except in a sandstorm, when it feels further
## and follows further ("storm_bold": `BotBrain.storm_boost`). It and the
## raiders leave each other be (`can_damage`).
const BURROWER := {"name": "Dune Burrower", "look": "dune_burrower", "health": 200.0, "armor": 30.0,
		"walk": 3.5, "sprint": 7.8, "weapon": "blade", "blade": "Burrower's Jaws", "damage": 28.0, "windup": 0.4,
		"reach": 2.8, "height": 1.4, "color": Color(0.6, 0.48, 0.32),
		"metas": {"lies_low": true, "sight": 9.0, "fov": 360.0, "leash": 14.0, "dash": 0.6, "storm_bold": 1.5}}
const BURROWER_FACTION := "burrower"
## The faction every roster kind fights for. A second army is a second
## faction on some "spawn_bot" markers (their meta "faction").
const FACTION := "dunes"

## Sandstorms (DESIGN.md "The Dune Sea (part two)", Caleb's call: shifting
## fields). Wide and quick, sight cut hard in the thick of it, and each one
## aimed through a wreck field (`weather_path`), burying the fields its
## heart crosses and uncovering buried ones elsewhere.
const STORM_RADIUS := 200.0
const STORM_SPEED := 4.5
const STORM_SIGHT := 0.35
const STORM_CARRY := 0.5
## How many of the eight wreck fields lie buried when the world starts.
const BURIED_AT_START := 3
## The convoy (DESIGN.md "The Dune Sea (part three)", Caleb's call: a
## hauler convoy, roof guns on the rovers): the hauler first, then its
## escort.
const CONVOY := ["rover_warden", "rover_warden", "bike_raider"]

## What a salvage crate holds (`roll_loot("crate")`): `CRATE_ITEMS` picks
## from `CRATE_TABLE`, worth several caches together, with the vehicle
## blueprints rare in it.
const CRATE_ITEMS := Vector2i(4, 6)
const CRATE_TABLE := [
	{"id": "dunes_gearbox", "weight": 24.0},
	{"id": "dunes_drive_coil", "weight": 12.0},
	{"id": "alloy_ingot", "weight": 16.0},
	{"id": "power_cell", "weight": 20.0},
	{"id": "circuit_board", "weight": 20.0},
	{"id": "scrap_metal", "weight": 20.0},
	{"id": "reactor_core", "weight": 1.5},
	{"id": "bp_mech_bulwark", "weight": 0.6},
	{"id": "bp_jet_kestrel", "weight": 0.6},
]
## The vehicles parked at the landing and the wreck fields: mostly rovers,
## built for the haul.
const VEHICLE_TABLE := [
	{"id": "rover_warden", "weight": 6.0},
	{"id": "bike_scrapper", "weight": 3.0},
	{"id": "bike_raider", "weight": 1.0},
]
## Loot tables by source (`roll_loot`): weighted item ids from `ItemDB`.
## Rare gear belongs in a PvP world; keep a gentle world's tables basic.
const CACHE_TABLE := [
	{"id": "scrap_metal", "weight": 30.0},
	{"id": "medkit", "weight": 18.0},
	{"id": "power_cell", "weight": 12.0},
	{"id": "circuit_board", "weight": 12.0},
	{"id": "rifle_scrap", "weight": 4.0},
	{"id": "pistol_service", "weight": 4.0},
	{"id": "plate_light", "weight": 3.0},
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
	"dunes_caches": {"title": "Loot 3 caches in the Dune Sea", "stat": "cache:cache", "goal": 3, "kind": "daily",
			"scrip": 150},
	"dunes_gearboxes": {"title": "Bring home 4 Salvaged Gearboxes", "stat": "item:dunes_gearbox", "goal": 4,
			"kind": "weekly", "scrip": 900},
	"dunes_raiders": {"title": "Bring down 10 of Dune Sea's raiders", "stat": "kills:dunes", "goal": 10,
			"kind": "weekly", "scrip": 700},
}


func _init() -> void:
	# The planet first (DESIGN.md "Planet kit"): it sets the sky, ground and
	# the rule defaults (cold, shot carry, grip) the lines below may change.
	take_planet("dunes")
	id = "dunes"
	display_name = "Dune Sea"
	description = "A sea of dunes and wreck fields, three times Ashfront's width. Haul salvage crates home in your vehicle's cargo; keep what you wear when you die, lose the pack and every crate. Sandstorms bury the wreck fields and uncover others."
	bot_count = 16
	contract_tag = "dunes"
	# You keep what you wear; the pack drops in a bag and every crate you
	# haul falls where you die (Caleb's call).
	keep_gear_on_death = true
	war_scale = 0.5
	weather_kind = "sand"
	weather_name = "Sandstorm"
	weather_radius = STORM_RADIUS
	weather_speed = STORM_SPEED
	weather_gap = Vector2(240.0, 480.0)
	weather_first = Vector2(90.0, 240.0)
	weather_sight = STORM_SIGHT
	weather_carry = STORM_CARRY
	weather_gust = 7.0
	weather_wipes_tracks = true
	weather_field = MapScript.FIELD
	weather_buries = true
	fields_buried_at_start = BURIED_AT_START
	# Convoys (part three): a rover hauling four crates, a second rover and
	# a bike riding escort.
	convoy_vehicles.assign(CONVOY)
	convoy_riders = 1
	convoy_faction = FACTION


## Items only this world adds. Ids are global, so prefix them with the
## world's id: ItemDB.register("dunes_trophy", ...).
func register_items() -> void:
	ItemDB.register("dunes_gearbox", "Salvaged Gearbox", ItemDB.Rarity.UNCOMMON, 260, ["material"], {},
			"A heavy gearbox out of a buried hauler, sand still in its teeth. Vehicle parts.")
	ItemDB.register("dunes_drive_coil", "Drive Coil", ItemDB.Rarity.RARE, 520, ["material"], {},
			"A hauler's drive coil, still wound. Vehicle parts.")


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


## A sandstorm comes in off the sand from any side, crosses one of the
## wreck fields and goes out the far side.
func weather_path(rng: RandomNumberGenerator) -> Array:
	var wreck: Dictionary = MapScript.WRECKS[rng.randi_range(0, MapScript.WRECKS.size() - 1)]
	var through := Vector3(wreck["at"].x, 0.0, wreck["at"].y)
	var angle := rng.randf() * TAU
	var wind := Vector3(cos(angle), 0.0, sin(angle))
	var reach := weather_field + weather_radius
	return [through - wind * reach, through + wind * reach]


func zone_name(tier: int) -> String:
	return ["The landing", "The wreck fields", "The deep sea"][tier] if tier >= 0 and tier <= 2 else ""


func starter_loadout() -> Array[String]:
	return ["rifle_scrap", "blade_scrap", "pistol_service", "plate_light", "visor_scav", "field_dressing"]


func roll_loot(source: String, rng: RandomNumberGenerator) -> Array[String]:
	var out: Array[String] = []
	if source == "crate":
		for i in rng.randi_range(CRATE_ITEMS.x, CRATE_ITEMS.y):
			out.append(ItemDB.roll(CRATE_TABLE, rng))
		return out
	if source == "vehicle":
		out.append(ItemDB.roll(VEHICLE_TABLE, rng))
		return out
	var table := BOT_TABLE if source == "bot" else CACHE_TABLE
	for i in rng.randi_range(1, 2) if source == "bot" else rng.randi_range(2, 4):
		out.append(ItemDB.roll(table, rng))
	return out


func contract_jobs() -> Dictionary:
	return CONTRACTS


## Builds a bot from its roster row. Only from `rng` and the bot's metas,
## so a client building the same seed gets the same bot.
func equip_bot(bot: Actor, rng: RandomNumberGenerator) -> void:
	# A lair's guard (the map's "spawn_guard" of faction "burrower") is a
	# Dune Burrower, wild.
	var kind := "burrower" if bot.faction == BURROWER_FACTION else _roll_kind(rng)
	var row: Dictionary = BURROWER if kind == "burrower" else ROSTER[kind]
	if bot.faction == "":
		bot.faction = FACTION
	bot.set_meta("kind", kind)
	bot.display_name = row["name"]
	bot.set_meta("look", row["look"])
	bot.walk_speed = row["walk"]
	bot.sprint_speed = row["sprint"]
	if row.has("height"):
		bot.set_stand_height(row["height"], 0.4)
	if row.has("color"):
		bot.body_color = row["color"]
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
		# Held as the item it is ("item"), so it looks like one.
		blade.item_id = row.get("item", "")
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


## The burrowers and the raiders leave each other be: the raiders know the
## sand's ways, and the burrowers hunt the strangers who do not.
func can_damage(attacker: Node, target: Node, info: DamageInfo) -> bool:
	if not super.can_damage(attacker, target, info):
		return false
	var a := attacker as Actor
	var t := target as Actor
	if a == null or t == null:
		return true
	return not ([a.faction, t.faction] in [[FACTION, BURROWER_FACTION], [BURROWER_FACTION, FACTION]])


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
	bot.display_name = "Wreck Baron"
	# A body of its own (`Look.SKINS` "baron"), not a brute with more health.
	bot.set_meta("look", "baron")
	bot.health.max_health = 900.0
	bot.health.health = 900.0
	bot.health.set_armor(120.0)
