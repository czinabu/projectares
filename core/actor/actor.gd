class_name Actor
extends CharacterBody3D
## A character in a raid: the player, a bot, or (later) a remote player.
##
## An Actor owns movement, health, inventory, weapons and the flight rig, and is
## driven only by its `cmd` (see ActorCommand). Controllers and AI live outside.

signal died(actor: Actor, info: DamageInfo)
signal landed(impact_speed: float)
## Short messages for whoever is watching this actor (the HUD for the player).
signal notice(text: String)
## This actor's attack landed on `target`. Drives hit markers and sounds.
signal hit_confirmed(target: Actor, info: DamageInfo, lethal: bool)
## A person's gunfire within earshot (`Combat.noise`): bots on patrol go to
## look. Blades make none, so a melee kill alerts nobody.
signal heard(at: Vector3, source: Actor)
## The power weapon slot changed mid-raid (`Loadout.set_power`); "" is empty.
signal power_changed(item_id: String, mag: int, reserve: int)
## The helmet on the head changed (`Loadout.wear_helmet`); "" is bare-headed.
signal helmet_changed(item_id: String)
## The armor frame worn changed (`Loadout.wear_frame`); "" is none.
signal frame_changed(item_id: String)
## The flight rig worn changed (`Loadout.wear_rig`); "" is none.
signal rig_changed(item_id: String)
## The ability chip in changed (`Loadout.wear_ability`); "" is none.
signal ability_changed(item_id: String)
## A weapon was materialized out of the pack in place of the one worn in its
## slot (`Loadout.swap_weapon`, the watch's summon).
signal weapon_swapped(item_id: String, mag: int, reserve: int)
## The weapon in hand started dematerializing back into the pack
## (`Loadout.store_weapon`, the watch's store), with the rounds it had.
signal weapon_stored(item_id: String, mag: int, reserve: int)
## Items this actor just took out of a container (`LootContainer.interact`),
## or a heavy weapon scanned off a rack, on the machine that decided it.
## Online `NetSession._looted` repeats it to the owner. Drives the visor's
## pickup feed; nothing in the simulation reads it.
signal looted(ids: Array[String])
## What this body carries weighs a new amount (`carry_kg`, `CarryLoad`).
signal carry_changed(kg: float)

const LAYER_WORLD := 1
const LAYER_ACTORS := 2
const LAYER_INTERACT := 4
## Vehicles (`vehicle.gd`): a person walks into a parked bike rather than
## through it, and its rider is let through by a collision exception.
const LAYER_VEHICLES := 8
## The body's capsule. `Combat.trace` tests rewound bodies against the same shape.
const BODY_RADIUS := 0.4
const BODY_HEIGHT := 1.8
## How far down from the top of the body a hit counts as a headshot.
const HEAD_SIZE := 0.3
## How tall the body is crouched (`crouched`) or down in a slide: low cover
## of about this height hides it, collision, hitbox and all.
const CROUCH_HEIGHT := 1.3
## Where the hand sits on the body when a controller is not posing it.
const HAND_REST := Vector3(0.38, 1.25, -0.35)

var faction := "raider"
var display_name := "Raider"
## The clan this actor fights for (its id), or "". Clanmates cannot hurt each
## other (`Combat.deal`). Set by the authority; never trusted from a client.
var clan := ""
## The clan's short tag, for views to show beside the name.
var clan_tag := ""
var is_player := false
var body_color := Color(0.25, 0.6, 1.0)

# Movement tuning.
var walk_speed := 6.0
var sprint_speed := 9.5
## A gun comes up from a sprint's port carry this long after the sprint ends
## before it can fire (`sprint_recover`), so sprinting costs a beat in a
## fight. Pulling the trigger ends a sprint.
var sprint_out_time := 0.2
## Seconds left before a gun can fire after a sprint.
var sprint_recover := 0.0
## How long a reload press is kept when the gun in hand cannot take it yet
## (drawing, healing, staggered), so the key never goes unanswered.
var reload_buffer := 0.4
var _reload_ask := 0.0
var jump_velocity := 7.0
var gravity := 20.0
var ground_accel := 60.0
var air_accel := 14.0
var max_fall_speed := 50.0
var dash_speed := 18.0
## Shooting from the air: guns spread this many degrees wider and bloom by
## this much more per shot, except in a rig's steady state (see `air_aim`).
var air_spread_deg := 1.5
var air_bloom_mult := 1.5
var dash_time := 0.18
var dash_cooldown := 0.8
## The dash is the evade (Caleb's call, DESIGN.md "Melee"): each rig dodges
## its own way (`dodge_style`): with no rig a roll or dive along the ground
## (`roll_speed` for `roll_time`), boots a jet sidestep (the dash, with its
## graze window), a jetpack a thrust burst (`thrust_dodge_mult` of the
## dash's speed) and wings a flap hop (`flap_hop` m/s up). Swings pass
## through a dodging body (`evade_left`, the dodge's middle `evade_share`
## of it), rounds do not, except a boots dash's graze. After it the body
## needs `dodge_recover` seconds before its weapon answers again, so a
## dodge spent is a moment given away.
var roll_speed := 7.5
var roll_time := 0.45
var thrust_dodge_mult := 1.25
var flap_hop := 3.5
var evade_share := 0.75
var dodge_recover := 0.2
## Seconds left in which a melee hit passes through (`dodge_style` decides
## how it looks).
var evade_left := 0.0
## Seconds left of the last dodge (rolling, stepping), for views.
var dodge_left := 0.0
## The style of the dodge under way ("" when none).
var dodge_shown := ""
var _dodge_rest := 0.0
## Landing faster than this (m/s, about a 6 m drop) hurts: `fall_damage`
## health for every m/s over it, scaled by the rig (`FlightRig.fall_damage_mult`).
## Landing out of a glide never hurts.
var fall_safe_speed := 16.0
var fall_damage := 4.0
## How far over the head a roof counts as being indoors, for flight
## (`FlightRig.indoors`).
var roof_reach := 8.0

var eye_height := 1.6
## How tall the body stands: `BODY_HEIGHT` for a person. A world may make a
## big body taller (Ashfront's walkers) when it equips the bot; the capsule,
## `Combat.trace` and headshots all follow `body_height()`.
var stand_height := BODY_HEIGHT
## How wide the body is: `BODY_RADIUS` for a person. A world may make a
## big target fatter (a Sky Leviathan's engine pod) when it equips the bot;
## the capsule and `Combat.trace` follow it (`set_body_radius`).
var body_radius := BODY_RADIUS
## A weak spot: hits from behind (and from steeply above) are multiplied by
## this, in `modify_incoming`. 1 for no weak spot. Set by the world when it
## equips a bot, so it is the same on every machine.
var rear_damage_mult := 1.0
## Every hit is divided by this, in `modify_incoming`: a boss that grows
## tougher with the players round it (`WorldDef.boss_party_scale`). Only the
## authority sets it, since only the authority deals damage.
var toughness := 1.0
## How far round from straight behind a hit still counts as in the back.
var rear_arc_deg := 60.0
var interact_range := 3.5
var heal_duration := 3.0
var heal_amount := 50.0

# Stamina pays for melee, blocking and dashing.
var max_stamina := 100.0
var stamina := 100.0
var stamina_regen := 28.0
var stamina_regen_delay := 0.9
var dash_stamina := 20.0
var stagger_speed_mult := 0.35
## Sliding: pressing slide while running fast drops you low and skids you
## along the ground, from `slide_speed` (or your speed, if faster) down to
## `slide_end_speed` over `slide_time`. Jumping ends it and keeps the speed.
var slide_speed := 11.0
var slide_end_speed := 4.0
var slide_time := 0.8
## The least ground speed a slide can start from.
var slide_min_speed := 7.0
var slide_cooldown := 0.6
var slide_stamina := 10.0
## How far the eyes drop while sliding, and how fast they get there (per second).
var slide_eye_drop := 0.75
var crouch_rate := 8.0
## Crouching (`ActorCommand.crouch`, a held flag the controller toggles with
## the crouch key): a slow, quiet walk with the eyes `crouch_eye_drop` lower,
## the body `CROUCH_HEIGHT` tall, and guns `crouch_spread_mult` as wide.
## Bots notice a crouched actor outside their view only this much as close
## (`BotBrain.close_sense_range`), so sneaking up behind one works.
var crouch_speed := 3.0
var crouch_eye_drop := 0.4
var crouch_spread_mult := 0.75
var crouch_sense_mult := 0.4

## How often the actor is simulated: every tick (1), or every nth tick with
## the time made up in one longer step. The authority thins out bots that no
## player is near (`Raid._tick_detail`); a player's own actor is never thinned.
var tick_every := 1

var cmd := ActorCommand.new()
var health := HealthComponent.new()
var inventory := Inventory.new()
var flight := FlightRig.new()
## Where flight ceilings are measured from: the raid's map unless set (a
## bench or test with no raid sets its own). See `ground_level`.
var ground_map: Node3D = null
var ability := Ability.new()
## The artifact carried on the watch for this outing. Always there;
## `Artifact.enabled` says whether one is worn.
var artifact := Artifact.new()
## The helmet. Always there; `Visor.enabled` says whether one is worn.
var visor := Visor.new()
## Where the worn helmet is (DESIGN.md "Helmet off"): 0 on the head, 1
## clipped to the hip, between while the off hand takes it off or puts it
## back. It follows the held `ActorCommand.helmet_off` at the pace of
## `helmet_stow_time`, so it predicts online and everyone sees the same; the
## visor stops working once it leaves the face (`HELMET_LIFTED`) and works
## again once it is back on. The skin shows the hand and the clip from it.
var helmet_stow := 0.0
## Seconds the whole take off (or put on) takes, hand up to hip.
var helmet_stow_time := 1.1
## How far into the take off the helmet leaves the head: the hand has
## reached it by then (`ActionPose.helmet_hand`).
const HELMET_LIFTED := 0.3
var weapons: Array[Weapon] = []
var active_weapon_index := 0
## Item ids of equipped gear (weapons, rig, armor). Dropped on death.
var gear_items: Array[String] = []
var frame_name := "No armor"
## The armor frame worn (an item id), "" for none. Set by `Loadout.wear_frame`.
var frame_id := ""
## The backpack worn (an item id), "" for the field pack. It sets the
## pack's capacity (`Loadout.wear_pack`); it and its contents count toward
## the carry weight.
var pack_id := ""
## Carry weight (`CarryLoad`): what the body carries, in kg, and what it
## does to moving, worked out again whenever what it carries changes
## (`mark_carry`). On a client the server's number is used (`carry_sent`,
## set by `NetSession`), since a client never sees anyone else's pack.
var carry_sent := -1.0
var _carry_kg := 0.0
var _carry_dirty := true
var _carry_known := false
## Ground speed, sprint and slide; acceleration and turning; jump take-off;
## all as multiples from the load (`CarryLoad`).
var carry_speed := 1.0
var carry_accel := 1.0
var carry_jump := 1.0
## Armor left on frames taken off into the pack (item id -> armor), so one
## put back on is no fresher than it was. A frame found comes whole.
var stowed_armor := {}
## How warm this actor looks through a thermal visor next to a bare body (1).
## Armor frames change it (see `Visor.heat_of`).
var heat_signature := 1.0
## Body heat, in a world that chills its players (`WorldDef.cold`): drained
## out in the open, refilled by warmth (`Raid._tick_cold`), and hurting once
## it is gone. Only the authority changes it; the owner's game is sent it
## (`NetSession._body_heat`).
var max_body_heat := 100.0
var body_heat := 100.0
## Standing in warmth now (a heater, a vent, a running engine). Authority
## and owner only.
var warming := false
## The bot faction hunting this player for a grudge (`Raid.grudges`), or "".
## Set by the authority and sent to the owner only, for the visor.
var hunted_by := ""
## Cold enough to shiver: body heat under `CHILL_SHARE`. The authority sets
## it and every client gets it in the state (`ActorCommand.STATE_CHILLED`),
## so everyone sees the shivering.
var shivering := false
const CHILL_SHARE := 0.35
## The vehicle this actor is riding, or null. While riding, the vehicle moves
## the actor; weapons, healing and abilities still work.
var vehicle: Node3D = null

var is_dead := false
## Set in a safe zone: weapons can be drawn and shown but not used, and
## abilities and healing do nothing.
var weapons_locked := false
## Set for a blades bout in the arena (`Arena._apply_rules`, on every
## machine from the bout's rules): no gun may be drawn, and one in hand is
## put away for the blade, so a fighter brings only their melee weapon.
var guns_locked := false
var heal_time_left := 0.0
## Seconds until a weapon summoned from the watch has finished materializing
## in the hand (it cannot be used until then), and how long that one takes.
var materialize_left := 0.0
var materialize_time := 0.0
## The heavy weapon takes the primary's place (Caleb's call): while it is
## out the primary waits in the watch, and whenever the primary next comes
## into the hand (a key, the watch, a spent heavy) it materializes over its
## summon time. The sidearm and blade stay instant from either.
var primary_in_watch := false
## Seconds until a weapon being stored through the watch has dematerialized
## out of the hand (`Loadout.store_weapon`), and how long that one takes.
## It cannot be used or switched from meanwhile, and is gone after.
var dematerialize_left := 0.0
var dematerialize_time := 0.0
## The weapon dematerializing, or null.
var _storing: Weapon = null
## Rounds left in guns put away in the pack by a summon: item id ->
## [magazine, reserve]. A gun summoned back comes as it was put away.
var stowed_rounds := {}
## The toy vehicle in the right hand (an item id off the watch), or "".
## Set only by whoever runs the world (`Raid.hold_toy`, `HomeBase.hold_toy`)
## and copied to clients by `NetSession`; nothing in the simulation reads
## it. Every view draws the toy in the one hand (`ActorSkin._update_toy`).
var toy_in_hand := ""
## The salvage crate held in both hands (`SalvageCrate`, the `Raid`'s
## `lift_crate`), or null. While one is held no weapon comes out, the walk
## slows to `crate_speed` with no sprint, and no rig lifts off.
var crate: SalvageCrate = null
var crate_speed := 0.6
## How many toy throws this actor has started. A view that sees it go up
## plays the throw (`ActionPose.toy_throw_t`); a count, not a flag, so a
## repeated or late copy plays it once.
var toy_throws := 0
var airborne_time := 0.0
## Airborne sign-out: a column everyone can see (DESIGN.md section 7). The
## authority sets it; clients copy it from the state snapshot. A Phase Cloak
## does not hide it.
var sign_out_beacon := false
var _beacon_hum := 0.0
## While staggered the actor cannot attack, block, dash or jump.
var stagger_left := 0.0
## Seconds left on the ground after a knockdown (`knock_down`), of
## `knocked_time` in all.
var knocked_left := 0.0
var knocked_time := 0.0
## A yaw something asked this body to turn to (a shadow step lands facing
## the foe's back), or NAN. Whoever steers the body takes it: the player's
## controller turns the view to it; a bot's aim already follows its target.
var turn_request := NAN
## Seconds left of the current slide; above zero while sliding.
var slide_left := 0.0
## How far down into a slide the actor is, 0 standing to 1 down.
var slide_low := 0.0
## Crouched now. Follows `ActorCommand.crouch`, except that the actor stays
## down while there is no room overhead to stand (`room_to_stand`), and a
## slide that ends under something low ends crouched.
var crouched := false
## How far down into the crouch the actor is, 0 standing to 1 crouched. The
## eyes, the body's height and the skin's crouch pose follow it.
var crouch := 0.0
## After a parry, the next melee hit inside this window hits harder.
var riposte_left := 0.0
## Seconds left of drop-in protection: nothing can hurt this actor. It ends
## early the moment they attack someone (see `Combat.deal`).
var protected_left := 0.0
## DEV MODE: god mode, set by a solo `Raid` running `dev_cheats`. Checked in
## `Combat.deal`, like `protected_left`, so no hit gets through.
var dev_invulnerable := false
## A keeper under the water (the `Raid`'s keeper machinery, "boss_pool"):
## nothing hurts it while it is down. Set on the authority only.
var submerged := false
## Public reputation. Written by the `Raid` that decides it (online, copied
## from the server); read by nameplates and the HUD. See `RenownLedger`.
var renown := 0
## Scrip carried: pay that is lost with the body until it is banked. Written
## by the `Raid`, like renown.
var scrip := 0
## This life's contract counters so far (`Raid._count`), for views: the
## watch's contract icon reads it. Set by the authority, and online sent to
## the owner only. Counted toward contracts only on a sign-out.
var tally := {}
## What this life has sent home through depots so far, for views: the
## watch's sign-out icon reads it (`Hud.banked_line`). Items, their worth
## and the scrip banked. Set by the authority (`Raid._on_actor_banked`),
## and online sent to the owner only (`NetSession._banked`). Already in the
## stash, so a death never takes it.
var banked_count := 0
var banked_value := 0
var banked_scrip := 0
var rank := 0
var streak := 0
var bounty := 0
## Everyone can see where this actor is.
var exposed := false
var marked := false
var body_mesh: MeshInstance3D
## Holds the active weapon's model; the skin puts it in the model's hand.
var hand := Node3D.new()
## The weapon last put away with the holster key, drawn again by it.
var last_drawn := 0

var _ticks_waited := 0
var _dash_left := 0.0
var _dash_cd := 0.0
var _dash_dir := Vector3.ZERO
var _dash_speed_now := 0.0
var _slide_cd := 0.0
## The air dash (sprint pressed in the air with a rig): the velocity it
## added this tick, taken off again before the rig steers next tick, its
## direction and cooldown. `air_dash_left` is the time it has left and
## `air_dash_side` how much of it runs sideways (-1 left to 1 right), for
## the skin's barrel roll.
var air_dash_left := 0.0
## Boots: seconds left in a dash's graze window (`FlightRig.graze_window`).
var graze_left := 0.0
var air_dash_side := 0.0
var _air_dash_vel := Vector3.ZERO
var _air_dash_dir := Vector3.ZERO
var _air_dash_cd := 0.0
## Wings: how far the bank has rolled in, -1 to 1. It follows the strafe keys
## at `FlightRig.glide_bank_rate`, so a tap nudges the heading and a hold
## comes round at the full turn rate.
var _bank := 0.0
## Wings: the glide is still being launched (see `_glide_velocity`).
var _glide_launch := true
## Wings: the first spread since leaving the ground has not happened yet, so
## the launch carries the glide all the way to cruise (see `_glide_velocity`).
var _first_spread := true
## Boots: whether this time in the air has had its wall kick (`_wall_kick`).
var _wall_kicked := false
## How far past the body's edge a wall still takes a boots' wall kick.
const WALL_KICK_REACH := 0.5
## Wings: seconds until a main gun can fire again after the wings fold.
var _wing_stow := 0.0
## Jetpack: the trigger pulled in a boost brings you upright into a hover,
## and the jets hold you there while it stays held (`_wants_hover`).
var _boost_flare := false
## Skating last tick: touching the floor mid-skate lifts you straight back up.
var _was_skating := false
## Jetpack: the heading a boost holds while free look is held (NAN: none,
## the boost follows the view).
var _boost_yaw := NAN
var _slide_dir := Vector3.ZERO
var _slide_from := 0.0
var _was_on_floor := true
## Where the feet last stood, and whether the worn rig counts its ceiling
## from there (`_ceiling_from_floor`, asked again when the rig changes).
var _floor_y := NAN
var _floor_rule_rig := "\n"
var _floor_rule := false
var _stamina_wait := 0.0
var _flash_left := 0.0
var _healing_with := ""
var _base_material: Material
var _body_shape: CapsuleShape3D
var _body_col: CollisionShape3D


func _init() -> void:
	health.name = "Health"
	inventory.name = "Inventory"
	flight.name = "FlightRig"
	add_child(health)
	add_child(inventory)
	add_child(flight)
	ability.name = "Ability"
	ability.actor = self
	add_child(ability)
	artifact.name = "Artifact"
	artifact.actor = self
	add_child(artifact)
	visor.name = "Visor"
	visor.actor = self
	add_child(visor)
	hand.name = "Hand"
	hand.position = HAND_REST
	add_child(hand)


func _ready() -> void:
	add_to_group("actors")
	collision_layer = LAYER_ACTORS
	collision_mask = LAYER_WORLD | LAYER_ACTORS | LAYER_VEHICLES
	floor_snap_length = 0.3
	_build_body()
	health.died.connect(_on_health_died)
	health.damaged.connect(_on_health_damaged)
	inventory.changed.connect(mark_carry)


func _build_body() -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = BODY_RADIUS
	shape.height = BODY_HEIGHT
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = BODY_HEIGHT * 0.5
	add_child(col)
	_body_shape = shape
	_body_col = col

	var mesh := CapsuleMesh.new()
	mesh.radius = 0.4
	mesh.height = 1.8
	var mat := StandardMaterial3D.new()
	mat.albedo_color = body_color
	mesh.material = mat
	body_mesh = MeshInstance3D.new()
	body_mesh.mesh = mesh
	body_mesh.position.y = 0.9
	add_child(body_mesh)

	# A visor so you can tell which way a greybox character is facing.
	var visor_mesh := BoxMesh.new()
	visor_mesh.size = Vector3(0.5, 0.15, 0.2)
	var visor_mat := StandardMaterial3D.new()
	visor_mat.albedo_color = Color(0.05, 0.05, 0.05)
	visor_mesh.material = visor_mat
	var visor := MeshInstance3D.new()
	visor.mesh = visor_mesh
	visor.position = Vector3(0, 0.65, -0.32)
	body_mesh.add_child(visor)


## Thins the actor out to one step every `every` ticks. `phase` spreads
## thinned actors over different ticks.
func thin(every: int, phase := 0) -> void:
	every = maxi(every, 1)
	if every == tick_every:
		return
	tick_every = every
	_ticks_waited = phase % every


## Whether the actor is simulated this tick. Whatever drives it (a bot's
## brain) asks before the actor's own step, and skips the same ticks.
func ticks_now() -> bool:
	return _ticks_waited + 1 >= tick_every


## Whether the actor took a step in the tick just gone.
func stepped() -> bool:
	return _ticks_waited == 0


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	if tick_every > 1:
		if not ticks_now():
			_ticks_waited += 1
			return
		_ticks_waited = 0
		delta *= tick_every
	rotation.y = cmd.yaw
	hand.position = HAND_REST
	hand.rotation = Vector3(cmd.pitch, 0.0, 0.0)
	_simulate_timers(delta)
	if vehicle == null:
		_simulate_movement(delta)
	elif crouched or crouch > 0.0 or slide_low > 0.0:
		# Seated: the vehicle carries the body; nobody rides crouched.
		crouched = false
		crouch = 0.0
		slide_low = 0.0
		_fit_body()
	_simulate_weapons(delta)
	ability.tick(delta)
	if cmd.ability_pressed and stagger_left <= 0.0 and not weapons_locked:
		ability.activate()
	artifact.tick(delta)
	if cmd.artifact_pressed and stagger_left <= 0.0 and not weapons_locked:
		artifact.activate()
	_simulate_helmet(delta)
	visor.tick(cmd, delta)
	if not weapons_locked:
		_simulate_heal(delta)
	# On a client of an online raid, using things is the server's decision.
	if cmd.interact_pressed and Combat.authoritative:
		var target := find_interactable()
		var raid := Raid.of(self) if crate != null else null
		if raid != null:
			# Hands full: the crate goes into what you look at, or down.
			raid.set_down_crate(self, target)
		elif target:
			target.interact(self)
	if global_position.y < WorldDef.VOID_Y_MAX and _below_world():
		kill("void")
	_pulse_sign_out_beacon(delta)


## The helmet comes off onto the hip, or back on, as the command asks
## (`helmet_stow`). Bare-headed there is nothing to take off.
func _simulate_helmet(delta: float) -> void:
	if not visor.enabled:
		helmet_stow = 0.0
		visor.stowed = false
		return
	var off := cmd.helmet_off and not is_dead
	helmet_stow = move_toward(helmet_stow, 1.0 if off else 0.0, delta / maxf(helmet_stow_time, 0.01))
	visor.stowed = helmet_stow >= HELMET_LIFTED


## True while a helmet is worn and on the head, not clipped to the hip.
func helmet_on_head() -> bool:
	return visor.working()


## True while the lamp on the helmet's brow shines: switched on (the held
## `ActorCommand.lamp`), the helmet on the head and its wearer alive. On the
## hip it goes dark and comes back on with the helmet. The beam is drawn by
## `ActorSkin` (view only).
func lamp_lit() -> bool:
	return cmd.lamp and helmet_on_head() and not is_dead


## Fallen out of the world: below its `WorldDef.void_y`. Asked only once
## below the highest any world sets, so the walk up the tree is rare.
func _below_world() -> bool:
	var world := Worlds.of(self)
	return global_position.y < (world.void_y if world != null else WorldDef.VOID_Y_MAX)


func _simulate_timers(delta: float) -> void:
	stagger_left = maxf(0.0, stagger_left - delta)
	knocked_left = maxf(0.0, knocked_left - delta)
	riposte_left = maxf(0.0, riposte_left - delta)
	protected_left = maxf(0.0, protected_left - delta)
	flight.jam_left = maxf(0.0, flight.jam_left - delta)
	graze_left = maxf(0.0, graze_left - delta)
	_stamina_wait = maxf(0.0, _stamina_wait - delta)
	if _stamina_wait <= 0.0:
		stamina = minf(max_stamina, stamina + stamina_regen * delta)
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0 and body_mesh:
			body_mesh.material_override = _base_material


## Takes stamina if there is enough. Returns false and takes nothing otherwise.
func spend_stamina(amount: float) -> bool:
	if amount <= 0.0:
		return true
	if stamina < amount:
		return false
	stamina -= amount
	_stamina_wait = stamina_regen_delay
	return true


func pause_stamina_regen() -> void:
	_stamina_wait = maxf(_stamina_wait, 0.2)


func stagger(duration: float) -> void:
	stagger_left = maxf(stagger_left, duration)
	notice.emit("Staggered")


## Knocks this body off its feet for `duration` (the hammer's ground
## pound): down on the ground and up again, staggered all the while and
## unable to walk. The server's call; clients see it through
## `ActorCommand.STATE_KNOCKED_DOWN`, and `ActorSkin` shows the fall.
func knock_down(duration: float) -> void:
	stagger_left = maxf(stagger_left, duration)
	if knocked_left <= 0.0:
		knocked_time = duration
	knocked_left = maxf(knocked_left, duration)
	knocked_time = maxf(knocked_time, knocked_left)
	notice.emit("Knocked down")


## How this body dodges now: "roll" on the ground with no working rig,
## "jet_step" in boots, "thrust" in a jetpack, "flap" in wings, and a
## plain "dash" in the air with no rig.
func dodge_style(on_floor := true) -> String:
	if not flight.enabled or not flight.working():
		return "roll" if on_floor else "dash"
	if flight.glide_speed > 0.0:
		return "flap"
	if flight.graze_window > 0.0:
		return "jet_step"
	return "thrust"


## True while a dodge and its recovery keep the weapon from answering.
func dodging() -> bool:
	return _dodge_rest > 0.0


## Gives the weapon in hand a chance to block or parry a hit.
func modify_incoming(info: DamageInfo) -> void:
	if evade_left > 0.0 and info.kind in ["melee", "slam", "hook"] and not is_dead:
		# Mid-dodge, a swing passes through.
		info.amount = 0.0
		notice.emit("Evaded")
		return
	var weapon := get_active_weapon()
	if weapon and not is_dead and stagger_left <= 0.0:
		weapon.modify_incoming(info)
	ability.modify_incoming(info)
	# Boots: a round that lands in a dash's graze window only grazes.
	if graze_left > 0.0 and info.kind == "bullet":
		info.amount *= flight.graze_mult
	if rear_damage_mult != 1.0 and hit_from_behind(info):
		info.amount *= rear_damage_mult
	if toughness > 1.0:
		info.amount /= toughness


## Whether a hit comes at the body's back (within `rear_arc_deg` of straight
## behind the way it faces) or from steeply above, judged from where the
## attacker stands, else from where the hit landed.
func hit_from_behind(info: DamageInfo) -> bool:
	var from := info.position
	if info.source is Node3D and is_instance_valid(info.source):
		from = (info.source as Node3D).global_position
	var to := from - (global_position + Vector3(0.0, stand_height * 0.5, 0.0))
	if to.length_squared() < 0.0001:
		return false
	to = to.normalized()
	if to.y > 0.8:
		return true
	var flat := Vector3(to.x, 0.0, to.z)
	if flat.length_squared() < 0.0001:
		return false
	var facing := Basis(Vector3.UP, cmd.yaw) * Vector3.FORWARD
	return facing.angle_to(flat.normalized()) >= PI - deg_to_rad(rear_arc_deg)

func _simulate_movement(delta: float) -> void:
	var on_floor := is_on_floor()
	var yaw_basis := Basis(Vector3.UP, cmd.yaw)
	var wish := yaw_basis * Vector3(cmd.move.x, 0.0, -cmd.move.y)
	if wish.length() > 1.0:
		wish = wish.normalized()

	refresh_carry()
	var speed := sprint_speed if (cmd.sprint and cmd.move.y > 0.0) else walk_speed
	if crate != null:
		# A crate in both hands: a slow walk, and no rig takes the weight.
		speed = walk_speed * crate_speed
		cmd.jump = false
		if not on_floor:
			cmd.jump_pressed = false
	# Looking through binoculars: no running, and a slow walk.
	if visor.is_zoomed():
		speed = walk_speed * visor.move_mult()
	if crouched and on_floor:
		speed = minf(speed, crouch_speed)
	var held := get_active_weapon()
	if held is Gun and ((held as Gun).is_aiming() or cmd.primary):
		# Aimed, or pulling the trigger, a sprint is only a walk.
		speed = minf(speed, walk_speed)
	if speed > walk_speed and on_floor and cmd.move.y > 0.0:
		sprint_recover = sprint_out_time
	if held:
		speed *= held.move_speed_mult()
	if flight.enabled:
		speed *= flight.ground_speed_mult
	speed *= carry_speed
	var staggered := stagger_left > 0.0
	if staggered:
		speed *= stagger_speed_mult
	if knocked_left > 0.0:
		# Down on the ground: no walking until back up.
		speed = 0.0
	# Take last tick's air dash back off, as far as it is still there (a wall
	# may have stopped it), so the rig's own flight carries on underneath.
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if _air_dash_vel != Vector3.ZERO:
		var dir := _air_dash_vel.normalized()
		horizontal -= dir * clampf(horizontal.dot(dir), 0.0, _air_dash_vel.length())
		_air_dash_vel = Vector3.ZERO
	if on_floor:
		flight.launched = false
		_first_spread = true
		_wall_kicked = false
	flight.refill(delta, on_floor)
	_measure_altitude(on_floor)
	_measure_indoors(on_floor)
	# A boost cut by the trigger flares upright into a hover while it is held.
	_boost_flare = cmd.primary and not on_floor and (_boost_flare or flight.is_boosting)
	# Gliding: holding jump while falling with wings carries you forward.
	# Once gliding you stay gliding while you climb on your speed.
	# Soaring (held sprint), the wings keep gliding with jump let go.
	flight.is_gliding = flight.can_glide() and not on_floor and not staggered \
			and (cmd.jump or (flight.is_gliding and cmd.sprint and flight.can_soar())) \
			and (velocity.y < 0.0 or flight.is_gliding)
	flight.is_soaring = flight.is_gliding and cmd.sprint and flight.can_soar() and not flight.overheated
	flight.is_skating = _wants_skate(on_floor, staggered)
	_was_skating = flight.is_skating
	flight.is_skimming = flight.skim_ready() and cmd.jump and not on_floor and not staggered and not flight.is_skating
	if not flight.is_gliding:
		if not _glide_launch:
			_first_spread = false
		_bank = 0.0
		_glide_launch = true
	if flight.is_skating:
		horizontal = _skate_velocity(horizontal, wish, yaw_basis, delta)
	elif on_floor:
		horizontal = horizontal.move_toward(wish * speed, ground_accel * carry_accel * delta)
	elif flight.is_skimming:
		horizontal = horizontal.move_toward(wish * flight.skim_speed, flight.skim_accel * delta)
	elif flight.is_gliding:
		horizontal = _glide_velocity(horizontal, wish, yaw_basis, delta)
	elif _wants_boost(on_floor, staggered):
		pass  # Boosting: `_simulate_hover` flies the whole velocity.
	elif _wants_hover(on_floor, staggered):
		horizontal = _cruise_velocity(horizontal, wish, delta)
	elif wish.length() > 0.01:
		# In the air you can steer but you keep your momentum if you let go.
		horizontal = horizontal.move_toward(wish * speed, air_accel * carry_accel * delta)

	_dash_cd = maxf(0.0, _dash_cd - delta)
	evade_left = maxf(0.0, evade_left - delta)
	dodge_left = maxf(0.0, dodge_left - delta)
	_dodge_rest = maxf(0.0, _dodge_rest - delta)
	if cmd.dash and _dash_cd <= 0.0 and not staggered and spend_stamina(dash_stamina):
		_dash_dir = wish.normalized() if wish.length() > 0.1 else yaw_basis * Vector3.FORWARD
		var style := dodge_style(on_floor)
		_dash_left = roll_time if style == "roll" else dash_time
		_dash_cd = dash_cooldown
		_dash_speed_now = roll_speed if style == "roll" else dash_speed * (thrust_dodge_mult if style == "thrust" else 1.0)
		graze_left = flight.graze_window if flight.working() else 0.0
		if style == "flap" and on_floor:
			velocity.y = maxf(velocity.y, flap_hop)
		evade_left = _dash_left * evade_share
		dodge_left = _dash_left
		dodge_shown = style
		_dodge_rest = _dash_left + dodge_recover
	if _dash_left > 0.0:
		_dash_left -= delta
		horizontal = _dash_dir * _dash_speed_now
		slide_left = 0.0
	horizontal = _simulate_slide(horizontal, on_floor, staggered, delta)
	_simulate_crouch(delta)

	horizontal += _air_dash(wish, yaw_basis, on_floor, staggered, delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if on_floor and cmd.jump_pressed and not staggered:
		velocity.y = jump_velocity * carry_jump
	elif cmd.jump_pressed and not staggered and flight.is_gliding and flight.pulse_velocity > 0.0:
		# A wing pulse: up, keeping the airspeed.
		var pulse := flight.try_pulse(flight.lift_cap(gravity))
		if pulse > 0.0:
			velocity.y = maxf(velocity.y, pulse)
	elif cmd.jump_pressed and not staggered and not on_floor and _wall_kick():
		pass  # Kicked off a wall: free, once a time in the air.
	elif cmd.jump_pressed and not staggered:
		var burst := flight.try_burst(flight.lift_cap(gravity))
		if burst > 0.0:
			velocity.y = maxf(velocity.y, burst)
			if flight.burst_push > 0.0 and wish.length() > 0.1:
				# Boots kick you the way you steer, not only up.
				var push := wish.normalized() * flight.burst_push
				var along := Vector3(velocity.x, 0.0, velocity.z).dot(wish.normalized())
				push *= clampf(1.0 - along / (flight.burst_push * 2.0), 0.0, 1.0)
				velocity.x += push.x
				velocity.z += push.z
	# A jetpack's jets hold you up only while aim is held, and a boost lights
	# them too (Caleb's call: no hover that stays on by itself).
	flight.is_boosting = _wants_boost(on_floor, staggered)
	flight.is_hovering = flight.is_boosting or _wants_hover(on_floor, staggered)
	flight.is_coasting = false
	if not flight.is_boosting or not cmd.free_look:
		_boost_yaw = NAN
	if flight.is_hovering:
		_simulate_hover(delta)
	elif flight.is_skating:
		_simulate_skate(delta)
	elif flight.is_skimming:
		_simulate_skim(delta)
	else:
		# Wings cool only on the ground; boots only near a surface.
		flight.aloft = not on_floor and (flight.ground_cool_only or (flight.can_skim()
				and height_above_ground(flight.skim_probe) >= flight.skim_low))
		var thrust := flight.tick(cmd.jump and not on_floor and not staggered, delta, flight.climb_heat_mult)
		velocity.y += (thrust - gravity) * delta
		if thrust > 0.0:
			# Under the ceiling the climb eases off and stops on it.
			velocity.y = minf(velocity.y, flight.max_rise_speed * flight.climb_room() * flight.indoor_factor())
		if flight.is_gliding:
			# The wings catch a fall or a dive over a moment, never in one
			# tick: sinking faster than the glide allows eases back to it.
			var sink := -_glide_sink()
			var caught := velocity.y if velocity.y >= sink \
					else minf(sink, velocity.y + (gravity + flight.glide_catch_accel) * delta)
			# Pulling up with speed in hand climbs on it.
			var pull := -glide_trim()
			var air_speed := Vector2(velocity.x, velocity.z).length()
			var spare := air_speed - flight.glide_speed * flight.glide_stall
			if pull > 0.0 and spare > 0.1:
				# The lift fades out as the speed comes down to the stall.
				var lift := air_speed * sin(pull * 0.7) * clampf(spare / (flight.glide_speed * 0.15), 0.0, 1.0)
				# Banked, the pull goes into the turn more than into height.
				lift *= 1.0 - flight.glide_bank_lift_loss * absf(_bank)
				# Speed buys height only up to the ceiling; soaring, the
				# thrust climbs steadily, never in a zoom.
				lift = minf(lift, flight.lift_cap(gravity))
				if flight.is_soaring:
					lift = minf(lift, flight.soar_climb)
				caught = maxf(caught, minf(lift, velocity.y + (gravity + flight.glide_lift_accel) * delta))
			velocity.y = caught
	_take_gusts(on_floor, delta)
	velocity.y = maxf(velocity.y, -max_fall_speed)

	# The air rising under an updraft carries the body along on top of its
	# own climb or fall: added for the move and taken off again after it.
	var rise := _ride_updraft(on_floor)
	velocity.y += rise
	var fall_speed := -velocity.y
	var gliding := flight.is_gliding
	if tick_every > 1:
		# One longer step: the engine moves a body by one tick of velocity.
		velocity *= tick_every
		move_and_slide()
		velocity /= tick_every
	else:
		move_and_slide()
	if rise != 0.0:
		# Landed or bumped a roof: the slide already took the speed off.
		velocity.y = minf(velocity.y, 0.0) if is_on_floor() or is_on_ceiling() else velocity.y - rise

	var now_on_floor := is_on_floor()
	airborne_time = 0.0 if now_on_floor else airborne_time + delta
	if now_on_floor and not _was_on_floor:
		_slide_landing()
		landed.emit(maxf(fall_speed, 0.0))
		_hurt_by_fall(fall_speed, gliding)
	_was_on_floor = now_on_floor


## A storm's gusts push a flight rig in the air (DESIGN.md "Weather: ash
## storms"), by its `gust_mult`. An acceleration, never a jolt, and a matter
## of where the actor is in the storm only, so a client predicts it.
func _take_gusts(on_floor: bool, delta: float) -> void:
	if on_floor or not flight.enabled or flight.gust_mult <= 0.0 or vehicle != null:
		return
	var raid := Raid.of(self)
	if raid == null or raid.weather.kind == "":
		return
	velocity += raid.weather.gust_at(global_position) * flight.gust_mult * delta


## How fast the air carries the actor up where it is (`WorldDef.updraft_at`):
## only in the air and out of a vehicle. Wings riding it spend no glide
## stamina (`FlightRig.in_updraft`). A matter of where the actor is only,
## so a client predicts it.
func _ride_updraft(on_floor: bool) -> float:
	flight.in_updraft = false
	if on_floor or vehicle != null:
		return 0.0
	var raid := Raid.of(self)
	if raid == null or raid.world == null:
		return 0.0
	var rise := raid.world.updraft_at(global_position)
	flight.in_updraft = rise > 0.0
	return rise


## A jetpack hovers in the air only while aim (`ActorCommand.secondary`,
## the right mouse button) is held: let go and you fall, or climb on held jump.
func _wants_hover(on_floor: bool, staggered: bool) -> bool:
	return (cmd.secondary or _boost_flare) and not on_floor and not staggered \
			and flight.can_hover() and not flight.overheated


## A jetpack boosts in the air on sprint, forward or with no move key
## (Shift with a strafe or back key is only the air dash): the jets light
## and speed you up head first along the view's heading, and the skin lays
## the body out prone as the speed builds (`ActorSkin._update_glide`). It
## needs no hover first. A press in the air starts it (so a sprinting jump
## off the ground stays a jump) and holding sprint keeps it going; with the
## jets already lit (aim held, or a boost running) holding it is enough,
## which is also how a remote player's boost follows the replicated jets.
## The boost is travel, not a fight (Caleb's call): aim or the trigger held
## brings you upright into a hover (`_boost_flare`), and a gun fires only
## `sprint_out_time` after the boost ends, as out of a sprint on the ground.
func _wants_boost(on_floor: bool, staggered: bool) -> bool:
	if on_floor or staggered or flight.boost_speed <= 0.0 or not flight.can_hover() or flight.overheated:
		return false
	if cmd.secondary or cmd.primary:
		return false
	if not cmd.sprint or not (cmd.move.y > 0.0 or cmd.move.length() < 0.1):
		return false
	return cmd.sprint_pressed or flight.is_hovering


## Jets lit: the rig carries your weight. Jump climbs, descend sinks, and a
## boost flies you head first along the view's heading, level unless jump or
## descend is held. The mouse's pitch never steers.
func _simulate_hover(delta: float) -> void:
	var climb := (1.0 if cmd.jump else 0.0) - (1.0 if cmd.descend else 0.0)
	flight.is_coasting = climb < 0.0 and not flight.is_boosting
	if flight.is_boosting:
		# Along the view's heading, level: jump and descend climb and sink.
		# The mouse's pitch only aims (Caleb's call: keys fly). Free look
		# held, the boost holds the heading it had and the view looks round
		# (like the wings); let go, it comes back round onto the view.
		if cmd.free_look and is_nan(_boost_yaw):
			var flat := Vector2(velocity.x, velocity.z)
			_boost_yaw = atan2(-velocity.x, -velocity.z) if flat.length() > 1.0 else cmd.yaw
		var heading := cmd.yaw if is_nan(_boost_yaw) else _boost_yaw
		sprint_recover = sprint_out_time
		var clumsy := flight.indoor_factor()
		var want := Basis(Vector3.UP, heading) * Vector3(cmd.move.x * flight.fly_speed * 0.5, 0.0, -flight.boost_speed) * clumsy
		want.y += flight.max_rise_speed * flight.climb_room() * clumsy if climb > 0.0 else climb * flight.descend_speed
		# Spooling up from slow it pulls hard, easing off near cruise speed.
		var going := clampf(Vector2(velocity.x, velocity.z).length() / maxf(flight.boost_speed, 0.1), 0.0, 1.0)
		var accel := lerpf(maxf(flight.boost_launch_accel, flight.boost_accel), flight.boost_accel, going * going)
		velocity = velocity.move_toward(want, accel * delta)
		# Travel is cheap; a climb in a boost costs what any climb does.
		flight.tick(true, delta, lerpf(flight.boost_heat_mult, maxf(flight.boost_heat_mult, flight.climb_heat_mult),
				flight.climb_room()) if climb > 0.0 else flight.boost_heat_mult)
		return
	var rise := flight.max_rise_speed * flight.climb_room() * flight.indoor_factor() if climb > 0.0 \
			else climb * flight.descend_speed
	velocity.y = move_toward(velocity.y, rise, flight.hover_accel * delta)
	if flight.is_coasting:
		# Jets idle: sink, keep the speed, and cool off.
		flight.coast(delta)
		return
	var cruising := Vector2(velocity.x, velocity.z).length() > flight.fly_speed * 0.5
	var level := flight.cruise_heat_mult if cruising else flight.hover_heat_mult
	# Under the ceiling the climb eases off, and so does what it costs: held
	# on the ceiling, the jets only hold you there.
	flight.tick(true, delta, lerpf(level, flight.climb_heat_mult, flight.climb_room()) if climb > 0.0 else level)


## Boots skate (Caleb's call: every rig cruises its own way): held sprint
## in the air, or on from a skate that touched down, within `skate_reach`
## of a surface. Back held brakes out of it.
func _wants_skate(on_floor: bool, staggered: bool) -> bool:
	if not flight.can_skate() or staggered or not cmd.sprint or cmd.move.y < -0.1:
		return false
	if on_floor and not _was_skating:
		return false
	return on_floor or height_above_ground(flight.skate_reach) < flight.skate_reach


## Skating: the boots carve after the view (and the strafe keys) at
## `skate_turn_rate`, speeding up to `skate_speed`.
func _skate_velocity(horizontal: Vector3, wish: Vector3, yaw_basis: Basis, delta: float) -> Vector3:
	var want := wish.normalized() if wish.length() > 0.1 else yaw_basis * Vector3.FORWARD
	var speed := horizontal.length()
	var heading := horizontal / speed if speed > 1.0 else want
	var angle := heading.signed_angle_to(want, Vector3.UP)
	var step := flight.skate_turn_rate * delta
	heading = heading.rotated(Vector3.UP, clampf(angle, -step, step))
	# A hard carve costs a little speed.
	var top := flight.skate_speed * flight.indoor_factor() * (1.0 - 0.15 * clampf(absf(angle), 0.0, 1.0))
	return heading * move_toward(speed, top, flight.skate_accel * delta)


## Skating: the boots hold `skate_height` over whatever is below, rising and
## sinking with it; a kick still carries you up first.
func _simulate_skate(delta: float) -> void:
	var height := height_above_ground(flight.skate_reach)
	if velocity.y > 0.0 and height > flight.skate_height:
		velocity.y -= gravity * delta
	else:
		var want := clampf((flight.skate_height - height) * 4.0, -flight.skate_lift, flight.skate_lift)
		velocity.y = move_toward(velocity.y, want, (gravity + 20.0) * delta)
	flight.tick(false, delta)


## Boots skimming: a kick rises as usual, then the boots hold your height
## (descend sinks), and the heat follows the height over what is below.
func _simulate_skim(delta: float) -> void:
	if velocity.y > 0.0 and not cmd.descend:
		velocity.y -= gravity * delta
	else:
		velocity.y = move_toward(velocity.y, -flight.descend_speed if cmd.descend else 0.0,
				flight.skim_hold_accel * delta)
	flight.skim(delta, height_above_ground(flight.skim_probe))


## Boots kick off a wall (Caleb's call, the style pass: free-running): jump
## pressed in the air with a wall beside you kicks you up (`wall_kick`, cut
## to top out on the ceiling) and away from it (`wall_kick_push`), keeping
## the speed you had along it, for no charge, once a time in the air. A
## matter of the command and the map only, so a client predicts it.
func _wall_kick() -> bool:
	if flight.wall_kick <= 0.0 or _wall_kicked or not flight.working() or flight.is_skating:
		return false
	var up := minf(flight.wall_kick, flight.lift_cap(gravity))
	if up < FlightRig.MIN_LIFT:
		return false
	var normal := wall_beside(BODY_RADIUS + WALL_KICK_REACH)
	if normal == Vector3.ZERO:
		return false
	_wall_kicked = true
	velocity.y = maxf(velocity.y, up)
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	flat -= normal * minf(flat.dot(normal), 0.0)
	flat += normal * flight.wall_kick_push
	velocity.x = flat.x
	velocity.z = flat.z
	flight.burst_fired.emit()
	return true


## The level way out of the nearest wall within `reach` of the body's
## middle (eight rays round it at waist height), or zero if there is none.
func wall_beside(reach: float) -> Vector3:
	if not is_inside_tree():
		return Vector3.ZERO
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0.0, 0.9, 0.0)
	var best := INF
	var normal := Vector3.ZERO
	for i in 8:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 8.0)
		var query := PhysicsRayQueryParameters3D.create(from, from + dir * reach, LAYER_WORLD)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var n: Vector3 = hit["normal"]
		var level := Vector3(n.x, 0.0, n.z)
		var dist := from.distance_to(hit["position"])
		if level.length() > 0.7 and dist < best:
			best = dist
			normal = level.normalized()
	return normal


## Tells the flight rig how high it is over the world's ground, for its
## ceiling (`FlightRig.ceiling`). Only rigs with a ceiling ask, and only in
## the air.
## A world may have a rig count from the floor its wearer last stood on
## instead (`WorldDef.rig_ceiling_from_floor`).
func _measure_altitude(on_floor: bool) -> void:
	flight.altitude_known = false
	if on_floor:
		_floor_y = global_position.y
	if not flight.enabled or flight.ceiling <= 0.0 or on_floor:
		return
	var ground := ground_level()
	if is_nan(ground):
		return
	if not is_nan(_floor_y) and _floor_y > ground and _ceiling_from_floor():
		ground = _floor_y
	flight.altitude_known = true
	flight.altitude = global_position.y - ground


## Whether the world has this rig count its ceiling from the last floor,
## asked once per rig worn.
func _ceiling_from_floor() -> bool:
	if _floor_rule_rig != flight.item_id:
		var raid := Raid.of(self)
		_floor_rule_rig = flight.item_id
		_floor_rule = raid != null and raid.world != null and raid.world.rig_ceiling_from_floor(flight.item_id)
	return _floor_rule


## The height of the world's ground under the actor, ignoring roofs and
## anything else built on it: the map's `ground_height` where it has one,
## else the map's own origin (see the map contract in `WorldDef`). NAN
## outside a raid, where nothing says where the ground is.
func ground_level() -> float:
	var map := ground_map
	if map == null:
		var raid := Raid.of(self)
		map = raid.map if raid != null else null
	if map == null or not is_instance_valid(map) or not map.is_inside_tree():
		return NAN
	if map.has_method("ground_height"):
		return map.call("ground_height", global_position.x, global_position.z)
	return map.global_position.y


## How high the feet are over the world below, up to `reach` meters.
func height_above_ground(reach: float) -> float:
	if not is_inside_tree():
		return reach
	var from := global_position + Vector3(0.0, 0.1, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3(0.0, -reach - 0.1, 0.0), LAYER_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return reach if hit.is_empty() else maxf(0.0, global_position.y - (hit["position"] as Vector3).y)


## Tells the flight rig whether a roof is close overhead (`roof_reach`),
## for rigs that fly worse indoors. Only in the air, and only for a rig that
## cares (`FlightRig.indoor_mult` under 1).
func _measure_indoors(on_floor: bool) -> void:
	flight.indoors = false
	if on_floor or not flight.enabled or flight.indoor_mult >= 1.0 or not is_inside_tree():
		return
	var from := global_position + Vector3(0.0, BODY_HEIGHT, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3(0.0, roof_reach, 0.0), LAYER_WORLD)
	flight.indoors = not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## A hard landing in a world hurts, through `Combat.deal` like any damage
## (so a safe zone refuses it). A glide lands softly, and the rig scales the
## rest (`FlightRig.fall_damage_mult`).
func _hurt_by_fall(fall_speed: float, gliding: bool) -> void:
	var mult := flight.fall_damage_mult if flight.enabled else 1.0
	var amount := (fall_speed - fall_safe_speed) * fall_damage * mult
	# Only out in a world: the home base and other test rooms cost nothing.
	if amount <= 0.0 or gliding or vehicle != null or is_dead or Raid.of(self) == null:
		return
	var info := DamageInfo.new()
	info.amount = amount
	info.kind = "fall"
	info.position = global_position
	info.armor_pierce = 1.0
	Combat.deal(self, info)


## Jets lit: the move keys cruise you about. Slow, you go where you steer;
## at speed the heading only turns at `FlightRig.cruise_turn_rate`, and
## letting go of the keys (or pulling the other way) brakes to a stop.
func _cruise_velocity(horizontal: Vector3, wish: Vector3, delta: float) -> Vector3:
	var speed := horizontal.length()
	var fly_speed := flight.fly_speed * flight.indoor_factor()
	if wish.length() < 0.1 or speed < fly_speed * 0.6:
		return horizontal.move_toward(wish * fly_speed, flight.fly_accel * carry_accel * delta)
	var heading := horizontal / speed
	var angle := heading.signed_angle_to(wish.normalized(), Vector3.UP)
	if absf(angle) > 2.0:
		return horizontal.move_toward(Vector3.ZERO, flight.fly_accel * carry_accel * delta)
	var step := flight.cruise_turn_rate * carry_accel * delta
	heading = heading.rotated(Vector3.UP, clampf(angle, -step, step))
	return heading * move_toward(speed, wish.length() * fly_speed, flight.fly_accel * carry_accel * delta)


## Every rig: sprint pressed in the air dashes the way the move keys point,
## forward with none held, on heat. Returns the velocity to add this tick;
## it is taken off again next tick, so the rig's own flight (a glide, a
## cruise, a skim) carries on the same way after it.
func _air_dash(wish: Vector3, yaw_basis: Basis, on_floor: bool, staggered: bool, delta: float) -> Vector3:
	_air_dash_cd = maxf(0.0, _air_dash_cd - delta)
	if on_floor or staggered:
		air_dash_left = 0.0
	elif cmd.sprint_pressed and _air_dash_cd <= 0.0 and air_dash_left <= 0.0 \
			and not _wants_boost(on_floor, staggered):
		# A press that starts (or is in) a jetpack boost is the boost's,
		# not a dash on top of it: that lurched ahead and stalled.
		var boost := _glide_boost_kind()
		if not flight.try_air_dash(flight.glide_boost_heat if boost != 0 else -1.0):
			return Vector3.ZERO
		_air_dash_cd = flight.air_dash_time + flight.air_dash_cooldown
		air_dash_side = 0.0
		if boost < 0:
			# Wings pulled up (back held): the boost climbs instead of going
			# backwards (Caleb's call), keeping the airspeed like a pulse.
			velocity.y = maxf(velocity.y, minf(flight.glide_boost_climb, flight.lift_cap(gravity)))
			return Vector3.ZERO
		if boost > 0:
			# A wing boost thrusts you the way you face (the way the wings
			# point, in free look), and the speed is kept: the glide carries
			# it and bleeds it off at `glide_drag`.
			var ahead := Vector3(velocity.x, 0.0, velocity.z)
			var thrust := ahead.normalized() if cmd.free_look and ahead.length() > 1.0 else yaw_basis * Vector3.FORWARD
			return thrust * flight.glide_boost
		_air_dash_dir = wish.normalized() if wish.length() > 0.1 else yaw_basis * Vector3.FORWARD
		air_dash_side = (yaw_basis.inverse() * _air_dash_dir).x
		air_dash_left = flight.air_dash_time
		graze_left = flight.graze_window
	if air_dash_left <= 0.0:
		return Vector3.ZERO
	air_dash_left -= delta
	_air_dash_vel = _air_dash_dir * flight.air_dash_speed
	return _air_dash_vel


## What a sprint press does in a glide on a rig with a wing boost
## (`FlightRig.glide_boost`): -1 climbs (Shift + S), 1 thrusts the way you
## face (Shift with any other key: wings never dash sideways), 0 is the
## ordinary air dash (not gliding).
func _glide_boost_kind() -> int:
	if not flight.is_gliding or flight.glide_boost <= 0.0:
		return 0
	return -1 if cmd.move.y < -0.1 and absf(cmd.move.x) <= absf(cmd.move.y) else 1


## Wings: touching down fast turns into a slide that keeps the speed.
func _slide_landing() -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	if flight.slide_landing_speed <= 0.0 or speed < flight.slide_landing_speed or slide_left > 0.0:
		return
	_slide_dir = Vector3(velocity.x, 0.0, velocity.z) / speed
	_slide_from = speed
	slide_left = slide_time
	_slide_cd = slide_time + slide_cooldown


## How much the air spoils aim: none on the ground or riding, 1 in a
## plain fall, and the rig's `FlightRig.flight_aim` while it flies its own
## way: jets lit and not boosting (jetpack, a little), dashing or skimming
## low (boots, none) or gliding (wings, worse than a fall).
func air_aim() -> float:
	if vehicle != null or airborne_time < 0.15:
		return 0.0
	if flight.is_hovering and not flight.is_boosting:
		return flight.flight_aim
	if flight.is_skating or (flight.is_skimming and flight.skim_band() == 0) \
			or (air_dash_left > 0.0 and flight.graze_window > 0.0):
		return flight.flight_aim
	if flight.is_gliding:
		return flight.flight_aim
	return 1.0


## Wings spread (or just folded) stop a main gun from firing.
func wings_block(weapon: Weapon) -> bool:
	return _wing_stow > 0.0 and weapon is Gun and not (weapon as Gun).is_sidearm


## The bank the wings roll toward, -1 to 1 (positive turns right). The
## wings fly where you look, like a bird (Caleb's call): they bank onto the
## view's heading, easing off as the heading comes round to it so they
## settle without swinging past. A strafe key held rolls them that way
## instead, for a harder turn. Holding free look (`ActorCommand.free_look`)
## the wings fly straight on and only the strafe keys turn them, so the view
## can look round and aim anywhere.
func glide_steer(heading: Vector3, yaw_basis: Basis) -> float:
	var strafe := clampf(cmd.move.x, -1.0, 1.0)
	if absf(strafe) > 0.1 or cmd.free_look:
		return strafe
	var off := heading.signed_angle_to(yaw_basis * Vector3.FORWARD, Vector3.UP)
	return -clampf(off / maxf(flight.glide_align_angle, 0.01), -1.0, 1.0)


## How far the glide is tipped, from the forward and back keys: 1 a full
## dive (forward), -1 a full flare (back).
func glide_trim() -> float:
	return clampf(cmd.move.y, -1.0, 1.0)


## A glide flies like a wing: it only ever goes the way it points, and its
## speed is momentum. The wings bank round onto where you look
## (`glide_steer`) and the heading turns with the bank, at up to
## `FlightRig.glide_turn_rate`; forward dives for speed and back pulls up
## (`glide_trim`), never the mouse's pitch. Like an airplane:
## - a turn costs speed (`glide_turn_drag` at full bank), and pulling up in a
##   bank tightens the turn (`glide_pull_turn`) rather than climbing, so it
##   costs more;
## - a banked wing holds you up less, so you sink faster
##   (`glide_bank_sink`, see `_glide_sink`);
## - slow down past the stall speed and the wings stall: they barely turn,
##   you drop at `stall_sink` and pick speed back up only by falling.
## The launch is the one time the wings hand you speed: a glide that starts
## slower than the stall sets off the way you face and is carried up to it.
func _glide_velocity(horizontal: Vector3, _wish: Vector3, yaw_basis: Basis, delta: float) -> Vector3:
	var heading := horizontal.normalized() if horizontal.length() > 1.0 else yaw_basis * Vector3.FORWARD
	var air_speed := horizontal.length()
	var cruise := flight.glide_speed
	var stall := cruise * flight.glide_stall
	# The first spread after leaving the ground is carried all the way to
	# cruise, so the wings bite at once at every tier; a later spread, wings
	# folded and opened again in the air, only up to the stall speed.
	var carry := cruise if _first_spread else stall
	if air_speed >= carry - 0.01:
		_glide_launch = false
	var trim := glide_trim()
	var pull := maxf(0.0, -trim)
	_bank = move_toward(_bank, glide_steer(heading, yaw_basis), flight.glide_bank_rate * delta)
	# Under the stall speed the wings lose their bite fast.
	var authority := pow(clampf(air_speed / maxf(stall, 0.1), flight.stall_authority, 1.0), 2.0)
	heading = heading.rotated(Vector3.UP,
			-_bank * flight.glide_turn_rate * authority * (1.0 + flight.glide_pull_turn * pull) * delta)
	if _glide_launch:
		# The launch: the wings bite and carry you off.
		air_speed = move_toward(air_speed, carry, flight.glide_accel * cruise / FlightRig.GLIDE_REFERENCE * delta)
	elif trim > 0.0:
		var top := cruise * (1.0 + flight.glide_dive_gain * trim)
		air_speed = move_toward(air_speed, top, (flight.glide_dive_accel * trim if air_speed < top else flight.glide_drag) * delta)
		if air_speed < cruise:
			air_speed = move_toward(air_speed, cruise, flight.glide_recover * delta)
	else:
		if velocity.y > 0.0:
			# Height is paid for in speed.
			air_speed -= flight.glide_climb_cost * velocity.y / maxf(air_speed, 1.0) * delta
		# Pulling up never gives speed back: held through a turn, it bleeds
		# away into a stall.
		var hold := cruise * lerpf(1.0, flight.glide_stall, pull)
		# A swoop (pulled up, climbing on a dive's speed past the glide's)
		# pays for its height in the climb's cost alone, not in drag on top
		# (Caleb's call, the style pass); at the glide's speed or under, a
		# pull-up bleeds speed as before.
		var swooping := pull > 0.0 and velocity.y > 0.0 and air_speed > cruise and not flight.is_soaring
		if air_speed > hold and not swooping:
			air_speed = move_toward(air_speed, hold, flight.glide_drag * delta)
		elif pull <= 0.0:
			air_speed = move_toward(air_speed, hold, flight.glide_recover * delta)
		# Stalled, the nose drops and the fall gives speed back, but a wing
		# still pulled up stays stalled: it mushes down well under the stall.
		var floor_speed := stall * (0.6 if pull > 0.0 else 1.0)
		if air_speed < floor_speed:
			air_speed = move_toward(air_speed, floor_speed, flight.stall_recover * delta)
	if not _glide_launch:
		# A turn costs speed, and a tight one, pulled in, costs more.
		air_speed -= flight.glide_turn_drag * absf(_bank) * (1.0 + pull) * delta
	if flight.is_soaring and air_speed < cruise:
		# Soaring: the thrust makes up what turns and climbs cost.
		air_speed = minf(cruise, air_speed + flight.soar_accel * delta)
	return heading * maxf(air_speed, 0.0)


## True while the wings are stalled: too slow to hold you up.
func glide_stalled() -> bool:
	return flight.is_gliding and not _glide_launch \
			and Vector2(velocity.x, velocity.z).length() < flight.glide_speed * flight.glide_stall - 0.5


## The fastest a glide sinks right now: faster in a dive and in a bank, and
## at `stall_sink` once stalled.
func _glide_sink() -> float:
	if flight.stall_sink > 0.0 and glide_stalled():
		return flight.stall_sink
	var trim := glide_trim()
	if flight.is_soaring and trim <= 0.0:
		# Soaring holds the wings level.
		return 0.0
	var sink := lerpf(flight.glide_fall_speed, flight.glide_dive_fall, trim) if trim > 0.0 else flight.glide_fall_speed
	return sink * (1.0 + flight.glide_bank_sink * absf(_bank))


## Starts, carries on, or ends a slide, and returns the ground velocity.
func _simulate_slide(horizontal: Vector3, on_floor: bool, staggered: bool, delta: float) -> Vector3:
	_slide_cd = maxf(0.0, _slide_cd - delta)
	if cmd.slide and on_floor and slide_left <= 0.0 and _slide_cd <= 0.0 and _dash_left <= 0.0 \
			and not staggered and horizontal.length() >= slide_min_speed and spend_stamina(slide_stamina):
		_slide_dir = horizontal.normalized()
		_slide_from = maxf(horizontal.length(), slide_speed * carry_speed * (flight.ground_speed_mult if flight.enabled else 1.0))
		slide_left = slide_time
		_slide_cd = slide_time + slide_cooldown
	if slide_left > 0.0:
		# Jumping, falling off an edge or being staggered ends it; the
		# speed carries on into whatever comes next.
		if cmd.jump_pressed or not on_floor or staggered:
			slide_left = 0.0
		else:
			slide_left = maxf(0.0, slide_left - delta)
			var done := 1.0 - slide_left / slide_time
			horizontal = _slide_dir * lerpf(_slide_from, slide_end_speed, done)
	slide_low = move_toward(slide_low, 1.0 if slide_left > 0.0 else 0.0, crouch_rate * delta)
	return horizontal


func is_sliding() -> bool:
	return slide_left > 0.0


## Crouches or stands from the command, staying down while there is no room
## to stand, and sets the body's height to match.
func _simulate_crouch(delta: float) -> void:
	var want := cmd.crouch and slide_left <= 0.0
	if want:
		if not crouched and slide_low > crouch:
			# Out of a slide into the crouch: no pop up in between.
			crouch = slide_low
		crouched = true
	elif crouched or (slide_left <= 0.0 and slide_low > 0.0):
		if room_to_stand():
			crouched = false
		elif not crouched:
			# A slide that ends under something low ends crouched.
			crouched = true
			crouch = maxf(crouch, slide_low)
	crouch = move_toward(crouch, 1.0 if crouched else 0.0, crouch_rate * delta)
	_fit_body()


## How tall the body stands now: `BODY_HEIGHT` up, `CROUCH_HEIGHT` crouched
## or down in a slide. Hit tests (`Combat.trace`) use the same height.
func body_height() -> float:
	return lerpf(stand_height, CROUCH_HEIGHT, maxf(crouch, slide_low))


## Makes the body `height` tall standing, eyes `eye_drop` under the top.
func set_stand_height(height: float, eye_drop := 0.2) -> void:
	stand_height = height
	eye_height = height - eye_drop
	_fit_body()


## Makes the body `radius` wide (and at least twice that tall).
func set_body_radius(radius: float) -> void:
	body_radius = radius
	if stand_height < radius * 2.0:
		set_stand_height(radius * 2.0)
	if _body_shape != null:
		_body_shape.radius = radius
	_fit_body()


## Whether the full standing body fits where the actor is: nothing of the
## world in the way overhead.
func room_to_stand() -> bool:
	if not is_inside_tree():
		return true
	var lift := 0.05
	var shape := CapsuleShape3D.new()
	shape.radius = BODY_RADIUS * 0.9
	shape.height = BODY_HEIGHT - lift
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, global_position + Vector3.UP * (lift + shape.height * 0.5))
	query.collision_mask = LAYER_WORLD
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


## Steadier aim while crouched on the ground: guns spread this many times
## as wide (`Gun.current_spread_deg`).
func aim_steadiness() -> float:
	if not crouched or not is_on_floor():
		return 1.0
	return lerpf(1.0, crouch_spread_mult, crouch)


## Keeps the collision capsule as tall as `body_height`, feet on the ground.
func _fit_body() -> void:
	if _body_shape == null:
		return
	var height := body_height()
	height = maxf(height, body_radius * 2.0)
	if is_equal_approx(_body_shape.height, height):
		return
	_body_shape.height = height
	_body_col.position.y = height * 0.5


func _simulate_weapons(delta: float) -> void:
	sprint_recover = maxf(0.0, sprint_recover - delta)
	_reload_ask = reload_buffer if cmd.reload_pressed else maxf(0.0, _reload_ask - delta)
	for w in weapons:
		w.tick(delta)
	if flight.glide_sidearm_only and flight.is_gliding:
		_wing_stow = flight.glide_stow_time
	else:
		_wing_stow = maxf(0.0, _wing_stow - delta)
	_tick_store(delta)
	var drew_on_pull := false
	var switch_to := cmd.switch_weapon
	if switch_to == ActorCommand.HOLSTER:
		switch_to = -1 if active_weapon_index >= 0 else -2
	# Weapons come out only where they are free (Caleb's call): while locked
	# (a safe zone, a gate outpost, the base off the range) a weapon in hand
	# is put away and nothing can be drawn.
	if weapons_locked or crate != null:
		if active_weapon_index >= 0 and _storing == null:
			_draw_weapon(-1)
		switch_to = -2
	elif cmd.primary and cmd.switch_weapon == -1 and active_weapon_index < 0 and _storing == null \
			and last_drawn >= 0 and last_drawn < weapons.size() and toy_in_hand == "":
		# Empty hands and a pull of the trigger: the weapon last held comes
		# out. That pull only draws it.
		_draw_weapon(last_drawn)
		drew_on_pull = true
	if guns_locked and switch_to >= 0 and switch_to < weapons.size() and weapons[switch_to] is Gun:
		switch_to = -2
	if cmd.switch_weapon != -1 and switch_to >= -1 and switch_to < weapons.size() \
			and switch_to != active_weapon_index and _storing == null:
		_draw_weapon(switch_to)
	if guns_locked and get_active_weapon() is Gun and _storing == null:
		_draw_weapon(blade_index())
	_swap_primary_and_heavy()
	materialize_left = maxf(0.0, materialize_left - delta)
	var weapon := get_active_weapon()
	if weapon and heal_time_left <= 0.0 and stagger_left <= 0.0 and not weapons_locked and not drew_on_pull \
			and not visor.is_zoomed() and materialize_left <= 0.0 and _storing == null and not dodging():
		# A gun run dry stays in hand (the visor prompts a reload,
		# `Hud.reload_prompt`); only the player switches weapons. A reload press made while the gun
		# could not take it (drawing, healing, staggered) is kept a moment.
		var gun := weapon as Gun
		if gun and _reload_ask > 0.0:
			gun.start_reload()
			_reload_ask = 0.0
		if not wings_block(weapon):
			weapon.handle_input(cmd, delta)
		else:
			weapon.drop_aim()
		# A power weapon with nothing left is thrown away. The authority
		# decides; a client hears it through `power_changed`.
		if gun and gun.is_power() and gun.is_spent() and Combat.authoritative:
			notice.emit("%s spent" % gun.display_name)
			Loadout.set_power(self, "")
	elif weapon:
		weapon.drop_aim()


## See `primary_in_watch`.
func _swap_primary_and_heavy() -> void:
	var held := get_active_weapon() as Gun
	if held == null:
		return
	if held.is_power():
		primary_in_watch = true
	elif primary_in_watch and not held.is_sidearm:
		primary_in_watch = false
		materialize_time = Loadout.summon_time(held.item_id)
		materialize_left = materialize_time


## Index of the melee weapon worn, or -1.
func blade_index() -> int:
	for i in weapons.size():
		if weapons[i] is MeleeWeapon:
			return i
	return -1


## Takes out the weapon at `index`, or puts the one in hand away with -1.
## The weapon dematerializing back into the pack (the watch's store), or null.
func storing_weapon() -> Weapon:
	return _storing if _storing != null and is_instance_valid(_storing) else null


## Starts weapon `weapon` dematerializing out of the hand over `time`
## seconds (`Loadout.store_weapon`). Once it has, it is taken away and the
## hands are empty.
func begin_store(weapon: Weapon, time: float) -> void:
	_storing = weapon
	dematerialize_time = maxf(time, 0.01)
	dematerialize_left = dematerialize_time


func _tick_store(delta: float) -> void:
	if _storing == null:
		return
	if not is_instance_valid(_storing):
		_storing = null
		dematerialize_left = 0.0
		return
	dematerialize_left = maxf(0.0, dematerialize_left - delta)
	if dematerialize_left > 0.0:
		return
	var index := weapons.find(_storing)
	var was_held := index >= 0 and index == active_weapon_index
	_storing = null
	if index < 0:
		return
	remove_weapon(index)
	if was_held:
		# Put away, not swapped: the hands are empty, and the holster key
		# draws the first weapon still worn.
		var order := slot_order()
		active_weapon_index = -1
		last_drawn = order[0] if not order.is_empty() else 0
		_refresh_weapon_visuals()


func _draw_weapon(index: int) -> void:
	var old := get_active_weapon()
	if old:
		old.on_holster()
		last_drawn = active_weapon_index
	active_weapon_index = index
	# What was still materializing stays behind with its hand: the weapon
	# drawn instead is ready at once, unless it materializes itself below.
	if get_active_weapon() != old:
		materialize_left = 0.0
	# A heavy weapon drawn out of the watch's chamber materializes first, the
	# same on every machine, since it follows the switch in the command.
	var heavy := get_active_weapon()
	if heavy != null and heavy != old and heavy.item_id != "" and ItemDB.has_tag(heavy.item_id, "power"):
		materialize_time = Loadout.summon_time(heavy.item_id)
		materialize_left = materialize_time
	_refresh_weapon_visuals()


func _simulate_heal(delta: float) -> void:
	if cmd.heal_pressed and heal_time_left <= 0.0 and health.health < health.max_health:
		var item := inventory.first_with_tag("heal")
		if item != "":
			_healing_with = item
			heal_time_left = heal_duration
			notice.emit("Using %s..." % ItemDB.item_name(item))
	if heal_time_left > 0.0:
		heal_time_left -= delta
		if heal_time_left <= 0.0 and inventory.remove_item(_healing_with):
			health.heal(ItemDB.item_stats(_healing_with).get("heal", heal_amount))
			notice.emit("Healed")


func get_eye_position() -> Vector3:
	return global_position + Vector3(0.0, eye_height - maxf(slide_eye_drop * slide_low, crouch_eye_drop * crouch), 0.0)


func get_aim_dir() -> Vector3:
	if cmd.aim_dir.length_squared() > 0.0001:
		return cmd.aim_dir.normalized()
	return Basis.from_euler(Vector3(cmd.pitch, cmd.yaw, 0.0)) * Vector3.FORWARD


## Weapon indices in key order: primary (1), sidearm (2), melee (3), then any
## special weapon. The number keys and the mouse wheel both use this, so the
## order never depends on how the loadout was equipped. A heavy (power)
## weapon is not in it: it waits in the watch's heavy chamber and is drawn
## only from the watch (Caleb's call, DESIGN.md section 6).
func slot_order() -> Array[int]:
	var order: Array[int] = []
	for rank in 3:
		for i in weapons.size():
			if _slot_rank(weapons[i]) == rank:
				order.append(i)
	return order


## The weapon index on number key `key` (1 to 4), or -1 if that slot is empty.
func weapon_for_key(key: int) -> int:
	var order := slot_order()
	return order[key - 1] if key >= 1 and key <= order.size() else -1


## The next (step 1) or previous (step -1) weapon index in key order, wrapping.
func cycle_weapon_index(step: int) -> int:
	var order := slot_order()
	if order.size() < 2:
		return active_weapon_index
	# Holstered: step from the weapon last drawn.
	var at := order.find(active_weapon_index if get_active_weapon() else last_drawn)
	return order[posmod(maxi(at, 0) + step, order.size())]


static func _slot_rank(w: Weapon) -> int:
	# Power weapons are guns too, but they wait in the watch's chamber.
	if w.item_id != "" and ItemDB.has_tag(w.item_id, "power"):
		return 3
	if w is Gun:
		return 1 if w.is_sidearm else 0
	if w is MeleeWeapon:
		return 2
	return 3


func get_active_weapon() -> Weapon:
	if active_weapon_index >= 0 and active_weapon_index < weapons.size():
		return weapons[active_weapon_index]
	return null


func equip_weapon(weapon: Weapon) -> void:
	weapon.actor = self
	weapons.append(weapon)
	_watch_attacks(weapon)
	add_child(weapon)
	weapon.visual = weapon.build_visual()
	if weapon.visual:
		hand.add_child(weapon.visual)
	_refresh_weapon_visuals()
	mark_carry()


## Shots and swings break a cloak (`Artifact.on_attack`).
func _watch_attacks(weapon: Weapon) -> void:
	var gun := weapon as Gun
	if gun:
		gun.fired.connect(func(_from: Vector3, _to: Vector3) -> void: artifact.on_attack())
	var blade := weapon as MeleeWeapon
	if blade:
		blade.swung.connect(func(_kind: String) -> void: artifact.on_attack())


## True while an artifact's Phase Cloak hides this actor.
func is_cloaked() -> bool:
	return artifact.is_cloaked()


## Puts `weapon` where the weapon at `index` was, freeing the old one. Used
## when a power weapon is swapped in or out mid-raid. Weapon indices keep
## their meaning, so switching weapons still picks the same slots.
func replace_weapon(index: int, weapon: Weapon) -> void:
	if index < 0 or index >= weapons.size():
		equip_weapon(weapon)
		return
	var old := weapons[index]
	if index == active_weapon_index:
		old.on_holster()
	if old.visual and is_instance_valid(old.visual):
		old.visual.queue_free()
	old.queue_free()
	weapon.actor = self
	weapons[index] = weapon
	_watch_attacks(weapon)
	add_child(weapon)
	weapon.visual = weapon.build_visual()
	if weapon.visual:
		hand.add_child(weapon.visual)
	_refresh_weapon_visuals()
	mark_carry()


## Takes out the weapon at `index` (the power slot uses this when a power
## weapon is picked up).
func draw_weapon(index: int) -> void:
	if index != active_weapon_index:
		_draw_weapon(index)


## Takes the weapon at `index` away for good (a spent power weapon). The
## active and last-drawn indices are kept pointing at the same weapons; if
## the weapon was in hand, the first weapon is drawn instead.
func remove_weapon(index: int) -> void:
	if index < 0 or index >= weapons.size():
		return
	var old := weapons[index]
	if index == active_weapon_index:
		old.on_holster()
		active_weapon_index = 0 if weapons.size() > 1 else -1
	elif active_weapon_index > index:
		active_weapon_index -= 1
	if last_drawn == index:
		last_drawn = 0
	elif last_drawn > index:
		last_drawn -= 1
	weapons.remove_at(index)
	if old.visual and is_instance_valid(old.visual):
		old.visual.queue_free()
	old.queue_free()
	_refresh_weapon_visuals()
	mark_carry()


func _refresh_weapon_visuals() -> void:
	for i in weapons.size():
		if weapons[i].visual:
			weapons[i].visual.visible = i == active_weapon_index


func add_impulse(impulse: Vector3) -> void:
	velocity += impulse


## Returns the interactable the actor is looking at, or null.
func find_interactable() -> Interactable:
	if not is_inside_tree():
		return null
	var from := get_eye_position()
	var to := from + get_aim_dir() * interact_range
	var query := PhysicsRayQueryParameters3D.create(from, to, LAYER_WORLD | LAYER_INTERACT)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	return hit.collider as Interactable


## Shows or removes the airborne sign-out column. The mesh is marked so a
## Phase Cloak leaves it solid (`ActorSkin._update_cloak`).
func set_sign_out_beacon(on: bool) -> void:
	if sign_out_beacon == on:
		return
	sign_out_beacon = on
	var column := get_node_or_null("SignOutBeacon")
	if not on:
		if column != null:
			# Drop it now. queue_free would leave the column up for the rest
			# of the frame, which is long enough to still be "there".
			column.free()
		return
	_beacon_hum = 0.0
	column = Node3D.new()
	column.name = "SignOutBeacon"
	_add_beacon_beam(column, 0.45, 0.28, Color(1.0, 0.55, 0.12, 0.55), Color(1.0, 0.48, 0.08), 2.0)
	_add_beacon_beam(column, 0.08, 0.08, Color(1.0, 0.95, 0.8, 0.9), Color(1.0, 0.92, 0.7), 3.0)
	add_child(column)


func _add_beacon_beam(column: Node3D, bottom: float, top: float, color: Color, emission: Color, energy: float) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = 80.0
	mesh.radial_segments = 8
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = emission
	mat.emission_energy_multiplier = energy
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material = mat
	var beam := MeshInstance3D.new()
	beam.mesh = mesh
	beam.position.y = 40.0
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.set_meta("uncloaked", true)
	if column.get_child_count() == 0:
		column.set_meta("beam_mat", mat)
	column.add_child(beam)


## Pulses the column and plays its tone. Headless play is silent.
func _pulse_sign_out_beacon(delta: float) -> void:
	if not sign_out_beacon:
		return
	var column := get_node_or_null("SignOutBeacon") as Node3D
	if column != null and column.has_meta("beam_mat"):
		var mat: StandardMaterial3D = column.get_meta("beam_mat")
		mat.albedo_color.a = 0.4 + 0.45 * absf(sin(Time.get_ticks_msec() * 0.006))
	_beacon_hum -= delta
	if _beacon_hum > 0.0:
		return
	_beacon_hum = 1.6
	var stream := Sfx.get_stream("beacon")
	if stream == null:
		return
	var tone := AudioStreamPlayer3D.new()
	tone.stream = stream
	tone.unit_size = 28.0
	tone.max_distance = 160.0
	tone.volume_db = 2.0
	add_child(tone)
	tone.finished.connect(tone.queue_free)
	tone.play()


## What this body carries, in kg (`CarryLoad`), up to date.
func carry_kg() -> float:
	refresh_carry()
	return _carry_kg


## What it carries changed (gear worn or taken off, the pack), so the load is
## worked out again before it next moves.
func mark_carry() -> void:
	_carry_dirty = true


## Works the load and what it does out again if what is carried changed.
## The flight rig's heat follows too (`FlightRig.load_heat`).
func refresh_carry() -> void:
	if not _carry_dirty:
		return
	_carry_dirty = false
	var kg := carry_sent if carry_sent >= 0.0 else CarryLoad.of_actor(self)
	carry_speed = CarryLoad.speed_mult(kg)
	carry_accel = CarryLoad.accel_mult(kg)
	carry_jump = CarryLoad.jump_mult(kg)
	flight.load_heat = CarryLoad.heat_mult(kg, flight.heavy_lift)
	if _carry_known and kg == _carry_kg:
		return
	_carry_known = true
	_carry_kg = kg
	carry_changed.emit(kg)


## Everything this actor would drop on death.
func get_drop_items() -> Array[String]:
	var out: Array[String] = []
	out.append_array(gear_items)
	out.append_array(inventory.items)
	return out


func kill(kind: String, source: Node = null) -> void:
	# Nothing keeps an actor alive through this, not even an arena's yield rule.
	health.min_health = 0.0
	var info := DamageInfo.new()
	info.amount = 999999.0
	info.kind = kind
	info.source = source
	health.apply_damage(info)


func _on_health_damaged(_info: DamageInfo) -> void:
	_flash()
	if heal_time_left > 0.0:
		heal_time_left = 0.0
		notice.emit("Heal interrupted")


## A brief white flash so every hit is visible.
func _flash() -> void:
	if body_mesh == null or DisplayServer.get_name() == "headless":
		return
	if _flash_left <= 0.0:
		_base_material = body_mesh.material_override
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 1, 1)
	body_mesh.material_override = mat
	_flash_left = 0.07


func _on_health_died(info: DamageInfo) -> void:
	is_dead = true
	set_sign_out_beacon(false)
	if _flash_left > 0.0 and body_mesh:
		body_mesh.material_override = _base_material
	collision_layer = 0
	velocity = Vector3.ZERO
	hand.visible = false
	if body_mesh:
		body_mesh.rotation.x = -PI / 2.0
		body_mesh.position.y = 0.4
	died.emit(self, info)
