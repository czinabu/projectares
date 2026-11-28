class_name BotBrain
extends Node3D
## Drives a bot Actor by writing its ActorCommand, exactly like a player does.
## Patrols, chases what it sees or what shot it, and fights with its weapon.

enum State { PATROL, CHASE, ATTACK }

var seed_value := 0
var sight_range := 38.0
var close_sense_range := 9.0
var fov_deg := 140.0
var attack_range := 28.0
## How far a bot on a vehicle's mounted gun opens fire (`_gun_reach`).
const MOUNTED_REACH := 45.0
var preferred_range := 14.0
var reaction_time := 0.7
## Melee only: how far off the chest a swing is aimed, per metre.
var aim_error := 0.05
var burst_time := 0.6
var burst_pause := 0.7
var patrol_radius := 22.0
var give_up_time := 7.0
## Further than this beyond its patrol, a bot runs back to its post.
var march_distance := 12.0
## How far the place a bot is heading for must move before it plans a new path.
var repath_distance := 1.5
## Chance that a melee bot reads an incoming swing and raises its guard to
## meet it (`guard_reaction` after it shows: a timed block, or a parry
## against a slow heavy). Guards turn to the swing by themselves; a bot,
## like a person, pays for a guard held up (`MeleeWeapon.hold_drain`).
var guard_skill := 0.4
## Scales the pause between swings. A world sets `melee_tempo` on the bot
## (a heavy that should land more than one swing in the time a gun takes to
## answer). 1 is the default cadence.
var melee_tempo := 1.0
var guard_reaction := 0.22
## A guard read in time goes up this long before the swing lands, as a
## person times it: inside `MeleeWeapon.timed_window`, give or take
## `guard_lead_jitter`, so a long heavy is not met by a guard held up (and
## drained) through its whole windup.
var guard_lead := 0.28
var guard_lead_jitter := 0.08
## Melee bots fight like people (DESIGN.md "Melee bots"): a share of their
## attacks are held heavies (more against a raised guard, which a heavy
## breaks), some charges are feints that hang on the charge to draw an
## early guard and then release as a light, a sprinting bot opens with a dash-strike from out of reach, and a
## bot strikes at once into a foe's recovery, stagger or its own riposte.
## Heavies, feints and dash-strikes come with the ring (`RING_HEAVY`,
## `RING_FEINT`, `RING_DASH`): the outer ring never dash-strikes.
const RING_FEINT := [0.0, 0.15, 0.3]
const RING_DASH := [0.0, 0.4, 0.7]
const RING_HEAVY := [0.05, 0.2, 0.3]
## The rest of a person's melee (DESIGN.md "Melee"): against a raised guard
## a bot kicks it open (`RING_KICK`), some of its heavies are feints it lets
## go into a guard part way (`RING_HEAVY_FEINT`), and a heavy it reads
## coming it may dodge instead of guarding (`RING_DODGE`).
const RING_KICK := [0.0, 0.25, 0.4]
const RING_HEAVY_FEINT := [0.0, 0.15, 0.3]
const RING_DODGE := [0.0, 0.15, 0.3]
var kick_chance := 0.25
## A weapon ability (`MeleeWeapon.weapon_ability`) is used when it is ready
## and the fight calls for it (`_wants_ability`): the hammer's pound when two
## foes stand in its ring, with one now and then (`pound_alone_chance`); the
## knife's shadow step and the hook blade's trip now and then
## (`ability_chance`); the sword's counter stance into a swing coming; the
## axe's hook into a raised guard. Bots do not vault.
var pound_alone_chance := 0.15
var ability_chance := 0.35
var heavy_feint_chance := 0.15
var melee_dodge_chance := 0.15
## A blade in reach beats a rifle (Caleb's call): an army bot cut by a
## blade flinches, its gun knocked `melee_knock_deg` off and its trigger
## held for `melee_flinch` seconds, so once a blade reaches a soldier the
## gun loses. Bots only: a player's aim is never moved.
var melee_flinch := 0.4
## An army gunner gives ground from a blade closer than this, from the hip.
var blade_backoff := 9.0
var melee_knock_deg := 14.0
var heavy_share := 0.25
var heavy_vs_guard := 0.6
var feint_chance := 0.15
var dash_chance := 0.6
## The least time between dash-strike tries, seconds.
var dash_every := 3.0
## How long a feint hangs on its charge before it lets go, seconds
## (under `MeleeWeapon.hold_time`, so the release is a light).
var feint_show := 0.15

## Gun aim. Bots aim like people, not like an aimbot: they turn onto a target
## at a limited speed, trail it while it moves, and their aim wanders by an
## angle that starts wide on first sight and settles while they hold it in
## view. Moving, airborne and distant targets are harder to hit.
## 0 is a rookie, 1 a veteran. Below 0, each bot rolls its own from its seed.
var skill := -1.0
## The range a bot rolls its skill from when `skill` is below 0. The `Raid`
## sets it from `WorldDef.bot_skill_range` (risk zones, warlords).
var skill_range := Vector2(0.25, 0.75)
## Turn speed onto the target, degrees a second (at skill 0.5).
var turn_speed_deg := 200.0
## Seconds the aim trails a moving target (at skill 0.5).
var track_lag := 0.22
## Settled aim wander, degrees (at skill 0.5). Wide enough that a rookie
## misses a runner, tight enough that a settled shot at rifle range can hit.
var aim_error_deg := 1.55
## The wander on first sight is this many times the settled one...
var settle_mult := 3.0
## ...and settles over this long in view.
var settle_time := 2.5
## Extra wander when the target is in the air, and per metre past
## `preferred_range`, degrees.
var air_error_deg := 3.0
var far_error_deg := 0.08
## Extra wander while the bot itself is moving, degrees.
var self_move_error_deg := 0.65
## Fires only when its aim is within this of where it means to aim, degrees.
var fire_cone_deg := 6.0

## Rival raiders (see `Raid._tick_raiders`). The `Raid` sends one on errands
## with `go_to` (a cache to loot) and has it `holding` still while it signs
## out; fights come first either way. `flies` lets it use its flight rig:
## jets or a kick over whatever it is stuck on, and a jetpack wearer takes
## to the air in a gunfight, hovering on held aim like a player.
var flies := false
## Seconds between a flier's hops in a gunfight, and how long one lasts, the
## first `combat_climb` of it climbing.
var combat_hop_every := Vector2(5.0, 10.0)
var combat_hop_time := 2.4
var combat_climb := 0.8
## A flier stuck this long, pushing against something, lifts off for
## `unstick_lift` seconds.
var stuck_time := 0.8
var unstick_lift := 1.2
## Below this heat (of the rig's 100) a flier starts a hop.
var hop_heat := 40.0
## A bot that wears a player's kit (a raider) looks after it the way a
## player does: back to the primary and a fresh mag between fights, the
## blade once every gun is dry, and a heal from its pack when hurt.
var uses_kit := false
## Below this share of its health it heals between fights...
var heal_below := 0.7
## ...and in a fight too, once this low and with nobody close.
var heal_desperate := 0.3
var heal_clear_range := 12.0
var holding := false
var errand := Vector3.ZERO
var has_errand := false

var state := State.PATROL
var actor: Actor
var target: Actor

var _nav: NavigationAgent3D
var _rng := RandomNumberGenerator.new()
var _home := Vector3.ZERO
var _dest := Vector3.ZERO
var _has_dest := false
var _last_seen := Vector3.ZERO
var _lost_time := 0.0
var _think_left := 0.0
var _repath_left := 0.0
var _path_to := Vector3.ZERO
## Where the path really ends: `_path_to` moved onto the walkable ground
## (`_onto_nav`), so a goal over a drop (a patrol point past a mesa's edge)
## is walked to the edge's nearest walkable point, not off it.
var _nav_goal := Vector3.ZERO
## How near the walkable end of its path a walking bot stops (metres).
const ARRIVE_STOP := 0.6
## New paths asked for in one physics tick, by every bot in the process. A
## path costs in proportion to the whole navigation mesh, not the path's
## length (the Dune Sea's: about 4 ms each), so several in one tick were a
## hitch; a bot over the budget asks again next tick and walks straight
## meanwhile.
const PATHS_PER_TICK := 2
static var _path_tick := -1
static var _paths_this_tick := 0
var _has_path := false
var _wait_left := 0.0
var _seen_time := 0.0
var _burst_left := 0.0
var _pause_left := 0.0
var _error := Vector3.ZERO
var _error_left := 0.0
var _strafe_sign := 1.0
var _strafe_left := 0.0
var _melee_wait := 0.0
## A charge in progress: hold the attack button this much longer, then
## let go (a heavy turns by itself past `hold_time`).
var _hold_left := 0.0
## The heavy under way is a feint: let it go into a guard part way.
var _feint_heavy := false
var _kick_seen := false
var _kick_answer := false
## This read's `guard_lead`, jittered.
var _lead_now := 0.28
var _dash_wait := 0.0
var _flinch_left := 0.0
## Recoil reaches a bot's aim too (`Gun.recoil_for`): it pulls against
## `recoil_control` of each kick, from `RECOIL_CONTROL` by skill, so a
## rookie's long burst climbs off target and a veteran's holds.
const RECOIL_CONTROL := Vector2(0.55, 0.9)
const RECOIL_SETTLE_DELAY := 0.1
const RECOIL_SETTLE := 9.0
var _recoil_gun: Gun
var _recoil_seen := 0
## The climb (up, right; degrees) the bot's aim is off by from recoil.
var _recoil := Vector2.ZERO
var _recoil_rest := 0.0
var _guard_delay := 0.0
## Counting down to raising the guard against a swing read in time; below
## zero, nothing to raise for.
var _read_left := -1.0
var _threat_seen := false
var _aim := Vector3.ZERO
var _aim_target: Actor
var _reaction := 0.0
var _wander := Vector2.ZERO
var _wander_goal := Vector2.ZERO
var _wander_left := 0.0
var _lag := 0.0
var _on_target := false
## A gun that must hold a lock before it fires (a walker's cannon): seconds
## the aim has to stay on a target it can see, from the actor's meta
## "lock_time" (0 for none). Breaking the line of sight starts it over.
var lock_time := 0.0
## A pack hunter's ways (DESIGN.md "The enemy AI pass"), set by a world with
## metas: "tracker" follows fresh tracks within that many metres (a trail of
## places, never where someone is now, through `_sensed`), "preys_on_cold"
## goes first for someone shivering, and "shuns_warmth" never fights anyone
## standing in a heater's or a beacon's warmth, nor walks into one.
var tracker_range := 0.0
var preys_on_cold := false
var shuns_warmth := false
## Checks each step stays on walkable ground (its world's meta "edge_guard":
## the Rift's mesas over lava). A step that would leave the navmesh slides
## along its edge instead.
var edge_guard := false
## How far ahead a guarded step looks, and how far off the navmesh counts
## as stepping off.
const EDGE_LOOK := 0.9
const EDGE_OFF := 0.35
## Seconds a track stays fresh enough to follow, and how often a tracker
## looks at the ground.
var track_fresh := 40.0
var sniff_every := 1.0
var _sniff_left := 0.0
var _trail_id := 0
## Group fights (DESIGN.md "Group fights", Caleb's call): a person (a
## player, or a bot that plays like one) is shot at by only `attack_slots`
## army bots at a time. The rest hold off, take cover or work round the
## flank until a slot comes free; slots are held a few seconds
## (`token_hold`) and pass along with a beat between (`token_beat`). A bot
## always shoots back at whoever hit it in the last `return_fire_time`
## seconds, and at anyone inside `point_blank`. Set from the bot's ring
## ("zone" meta): `RING_SLOTS`.
const RING_SLOTS := [1, 2, 3]
var attack_slots := 2
var token_hold := Vector2(2.5, 4.0)
var token_beat := 0.5
var return_fire_time := 2.0
var point_blank := 7.0
## A kind that keeps its turn even when hit (meta "holds_turn", Frostline's
## Wardens): return fire no longer skips the queue, so a post that is shot
## at still opens up one at a time; only `point_blank` does.
var holds_turn := false
## Bots on the outer ring hold their cover; further in they also flank.
var flanks := true
## How many bots work round one person's flank at once: one, or two for a
## pincer from both sides (meta "flankers").
var flankers := 1
## A target further off is spotted more slowly: the reaction time grows
## to this many times its near value at the edge of sight, and a crouched
## target takes `crouch_notice_mult` longer still.
var far_notice_mult := 1.6
var crouch_notice_mult := 1.3

## Senses and squads (DESIGN.md "Enemy senses and squads"). A bot reacts
## only to what it senses: what it sees, a person's noise it hears (shots,
## `Combat.noise`; footsteps, jets and engines, `noise_of`), a hit, or a
## squadmate's callout. Whatever it learns is a place and a moment, never
## live tracking: once it loses sight it searches from there.
##
## Only `RING_HUNTERS` army bots (by ring) may leave their ground to close
## on, chase or search for one person (`SquadBoard.hunt`); the rest fight
## from where they stand, so a person never pulls a whole army along.
const RING_HUNTERS := [3, 4, 5]
var max_hunters := 4
## How far past its patrol radius a bot follows anything before it turns
## back to its post (a bot that plays like a person, or on an errand, roams).
var leash := 35.0
## An ambusher ("lies_low", the marsh's lurkers): with nothing to fight it
## goes back to its post and lies there crouched and still, never patrols,
## so it is where it was left when someone comes close.
var lies_low := false
## A kind a storm makes bolder ("storm_bold", the Dune Sea's burrowers, who
## hunt by the tremor of feet through the sand): where everyone else's
## sight shrinks in a storm, its sight and its leash grow by this share of
## the storm's strength where it stands (`storm_boost`).
var storm_bold := 0.0
var storm_boost := 1.0
## A keeper that dives is held under the water by the `Raid` (`_tick_dive`):
## it crouches and does nothing else until let up, then stands still
## (`held_still`) while it rises.
var held_under := false
var held_still := false
## The ground it fights on (the enemy AI pass, step 4): its kind and how
## much slower it is to notice someone there. `set_ground` sets both.
var ground := ""
var ground_notice := 1.0
var _base_ground := {}
var _own_patrol := -1.0
## How many bots go to look at one person's noise; the rest turn to face it.
var noise_lookers := 3
## A person sprinting is heard this far off (through walls too), a jog
## closer; walking or crouched is silent. Jets and engines carry further.
const STEP_SPRINT := 16.0
const STEP_JOG := 7.0
const ENGINE_HEARD := 40.0
## The furthest anything is heard from (a jetpack at work, `FlightRig.noise`):
## how far a listening bot looks round for noise at all.
const LOUDEST_HEARD := 60.0
## Seconds an alerted bot faces a sound it is not going to look at.
var alert_time := 4.0
## A callout: a bot that spots a person tells its faction within this range
## where the person is now, at most every `callout_every` seconds.
var callout_range := 30.0
var callout_every := 4.0
## The bot's fireteam (`WarCommander`, 0 for none): a callout reaches its
## own team out to `team_range`.
var team := 0
var team_range := 60.0
## A person seen at the same distance as an enemy soldier is the second
## choice by this much: an army fights the other army first.
var person_bias := 1.3
## Searching: points looked at round the last sighting after reaching it.
var search_points := 2
var search_spread := 8.0
## The bot whose turn it is keeps shooting at the cover a person ducked
## behind for this long (it pins them; the round still has to reach them).
var suppress_time := 2.5
var suppress_spread_deg := 2.5
## Below this share of its health a soldier falls back to its post and only
## fights back when pressed (heavier kinds stand their ground).
var fall_back_below := 0.35
## A fireteam that has lost this share of itself breaks off: each of the
## rest falls back to its post for `break_time` (meta "breaks_at"; 0 never).
## Losses count from when it joined the team (`set_team`, `ally_down`).
var breaks_at := 0.0
var break_time := 12.0
var team_size := 0
var _allies_lost := 0
var _broken_left := 0.0
## Seconds a bot runs from a grenade or rocket about to burst near it, and
## its chance to notice one, from its lowest skill to its highest.
var dodge_time := 1.0
var dodge_chance := Vector2(0.45, 0.9)

## Who holds a slot on each person, by the person's instance id:
## {"holders": {brain id: physics frame it lets go}, "free_at": frame}.
static var _slots := {}
## Off lets every bot shoot at once (the group bench's `--slots off`, to
## compare); always on in play.
static var ration_attacks := true
var _rest_until := 0
var _hit_by: Actor
var _hit_at := -1000000
var _cover := Vector3.INF
var _cover_left := 0.0
var _lock := 0.0
var _stuck_for := 0.0
var _lift_left := 0.0
var _side_left := 0.0
var _climb_for := 0.0
var _climb_from := Vector3.ZERO
var _hop_in := 3.0
var _hop_left := 0.0
var _contact_id := 0
var _contact_person := false
var _last_vel := Vector3.ZERO
var _hunting := false
var _search: Array[Vector3] = []
var _search_slow := 0.0
var _suppress_left := 0.0
var _alert_left := 0.0
var _alert_at := Vector3.ZERO
var _heard_at := Vector3.INF
var _heard_from: Actor
var _called_at := -1000.0
var _called := false
var _falling_back := false
var _dodge_left := 0.0
var _dodge_from := Vector3.ZERO
var _danger_seen := {}


func _ready() -> void:
	actor = get_parent() as Actor
	process_physics_priority = -5
	_rng.seed = seed_value
	_nav = NavigationAgent3D.new()
	_nav.path_desired_distance = 1.0
	_nav.target_desired_distance = 1.5
	add_child(_nav)
	_home = actor.global_position
	actor.cmd.yaw = _rng.randf_range(-PI, PI)
	# Not every bot thinks on the same tick.
	_think_left = _rng.randf() * 0.2
	if skill < 0.0:
		skill = _rng.randf_range(skill_range.x, skill_range.y)
	if actor.has_meta("melee_tempo"):
		melee_tempo = float(actor.get_meta("melee_tempo"))
	# A world may give a body its own aim: a heavy machine that comes round
	# slowly ("aim_turn", degrees a second) but leads a moving or flying
	# target well ("track_lag", "air_error", see the aim tuning above).
	if actor.has_meta("aim_turn"):
		turn_speed_deg = float(actor.get_meta("aim_turn"))
	if actor.has_meta("track_lag"):
		track_lag = float(actor.get_meta("track_lag"))
	if actor.has_meta("air_error"):
		air_error_deg = float(actor.get_meta("air_error"))
	lock_time = float(actor.get_meta("lock_time", 0.0))
	# A world may give a kind its own senses (the enemy AI pass): how far it
	# sees ("sight", metres), how wide ("fov", degrees), how far it fights
	# from ("reach", metres) and how much slower it notices someone at the
	# edge of its sight ("far_notice"). A long eye still notices slowly out
	# there, so a scope keeps the first shot.
	if actor.has_meta("sight"):
		sight_range = float(actor.get_meta("sight"))
	if actor.has_meta("fov"):
		fov_deg = float(actor.get_meta("fov"))
	if actor.has_meta("reach"):
		attack_range = float(actor.get_meta("reach"))
	if actor.has_meta("far_notice"):
		far_notice_mult = float(actor.get_meta("far_notice"))
	# How it fires ("burst": seconds on the trigger, seconds off): a slow,
	# steady gun keeps its trigger down longer than a rifle's short bursts.
	# How it fights a doctrine (the enemy AI pass, step 3): the distance it
	# keeps ("range"), how badly hurt before it falls back ("fall_back"),
	# how many more of it may hunt one person ("hunters", added to the
	# ring's), a pincer ("flankers") and when its team breaks ("breaks_at").
	if actor.has_meta("range"):
		preferred_range = float(actor.get_meta("range"))
	if actor.has_meta("fall_back"):
		fall_back_below = float(actor.get_meta("fall_back"))
	flankers = int(actor.get_meta("flankers", 1))
	breaks_at = float(actor.get_meta("breaks_at", 0.0))
	if actor.has_meta("burst"):
		var burst: Vector2 = actor.get_meta("burst")
		burst_time = burst.x
		burst_pause = burst.y
	tracker_range = float(actor.get_meta("tracker", 0.0))
	preys_on_cold = bool(actor.get_meta("preys_on_cold", false))
	shuns_warmth = bool(actor.get_meta("shuns_warmth", false))
	edge_guard = bool(actor.get_meta("edge_guard", false))
	lies_low = bool(actor.get_meta("lies_low", false))
	storm_bold = float(actor.get_meta("storm_bold", 0.0))
	# How far past its ground a kind follows ("leash"): an ambusher that
	# never leaves its pool.
	if actor.has_meta("leash"):
		leash = float(actor.get_meta("leash"))
	var ring := int(actor.get_meta("zone", 1))
	attack_slots = RING_SLOTS[clampi(ring, 0, RING_SLOTS.size() - 1)]
	max_hunters = RING_HUNTERS[clampi(ring, 0, RING_HUNTERS.size() - 1)]
	feint_chance = RING_FEINT[clampi(ring, 0, RING_FEINT.size() - 1)]
	dash_chance = RING_DASH[clampi(ring, 0, RING_DASH.size() - 1)]
	heavy_share = RING_HEAVY[clampi(ring, 0, RING_HEAVY.size() - 1)]
	kick_chance = RING_KICK[clampi(ring, 0, RING_KICK.size() - 1)]
	heavy_feint_chance = RING_HEAVY_FEINT[clampi(ring, 0, RING_HEAVY_FEINT.size() - 1)]
	melee_dodge_chance = RING_DODGE[clampi(ring, 0, RING_DODGE.size() - 1)]
	flanks = ring > 0
	# A world may hold a kind to fewer shooters at one person ("slots").
	if actor.has_meta("slots"):
		attack_slots = int(actor.get_meta("slots"))
	holds_turn = bool(actor.get_meta("holds_turn", false))
	max_hunters += int(actor.get_meta("hunters", 0))
	# A kind that dash-strikes whatever its ring ("dash", a chance).
	if actor.has_meta("dash"):
		dash_chance = float(actor.get_meta("dash"))
	if actor.has_meta("dash_every"):
		dash_every = float(actor.get_meta("dash_every"))
	# A world may make a kind feint more than its ring would ("feint_chance":
	# the marsh's stalkers circle and feint before they strike).
	if actor.has_meta("feint_chance"):
		feint_chance = float(actor.get_meta("feint_chance"))
	actor.health.damaged.connect(_on_damaged)
	actor.heard.connect(_on_heard)


## Sends the bot to hold a place: it walks there and patrols around it from
## then on. Fights along the way still come first.
func post_to(point: Vector3, radius: float) -> void:
	_home = point
	# Never wider than the bot's own round, and a tight post (a line, a
	# siege ring) does not keep it tight at the next one.
	if _own_patrol < 0.0:
		_own_patrol = patrol_radius
	patrol_radius = minf(_own_patrol, maxf(radius * 0.8, 4.0))
	_has_dest = false
	_wait_left = 0.0


## Fights the way its ground asks (`WorldDef.ground_styles`): "range"
## scales the distance it keeps, "hunters" is added to how many may hunt
## one person, "leash" is how far it chases and "notice" scales how long
## it takes to spot someone. Each style is laid over the bot's own numbers,
## never over the last style, so moving ground to ground never drifts.
func set_ground(kind: String, style: Dictionary) -> void:
	if kind == ground:
		return
	if _base_ground.is_empty():
		_base_ground = {"range": preferred_range, "hunters": max_hunters, "leash": leash}
	ground = kind
	preferred_range = float(_base_ground["range"]) * float(style.get("range", 1.0))
	max_hunters = maxi(0, int(_base_ground["hunters"]) + int(style.get("hunters", 0)))
	leash = float(style.get("leash", _base_ground["leash"]))
	ground_notice = float(style.get("notice", 1.0))


## Where the bot is posted.
func home() -> Vector3:
	return _home


## Sends the bot to a place (a raider to a cache). It runs there whenever
## it is not fighting, and stays once it arrives (`at_errand`).
func go_to(point: Vector3) -> void:
	errand = point
	has_errand = true
	holding = false


## Done with its errand: it patrols where it stands until given another.
func clear_errand() -> void:
	has_errand = false
	_home = actor.global_position
	_has_dest = false


func at_errand() -> bool:
	return has_errand and _flat_dist(errand) < 2.2 and absf(errand.y - actor.global_position.y) < 2.5


func _physics_process(delta: float) -> void:
	if actor.is_dead:
		_release()
		return
	# A bot nobody is near thinks only on the ticks its body moves.
	if not actor.ticks_now():
		return
	delta *= actor.tick_every
	var cmd := actor.cmd
	cmd.clear_one_shots()
	cmd.primary = false
	cmd.secondary = false
	cmd.sprint = false
	cmd.jump = false
	cmd.crouch = false
	cmd.move = Vector2.ZERO
	cmd.aim_dir = Vector3.ZERO
	# Held by its keeper's fight (`Raid._tick_dive`): down and still while
	# under, still while it rises.
	if held_under or held_still:
		cmd.crouch = held_under
		return

	_think_left -= delta
	if _think_left <= 0.0:
		_think_left = 0.2
		var had := target
		target = _find_target()
		if target != had and had != null and is_instance_valid(had) and _hunting:
			SquadBoard.stop_hunt(had.get_instance_id(), get_instance_id())
			_hunting = false
		_think_danger()
		if target == null and _heard_at.is_finite() and state != State.ATTACK:
			_on_heard(_heard_at, _heard_from)
		if target == null and tracker_range > 0.0 and state != State.ATTACK:
			_sniff(0.2)
		if not _falling_back and not uses_kit and _stands_ground() == false \
				and actor.health.health < actor.health.max_health * fall_back_below:
			_falling_back = true
		if _broken_left > 0.0:
			_broken_left -= 0.2

	if _dodge_left > 0.0:
		_dodge_left -= delta
		if target and is_instance_valid(target) and not target.is_dead:
			_aim_gun(cmd, actor.get_eye_position(), target.global_position + Vector3(0, 1.1, 0),
					actor.get_eye_position().distance_to(target.global_position), delta)
		_dodge(cmd, delta)
	elif target and is_instance_valid(target) and not target.is_dead:
		if target.get_instance_id() != _contact_id or state != State.ATTACK:
			_new_contact()
		_last_seen = target.global_position
		_last_vel = target.velocity
		_lost_time = 0.0
		_suppress_left = suppress_time
		_seen_time += delta
		state = State.ATTACK
		_attack(cmd, delta)
		if _contact_person and not _called and _seen_time >= _reaction * 0.5:
			_called = true
			_call_out(target)
	elif state == State.ATTACK or state == State.CHASE:
		_lost(cmd, delta)
	elif _alert_left > 0.0:
		# Heard something it is not going to look at: face it, gun up.
		_alert_left -= delta
		_look_along(cmd, _alert_at - actor.get_eye_position())
		cmd.secondary = actor.get_active_weapon() is Gun and actor.is_on_floor()
		cmd.crouch = lies_low
	elif holding:
		_stuck_for = 0.0
	elif has_errand:
		if not at_errand():
			cmd.sprint = true
			_move_toward(cmd, errand, delta, true)
	else:
		_patrol(cmd, delta)
	# A gun never reloads itself: a bot presses the key like a player.
	var dry := actor.get_active_weapon() as Gun
	if dry != null and not dry.is_reloading() and (dry.jammed or (dry.ammo_in_mag <= 0 and dry.reserve_ammo > 0)):
		cmd.reload_pressed = true
	if uses_kit:
		_tend_kit(cmd)
	# A bot's paths are walked and hopped: held Shift in the air would put
	# boots into a skate or wings into a soar (the cruises are a player's).
	if not actor.is_on_floor() and (actor.flight.can_skate() or actor.flight.can_soar()):
		cmd.sprint = false


## Looks after a player's kit (`uses_kit`): heal when hurt and safe enough,
## put the primary back in hand and reload it between fights, and in a fight
## swap off a gun with nothing left for one with rounds, or the blade.
## Only presses, the same keys a player would use.
func _tend_kit(cmd: ActorCommand) -> void:
	var share := actor.health.health / maxf(actor.health.max_health, 1.0)
	var near := target != null and is_instance_valid(target) \
			and actor.global_position.distance_to(target.global_position) < heal_clear_range
	if actor.heal_time_left <= 0.0 and actor.inventory.first_with_tag("heal") != "" \
			and ((state == State.PATROL and share < heal_below) or (share < heal_desperate and not near)):
		cmd.heal_pressed = true
		return
	if actor.heal_time_left > 0.0:
		return
	var held := actor.get_active_weapon()
	var gun := held as Gun
	if state == State.ATTACK:
		# A primary run dry mid-fight: the sidearm, as a player would press 2
		# (a gun never switches itself).
		if gun != null and not gun.is_sidearm and not gun.is_power() and gun.ammo_in_mag <= 0:
			var sidearm := _loaded_sidearm()
			if sidearm >= 0:
				cmd.switch_weapon = sidearm
				return
		# Dry with nothing to reload from: the other gun if it has rounds,
		# else the blade.
		if held == null or (gun != null and gun.is_spent()):
			var next := _loaded_gun()
			cmd.switch_weapon = next if next >= 0 else _blade_index()
		return
	if state != State.PATROL:
		return
	var primary := _primary_index()
	if primary >= 0 and actor.active_weapon_index != primary and not (actor.weapons[primary] as Gun).is_spent():
		cmd.switch_weapon = primary
	elif gun != null and not gun.is_reloading() and gun.ammo_in_mag < gun.mag_size and gun.reserve_ammo > 0:
		cmd.reload_pressed = true
	elif held == null:
		var any := _loaded_gun()
		cmd.switch_weapon = any if any >= 0 else _blade_index()


## How far it opens fire: its own kind's range, or a mounted gun's (a
## gunner's seat turns even a blade fighter into a gunner).
func _gun_reach() -> float:
	var held := actor.get_active_weapon()
	if held != null and held.has_meta("mounted"):
		return maxf(attack_range, MOUNTED_REACH)
	return attack_range


func _primary_index() -> int:
	# On a vehicle's gun (a gunner's seat), that is the gun to fight with.
	for i in actor.weapons.size():
		if actor.weapons[i].has_meta("mounted"):
			return i
	for i in actor.weapons.size():
		var gun := actor.weapons[i] as Gun
		if gun != null and not gun.is_sidearm and not gun.is_power():
			return i
	return -1


## A sidearm with rounds in its magazine, or -1.
func _loaded_sidearm() -> int:
	for i in actor.weapons.size():
		var gun := actor.weapons[i] as Gun
		if gun != null and gun.is_sidearm and gun.ammo_in_mag > 0:
			return i
	return -1


## A gun that can still shoot, the primary first, or -1.
func _loaded_gun() -> int:
	for i in actor.slot_order():
		var gun := actor.weapons[i] as Gun
		if gun != null and not gun.is_spent():
			return i
	return -1


func _blade_index() -> int:
	for i in actor.weapons.size():
		if actor.weapons[i] is MeleeWeapon:
			return i
	return -1


func _attack(cmd: ActorCommand, delta: float) -> void:
	_refresh_hunt()
	_error_left -= delta
	if _error_left <= 0.0:
		_error_left = 0.35
		_error = Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1))
	var eye := actor.get_eye_position()
	var chest := target.global_position + Vector3(0, 1.1, 0)
	var dist := eye.distance_to(chest)

	var blade := actor.get_active_weapon() as MeleeWeapon
	if blade:
		var aim_point := chest + _error * dist * aim_error
		_look_along(cmd, aim_point - eye)
		cmd.aim_dir = (aim_point - eye).normalized()
		_aim = cmd.aim_dir
		if not _may_attack(dist):
			_wait_turn_melee(cmd, blade, delta)
			return
		_attack_melee(cmd, blade, delta)
		return
	_aim_gun(cmd, eye, chest, dist, delta)
	_combat_hop(cmd, delta)
	if (_falling_back or _broken_left > 0.0) and dist > point_blank \
			and not (_hit_by == target and _since_hit() < return_fire_time):
		_fall_back(cmd, delta)
		return
	var my_turn := _may_attack(dist)
	if not my_turn:
		# Keep the gun on them, ready, but hold fire and get somewhere better.
		_wait_turn(cmd, delta, dist)
		return
	# Aim down sights on the ground, the way a person fights a duel. In the
	# air the hop owns the aim button (a jetpack hovers while it is held).
	# A gun that locks on raises its aim (and its tracking beam, which every
	# view draws from the held aim) only once it has reacted, as the lock starts.
	# The gun comes up halfway through the reaction: the tell before the
	# first shot (every view sees it, and hears the bark, `ActorSkin`).
	var raise_at := _reaction if lock_time > 0.0 else _reaction * 0.5
	if actor.is_on_floor() and _hop_left <= 0.0 and _seen_time >= raise_at:
		cmd.secondary = true

	# A blade coming in: give ground from the hip at a full walk, angling
	# off, rather than stand aiming down sights to be cut.
	if not uses_kit and target.get_active_weapon() is MeleeWeapon and dist < blade_backoff:
		cmd.secondary = false
		cmd.move = Vector2(_strafe_sign * 0.6, -1.0).normalized()
	# Keep a comfortable distance: close in from cover to cover, peek from
	# the cover it is in, back off, or strafe. A bot that may not leave its
	# ground (not a hunter, or past its leash) fights from where it is.
	elif dist > preferred_range * 1.4 and _may_close(target.global_position):
		_advance(cmd, delta)
	elif _at_cover():
		# Peek: down behind it between bursts, up to shoot.
		cmd.crouch = _burst_left <= 0.0 and _pause_left > 0.35
	elif dist > preferred_range * 1.4:
		pass
	elif dist < preferred_range * 0.5:
		cmd.move = Vector2(0, -1)
	else:
		_strafe_left -= delta
		if _strafe_left <= 0.0:
			_strafe_left = _rng.randf_range(0.8, 2.0)
			_strafe_sign = -_strafe_sign
		cmd.move = Vector2(_strafe_sign, 0)

	if _flinch_left > 0.0:
		_flinch_left -= delta
		return
	if _seen_time < _reaction or dist > _gun_reach() or not _on_target:
		_lock = 0.0 if not _on_target else _lock
		return
	if lock_time > 0.0:
		# The tracking beam: a lock builds while the target stays in sight,
		# and a wall (or a flier ducking behind one) breaks it.
		var query := PhysicsRayQueryParameters3D.create(eye, chest, Actor.LAYER_WORLD)
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			_lock = 0.0
			return
		_lock += delta
		if _lock < lock_time:
			return
	_fire_bursts(cmd, delta)


## Fires in bursts with a pause between, holding the trigger through a burst.
func _fire_bursts(cmd: ActorCommand, delta: float) -> void:
	if _burst_left > 0.0:
		_burst_left -= delta
		cmd.primary = true
		cmd.primary_pressed = true
		if _burst_left <= 0.0:
			_pause_left = burst_pause * _rng.randf_range(0.7, 1.4)
	else:
		_pause_left -= delta
		if _pause_left <= 0.0:
			_burst_left = burst_time


## Turns the bot's aim toward the target the way a person would (see the
## aim tuning at the top) and sets `_on_target` when it is close enough to
## shoot. A new target means a fresh reaction time and a wide first aim.
func _aim_gun(cmd: ActorCommand, eye: Vector3, chest: Vector3, dist: float, delta: float) -> void:
	var sharp := clampf(skill, 0.0, 1.0)
	_take_recoil(delta)
	if target != _aim_target:
		_aim_target = target
		_seen_time = 0.0
		_lock = 0.0
		_reaction = reaction_time * _rng.randf_range(0.8, 1.3) * (1.4 - 0.8 * sharp) \
				* notice_mult(dist, sight_range * storm_boost, target.crouched, far_notice_mult, crouch_notice_mult) \
				* ground_notice
		if _hit_by == target and _since_hit() < return_fire_time:
			_reaction *= 0.5
		_wander_left = 0.0
		# The first look lands off to one side.
		_wander = Vector2.from_angle(_rng.randf() * TAU)
		if _aim.length_squared() < 0.5:
			_aim = Basis.from_euler(Vector3(cmd.pitch, cmd.yaw, 0.0)) * Vector3.FORWARD
	# Where it means to aim: where the target was a moment ago, plus a
	# wander that drifts rather than jumps.
	_wander_left -= delta
	if _wander_left <= 0.0:
		_wander_left = _rng.randf_range(0.3, 0.6)
		_wander_goal = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).limit_length(1.0)
		_lag = track_lag * _rng.randf_range(0.4, 1.3) * (1.5 - sharp)
	_wander = _wander.lerp(_wander_goal, clampf(delta * 5.0, 0.0, 1.0))
	var settle := lerpf(settle_mult, 1.0, clampf(_seen_time / settle_time, 0.0, 1.0))
	var error := aim_error_deg * (1.5 - sharp) * settle
	if target.airborne_time > 0.15:
		error += air_error_deg
	error += far_error_deg * maxf(dist - preferred_range, 0.0)
	if Vector2(actor.velocity.x, actor.velocity.z).length() > 1.0:
		error += self_move_error_deg
	var to := (chest - target.velocity * _lag - eye).normalized()
	var side := to.cross(Vector3.UP).normalized()
	var up := side.cross(to).normalized()
	var off := deg_to_rad(error)
	var want := (to + side * tan(_wander.x * off + deg_to_rad(_recoil.y))
			+ up * tan(_wander.y * off + deg_to_rad(_recoil.x))).normalized()
	# Turn at a limited speed: no snap.
	var gap := _aim.angle_to(want)
	var step := deg_to_rad(turn_speed_deg * (0.6 + 0.8 * sharp)) * delta
	if gap > 0.0001:
		_aim = _aim.slerp(want, minf(1.0, step / gap)).normalized()
	_on_target = _aim.angle_to(want) < deg_to_rad(fire_cone_deg)
	_look_along(cmd, _aim)
	cmd.aim_dir = _aim


## Rush the target and swing when in reach. A bot that reads an incoming
## swing (`guard_skill`) raises its guard `guard_reaction` after it shows,
## and lowers it once the swing is spent, so it pays for timing rather than
## for holding. Swings have a visible windup, so a well-timed parry turns
## the fight.
func _attack_melee(cmd: ActorCommand, blade: MeleeWeapon, delta: float) -> void:
	var dist := _flat_dist(target.global_position)
	_melee_wait = maxf(0.0, _melee_wait - delta)
	_guard_delay = maxf(0.0, _guard_delay - delta)
	_dash_wait = maxf(0.0, _dash_wait - delta)
	if _hold_left > 0.0:
		_carry_charge(cmd, blade, delta, dist)
		return
	if dist > blade.reach * 0.7 and _may_close(target.global_position):
		cmd.sprint = true
		_move_toward(cmd, target.global_position, delta, false)
	if _try_dash_strike(cmd, blade, dist):
		return
	# Closing on a gunner with a blade, a bot that plays like a person keeps
	# its guard up (the fresh guard turns rounds aside, then it halves them).
	if uses_kit and target.get_active_weapon() is Gun and dist > blade.reach * 1.1:
		cmd.secondary = true
		return

	if _feint_heavy and blade._windup_kind == "heavy":
		if blade._windup_left < blade._windup_total * 0.6:
			cmd.secondary = true
			_feint_heavy = false
			_melee_wait = _rng.randf_range(0.2, 0.4)
		return
	_feint_heavy = false
	var foe_blade := target.get_active_weapon() as MeleeWeapon
	if _guard_against(cmd, blade, foe_blade, dist, delta):
		return

	# A kick read in time is answered with a swing, which beats it.
	var kicking := foe_blade != null and foe_blade.is_kicking() and foe_blade._windup_left > 0.0
	if kicking and not _kick_seen:
		_kick_answer = _rng.randf() < guard_skill
	_kick_seen = kicking
	if kicking and _kick_answer and dist <= blade.reach * 0.9 and not blade.is_busy() \
			and foe_blade._windup_left > blade.light_windup * 0.6:
		_kick_answer = false
		cmd.primary_pressed = true
		_melee_wait = _rng.randf_range(0.3, 0.5)
		return
	# An opening: the foe is recovering from a swing, staggered, or this bot
	# just parried. Strike now rather than wait out the tempo.
	var opening := actor.riposte_left > 0.0 or target.stagger_left > 0.0 \
			or (foe_blade != null and foe_blade.recover_progress() >= 0.0 and foe_blade.recover_progress() < 0.6)
	var may_swing := _melee_wait <= 0.0 or opening
	if dist <= blade.reach * 0.9 and may_swing and _seen_time >= reaction_time and not blade.is_busy():
		_start_attack(cmd, blade, opening)
		return
	# Between swings against a gun the guard stays up: rounds cost no held
	# drain, and each one the guard stops is paid for on its own.
	if target.get_active_weapon() is Gun and dist <= blade.reach * 1.6 and _guard_delay <= 0.0 \
			and _seen_time >= reaction_time and not blade.is_winding_up():
		cmd.secondary = true


## Reads a swing coming from `foe_blade` and keeps the guard up through it.
## True while guarding (nothing else this tick).
func _guard_against(cmd: ActorCommand, blade: MeleeWeapon, foe_blade: MeleeWeapon,
		dist: float, delta: float) -> bool:
	var threatened := foe_blade != null and foe_blade.threat_dir() >= 0 and dist <= foe_blade.reach * 1.5
	if threatened and not _threat_seen:
		_read_left = guard_reaction if _rng.randf() < guard_skill else -1.0
		_lead_now = guard_lead + _rng.randf_range(-guard_lead_jitter, guard_lead_jitter)
		# A heavy read in time may be dodged rather than met.
		if _read_left >= 0.0 and foe_blade._windup_kind == "heavy" and _rng.randf() < melee_dodge_chance \
				and actor.stamina >= actor.dash_stamina:
			cmd.dash = true
			cmd.move = Vector2(_strafe_sign, -0.5)
			_read_left = -1.0
	_threat_seen = threatened
	if not threatened:
		_read_left = -1.0
		return false
	if _read_left < 0.0 or blade.is_winding_up() or _guard_delay > 0.0:
		return false
	_read_left = maxf(0.0, _read_left - delta)
	if _read_left > 0.0:
		return false
	if not blade.is_blocking() and foe_blade._windup_left > _lead_now:
		# Read, but too early to raise it: wait for the swing.
		return false
	cmd.secondary = true
	return true


## Picks the next swing: a light tap, a held heavy (likelier into a raised
## guard or a stagger), or a feint.
func _start_attack(cmd: ActorCommand, blade: MeleeWeapon, opening: bool) -> void:
	_melee_wait = _rng.randf_range(1.0, 1.7) * melee_tempo
	if uses_kit:
		# A person chains the three-hit combo, then breathes.
		_melee_wait = _rng.randf_range(0.3, 0.45) if blade.combo_step < 2 else _rng.randf_range(0.8, 1.2)
	# Against a blade the guard comes back up as soon as a swing is read;
	# against a gun a guard straight back up only costs the combo its pace.
	_guard_delay = 0.75 if target.get_active_weapon() is Gun else 0.3
	var guarded := false
	var foe_blade := target.get_active_weapon() as MeleeWeapon
	if foe_blade != null:
		guarded = foe_blade.is_blocking()
	if _wants_ability(blade, guarded):
		cmd.weapon_ability_pressed = true
		_melee_wait = blade.ability_windup + blade.ability_recover
		return
	if guarded and actor.stamina >= blade.kick_stamina and _rng.randf() < kick_chance:
		# A guard held up gets kicked open.
		cmd.kick_pressed = true
		return
	var heavy_odds := heavy_vs_guard if guarded or target.stagger_left > 0.0 else heavy_share
	if opening and actor.riposte_left > 0.0:
		heavy_odds = maxf(heavy_odds, 0.5)
	if actor.stamina >= blade.heavy_stamina and _rng.randf() < heavy_odds:
		# Hold through the turn into a heavy: its charge and windup show.
		_feint_heavy = not opening and _rng.randf() < heavy_feint_chance \
				and actor.stamina >= blade.heavy_stamina + blade.feint_stamina
		_hold_left = blade.hold_time + 0.05
		cmd.primary_pressed = true
		cmd.primary = true
		return
	if not opening and _rng.randf() < feint_chance:
		# Hang on the charge to draw an early guard, then let go as a light.
		_hold_left = feint_show + 0.02
		cmd.primary_pressed = true
		cmd.primary = true
		return
	cmd.primary_pressed = true


## True when the weapon's ability is ready and the moment fits it.
func _wants_ability(blade: MeleeWeapon, guarded: bool) -> bool:
	if not blade.ability_ready() or not actor.is_on_floor() or actor.stamina < blade.ability_stamina:
		return false
	var dist := target.global_position.distance_to(actor.global_position)
	var foe_blade := target.get_active_weapon() as MeleeWeapon
	match blade.ability:
		"ground_pound":
			return _wants_pound(blade)
		"shadow_step":
			return dist <= blade.ability_radius and not MeleeWeapon.is_behind(target, actor.global_position, 180.0) \
					and _rng.randf() < ability_chance
		"trip":
			return dist <= blade.ability_radius and _rng.randf() < ability_chance
		"counter_stance":
			return foe_blade != null and (foe_blade.is_winding_up() or foe_blade.is_charging()) \
					and dist <= foe_blade.reach + 1.0
		"guard_hook":
			return guarded and dist <= blade.ability_radius
	return false


## True when the ground pound is ready and worth it: the target in its
## ring and another foe too, or now and then the target alone. Looked at
## only when a hammer bot picks a swing with the pound ready, so the scan
## of the field is rare.
func _wants_pound(blade: MeleeWeapon) -> bool:
	if blade.ability != "ground_pound" or not blade.ability_ready() or not actor.is_on_floor() \
			or actor.stamina < blade.ability_stamina:
		return false
	var ring := blade.ability_radius * 0.8
	if target.global_position.distance_to(actor.global_position) > ring:
		return false
	for node in get_tree().get_nodes_in_group("actors"):
		var other := node as Actor
		if other == null or other == actor or other == target or other.is_dead or other.faction == actor.faction:
			continue
		if other.global_position.distance_to(actor.global_position) <= ring:
			return true
	return _rng.randf() < pound_alone_chance


## Keeps a charge held until it is let go.
func _carry_charge(cmd: ActorCommand, blade: MeleeWeapon, delta: float, dist: float) -> void:
	_hold_left -= delta
	if dist > blade.reach * 0.6:
		_move_toward(cmd, target.global_position, delta, false)
	if _hold_left > 0.0:
		cmd.primary = true
	else:
		_hold_left = 0.0


## A bot running in from out of reach opens with a dash-strike (a heavy
## started at a sprint closes up to `MeleeWeapon.dash_range`).
func _try_dash_strike(cmd: ActorCommand, blade: MeleeWeapon, dist: float) -> bool:
	if blade.dash_range <= 0.0 or _dash_wait > 0.0 or blade.is_busy() or not cmd.sprint:
		return false
	if dist < blade.reach * 1.4 or dist > blade.reach + blade.dash_range * 0.8:
		return false
	if _seen_time < reaction_time or not actor.is_on_floor():
		return false
	if actor.stamina < blade.heavy_stamina + blade.dash_stamina:
		return false
	_dash_wait = dash_every
	if _rng.randf() >= dash_chance:
		return false
	cmd.tertiary_pressed = true
	_melee_wait = _rng.randf_range(1.0, 1.7) * melee_tempo
	_guard_delay = 0.75
	return true


## A target seen for the first time (or again after losing it): note who
## it is. A person is called out to the squad once the bot has reacted and
## brings its gun up (`_call_out`, with the bark every view hears).
func _new_contact() -> void:
	var id := target.get_instance_id()
	if id != _contact_id:
		_release()
		_stop_hunting()
	_contact_id = id
	_contact_person = not uses_kit and is_person(target)
	_search.clear()
	_alert_left = 0.0
	_called = false


## Keeps (or asks for) a hunter place on the person in sight.
func _refresh_hunt() -> void:
	if not _contact_person or not ration_attacks:
		_hunting = true
		return
	_hunting = SquadBoard.hunt(_contact_id, get_instance_id(), max_hunters, Engine.get_physics_frames(), 3.0)


func _stop_hunting() -> void:
	if _contact_id != 0:
		SquadBoard.stop_hunt(_contact_id, get_instance_id())
		SquadBoard.stop_flank(_contact_id, get_instance_id())
	_hunting = false


## Whether the bot may leave its ground to go to `point`: within its leash,
## and for a person only as one of the hunters.
func _may_close(point: Vector3) -> bool:
	if uses_kit or has_errand:
		return true
	if not _within_leash(point):
		return false
	return _hunting or not _contact_person or not ration_attacks


## Within `leash` of the ground the bot holds (its patrol round its post).
func _within_leash(point: Vector3) -> bool:
	if uses_kit or has_errand:
		return true
	var off := point - _home
	off.y = 0.0
	return off.length() <= patrol_radius + leash * storm_boost


## Lost sight of its contact: the bot whose turn it was pins the cover they
## went behind for a moment, the flanker works round, and the hunters
## search from the last sighting; anyone else, or once the search is done,
## goes back to its ground.
func _lost(cmd: ActorCommand, delta: float) -> void:
	_hold_left = 0.0
	_lock = 0.0
	_lost_time += delta
	state = State.CHASE
	if _suppress_left > 0.0 and _may_suppress():
		_suppress_left -= delta
		_suppress(cmd, delta)
		return
	_suppress_left = 0.0
	_release()
	_seen_time = 0.0
	_aim_target = null
	if _lost_time > give_up_time or not _may_close(_last_seen):
		_end_search()
		return
	if _search.is_empty():
		_plan_search()
		if _search.is_empty():
			_end_search()
			return
	var dest: Vector3 = _search[0]
	if actor.get_real_velocity().length() < 0.3:
		_search_slow += delta
	else:
		_search_slow = 0.0
	if _flat_dist(dest) < 2.0 or _search_slow > 1.5:
		_search_slow = 0.0
		_search.pop_front()
		if _search.is_empty():
			_end_search()
		return
	# Hurried to where it last saw them, then a careful look round.
	cmd.sprint = _lost_time < 3.0
	_move_toward(cmd, dest, delta, true)


## Where to look: where the contact was last seen, carried on a little the
## way it was going, then a few points round that, ahead of its course. The
## one flanker goes round the side first.
func _plan_search() -> void:
	var drift := Vector3(_last_vel.x, 0.0, _last_vel.z).limit_length(6.0)
	var guess := _last_seen + drift
	if _contact_person and flanks and SquadBoard.flank(_contact_id, get_instance_id(),
			Engine.get_physics_frames(), 6.0, flankers):
		var off := actor.global_position - guess
		off.y = 0.0
		if off.length() > 0.5:
			var side := deg_to_rad(75.0) * (1.0 if _rng.randf() < 0.5 else -1.0)
			var spot := guess + off.normalized().rotated(Vector3.UP, side) * 8.0
			if _within_leash(spot):
				_search.append(spot)
	_search.append(guess)
	var heading := atan2(drift.z, drift.x) if drift.length() > 0.5 else _rng.randf() * TAU
	for i in search_points:
		var angle := heading + _rng.randf_range(-PI * 0.5, PI * 0.5)
		var spot := guess + Vector3(cos(angle), 0.0, sin(angle)) * search_spread * _rng.randf_range(0.5, 1.0)
		if _within_leash(spot):
			_search.append(spot)


## Done looking: back to its ground, facing where it lost them for a moment.
func _end_search() -> void:
	_release()
	_stop_hunting()
	_search.clear()
	_contact_id = 0
	state = State.PATROL
	_has_dest = false
	_alert_at = _last_seen + Vector3(0, 1.0, 0)
	_alert_left = alert_time * 0.5


## Suppressing: only the bot whose turn it is on that person, with a gun
## that needs no lock, within range of where they went.
func _may_suppress() -> bool:
	if not _contact_person or lock_time > 0.0:
		return false
	var gun := actor.get_active_weapon() as Gun
	if gun == null or gun.is_spent():
		return false
	if actor.get_eye_position().distance_to(_last_seen) > attack_range:
		return false
	var slot: Dictionary = _slots.get(_contact_id, {})
	return not slot.is_empty() and int(slot.holders.get(get_instance_id(), 0)) > Engine.get_physics_frames()


## Bursts at the cover a person ducked behind, where their chest was, a
## little wide: it keeps them down. Rounds still have to reach them.
func _suppress(cmd: ActorCommand, delta: float) -> void:
	var eye := actor.get_eye_position()
	var point := _last_seen + Vector3(0, 1.1, 0)
	var to := (point - eye).normalized()
	var side := to.cross(Vector3.UP).normalized()
	var spread := deg_to_rad(suppress_spread_deg)
	var want := (to + side * tan(_rng.randf_range(-spread, spread))
			+ Vector3.UP * tan(_rng.randf_range(-spread, spread) * 0.5)).normalized()
	var gap := _aim.angle_to(want)
	var step := deg_to_rad(turn_speed_deg) * delta
	if gap > 0.0001:
		_aim = _aim.slerp(want, minf(1.0, step / gap)).normalized()
	_look_along(cmd, _aim)
	cmd.aim_dir = _aim
	cmd.secondary = actor.is_on_floor()
	if _aim.angle_to(to) < deg_to_rad(fire_cone_deg + suppress_spread_deg):
		_fire_bursts(cmd, delta)


## Tells the bot's faction nearby where the person it just saw is: a
## snapshot, never live tracking.
func _call_out(person: Actor) -> void:
	var now := float(Engine.get_physics_frames()) / Engine.physics_ticks_per_second
	if now - _called_at < callout_every:
		return
	_called_at = now
	var raid := Raid.of(actor)
	if raid == null:
		return
	var at := person.global_position
	var reach := callout_range * callout_range
	var team_reach := team_range * team_range
	for bot: Variant in raid.bots:
		if not is_instance_valid(bot) or bot == actor:
			continue
		var other := bot as Actor
		if other.is_dead or other.faction != actor.faction:
			continue
		var brain := other.get_node_or_null("Brain") as BotBrain
		if brain == null or brain.uses_kit:
			continue
		var apart := other.global_position.distance_squared_to(actor.global_position)
		if apart <= reach or (team != 0 and brain.team == team and apart <= team_reach):
			brain.hear_callout(at, person)


## Heavier kinds and bosses stand their ground when hurt.
func _stands_ground() -> bool:
	return actor.has_meta("boss") or str(actor.get_meta("kind", "soldier")) in ["heavy", "exo", "walker"]


## Badly hurt: back to its post, the squad's ground, and down in cover there;
## it fights back only when pressed (`_attack` lets it then).
func _fall_back(cmd: ActorCommand, delta: float) -> void:
	_release()
	_stop_hunting()
	if _flat_dist(_home) > 4.0:
		_move_toward(cmd, _home, delta, false)
		return
	_cover_left -= delta
	if _cover_left <= 0.0:
		_cover_left = 2.0
		_cover = _find_cover(false)
	if _cover.is_finite() and _flat_dist(_cover) > 1.0:
		_move_toward(cmd, _cover, delta, false)
	else:
		cmd.crouch = true


## Joins fireteam `id` of `size` (the `Raid`'s orders); a new team starts
## counting its losses afresh.
func set_team(id: int, size: int) -> void:
	if id != team:
		_allies_lost = 0
	team = id
	team_size = size


## One of its fireteam fell. A team that breaks (`breaks_at`) falls back
## once it has lost that share of itself.
func ally_down() -> void:
	if team == 0 or breaks_at <= 0.0 or uses_kit:
		return
	_allies_lost += 1
	if _broken_left <= 0.0 and _allies_lost >= maxi(1, ceili(team_size * breaks_at)):
		_broken_left = break_time
		_allies_lost = 0


## Broken off from a fight its team was losing (`ally_down`).
func is_broken() -> bool:
	return _broken_left > 0.0


## A grenade or rocket about to burst near the bot: it runs (`_dodge`). A
## bot notices each round once, and only sometimes, by skill.
func _think_danger() -> void:
	if Gun.live_rounds.is_empty():
		return
	var me := actor.global_position + Vector3(0, 0.9, 0)
	for node: Variant in Gun.live_rounds:
		if not is_instance_valid(node):
			continue
		var shot := node as Node3D
		var radius := float(shot.get("splash_radius"))
		if radius <= 0.0 or shot.get("gun_shooter") == actor or shot.get_world_3d() != get_world_3d():
			continue
		var vel: Vector3 = shot.get("velocity")
		var from := shot.global_position
		var to := from + vel * (0.4 if str(shot.get("kind")) == "grenade" else 1.0)
		var near := Geometry3D.get_closest_point_to_segment(me, from, to)
		if near.distance_to(me) > radius + 1.0:
			continue
		var id := shot.get_instance_id()
		if _danger_seen.has(id):
			continue
		if _danger_seen.size() > 32:
			_danger_seen.clear()
		_danger_seen[id] = true
		if _rng.randf() < lerpf(dodge_chance.x, dodge_chance.y, clampf(skill, 0.0, 1.0)):
			_dodge_from = near
			_dodge_left = dodge_time
			return


## Running from a burst: straight away from it, or to the side of a rocket.
func _dodge(cmd: ActorCommand, delta: float) -> void:
	var away := actor.global_position - _dodge_from
	away.y = 0.0
	if away.length() < 0.3:
		away = Basis(Vector3.UP, cmd.yaw) * Vector3.RIGHT * _strafe_sign
	if target == null:
		_look_along(cmd, away)
	cmd.sprint = true
	var local := Basis(Vector3.UP, cmd.yaw).inverse() * away.normalized()
	cmd.move = Vector2(local.x, -local.z)
	if flies:
		_unstick(cmd, delta)
	else:
		_climb_out(cmd, delta)
		if edge_guard:
			_keep_on_ground(cmd, _nav.get_navigation_map())


## A guarded bot's step (`edge_guard`), the side-step out of a jam
## included, that would leave the navmesh slides along its edge instead, or
## stops if there is no way along.
func _keep_on_ground(cmd: ActorCommand, map_rid: RID) -> void:
	if cmd.move.length() < 0.05 or NavigationServer3D.map_get_iteration_id(map_rid) <= 0:
		return
	var dir := Basis(Vector3.UP, cmd.yaw) * Vector3(cmd.move.x, 0.0, -cmd.move.y)
	dir.y = 0.0
	dir = dir.normalized()
	var ahead := actor.global_position + dir * EDGE_LOOK
	var on := NavigationServer3D.map_get_closest_point(map_rid, ahead)
	if Vector2(on.x - ahead.x, on.z - ahead.z).length() <= EDGE_OFF:
		return
	var slide := on - actor.global_position
	slide.y = 0.0
	if slide.length() < 0.3:
		cmd.move = Vector2.ZERO
		_side_left = 0.0
		return
	var local := Basis(Vector3.UP, cmd.yaw).inverse() * slide.normalized()
	cmd.move = Vector2(local.x, -local.z)


## A bot on foot pressing on and getting nowhere (a crater's lip, a wall
## its path runs into) jumps and steps aside, as a person would: the same
## keys a player presses.
func _climb_out(cmd: ActorCommand, delta: float) -> void:
	if _side_left > 0.0:
		_side_left -= delta
		cmd.move = (cmd.move + Vector2(_strafe_sign, 0.0)).normalized()
		return
	# Measured by ground covered, not speed: a bot sliding back down a
	# slope it cannot climb is moving, and going nowhere. Pressing into
	# the person it is fighting is not being stuck.
	if target != null and _flat_dist(target.global_position) < 4.0:
		_climb_for = 0.0
		_climb_from = actor.global_position
		return
	_climb_for += delta
	if _climb_for < stuck_time * 2.0:
		return
	var gone := actor.global_position - _climb_from
	gone.y = 0.0
	_climb_for = 0.0
	_climb_from = actor.global_position
	if gone.length() < 1.0 and actor.is_on_floor():
		cmd.jump_pressed = true
		_side_left = 0.7
		_strafe_sign = -_strafe_sign


func _patrol(cmd: ActorCommand, delta: float) -> void:
	if lies_low:
		# Back to its post, then down and still.
		if _flat_dist(_home) > 1.5:
			_move_toward(cmd, _home, delta, true)
		else:
			cmd.crouch = true
		return
	if _wait_left > 0.0:
		_wait_left -= delta
		return
	if not _has_dest:
		var angle := _rng.randf_range(0, TAU)
		_dest = _home + Vector3(cos(angle), 0, sin(angle)) * _rng.randf_range(5.0, patrol_radius)
		# A point past a drop is walked to its edge: patrol to the edge.
		_dest = _onto_nav(_dest)
		_has_dest = true
		_repath_left = 0.0
	if _flat_dist(_dest) < 2.0:
		_has_dest = false
		_wait_left = _rng.randf_range(1.0, 3.5)
		return
	# A long way from the post: this is a march, not a patrol.
	cmd.sprint = _flat_dist(_home) > patrol_radius + march_distance
	_move_toward(cmd, _dest, delta, true)
	# Give up on a point we cannot reach.
	if actor.get_real_velocity().length() < 0.3:
		_wait_left = 0.0
		if _rng.randf() < delta * 0.7:
			_has_dest = false


## Walks toward a point using the navmesh when one is ready, else in a straight line.
func _move_toward(cmd: ActorCommand, dest: Vector3, delta: float, face_travel: bool) -> void:
	# A new path is the dearest thing a bot does, so it asks for one only when
	# the place it is going has really moved (further for a far-off place), or
	# when the path it has ran out short of it: a search only reaches so far,
	# and a long march arrives in legs.
	_repath_left -= delta
	if shuns_warmth:
		dest = _outside_warmth(dest)
	var dir := dest - actor.global_position
	if _repath_left <= 0.0:
		var moved := dest.distance_to(_path_to)
		var short := _nav.is_navigation_finished() and _flat_dist(dest) > 3.0
		if (not _has_path or short or moved > maxf(repath_distance, dir.length() * 0.15)) \
				and _path_allowed():
			_has_path = true
			_path_to = dest
			_nav_goal = _onto_nav(dest)
			_nav.target_position = _nav_goal
			_repath_left = 0.4
	var map_rid := _nav.get_navigation_map()
	if NavigationServer3D.map_get_iteration_id(map_rid) > 0:
		if _has_path and not flies and _nav.is_navigation_finished():
			# The path ran out: head for where it really ends (a goal on
			# another mesa ends at this one's edge), and stop on arriving.
			# Walking on at full pace overshoots, and at an edge that is a fall.
			dir = _nav.get_final_position() - actor.global_position
			if Vector2(dir.x, dir.z).length() < ARRIVE_STOP:
				return
		var next := _nav.get_next_path_position()
		var step := next - actor.global_position
		step.y = 0.0
		if step.length() > 0.2:
			dir = step
	dir.y = 0.0
	if dir.length() < 0.05:
		return
	dir = dir.normalized()
	if face_travel:
		_look_along(cmd, dir)
	var local := Basis(Vector3.UP, cmd.yaw).inverse() * dir
	cmd.move = Vector2(local.x, -local.z)
	if flies:
		_unstick(cmd, delta)
	else:
		_climb_out(cmd, delta)
		if edge_guard:
			_keep_on_ground(cmd, map_rid)


## Takes one of this tick's new paths (`PATHS_PER_TICK`), or says none is left.
func _path_allowed() -> bool:
	var tick := Engine.get_physics_frames()
	if tick != _path_tick:
		_path_tick = tick
		_paths_this_tick = 0
	if _paths_this_tick >= PATHS_PER_TICK:
		return false
	_paths_this_tick += 1
	return true


## `dest` moved onto the nearest walkable ground, once the navigation map is
## ready, for a bot that keeps off edges (`edge_guard`: the Rift's mesas).
## Elsewhere the goal is left alone: the lookup costs as much as a path. A
## flier's goal (it may be in the air) is left alone too.
func _onto_nav(dest: Vector3) -> Vector3:
	var map_rid := _nav.get_navigation_map()
	if flies or not edge_guard or NavigationServer3D.map_get_iteration_id(map_rid) <= 0:
		return dest
	var on := NavigationServer3D.map_get_closest_point(map_rid, dest)
	return dest if on == Vector3.ZERO else on


## A flier pushing against something it cannot walk over lifts off: a jump
## held into the rig's own lift (a jetpack's jets on held aim, the boots'
## skim, the wings' glide), the same keys a player would hold.
func _unstick(cmd: ActorCommand, delta: float) -> void:
	if not actor.flight.enabled:
		return
	if actor.is_on_floor() and actor.get_real_velocity().length() < 0.6:
		_stuck_for += delta
	else:
		_stuck_for = 0.0
	if _stuck_for > stuck_time and not actor.flight.overheated:
		_stuck_for = 0.0
		_lift_left = unstick_lift
	if _lift_left <= 0.0:
		return
	_lift_left -= delta
	if actor.is_on_floor():
		cmd.jump_pressed = true
	cmd.jump = true
	if actor.flight.can_hover():
		cmd.secondary = true


## A jetpack wearer in a gunfight takes to the air now and then: up off the
## ground, a climb, then a hover on held aim while it shoots, and down again
## when it lets go. It costs heat like anyone's, so it waits for a cool rig.
func _combat_hop(cmd: ActorCommand, delta: float) -> void:
	if not flies or not actor.flight.enabled or not actor.flight.can_hover():
		return
	if _hop_left > 0.0:
		_hop_left -= delta
		cmd.secondary = true
		cmd.jump = _hop_left > combat_hop_time - combat_climb
		return
	_hop_in -= delta
	if _hop_in <= 0.0 and actor.is_on_floor() and actor.flight.heat < hop_heat and not actor.flight.overheated:
		_hop_in = _rng.randf_range(combat_hop_every.x, combat_hop_every.y)
		_hop_left = combat_hop_time
		cmd.jump_pressed = true
		cmd.jump = true


func _look_along(cmd: ActorCommand, dir: Vector3) -> void:
	if dir.length() < 0.001:
		return
	dir = dir.normalized()
	cmd.yaw = atan2(-dir.x, -dir.z)
	cmd.pitch = asin(clampf(dir.y, -1.0, 1.0))


func _find_target() -> Actor:
	var best: Actor = null
	var best_score := INF
	var eye := actor.get_eye_position()
	var forward := Basis(Vector3.UP, actor.cmd.yaw) * Vector3.FORWARD
	var world := Worlds.of(actor)
	# A storm cuts how far a bot sees (DESIGN.md "Weather: ash storms"), by
	# the worse of where it stands and where its target does, and muffles
	# what it hears.
	var raid := Raid.of(actor)
	var weather: Weather = raid.weather if raid != null and raid.weather.kind != "" else null
	storm_boost = 1.0 + storm_bold * weather.strength_at(actor.global_position) \
			if weather != null and storm_bold > 0.0 else 1.0
	var sight := sight_range * storm_boost
	var listening := state != State.ATTACK
	var reach := maxf(sight, LOUDEST_HEARD) if listening else sight
	var heard_dist := INF
	_heard_at = Vector3.INF
	_heard_from = null
	for node in get_tree().get_nodes_in_group("actors"):
		var other := node as Actor
		if other == null or other == actor or other.is_dead or other.faction == actor.faction:
			continue
		# Distance first: it is the cheapest way to rule most of a big field out.
		var chest := other.global_position + Vector3(0, other.body_height() * 0.6, 0)
		var dist := eye.distance_to(chest)
		if dist >= reach or dist * 0.85 >= best_score and not listening:
			continue
		# Past sight and an engine's reach, only a rig loud enough is heard.
		if dist >= sight and dist >= ENGINE_HEARD and (other.flight == null or other.flight.noise() <= dist):
			continue
		if not Raid.together(actor, other):
			continue
		if world and not world.can_damage(actor, other, null):
			continue
		var person := not uses_kit and is_person(other)
		# Heard, not seen: a person's footsteps, jets or engine, through walls.
		if listening and person and dist < heard_dist:
			var loud := noise_of(other)
			if loud > 0.0 and weather != null:
				loud *= weather.carry_at(other.global_position)
			if dist < loud:
				heard_dist = dist
				_heard_at = other.global_position
				_heard_from = other
		var score := dist * (person_bias if person else 1.0) * (0.85 if other == target else 1.0)
		if preys_on_cold and other.shivering:
			score *= 0.6
		if dist >= sight or score >= best_score:
			continue
		if weather != null and storm_bold <= 0.0 and dist >= sight_range * weather.sight_between(eye, chest):
			continue
		# Close air (a forest's mist) shuts the eyes in as it does a player's.
		if world and dist >= minf(world.sight_at(eye), world.sight_at(chest)):
			continue
		# Smoke hides a body from a bot as it does from a player's eyes.
		if raid != null and raid.smoke.blocks(eye, chest):
			continue
		if shuns_warmth and raid != null and in_warmth(raid, other.global_position):
			continue
		# A Phase Cloak hides all but someone right beside the bot.
		if other.is_cloaked() and dist > other.artifact.cloak_sense_range:
			continue
		# Riding (a convoy's gunner or passenger), it keeps watch all round.
		var in_view := actor.vehicle != null \
				or forward.angle_to((chest - eye).normalized()) < deg_to_rad(fov_deg) * 0.5
		# Someone crouched creeps up quieter: sensed only closer in.
		var sense := close_sense_range * (other.crouch_sense_mult if other.crouched else 1.0)
		if not in_view and dist > sense and other != target:
			continue
		var space := get_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.create(eye, chest, Actor.LAYER_WORLD)
		if not space.intersect_ray(query).is_empty():
			# Ducked in cover, it still knows it can stand up and see its target.
			if other != target or not actor.crouched:
				continue
			query = PhysicsRayQueryParameters3D.create(eye + Vector3(0, 0.6, 0), chest, Actor.LAYER_WORLD)
			if not space.intersect_ray(query).is_empty():
				continue
		best = other
		best_score = score
	if best != null:
		_heard_at = Vector3.INF
		_heard_from = null
	return best


## A tracker reads the ground (`tracker_range`): the freshest mark near it
## that it has not followed yet sends it there, as a place to search, never
## the person's live position. Who made it is only the contact it is after.
func _sniff(delta: float) -> void:
	_sniff_left -= delta
	if _sniff_left > 0.0:
		return
	_sniff_left = sniff_every
	var raid := Raid.of(actor)
	if raid == null or not raid.world.tracks:
		return
	var newest: Array = []
	for mark: Array in raid.tracks.near(actor.global_position, tracker_range):
		if int(mark[0]) <= _trail_id or float(mark[4]) < raid.clock - track_fresh:
			continue
		if newest.is_empty() or int(mark[0]) > int(newest[0]):
			newest = mark
	if newest.is_empty():
		return
	_trail_id = int(newest[0])
	var at: Vector3 = newest[1]
	var world := Worlds.of(actor)
	var maker: Actor = null
	var best := 40.0
	for node in get_tree().get_nodes_in_group("actors"):
		var other := node as Actor
		if other == null or other.is_dead or other.faction == actor.faction or not is_person(other):
			continue
		if not Raid.together(actor, other) or (world and not world.can_damage(actor, other, null)):
			continue
		var dist := other.global_position.distance_to(at)
		if dist < best:
			best = dist
			maker = other
	if maker != null:
		_sensed(at, maker, false, true)


## Whether `at` stands in a heater's, vent's or beacon's warmth.
static func in_warmth(raid: Raid, at: Vector3) -> bool:
	for source in raid.warmth:
		if raid.waits_on_keeper(source):
			continue
		var off := at - source.global_position
		var radius := float(source.get_meta("radius", 4.0))
		if absf(off.y) < 3.0 and Vector2(off.x, off.z).length_squared() <= radius * radius:
			return true
	return false


## `dest`, moved out to the edge of any warmth it stands in.
func _outside_warmth(dest: Vector3) -> Vector3:
	var raid := Raid.of(actor)
	if raid == null:
		return dest
	for source in raid.warmth:
		var off := dest - source.global_position
		var radius := float(source.get_meta("radius", 4.0)) + 1.0
		var flat := Vector2(off.x, off.z)
		if absf(off.y) < 3.0 and flat.length_squared() < radius * radius:
			var out := flat.normalized() if flat.length() > 0.1 else Vector2.RIGHT
			return Vector3(source.global_position.x + out.x * radius, dest.y, source.global_position.z + out.y * radius)
	return dest


## How far off a bot hears `other` move (0: silent): an occupied vehicle's
## engine, a flight rig at work (`FlightRig.noise`), or footsteps by pace.
## Walking and crouching make no sound worth turning for.
static func noise_of(other: Actor) -> float:
	if other.vehicle != null:
		return ENGINE_HEARD
	# A flight rig at work is heard as far as the rig carries (its
	# `noise_range`: the jetpack loud, the wings a rush, boots quiet).
	var rig := other.flight.noise() if other.flight != null else 0.0
	if rig > 0.0:
		return rig
	if not other.is_on_floor() or other.crouched:
		return 0.0
	var pace := Vector2(other.velocity.x, other.velocity.z).length()
	if pace > other.walk_speed + 1.0:
		return STEP_SPRINT
	if pace > 4.0:
		return STEP_JOG
	return 0.0


func _flat_dist(point: Vector3) -> float:
	var d := point - actor.global_position
	d.y = 0.0
	return d.length()


## Getting shot tells the bot where to look, even if it never saw the shooter.
func _on_damaged(info: DamageInfo) -> void:
	var source := info.source as Actor
	if source and source != actor:
		_hit_by = source
		_hit_at = Engine.get_physics_frames()
	if info.kind == "melee" and info.amount > 0.0 and not uses_kit and actor.get_active_weapon() is Gun:
		_flinch(melee_flinch, melee_knock_deg)
	if source and source != actor and state == State.PATROL:
		_sensed(source.global_position, source, false, true)


## Gunfire nearby (`Combat.noise`), the defence grid's call or footsteps:
## the nearest few bots (`noise_lookers`) that may leave their ground go to
## look where it came from, the rest turn to face it. A blade makes no
## noise, so a melee kill leaves the rest on patrol.
func _on_heard(at: Vector3, source: Actor) -> void:
	_sensed(at, source, true, false)


## A squadmate saw a person at `at` (`_call_out`): a bot that may leave its
## ground comes to look, the rest face that way.
func hear_callout(at: Vector3, about: Actor) -> void:
	_sensed(at, about, false, true)


## Its army holds a grudge against `about` (`Raid._tick_grudges`): the bot
## goes to look round where they roughly are, as it would for a noise heard
## (off by a tenth of the distance), if it may hunt them.
func hunt_grudge(at: Vector3, about: Actor) -> void:
	_sensed(at, about, false, false)


## Something tells the bot about `source` at `at`: it searches from there
## if it may (a free hunter place and, for a noise, a looker's), else it
## turns to face it for `alert_time`. Hearing is rough: the place is off by
## up to a tenth of the distance. `sure` (a hit, a callout) is exact.
func _sensed(at: Vector3, source: Actor, noise: bool, sure: bool) -> void:
	if source == null or not is_instance_valid(source) or source.faction == actor.faction:
		return
	if state == State.ATTACK:
		return
	var world := Worlds.of(actor)
	if world and not world.can_damage(actor, source, null):
		return
	var id := source.get_instance_id()
	if not sure:
		var off := actor.global_position.distance_to(at) * 0.1
		at += Vector3(_rng.randf_range(-off, off), 0.0, _rng.randf_range(-off, off))
	if state == State.CHASE:
		if id == _contact_id:
			# A fresh fix on what it is already looking for.
			_last_seen = at
			_lost_time = 0.0
			_search.clear()
		return
	_heard_at = Vector3.INF
	var person := not uses_kit and is_person(source)
	var now := Engine.get_physics_frames()
	var may := _within_leash(at)
	if may and person and noise:
		may = SquadBoard.look(id, get_instance_id(), noise_lookers, now, 6.0)
	if may and person and ration_attacks:
		may = SquadBoard.hunt(id, get_instance_id(), max_hunters, now, 3.0)
	if not may:
		_alert_at = at + Vector3(0, 1.0, 0)
		_alert_left = alert_time
		return
	_hunting = person
	_contact_id = id
	_contact_person = person
	_last_seen = at
	_last_vel = Vector3.ZERO
	_lost_time = 0.0
	_suppress_left = 0.0
	_search.clear()
	_alert_left = 0.0
	state = State.CHASE


## How much longer than its near reaction a bot takes to spot someone `dist`
## away (up to `far` times at `sight`), longer still for a crouched body.
static func notice_mult(dist: float, sight: float, crouched: bool, far: float, crouch: float) -> float:
	var mult := lerpf(1.0, far, clampf(dist / maxf(sight, 1.0), 0.0, 1.0))
	return mult * (crouch if crouched else 1.0)


func _since_hit() -> float:
	return float(Engine.get_physics_frames() - _hit_at) / Engine.physics_ticks_per_second


## Someone who takes slots: a player, or a bot that plays like one.
static func is_person(other: Actor) -> bool:
	var brain := other.get_node_or_null("Brain") as BotBrain
	return brain == null or brain.uses_kit


## Whether this bot may shoot or swing at its target now (see `attack_slots`).
func _may_attack(dist: float) -> bool:
	if uses_kit or not ration_attacks or not is_person(target):
		return true
	if dist < point_blank:
		return true
	# A vehicle's mounted gun is no rifle in a crowd: its gunner never waits
	# a turn.
	var held := actor.get_active_weapon()
	if held != null and held.has_meta("mounted"):
		return true
	if not holds_turn and _hit_by == target and _since_hit() < return_fire_time:
		return true
	return take_slot(target.get_instance_id(), get_instance_id(), attack_slots,
			Engine.get_physics_frames(), self)


## Asks for one of `slots` slots on the person `key` for the brain `me` at
## physics frame `now`; true while it holds one. Static so it can be checked
## on its own. `brain` (may be null) times its hold and rest.
static func take_slot(key: int, me: int, slots: int, now: int, brain: BotBrain) -> bool:
	var slot: Dictionary = _slots.get(key, {})
	if slot.is_empty():
		slot = {"holders": {}, "free_at": 0}
		_slots[key] = slot
		if _slots.size() > 512:
			_prune(now)
	var holders: Dictionary = slot.holders
	var tps := Engine.physics_ticks_per_second
	var beat := int((brain.token_beat if brain else 0.5) * tps)
	for id: int in holders.keys():
		if holders[id] <= now:
			slot.free_at = maxi(slot.free_at, holders[id] + beat)
			holders.erase(id)
	if holders.has(me):
		return true
	if brain and now < brain._rest_until:
		return false
	if holders.size() >= slots or now < slot.free_at:
		return false
	var hold := 3.0
	if brain:
		hold = brain._rng.randf_range(brain.token_hold.x, brain.token_hold.y)
	var until := now + int(hold * tps)
	holders[me] = until
	slot.free_at = now + beat
	if brain:
		# Give the others a turn before taking another.
		brain._rest_until = until + int(hold * 0.6 * tps)
	return true


## How many hold a slot on the person `key` at frame `now`.
static func slot_holders(key: int, now: int) -> int:
	var slot: Dictionary = _slots.get(key, {})
	if slot.is_empty():
		return 0
	var count := 0
	for id: int in slot.holders:
		if slot.holders[id] > now:
			count += 1
	return count


static func _prune(now: int) -> void:
	for key: int in _slots.keys():
		var holders: Dictionary = _slots[key].holders
		if holders.values().all(func(until: int) -> bool: return until <= now):
			_slots.erase(key)


## Lets go of any slot this bot holds.
func _release() -> void:
	var id := _contact_id
	if id == 0 and target != null and is_instance_valid(target):
		id = target.get_instance_id()
	if id == 0:
		return
	var slot: Dictionary = _slots.get(id, {})
	if not slot.is_empty() and slot.holders.has(get_instance_id()):
		slot.holders.erase(get_instance_id())
		slot.free_at = maxi(slot.free_at, Engine.get_physics_frames() + int(token_beat * Engine.physics_ticks_per_second))


## Waiting for a slot with a gun: get into cover from the target, or round
## its flank, and keep the gun on them.
func _wait_turn(cmd: ActorCommand, delta: float, dist: float) -> void:
	_cover_left -= delta
	if _cover_left <= 0.0 or not _cover.is_finite():
		_cover_left = 1.5
		_cover = _find_cover(false)
		if not _cover.is_finite() and flanks and _may_close(target.global_position) \
				and (not _contact_person or SquadBoard.flank(_contact_id, get_instance_id(),
					Engine.get_physics_frames(), 4.0, flankers)):
			_cover = _flank_point(dist)
	if _cover.is_finite() and _flat_dist(_cover) > 1.0:
		_move_toward(cmd, _cover, delta, false)
		return
	if _cover.is_finite():
		# In cover: get down behind it.
		cmd.crouch = true
		return
	# Nowhere better: keep a respectful distance, shifting from side to side
	# rather than standing still for a clean shot when its turn comes.
	if dist < preferred_range:
		cmd.move = Vector2(0, -1)
		return
	_strafe_left -= delta
	if _strafe_left <= 0.0:
		_strafe_left = _rng.randf_range(0.8, 2.0)
		_strafe_sign = -_strafe_sign
	cmd.move = Vector2(_strafe_sign * 0.7, 0)


## Waiting for a slot with a blade: circle just out of reach, ready to guard.
func _wait_turn_melee(cmd: ActorCommand, blade: MeleeWeapon, delta: float) -> void:
	var dist := _flat_dist(target.global_position)
	if dist > blade.reach * 2.5:
		if _may_close(target.global_position):
			_move_toward(cmd, target.global_position, delta, false)
	elif dist < blade.reach * 1.8:
		cmd.move = Vector2(0, -1)
	else:
		cmd.move = Vector2(_strafe_sign, 0)
	# Guard only against a swing read in time: a guard held up drains.
	_guard_against(cmd, blade, target.get_active_weapon() as MeleeWeapon, dist, delta)


## Cover from the target, chosen by the angle it is attacking from: a spot
## within a few metres where its eyes cannot see the bot crouched, still in
## shooting range, best where the bot can stand up and see it again (to
## peek) and that no squadmate already holds. `advance` asks only for spots
## nearer the target (moving up from cover to cover). INF when none of the
## tries finds one.
func _find_cover(advance: bool) -> Vector3:
	var space := get_world_3d().direct_space_state
	var their_eye := target.get_eye_position()
	var their_chest := target.global_position + Vector3(0, target.body_height() * 0.6, 0)
	var from := actor.global_position
	var now := Engine.get_physics_frames()
	var me := get_instance_id()
	var dist_now := _flat_dist(target.global_position)
	# Try round the side facing the target first: cover lies between.
	var toward := target.global_position - from
	toward.y = 0.0
	var start := atan2(toward.z, toward.x) if toward.length() > 0.1 else _rng.randf() * TAU
	var best := Vector3.INF
	var best_score := -INF
	for i in 7:
		var angle := start + (i - 3) * TAU / 10.0 + _rng.randf_range(-0.2, 0.2)
		var spot := from + Vector3(cos(angle), 0.0, sin(angle)) * _rng.randf_range(2.5, 8.0)
		var reach := Vector2(spot.x - their_eye.x, spot.z - their_eye.z).length()
		if reach > attack_range or reach < preferred_range * 0.5:
			continue
		if advance and reach > dist_now - 2.0:
			continue
		if not SquadBoard.cover_free(spot, me, now):
			continue
		var low := PhysicsRayQueryParameters3D.create(their_eye, spot + Vector3(0, 0.9, 0), Actor.LAYER_WORLD)
		if space.intersect_ray(low).is_empty():
			continue
		var score := -spot.distance_to(from) * 0.2
		if advance:
			score += (dist_now - reach) * 0.3
		var peek := PhysicsRayQueryParameters3D.create(spot + Vector3(0, 1.55, 0), their_chest, Actor.LAYER_WORLD)
		if space.intersect_ray(peek).is_empty():
			score += 2.0
		if score > best_score:
			best_score = score
			best = spot
	if best.is_finite():
		SquadBoard.take_cover(best, me, now, 4.0)
	return best


## True while the bot is at its chosen cover.
func _at_cover() -> bool:
	return _cover.is_finite() and _flat_dist(_cover) < 1.2


## Closing on the target from cover to cover: a sprint to the next cover
## nearer it, a moment there, then the next; straight at it when there is
## none.
func _advance(cmd: ActorCommand, delta: float) -> void:
	_cover_left -= delta
	if _cover_left <= 0.0 or not _cover.is_finite():
		_cover_left = _rng.randf_range(1.4, 2.2)
		_cover = _find_cover(true)
	if not _cover.is_finite():
		_move_toward(cmd, target.global_position, delta, false)
	elif _flat_dist(_cover) > 1.0:
		_move_toward(cmd, _cover, delta, false)
	else:
		cmd.crouch = _burst_left <= 0.0 and _pause_left > 0.35


## A point off the target's side, at the bot's preferred range.
func _flank_point(dist: float) -> Vector3:
	var off := actor.global_position - target.global_position
	off.y = 0.0
	if off.length() < 0.1:
		off = Vector3.FORWARD
	var side := 1.0 if _rng.randf() < 0.5 else -1.0
	if flankers > 1 and _contact_person:
		# A pincer: the flankers come round both sides.
		var taken := SquadBoard.flank_side(_contact_id, get_instance_id())
		if taken != 0:
			side = float(taken)
	var turn := deg_to_rad(50.0) * side
	var reach := clampf(dist, preferred_range * 0.8, attack_range * 0.8)
	return target.global_position + off.normalized().rotated(Vector3.UP, turn) * reach


## Knocks the gun off its aim and holds the trigger for `time` seconds.
func _flinch(time: float, knock_deg: float) -> void:
	_flinch_left = maxf(_flinch_left, time)
	_burst_left = 0.0
	if _aim.length_squared() > 0.0:
		var side := Vector3.UP.cross(_aim).normalized()
		_aim = _aim.rotated(Vector3.UP, deg_to_rad(knock_deg) * (1.0 if _rng.randf() < 0.5 else -1.0))
		if side.length_squared() > 0.0:
			_aim = _aim.rotated(side, deg_to_rad(knock_deg * 0.5) * _rng.randf_range(-1.0, 1.0))
		_on_target = false


## Adds the kick of any shot the held gun fired since the last tick to the
## climb the bot is fighting, less what it pulls against, and lets the climb
## settle once it stops firing (as a player's view settles).
func _take_recoil(delta: float) -> void:
	var gun := actor.get_active_weapon() as Gun
	if gun != _recoil_gun:
		_recoil_gun = gun
		_recoil_seen = gun.shots_fired if gun else 0
	if gun != null and gun.shots_fired != _recoil_seen:
		var shots := gun.shots_fired - _recoil_seen
		_recoil_seen = gun.shots_fired
		var left := 1.0 - lerpf(RECOIL_CONTROL.x, RECOIL_CONTROL.y, skill)
		_recoil += gun.last_recoil * shots * left * (0.6 if gun.is_aiming() else 1.0)
		_recoil_rest = 0.0
		return
	_recoil_rest += delta
	if _recoil_rest >= RECOIL_SETTLE_DELAY:
		_recoil *= exp(-RECOIL_SETTLE * delta)
