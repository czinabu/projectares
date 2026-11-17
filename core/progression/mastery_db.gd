extends RefCounted
## Every mastery track and the variants it unlocks. Plain data plus a few
## static helpers. Load it with `preload`, it has no class_name on purpose.
##
## A track covers one *type* of gear, picked by an item tag ("rifle", "blink",
## "frame_heavy"), so it carries over to any item of that type in any world.
## Mastery never adds raw power. Every variant trades one strength for another,
## and the stock item is always a valid pick.
##
## A variant's `mods` map a stat to [op, value], op being "mul", "add" or "set".
## Weapon and ability mods name properties on the Weapon or Ability. Frame mods
## use three actor-level stats: "armor", "speed" and "heat".

## Total XP needed for each level. Index is the level, so level 0 needs 0.
const LEVEL_XP: Array[int] = [0, 150, 400, 800, 1400, 2200]

const TRACKS := {
	# Firearms
	"rifle": {"name": "Rifle", "kind": "weapon", "variants": [
		{"id": "long_barrel", "name": "Long Barrel", "level": 2,
			"desc": "Tighter and longer reach, slower fire.",
			"mods": {"spread_deg": ["mul", 0.7], "max_range": ["mul", 1.3], "fire_interval": ["mul", 1.15]}},
		{"id": "cut_down", "name": "Cut Down", "level": 4,
			"desc": "Fires faster, kicks harder and sprays wider.",
			"mods": {"fire_interval": ["mul", 0.87], "spread_deg": ["mul", 1.3], "recoil_kick_deg": ["mul", 1.25]}},
	]},
	"smg": {"name": "SMG", "kind": "weapon", "variants": [
		{"id": "drum_mag", "name": "Drum Mag", "level": 2,
			"desc": "Half again the magazine, much slower reload.",
			"mods": {"mag_size": ["mul", 1.5], "ammo_in_mag": ["mul", 1.5], "reload_time": ["mul", 1.35]}},
		{"id": "hair_trigger", "name": "Hair Trigger", "level": 4,
			"desc": "Even faster fire, wider spread.",
			"mods": {"fire_interval": ["mul", 0.85], "spread_deg": ["mul", 1.35]}},
	]},
	"marksman": {"name": "Marksman rifle", "kind": "weapon", "variants": [
		{"id": "quick_action", "name": "Quick Action", "level": 2,
			"desc": "Shoots faster, hits a little lighter.",
			"mods": {"fire_interval": ["mul", 0.78], "damage": ["mul", 0.85]}},
		{"id": "heavy_rounds", "name": "Heavy Rounds", "level": 4,
			"desc": "Hits harder, fires slower and kicks more.",
			"mods": {"damage": ["mul", 1.15], "fire_interval": ["mul", 1.3], "recoil_kick_deg": ["mul", 1.3]}},
	]},
	"shotgun": {"name": "Shotgun", "kind": "weapon", "variants": [
		{"id": "choke", "name": "Choke", "level": 2,
			"desc": "Tighter pattern and more reach, two fewer pellets.",
			"mods": {"spread_deg": ["mul", 0.65], "max_range": ["mul", 1.3], "pellets": ["add", -2]}},
		{"id": "speed_loader", "name": "Speed Loader", "level": 4,
			"desc": "Reloads much faster, holds two fewer shells.",
			"mods": {"reload_time": ["mul", 0.6], "mag_size": ["add", -2], "ammo_in_mag": ["add", -2]}},
	]},
	# Melee
	"blade": {"name": "Blade", "kind": "weapon", "variants": [
		{"id": "duelist_grip", "name": "Duelist Grip", "level": 2,
			"desc": "A wider parry window, lighter quick cuts.",
			"mods": {"parry_window": ["mul", 1.35], "light_damage": ["mul", 0.88]}},
		{"id": "heavy_edge", "name": "Heavy Edge", "level": 4,
			"desc": "Heavier lunges with a longer windup.",
			"mods": {"heavy_damage": ["mul", 1.15], "heavy_windup": ["mul", 1.25]}},
	]},
	"hammer": {"name": "Hammer", "kind": "weapon", "variants": [
		{"id": "short_haft", "name": "Short Haft", "level": 2,
			"desc": "Quicker swings, less reach.",
			"mods": {"light_windup": ["mul", 0.8], "light_recover": ["mul", 0.85], "reach": ["mul", 0.85]}},
		{"id": "quake_head", "name": "Quake Head", "level": 4,
			"desc": "The dive slam covers more ground but hits softer.",
			"mods": {"slam_radius": ["mul", 1.3], "slam_damage": ["mul", 0.85]}},
	]},
	"knife": {"name": "Knife", "kind": "weapon", "variants": [
		{"id": "assassin_grip", "name": "Assassin Grip", "level": 2,
			"desc": "Cuts from behind hit much harder, cuts from the front softer.",
			"mods": {"backstab_mult": ["mul", 1.25], "light_damage": ["mul", 0.85]}},
		{"id": "fighting_knife", "name": "Fighting Knife", "level": 4,
			"desc": "A longer blade with more reach, slower to recover.",
			"mods": {"reach": ["mul", 1.15], "light_recover": ["mul", 1.2]}},
	]},
	"axe": {"name": "Axe", "kind": "weapon", "variants": [
		{"id": "bearded_head", "name": "Bearded Head", "level": 2,
			"desc": "Breaks guards even faster, with a slower windup.",
			"mods": {"guard_crush": ["mul", 1.3], "light_windup": ["mul", 1.2]}},
		{"id": "long_haft", "name": "Long Haft", "level": 4,
			"desc": "More reach and heavier chops, slower heavy swings.",
			"mods": {"reach": ["mul", 1.15], "heavy_windup": ["mul", 1.2]}},
	]},
	"spear": {"name": "Spear", "kind": "weapon", "variants": [
		{"id": "leaf_blade", "name": "Leaf Blade", "level": 2,
			"desc": "A wider head that catches more, on a shorter shaft.",
			"mods": {"arc_deg": ["mul", 1.5], "reach": ["mul", 0.88]}},
		{"id": "pike_shaft", "name": "Pike Shaft", "level": 4,
			"desc": "Even more reach, and a wider weak spot up close.",
			"mods": {"reach": ["mul", 1.15], "close_range": ["mul", 1.4]}},
	]},
	# Abilities
	"blink": {"name": "Phase Step", "kind": "ability", "variants": [
		{"id": "short_hop", "name": "Short Hop", "level": 2,
			"desc": "A much shorter step that recharges much sooner.",
			"mods": {"blink_range": ["mul", 0.55], "cooldown": ["mul", 0.55]}},
		{"id": "ward_step", "name": "Ward Step", "level": 4,
			"desc": "Arrive behind a one-second barrier. Longer cooldown.",
			"mods": {"blink_shield": ["set", 1.0], "cooldown": ["mul", 1.35]}},
	]},
	"barrier": {"name": "Kinetic Barrier", "kind": "ability", "variants": [
		{"id": "flash_barrier", "name": "Flash Barrier", "level": 2,
			"desc": "Blocks far more, for half as long.",
			"mods": {"duration": ["mul", 0.5], "damage_reduction": ["set", 0.85]}},
		{"id": "long_barrier", "name": "Long Barrier", "level": 4,
			"desc": "Lasts much longer, blocks less.",
			"mods": {"duration": ["mul", 1.75], "damage_reduction": ["set", 0.4]}},
	]},
	"pulse": {"name": "Shock Pulse", "kind": "ability", "variants": [
		{"id": "wide_pulse", "name": "Wide Pulse", "level": 2,
			"desc": "Reaches further, hurts less.",
			"mods": {"pulse_radius": ["mul", 1.35], "pulse_damage": ["mul", 0.6]}},
		{"id": "stun_pulse", "name": "Stun Pulse", "level": 4,
			"desc": "Staggers much longer, smaller radius.",
			"mods": {"pulse_stagger": ["mul", 1.6], "pulse_radius": ["mul", 0.75]}},
	]},
	# Armor frames
	"frame_light": {"name": "Light frame", "kind": "frame", "variants": [
		{"id": "stripped", "name": "Stripped", "level": 2,
			"desc": "Even faster, a quarter less armor.",
			"mods": {"armor": ["mul", 0.75], "speed": ["mul", 1.05]}},
		{"id": "padded", "name": "Padded", "level": 4,
			"desc": "A quarter more armor, a little slower.",
			"mods": {"armor": ["mul", 1.25], "speed": ["mul", 0.96]}},
	]},
	"frame_medium": {"name": "Medium frame", "kind": "frame", "variants": [
		{"id": "agile", "name": "Agile", "level": 2,
			"desc": "A little faster, less armor.",
			"mods": {"armor": ["mul", 0.85], "speed": ["mul", 1.04]}},
		{"id": "plated", "name": "Plated", "level": 4,
			"desc": "More armor, a little slower.",
			"mods": {"armor": ["mul", 1.15], "speed": ["mul", 0.95]}},
	]},
	"frame_heavy": {"name": "Heavy frame", "kind": "frame", "variants": [
		{"id": "vented", "name": "Vented", "level": 2,
			"desc": "Flight gear runs much cooler, a little less armor.",
			"mods": {"heat": ["mul", 0.78], "armor": ["mul", 0.9]}},
		{"id": "bastion", "name": "Bastion", "level": 4,
			"desc": "Even more armor, even slower.",
			"mods": {"armor": ["mul", 1.15], "speed": ["mul", 0.93]}},
	]},
}


static func has_track(track: String) -> bool:
	return TRACKS.has(track)


## The track an item trains, found from its tags, or "" for none.
static func track_for_item(id: String) -> String:
	for track: String in TRACKS:
		if ItemDB.has_tag(id, track):
			return track
	return ""


static func track_name(track: String) -> String:
	return TRACKS.get(track, {}).get("name", track)


static func track_kind(track: String) -> String:
	return TRACKS.get(track, {}).get("kind", "")


static func max_level() -> int:
	return LEVEL_XP.size() - 1


static func level_for_xp(xp: int) -> int:
	var level := 0
	for i in LEVEL_XP.size():
		if xp >= LEVEL_XP[i]:
			level = i
	return level


## XP needed for the next level, or -1 at the max level.
static func next_level_xp(level: int) -> int:
	return LEVEL_XP[level + 1] if level < max_level() else -1


static func variants(track: String) -> Array:
	return TRACKS.get(track, {}).get("variants", [])


static func variant(track: String, variant_id: String) -> Dictionary:
	for v: Dictionary in variants(track):
		if v.id == variant_id:
			return v
	return {}


## Applies a variant's mods to an object's properties. Integer stats stay integers.
static func apply_mods(target: Object, mods: Dictionary) -> void:
	for stat: String in mods:
		if not stat in target:
			push_warning("Mastery: %s has no property '%s'" % [target.get_class(), stat])
			continue
		target.set(stat, modded(target.get(stat), mods[stat]))


static func modded(value: Variant, mod: Array) -> Variant:
	var out := float(value)
	match mod[0]:
		"mul":
			out *= mod[1]
		"add":
			out += mod[1]
		"set":
			out = mod[1]
	if typeof(value) == TYPE_INT:
		return maxi(1, roundi(out))
	return out
