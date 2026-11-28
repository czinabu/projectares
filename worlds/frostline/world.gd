extends WorldDef
## Frostline: a frozen river valley where the war ended long ago, climbing to
## the Stilled Engine, the terraforming drum that once kept the world warm.
## The co-op expedition world (DESIGN.md section 2): no PvP, and two hostile
## factions that fight each other as readily as you: the Engine's Warden
## automata, still on guard, and packs of Feral stalkers.

const MapScript := preload("res://worlds/frostline/map.gd")

## Share of bots that are Feral stalkers; the rest are Wardens.
const FERAL_CHANCE := 0.45
## The enemies by zone, river mouth to glacier head (DESIGN.md "The enemy AI
## pass", step 2). A Warden is the machine you sneak past: it sees far down
## a narrow cone, notices slowly out there, and holds a beam on you before
## its first shot, so a crouch out of its sweep or a whiteout gets you by;
## seen, it shoots hard and true. A Feral is a pack hunter: weak alone, it
## follows fresh tracks (`FERAL_TRACKS` metres), picks on someone shivering
## and never steps into a heater's or a beacon's warmth.
const WARDEN_HEALTH := [160.0, 180.0, 195.0]
const WARDEN_ARMOR := [15.0, 20.0, 25.0]
## The glacier head's Wardens hit softer than the gate's (Caleb's pick):
## with `holds_turn`, a solo player in the open beats its post of three
## about one time in six (duel bench `--group 3`), while one Warden alone
## still almost never wins.
const WARDEN_DAMAGE := [24.0, 26.0, 21.0]
const WARDEN_INTERVAL := 0.4
const WARDEN_SPREAD := 0.6
const WARDEN_SIGHT := 70.0
const WARDEN_FOV := 100.0
const WARDEN_REACH := 60.0
const WARDEN_FAR_NOTICE := 2.4
const WARDEN_LOCK := 0.5
const WARDEN_TURN := 140.0
## How many Wardens shoot at one person at once (`BotBrain.attack_slots`):
## the rest hold their beams on you and wait, so a post is a fight you can
## win alone from cover, never a firing squad.
const WARDEN_SLOTS := [1, 1, 1]
## Trigger time and rest: steady aimed shots, not a rifleman's bursts.
const WARDEN_BURST := Vector2(2.4, 0.5)
const FERAL_HEALTH := [70.0, 70.0, 75.0]
const FERAL_DAMAGE := [18.0, 18.0, 19.0]
const FERAL_WINDUP := [0.4, 0.36, 0.32]
const FERAL_TRACKS := 26.0
## Aim skill by zone (`BotBrain.skill`), quiet at the mouth and sharp at the
## glacier head; Frostline's bosses keep the usual boss range.
const BOT_SKILL := [Vector2(0.3, 0.5), Vector2(0.4, 0.6), Vector2(0.5, 0.7)]
## The cold (DESIGN.md "Frostline"): body heat lost a second in the open in
## each zone, from the river mouth to the glacier head, and how much faster
## it goes high up in the wind (on a rim or in the air, `EXPOSED_OVER`
## metres over the valley floor).
const ZONE_COLD := [0.7, 1.0, 1.4]
const EXPOSED_OVER := 22.0
const EXPOSED_MULT := 1.5
## Inside the Engine (DESIGN.md "The Engine's inside") the wind is gone but
## the cold is not: the Drum Hall is gentler than the glacier head outside,
## and it gets colder the deeper you go (`MapScript.engine_depth`: the hall,
## the Shaft and the Coil Galleries, the Descent, then the Heart).
const ENGINE_COLD := [0.8, 1.1, 1.3, 1.5]
## Wading the Coil Galleries' coolant channel: bitter, so the dry walks round
## it are worth taking.
const COOLANT_COLD := 2.6
## How much grip a wheel gets on Frostline's snow and on its bare ice
## (`WorldDef.surface_grip`): wheels break loose and slide.
const SNOW_GRIP := 0.75
const ICE_GRIP := 0.35

## The Wardens are the Engine's defence grid, still running (DESIGN.md
## "Frostline", step 7): one hurt in a fight it survives calls every Warden
## within this many metres (`WorldDef.linked_factions`).
const GRID_LINK := 60.0
## A valley pocket wakes when a player comes this near (metres): past a
## Warden's sight (`WARDEN_SIGHT`), so a post is already standing when you
## first see it.
const POCKET_WAKE := 150.0
## The grid's boss, the Engine Sentinel, guards the hatch: a Warden three
## metres tall with a lance that must hold its tracking beam on you before it
## fires, and its heat vent in its back (hits there do `SENTINEL_REAR`
## times). Made for one player; each other player near it makes it tougher
## by `SENTINEL_PARTY` (`WorldDef.boss_party_scale`).
const SENTINEL_HEIGHT := 3.2
const SENTINEL_HEALTH := 480.0
const SENTINEL_ARMOR := 40.0
const SENTINEL_REAR := 2.0
const SENTINEL_LOCK := 1.2
const SENTINEL_DAMAGE := 30.0
const SENTINEL_INTERVAL := 0.6
const SENTINEL_PARTY := 0.6
## The Heart Warden (DESIGN.md "The Engine's inside", Caleb's call), the
## keeper of the Engine's Heart: taller than the Sentinel and far tougher,
## its back the weak spot (`HEART_REAR`). While it is above half health it
## calls Wardens out of the wall sockets; below, the core thaws and the
## pylons vent coolant across the floor (`WorldDef.keeper_*`, the map's
## "boss_socket" and "purge" markers). Made for one player, it scales with
## company like the Sentinel.
const HEART_HEIGHT := 4.2
const HEART_HEALTH := 620.0
const HEART_ARMOR := 50.0
const HEART_REAR := 2.5
const HEART_LOCK := 0.9
const HEART_DAMAGE := 21.0
const HEART_INTERVAL := 0.55
## Its vault (Caleb's call): every player who fought it gets a share of its
## own, the best parts, the Mk3 materials, upgrade data, a chance at an
## expedition blueprint and, rarely, an artifact: rarer than an Ashfront
## warlord's (`WorldDef.warlord_artifact_chance`), so the war stays the
## faster route.
const VAULT_TABLE := [
	{"id": "engine_coil", "weight": 30.0},
	{"id": "glacial_alloy", "weight": 24.0},
	{"id": "cryo_core", "weight": 20.0},
	{"id": "reactor_core", "weight": 8.0},
	{"id": "alloy_ingot", "weight": 10.0},
	{"id": "medkit", "weight": 8.0},
]
const VAULT_ITEMS := Vector2i(3, 4)
const VAULT_DATA := Vector2i(1, 2)
const VAULT_BLUEPRINT := 0.3
const VAULT_BLUEPRINTS := ["bp_frame_thermal", "bp_grip_glacier"]
const VAULT_ARTIFACT := 0.05
## The chance a share of the vault holds the Heart Warden armor paint,
## earned nowhere else (Caleb's call: special paints from the hardest
## fights).
const VAULT_PAINT := 0.1
## Whiteouts (DESIGN.md "Frostline", step 5): blizzards that come down the
## valley one at a time on the shared weather (`WorldDef.weather_*`), most
## of them off the glacier (a cold wind falls downhill), now and then one
## up from the frozen sea. `WHITEOUT_DOWN` is the share that come down.
const WHITEOUT_DOWN := 0.75
## How far the valley runs, mouth to head, on the map's z.
const VALLEY_FROM_Z := 300.0
const VALLEY_TO_Z := -300.0
## The slow route to the war's blueprints (DESIGN.md section 10, Caleb's
## call): a Frostline warlord (the Sentinel, or an event's) carries one now
## and then, rarer than in Ashfront, and a piece of upgrade data.
const WARLORD_BLUEPRINT := 0.15
## And the relay on the Engine's back, the hardest cache to reach: now and
## then one of the war's blueprints too (`roll_crafting_loot` leaves the
## expedition's own out: those are in its table already).
const RELAY_BLUEPRINT := 0.06
## The expedition's own contracts (DESIGN.md "Frostline", step 7): on the
## board beside the jobs that count anywhere, counted only here. Every one
## can be done alone. The weeklies are the long expeditions, and like every
## weekly they pay a blueprint the account does not know yet: the contract
## half of the slow route to the war's blueprints.
const CONTRACTS := {
	"frost_relay": {"title": "Loot the relay on the Engine's back", "stat": "cache:relay", "goal": 1,
			"kind": "daily", "scrip": 220},
	"frost_engine": {"title": "Loot 2 caches inside the Engine", "stat": "cache:engine", "goal": 2,
			"kind": "daily", "scrip": 200},
	"frost_rims": {"title": "Loot 3 caches up on the rims", "stat": "cache:rooftop", "goal": 3,
			"kind": "daily", "scrip": 180},
	"frost_grid": {"title": "Bring down 6 Wardens", "stat": "kills:warden", "goal": 6, "kind": "daily",
			"scrip": 160},
	"frost_cores": {"title": "Bring home 3 Cryo Cores", "stat": "item:cryo_core", "goal": 3, "kind": "daily",
			"scrip": 170},
	"frost_sentinel": {"title": "Bring down the Engine Sentinel twice", "stat": "boss:sentinel", "goal": 2,
			"kind": "weekly", "scrip": 900, "items": ["upgrade_data"], "reward_tag": "blueprint"},
	"frost_coils": {"title": "Bring home 3 Engine Coils", "stat": "item:engine_coil", "goal": 3,
			"kind": "weekly", "scrip": 850, "items": ["upgrade_data"], "reward_tag": "blueprint"},
}

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

## Inside the Engine: what crafting runs on, Engine Coils most of all, the
## deeper the better (DESIGN.md "The Engine's inside").
const ENGINE_TABLE := [
	{"id": "engine_coil", "weight": 26.0},
	{"id": "glacial_alloy", "weight": 20.0},
	{"id": "cryo_core", "weight": 20.0},
	{"id": "frost_cryo_cell", "weight": 16.0},
	{"id": "alloy_ingot", "weight": 12.0},
	{"id": "power_cell", "weight": 10.0},
	{"id": "medkit", "weight": 8.0},
	{"id": "upgrade_data", "weight": 3.0},
	{"id": "bp_frame_thermal", "weight": 1.5},
	{"id": "bp_grip_glacier", "weight": 1.5},
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
	# The Glacier (DESIGN.md "Planet kit"): its sky, ground and horizon. Its
	# rule defaults are only a start; the cold, the shot's carry and the
	# grip below and in `surface_grip` are Frostline's own.
	take_planet("glacier")
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
	# Packs of Ferals on the floor and Wardens on the posts (DESIGN.md "The
	# enemy AI pass", step 2), as encounter pockets (DESIGN.md "Enemy
	# layout"): each wakes as a player comes within sight range, so the
	# budget is spent where someone is. No army walks the valley.
	bot_count = 0
	pocket_wake = POCKET_WAKE
	# The Engine's levels go down under the valley floor: the world ends
	# below the Descent's foot.
	void_y = MapScript.engine_bed() + MapScript.ENGINE_AXIS + MapScript.DESCENT_FLOOR - 15.0
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
	# The defence grid: Wardens call each other to a fight, and the Engine
	# Sentinel at the hatch is made for one player and scales up with more.
	linked_factions = {"warden": GRID_LINK}
	boss_party_scale = SENTINEL_PARTY
	warlord_blueprint_chance = WARLORD_BLUEPRINT
	warlord_upgrade_data = 1
	# Its own contracts, counted only here.
	contract_tag = "expedition"
	# Whiteouts: a blizzard fills the valley wall to wall as it comes
	# through. Sight closes in, the wind swallows gunshots (the still air's
	# carry is gone), gusts throw flight rigs about, the cold bites twice
	# as hard and the snow fills in every trail it passes over.
	weather_kind = "snow"
	weather_name = "Whiteout"
	weather_radius = 120.0
	weather_speed = 3.5
	weather_ramp = 45.0
	weather_gap = Vector2(300.0, 600.0)
	weather_first = Vector2(90.0, 240.0)
	weather_sight = 0.5
	weather_carry = 0.4
	weather_gust = 8.0
	weather_cold = 2.0
	weather_wipes_tracks = true
	weather_field = 300.0


## A whiteout runs the length of the valley, not across it: most come down
## off the glacier toward the river mouth, some up from the sea, each
## wandering a little across the floor as it goes.
func weather_path(rng: RandomNumberGenerator) -> Array:
	var reach := weather_radius
	var head := Vector3(rng.randf_range(-20.0, 20.0), 0.0, VALLEY_TO_Z - reach)
	var mouth := Vector3(rng.randf_range(-30.0, 30.0), 0.0, VALLEY_FROM_Z + reach)
	if rng.randf() < WHITEOUT_DOWN:
		return [head, mouth]
	return [mouth, head]


func register_items() -> void:
	ItemDB.register("frost_cryo_cell", "Cryo Cell", ItemDB.Rarity.UNCOMMON, 140, ["material"], {},
			"Station coolant cartridge. Still frosted over.")
	ItemDB.register("frost_signal_core", "Signal Core", ItemDB.Rarity.EPIC, 1200, ["material"], {},
			"The heart of the relay mast. Hums when you hold it.")
	ItemDB.register("frost_ice_axe", "Ice Axe", ItemDB.Rarity.RARE, 750, ["weapon", "melee", "one_handed", "axe"],
			{"light_damage": 32.0, "heavy_damage": 82.0, "heavy_lunge": 12.0, "slam_damage": 70.0,
			"reach": 2.9, "light_windup": 0.15, "light_recover": 0.34, "heavy_windup": 0.46,
			"light_stamina": 12.0, "heavy_stamina": 30.0, "swing_style": "chop", "swing_scale": 0.9,
			"ability": "guard_hook", "ability_windup": 0.45, "ability_recover": 0.35, "ability_radius": 3.0,
			"ability_damage": 8.0, "ability_knock": 8.0, "ability_cooldown": 12.0, "ability_stamina": 18.0},
			"Long heavy lunge and a hard dive slam. Built for closing distance on open ice.")


func create_map() -> Node3D:
	var map := MapScript.new()
	map.planet = planet_type()
	return map


func prepare_map() -> void:
	var map: Node3D = MapScript.new()
	map.call("prepare_shared")
	map.free()


## The zones run along the valley: the river mouth is the outer ring, the
## Narrows and the lake the middle, the glacier head and the Engine the core.
func bot_skill_range(bot: Actor, warlord: bool) -> Vector2:
	if warlord:
		return super(bot, warlord)
	return BOT_SKILL[clampi(int(bot.get_meta("zone", 1)), 0, 2)]


func zone_at(pos: Vector3) -> int:
	if pos.z <= MapScript.CORE_FROM_Z:
		return 2
	if pos.z <= MapScript.MIDDLE_FROM_Z:
		return 1
	return 0


## The Engine's inside is out of the wind and the weather.
func sheltered_at(pos: Vector3) -> bool:
	return MapScript.inside_engine(pos)


## Colder further up the valley, and colder still up in the wind. Inside the
## Engine, out of the wind, colder the deeper you go.
func cold_at(pos: Vector3) -> float:
	if MapScript.inside_engine(pos):
		if MapScript.on_coolant(pos):
			return COOLANT_COLD
		return ENGINE_COLD[clampi(MapScript.engine_depth(pos), 0, ENGINE_COLD.size() - 1)]
	var rate: float = ZONE_COLD[clampi(zone_at(pos), 0, 2)]
	if pos.y - MapScript.floor_at(pos.z) > EXPOSED_OVER:
		rate *= EXPOSED_MULT
	return rate


## The middle of the frozen lake, where the ice is thin.
func thin_ice_at(pos: Vector3) -> bool:
	return MapScript.lake_reach(pos.x, pos.z) < MapScript.THIN_ICE and pos.y < MapScript.floor_at(pos.z) + 1.0


## Wheels slide on Frostline: packed snow everywhere, and the frozen river,
## the lake and the frozen sea past the mouth are bare ice.
func surface_grip(pos: Vector3) -> float:
	var floor_y := MapScript.floor_at(pos.z)
	if pos.y > floor_y + 1.5:
		return SNOW_GRIP
	var across := absf(pos.x - MapScript.centre(pos.z))
	if MapScript.lake_reach(pos.x, pos.z) < 1.0 or (pos.z > -40.0 and across < 10.0) or pos.z > 296.0:
		return ICE_GRIP
	return SNOW_GRIP


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
		"engine":
			table = ENGINE_TABLE
			count = rng.randi_range(2, 3)
		"relay":
			var haul: Array[String] = []
			for i in rng.randi_range(3, 4):
				haul.append(ItemDB.roll(RELAY_TABLE, rng))
			haul.append_array(roll_crafting_loot(rng, RELAY_BLUEPRINT, 0))
			return haul
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


func contract_jobs() -> Dictionary:
	return CONTRACTS


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


## Station automata: slow on their feet, long-sighted down a narrow cone,
## and slow to fire (a beam holds first), then accurate.
func _make_warden(bot: Actor, rng: RandomNumberGenerator) -> void:
	bot.faction = "warden"
	bot.display_name = "Warden"
	bot.set_meta("look", "sentinel")
	_paint(bot, Color(0.55, 0.8, 0.95))
	var tier := clampi(int(bot.get_meta("zone", 1)), 0, 2)
	bot.walk_speed = 3.6
	bot.sprint_speed = 5.2
	bot.health.max_health = WARDEN_HEALTH[tier]
	bot.health.health = WARDEN_HEALTH[tier]
	bot.health.set_armor(WARDEN_ARMOR[tier])
	bot.set_meta("sight", WARDEN_SIGHT)
	bot.set_meta("fov", WARDEN_FOV)
	bot.set_meta("reach", WARDEN_REACH)
	bot.set_meta("far_notice", WARDEN_FAR_NOTICE)
	bot.set_meta("lock_time", WARDEN_LOCK)
	bot.set_meta("aim_turn", WARDEN_TURN)
	bot.set_meta("burst", WARDEN_BURST)
	bot.set_meta("slots", WARDEN_SLOTS[tier])
	bot.set_meta("holds_turn", true)
	for item in roll_loot("warden", rng):
		bot.inventory.add_item(item)
	var gun := Gun.new()
	gun.display_name = "Warden Repeater"
	gun.damage = WARDEN_DAMAGE[tier]
	gun.spread_deg = WARDEN_SPREAD
	gun.fire_interval = WARDEN_INTERVAL
	gun.max_range = 160.0
	gun.reserve_ammo = 400
	gun.headshot_mult = 1.0
	bot.equip_weapon(gun)


## A warlord: the Engine Sentinel at the hatch (its "spawn_boss" marker's
## meta "boss"), else an event's warlord as anywhere. Runs on clients too,
## so it is free of randomness.
func make_warlord(bot: Actor) -> void:
	if bot.get_meta("boss", "") == MapScript.HEART_KEEPER:
		_make_heart_warden(bot)
		return
	if bot.get_meta("boss", "") != "sentinel":
		super(bot)
		return
	bot.display_name = "Engine Sentinel"
	bot.set_meta("look", "colossus")
	bot.set_stand_height(SENTINEL_HEIGHT, 0.3)
	bot.walk_speed = 3.0
	bot.sprint_speed = 3.6
	bot.health.max_health = SENTINEL_HEALTH
	bot.health.health = SENTINEL_HEALTH
	bot.health.set_armor(SENTINEL_ARMOR)
	bot.rear_damage_mult = SENTINEL_REAR
	# A heavy machine: it comes round slowly but leads a flier well, and its
	# beam must hold you before the lance fires, so breaking the line is the
	# answer (`BotBrain.lock_time`).
	bot.set_meta("aim_turn", 80.0)
	bot.set_meta("track_lag", 0.1)
	bot.set_meta("air_error", 0.6)
	bot.set_meta("lock_time", SENTINEL_LOCK)
	var lance := bot.get_active_weapon() as Gun
	if lance:
		lance.display_name = "Grid Lance"
		lance.damage = SENTINEL_DAMAGE
		lance.spread_deg = 0.35
		lance.fire_interval = SENTINEL_INTERVAL
		lance.max_range = 120.0
		lance.mag_size = 10
		lance.ammo_in_mag = 10
		lance.reserve_ammo = 999


func boss_back_news(bot: Actor, _where: String) -> String:
	if bot != null and bot.get_meta("boss", "") == "sentinel":
		return "The Engine Sentinel stands guard at the hatch again"
	if bot != null and bot.get_meta("boss", "") == MapScript.HEART_KEEPER:
		return "The Heart Warden wakes in the Engine's Heart again"
	return super(bot, _where)


## The Heart Warden, from the Sentinel's machine. Runs on clients too, so it
## is free of randomness.
func _make_heart_warden(bot: Actor) -> void:
	bot.display_name = "Heart Warden"
	# Its own machine to look at, not the Sentinel grown taller: dark plate,
	# its core bared and a crown of vents (`Look` "core_colossus").
	bot.set_meta("look", "core_colossus")
	_paint(bot, Color(0.4, 0.85, 1.0))
	bot.set_stand_height(HEART_HEIGHT, 0.35)
	bot.walk_speed = 2.6
	bot.sprint_speed = 3.2
	bot.health.max_health = HEART_HEALTH
	bot.health.health = HEART_HEALTH
	bot.health.set_armor(HEART_ARMOR)
	bot.rear_damage_mult = HEART_REAR
	bot.set_meta("aim_turn", 70.0)
	bot.set_meta("track_lag", 0.12)
	bot.set_meta("air_error", 0.7)
	bot.set_meta("lock_time", HEART_LOCK)
	var lance := bot.get_active_weapon() as Gun
	if lance:
		lance.display_name = "Core Lance"
		lance.damage = HEART_DAMAGE
		lance.spread_deg = 0.4
		lance.fire_interval = HEART_INTERVAL
		lance.max_range = 80.0
		lance.mag_size = 12
		lance.ammo_in_mag = 12
		lance.reserve_ammo = 999


func roll_vault(_kind: String, rng: RandomNumberGenerator) -> Array[String]:
	var out: Array[String] = []
	for i in rng.randi_range(VAULT_ITEMS.x, VAULT_ITEMS.y):
		out.append(ItemDB.roll(VAULT_TABLE, rng))
	for i in rng.randi_range(VAULT_DATA.x, VAULT_DATA.y):
		out.append("upgrade_data")
	if rng.randf() < VAULT_BLUEPRINT:
		out.append(VAULT_BLUEPRINTS[rng.randi() % VAULT_BLUEPRINTS.size()])
	var relic := roll_artifact(rng, VAULT_ARTIFACT)
	if relic != "":
		out.append(relic)
	if rng.randf() < VAULT_PAINT:
		out.append("paint_warden")
	return out


func keeper_news(_bot: Actor, phase: int) -> String:
	if phase == 2:
		return "The core thaws: the pylons are venting coolant, watch the floor"
	if phase == 0:
		return "The Heart Warden has fallen: its vault is open to all who fought it, and the deep beacon is lit"
	return ""


## Fast, fragile pack hunters with hooked blades.
func _make_feral(bot: Actor, rng: RandomNumberGenerator) -> void:
	bot.faction = "feral"
	bot.display_name = "Feral Stalker"
	bot.set_meta("look", "feral")
	_paint(bot, Color(0.18, 0.2, 0.26))
	var tier := clampi(int(bot.get_meta("zone", 1)), 0, 2)
	bot.walk_speed = 6.0
	bot.sprint_speed = 9.0
	bot.health.max_health = FERAL_HEALTH[tier]
	bot.health.health = FERAL_HEALTH[tier]
	# A pack hunter (`BotBrain`): it follows fresh tracks, goes for the
	# shivering, and keeps out of the warm.
	bot.set_meta("tracker", FERAL_TRACKS)
	bot.set_meta("preys_on_cold", true)
	bot.set_meta("shuns_warmth", true)
	for item in roll_loot("feral", rng):
		bot.inventory.add_item(item)
	var blade := MeleeWeapon.new()
	blade.display_name = "Hooked Blade"
	blade.light_damage = FERAL_DAMAGE[tier]
	blade.light_windup = FERAL_WINDUP[tier]
	blade.light_stamina = 0.0
	blade.reach = 2.4
	bot.equip_weapon(blade)


func _paint(bot: Actor, color: Color) -> void:
	bot.body_color = color
	if bot.body_mesh:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		bot.body_mesh.material_override = mat
