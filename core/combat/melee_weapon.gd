class_name MeleeWeapon
extends Weapon
## Blade-style melee.
##
## Attacks: a three-hit light combo, a heavy lunge, and a dive slam from the air.
## All on one button: a tap is a light attack, and holding past `hold_time`
## charges into the heavy (or the dive slam in the air). The tap strikes on
## release; the heavy shows its full windup once the charge turns into it.
## Every attack has a windup you can see, which is what makes parrying possible.
## A press made while the blade is still busy (mid-swing or recovering) is kept
## for `press_buffer` and plays as soon as it is free, so combos chain without
## pixel-perfect timing. The time a tap was held counts toward its windup.
## A heavy lunges at the foe in front of you and stops at striking distance; in
## the air, with an airborne foe in the aim cone, it becomes the magnetic
## air-lunge instead of a dive slam.
## Sprinting, the heavy is a dash-strike instead: it closes up to `dash_range`
## on the foe in front within the same windup, so a blade can reach a gunner.
## Backing away (move back) with a foe right behind you, a light attack is a
## back strike: a reverse stab behind you for `back_strike_mult`.
## Defense: hold block to stop hits from the front at a stamina cost. Raising the
## guard just before a hit lands is a parry: no damage, the attacker is
## staggered, and your next hit is a stronger riposte. Against small-arms fire
## the fresh guard deflects every round from the front for `deflect_window`; after
## that a held guard only turns aside part of each. A guard raised again too
## soon after the last (`guard_rearm`) gets no parry or deflect, so it has to
## be timed rather than spammed.
## Blades are quiet and slip past armor: melee hits ignore armor
## (`armor_pierce`) and never make noise (`Combat.noise`), so a blade kill does
## not bring the next patrol. Each melee item is tagged "one_handed" (moves
## faster) or "two_handed" (moves slower, and its heavies stagger and break
## armor), read with `is_two_handed_id`.
##
## Everything is directional. The actor's command carries a stance (overhead,
## left or right). An attack swings toward its stance: a left swing starts on
## your right and ends on your left (Caleb's call), so it comes from the
## mirrored side (`swing_from`). A guard covers the side of its stance, and
## only stops a melee hit that arrives at that side, so you read the enemy's
## windup and they read yours. Two fighters who both pick left meet: the left
## swing arrives on the defender's left.

signal swung(kind: String)
signal blocked_hit(info: DamageInfo)
signal parried_hit(info: DamageInfo)
## A strike reached `target`: emitted on every machine the swing is simulated
## on, before the server decides the damage, so the attacker's own view can
## answer at once. `outcome` is the local guess: "hit", "block" or "parry".
signal contact(target: Actor, outcome: String, at: Vector3)

enum Dir { OVERHEAD, LEFT, RIGHT }

const DIR_NAMES := ["overhead", "left", "right"]
const REST_POSE := -0.45
const GUARD_POSE := 0.25
const SWING_TIME := 0.16
## The shown swing starts this long before the strike lands (at most
## `SWING_LEAD_SHARE` of the windup), so the blade accelerates into the hit
## and arrives as the damage does, then eases out through the follow-through
## (`swing_arc`). View only: the strike still lands when the windup ends.
const SWING_LEAD := 0.09
const SWING_LEAD_SHARE := 0.6
## A two-hander's swing leads and follows through this much slower, so it
## shows its weight.
const TWO_HAND_SWING := 1.35
const WINDUP_ROLL := 1.1
## Where the blade ends its swing; recovery eases back from here to rest.
const FOLLOW_THROUGH := -2.1
## A strike counts this much of a body's width beyond `reach` and the arc,
## so one that visibly reaches someone's shoulder is not a miss.
const HIT_ALLOWANCE := 0.2
## How far to the side a side swing starts and ends, beside the hand.
const SIDE_REACH := 0.28
## A side swing sweeps across, more flat than a chop: its pitch at the start
## and the end.
const SIDE_SWING_FROM := 0.5
const SIDE_SWING_TO := -1.0
## The blade's pitch for a thrust, drawn back and driven out (point
## forward), and for a chop, raised behind the shoulder.
const THRUST_COCKED := -1.35
const THRUST_OUT := -1.6
const CHOP_RAISED := 1.45
## How long a landed strike holds the swing still (view only); a
## two-hander's lands with `TWO_HAND_HITSTOP` times the pause, its weight.
const HITSTOP := 0.06
const TWO_HAND_HITSTOP := 1.8
## How long a strike met by a guard holds still, while the two blades meet
## at one point (`ActionPose.bind`; view only).
const BIND_HOLD := 0.12
## Where the blade is held, relative to the hand, for each guard.
const GUARD_OFFSET_OVERHEAD := Vector3(-0.25, 0.3, 0.0)
const GUARD_OFFSET_LEFT := Vector3(-0.5, 0.05, 0.0)
const GUARD_OFFSET_RIGHT := Vector3(0.12, 0.05, 0.0)

## Hold the attack button this long and it becomes a heavy instead of a light.
var hold_time := 0.25
## A press made while the blade is busy is kept this long and plays once it is
## free. Held, it keeps charging toward a heavy meanwhile.
var press_buffer := 0.35
## The time a tap was held counts toward its light windup, down to this share
## of `light_windup`, so a tap answers quickly but still shows a windup.
var light_windup_floor := 0.5

var light_damage := 28.0
var heavy_damage := 65.0
var reach := 2.8
var arc_deg := 110.0
var light_windup := 0.1
var light_recover := 0.28
var combo_finisher_mult := 1.5
var combo_window := 0.9
var heavy_windup := 0.4
var heavy_recover := 0.5
## Speed of the heavy lunge, m/s, held through the windup. It carries you at
## most `heavy_lunge * heavy_windup` metres, and stops at striking distance
## from the foe it aims at.
var heavy_lunge := 9.0
## With nobody to lunge at, a heavy still steps this far forward.
var heavy_step := 1.0
## Lunges stop with the foe this far inside `reach`.
var lunge_stop := 0.6
## Foes within this cone of the aim are lunged at.
var lunge_cone_deg := 60.0
## A light attack steps in up to this far when the foe is just out of reach.
var light_step := 0.3
## The magnetic air-lunge: a heavy in the air at an airborne foe within this
## range and cone pulls you to them (design doc, "Melee air-lunge").
var air_lunge_range := 6.0
var air_lunge_cone_deg := 40.0
## What is left of the lunge's speed once it has carried you there.
var air_lunge_keep := 0.35
var slam_damage := 55.0
var slam_radius := 4.5
var slam_fall_speed := 32.0

var light_stamina := 10.0
var heavy_stamina := 28.0
var slam_stamina := 20.0

## Hits from within this arc in front of you can be blocked.
var block_arc_deg := 130.0
## A guard raised this recently counts as a parry.
var parry_window := 0.22
var block_stamina_per_damage := 0.6
## Blocking rewards timing over holding (Caleb's call): a guard raised
## within `timed_window` of a hit is a timed block and pays only
## `timed_block_cost` of the stamina; a guard held longer drains
## `hold_drain` stamina a second, growing by `hold_drain_ramp` of it for
## every second held, and pays full price for every hit.
var timed_window := 0.4
var timed_block_cost := 0.15
var hold_drain := 5.0
var hold_drain_ramp := 0.6
## Blade against blade, every light shows this long more windup than its
## weapon's own, so a defender can see it coming and time a guard (counted
## from the press, the hold of the tap included). Against anyone without a
## blade drawn the cut stays quick, so a blade still beats a gun in reach
## (`facing_blade`).
var light_tell := 0.2
## A blade only turns aside part of a bullet.
var bullet_block_fraction := 0.5
## Bullets from the front within this long of raising the guard are deflected
## outright, each costing `deflect_stamina`.
var deflect_window := 0.3
var deflect_stamina := 4.0
## Rounds from guns with any of these tags are not small arms: no guard
## deflects or blocks them (Caleb's call: no deflecting sniper rounds or
## explosives; blasts are not "bullet" hits at all).
var undeflectable_tags: Array[String] = ["power", "marksman", "sniper"]
## A guard raised within this long of the last one dropping gets no parry,
## deflect or timed block, so mashing the guard is not timing. A guard that
## met a hit in time (`_guard_paid`) is rearmed at once.
var guard_rearm := 0.4
var parry_stagger := 1.1
## A blow that lands on someone winding up or charging a swing cuts it off
## and holds them this long: the quicker blade wins a trade. A guard or a
## body at rest is never held, so a landed light never locks anyone up.
var interrupt_stagger := 0.3
## Two strikes meeting: a blow that arrives while the foe's own swing is
## within `clash_window` of landing is a clash; neither cuts, both are
## knocked back for `clash_stagger` and the blades meet.
var clash_window := 0.08
var clash_stagger := 0.35
## A heavy cancelled early in its windup (aim pressed before its last
## `SWING_LEAD`) is a feint: it costs `feint_stamina` and the guard comes up.
var feint_stamina := 12.0
## A heavy thrown straight after a light, inside the combo window, comes
## `combo_heavy_speed` of the time and from the side the next light would,
## so lights and a heavy flow as one string.
var combo_heavy_speed := 0.8
## The kick (V): breaks a held guard (`kick_guard_stagger`, through any
## guard, unblockable), costs `kick_stamina`, shows a slow windup a swing
## beats (`kick_windup`, longer than a light's) and leaves its kicker open
## after (`kick_recover`). Reaches `kick_reach` within `kick_arc_deg`.
var kick_windup := 0.38
var kick_recover := 0.4
var kick_reach := 2.0
var kick_arc_deg := 80.0
var kick_damage := 6.0
var kick_stamina := 15.0
var kick_guard_stagger := 0.85
var guard_break_stagger := 0.9
## A weapon ability (`ActorCommand.weapon_ability_pressed`, a key of its
## own), picked by the item's stats: "" for none. "ground_pound" (the
## hammer): on the ground, the weapon goes up over the head for
## `ability_windup`, longer than a heavy's so anyone near can read it and
## dodge, block or step out, then is driven into the ground. A shock ring
## reaches everyone on the ground within `ability_radius` for a little
## damage (`ability_damage`, through `Combat.deal`, so a guard blocks it and
## a parry staggers the pounder) and knocks them back off their feet: down
## for `ability_knockdown` (`Actor.knock_down`) and shoved out and up
## (`ability_knock`, `ability_lift`, less at the ring's edge). Then it is spent for
## `ability_cooldown` seconds, from the press.
## "shadow_step" (the knife): a short crouch (`ability_windup`), then a step
## through to just behind the foe in front within `ability_radius`, turned
## to face their back, where the knife's cut is a backstab. With no foe in
## front it does nothing and costs nothing.
## "counter_stance" (swords): the blade held up for `ability_windup`; a melee
## hit that lands on it from the front is turned aside (a parry, the
## attacker staggered) and answered at once with a quick riposte cut. It
## ends on the first hit, and leaves its user open while it lasts to a
## kick, which goes through any guard.
## "guard_hook" (axes): a windup (`ability_windup`), then the axe's beard
## hooks the foe in front within `ability_radius`: through any guard (a
## held guard is torn open, `guard_break_stagger`), a little damage, and a
## pull a step toward the axe (`ability_knock`). A dodge slips it.
## "vault" (spears): the spear is planted (`ability_windup`) and the body
## vaults up and ahead (`ability_lift`, `ability_knock`); from the top of
## the arc the heavy is the spear's dive slam or air-lunge.
## "trip" (the hook blade): a low hooked cut (`ability_windup`) at the foe in
## front within `ability_radius`, blockable like any cut, that knocks them
## down for `ability_knockdown`.
var ability := ""
var ability_windup := 0.65
var ability_recover := 0.7
var ability_cooldown := 12.0
var ability_radius := 5.0
var ability_damage := 12.0
var ability_knockdown := 1.4
var ability_knock := 10.0
var ability_lift := 5.0
var ability_stamina := 25.0
## Who is higher above (or below) the pounder than this rides over the ring.
const POUND_HEIGHT := 1.5
## What each ability is called on the weapon line and in the controls.
const ABILITY_NAMES := {"ground_pound": "pound", "shadow_step": "shadow step", "counter_stance": "counter",
		"guard_hook": "hook", "vault": "vault", "trip": "trip"}
## How wide in front the hook and the trip reach, in degrees.
const ABILITY_ARC_DEG := 80.0
## How far behind the foe's back a shadow step lands, and the windup of the
## riposte a counter stance answers with.
const STEP_BEHIND := 1.3
const COUNTER_ANSWER := 0.08
var riposte_window := 1.6
var riposte_mult := 1.5

## What sets one melee type apart. The defaults change nothing, so a weapon
## only gets the traits its item stats ask for.
## Hits on someone facing away, from outside their front `backstab_arc_deg`,
## are multiplied by this. A guard never covers the back anyway.
var backstab_mult := 1.0
var backstab_arc_deg := 180.0
## A guard that stops this weapon's hit pays this many times the usual stamina,
## so heavy chopping breaks guards.
var guard_crush := 1.0
## How far above or below you a swing still connects. Long reach pokes fliers.
var vertical_reach := 2.5
## Targets closer than this are inside the point and take `close_mult` damage.
var close_range := 0.0
var close_mult := 1.0
## A heavy hit that lands unblocked staggers the target for this long.
var heavy_stagger := 0.0

## Share of a melee hit that goes past armor (`DamageInfo.armor_pierce`).
var armor_pierce := 1.0
## Armor a hit tears off, as a share of its damage (`DamageInfo.armor_break`).
var armor_break := 0.0
## The hold class, from the item's "one_handed" or "two_handed" tag: walk
## speed with it in hand, and what a two-hander adds to its heavies.
var one_hand_speed := 1.08
var two_hand_speed := 0.9
## Overrides the hold class's speed when above zero (the knife is lighter).
var move_mult := 0.0
var two_hand_stagger := 0.7
var two_hand_armor_break := 0.5

## How the attacks look, from the item's stats (view only): "slash" sweeps an
## arc (swords), "thrust" stabs straight out along the aim (the spear),
## "chop" comes down from over the shoulder (the axe, the hammer), "cut"
## is a two-handed sword's kenjutsu cuts (the katana, `ActionPose.cuts`).
## `heavy_style` gives the heavy its own, "" for the same. `swing_scale`
## sizes the motion (a knife's are small and tight).
var swing_style := "slash"
var heavy_style := ""
var swing_scale := 1.0

## The dash-strike: a heavy started while sprinting reaches a foe up to this
## far away (flat metres past striking distance), over the heavy's windup.
var dash_range := 9.0
## Extra stamina a heavy pays when it dashes further than a plain lunge.
var dash_stamina := 12.0
## A charge: a heavy started at a sprint at a foe out of reach runs its
## whole `dash_range` toward them instead of stopping at striking distance,
## so a foe who steps aside lets it run on past (into whatever stands
## behind).
var dash_through := false
## A light attack while moving back, with a foe behind in reach, strikes
## behind you for this much more. Zero turns the move off.
var back_strike_mult := 1.4

## The stance the actor is asking for right now.
var stance := Dir.OVERHEAD
## The side the current or last attack comes from, as the attacker sees it:
## `swing_from(stance)` when it started, so a left swing comes from the right.
var attack_dir := Dir.OVERHEAD
## The side the guard covers, as the defender sees it. Set when it is raised.
var guard_dir := Dir.OVERHEAD

var combo_step := 0
var _cooldown := 0.0
var _combo_timer := 0.0
var _windup_left := 0.0
var _windup_kind := ""
var _windup_damage := 0.0
var _slamming := false
var _blocking := false
var _block_time := 0.0
## Seconds since the guard last dropped, for `guard_rearm`.
var _since_guard := 99.0
## The guard now up was raised in time to parry or deflect.
var _parry_ready := true
## The guard up now met a hit with a parry or timed block.
var _guard_paid := false
## The aim (guard) button was down last tick: a press is its edge.
var _aim_was := false
## Whether a blade faces this guard (`facing_blade`), looked at every
## quarter second while it is held.
var _blade_near := false
var _blade_check := 0.0
## The command asked to sprint this tick: a heavy now is a dash-strike.
var _sprinting := false
## The lunge in progress is a dash-strike (status and tests).
var _dashing := false
## The command is moving back this tick: a light now may be a back strike.
var _backing := false
## The light winding up strikes behind (`back_strike_mult`).
var _back_strike := false
var _swing_left := 0.0
## Seconds the attack button has been held, or below zero when not charging.
var _charge := -1.0
## A press made while busy, waiting to play (`press_buffer`).
var _queued := false
var _queued_age := 0.0
## How long the queued press has been held, or below zero once let go.
var _queued_held := 0.0
## The lunge in progress: velocity held each tick for `_lunge_left` seconds.
var _lunge_vel := Vector3.ZERO
var _lunge_left := 0.0
var _air_lunge := false
## The airborne foe an air-lunge homes on.
var _lunge_foe: Actor = null
## The recovery after the last strike, for the pose (view only).
var _recover_total := 0.0
## The windup's full length, the shown swing's lead into the strike and its
## follow-through time (view only, see `swing_arc`).
var _windup_total := 0.0
var _swing_lead := 0.0
var _swing_time := SWING_TIME
## The swing being shown is a back strike (the reverse stab).
var _back_shown := false
## The kind of the attack being shown ("light" or "heavy"), for its style.
var _shown_kind := "light"
var _hitstop_left := 0.0
## Seconds until the weapon ability can be used again.
var ability_left := 0.0
## Seconds left in a counter stance.
var _countering_left := 0.0
## The foe a shadow step is going behind.
var _step_foe: Actor = null


func build_visual() -> Node3D:
	var root := Node3D.new()
	root.add_child(Weapon.make_part(Vector3(0.05, 0.22, 0.05), Vector3(0, 0.0, 0), Color(0.15, 0.15, 0.15)))
	root.add_child(Weapon.make_part(Vector3(0.2, 0.04, 0.06), Vector3(0, 0.12, 0), Color(0.3, 0.3, 0.3)))
	root.add_child(Weapon.make_part(Vector3(0.06, 0.95, 0.015), Vector3(0, 0.62, 0), Color(0.45, 0.9, 1.0), true))
	root.rotation.x = REST_POSE
	return root


## True for an item held with both hands (its "two_handed" tag). The one
## flag gameplay and the view (`Look.is_two_handed`) both read.
static func is_two_handed_id(id: String) -> bool:
	return id != "" and ItemDB.has_tag(id, "two_handed")


func is_two_handed() -> bool:
	return is_two_handed_id(item_id)


func move_speed_mult() -> float:
	if move_mult > 0.0:
		return move_mult
	return two_hand_speed if is_two_handed() else one_hand_speed


## How long an unblocked heavy staggers: the item's own, or a two-hander's.
func heavy_stagger_now() -> float:
	return maxf(heavy_stagger, two_hand_stagger) if is_two_handed() else heavy_stagger


func armor_break_now() -> float:
	return maxf(armor_break, two_hand_armor_break) if is_two_handed() else armor_break


## True when a guard can stop rounds from the gun `id`: small arms only.
func stops_round(id: String) -> bool:
	for tag in undeflectable_tags:
		if id != "" and ItemDB.has_tag(id, tag):
			return false
	return true


## True while the guard is fresh enough that a hit of `kind` is parried (a
## blade) or deflected (a bullet) rather than only blocked.
func in_parry_window(kind: String) -> bool:
	if not _blocking or not _parry_ready:
		return false
	return _block_time <= (deflect_window if kind == "bullet" else parry_window)


## The side a swing toward `p_stance` starts from: a swing to the left is
## cocked on the right and sweeps across to the left, and back the other way.
static func swing_from(p_stance: int) -> int:
	return mirror(p_stance)


## A swing from the attacker's left arrives on the defender's right.
static func mirror(dir: int) -> int:
	if dir == Dir.LEFT:
		return Dir.RIGHT
	if dir == Dir.RIGHT:
		return Dir.LEFT
	return dir


func controls_hint() -> String:
	var pound := "   Q or the mouse's thumb button: %s" % ABILITY_NAMES[ability] if ABILITY_NAMES.has(ability) else ""
	return "Tap left mouse to swing, hold it for a heavy (a dive slam in the air)" + pound + "   Right mouse just before a hit parries, a little earlier blocks cheaply; held, the guard drains stamina"


func is_blocking() -> bool:
	return _blocking


func is_winding_up() -> bool:
	return _windup_left > 0.0


func tick(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	ability_left = maxf(0.0, ability_left - delta)
	_countering_left = maxf(0.0, _countering_left - delta)
	if _combo_timer > 0.0:
		_combo_timer -= delta
		if _combo_timer <= 0.0:
			combo_step = 0
	if actor.stagger_left > 0.0:
		# Being staggered cancels an attack in progress and drops the guard.
		_windup_left = 0.0
		_windup_kind = ""
		_blocking = false
		_lunge_left = 0.0
		_queued = false
		_countering_left = 0.0
		_step_foe = null
	elif _windup_left > 0.0:
		_windup_left -= delta
		if _windup_left <= 0.0:
			if _windup_kind == "kick":
				_kick_lands()
			elif _windup_kind == "pound":
				_pound_lands()
			elif _windup_kind == "step":
				_shadow_step_lands()
			elif _windup_kind == "hook":
				_hook_lands()
			elif _windup_kind == "vault":
				_vault_lands()
			elif _windup_kind == "trip":
				_trip_lands()
			else:
				_strike(_windup_damage, _windup_kind)
			_windup_kind = ""
	_carry_lunge(delta)
	_animate(delta)


func handle_input(cmd: ActorCommand, delta: float) -> void:
	# Sides are the blade's own (Caleb's call: melee is timing, not
	# matching a side): lights run through the combo's sides, and the guard
	# turns to meet whatever comes.
	if not is_busy():
		stance = next_stance() as Dir
	_sprinting = cmd.sprint
	_backing = cmd.move.y < -0.5
	if cmd.secondary and not _aim_was:
		_try_feint()
	_aim_was = cmd.secondary
	var wants_block := cmd.secondary and not _slamming and _windup_left <= 0.0 and actor.stamina > 0.0
	if wants_block and not _blocking:
		_block_time = 0.0
		_blade_check = 0.0
		_guard_paid = false
		guard_dir = _guard_toward() as Dir
		_parry_ready = _since_guard >= guard_rearm
	if _blocking and not wants_block:
		_since_guard = guard_rearm if _guard_paid else 0.0
	_blocking = wants_block
	if not _blocking:
		_since_guard += delta
	if _blocking:
		_charge = -1.0
		_queued = false
		_block_time += delta
		_drain_held_guard(delta)
		actor.pause_stamina_regen()
		return
	if is_busy():
		_charge = -1.0
		_queue_press(cmd, delta)
		return
	if cmd.kick_pressed:
		_charge = -1.0
		_queued = false
		kick()
		return
	if cmd.weapon_ability_pressed:
		_charge = -1.0
		_queued = false
		weapon_ability()
		return
	if cmd.tertiary_pressed:
		# A heavy asked for outright (bots, or a bound key).
		_charge = -1.0
		_queued = false
		_heavy_or_slam()
		return
	if _queued:
		# A press made while busy plays now: a tap that was let go is a light,
		# one still held carries on charging from where it got to.
		_queued = false
		if _queued_held < 0.0:
			_light_attack(0.0)
			return
		_charge = _queued_held
	elif cmd.primary_pressed:
		_charge = 0.0
	if _charge < 0.0:
		return
	if not cmd.primary:
		# Let go before the charge turned: a tap, so a light attack.
		var held := _charge
		_charge = -1.0
		_light_attack(held)
		return
	_charge += delta
	if _charge >= hold_time:
		_charge = -1.0
		_heavy_or_slam()


## A kick (`ActorCommand.kick_pressed`): on the ground only, with a windup
## a swing can beat.
func kick() -> void:
	if not actor.is_on_floor() or not actor.spend_stamina(kick_stamina):
		return
	_windup_kind = "kick"
	_windup_damage = kick_damage
	_windup_left = kick_windup
	_windup_total = kick_windup
	_shown_kind = "kick"
	_swing_lead = 0.0
	_cooldown = kick_windup + kick_recover
	_recover_total = 0.0
	swung.emit("kick_windup")


## True when the weapon has an ability and it is ready to use.
func ability_ready() -> bool:
	return ability != "" and ability_left <= 0.0


## The weapon's ability (`ability`): the ground pound, on the ground only.
func weapon_ability() -> void:
	if ability == "" or ability_left > 0.0 or not actor.is_on_floor():
		return
	var foe: Actor = null
	if ability == "shadow_step":
		var found := _lunge_target(ability_radius)
		if found.is_empty():
			return
		foe = found[0]
	elif not ABILITY_NAMES.has(ability):
		return
	if not actor.spend_stamina(ability_stamina):
		return
	ability_left = ability_cooldown
	combo_step = 0
	_cooldown = ability_windup + ability_recover
	match ability:
		"ground_pound":
			_begin_windup("pound", ability_damage, ability_windup)
			attack_dir = Dir.OVERHEAD
			swung.emit("pound_windup")
		"shadow_step":
			_step_foe = foe
			_begin_windup("step", 0.0, ability_windup)
			swung.emit("step_windup")
		"guard_hook", "vault", "trip":
			var kind: String = {"guard_hook": "hook", "vault": "vault", "trip": "trip"}[ability]
			_begin_windup(kind, ability_damage, ability_windup)
			if kind == "trip":
				attack_dir = swing_from(stance) as Dir
			swung.emit(kind + "_windup")
		"counter_stance":
			_countering_left = ability_windup
			_shown_kind = "counter"
			guard_dir = Dir.OVERHEAD
			_recover_total = 0.0
			swung.emit("counter")


## The foes in front within `ability_radius` and `ABILITY_ARC_DEG`, with
## where this machine sees them.
func _ability_reach() -> Array:
	var forward := actor.get_aim_dir()
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	var seen := Combat.positions_seen_by(actor)
	var out: Array = []
	for other in _other_actors():
		var at: Vector3 = seen.get(other, other.global_position)
		var to := at - actor.global_position
		if absf(to.y) > 1.2:
			continue
		to.y = 0.0
		if to.length() - HIT_ALLOWANCE > ability_radius:
			continue
		if to.length() > 0.6 and forward.angle_to(to.normalized()) > deg_to_rad(ABILITY_ARC_DEG) * 0.5:
			continue
		out.append([other, at, to])
	return out


## The axe's hook lands: through any guard, and a pull toward the axe.
func _hook_lands() -> void:
	swung.emit("hook")
	_swing_left = SWING_TIME
	_swing_time = SWING_TIME
	_recover_total = _cooldown
	Sfx.play("block", null if actor.is_player else actor.global_position, -4.0)
	for reached: Array in _ability_reach():
		var other: Actor = reached[0]
		var to: Vector3 = reached[2]
		var blade := other.get_active_weapon() as MeleeWeapon
		var guarding := blade != null and blade.is_blocking()
		_contact(other, reached[1])
		if not Combat.deal(other, DamageInfo.make(_windup_damage, actor, "hook", reached[1])) or other.is_dead:
			continue
		if guarding:
			blade.drop_aim()
			other.stagger(guard_break_stagger)
			other.notice.emit("Guard hooked open")
		var back := -to.normalized() if to.length() > 0.1 else Vector3.ZERO
		# A little lift, so the pull carries over the ground.
		other.add_impulse(back * ability_knock + Vector3.UP * 2.5)


## The spear's vault: up and ahead off the planted spear.
func _vault_lands() -> void:
	swung.emit("vault")
	_shown_kind = "vault"
	var forward := actor.get_aim_dir()
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	actor.velocity = forward * ability_knock + Vector3.UP * ability_lift
	if actor.is_inside_tree():
		Fx.puff(actor.get_parent(), actor.global_position + forward * 0.6, 0.7, Color(0.55, 0.5, 0.45, 0.6))
	Sfx.play("dash", null if actor.is_player else actor.global_position, -4.0)
	# Free in the air at once, for the heavy from the top.
	_cooldown = minf(_cooldown, ability_recover)


## The hook blade's trip: a low cut that takes the feet out.
func _trip_lands() -> void:
	swung.emit("trip")
	_swing_time = SWING_TIME
	_swing_left = _swing_time
	_recover_total = _cooldown
	Sfx.play("swing", null if actor.is_player else actor.global_position)
	for reached: Array in _ability_reach():
		var other: Actor = reached[0]
		_contact(other, reached[1])
		var info := DamageInfo.make(_windup_damage, actor, "melee", reached[1])
		info.direction = attack_dir
		info.armor_pierce = armor_pierce
		if not Combat.deal(other, info) or info.blocked or info.parried or other.is_dead:
			continue
		other.knock_down(ability_knockdown)


## True while a counter stance is held.
func is_countering() -> bool:
	return _countering_left > 0.0


## The guard is shown: held, or a counter stance. For poses.
func is_guard_shown() -> bool:
	return _blocking or _countering_left > 0.0


## The shadow step lands: through to just behind the foe, facing their back.
func _shadow_step_lands() -> void:
	var foe := _step_foe
	_step_foe = null
	_shown_kind = "step"
	if foe == null or not is_instance_valid(foe) or foe.is_dead:
		return
	var seen := Combat.positions_seen_by(actor)
	var at: Vector3 = seen.get(foe, foe.global_position)
	var facing := foe.get_aim_dir()
	facing.y = 0.0
	if facing.length() < 0.01:
		facing = (at - actor.global_position) * Vector3(1, 0, 1)
	facing = facing.normalized()
	var to := at - facing * STEP_BEHIND
	if actor.is_inside_tree():
		# Never through a wall: short of it, or the side the step came from.
		var chest := Vector3.UP * Actor.BODY_HEIGHT * 0.6
		var query := PhysicsRayQueryParameters3D.create(at + chest, to + chest, Actor.LAYER_WORLD)
		var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			var room := at.distance_to(hit.position) - 0.5
			if room < 0.8:
				return
			to = at - facing * room
	if actor.is_inside_tree():
		Fx.puff(actor.get_parent(), actor.global_position + Vector3.UP * 0.9, 0.8, Color(0.15, 0.15, 0.18, 0.6))
		Fx.puff(actor.get_parent(), to + Vector3.UP * 0.9, 0.6, Color(0.15, 0.15, 0.18, 0.5))
	actor.global_position = to
	actor.velocity = Vector3.ZERO
	# Turned to the foe's back: the view follows (`Actor.turn_request`).
	var look := at - to
	actor.turn_request = atan2(-look.x, -look.z)
	Sfx.play("dash", null if actor.is_player else actor.global_position, -6.0)
	swung.emit("step")
	# The blade is ready at once behind them.
	_cooldown = minf(_cooldown, ability_recover)


## True while the ground pound is winding up or being shown.
func is_pounding() -> bool:
	return _shown_kind == "pound" and (_windup_left > 0.0 or _cooldown > 0.0)


## The ground pound lands: a ring through everyone on the ground near.
func _pound_lands() -> void:
	swung.emit("pound")
	_swing_time = SWING_TIME * TWO_HAND_SWING
	_swing_left = _swing_time
	_back_shown = false
	_recover_total = _cooldown
	Sfx.play("slam", null if actor.is_player else actor.global_position)
	var forward := actor.get_aim_dir()
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	if actor.is_inside_tree():
		var ground := actor.global_position + Vector3.UP * 0.08
		Fx.ring(actor.get_parent(), ground, ability_radius, Color(1.0, 0.62, 0.3), 0.7, false)
		Fx.puff(actor.get_parent(), ground + forward * 1.4, 1.3, Color(0.55, 0.5, 0.45, 0.7))
	var seen := Combat.positions_seen_by(actor)
	for other in _other_actors():
		var at: Vector3 = seen.get(other, other.global_position)
		var to := at - actor.global_position
		if absf(to.y) > POUND_HEIGHT:
			continue
		to.y = 0.0
		var dist := to.length()
		if dist - HIT_ALLOWANCE > ability_radius:
			continue
		var info := DamageInfo.make(_windup_damage, actor, "melee", at)
		info.direction = Dir.OVERHEAD
		info.armor_pierce = armor_pierce
		if not Combat.deal(other, info) or info.blocked or info.parried or other.is_dead:
			continue
		other.knock_down(ability_knockdown)
		var away := to / dist if dist > 0.1 else forward
		var share := 1.0 - 0.5 * clampf(dist / maxf(ability_radius, 0.1), 0.0, 1.0)
		other.add_impulse(away * ability_knock * share + Vector3.UP * ability_lift * share)


## True while a kick is winding up or just landed.
func is_kicking() -> bool:
	return _shown_kind == "kick" and (_windup_left > 0.0 or _cooldown > 0.0)


## The kick lands: on a raised guard it breaks it open, and it only scuffs
## anyone else. It goes through any guard; a dodge slips it.
func _kick_lands() -> void:
	swung.emit("kick")
	Sfx.play("block", null if actor.is_player else actor.global_position, -6.0)
	var forward := actor.get_aim_dir()
	forward.y = 0.0
	forward = forward.normalized()
	var seen := Combat.positions_seen_by(actor)
	for other in _other_actors():
		var at: Vector3 = seen.get(other, other.global_position)
		var to := at - actor.global_position
		if absf(to.y) > 1.2:
			continue
		to.y = 0.0
		if to.length() - HIT_ALLOWANCE > kick_reach:
			continue
		if to.length() > 0.6 and forward.angle_to(to.normalized()) > deg_to_rad(kick_arc_deg) * 0.5:
			continue
		var blade := other.get_active_weapon() as MeleeWeapon
		var guarding := blade != null and blade.is_blocking()
		var info := DamageInfo.make(kick_damage, actor, "kick", at)
		if not Combat.deal(other, info) or info.amount <= 0.0 or other.is_dead:
			continue
		if guarding:
			other.stagger(kick_guard_stagger)
			other.notice.emit("Guard kicked open")


## Aim pressed early in a heavy's windup feints it: the heavy is let go
## (it never lands) and the guard comes up from the same press.
func _try_feint() -> void:
	if _windup_kind != "heavy" or _windup_left <= _swing_lead or _windup_left <= 0.0:
		return
	if not actor.spend_stamina(feint_stamina):
		return
	_windup_left = 0.0
	_windup_kind = ""
	_lunge_left = 0.0
	_dashing = false
	_cooldown = 0.0
	_shown_kind = "light"
	actor.notice.emit("Feint")
	swung.emit("feint")


## True when the nearest foe in reach has a blade drawn: a duel of blades,
## where cuts are measured (`light_tell`).
func facing_blade() -> bool:
	var nearest := INF
	var blade := false
	var seen := Combat.positions_seen_by(actor)
	for other in _other_actors():
		var at: Vector3 = seen.get(other, other.global_position)
		var dist := at.distance_to(actor.global_position)
		if dist < nearest and dist <= reach * 2.0:
			nearest = dist
			blade = other.get_active_weapon() is MeleeWeapon
	return blade


## The side the next swing goes toward: a combo runs left, right, then
## overhead (each swing starting on the other side, `swing_from`).
func next_stance() -> int:
	return [Dir.LEFT, Dir.RIGHT, Dir.OVERHEAD][combo_step % 3]


## The side a guard raised now turns to: to meet the nearest foe's swing
## that is coming, else across the middle.
func _guard_toward() -> int:
	var best := -1
	var nearest := INF
	for other in _other_actors():
		var blade := other.get_active_weapon() as MeleeWeapon
		if blade == null or blade.threat_dir() < 0:
			continue
		var dist := other.global_position.distance_to(actor.global_position)
		if dist < nearest and dist <= blade.reach * 1.5:
			nearest = dist
			best = mirror(blade.threat_dir())
	return best if best >= 0 else Dir.OVERHEAD


## A guard held past `timed_window` costs stamina for every moment it stays
## up, more the longer it is held; once the stamina is gone the guard drops.
func _drain_held_guard(delta: float) -> void:
	if _block_time <= timed_window or hold_drain <= 0.0:
		return
	# Only blade against blade: a guard held up against gunfire is still the
	# shield it was (each round it turns aside costs on its own).
	_blade_check -= delta
	if _blade_check <= 0.0:
		_blade_check = 0.25
		_blade_near = facing_blade()
	if not _blade_near:
		return
	var held := _block_time - timed_window
	actor.stamina = maxf(0.0, actor.stamina - hold_drain * (1.0 + hold_drain_ramp * held) * delta)


## True while the guard up now still counts as timed: raised just now, and
## not mashed.
func in_timed_window() -> bool:
	return _blocking and _parry_ready and _block_time <= timed_window


## True while a swing, its recovery or a slam keeps the blade from attacking.
func is_busy() -> bool:
	return _cooldown > 0.0 or _slamming or _windup_left > 0.0 or _countering_left > 0.0


## Remembers a press made while busy, and how long it is held.
func _queue_press(cmd: ActorCommand, delta: float) -> void:
	if cmd.primary_pressed:
		_queued = true
		_queued_age = 0.0
		_queued_held = 0.0 if cmd.primary else -1.0
		return
	if not _queued:
		return
	# A press made during a windup is kept until its strike: only the
	# recovery after it counts toward forgetting a tap.
	if _windup_left <= 0.0:
		_queued_age += delta
	if _queued_held >= 0.0:
		_queued_held = _queued_held + delta if cmd.primary else -1.0
	# A tap is forgotten once it is old; a press still held is a charge.
	if _queued_held < 0.0 and _queued_age > press_buffer:
		_queued = false


## True while the attack button is held but has not yet become a heavy.
func is_charging() -> bool:
	return _charge >= 0.0


func _heavy_or_slam() -> void:
	if actor.is_on_floor():
		_heavy_attack()
		return
	var foe := _air_lunge_target()
	if foe:
		_air_lunge_at(foe)
	else:
		_start_slam()


## The hand is taken from the weapon this tick (a dodge, a stagger): the
## guard drops and a charge is let go without a swing.
func drop_aim() -> void:
	if _blocking:
		_since_guard = guard_rearm if _guard_paid else 0.0
	_blocking = false
	_charge = -1.0


func on_holster() -> void:
	_charge = -1.0
	_queued = false
	_blocking = false
	_windup_left = 0.0
	_windup_kind = ""
	_lunge_left = 0.0
	_air_lunge = false
	_dashing = false
	_back_strike = false
	_lunge_foe = null
	combo_step = 0
	# A slam put away mid-fall does not land.
	if _slamming:
		_slamming = false
		if actor.landed.is_connected(_on_slam_landed):
			actor.landed.disconnect(_on_slam_landed)


## The side an attack is coming from right now, as the attacker sees it: the
## windup's side, or the stance while the button is held for a heavy. -1 when
## nothing is coming. What a defender (or the HUD) can read off the blade.
func threat_dir() -> int:
	if _windup_left > 0.0:
		return attack_dir
	if _charge >= 0.0:
		return swing_from(stance)
	return -1


## 0 at the start of the recovery after a strike, 1 once ready again, or -1
## when not recovering. For poses.
func recover_progress() -> float:
	if _recover_total <= 0.0 or _cooldown <= 0.0 or _windup_left > 0.0:
		return -1.0
	return clampf(1.0 - _cooldown / _recover_total, 0.0, 1.0)


func is_lunging() -> bool:
	return _lunge_left > 0.0


## A dash-strike (or a charge) is carrying the actor.
func is_dashing() -> bool:
	return _dashing and _lunge_left > 0.0


func status_text() -> String:
	if _blocking:
		return "%s  guarding %s" % [display_name, DIR_NAMES[guard_dir]]
	if _dashing and _lunge_left > 0.0:
		return "%s  dash strike" % display_name
	if _slamming:
		return "%s  dive slam" % display_name
	if is_pounding():
		return "%s  ground pound" % display_name
	if _countering_left > 0.0:
		return "%s  counter stance" % display_name
	if _air_lunge and _windup_left > 0.0:
		return "%s  air lunge" % display_name
	if actor.riposte_left > 0.0:
		return "%s  riposte ready" % display_name
	if combo_step > 0:
		return "%s  %s  combo %d" % [display_name, DIR_NAMES[stance], combo_step]
	if ability != "" and ability_left > 0.0:
		return "%s  %s  %s in %ds" % [display_name, DIR_NAMES[stance], ABILITY_NAMES.get(ability, "ability"), ceili(ability_left)]
	return "%s  %s" % [display_name, DIR_NAMES[stance]]


func modify_incoming(info: DamageInfo) -> void:
	if _countering_left > 0.0 and info.kind == "melee" and _counter(info):
		return
	if not _blocking or info.kind not in ["bullet", "melee"]:
		return
	if info.kind == "bullet" and not stops_round(info.weapon_id):
		return
	var source := info.source as Node3D
	if source == null:
		return
	var forward := actor.get_aim_dir()
	forward.y = 0.0
	var to := source.global_position - actor.global_position
	to.y = 0.0
	if to.length() > 0.01 and forward.normalized().angle_to(to.normalized()) > deg_to_rad(block_arc_deg) * 0.5:
		return
	if info.kind == "melee" and info.direction >= 0:
		# The guard turns to meet the swing, whichever side it comes from.
		guard_dir = mirror(info.direction) as Dir

	if info.kind == "bullet" and in_parry_window("bullet") and actor.spend_stamina(deflect_stamina):
		# A fresh guard turns every round from the front aside.
		info.amount = 0.0
		info.parried = true
		actor.notice.emit("Deflected")
		if actor.is_inside_tree():
			Fx.burst(actor.get_parent(), actor.get_eye_position() + actor.get_aim_dir() * 0.6, 0.25, Color(1.0, 0.85, 0.4))
		parried_hit.emit(info)
		Sfx.play("parry", null if actor.is_player else actor.global_position)
		return

	if info.kind == "melee" and in_parry_window("melee"):
		info.amount = 0.0
		info.parried = true
		_guard_paid = true
		actor.riposte_left = riposte_window
		actor.notice.emit("Parry!")
		var attacker := source as Actor
		if info.kind == "melee" and attacker:
			attacker.stagger(parry_stagger)
		parried_hit.emit(info)
		Sfx.play("parry", null if actor.is_player else actor.global_position)
		return

	var stopped := info.amount if info.kind == "melee" else info.amount * bullet_block_fraction
	var cost := stopped * block_stamina_per_damage * info.guard_mult
	var timed := in_timed_window()
	if timed:
		cost *= timed_block_cost
	if actor.spend_stamina(cost):
		info.amount -= stopped
		info.blocked = true
		info.timed = timed
		if timed:
			_guard_paid = true
		blocked_hit.emit(info)
		Sfx.play("block", null if actor.is_player else actor.global_position)
	else:
		actor.stamina = 0.0
		_blocking = false
		actor.stagger(guard_break_stagger)
		actor.notice.emit("Guard broken")


## A counter stance meets `info`: from the front it is turned aside, the
## attacker staggered, and a quick riposte answers. True when it did.
func _counter(info: DamageInfo) -> bool:
	var attacker := info.source as Actor
	if attacker == null:
		return false
	var forward := actor.get_aim_dir()
	forward.y = 0.0
	var to := attacker.global_position - actor.global_position
	to.y = 0.0
	if to.length() > 0.01 and forward.normalized().angle_to(to.normalized()) > deg_to_rad(block_arc_deg) * 0.5:
		return false
	info.amount = 0.0
	info.parried = true
	_countering_left = 0.0
	attacker.stagger(parry_stagger)
	actor.notice.emit("Countered!")
	parried_hit.emit(info)
	Sfx.play("parry", null if actor.is_player else actor.global_position)
	# The answer: a riposte cut straight away, at the riposte's strength.
	actor.riposte_left = riposte_window
	_cooldown = COUNTER_ANSWER + light_recover
	_begin_windup("light", light_damage, COUNTER_ANSWER)
	return true


func _light_attack(held: float) -> void:
	if not actor.spend_stamina(light_stamina):
		return
	combo_step = combo_step % 3 + 1
	var finisher := combo_step == 3
	# The hold before the release was already part of the windup.
	var tell := light_tell if facing_blade() else 0.0
	var windup := maxf(light_windup + tell - held, light_windup * light_windup_floor)
	_combo_timer = combo_window + windup
	_cooldown = windup + light_recover * (1.6 if finisher else 1.0)
	_begin_windup("light", light_damage * (combo_finisher_mult if finisher else 1.0), windup)
	_back_strike = _backing and back_strike_mult > 0.0 and _foe_behind()
	if _back_strike:
		return
	# Just out of reach: step in so the cut lands.
	var foe := _lunge_target(reach + light_step)
	if foe.size() > 0:
		var gap: float = foe[1] - reach * 0.85
		if gap > 0.0:
			_start_lunge(foe[2] * (gap / maxf(windup, 0.12)), maxf(windup, 0.12))


func _heavy_attack() -> void:
	if not actor.spend_stamina(heavy_stamina):
		return
	# Straight off a light, the heavy carries the string on: quicker, from
	# the side the next cut would come.
	var chained := combo_step > 0 and _combo_timer > 0.0
	var windup := heavy_windup * (combo_heavy_speed if chained else 1.0)
	combo_step = 0
	_cooldown = windup + heavy_recover
	_begin_windup("heavy", heavy_damage, windup)
	if chained:
		attack_dir = swing_from(stance) as Dir
	var time := maxf(windup, 0.05)
	var most := heavy_lunge * time
	var dash := dash_range if _sprinting and dash_range > most else most
	var foe := _lunge_target(reach + dash)
	if foe.size() > 0:
		# Close to striking distance, never past the foe, unless it charges.
		var travel := clampf(foe[1] - reach * lunge_stop, 0.0, dash)
		if dash_through and _sprinting and foe[1] > reach * 1.4:
			travel = dash
		# Further than a plain lunge reaches is a dash-strike, and costs more.
		if travel > most and not actor.spend_stamina(dash_stamina):
			travel = most
		_dashing = travel > most
		_start_lunge(foe[2] * (travel / time), time)
	else:
		var forward := actor.get_aim_dir()
		forward.y = 0.0
		_start_lunge(forward.normalized() * (minf(heavy_step, most) / time), time)


## True when a foe stands behind within striking reach, for a back strike.
func _foe_behind() -> bool:
	var back := -actor.get_aim_dir()
	back.y = 0.0
	if back.length() < 0.01:
		return false
	back = back.normalized()
	var seen := Combat.positions_seen_by(actor)
	for other in _other_actors():
		var to: Vector3 = seen.get(other, other.global_position) - actor.global_position
		if absf(to.y) > vertical_reach:
			continue
		to.y = 0.0
		if to.length() > 0.01 and to.length() - HIT_ALLOWANCE <= reach \
				and back.angle_to(to.normalized()) <= deg_to_rad(arc_deg) * 0.5:
			return true
	return false


## The nearest foe on the ground within `range_m` and the lunge cone, as
## [actor, flat distance, flat direction], or [] for none. Foes are where this
## attacker sees them, so a lunge online goes where it looked like it would.
func _lunge_target(range_m: float) -> Array:
	var forward := actor.get_aim_dir()
	forward.y = 0.0
	if forward.length() < 0.01:
		return []
	forward = forward.normalized()
	var half := deg_to_rad(lunge_cone_deg) * 0.5
	var seen := Combat.positions_seen_by(actor)
	var best: Array = []
	for other in _other_actors():
		var at: Vector3 = seen.get(other, other.global_position)
		var to := at - actor.global_position
		if absf(to.y) > vertical_reach:
			continue
		to.y = 0.0
		var dist := to.length()
		if dist < 0.01 or dist > range_m or forward.angle_to(to / dist) > half:
			continue
		if best.is_empty() or dist < best[1]:
			best = [other, dist, to / dist]
	return best


## An airborne foe the magnetic air-lunge can reach, or null.
func _air_lunge_target() -> Actor:
	if air_lunge_range <= 0.0:
		return null
	var aim := actor.get_aim_dir().normalized()
	var half := deg_to_rad(air_lunge_cone_deg) * 0.5
	var seen := Combat.positions_seen_by(actor)
	var best: Actor = null
	var best_dist := INF
	for other in _other_actors():
		if other.is_on_floor():
			continue
		var at: Vector3 = seen.get(other, other.global_position)
		var to := at - actor.global_position
		var dist := to.length()
		if dist < 0.01 or dist > air_lunge_range or dist >= best_dist or aim.angle_to(to / dist) > half:
			continue
		best = other
		best_dist = dist
	return best


## A heavy in the air at an airborne foe: the full heavy windup, spent flying
## to them, and the strike lands as you arrive. A whiff leaves you drifting.
func _air_lunge_at(foe: Actor) -> void:
	if not actor.spend_stamina(heavy_stamina):
		return
	combo_step = 0
	_cooldown = heavy_windup + heavy_recover
	_begin_windup("heavy", heavy_damage, heavy_windup)
	_air_lunge = true
	_lunge_foe = foe
	_lunge_left = maxf(heavy_windup, 0.05)
	_lunge_vel = _air_lunge_velocity(_lunge_left)


## Toward the air-lunge's foe, fast enough to arrive at striking distance as
## `time_left` runs out. It follows them as they fly: that is the magnet.
func _air_lunge_velocity(time_left: float) -> Vector3:
	if _lunge_foe == null or not is_instance_valid(_lunge_foe) or _lunge_foe.is_dead:
		return _lunge_vel
	var seen := Combat.positions_seen_by(actor)
	var to: Vector3 = seen.get(_lunge_foe, _lunge_foe.global_position) - actor.global_position
	var travel := maxf(to.length() - reach * lunge_stop, 0.0)
	if to.length() < 0.01:
		return Vector3.ZERO
	return to.normalized() * (travel / maxf(time_left, 1.0 / 60.0))


func _start_lunge(vel: Vector3, time: float) -> void:
	_lunge_vel = vel
	_lunge_left = time if vel.length() > 0.01 else 0.0


## Holds the lunge's velocity. Runs after the actor has moved this tick, so
## the next move carries it; movement only eases it a little in between.
func _carry_lunge(delta: float) -> void:
	if _lunge_left <= 0.0:
		return
	if actor.get_active_weapon() != self:
		_lunge_left = 0.0
		return
	_lunge_left -= delta
	if _air_lunge:
		if _lunge_left > 0.0:
			_lunge_vel = _air_lunge_velocity(_lunge_left)
		actor.velocity = _lunge_vel if _lunge_left > 0.0 else _lunge_vel * air_lunge_keep
	elif _lunge_left > 0.0:
		actor.velocity.x = _lunge_vel.x
		actor.velocity.z = _lunge_vel.z
	if _lunge_left <= 0.0:
		_air_lunge = false
		_dashing = false
		_lunge_foe = null


func _begin_windup(kind: String, amount: float, time: float) -> void:
	if actor.riposte_left > 0.0:
		amount *= riposte_mult
		actor.riposte_left = 0.0
	_windup_kind = kind
	_windup_damage = amount
	_windup_left = maxf(time, 0.001)
	_windup_total = _windup_left
	_shown_kind = kind
	var weight := TWO_HAND_SWING if is_two_handed() else 1.0
	_swing_lead = minf(SWING_LEAD * weight, _windup_left * SWING_LEAD_SHARE)
	_back_shown = false
	# A heavy comes from the middle, over the top; a light from its side.
	attack_dir = Dir.OVERHEAD if kind == "heavy" else swing_from(stance) as Dir


func _start_slam() -> void:
	if not actor.spend_stamina(slam_stamina):
		return
	_slamming = true
	_cooldown = 1.0
	actor.velocity.y = -slam_fall_speed
	if not actor.landed.is_connected(_on_slam_landed):
		actor.landed.connect(_on_slam_landed, CONNECT_ONE_SHOT)


func _on_slam_landed(_impact_speed: float) -> void:
	_slamming = false
	swung.emit("slam")
	Sfx.play("slam", null if actor.is_player else actor.global_position)
	var seen := Combat.positions_seen_by(actor)
	for other in _other_actors():
		var at: Vector3 = seen.get(other, other.global_position)
		if at.distance_to(actor.global_position) <= slam_radius:
			Combat.deal(other, DamageInfo.make(slam_damage, actor, "slam", at))


func _strike(amount: float, kind: String) -> void:
	swung.emit(kind)
	_swing_time = SWING_TIME * (TWO_HAND_SWING if is_two_handed() else 1.0)
	_swing_left = _swing_time
	_back_shown = _back_strike
	_recover_total = _cooldown
	Sfx.play("swing", null if actor.is_player else actor.global_position)
	var forward := actor.get_aim_dir()
	forward.y = 0.0
	forward = forward.normalized()
	if _back_strike:
		# The reverse stab reaches behind.
		forward = -forward
		amount *= back_strike_mult
		_back_strike = false
	var half_arc := deg_to_rad(arc_deg) * 0.5
	var seen := Combat.positions_seen_by(actor)
	for other in _other_actors():
		var at: Vector3 = seen.get(other, other.global_position)
		var to := at - actor.global_position
		var vertical := absf(to.y)
		to.y = 0.0
		var dist := to.length()
		# A blade reaches a body, not the middle of it: count its width.
		if dist - HIT_ALLOWANCE > reach or vertical > vertical_reach:
			continue
		if dist > 0.8 and forward.angle_to(to.normalized()) > half_arc + atan(HIT_ALLOWANCE / dist):
			continue
		var hit := amount
		if dist < close_range:
			hit *= close_mult
		if backstab_mult != 1.0 and is_behind(other, actor.global_position, backstab_arc_deg):
			hit *= backstab_mult
		_contact(other, at)
		var info := DamageInfo.make(hit, actor, "melee", at)
		info.direction = attack_dir
		info.guard_mult = guard_crush
		info.armor_pierce = armor_pierce
		if kind == "heavy":
			info.armor_break = armor_break_now()
		var stagger := heavy_stagger_now()
		var foe_blade := other.get_active_weapon() as MeleeWeapon
		var swinging := foe_blade != null and (foe_blade.is_winding_up() or foe_blade.is_charging())
		if clashes_with(foe_blade):
			# Two strikes meet: neither cuts, both are knocked back.
			if Combat.authoritative:
				actor.stagger(clash_stagger)
				other.stagger(clash_stagger)
				actor.notice.emit("Clash")
				other.notice.emit("Clash")
			continue
		if not Combat.deal(other, info) or info.blocked or info.parried or other.is_dead:
			continue
		if kind == "heavy" and stagger > 0.0:
			other.stagger(stagger)
		if swinging:
			other.stagger(interrupt_stagger)
			other.notice.emit("Interrupted")


## The strike reached `other`: guess what their guard does with it, and let
## the views answer now rather than after the server's word.
func _contact(other: Actor, at: Vector3) -> void:
	var outcome := guess_outcome(other)
	_hitstop_left = HITSTOP * (TWO_HAND_HITSTOP if is_two_handed() else 1.0) if outcome == "hit" else BIND_HOLD
	if _air_lunge and _lunge_left > 0.0:
		# Arrived: the lunge has done its job.
		_lunge_left = minf(_lunge_left, 0.0001)
	var chest := at + Vector3(0.0, Actor.BODY_HEIGHT * 0.6, 0.0)
	contact.emit(other, outcome, chest)
	if actor.is_inside_tree() and outcome == "hit":
		# A guard's spark is struck where the blades meet (`ActorSkin`).
		Fx.burst(actor.get_parent(), chest, 0.35, Color(1.0, 0.45, 0.35))


## True when `foe_blade`'s own strike is about to land as this one does, so
## the two meet in a clash.
func clashes_with(foe_blade: MeleeWeapon) -> bool:
	return foe_blade != null and foe_blade._windup_kind in ["light", "heavy"] \
			and foe_blade._windup_left > 0.0 and foe_blade._windup_left <= clash_window


## What `other`'s guard would do with a strike from this blade right now:
## "parry", "block" or "hit". The server's `modify_incoming` decides for real;
## this only lets the attacker's view answer straight away.
func guess_outcome(other: Actor) -> String:
	var blade := other.get_active_weapon() as MeleeWeapon
	if clashes_with(blade):
		return "clash"
	if blade == null or not blade.is_guard_shown() or other.stagger_left > 0.0:
		return "hit"
	var facing := other.get_aim_dir()
	facing.y = 0.0
	var to := actor.global_position - other.global_position
	to.y = 0.0
	if facing.length() > 0.01 and to.length() > 0.01 \
			and facing.normalized().angle_to(to.normalized()) > deg_to_rad(blade.block_arc_deg) * 0.5:
		return "hit"
	return "parry" if blade.is_countering() or blade.in_parry_window("melee") else "block"


## How far through the shown swing the blade is, 0 to 1 along its arc, or -1
## when no swing is showing. It starts `_swing_lead` before the strike and
## speeds up into it (half the arc at the moment of the hit), then slows
## through the follow-through. View only; both views read it.
func swing_arc() -> float:
	if _slamming:
		return -1.0
	if _windup_left > 0.0:
		if _windup_left > _swing_lead or _swing_lead <= 0.0:
			return -1.0
		var into := 1.0 - _windup_left / _swing_lead
		# The pound is driven all the way down by the time it lands.
		return into * into if _shown_kind == "pound" else 0.5 * into * into
	if _swing_left > 0.0:
		if _shown_kind == "pound":
			return 1.0
		var after := 1.0 - _swing_left / maxf(_swing_time, 0.001)
		return 0.5 + 0.5 * (1.0 - (1.0 - after) * (1.0 - after))
	return -1.0


## The style of the attack being shown or about to be: the heavy's own when
## it has one, else `swing_style`.
func style_now() -> String:
	var heavy := _shown_kind == "heavy" or (_charge >= 0.0 and _charge >= hold_time * 0.5)
	return heavy_style if heavy and heavy_style != "" else swing_style


## How far into its windup the blade is drawn back (0 to 1, before the
## swing's lead), for a windup that keeps coiling instead of holding still.
func windup_coil() -> float:
	var span := _windup_total - _swing_lead
	if _windup_left <= 0.0 or span <= 0.0:
		return 0.0
	return clampf(1.0 - (_windup_left - _swing_lead) / span, 0.0, 1.0)


## True while a back strike is winding up or being shown.
func showing_back_strike() -> bool:
	return (_back_strike and _windup_left > 0.0) or (_back_shown and _swing_left > 0.0)


## True when `from` is outside the front `front_arc_deg` of `target`, the way
## it faces.
static func is_behind(target: Actor, from: Vector3, front_arc_deg: float) -> bool:
	var facing := target.get_aim_dir()
	facing.y = 0.0
	var to := from - target.global_position
	to.y = 0.0
	if facing.length() < 0.01 or to.length() < 0.01:
		return false
	return facing.normalized().angle_to(to.normalized()) > deg_to_rad(front_arc_deg) * 0.5


## Greybox poses. The blade is cocked to the attack's side for a windup, swept
## through on a strike, and held on the guarded side while blocking, so both
## fighters can read the direction.
func _animate(delta: float) -> void:
	if visual == null:
		return
	var pose := REST_POSE
	var roll := 0.0
	var offset := Vector3.ZERO
	var follow := 24.0
	if _hitstop_left > 0.0:
		# A landed strike holds the swing still for a moment.
		_hitstop_left -= delta
		return
	var arc := swing_arc()
	if _swing_left > 0.0 and _windup_left <= 0.0:
		_swing_left -= delta
	if is_kicking():
		# A kick is the leg's: the weapon stays held as it rests (cocking
		# it like a swing's windup flung a carried hammer out behind).
		pass
	elif _slamming:
		pose = 1.3
	elif showing_back_strike():
		# A reverse grip, the point turned back past the hip, thrust back.
		pose = -2.6
		offset.z = 0.12 * maxf(arc, 0.0)
		follow = 40.0
	elif arc >= 0.0:
		# Swept across to the other side (a side swing), or chopped down:
		# faster into the hit, slower through the follow-through.
		var u := arc
		follow = 60.0
		var style := style_now()
		if style == "thrust":
			# Point first, straight out.
			pose = lerpf(THRUST_COCKED, THRUST_OUT, u)
			offset.z = lerpf(0.08, -0.05, u)
		elif style == "chop":
			# Down from over the shoulder, a side chop on a diagonal.
			var side := _side(attack_dir)
			pose = lerpf(CHOP_RAISED - 0.3, FOLLOW_THROUGH, u)
			roll = lerpf(side * 0.5, -side * 0.3, u) * WINDUP_ROLL
			offset.x = lerpf(-side, side, u) * SIDE_REACH * 0.5
		elif attack_dir == Dir.OVERHEAD:
			pose = lerpf(0.6, FOLLOW_THROUGH, u)
		else:
			var side := _side(attack_dir)
			pose = lerpf(SIDE_SWING_FROM, SIDE_SWING_TO, u)
			roll = lerpf(side, -side, u) * WINDUP_ROLL
			offset.x = lerpf(-side, side, u) * SIDE_REACH
	elif _windup_left > 0.0:
		# Cocked on the side the swing comes from, drawing further back as
		# the windup goes on.
		var coil := windup_coil()
		var style := style_now()
		if style == "thrust":
			# Drawn back, point toward the foe.
			pose = THRUST_COCKED
			offset.z = 0.08 + 0.04 * coil
		elif style == "chop":
			# Raised high behind the shoulder.
			pose = CHOP_RAISED + 0.15 * coil
			roll = _side(attack_dir) * WINDUP_ROLL * 0.5
			offset.x = -_side(attack_dir) * SIDE_REACH * 0.5
			offset.y = 0.1
		else:
			pose = (1.0 if _windup_kind == "heavy" else 0.7) + 0.15 * coil
			roll = _side(attack_dir) * WINDUP_ROLL * (1.0 + 0.1 * coil)
			offset.x = -_side(attack_dir) * SIDE_REACH
			if attack_dir == Dir.OVERHEAD:
				pose += 0.35
				offset.y = 0.12
	elif is_guard_shown():
		pose = GUARD_POSE
		if guard_dir == Dir.OVERHEAD:
			roll = 1.4
			offset = GUARD_OFFSET_OVERHEAD
		else:
			roll = _side(guard_dir) * 0.2
			offset = GUARD_OFFSET_LEFT if guard_dir == Dir.LEFT else GUARD_OFFSET_RIGHT
	elif _charge >= 0.0 or (_queued and _queued_held >= 0.0):
		# Drawing back while the button is held, toward the heavy's windup.
		var held := _charge if _charge >= 0.0 else _queued_held
		var t := clampf(held / maxf(hold_time, 0.01), 0.0, 1.0)
		pose = lerpf(REST_POSE, 0.6, t)
		roll = _side(swing_from(stance)) * WINDUP_ROLL * t
	elif recover_progress() >= 0.0:
		# Recovering: ease back from where the swing ended, so the wait
		# before the next attack can be seen.
		var t := smoothstep(0.0, 1.0, recover_progress())
		var style := style_now()
		if style == "thrust":
			pose = lerpf(THRUST_OUT, REST_POSE, t)
		elif style == "chop" or attack_dir == Dir.OVERHEAD:
			pose = lerpf(FOLLOW_THROUGH * 0.75, REST_POSE, t)
		else:
			var side := _side(attack_dir)
			pose = lerpf(SIDE_SWING_TO, REST_POSE, t)
			roll = -side * WINDUP_ROLL * (1.0 - t)
			offset.x = side * SIDE_REACH * (1.0 - t)
	visual.rotation.z = lerp_angle(visual.rotation.z, roll, 1.0 - exp(-follow * delta))
	visual.rotation.x = lerp_angle(visual.rotation.x, pose, 1.0 - exp(-maxf(follow, 40.0) * delta))
	visual.position = visual.position.lerp(offset, 1.0 - exp(-follow * delta))


## +1 for the actor's left, -1 for the right, 0 for overhead.
static func _side(dir: int) -> float:
	if dir == Dir.LEFT:
		return 1.0
	if dir == Dir.RIGHT:
		return -1.0
	return 0.0


func _other_actors() -> Array[Actor]:
	var out: Array[Actor] = []
	if not actor.is_inside_tree():
		return out
	for node in actor.get_tree().get_nodes_in_group("actors"):
		var other := node as Actor
		if other and other != actor and not other.is_dead and Raid.together(actor, other):
			out.append(other)
	return out
