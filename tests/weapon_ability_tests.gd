extends RefCounted
## Checks the first weapon ability, the Breaker Hammer's ground pound
## (`MeleeWeapon.weapon_ability`): its own key and press on the wire, a
## windup anyone can read, a ring that knocks everyone on the ground near
## back and off their feet, a guard that stops it, and a cooldown
## (`-- --groups weapon_ability` runs just these).

const Arsenal := preload("res://tests/melee_arsenal_tests.gd")

const HAMMER := "hammer_breaker"


static func run(t: Node) -> void:
	_data(t)
	_wire(t)
	await _in_raid(t)


static func _data(t: Node) -> void:
	print("Weapon ability: the data")
	var hammer := Arsenal._make(HAMMER)
	t.check(hammer.ability == "ground_pound", "the Breaker Hammer has the ground pound")
	t.check(hammer.ability_windup > hammer.heavy_windup,
			"the pound winds up longer than a heavy, so anyone near can read it (%.2f s)" % hammer.ability_windup)
	t.check(hammer.ability_cooldown >= 8.0, "and it is spent for a while after (%.0f s)" % hammer.ability_cooldown)
	t.check(hammer.ability_damage < hammer.light_damage, "it knocks people down more than it hurts them")
	hammer.free()
	var unknown := []
	for id: String in ItemDB.all_ids():
		var picked := str(ItemDB.item_stats(id).get("ability", ""))
		if ItemDB.has_tag(id, "melee") and picked != "" and not MeleeWeapon.ABILITY_NAMES.has(picked):
			unknown.append(id)
	t.check(unknown.is_empty(), "every melee ability an item names is one the weapon knows (%s)" % [unknown])
	var knife := Arsenal._make("knife_gutter")
	var sword := Arsenal._make("blade_scrap")
	t.check(knife.ability == "shadow_step" and sword.ability == "counter_stance",
			"the knife has the shadow step and the sword the counter stance")
	t.check(knife.ability_windup >= 0.25, "the step crouches first, a tell you can see (%.2f s)" % knife.ability_windup)
	knife.free()
	sword.free()
	t.check(InputMap.has_action("weapon_ability"), "the weapon ability has a key of its own")


static func _wire(t: Node) -> void:
	print("Weapon ability: the press travels")
	var cmd := ActorCommand.new()
	cmd.weapon_ability_pressed = true
	cmd.lamp = true
	cmd.kick_pressed = true
	t.check(ActorCommand.ONE_SHOT_MASK & ActorCommand.FLAG_WEAPON_ABILITY_PRESSED != 0
			and ActorCommand.HELD_MASK & ActorCommand.FLAG_WEAPON_ABILITY_PRESSED == 0, "the press is a one-shot")
	var sent: Array = NetSession.unpack_inputs(NetSession.pack_inputs([[1, cmd.to_array(), 0]]))[0][1]
	var back := ActorCommand.new()
	back.apply_array(sent)
	t.check(ActorCommand.STATE_KNOCKED_DOWN > ActorCommand.FLAG_WEAPON_ABILITY_PRESSED
			and (ActorCommand.HELD_MASK | ActorCommand.ONE_SHOT_MASK) & ActorCommand.STATE_KNOCKED_DOWN == 0,
			"a knockdown is a state bit, never an input")
	t.check(back.weapon_ability_pressed and back.lamp and back.kick_pressed,
			"the press crosses the wire in its own byte, past the first 32 bits, and leaves the others alone")
	cmd.weapon_ability_pressed = false
	sent = NetSession.unpack_inputs(NetSession.pack_inputs([[1, cmd.to_array(), 0]]))[0][1]
	back.apply_array(sent)
	t.check(not back.weapon_ability_pressed and back.lamp, "and no press stays no press")
	back.weapon_ability_pressed = true
	back.clear_one_shots()
	t.check(not back.weapon_ability_pressed, "it lasts one tick")


static func _press(t: Node, p: Actor) -> void:
	p.cmd.weapon_ability_pressed = true
	await t.frames(1)
	p.cmd.weapon_ability_pressed = false


static func _in_raid(t: Node) -> void:
	print("Weapon ability: the ground pound in a fight")
	var raid: Raid = await t._new_raid(53, false)
	var setup: Array = await t._duel(raid)
	var p: Actor = setup[0]
	var foe: Actor = setup[1]
	var foe_blade: MeleeWeapon = setup[2]
	foe.health.max_health = 500.0
	p.protected_left = 0.0
	foe.protected_left = 0.0
	var hammer := await Arsenal._arm(t, p, HAMMER)

	# In range and on the ground: knocked back, off its feet.
	Arsenal._reset(foe)
	Arsenal._place(p, foe, 3.0)
	await t.frames(2)
	var start := foe.global_position
	var health := foe.health.health
	var stamina := p.stamina
	await _press(t, p)
	t.check(hammer.is_pounding() and hammer.is_winding_up(), "the pound winds up first")
	t.check(p.stamina < stamina, "and costs stamina")
	await t.frames(int(hammer.ability_windup * 60.0) - 6)
	t.check(foe.health.health == health and foe.stagger_left <= 0.0, "nothing lands during the windup")
	await t.frames(10)
	t.check(is_equal_approx(health - foe.health.health, hammer.ability_damage),
			"it lands for a little damage (%.0f)" % (health - foe.health.health))
	t.check(foe.knocked_left > 0.5 and foe.stagger_left > 0.5,
			"and knocks the foe off its feet (down for %.2f s)" % foe.knocked_left)
	await t.frames(30)
	var pushed := Vector2(foe.global_position.x - start.x, foe.global_position.z - start.z)
	t.check(pushed.y < -1.0, "and back, away from the hammer (%.1f m)" % pushed.length())
	t.check(hammer.ability_left > hammer.ability_cooldown - 2.0, "then it cools down")
	# The server's word on it reaches every view through the state.
	var net := NetSession.new()
	net.raid = raid
	net._actors[7] = foe
	var entry := net._state_entry(7, 0)
	t.check(int(entry[3][ActorCommand.FLAGS_INDEX]) & ActorCommand.STATE_KNOCKED_DOWN != 0,
			"the state a client is sent says the foe is down")
	var left := foe.knocked_left
	foe.knocked_left = 0.0
	net._apply_state(foe, entry, false)
	t.check(foe.knocked_left > 0.0 and absf(foe.knocked_left - foe.stagger_left) < 0.05,
			"and a client puts it down for what is left (%.2f of %.2f s)" % [foe.knocked_left, left])
	net.free()
	await t.frames(int(foe.knocked_left * 60.0) + 2)
	t.check(foe.knocked_left <= 0.0, "and the foe gets back up")

	# Spent: a second press does nothing until it has cooled.
	await t.frames(int(hammer.ability_recover * 60.0) + 10)
	Arsenal._reset(foe)
	Arsenal._place(p, foe, 3.0)
	stamina = p.stamina
	await _press(t, p)
	t.check(not hammer.is_winding_up() and p.stamina == stamina, "a press while it cools does nothing")
	t.check(hammer.status_text().contains("pound in"), "the weapon line says when it is back: %s" % hammer.status_text())

	# Out of the ring, or above it, nothing.
	hammer.ability_left = 0.0
	Arsenal._reset(foe)
	Arsenal._place(p, foe, hammer.ability_radius + 2.0)
	await t.frames(2)
	health = foe.health.health
	await _press(t, p)
	await t.frames(int(hammer.ability_windup * 60.0) + 4)
	t.check(foe.health.health == health and foe.stagger_left <= 0.0, "past the ring's edge it does nothing")
	await t.frames(int(hammer.ability_recover * 60.0) + 4)
	hammer.ability_left = 0.0
	Arsenal._reset(foe)
	await _press(t, p)
	await t.frames(int(hammer.ability_windup * 60.0) - 2)
	Arsenal._place(p, foe, 2.0, 3.0)
	foe.velocity = Vector3.ZERO
	health = foe.health.health
	await t.frames(4)
	t.check(foe.health.health == health and foe.stagger_left <= 0.0, "a flier above it is not touched")
	await t.frames(int(hammer.ability_recover * 60.0) + 30)

	# A guard raised in time stops it, like any melee hit.
	hammer.ability_left = 0.0
	Arsenal._reset(foe)
	Arsenal._place(p, foe, 3.0)
	foe.cmd.secondary = true
	await t.frames(30)
	Arsenal._place(p, foe, 3.0)
	health = foe.health.health
	await _press(t, p)
	await t.frames(int(hammer.ability_windup * 60.0) + 4)
	t.check(foe.health.health == health and foe_blade.is_blocking() and foe.stagger_left <= 0.0,
			"a raised guard stops it and keeps its feet")
	foe.cmd.secondary = false
	await t.frames(2)

	# A bot with the hammer uses it when foes crowd it.
	var brain := foe.get_node_or_null("Brain") as BotBrain
	if brain == null:
		t.check(false, "the foe has a brain to ask")
		return
	var bot_hammer := await Arsenal._arm(t, foe, HAMMER)
	Arsenal._reset(foe)
	Arsenal._place(p, foe, 3.0)
	await t.frames(2)
	brain.target = p
	brain.pound_alone_chance = 0.0
	t.check(not brain._wants_pound(bot_hammer), "a bot keeps the pound for a crowd, one foe alone is not worth it")
	brain.pound_alone_chance = 1.0
	t.check(brain._wants_pound(bot_hammer), "but sometimes uses it on one")
	bot_hammer.ability_left = 5.0
	t.check(not brain._wants_pound(bot_hammer), "never while it cools")
	bot_hammer.ability_left = 0.0
	Arsenal._place(p, foe, bot_hammer.ability_radius + 1.0)
	t.check(not brain._wants_pound(bot_hammer), "nor with the foe outside the ring")
	# Each other ability has its moment.
	var bot_axe := await Arsenal._arm(t, foe, "axe_splitter")
	Arsenal._place(p, foe, 2.0)
	t.check(brain._wants_ability(bot_axe, true) and not brain._wants_ability(bot_axe, false),
			"a bot hooks a raised guard, and only a raised guard")
	var bot_sword := await Arsenal._arm(t, foe, "blade_scrap")
	var mine := await Arsenal._arm(t, p, "")
	Arsenal._place(p, foe, 2.0)
	t.check(not brain._wants_ability(bot_sword, false), "a bot keeps its counter stance until a swing comes")
	mine._begin_windup("heavy", 1.0, 0.5)
	t.check(brain._wants_ability(bot_sword, false), "and takes it into a swing coming")
	await t.frames(40)

	await _shadow_step(t, raid, p, foe)
	await _counter_stance(t, p, foe)
	await _guard_hook(t, p, foe)
	await _trip(t, p, foe)
	await _vault(t, p)


## The knife steps through behind the foe in front, facing their back.
static func _shadow_step(t: Node, raid: Raid, p: Actor, foe: Actor) -> void:
	print("Weapon ability: the knife's shadow step")
	var foe_blade := await Arsenal._arm(t, foe, "")
	var knife := await Arsenal._arm(t, p, "knife_gutter")
	Arsenal._reset(foe)
	Arsenal._place(p, foe, 6.5)
	await t.frames(2)
	var stamina := p.stamina
	await _press(t, p)
	t.check(not knife.is_winding_up() and p.stamina >= stamina and knife.ability_left <= 0.0,
			"with no foe in reach the step does nothing and costs nothing")
	Arsenal._place(p, foe, 3.5)
	await t.frames(2)
	var start := p.global_position
	await _press(t, p)
	t.check(knife.is_winding_up(), "in reach, it crouches first")
	t.check(p.global_position.distance_to(start) < 0.3, "and has not moved yet")
	await t.frames(int(knife.ability_windup * 60.0) + 3)
	var foe_back := foe.global_position - foe.get_aim_dir() * Vector3(1, 0, 1)
	t.check(p.global_position.distance_to(foe_back) < 1.0,
			"then it is behind the foe (%.1f m from its back)" % p.global_position.distance_to(foe_back))
	t.check(not is_nan(p.turn_request) or MeleeWeapon.is_behind(foe, p.global_position, 180.0),
			"facing their back")
	p.turn_request = NAN
	t.check(MeleeWeapon.is_behind(foe, p.global_position, knife.backstab_arc_deg), "where the knife's cut is a backstab")
	t.check(knife.ability_left > knife.ability_cooldown - 1.0, "then it cools down")
	foe_blade.light_stamina = 0.0


## A sword in counter stance turns a cut aside and answers with a riposte.
static func _counter_stance(t: Node, p: Actor, foe: Actor) -> void:
	print("Weapon ability: the sword's counter stance")
	var foe_blade := await Arsenal._arm(t, foe, "")
	foe_blade.light_windup = 0.3
	foe_blade.light_tell = 0.0
	var sword := await Arsenal._arm(t, p, "blade_scrap")
	Arsenal._reset(foe)
	Arsenal._place(p, foe, 2.0)
	p.cmd.yaw = 0.0
	p.cmd.aim_dir = Vector3.FORWARD
	await t.frames(30)
	Arsenal._place(p, foe, 2.0)
	p.health.health = p.health.max_health
	await _press(t, p)
	t.check(sword.is_countering() and sword.is_guard_shown(), "the sword takes its counter stance, the guard shown")
	var foe_health := foe.health.health
	var health := p.health.health
	foe_blade._strike(foe_blade.light_damage, "light")
	t.check(p.health.health == health, "a cut into it does nothing")
	t.check(foe.stagger_left > 0.0 and not sword.is_countering(), "the cutter is staggered and the stance is spent")
	await t.frames(12)
	t.check(foe.health.health < foe_health, "and the riposte answers at once (%.0f)" % (foe_health - foe.health.health))
	# Held out, the stance ends by itself and leaves the sword free.
	await t.frames(int(sword.ability_recover * 60.0) + 30)
	sword.ability_left = 0.0
	await _press(t, p)
	await t.frames(int(sword.ability_windup * 60.0) + 2)
	t.check(not sword.is_countering(), "a stance nobody cuts into ends by itself")


## The axe hooks a held guard open and pulls its owner a step in.
static func _guard_hook(t: Node, p: Actor, foe: Actor) -> void:
	print("Weapon ability: the axe's guard hook")
	var foe_blade := await Arsenal._arm(t, foe, "")
	var axe := await Arsenal._arm(t, p, "axe_splitter")
	Arsenal._reset(foe)
	Arsenal._place(p, foe, 2.6)
	foe.cmd.secondary = true
	await t.frames(30)
	Arsenal._place(p, foe, 2.6)
	var start := foe.global_position
	var health := foe.health.health
	await _press(t, p)
	t.check(axe.is_winding_up(), "the hook winds up first")
	await t.frames(int(axe.ability_windup * 60.0) + 2)
	t.check(not foe_blade.is_blocking() and foe.stagger_left > 0.0, "and tears a held guard open")
	t.check(foe.health.health < health, "through it, for a little damage (%.0f)" % (health - foe.health.health))
	foe.cmd.secondary = false
	await t.frames(12)
	t.check(foe.global_position.distance_to(p.global_position) < start.distance_to(p.global_position) - 0.3,
			"and pulls the foe a step in")
	await t.frames(int(axe.ability_recover * 60.0) + 10)


## The hook blade trips the foe in front off its feet; a guard stops it.
static func _trip(t: Node, p: Actor, foe: Actor) -> void:
	print("Weapon ability: the hook blade's trip")
	var foe_blade := await Arsenal._arm(t, foe, "")
	var hook := await Arsenal._arm(t, p, "blade_hook")
	Arsenal._reset(foe)
	Arsenal._place(p, foe, 2.0)
	await t.frames(30)
	Arsenal._place(p, foe, 2.0)
	await _press(t, p)
	await t.frames(int(hook.ability_windup * 60.0) + 2)
	t.check(foe.knocked_left > 0.5, "the trip knocks the foe down (%.2f s)" % foe.knocked_left)
	await t.frames(int(foe.knocked_left * 60.0) + 30)
	hook.ability_left = 0.0
	Arsenal._reset(foe)
	Arsenal._place(p, foe, 2.0)
	foe.cmd.secondary = true
	await t.frames(30)
	Arsenal._place(p, foe, 2.0)
	await _press(t, p)
	await t.frames(int(hook.ability_windup * 60.0) + 2)
	t.check(foe.knocked_left <= 0.0 and foe_blade.is_blocking(), "a raised guard stops it")
	foe.cmd.secondary = false
	await t.frames(int(hook.ability_recover * 60.0) + 10)


## The spear vaults up and ahead off its planted point.
static func _vault(t: Node, p: Actor) -> void:
	print("Weapon ability: the spear's vault")
	var spear := await Arsenal._arm(t, p, "spear_lancer")
	await t.frames(30)
	var start := p.global_position
	await _press(t, p)
	t.check(spear.is_winding_up() and p.is_on_floor(), "the spear is planted first")
	var top := start.y
	for i in int(spear.ability_windup * 60.0) + 40:
		await t.frames(1)
		top = maxf(top, p.global_position.y)
	var ahead := Vector2(p.global_position.x - start.x, p.global_position.z - start.z)
	t.check(top - start.y > 2.0, "then the body vaults up (%.1f m)" % (top - start.y))
	t.check(ahead.length() > 2.0 and ahead.y < 0.0, "and ahead, the way it faces (%.1f m)" % ahead.length())
