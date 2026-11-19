extends Node
## Measures how the enemy types fight: a reference player (a bot in a mid
## kit, steady average aim, see `REF_KIT`) duels each enemy type many times
## on open, flat ground, and the bench prints who won, how fast and with how
## much health left, beside the target for each type (`TARGETS`, DESIGN.md
## "Enemy balance"). Every duel of a matchup runs at once, far apart.
##
##   godot --headless --fixed-fps 60 --path . res://tests/duel_bench.tscn
##   ... -- --duels 40 --ranges 12,25 --only raider --world ashfront --seed 1
##   ... -- --melee blade_scrap   (the melee bench: the reference fights with
##   that blade only, against each type; DESIGN.md "Melee bots")
##
## Enemies are built the way the world builds them (`equip_bot`,
## `raider_kit`, `make_warlord`), so tuning the world's numbers moves these.

## The reference player: a carbine, a sidearm, a knife, a medium frame and a
## medkit, no rig or helmet, aiming at 0.5 (`BotBrain.skill`).
const REF_KIT: Array[String] = ["rifle_carbine", "pistol_machine", "knife_gutter", "frame_trooper", "medkit"]
const REF_SKILL := 0.5
## Each enemy type: how it is made, and the share of duels the reference
## player should win (a band, low to high).
const TARGETS := {
	"soldier_outer": {"kind": "soldier", "zone": 0, "win": Vector2(0.85, 0.97), "role": "fodder: teaches the basics"},
	"soldier_core": {"kind": "soldier", "zone": 2, "win": Vector2(0.65, 0.85), "role": "pressure, deadly in numbers"},
	"heavy_outer": {"kind": "heavy", "zone": 0, "win": Vector2(0.75, 0.95), "role": "parry practice"},
	"heavy_core": {"kind": "heavy", "zone": 2, "win": Vector2(0.55, 0.8), "role": "punishes panic"},
	"raider": {"kind": "raider", "zone": 0, "win": Vector2(0.4, 0.6), "role": "an equal"},
	"warlord": {"kind": "warlord", "zone": 2, "win": Vector2(0.1, 0.35), "role": "a squad fight"},
	# Heavy units (DESIGN.md "Heavy units"), last so the rows above keep their seeds.
	"exo_outer": {"kind": "exo", "zone": 0, "win": Vector2(0.7, 0.9), "role": "the tougher soldier"},
	"exo_core": {"kind": "exo", "zone": 2, "win": Vector2(0.45, 0.7), "role": "armor that needs a plan"},
	"walker_middle": {"kind": "walker", "zone": 1, "win": Vector2(0.15, 0.4), "role": "a fight for two players"},
	"walker_core": {"kind": "walker", "zone": 2, "win": Vector2(0.1, 0.3), "role": "a fight for two players"},
}
## Other worlds' enemies, by world id (the enemy AI pass): a "faction" row is
## built from that faction's marker, as the map would. Frostline's bands are
## proposed in the pass's plan, not yet confirmed by Caleb.
const WORLD_TARGETS := {
	"frostline": {
		"warden_mouth": {"kind": "warden", "faction": "warden", "zone": 0, "win": Vector2(0.85, 0.95), "role": "a sentry you learn to slip past"},
		"warden_head": {"kind": "warden", "faction": "warden", "zone": 2, "win": Vector2(0.7, 0.9), "role": "the grid at the glacier head"},
		"feral_mouth": {"kind": "feral", "faction": "feral", "zone": 0, "win": Vector2(0.85, 0.97), "role": "a stray from a small pack"},
		"feral_head": {"kind": "feral", "faction": "feral", "zone": 2, "win": Vector2(0.75, 0.92), "role": "one of the big packs"},
	},
}
## The rows a group fight (`--group`) runs, by world.
const GROUP_TYPES := {
	"ashfront": ["soldier_outer", "soldier_core"],
	"frostline": ["feral_mouth", "feral_head", "warden_head"],
}
## Seconds before an unfinished duel counts as a draw.
const TIME_LIMIT := 45.0
## Metres between duels, so no stray round reaches the next pair.
const SPACING := 160.0

var _world: WorldDef
var _raid: Raid
## The reference's kit: `REF_KIT`, or a blade, the frame and the medkit for
## the melee bench.
var _ref_kit: Array[String] = REF_KIT.duplicate()
var _melee := false
## The rows for this world: `TARGETS` for Ashfront, else `WORLD_TARGETS`.
var _targets: Dictionary = TARGETS


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var duels := int(_arg(args, "--duels", "30"))
	var ranges: Array[float] = []
	for part in _arg(args, "--ranges", "12,25").split(","):
		ranges.append(float(part))
	var only := _arg(args, "--only", "")
	var seed_base := int(_arg(args, "--seed", "1"))
	_world = Worlds.get_world(_arg(args, "--world", "ashfront"))
	_targets = WORLD_TARGETS.get(_world.id, TARGETS)
	var blade := _arg(args, "--melee", "")
	if blade != "":
		_melee = true
		_ref_kit.assign([blade, "frame_trooper", "medkit"])
	var field := Field.new()
	field.source = _world
	field.rows = duels
	_raid = Raid.new()
	add_child(_raid)
	# A duel is the fight a player is standing in, so both bodies simulate
	# every tick. With no player nearby the raid would thin every bot out to
	# every fourth tick, and the bench would measure that coarser fight.
	_raid.far_detail_step = 1
	_raid.start_server(field, seed_base)
	print("Duel bench: %s, %d duels a matchup, reference kit %s at skill %.2f" % [_world.id, duels,
			", ".join(_ref_kit), REF_SKILL])
	print("%-14s %5s  %6s %6s %6s  %8s %8s  %7s  %s" % ["enemy", "range", "win", "loss", "draw",
			"ttk win", "ttk loss", "hp left", "target"])
	var groups := _arg(args, "--group", "")
	if groups != "":
		BotBrain.ration_attacks = _arg(args, "--slots", "on") != "off"
		print("Group fights: the reference against several at once (attack slots %s)" % (
				"on" if BotBrain.ration_attacks else "off"))
		var g_off := 0
		for type: String in GROUP_TYPES.get(_world.id, GROUP_TYPES["ashfront"]):
			if only != "" and type != only:
				continue
			for size in groups.split(","):
				for distance in ranges:
					var r: Dictionary = await _matchup(type, distance, duels, seed_base * 1000 + g_off, int(size))
					g_off += duels
					_report("%s x%s" % [type, size], distance, r, type)
		get_tree().quit()
		return
	var off := 0
	for type: String in _targets:
		if only != "" and type != only:
			continue
		for distance in ranges:
			var result: Dictionary = await _matchup(type, distance, duels, seed_base * 1000 + off)
			off += duels
			_report(type, distance, result)
	get_tree().quit()


## Runs `count` duels of the reference player against `type` at once and
## returns the tallies.
func _matchup(type: String, distance: float, count: int, seed_from: int, group := 1) -> Dictionary:
	var pairs: Array[Dictionary] = []
	for i in count:
		var row := Vector3((i % 6) * SPACING, 0.0, (i / 6) * SPACING)
		var ref := _make_ref(row, seed_from + i)
		var foes: Array[Actor] = []
		for g in group:
			# A group stands in an arc in front of the reference.
			var angle := (g - (group - 1) * 0.5) * deg_to_rad(18.0)
			var at := row + Vector3(cos(angle), 0, sin(angle)) * distance
			var foe := _make_enemy(type, at, seed_from + i + g * 100003)
			_face(foe, ref)
			foes.append(foe)
		_face(ref, foes[0])
		pairs.append({"ref": ref, "foe": foes[0], "foes": foes, "ended": -1.0, "winner": ""})
	var clock := 0.0
	var step := 1.0 / Engine.physics_ticks_per_second
	var open := count
	while open > 0 and clock < TIME_LIMIT:
		await get_tree().physics_frame
		clock += step
		for pair in pairs:
			if pair.ended >= 0.0:
				continue
			var ref: Actor = pair.ref
			var foes: Array[Actor] = pair.foes
			var all_down := foes.all(func(f: Actor) -> bool: return f.is_dead)
			if ref.is_dead or all_down:
				pair.ended = clock
				pair.winner = "ref" if all_down else "foe"
				pair.hp = ref.health.health / ref.health.max_health if all_down else 0.0
				open -= 1
				_stop(ref)
				for f in foes:
					_stop(f)
	var out := {"win": 0, "loss": 0, "draw": 0, "ttk_win": 0.0, "ttk_loss": 0.0, "hp": 0.0}
	for pair in pairs:
		if pair.winner == "ref":
			out.win += 1
			out.ttk_win += pair.ended
			out.hp += pair.hp
		elif pair.winner == "foe":
			out.loss += 1
			out.ttk_loss += pair.ended
		else:
			out.draw += 1
		_raid._remove_actor(pair.ref)
		for actor: Actor in pair.foes:
			_raid._remove_actor(actor)
	await get_tree().physics_frame
	return out


func _report(type: String, distance: float, r: Dictionary, kind := "") -> void:
	var total := maxf(r.win + r.loss + r.draw, 1)
	var share: float = r.win / total
	if kind != "":
		# Group rows have no agreed band yet: print the numbers only.
		print("%-18s %4.0fm  %5.0f%% %5.0f%% %5.0f%%  %7.1fs %7.1fs  %6.0f%%" % [type, distance,
				share * 100.0, r.loss / total * 100.0, r.draw / total * 100.0,
				r.ttk_win / maxf(r.win, 1), r.ttk_loss / maxf(r.loss, 1), r.hp / maxf(r.win, 1) * 100.0])
		return
	if _melee:
		# Melee rows have no agreed band yet: the numbers and the role only.
		print("%-14s %4.0fm  %5.0f%% %5.0f%% %5.0f%%  %7.1fs %7.1fs  %6.0f%%  melee (%s)" % [type, distance,
				share * 100.0, r.loss / total * 100.0, r.draw / total * 100.0,
				r.ttk_win / maxf(r.win, 1), r.ttk_loss / maxf(r.loss, 1), r.hp / maxf(r.win, 1) * 100.0,
				_targets[type].role])
		return
	var band: Vector2 = _targets[type].win
	var verdict := "ok" if share >= band.x and share <= band.y else ("TOO HARD" if share < band.x else "TOO EASY")
	print("%-14s %4.0fm  %5.0f%% %5.0f%% %5.0f%%  %7.1fs %7.1fs  %6.0f%%  %.0f-%.0f%% %s (%s)" % [type, distance,
			share * 100.0, r.loss / total * 100.0, r.draw / total * 100.0,
			r.ttk_win / maxf(r.win, 1), r.ttk_loss / maxf(r.loss, 1), r.hp / maxf(r.win, 1) * 100.0,
			band.x * 100.0, band.y * 100.0, verdict, _targets[type].role])


func _make_ref(at: Vector3, equip_seed: int) -> Actor:
	var ref := _raid.spawn_bot("Ref%d" % equip_seed, at, equip_seed, false, "ref", 0, _ref_kit)
	ref.display_name = "Reference"
	_brain(ref, equip_seed, Vector2(REF_SKILL, REF_SKILL), true)
	_seed_guns(ref, equip_seed)
	return ref


func _make_enemy(type: String, at: Vector3, equip_seed: int) -> Actor:
	var def: Dictionary = _targets[type]
	var bot: Actor
	if def.has("faction"):
		# Built as the faction's own marker would build it.
		bot = _raid.spawn_bot("Foe%d" % equip_seed, at, equip_seed, false, def.faction, def.zone)
		_brain(bot, equip_seed, _world.bot_skill_range(bot, false), false)
		_seed_guns(bot, equip_seed)
		return bot
	match def.kind:
		"raider":
			var rng := RandomNumberGenerator.new()
			rng.seed = equip_seed
			bot = _raid.spawn_bot("Foe%d" % equip_seed, at, equip_seed, false, "raider:Foe", def.zone,
					_world.raider_kit(rng))
			var brain := _brain(bot, equip_seed, _world.raider_skill, true)
			brain.flies = bot.flight.enabled
		"warlord":
			# Rolled until the world would let it be a warlord
			# (`WorldDef.bot_allowed`: never a walker).
			var try_seed := equip_seed
			while true:
				bot = _raid.spawn_bot("Foe%d" % try_seed, at, try_seed, true, "", def.zone)
				if bot.get_meta("kind", "") != "walker":
					break
				_raid._remove_actor(bot)
				try_seed += 7919
			_brain(bot, equip_seed, _world.bot_skill_range(bot, true), false)
		_:
			# The world rolls the kind from the seed (its meta "kind", or for
			# a world that sets none, a blade means a heavy): try seeds until
			# it gives the kind asked for.
			var try_seed := equip_seed
			while true:
				bot = _raid.spawn_bot("Foe%d" % try_seed, at, try_seed, false, "", def.zone)
				var kind: String = bot.get_meta("kind",
						"heavy" if bot.get_active_weapon() is MeleeWeapon else "soldier")
				if kind == def.kind:
					break
				_raid._remove_actor(bot)
				try_seed += 7919
			_brain(bot, equip_seed, _world.bot_skill_range(bot, false), false)
	_seed_guns(bot, equip_seed)
	return bot


## Guns draw their spread from an unseeded generator, so the same duel would
## not repeat. Pin it from the duel seed; the fights stay a sample, and the
## table can be run again.
func _seed_guns(actor: Actor, salt: int) -> void:
	var i := 0
	for weapon in actor.weapons:
		var gun := weapon as Gun
		if gun:
			gun._rng.seed = hash(salt * 1000 + i)
		i += 1


func _brain(actor: Actor, brain_seed: int, skill_range: Vector2, kit: bool) -> BotBrain:
	var brain := BotBrain.new()
	brain.name = "Brain"
	brain.seed_value = brain_seed
	brain.skill_range = skill_range
	brain.uses_kit = kit
	# A duel is a stand-up fight: nobody wanders off to patrol.
	brain.patrol_radius = 2.0
	actor.add_child(brain)
	return brain


func _face(actor: Actor, other: Actor) -> void:
	var to := other.global_position - actor.global_position
	actor.cmd.yaw = atan2(-to.x, -to.z)


func _stop(actor: Actor) -> void:
	var brain := actor.get_node_or_null("Brain")
	if brain:
		brain.set_physics_process(false)
	actor.cmd.apply_array(ActorCommand.new().to_array())


func _arg(args: PackedStringArray, key: String, fallback: String) -> String:
	var at := args.find(key)
	return args[at + 1] if at >= 0 and at + 1 < args.size() else fallback


## Open, flat ground with nothing on it, and the source world's rules and
## soldiers. No armies, events or raiders of its own.
class Field extends WorldDef:
	var source: WorldDef
	var rows := 30

	func _init() -> void:
		id = "duel_field"
		display_name = "Duel field"
		bot_count = 0
		raider_count = 0
		event_interval = 0.0
		power_weapon_rate = 0.0
		war_scale = 0.0
		assault_size = 0

	func create_map() -> Node3D:
		var map := Node3D.new()
		var floor_body := StaticBody3D.new()
		floor_body.collision_layer = Actor.LAYER_WORLD
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		var span := SPACING * (6.0 + ceilf(rows / 6.0)) + 200.0
		box.size = Vector3(span, 1.0, span)
		shape.shape = box
		floor_body.add_child(shape)
		floor_body.position = Vector3(span * 0.4, -0.5, span * 0.4)
		map.add_child(floor_body)
		return map

	func can_damage(attacker: Node, target: Node, info: DamageInfo) -> bool:
		return source.can_damage(attacker, target, info)

	func equip_bot(bot: Actor, rng: RandomNumberGenerator) -> void:
		source.equip_bot(bot, rng)

	func make_warlord(bot: Actor) -> void:
		source.make_warlord(bot)

	func bot_skill_range(bot: Actor, warlord: bool) -> Vector2:
		return source.bot_skill_range(bot, warlord)

	func zone_at(pos: Vector3) -> int:
		return 1
