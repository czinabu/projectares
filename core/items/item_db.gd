extends Node
## Autoload `ItemDB`: every item definition in the game.
##
## Items are plain data with tags. Worlds decide which tags they allow, which is
## what lets one stash work across very different worlds later.

enum Rarity { COMMON, UNCOMMON, RARE, EPIC, RELIC }

const RARITY_NAMES := ["Common", "Uncommon", "Rare", "Epic", "Relic"]
const RARITY_COLORS := [
	Color(0.75, 0.75, 0.75),
	Color(0.35, 0.8, 0.4),
	Color(0.3, 0.55, 1.0),
	Color(0.7, 0.35, 0.95),
	Color(1.0, 0.65, 0.15),
]

## How much each Mk tier adds to a flight rig's strength (Caleb's call:
## about 15% a tier, to the strength only, never the weakness). Mk2 is
## Mk1 times this, Mk3 times it twice. See `_rig_tier`.
const RIG_TIER_STEP := 1.15

var _items := {}


func _ready() -> void:
	# Free scrap kit. Tagged "starter": every player owns one of each to
	# equip (`StashRules.free_items`), and it can never be stashed, so it
	# cannot be farmed.
	register("rifle_scrap", "Scrap Rifle", Rarity.COMMON, 0, ["weapon", "firearm", "rifle", "starter"], {},
			"Worn automatic rifle.")
	register("blade_scrap", "Scrap Blade", Rarity.COMMON, 0, ["weapon", "melee", "one_handed", "blade", "starter"], {},
			"A sharpened strip of plating.")
	register("pistol_service", "Service Pistol", Rarity.COMMON, 0,
			["weapon", "firearm", "sidearm", "pistol", "starter"],
			{"semi_auto": true, "damage": 22.0, "fire_interval": 0.16, "mag_size": 12, "ammo_in_mag": 12,
			"reserve_ammo": 60, "reload_time": 1.1, "spread_deg": 0.6, "bloom_per_shot": 0.5,
			"recoil_kick_deg": 0.7, "max_range": 90.0},
			"Reliable semi-auto sidearm. Accurate, and quick to reload.")
	register("jetpack_mk1", "Mk1 Jetpack", Rarity.COMMON, 0, ["flight_rig", "starter"], JETPACK_MK1.duplicate(),
			"Height and hover. Climb to 40 m and hover 8 s to fight from above with steady aim. Slow across the map, a boost overheats it in seconds, clumsy under a roof, and loud and bright on scans and thermal.")
	register("plate_light", "Scrap Plate", Rarity.COMMON, 0, ["armor", "frame_light", "starter"],
			{"armor": 30.0}, "30 armor.")
	register("field_dressing", "Field Dressing", Rarity.COMMON, 0, ["consumable", "heal", "starter"],
			{"heal": 30.0}, "Heals 30.")

	# Firearms
	register("rifle_carbine", "Ashfront Carbine", Rarity.UNCOMMON, 450, ["weapon", "firearm", "rifle", "vendor"],
			{"damage": 24.0, "fire_interval": 0.1, "spread_deg": 0.9, "reserve_ammo": 150},
			"Reliable automatic. Harder hitting and tighter than the scrap rifle.")
	register("smg_stinger", "Stinger SMG", Rarity.UNCOMMON, 420, ["weapon", "firearm", "smg", "vendor"],
			{"damage": 14.0, "fire_interval": 0.065, "mag_size": 40, "ammo_in_mag": 40,
			"reserve_ammo": 200, "spread_deg": 1.9, "recoil_kick_deg": 0.3, "max_range": 80.0},
			"Very fast fire and light recoil. Best up close.")
	register("dmr_longshot", "Longshot DMR", Rarity.RARE, 900, ["weapon", "firearm", "marksman"],
			{"damage": 55.0, "fire_interval": 0.42, "mag_size": 12, "ammo_in_mag": 12,
			"reserve_ammo": 60, "spread_deg": 0.25, "recoil_kick_deg": 1.7, "bloom_per_shot": 0.9,
			"max_range": 220.0},
			"Slow, precise, and heavy hitting. Two shots drop most targets.")
	register("shotgun_breacher", "Breacher Shotgun", Rarity.RARE, 850, ["weapon", "firearm", "shotgun"],
			{"damage": 11.0, "pellets": 8, "fire_interval": 0.75, "mag_size": 6, "ammo_in_mag": 6,
			"reserve_ammo": 36, "spread_deg": 4.5, "recoil_kick_deg": 2.4, "reload_time": 2.4,
			"max_range": 40.0},
			"Eight pellets a shot. Devastating in reach of a blade.")

	# Sidearms: worn on the hip and drawn when the primary runs dry.
	register("pistol_machine", "Hornet Machine Pistol", Rarity.UNCOMMON, 380,
			["weapon", "firearm", "sidearm", "machine_pistol", "vendor"],
			{"damage": 9.0, "fire_interval": 0.055, "mag_size": 20, "ammo_in_mag": 20, "reserve_ammo": 100,
			"reload_time": 1.4, "spread_deg": 2.6, "bloom_per_shot": 0.45, "max_bloom": 4.0,
			"recoil_kick_deg": 0.35, "max_range": 45.0},
			"Full-auto spray. Deadly up close, useless at range.")
	register("pistol_hand_cannon", "Warden Hand Cannon", Rarity.RARE, 750,
			["weapon", "firearm", "sidearm", "hand_cannon"],
			{"semi_auto": true, "damage": 48.0, "headshot_mult": 2.0, "fire_interval": 0.55, "mag_size": 6,
			"ammo_in_mag": 6, "reserve_ammo": 30, "reload_time": 2.2, "spread_deg": 0.4,
			"bloom_per_shot": 1.2, "recoil_kick_deg": 2.6, "max_range": 110.0},
			"Slow, heavy revolver. Headshots hit twice as hard.")

	# Power weapons: found, never bought or brought. They lie on racks in
	# the world (`PowerArmory`) and are scanned into the watch when taken.
	# A few shots each; one that runs dry is thrown away. Tagged "power" so
	# they never reach a stash or a bag.
	register("power_rail_lance", "Rail Lance", Rarity.EPIC, 0, ["weapon", "firearm", "power", "railgun"],
			{"damage": 120.0, "charge_time": 0.85, "fire_interval": 0.6, "mag_size": 4, "ammo_in_mag": 4,
			"reserve_ammo": 0, "spread_deg": 0.0, "bloom_per_shot": 0.0, "pierce": 3, "wall_pierce": 2,
			"max_range": 300.0, "recoil_kick_deg": 4.0, "beam_time": 1.4, "damage_kind": "rail",
			"tracer_color": Color(0.35, 0.95, 1.0), "shot_sound": "rail"},
			"Mag-rail. Hold to charge: the slug goes through three bodies and two walls, and its beam hangs in the air and gives you away. 4 shots.")
	register("power_helion", "Helion Plasma Launcher", Rarity.EPIC, 0, ["weapon", "firearm", "power", "launcher"],
			{"projectile": "rocket", "projectile_speed": 34.0, "damage": 40.0, "splash_radius": 5.5,
			"splash_damage": 110.0, "fire_interval": 1.0, "mag_size": 1, "ammo_in_mag": 1, "reserve_ammo": 3,
			"reload_time": 1.8, "spread_deg": 0.3, "bloom_per_shot": 0.0, "recoil_kick_deg": 3.0,
			"heat_seek_cone": 22.0, "damage_kind": "plasma", "tracer_color": Color(1.0, 0.45, 0.15),
			"shot_sound": "plasma_shot"},
			"Plasma rockets that burst over a wide area. Aimed near a thrusting jetpack, they lock onto its heat. 4 shots.")
	register("power_arc_mortar", "Arc Mortar", Rarity.EPIC, 0, ["weapon", "firearm", "power", "grenade_launcher"],
			{"projectile": "grenade", "projectile_speed": 18.0, "projectile_gravity": 1.0, "bounces": 3,
			"fuse_time": 1.8, "damage": 30.0, "splash_radius": 5.0, "splash_damage": 85.0, "fire_interval": 0.55,
			"mag_size": 6, "ammo_in_mag": 6, "reserve_ammo": 0, "spread_deg": 0.4, "bloom_per_shot": 0.0,
			"recoil_kick_deg": 2.0, "damage_kind": "arc", "tracer_color": Color(0.7, 0.45, 1.0),
			"shot_sound": "arc_shot"},
			"Lobs bouncing arc charges over cover. They burst on a body or when the fuse runs out. 6 shots.")
	register("power_storm_cannon", "Storm Cannon", Rarity.EPIC, 0, ["weapon", "firearm", "power", "minigun"],
			{"spin_up": 0.9, "spin_move_mult": 0.55, "damage": 13.0, "fire_interval": 0.045, "mag_size": 180,
			"ammo_in_mag": 180, "reserve_ammo": 0, "spread_deg": 2.2, "bloom_per_shot": 0.05, "max_bloom": 1.5,
			"recoil_kick_deg": 0.15, "max_range": 110.0, "damage_kind": "plasma",
			"tracer_color": Color(1.0, 0.3, 0.85), "shot_sound": "pulse"},
			"Rotary pulse cannon. Slow to spin up, slows you right down, shreds anything in front of it. 180 shots.")

	# Attachments for primaries. Each fits one slot on the gun (its second tag:
	# optic, muzzle, grip or magazine) and fits every primary. `Gun.fit` reads
	# the stats: "mult" scales the gun's own tuning values, "zoom" is how far an
	# optic magnifies while aiming, "quiet" hides the shot, and "model" picks the
	# shape built on the gun. Every one trades something away.
	_attachment("optic_reflex", "Reflex Sight", Rarity.UNCOMMON, 260, "optic", true,
			{"model": "reflex", "zoom": 1.35, "mult": {"ads_spread_mult": 0.8}},
			"Red dot in a small window. A little zoom, and steadier when aimed.")
	_attachment("optic_scope", "4x Ranger Scope", Rarity.RARE, 700, "optic", false,
			{"model": "scope", "zoom": 2.6, "lens": true, "mult": {"ads_spread_mult": 0.55, "spread_deg": 1.15}},
			"Four times zoom and very steady when aimed. Looser from the hip.")
	_attachment("optic_longscope", "8x Longscope", Rarity.EPIC, 1400, "optic", false,
			{"model": "longscope", "zoom": 4.6, "lens": true, "mult": {"ads_spread_mult": 0.4, "spread_deg": 1.3}},
			"Eight times zoom for picking off targets across the map. Clumsy up close.")
	_attachment("muzzle_compensator", "Compensator", Rarity.UNCOMMON, 240, "muzzle", true,
			{"model": "compensator", "mult": {"recoil_kick_deg": 0.7, "recoil_side_deg": 0.75, "spread_deg": 1.08}},
			"Vents gas upward: much less kick, slightly wider spread.")
	_attachment("muzzle_booster", "Muzzle Booster", Rarity.UNCOMMON, 300, "muzzle", true,
			{"model": "booster", "mult": {"fire_interval": 0.88, "recoil_kick_deg": 1.15, "bloom_per_shot": 1.15}},
			"Cycles the action faster. Kicks harder for it.")
	_attachment("muzzle_suppressor", "Suppressor", Rarity.RARE, 650, "muzzle", false,
			{"model": "suppressor", "quiet": true, "mult": {"damage": 0.92, "max_range": 0.9}},
			"No tracers, no flash and a much quieter shot. Costs a little damage and range.")
	_attachment("grip_vertical", "Vertical Grip", Rarity.UNCOMMON, 220, "grip", true,
			{"model": "vertical_grip", "mult": {"recoil_kick_deg": 0.8, "max_bloom": 0.8, "reload_time": 1.06}},
			"Holds a spray down. Slightly slower reloads.")
	_attachment("grip_angled", "Angled Grip", Rarity.UNCOMMON, 220, "grip", true,
			{"model": "angled_grip", "mult": {"bloom_recovery": 1.5, "spread_deg": 0.9, "recoil_kick_deg": 1.05}},
			"Tighter shots and spread that settles fast. A touch more kick.")
	_attachment("mag_extended", "Extended Mag", Rarity.UNCOMMON, 280, "magazine", true,
			{"model": "extended_mag", "mult": {"mag_size": 1.5, "reload_time": 1.15}},
			"Half again as many rounds. Slower to reload.")
	_attachment("mag_quick", "Quick Mag", Rarity.UNCOMMON, 260, "magazine", true,
			{"model": "quick_mag", "mult": {"reload_time": 0.65, "mag_size": 0.85}},
			"Pull tabs and a flared well: reloads a third faster, holds a few less.")
	_attachment("mag_drum", "Drum Mag", Rarity.RARE, 750, "magazine", false,
			{"model": "drum", "mult": {"mag_size": 2.2, "reload_time": 1.45, "spread_deg": 1.1}},
			"More than twice the rounds. Heavy: slow reloads and a wider spread.")

	# Melee. Every melee item is tagged "one_handed" or "two_handed": light
	# one-handers move faster, two-handers slower but stagger and break armor
	# (`MeleeWeapon`), and the hands hold it that way (`Look.is_two_handed`).
	register("blade_arc", "Arc Blade", Rarity.RARE, 800, ["weapon", "melee", "one_handed", "blade"],
			{"light_damage": 34.0, "heavy_damage": 72.0, "light_recover": 0.22, "parry_window": 0.26,
			"swing_style": "cut"},
			"Faster swings and a more forgiving parry.")
	register("hammer_breaker", "Breaker Hammer", Rarity.UNCOMMON, 500, ["weapon", "melee", "two_handed", "hammer", "vendor"],
			{"light_damage": 42.0, "heavy_damage": 95.0, "light_windup": 0.22, "light_recover": 0.45,
			"heavy_windup": 0.55, "light_stamina": 16.0, "heavy_stamina": 36.0, "reach": 3.1, "swing_style": "chop",
			"slam_damage": 85.0, "slam_radius": 5.5},
			"Slow and brutal. Its dive slam hits a wide area.")
	register("knife_gutter", "Gutter Knife", Rarity.COMMON, 250, ["weapon", "melee", "one_handed", "knife", "vendor"],
			{"light_damage": 17.0, "heavy_damage": 40.0, "reach": 2.1, "arc_deg": 90.0,
			"light_windup": 0.08, "light_recover": 0.15, "heavy_windup": 0.25, "heavy_recover": 0.35,
			"heavy_lunge": 12.0, "light_stamina": 6.0, "heavy_stamina": 18.0, "parry_window": 0.16,
			"slam_damage": 35.0, "slam_radius": 3.0, "backstab_mult": 2.2, "backstab_arc_deg": 180.0,
			"move_mult": 1.15, "heavy_style": "thrust", "swing_scale": 0.7},
			"Very quick, short and light. Cuts from behind do more than double, so get round their guard.")
	register("axe_splitter", "Splitter Axe", Rarity.UNCOMMON, 550, ["weapon", "melee", "one_handed", "axe", "vendor"],
			{"light_damage": 33.0, "heavy_damage": 85.0, "reach": 2.6, "light_windup": 0.16,
			"light_recover": 0.34, "heavy_windup": 0.48, "light_stamina": 13.0, "heavy_stamina": 32.0,
			"guard_crush": 2.5, "swing_style": "chop", "swing_scale": 0.9},
			"Chops through guards. Blocking it costs two and a half times the stamina, so a few hits break a guard.")
	register("spear_lancer", "Lancer Spear", Rarity.RARE, 900, ["weapon", "melee", "two_handed", "spear"],
			{"light_damage": 27.0, "heavy_damage": 62.0, "reach": 4.1, "arc_deg": 40.0,
			"vertical_reach": 3.8, "close_range": 1.5, "close_mult": 0.5, "light_windup": 0.14,
			"light_recover": 0.3, "heavy_windup": 0.42, "heavy_lunge": 6.0, "heavy_stagger": 0.6,
			"slam_damage": 40.0, "slam_radius": 3.5, "swing_style": "thrust"},
			"The longest reach of any blade, and it pokes fliers overhead. Narrow thrusts, half damage up close, and a heavy thrust staggers.")

	# Armor frames
	register("frame_runner", "Runner Frame", Rarity.UNCOMMON, 400, ["armor", "frame_light", "vendor"],
			{"armor": 45.0, "speed_mult": 1.08, "heat_mult": 0.8, "heat_signature": 0.7},
			"Light: 45 armor, 8% faster, jetpack runs cooler. Dim on thermal.")
	register("frame_trooper", "Trooper Frame", Rarity.UNCOMMON, 450, ["armor", "frame_medium", "vendor"],
			{"armor": 85.0},
			"Medium: 85 armor, no penalties.")
	register("frame_bulwark", "Bulwark Frame", Rarity.RARE, 900, ["armor", "frame_heavy"],
			{"armor": 125.0, "speed_mult": 0.86, "heat_mult": 1.25, "heat_signature": 1.3},
			"Heavy: 125 armor, 14% slower, wings and boots run hotter (jetpacks carry it). Bright on thermal.")

	# Flight rigs (the Mk1 numbers are `JETPACK_MK1`, `BOOTS_MK1` and
	# `WINGS_MK1` at the bottom of this file). Each comes in tiers: a higher
	# Mk adds about 15% to the rig's strength only (`_rig_tier`). Only Mk1
	# drops or is sold; Mk2 and up are crafted from blueprints (DESIGN.md
	# section 10) and are at stake like any gear.
	_rig_tier("jetpack_mk2", "Mk2 Jetpack", Rarity.RARE, 1000, "jetpack_mk1", 2,
			"Longer hover and more heat to burn, and a higher ceiling. Still slow across the map, loud and bright.")
	_rig_tier("jetpack_mk3", "Mk3 Jetpack", Rarity.EPIC, 2200, "jetpack_mk1", 3,
			"The longest hover and the highest ceiling of any rig. Still slow across the map, loud and bright.")
	register("boots_thruster", "Mk1 Thruster Boots", Rarity.UNCOMMON, 1000, ["flight_rig", "vendor"], BOOTS_MK1.duplicate(),
			"Ground agility and stealth. 15% faster on foot, no fall damage, and 4 charges for kicks and dashes, each dash a brief window where rounds only graze. Quiet and dim on scans, and they work indoors. Top out at 10 m and are slow over open ground.")
	_rig_tier("boots_thruster_mk2", "Mk2 Thruster Boots", Rarity.RARE, 1300, "boots_thruster", 2,
			"One more charge and a faster refill. Still top out at 10 m.")
	_rig_tier("boots_thruster_mk3", "Mk3 Thruster Boots", Rarity.EPIC, 2200, "boots_thruster", 3,
			"Two more charges than the Mk1 and the fastest refill. Still top out at 10 m.")
	register("wings_glide", "Mk1 Glide Wings", Rarity.RARE, 1000, ["flight_rig"], WINGS_MK1.duplicate(),
			"Distance and speed. Launch, then glide at 22 m/s and dive at 30, for 25 s of glide stamina that refills on the ground, with two boosts a flight. Twice as fast across the map, but no hover or climb, poor aim, sidearm only while spread, and they cannot open indoors.")
	_rig_tier("wings_glide_mk2", "Mk2 Glide Wings", Rarity.RARE, 1400, "wings_glide", 2,
			"Faster glides, dives and boosts, and longer glide stamina. Still no hover or climb.")
	_rig_tier("wings_glide_mk3", "Mk3 Glide Wings", Rarity.EPIC, 2200, "wings_glide", 3,
			"The fastest rig there is, with the longest glide. Still no hover or climb.")

	# Abilities
	register("chip_blink", "Phase Step", Rarity.RARE, 900, ["ability", "blink"],
			{"effect": "blink", "cooldown": 8.0, "blink_range": 9.0},
			"Step nine meters in the direction you aim. Stops short of walls.")
	register("chip_barrier", "Kinetic Barrier", Rarity.UNCOMMON, 650, ["ability", "barrier"],
			{"effect": "barrier", "cooldown": 20.0, "duration": 4.0, "damage_reduction": 0.6},
			"For four seconds you take 60% less damage from bullets and blades.")
	register("chip_pulse", "Shock Pulse", Rarity.RARE, 850, ["ability", "pulse"],
			{"effect": "pulse", "cooldown": 16.0, "pulse_radius": 6.5, "pulse_damage": 18.0,
			"pulse_stagger": 1.3},
			"A shockwave that hurts and staggers everyone near you.")

	# Artifacts (DESIGN.md section 6): rare, powerful, one per outing on the
	# watch. Earned, never sold: no "vendor" tag. `effect` picks what the
	# `Artifact` does; every one is seen or felt by the people it touches.
	register("artifact_rewind", "Time Rewind", Rarity.RELIC, 3000, ["artifact", "rewind"],
			{"effect": "rewind", "charges": 1, "rewind_seconds": 4.0},
			"Once an outing: snap back to where you were, and how healthy you were, four seconds ago. Leaves a glowing trail the shooter can follow.")
	register("artifact_cloak", "Phase Cloak", Rarity.RELIC, 2800, ["artifact", "cloak"],
			{"effect": "cloak", "charges": 0, "cooldown": 90.0, "duration": 6.0, "cloak_sense_range": 4.0},
			"Near-invisible for six seconds. Firing or swinging breaks it, anyone close still notices you, and a sign-out waits while it runs.")
	register("artifact_overclock", "Overclock Core", Rarity.RELIC, 2600, ["artifact", "overclock"],
			{"effect": "overclock", "charges": 0, "cooldown": 90.0, "duration": 10.0},
			"Your flight rig makes no heat for ten seconds. Then it burns out and locks up overheated, wherever you are.")
	register("artifact_bloom", "Static Bloom", Rarity.RELIC, 2600, ["artifact", "bloom"],
			{"effect": "bloom", "charges": 0, "cooldown": 75.0, "bloom_radius": 14.0, "jam_time": 3.0},
			"A pulse that shuts off every flight rig within 14 meters for three seconds. Yours too: everyone drops.")

	# Helmets. The visor is the wearer's display in first person, and `mode`
	# picks what it can do (see `Visor`). Mk2 helmets are never sold or
	# dropped: they are crafted from blueprints (DESIGN.md section 10).
	register("visor_scav", "Scav Visor", Rarity.COMMON, 0, ["helmet", "visor_plain", "starter"],
			{"mode": "", "glass_color": Color(0.8, 0.75, 0.6)},
			"A cracked visor. Shows how hurt you are and nothing else.")
	register("helm_spotter", "Spotter Helmet", Rarity.UNCOMMON, 500, ["helmet", "optic", "vendor"],
			{"mode": "zoom", "zoom_levels": [4.0, 8.0], "glass_color": Color(1.0, 0.75, 0.3)},
			"Binoculars at 4x and 8x with a range finder. Fire while zoomed to tag a target. The lens glints.")
	register("helm_spotter_mk2", "Spotter Helmet Mk2", Rarity.RARE, 1100, ["helmet", "optic"],
			{"mode": "zoom", "zoom_levels": [4.0, 10.0], "tag_time": 7.0, "glass_color": Color(1.0, 0.75, 0.3)},
			"Binoculars at 4x and 10x. Tags last two seconds longer.")
	register("helm_seeker", "Seeker Helmet", Rarity.UNCOMMON, 550, ["helmet", "scanner", "vendor"],
			{"mode": "scan", "cooldown": 25.0, "scan_radius": 40.0, "glass_color": Color(0.4, 1.0, 0.8)},
			"A scan pulse shows where everyone within 40 meters stood. They hear it and know where it came from.")
	register("helm_seeker_mk2", "Seeker Helmet Mk2", Rarity.RARE, 1200, ["helmet", "scanner"],
			{"mode": "scan", "cooldown": 21.0, "scan_radius": 48.0, "glass_color": Color(0.4, 1.0, 0.8)},
			"A wider scan pulse, 48 meters, that is ready again sooner.")

	register("helm_warden", "Warden Helmet", Rarity.UNCOMMON, 600, ["helmet", "tactical", "vendor"],
			{"mode": "threat", "cooldown": 30.0, "threat_range": 60.0, "glass_color": Color(0.55, 0.8, 1.0)},
			"Shows where a hit came from, the health of who you aim at, and what is in nearby loot. "
			+ "Threat Sense outlines anyone aiming at you for five seconds.")
	register("helm_warden_mk2", "Warden Helmet Mk2", Rarity.RARE, 1300, ["helmet", "tactical"],
			{"mode": "threat", "cooldown": 26.0, "threat_range": 75.0, "read_range": 40.0,
			"glass_color": Color(0.55, 0.8, 1.0)},
			"Threat Sense reaches 75 meters and is ready sooner. Reads targets out to 40 meters.")
	register("helm_ember", "Ember Helmet", Rarity.UNCOMMON, 580, ["helmet", "thermal", "vendor"],
			{"mode": "thermal", "battery": 12.0, "glass_color": Color(1.0, 0.45, 0.25)},
			"Thermal sight on a twelve second battery. Warm bodies stand out through smoke and storm, "
			+ "never through walls. A hot jetpack shines.")
	register("helm_ember_mk2", "Ember Helmet Mk2", Rarity.RARE, 1250, ["helmet", "thermal"],
			{"mode": "thermal", "battery": 16.0, "battery_refill": 16.0, "glass_color": Color(1.0, 0.45, 0.25)},
			"Thermal sight with a sixteen second battery that refills faster.")

	# Vehicles. Not carried: the Raid parks one next to you when you deploy, and
	# whoever signs out riding it takes it home. Stats tune Vehicle.
	register("bike_scrapper", "Scrapper Bike", Rarity.UNCOMMON, 600, ["vehicle", "vendor"],
			{"max_speed": 22.0, "boost_speed": 29.0, "body_color": Color(0.6, 0.45, 0.3)},
			"Rattly motorbike. Fast, loud, and no cover for the rider.")
	register("bike_raider", "Raider Bike", Rarity.RARE, 1400, ["vehicle"],
			{"max_speed": 27.0, "boost_speed": 37.0, "accel": 18.0, "turn_rate": 2.6,
			"body_color": Color(0.85, 0.2, 0.15)},
			"Tuned motorbike. Quicker off the line and much faster flat out.")
	# The rest of the agreed roster (DESIGN.md section 8), at a first,
	# drivable level: no turret, passengers, armor or missiles yet.
	# `watch_recharge` is the watch's wait after one is thrown (heavier is
	# slower), `footprint` the clear ground it needs to unpack, and
	# `bay_scale` how small it parks in the base's garage bay.
	register("rover_warden", "Warden Rover", Rarity.RARE, 2400, ["vehicle", "rover"],
			{"model": "rover", "max_speed": 23.0, "boost_speed": 28.0, "accel": 9.0, "turn_rate": 1.5,
			"full_turn_speed": 8.0, "brake_decel": 24.0, "lean_amount": -0.06, "rider_lean": 0.2,
			"body_size": Vector3(2.0, 1.4, 4.2), "seat_offset": Vector3(-0.4, 0.13, 0.25),
			"seat_point": Vector3(-0.4, 0.95, 0.25),
			"grip_points": [Vector3(-0.58, 1.27, -0.25), Vector3(-0.22, 1.27, -0.25)] as Array[Vector3],
			"peg_points": [Vector3(-0.52, 0.86, -0.5), Vector3(-0.28, 0.86, -0.5)] as Array[Vector3],
			"exit_offset": Vector3(-1.9, 0.1, 0.0), "body_color": Color(0.42, 0.48, 0.32),
			"footprint": Vector3(2.3, 1.4, 4.4), "watch_recharge": 30.0, "bay_scale": 0.6},
			"Armored four-wheeler. Slow to turn and needs open ground, but it shrugs off rough terrain.")
	register("mech_bulwark", "Bulwark Mech", Rarity.EPIC, 4200, ["vehicle", "walker"],
			{"model": "mech", "max_speed": 9.0, "boost_speed": 13.0, "accel": 8.0, "turn_rate": 1.2,
			"pivot_turn": 1.0, "full_turn_speed": 3.0, "jump_speed": 9.0, "lean_amount": -0.03,
			"rider_lean": 0.2, "body_size": Vector3(1.9, 3.3, 1.9), "seat_offset": Vector3(0.0, 1.52, 0.15),
			"seat_point": Vector3(0.0, 2.3, 0.15),
			"grip_points": [Vector3(-0.25, 2.5, -0.38), Vector3(0.25, 2.5, -0.38)] as Array[Vector3],
			"peg_points": [Vector3(-0.16, 2.08, -0.5), Vector3(0.16, 2.08, -0.5)] as Array[Vector3],
			"exit_offset": Vector3(1.8, 0.1, 0.0), "body_color": Color(0.55, 0.52, 0.45),
			"footprint": Vector3(2.0, 3.0, 2.0), "watch_recharge": 60.0, "bay_scale": 0.6},
			"Compact walker. Slow and heavy, turns on the spot and hops on jump-jets. Its power unit "
			+ "sits exposed on its back.")
	register("jet_kestrel", "Kestrel Jet", Rarity.EPIC, 4600, ["vehicle", "aircraft"],
			{"model": "jet", "max_speed": 45.0, "boost_speed": 60.0, "accel": 10.0, "turn_rate": 1.3,
			"full_turn_speed": 8.0, "takeoff_speed": 24.0, "stall_speed": 22.0, "climb_rate": 10.0,
			"lean_amount": 0.0, "rider_lean": 0.1, "body_size": Vector3(1.3, 1.5, 6.4),
			"seat_offset": Vector3(0.0, 0.52, -0.55), "seat_point": Vector3(0.0, 1.3, -0.55),
			"grip_points": [Vector3(-0.22, 1.47, -1.05), Vector3(0.22, 1.47, -1.05)] as Array[Vector3],
			"peg_points": [Vector3(-0.15, 0.9, -1.6), Vector3(0.15, 0.9, -1.6)] as Array[Vector3],
			"exit_offset": Vector3(1.6, 0.1, -0.5), "body_color": Color(0.6, 0.65, 0.72),
			"footprint": Vector3(5.0, 1.8, 6.6), "watch_recharge": 60.0, "bay_scale": 0.42},
			"Starfighter. Fast across the map and fragile; it cannot hover, and only flies in worlds with open skies.")

	# Blueprints (DESIGN.md section 10). Found in the PvP world and at stake
	# until they are home; once in a stash a blueprint is learned for good
	# and what it makes is crafted at the gunsmith bench (`Crafting`). A copy
	# of one already known is loot to sell. Never sold in a shop.
	_blueprint("bp_jetpack", "Jetpack Blueprint", Rarity.RARE, 300,
			"Plans for the jetpack. Craft the Mk2 and Mk3 from it with upgrade data.")
	_blueprint("bp_boots_thruster", "Thruster Boots Blueprint", Rarity.RARE, 300,
			"Plans for the thruster boots. Craft the Mk2 and Mk3 from it with upgrade data.")
	_blueprint("bp_wings_glide", "Glide Wings Blueprint", Rarity.RARE, 300,
			"Plans for the glide wings. Craft the Mk2 and Mk3 from it with upgrade data.")
	_blueprint("bp_dmr_longshot", "Longshot DMR Blueprint", Rarity.RARE, 250,
			"Plans for the Longshot DMR. Craft one whenever you have the parts.")
	_blueprint("bp_shotgun_breacher", "Breacher Shotgun Blueprint", Rarity.RARE, 250,
			"Plans for the Breacher Shotgun. Craft one whenever you have the parts.")
	_blueprint("bp_mech_bulwark", "Bulwark Mech Blueprint", Rarity.EPIC, 1200,
			"Plans for the Bulwark Mech. The only way to own one.")
	_blueprint("bp_jet_kestrel", "Kestrel Jet Blueprint", Rarity.EPIC, 1200,
			"Plans for the Kestrel Jet. The only way to own one.")
	# What a Mk2 or Mk3 craft spends. Worth nothing to a shop, so it is never
	# sold by accident; it is only kept if you get it home.
	register("upgrade_data", "Upgrade Data", Rarity.RARE, 0, ["upgrade_data"], {},
			"Combat data pulled from the war. Steps a blueprint up to Mk2 and Mk3 at the gunsmith bench.")

	# Consumables
	register("medkit", "Medkit", Rarity.COMMON, 60, ["consumable", "heal", "vendor"], {"heal": 50.0}, "Heals 50.")

	# Loot
	register("scrap_metal", "Scrap Metal", Rarity.COMMON, 25, ["material"])
	register("circuit_board", "Circuit Board", Rarity.UNCOMMON, 70, ["material"])
	register("power_cell", "Power Cell", Rarity.UNCOMMON, 110, ["material"])
	register("alloy_ingot", "Alloy Ingot", Rarity.RARE, 240, ["material"])
	register("targeting_chip", "Targeting Chip", Rarity.RARE, 320, ["augment"])
	register("reactor_core", "Reactor Core", Rarity.EPIC, 900, ["material"])
	register("lattice_shard", "Lattice Shard", Rarity.RELIC, 2500, ["relic"])

	# Furniture and decorations for a home base. Bought from the Furnisher,
	# kept in the stash, never taken on a raid. "footprint" is the size in
	# meters and "color" the base color, for whatever displays them.
	_furniture("furn_table", "Mess Table", 120, Vector3(1.6, 0.8, 0.9), Color(0.42, 0.36, 0.3),
			"A steel table that has seen a lot of card games.")
	_furniture("furn_bunk", "Steel Bunk", 150, Vector3(2.0, 0.6, 0.9), Color(0.35, 0.38, 0.42),
			"Somewhere to sleep between drops.")
	_furniture("furn_locker", "Gear Locker", 200, Vector3(0.9, 1.9, 0.5), Color(0.3, 0.4, 0.35),
			"Dented, lockable, yours.")
	_furniture("furn_couch", "Salvaged Couch", 250, Vector3(2.0, 0.8, 0.9), Color(0.5, 0.25, 0.2),
			"Pulled from a wreck and surprisingly comfortable.")
	_furniture("furn_workbench", "Workbench", 300, Vector3(1.8, 0.9, 0.8), Color(0.45, 0.4, 0.3),
			"A place to strip, clean and admire your gear.")
	_furniture("furn_armor_stand", "Armor Stand", 300, Vector3(0.7, 1.8, 0.7), Color(0.4, 0.4, 0.45),
			"Shows off a frame at full height.")
	_furniture("furn_weapon_rack", "Weapon Rack", 350, Vector3(1.8, 1.6, 0.4), Color(0.3, 0.3, 0.33),
			"Wall rack for the weapons you are proudest of.")
	_furniture("furn_trophy_case", "Trophy Case", 500, Vector3(1.4, 1.9, 0.5), Color(0.55, 0.45, 0.25),
			"Glass-fronted case for the rarest things you have brought home.", Rarity.UNCOMMON)
	_furniture("decor_lamp", "Work Lamp", 60, Vector3(0.3, 1.5, 0.3), Color(1.0, 0.85, 0.55),
			"Warm light on a tripod.", Rarity.COMMON, true)
	_furniture("decor_plant", "Potted Fern", 70, Vector3(0.5, 0.9, 0.5), Color(0.25, 0.55, 0.3),
			"Something green that is not trying to kill you.", Rarity.COMMON, true)
	_furniture("decor_rug", "Woven Rug", 80, Vector3(2.4, 0.03, 1.6), Color(0.55, 0.3, 0.25),
			"Takes the chill off a concrete floor.", Rarity.COMMON, true)
	_furniture("decor_banner", "War Banner", 100, Vector3(1.0, 1.8, 0.05), Color(0.7, 0.2, 0.15),
			"Hang your colors.", Rarity.COMMON, true)
	_furniture("decor_neon", "Neon Sign", 180, Vector3(1.2, 0.5, 0.1), Color(0.2, 0.9, 1.0),
			"Buzzes a little. Glows a lot.", Rarity.UNCOMMON, true)

	# Clothing. Cosmetic only: an outfit item in the stash unlocks the
	# character customizer outfits listed in its "outfits" stat (the ids the
	# customizer uses, one per body build that has the outfit). It fits no
	# loadout slot, so it never goes on a raid and is never lost.
	_outfit("outfit_scout", "Scout Outfit", 150, ["m_Adventurer"], "Hard-wearing field clothes.")
	_outfit("outfit_punk", "Punk Outfit", 200, ["m_Punk", "f_Punk"], "Loud, torn and proud of it.")
	_outfit("outfit_sellsword", "Sellsword Outfit", 300, ["f_Medieval"], "Old-world leathers for hired blades.",
			Rarity.UNCOMMON)
	_outfit("outfit_envoy", "Envoy Outfit", 350, ["f_Formal"], "Formal wear that says you are not here to shoot.",
			Rarity.UNCOMMON)
	_outfit("outfit_suit", "Suit", 350, ["m_Suit", "f_Suit"], "For when the deal matters more than the fight.",
			Rarity.UNCOMMON)
	_outfit("outfit_trooper", "Trooper Outfit", 400, ["m_Swat", "f_Soldier"], "Fatigues and webbing. Looks the part.",
			Rarity.UNCOMMON)


## Registers a weapon attachment for `slot` (also its tag: see `Loadout.SLOTS`).
func _attachment(id: String, display_name: String, rarity: Rarity, value: int, slot: String, vendor: bool,
		stats: Dictionary, description: String) -> void:
	var tags := ["attachment", slot]
	if vendor:
		tags.append("vendor")
	register(id, display_name, rarity, value, tags, stats, description)


## Registers a blueprint (see `core/progression/crafting.gd` for what it makes).
func _blueprint(id: String, display_name: String, rarity: Rarity, value: int, description: String) -> void:
	register(id, display_name, rarity, value, ["blueprint"], {}, description)


## Registers a clothing item that unlocks the customizer outfits `outfits`.
func _outfit(id: String, display_name: String, value: int, outfits: Array, description: String,
		rarity: Rarity = Rarity.COMMON) -> void:
	register(id, display_name, rarity, value, ["cosmetic", "vendor"], {"outfits": outfits}, description)


## Registers a home base piece. Small pieces are also tagged "decor".
func _furniture(id: String, display_name: String, value: int, footprint: Vector3, color: Color,
		description: String, rarity: Rarity = Rarity.COMMON, decor := false) -> void:
	var tags := ["furniture", "vendor"]
	if decor:
		tags.append("decor")
	register(id, display_name, rarity, value, tags, {"footprint": footprint, "color": color}, description)


## A higher tier of a flight rig: the Mk1 `base` rig's stats with its
## strength scaled up by `RIG_TIER_STEP` once per tier above Mk1. Which
## stats are the strength is the rig's `RIG_STRENGTH` list: a stat named there
## grows, and one named with a leading "-" shrinks (a heat cost or a wait).
## Integer stats (charges) round. Tiers above Mk1 are crafted, never sold or
## handed out, so the base's "vendor" and "starter" tags are not copied.
func _rig_tier(id: String, display_name: String, rarity: Rarity, value: int, base: String, tier: int,
		description: String) -> void:
	var stats := item_stats(base).duplicate()
	var scale := pow(RIG_TIER_STEP, tier - 1)
	for entry: String in RIG_STRENGTH[base]:
		var shrink := entry.begins_with("-")
		var stat := entry.trim_prefix("-")
		var value_now: Variant = stats[stat]
		var scaled: float = float(value_now) / scale if shrink else float(value_now) * scale
		if stat == "max_charges":
			# Boots: one more charge a tier (Caleb's call), not 15% of four.
			stats[stat] = int(value_now) + tier - 1
		elif typeof(value_now) == TYPE_INT:
			stats[stat] = roundi(scaled)
		else:
			stats[stat] = snappedf(scaled, 0.01)
	stats["tier"] = tier
	var tags: Array = get_item(base).get("tags", []).filter(func(tag: String) -> bool:
			return tag != "vendor" and tag != "starter")
	register(id, display_name, rarity, value, tags, stats, description)


## Tags also pick the mastery track an item trains: "rifle", "blink", "frame_heavy"
## and so on (see core/progression/mastery_db.gd).
## `stats` are applied to the weapon, rig or actor when the item is equipped.
func register(id: String, display_name: String, rarity: Rarity, value: int, tags: Array,
		stats: Dictionary = {}, description: String = "") -> void:
	_items[id] = {
		"id": id,
		"name": display_name,
		"rarity": rarity,
		"value": value,
		"tags": tags,
		"stats": stats,
		"description": description,
	}


func has_item(id: String) -> bool:
	return _items.has(id)


## Every registered item id, in the order they were registered.
func all_ids() -> Array:
	return _items.keys()


func get_item(id: String) -> Dictionary:
	return _items.get(id, {})


func item_name(id: String) -> String:
	return get_item(id).get("name", id)


func item_value(id: String) -> int:
	return get_item(id).get("value", 0)


func item_rarity(id: String) -> int:
	return get_item(id).get("rarity", Rarity.COMMON)


func has_tag(id: String, tag: String) -> bool:
	return tag in get_item(id).get("tags", [])


func item_stats(id: String) -> Dictionary:
	return get_item(id).get("stats", {})


func item_description(id: String) -> String:
	return get_item(id).get("description", "")


func rarity_name(id: String) -> String:
	return RARITY_NAMES[item_rarity(id)]


func total_value(ids: Array) -> int:
	var total := 0
	for id: String in ids:
		total += item_value(id)
	return total


## Picks one item id from a weighted table: [{ "id": String, "weight": float }].
func roll(table: Array, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for entry: Dictionary in table:
		total += entry.weight
	if total <= 0.0:
		return ""
	var pick := rng.randf() * total
	for entry: Dictionary in table:
		pick -= entry.weight
		if pick <= 0.0:
			return entry.id
	return table.back().id


## "3x Scrap Metal, 1x Power Cell" style summary, most valuable first.
func summarize(ids: Array) -> String:
	if ids.is_empty():
		return "nothing"
	var counts := {}
	for id: String in ids:
		counts[id] = counts.get(id, 0) + 1
	var keys := counts.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return item_value(a) > item_value(b))
	var parts: Array[String] = []
	for id: String in keys:
		parts.append("%dx %s" % [counts[id], item_name(id)])
	return ", ".join(parts)


# The Mk1 flight rigs (Caleb's balance pass, DESIGN.md section 5). Each rig
# has one job and one weakness; tune them here. Heat is out of 100.

## Jetpack: height and hover. Hover burns `heat_per_sec` (8 s on a full
## bar), climbing 1.5x and boosting 2.5x (about 3 s). Climbs at 8 m/s to a
## 40 m ceiling, cruises at 14 and boosts at 18 m/s. Cools in 4 s on the
## ground. Steady in the air (+10% spread), half fall damage, clumsy under a
## roof, seen 120 m away on scans and thermal.
const JETPACK_MK1 := {
	"thrust_accel": 36.0, "max_rise_speed": 8.0, "fly_speed": 14.0, "boost_speed": 18.0,
	"heat_per_sec": 12.5, "hover_heat_mult": 1.0, "cruise_heat_mult": 1.0, "climb_heat_mult": 1.5,
	"boost_heat_mult": 2.5, "cool_per_sec": 25.0, "coast_cool": 25.0, "ceiling": 40.0,
	"flight_aim": 0.1, "fall_damage_mult": 0.5, "scan_range": 120.0, "indoor_mult": 0.5,
	"heavy_lift": true, "tier": 1,
}

## Thruster boots: ground agility and stealth. No heat: 4 charges pay for
## kicks (up to a 10 m ceiling) and 14 m/s air dashes, one back every
## 1.5 s. A 1.5 s skim per jump. 15% faster on foot, no fall damage, a
## 0.2 s graze window on every dash, steady aim mid-dash, full use indoors,
## seen only 30 m away on scans and thermal.
const BOOTS_MK1 := {
	"thrust_accel": 0.0, "burst_velocity": 12.0, "burst_heat": 0.0, "burst_push": 11.0,
	"max_charges": 4, "charge_time": 1.5, "skim_speed": 12.0, "skim_time": 1.5,
	"skim_mid_heat": 0.0, "skim_high_heat": 0.0, "air_dash_speed": 14.0, "air_dash_time": 0.3,
	"air_dash_heat": 0.0, "air_dash_cooldown": 0.25, "ground_speed_mult": 1.15, "flight_aim": 0.0,
	"fall_damage_mult": 0.0, "graze_window": 0.2, "scan_range": 30.0, "indoor_mult": 1.0,
	"ceiling": 10.0, "tier": 1,
}

## Glide wings: distance and speed. A free launch, then a 22 m/s glide that
## dives to 30, on 25 s of glide stamina (`glide_heat`) that refills in 5 s
## on the ground only. Two boosts a flight (+8 m/s, or a small lift on
## Shift + S), refilled on the ground. No hover and no climb of their own,
## poor aim (+50% spread), sidearm only, 5% slower on foot, no fall damage
## out of a glide, cannot open indoors, seen 80 m away.
const WINGS_MK1 := {
	"thrust_accel": 0.0, "burst_velocity": 14.0, "burst_heat": 0.0, "launch_once": true,
	"cool_per_sec": 20.0, "ground_cool_only": true, "glide_heat": 4.0, "glide_cool": 0.0,
	"glide_fall_speed": 1.2, "glide_speed": 22.0, "glide_dive_gain": 0.364, "glide_turn_rate": 2.4,
	"stall_sink": 6.0, "air_dash_speed": 12.0, "air_dash_heat": 0.0, "air_dash_cooldown": 1.0,
	"glide_boost": 8.0, "glide_boost_climb": 6.0, "glide_boost_heat": 0.0,
	"max_charges": 2, "charge_time": 1.0, "charge_on_ground": true,
	"glide_sidearm_only": true, "slide_landing_speed": 18.0, "ground_speed_mult": 0.95,
	"flight_aim": 1.5, "fall_damage_mult": 1.0, "scan_range": 80.0, "indoor_mult": 0.0,
	"ceiling": 40.0, "tier": 1,
}

## What a higher tier improves on each rig: its strength only (see
## `_rig_tier`; "-" lowers a cost or a wait). Jetpacks get more hover, heat
## and height; boots one more charge and a faster refill; wings more speed
## and glide time.
const RIG_STRENGTH := {
	"jetpack_mk1": ["-heat_per_sec", "cool_per_sec", "coast_cool", "ceiling"],
	"boots_thruster": ["max_charges", "-charge_time"],
	"wings_glide": ["glide_speed", "glide_boost", "-glide_heat"],
}
