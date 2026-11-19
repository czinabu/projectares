class_name Race
extends Raid
## A race world's time trials (DESIGN.md section 9). The `Raid` that runs a
## world whose map lays out a `RaceTrack`: nobody loses gear and weapons stay
## locked (`WorldDef.gear_at_risk` and `weapons_free` off), and the machines
## waiting in the pit bays are the class's stock machines, tuned by their
## race profile (`Vehicle.race`), never the rider's own.
##
## Getting on a bay machine starts a run: it is set at a free start slot
## behind the line and held (`Vehicle.held`) while the gantry's lights come
## on one by one, then goes. Each run passes the track's gates in order; the
## line ends a lap, `RaceTrack.laps` laps end the run. A lap that strayed off
## the track (`RaceTrack.is_off_track`) is timed but does not count. Getting
## off, or the machine going, retires the run.
##
## Only the authority judges a run. Clients get their own run's view from
## `NetSession` (`remote_run`) and ask for a restart or retirement through
## `send_request`. The ghost, the gantry, the splits on the arches and the
## board are drawn by `RaceView`, which only reads `view_run` and `board`.
##
## Live races (`heats`): a racer on a machine asks to race (the race icon's
## "race" pick, `join_race`), and the track's next race forms on the grid:
## everyone who gets on a machine there while it forms joins it, held at a
## slot. When `FORM_TIME` runs out (sooner once the grid is full of
## people), AI racers (`RaceDriver`) take every empty slot up to
## `GRID_SIZE`, so nobody races alone, and everyone goes under one set of
## lights. Places are worked out every tick from how far round each run is
## (`run_distance`); a lap off the track costs `OFF_TRACK_PENALTY` on the
## finish. Once the first racer finishes the rest have `FINISH_GRACE` to
## cross the line, then the results go on the pit board and the AI racers
## leave. An AI racer is a bot on a stock bay machine, driven through its
## `ActorCommand` like a player: its laps never go on the board.
##
## The league (`RaceLeague`, kept on each racer's account through
## `league_bank`): a race's grid is filled with the named rivals of its best
## rider's league, then other AI racers at that league's skill. The rivals
## talk to each person racing them on the race radio (`radio`): at the
## lights, passing and being passed, off the track and at the finish. When
## a race closes each person's finish goes to the bank, which moves their
## rating and pays its scrip (`RaceLeague.apply`).
##
## Ghosts: the authority records every person's lap as it is driven
## (`Run.recording`, a `RaceGhost`), and a counted lap faster than the
## racer's best on that track and machine goes to the bank
## (`LeagueBank.keep_ghost`: the account online, a file solo) and back to
## the racer (`ghost_kept`). Which ghost a racer chases is theirs to pick on
## the race icon (`GHOST_PICKS`: their own best, a friend's, the board
## leader's, or none); `want_ghost` asks for it (solo the bank, online the
## server, who knows each racer's friends) and `take_ghost` keeps the
## answer for `RaceView` to play. Friends' best laps come the same way
## (`friend_bests`) for the pit boards.
##
## Getting on and off made easy (Caleb's ask): race control's desks (map
## markers in group "race_desk", metas "track" and "machine") put whoever
## uses one straight onto the grid of that track's next race on a fresh
## machine (`sign_up`, asked as "signup:<track>:<machine>"); the watch desk
## (no machine) is `RaceView`'s, a view of the racers. Once a person's run
## is done, they are guided into the pits (the track's `RaceTrack.pit`, a
## waypoint on their HUD) and set down on pit row when they drive within
## `PIT_RADIUS` of it, or after `PIT_TIME` wherever they are; the machine
## goes (a bay fills again by itself).
##
## A world may lay out several tracks (Meridian has Coilrun and Skyhook),
## each with its own pit bays, grid, gantry, gates and board. A run is on
## the track whose road the machine was nearest when it was got on
## (`track_near`), so a racer picks a track by walking to its pit row.
##
## Map contract, beyond `WorldDef`'s: a `race_track()` method returning the
## first `RaceTrack` and, with more than one, `race_tracks()` returning them
## all; "spawn_vehicle" markers for the bays, as in any world (the world's
## `roll_loot` names the machine each bay holds).

const Contracts := preload("res://core/economy/contracts.gd")
const RaceLeague := preload("res://core/race/race_league.gd")

## The lights over the line come on one every `LIGHT_STEP` seconds; when
## all `LIGHTS` are lit, they go out and the run goes.
const LIGHTS := 5
const LIGHT_STEP := 0.6
## Best laps kept on each track's board.
const BOARD_SIZE := 8
## A racing machine resting this far under the track has fallen off it
## (into the Spillway's channel) and is put back (`_back_on_track`).
const FALLEN_DEPTH := 3.0
## A live race's grid: people first, AI racers in every slot left.
const GRID_SIZE := 8
## Seconds a race forms on the grid before it goes, and once it is full of
## people.
const FORM_TIME := 30.0
const FULL_FORM := 8.0
## Seconds the rest have to finish once the winner is home.
const FINISH_GRACE := 20.0
## Seconds the results stay up before the AI racers leave.
const RESULTS_TIME := 12.0
## Seconds added to a finish for each lap that left the track.
const OFF_TRACK_PENALTY := 3.0
## An AI racer stopped this long in a race is put back at the last
## checkpoint, as anyone down in a channel is (it costs it the time).
const AI_STUCK := 3.0
## The race radio: at most one line to a racer every `RADIO_GAP` seconds,
## and from one rival every `RIVAL_GAP`; nothing said in the first
## `RADIO_QUIET` seconds after the lights, while the field sorts itself out.
const RADIO_GAP := 5.0
const RIVAL_GAP := 20.0
const RADIO_QUIET := 4.0
## A finished racer is set down within this of the track's pit (metres)...
const PIT_RADIUS := 9.0
## ...or this long after their finish, wherever they are (seconds).
const PIT_TIME := 40.0
## How near a race control desk or a pit bench a person must stand to use it (metres).
const DESK_REACH := 3.0
## Getting off a machine further than this from its track's pit (metres)
## sets you down on pit row, so nobody is left walking the track.
const PIT_WALK := 60.0
## Every person in the world is on a forming grid: the lights come on this
## soon (seconds), so nobody waits half a minute for people who are not there.
const ALL_IN_FORM := 10.0
## Ambient races (Caleb's ask, so the world never feels dead): while anyone
## is in the world, the free track nearest them gets an AI-only race of
## `AMBIENT_FIELD` racers, the first `AMBIENT_FIRST` seconds after someone
## is there and the next `AMBIENT_GAP` after one closes. At most
## `AMBIENT_TRACKS` run at once: each AI racer's machine costs the server
## about as much as a bot (its move), so the count is kept small. One runs
## no longer than `AMBIENT_LIMIT`.
const AMBIENT_FIELD := 6
const AMBIENT_TRACKS := 1
const AMBIENT_FIRST := 8.0
const AMBIENT_GAP := 20.0
const AMBIENT_LIMIT := 600.0

## What the race icon's ghost pick turns through, in order.
const GHOST_PICKS: Array[String] = ["mine", "friend", "leader", "off"]
## Solo: where the profile's ghosts are kept (the same file older builds
## kept the view's ghosts in, read in either form).
const GHOST_PATH := "user://race_ghosts.json"

## Off turns ambient races off (the tests that want a quiet track).
static var ambient_races := true

## The callsigns of AI racers who are not named rivals.
const AI_NAMES: Array[String] = ["Vex Morrow", "Juno Kade", "Rook Halloran", "Sable Ito", "Dax Ferro",
		"Mika Strand", "Tavi Okonkwo", "Wren Castell", "Bodhi Lark", "Ines Varga", "Cass Rennick", "Oto Brandt"]

## A racer's run changed: started, a gate, a lap, finished or retired.
signal run_changed(actor: Actor)
## A lap was finished. `counted` is false when it strayed off the track.
signal lap_finished(actor: Actor, lap_time: float, counted: bool)
signal board_changed
## A live race formed, started, changed its field or finished.
signal heat_changed
## A rival said `text` to `actor` over the race radio.
signal radio(actor: Actor, from: String, text: String)
## A race moved `actor`'s league standing (sent to their bank).
signal league_changed(actor: Actor)
## A person's lap was kept as their best ghost (authority).
signal ghost_kept(actor: Actor, track_id: String, machine: String, ghost: RaceGhost)
## A ghost asked for with `want_ghost` came (or came back empty).
signal ghost_changed
## Online server: a racer's friends' best laps should be sent again.
signal bests_changed

## The first track, and every track the map lays out (`circuits`; `tracks`
## is the `Raid`'s footprints).
var track: RaceTrack
var circuits: Array[RaceTrack] = []
## Actor -> Run, on the authority.
var runs := {}
## The best laps: [{"name", "machine", "time", "track"}], fastest first,
## at most `BOARD_SIZE` per track (`board_for`).
var board: Array[Dictionary] = []
## Online client: the local player's run, as the server last sent it, and
## the local time it arrived (`Time.get_ticks_msec`).
var remote_run := {}
var remote_at := 0
## Track id -> Heat: each track's live race, forming, running or showing
## its results. Authority only; clients get `remote_heats`.
var heats := {}
## Online client: each track's race as the server last sent it
## (`heat_view`), with "made" the local time it arrived.
var remote_heats := {}
## Where each racer's league standing is kept and their results go. None
## (as in most tests): every grid is a rookie one and nothing is recorded.
var league_bank: LeagueBank
## Actor -> RaceDriver, the AI racers on the authority.
var drivers := {}
var _ai_made := 0
## Online client: sends a request (`request`'s action) to the server.
var send_request: Callable
## Online client: asks the server for a ghost (pick, track id, machine).
var send_ghost_ask: Callable
## "pick|track|machine" -> the ghost asked for: {"name", "machine", "lap",
## "ghost": RaceGhost}, {} when there is none, {"waiting": true} until it
## comes (`want_ghost`, `take_ghost`). The local racer's only.
var ghosts := {}
## The local racer's friends' best laps: [{"name", "track", "machine",
## "time"}], fastest first (online only; solo has no friends).
## Kits fitted this session, ahead of the bank catching up (authority):
## owner key -> machine -> kit.
var _tunes := {}
var friend_bests: Array = []
var _leaders := {}
## Seconds until the next ambient race may form.
var _ambient_wait := AMBIENT_FIRST


class Run:
	extends RefCounted
	var actor: Actor
	var vehicle: Node3D
	var track: RaceTrack
	var machine := ""
	## "grid" (held for the lights), "racing", "done".
	var phase := "grid"
	var go_at := 0.0
	var lap := 1
	## The next gate to pass (0 is the line).
	var next_gate := 1
	var lap_start := 0.0
	var last_pos := Vector3.ZERO
	var hint := -1
	## Still counts: has not strayed off the track this lap.
	var clean := true
	## Race clock time at each gate this lap, and on the best lap.
	var splits: Array[float] = []
	var best_splits: Array[float] = []
	## The last gate passed this lap and its time against the best lap's.
	var last_gate := -1
	var last_delta := NAN
	var last_lap := -1.0
	var best_lap := -1.0
	var total := -1.0
	var slot := 0
	## The live race this run is in, or null for a time trial.
	var heat: Heat
	## Driven by a `RaceDriver`, not a person.
	var ai := false
	## Place in the race now, and at the finish (0: none yet).
	var place := 0
	var finish_place := 0
	## Laps that left the track, each `OFF_TRACK_PENALTY` on the finish.
	var off_laps := 0
	## Seconds an AI racer has been stopped, racing (`AI_STUCK`).
	var stuck_for := 0.0
	## The racer's owner key (`Raid.PlayerState.owner`), for the league.
	var key := ""
	## An AI racer who is a named rival (`RaceLeague.RIVALS`).
	var rival := ""
	## The race radio: when this racer last heard a line, and from whom.
	var radio_at := -INF
	var heard := {}
	## The lap being driven, as a ghost (people only, authority).
	var recording := RaceGhost.new()
	## When the run was done (race clock), for the way into the pits.
	var done_at := 0.0
	## The machine was made for this run at a desk (`sign_up`).
	var desk_made := false
	## The tuning kit fitted for this run (`RaceLeague.KITS`; people only).
	var kit := "stock"


## One track's live race.
class Heat:
	extends RefCounted
	var track: RaceTrack
	## "forming" (on the grid, waiting for racers), "racing", "done".
	var phase := "forming"
	var starts_at := 0.0
	## Set once the winner is home: when the rest are out of time.
	var ends_at := INF
	## When the results come down and the AI racers leave.
	var closes_at := INF
	var runs: Array[Run] = []
	## The league whose rivals and skill fill the grid (`RaceLeague`).
	var league := 0
	## An AI-only race run so the track is never empty (`ambient_races`):
	## nobody's league moves, and a person asking to race calls its field
	## back to the grid (`_call_to_grid`).
	var ambient := false
	## How many slots the AI fill up to.
	var field := GRID_SIZE
	## When the lights went out.
	var started_at := 0.0
	## Once done: [{"name", "machine", "time", "place", "ai", "penalty"}],
	## first place first; "time" is -1 for a racer who did not finish.
	var results: Array[Dictionary] = []

	func people() -> int:
		return runs.filter(func(r: Run) -> bool: return not r.ai).size()


## Where racers' league standings and best-lap ghosts are kept: nothing
## here (every racer a fresh rookie, nothing recorded). Keys are owner keys.
class LeagueBank:
	extends RefCounted

	func state(_key: String) -> Dictionary:
		return RaceLeague.fresh()

	## `result` is `RaceLeague.clean_result`'s; the bank applies it.
	func record(_key: String, _result: Dictionary) -> void:
		pass

	## The racer's best lap on a track and machine, or -1.
	func best(key: String, track_id: String, machine: String) -> float:
		return RaceLeague.best_lap(state(key), track_id, machine)

	## Keeps `ghost` as the racer's best there (its `lap_time` is the lap's).
	func keep_ghost(_key: String, _track_id: String, _machine: String, _ghost: RaceGhost) -> void:
		pass

	## The fastest ghost kept among `keys` on a track (on `machine`, any
	## with none), as `StashService.race_ghost` answers. Solo only: the
	## server asks its accounts, awaited.
	func ghost_of(_keys: Array, _track_id: String, _machine: String) -> Dictionary:
		return {"ok": false}

	## Fits `kit` to the racer's `machine` (`RaceLeague.set_kit`, checked first).
	func tune(_key: String, _machine: String, _kit: String) -> void:
		pass


## Solo: the local profile, and its ghosts in `GHOST_PATH`.
class ProfileLeagueBank:
	extends LeagueBank

	## Track id -> machine -> {"lap", "ghost": packed}.
	var _kept := {}
	var _loaded := false

	func state(_key: String) -> Dictionary:
		return RaceLeague.clean(Profile.racing)

	func record(_key: String, result: Dictionary) -> void:
		Profile.record_race(result)

	func tune(_key: String, machine: String, kit: String) -> void:
		Profile.tune_race(machine, kit)

	func best(_key: String, track_id: String, machine: String) -> float:
		load_kept()
		return RaceLeague.best_lap(Profile.racing, track_id, machine)

	func keep_ghost(_key: String, track_id: String, machine: String, ghost: RaceGhost) -> void:
		load_kept()
		if not Profile.keep_race_best(track_id, machine, ghost.lap_time):
			return
		if not _kept.has(track_id):
			_kept[track_id] = {}
		_kept[track_id][machine] = {"lap": ghost.lap_time, "ghost": ghost.to_packed()}
		if Profile.persist:
			var file := FileAccess.open(GHOST_PATH, FileAccess.WRITE)
			if file != null:
				file.store_string(JSON.stringify(_kept))

	func ghost_of(_keys: Array, track_id: String, machine: String) -> Dictionary:
		load_kept()
		var on := machine if machine != "" else RaceLeague.best_machine(Profile.racing, track_id)
		var kept: Dictionary = _kept.get(track_id, {}).get(on, {})
		if kept.is_empty():
			return {"ok": false}
		return {"ok": true, "name": Profile.player_name, "machine": on, "lap": float(kept.lap),
				"ghost": str(kept.ghost)}

	## The ghosts on disk, older builds' too, with their laps noted as the
	## profile's bests.
	func load_kept() -> void:
		if _loaded:
			return
		_loaded = true
		if not FileAccess.file_exists(GHOST_PATH):
			return
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(GHOST_PATH))
		if not data is Dictionary:
			return
		for track_id: Variant in data:
			if not data[track_id] is Dictionary:
				continue
			for machine: Variant in data[track_id]:
				var entry: Variant = data[track_id][machine]
				var ghost: RaceGhost = null
				if entry is Dictionary and entry.has("ghost"):
					ghost = RaceGhost.from_packed(entry.ghost, str(machine), float(entry.get("lap", -1.0)))
				else:
					ghost = RaceGhost.from_data(entry)
				if ghost == null or ghost.lap_time <= 0.0:
					continue
				if not _kept.has(str(track_id)):
					_kept[str(track_id)] = {}
				_kept[str(track_id)][str(machine)] = {"lap": ghost.lap_time, "ghost": ghost.to_packed()}
				RaceLeague.note_best(Profile.racing, str(track_id), str(machine), ghost.lap_time)


## Server: the accounts a `StashService` (or an `AccountLink`) keeps.
class StashLeagueBank:
	extends LeagueBank

	var service: Object

	func _init(p_service: Object) -> void:
		service = p_service

	func state(key: String) -> Dictionary:
		var snapshot: Dictionary = service.snapshot(key)
		return RaceLeague.clean(snapshot.get("racing", {}))

	func record(key: String, result: Dictionary) -> void:
		service.record_race(key, result)

	func tune(key: String, machine: String, kit: String) -> void:
		service.tune_race(key, machine, kit)

	func keep_ghost(key: String, track_id: String, machine: String, ghost: RaceGhost) -> void:
		service.keep_ghost(key, track_id, machine, ghost.lap_time, ghost.to_packed())


# --- Setting up ---------------------------------------------------------------

func _setup(p_world: WorldDef, p_seed: int) -> void:
	super(p_world, p_seed)
	if map != null and map.has_method("race_tracks"):
		circuits.assign(map.call("race_tracks"))
	elif map != null and map.has_method("race_track"):
		circuits.assign([map.call("race_track")])
	if not circuits.is_empty():
		track = circuits[0]


## The track with id `id`, or the first.
func track_by_id(id: String) -> RaceTrack:
	for t in circuits:
		if t.id == id:
			return t
	return track


## The track whose road runs nearest `pos`, height counted.
func track_near(pos: Vector3) -> RaceTrack:
	var best := track
	var best_d := INF
	for t in circuits:
		var i := t.locate(pos)
		if i < 0:
			continue
		var d := t.points[i].distance_to(pos)
		if d < best_d:
			best_d = d
			best = t
	return best


## Every machine here is a stock one: its race profile replaces its tuning.
func spawn_vehicle(id: String, at: Vector3, heading: float, unpacking := false) -> Node3D:
	var vehicle := super(id, at, heading, unpacking)
	vehicle.call("apply_race_profile")
	if mode != Mode.CLIENT:
		vehicle.connect("dismounted", _on_vehicle_dismounted.bind(vehicle))
	return vehicle


func add_player(p_kit: Array = [], p_mastery: Dictionary = {}, p_name := "Raider",
		p_owner := "", p_renown := 0, p_drop := "", _p_insured := "") -> Actor:
	# Nothing of your own rides here: the machines are the track's.
	var kit: Array[String] = []
	for id: String in (p_kit if not p_kit.is_empty() else world.starter_loadout()):
		if id == Loadout.BARE or not (ItemDB.has_tag(id, "vehicle") or ItemDB.has_tag(id, "heal")):
			kit.append(id)
	if kit.is_empty():
		kit.append(Loadout.BARE)
	return super(kit, p_mastery, p_name, p_owner, p_renown, p_drop)


# --- Running ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	super(delta)
	if world == null or track == null:
		return
	if mode == Mode.CLIENT:
		_hold_remote()
		return
	_keep_racers_safe()
	for actor: Actor in runs.keys():
		_tick_run(runs[actor], delta)
	_tick_heats(delta)
	_tick_ambient(delta)


func _on_vehicle_mounted(actor: Actor, vehicle: Node3D) -> void:
	super(actor, vehicle)
	if mode == Mode.CLIENT or track == null or vehicle.get("rider") != actor or state_for(actor) == null:
		return
	start_run(actor, vehicle)


func _on_vehicle_dismounted(actor: Actor, vehicle: Node3D) -> void:
	var run: Run = runs.get(actor)
	if run != null and run.vehicle == vehicle:
		retire(actor)
		if not run.ai:
			# Once the getting off is done: back to pit row if it was out on
			# the track, and a desk's machine goes.
			_off_machine.call_deferred(actor.get_instance_id(), vehicle.get_instance_id(), run.track.id,
					run.desk_made)


## A person got off their run's machine (Caleb's ask: never left out on the
## track). Further than `PIT_WALK` from the pit they are set down on pit row
## and the machine goes (a bay fills again by itself); a desk's machine
## goes wherever they got off.
func _off_machine(actor_id: int, vehicle_id: int, track_id: String, desk_made: bool) -> void:
	var actor := instance_from_id(actor_id) as Actor
	var vehicle := instance_from_id(vehicle_id) as Node3D
	var far := false
	if is_instance_valid(actor) and not actor.is_dead and actor.vehicle == null:
		var pit := track_by_id(track_id).pit_spot()
		far = Vector2(actor.global_position.x - pit.x, actor.global_position.z - pit.z).length() > PIT_WALK
		if far:
			actor.velocity = Vector3.ZERO
			actor.global_position = _stand(pit + Vector3(0, 0.3, 0))
			actor.notice.emit("On pit row · take a machine or sign up at race control")
	if is_instance_valid(vehicle) and vehicle.get("rider") == null and (desk_made or far):
		remove_vehicle(vehicle)


## Puts `actor`, riding `vehicle`, on a free start slot, held for the lights.
func start_run(actor: Actor, vehicle: Node3D) -> void:
	var run := Run.new()
	run.actor = actor
	run.vehicle = vehicle
	run.machine = str(vehicle.get("item_id"))
	run.track = track_near(vehicle.global_position)
	var state := state_for(actor)
	run.key = state.owner if state != null else ""
	var old: Run = runs.get(actor)
	if old != null and old.track == run.track and old.machine == run.machine:
		run.best_lap = old.best_lap
		run.best_splits = old.best_splits
	runs[actor] = run
	run.kit = kit_for(run.key, run.machine)
	fit(vehicle, run.kit)
	var heat: Heat = heats.get(run.track.id)
	if heat != null and heat.phase == "forming" and heat.people() < GRID_SIZE:
		_join(run, heat)
		return
	_to_grid(run)
	actor.notice.emit("Time trial · %s · %d laps" % [run.track.display_name, run.track.laps])


func _to_grid(run: Run) -> void:
	var rt := run.track
	var taken := {}
	for other: Run in runs.values():
		if other != run and other.phase in ["grid", "waiting"] and other.track == rt:
			taken[other.slot] = true
	run.slot = 0
	while taken.has(run.slot) and run.slot < rt.start_slots.size() - 1:
		run.slot += 1
	var at: Transform3D = rt.start_slots[run.slot]
	var vehicle := run.vehicle
	vehicle.global_position = at.origin + Vector3(0, 0.4, 0)
	vehicle.set("heading", at.basis.get_euler().y)
	vehicle.rotation = Vector3(0, at.basis.get_euler().y, 0)
	vehicle.set("speed", 0.0)
	vehicle.set("velocity", Vector3.ZERO)
	vehicle.set("held", true)
	run.heat = null
	run.place = 0
	run.finish_place = 0
	run.off_laps = 0
	run.phase = "grid"
	run.go_at = clock + LIGHTS * LIGHT_STEP
	run.lap = 1
	run.next_gate = 1
	run.clean = true
	run.splits.clear()
	run.last_gate = -1
	run.last_delta = NAN
	run.last_lap = -1.0
	run.total = -1.0
	run.recording.clear()
	run.last_pos = vehicle.global_position
	run.hint = rt.locate(run.last_pos)
	run_changed.emit(run.actor)


func _tick_run(run: Run, _delta: float) -> void:
	var rt := run.track
	var vehicle := run.vehicle
	if not is_instance_valid(vehicle) or not is_instance_valid(run.actor) or run.actor.is_dead:
		retire(run.actor)
		return
	var pos: Vector3 = vehicle.global_position
	if run.phase == "waiting":
		run.last_pos = pos
		return
	if run.phase == "grid":
		if clock >= run.go_at:
			run.phase = "racing"
			run.lap_start = run.go_at
			vehicle.set("held", false)
			run_changed.emit(run.actor)
		run.last_pos = pos
		return
	var from := run.last_pos
	run.last_pos = pos
	run.hint = rt.locate(pos, run.hint)
	if run.phase == "done" and not run.ai:
		_tick_pit_in(run, pos)
		return
	if run.phase != "racing":
		return
	if not run.ai:
		run.recording.record(clock - run.lap_start, pos, vehicle.global_rotation.y)
	if run.clean and rt.is_off_track(pos, run.hint):
		run.clean = false
		run.actor.notice.emit("Off the track: this lap will not count" if run.heat == null
				else "Off the track: %d s on your finish" % int(OFF_TRACK_PENALTY))
		run_changed.emit(run.actor)
		if run.heat != null and not run.ai:
			_rival_says(run, _nearest_rival(run), "off")
	var t := rt.cross(run.next_gate, from, pos)
	if t < 0.0:
		return
	# The moment it went through, between the last tick and this one.
	var at := clock - get_physics_process_delta_time() * (1.0 - t)
	if run.next_gate != 0:
		run.splits.append(at - run.lap_start)
		run.last_gate = run.next_gate
		var i := run.splits.size() - 1
		run.last_delta = run.splits[i] - run.best_splits[i] if i < run.best_splits.size() else NAN
		run.next_gate = (run.next_gate + 1) % rt.gates.size()
		run_changed.emit(run.actor)
		return
	_finish_lap(run, at)


func _finish_lap(run: Run, at: float) -> void:
	var lap_time := at - run.lap_start
	run.splits.append(lap_time)
	run.last_lap = lap_time
	run.last_gate = 0
	var i := run.splits.size() - 1
	run.last_delta = run.splits[i] - run.best_splits[i] if i < run.best_splits.size() else NAN
	var counted := run.clean
	if not counted and run.heat != null:
		run.off_laps += 1
	if counted and (run.best_lap < 0.0 or lap_time < run.best_lap):
		run.best_lap = lap_time
		run.best_splits = run.splits.duplicate()
		var state := state_for(run.actor)
		# An AI racer's laps are not people's times.
		if not run.ai:
			add_record(run.actor.display_name, run.machine, lap_time, state.owner if state != null else "", run.track.id)
	if counted and not run.ai:
		_keep_ghost(run, lap_time)
	run.recording = RaceGhost.new()
	lap_finished.emit(run.actor, lap_time, counted)
	run.splits.clear()
	run.clean = true
	run.lap_start = at
	run.next_gate = 1
	if run.lap >= run.track.laps:
		run.phase = "done"
		run.done_at = clock
		run.total = at - run.go_at
		if run.heat != null:
			_finished_in_heat(run)
		else:
			run.actor.notice.emit("Finished in %s" % format_time(run.total))
	else:
		run.lap += 1
	run_changed.emit(run.actor)


## A person's counted lap: kept as their ghost if it beats their best there.
func _keep_ghost(run: Run, lap_time: float) -> void:
	var ghost := run.recording
	if league_bank == null or ghost.samples() < 10:
		return
	var best := league_bank.best(run.key, run.track.id, run.machine)
	if best > 0.0 and best <= lap_time:
		return
	ghost.machine = run.machine
	ghost.lap_time = lap_time
	league_bank.keep_ghost(run.key, run.track.id, run.machine, ghost)
	ghost_kept.emit(run.actor, run.track.id, run.machine, ghost)
	bests_changed.emit()
	if run.actor == player:
		take_ghost("mine", run.track.id, run.machine, {"ok": true, "name": run.actor.display_name,
				"machine": run.machine, "lap": lap_time, "ghost": ghost})


## A person's run is done: once they drive into the pits (or the time for
## it is up) they are set down on pit row and the machine goes.
func _tick_pit_in(run: Run, pos: Vector3) -> void:
	var pit := run.track.pit_spot()
	var near := Vector2(pos.x - pit.x, pos.z - pit.z).length() <= PIT_RADIUS and absf(pos.y - pit.y) < 6.0
	if near or clock - run.done_at >= PIT_TIME:
		set_down(run.actor, not near)


## Takes `actor` off their machine and out of their run, standing on pit row
## (`to_pit`: put there; else where they got off), and the machine goes.
func set_down(actor: Actor, to_pit := true) -> void:
	var run: Run = runs.get(actor)
	if run == null:
		return
	var vehicle := run.vehicle
	var pit := run.track.pit_spot()
	retire(actor)
	if is_instance_valid(vehicle):
		if vehicle.get("rider") == actor:
			vehicle.call("dismount")
		remove_vehicle(vehicle)
	if is_instance_valid(actor):
		if to_pit:
			actor.velocity = Vector3.ZERO
			actor.global_position = _stand(pit + Vector3(0, 0.3, 0))
		actor.notice.emit("On pit row · take a machine or sign up at race control")


## Ends `actor`'s run: they keep their machine until they get off it, and
## nothing more is timed.
func retire(actor: Actor) -> void:
	var run: Run = runs.get(actor)
	if run == null:
		return
	runs.erase(actor)
	if run.heat != null and run.phase != "done":
		# Out of the race: a racer who did not finish.
		run.phase = "retired"
		heat_changed.emit()
	if is_instance_valid(run.vehicle):
		run.vehicle.set("held", false)
		if run.kit != "stock":
			fit(run.vehicle, "stock")
	if is_instance_valid(actor):
		run_changed.emit(actor)


## A racer asks for something: "restart" (back to the grid on the same
## machine) or "retire" (stop the run and get off). Returns {"ok"} or
## {"ok": false, "error"}. Online only the server's own copy decides.
func request(actor: Actor, action: String) -> Dictionary:
	if mode == Mode.CLIENT:
		if send_request.is_valid():
			send_request.call(action)
		return {"ok": true}
	var run: Run = runs.get(actor)
	if action.begins_with("tune:"):
		return tune(actor, action.substr(5))
	if action.begins_with("signup:"):
		var parts := action.split(":")
		if parts.size() != 3:
			return {"ok": false, "error": "Unknown request"}
		return sign_up(actor, parts[1], parts[2])
	match action:
		"race":
			return join_race(actor)
		"restart":
			if run == null:
				var vehicle: Node3D = actor.vehicle
				if vehicle == null or vehicle.get("rider") != actor:
					return {"ok": false, "error": "Get on a machine in the pit bays first"}
				start_run(actor, vehicle)
				return {"ok": true}
			# Out of a live race and back to a time trial.
			_leave_heat(run)
			_to_grid(run)
			return {"ok": true}
		"retire":
			if run == null:
				return {"ok": false, "error": "No run to stop"}
			var vehicle := run.vehicle
			if is_instance_valid(vehicle) and vehicle.get("rider") == actor:
				# Getting off ends the run and, out on the track, sets you
				# down on pit row (`_off_machine`).
				vehicle.call("dismount")
			else:
				retire(actor)
			return {"ok": true}
	return {"ok": false, "error": "Unknown request"}


## Asks for something as the local player: solo at once, online through
## the server.
func ask(action: String) -> void:
	if player == null or not is_instance_valid(player):
		return
	var result := request(player, action)
	if not result.get("ok", false):
		player.notice.emit(str(result.get("error", "")))


## Keeps a record on a track's board (the first track's when `track_id` is
## empty): the best lap per racer and machine.
func add_record(racer: String, machine: String, time: float, key := "", track_id := "") -> void:
	var who := key if key != "" else racer
	var on := track_id if track_id != "" else (track.id if track != null else "")
	for entry in board:
		if entry.track == on and entry.get("key", entry.name) == who and entry.machine == machine:
			if time >= float(entry.time):
				return
			board.erase(entry)
			break
	board.append({"name": racer, "machine": machine, "time": time, "key": who, "track": on})
	board.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.time) < float(b.time))
	var kept: Array[Dictionary] = []
	var counts := {}
	for entry in board:
		counts[entry.track] = int(counts.get(entry.track, 0)) + 1
		if counts[entry.track] <= BOARD_SIZE:
			kept.append(entry)
	board = kept
	_forget_leader_ghosts()
	board_changed.emit()


## One track's best laps, fastest first.
func board_for(track_id: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for entry in board:
		if entry.track == track_id:
			rows.append(entry)
	return rows


## The board as sent to clients: no keys.
func public_board() -> Array:
	return board.map(func(e: Dictionary) -> Dictionary:
		return {"name": e.name, "machine": e.machine, "time": e.time, "track": e.track})


## Nobody here can be hurt or fall out of the world, and weapons stay
## locked. Riders off a machine walk back to the pits.
func _keep_racers_safe() -> void:
	for state in players:
		var actor := state.actor
		if not is_instance_valid(actor) or actor.is_dead:
			continue
		actor.weapons_locked = true
		actor.health.health = actor.health.max_health
		if actor.global_position.y < -20.0 and actor.vehicle == null:
			var spawns := _map_nodes("spawn_player")
			actor.velocity = Vector3.ZERO
			actor.global_position = spawns[0].global_position if not spawns.is_empty() else Vector3(0, 2, 0)
	for actor: Actor in runs.keys():
		var run: Run = runs[actor]
		if not is_instance_valid(run.vehicle):
			continue
		var pos: Vector3 = run.vehicle.global_position
		if pos.y < -20.0:
			# Fell off the world: back to the grid, or on in a race.
			if run.heat != null and run.phase in ["racing", "done"]:
				_back_on_track(run)
			elif run.heat == null:
				_to_grid(run)
		elif run.phase == "racing" and run.hint >= 0 and pos.y < run.track.points[run.hint].y - FALLEN_DEPTH \
				and run.vehicle.get("airborne_time") == 0.0:
			# Down in a channel or a pit with no way out: back on the track at
			# the last gate passed, stopped. The clock keeps running.
			_back_on_track(run)


## Puts a run's machine back on the track just past the last gate it
## passed, facing down the track and stopped.
func _back_on_track(run: Run) -> void:
	var rt := run.track
	var g: Dictionary = rt.gates[(run.next_gate - 1 + rt.gates.size()) % rt.gates.size()]
	var at: Vector3 = g.at + g.forward * 3.0 + Vector3(0, 0.5, 0)
	var vehicle := run.vehicle
	var yaw := rt.heading(int(g.index))
	vehicle.global_position = at
	vehicle.set("heading", yaw)
	vehicle.rotation = Vector3(0, yaw, 0)
	vehicle.set("speed", 0.0)
	vehicle.set("slip", 0.0)
	vehicle.set("velocity", Vector3.ZERO)
	run.last_pos = at
	run.hint = int(g.index)
	run.actor.notice.emit("Back on the track at the last checkpoint")
	run_changed.emit(run.actor)


## Online client: the run the server sent holds the local rider's machine
## for the lights, the same as the server does.
func _hold_remote() -> void:
	if player == null or not is_instance_valid(player) or player.vehicle == null:
		return
	var phase := str(remote_run.get("phase", ""))
	var held := phase == "waiting" or (phase == "grid" and run_go_in(remote_run) > 0.0)
	player.vehicle.set("held", held)


# --- Live races -----------------------------------------------------------------

## `actor`, on a machine, asks to race: they join the track's race forming
## on the grid, or start one. Returns {"ok"} or {"ok": false, "error"}.
func join_race(actor: Actor) -> Dictionary:
	var run: Run = runs.get(actor)
	if run == null:
		var vehicle: Node3D = actor.vehicle
		if vehicle == null or vehicle.get("rider") != actor:
			return {"ok": false, "error": "Get on a machine in the pit bays first"}
		start_run(actor, vehicle)
		run = runs.get(actor)
		if run == null:
			return {"ok": false, "error": "No machine to race"}
	if run.heat != null and run.heat.phase in ["forming", "racing"] and not run.heat.ambient:
		return {"ok": true}
	var heat: Heat = heats.get(run.track.id)
	if heat != null and heat.ambient:
		# The AI's own race: its field comes back to the grid to race you.
		_call_to_grid(heat)
	if heat != null and heat.phase == "racing":
		return {"ok": false, "error": "A race is running here: the next forms once it is over"}
	if heat != null and heat.phase == "forming" and heat.people() >= GRID_SIZE:
		return {"ok": false, "error": "The grid is full"}
	if heat == null or heat.phase == "done":
		if heat != null:
			_close_out(heat)
		heat = Heat.new()
		heat.track = run.track
		heat.starts_at = clock + FORM_TIME
		heats[run.track.id] = heat
	_join(run, heat)
	return {"ok": true}


# --- Tuning ---------------------------------------------------------------------

## Sets `vehicle` to its race profile with `kit` fitted (`RaceLeague.tuned`).
## Every machine reads as stock unless a person's run fits a kit.
static func fit(vehicle: Node3D, kit: String) -> void:
	if not is_instance_valid(vehicle):
		return
	vehicle.call("apply_race_profile")
	if kit == "stock" or not RaceLeague.KITS.has(kit):
		return
	var profile := RaceLeague.tuned(vehicle.get("race"), kit)
	for stat: String in profile:
		if stat in vehicle:
			vehicle.set(stat, profile[stat])


## A racer's league state with this session's fitted kits over the bank's.
func tune_state(key: String) -> Dictionary:
	var state := league_bank.state(key) if league_bank != null else RaceLeague.fresh()
	var fitted: Dictionary = _tunes.get(key, {})
	for machine: String in fitted:
		RaceLeague.set_kit(state, machine, fitted[machine])
	return state


## The kit on a racer's machine (no AI or nameless racer has one).
func kit_for(key: String, machine: String) -> String:
	if key == "" or league_bank == null:
		return "stock"
	return RaceLeague.kit_of(tune_state(key), machine)


## The pit bench for `machine` that `actor` stands at, or null.
func bench_near(actor: Actor, machine: String) -> Node3D:
	if map == null:
		return null
	for node: Node in _map_nodes("race_tune"):
		var bench := node as Node3D
		if bench != null and str(bench.get_meta("machine", "")) == machine \
				and Vector2(bench.global_position.x - actor.global_position.x,
						bench.global_position.z - actor.global_position.z).length() <= DESK_REACH:
			return bench
	return null


## The pit bench: fits the next kit the racer's league has unlocked to
## their `machine` (round to stock), kept on their account. A machine on
## the grid takes it at once; one racing keeps its kit to the flag.
func tune(actor: Actor, machine: String) -> Dictionary:
	var state := state_for(actor)
	if state == null or league_bank == null:
		return {"ok": false, "error": "No tuning here"}
	if bench_near(actor, machine) == null:
		return {"ok": false, "error": "Tune a machine at its bench in the pits"}
	var key: String = state.owner
	var league := tune_state(key)
	var kits := RaceLeague.kits_for(league)
	if kits.size() < 2:
		return {"ok": false, "error": "Tuning kits open from the %s league" % RaceLeague.league_name(1)}
	var kit := RaceLeague.next_kit(league, machine)
	if not _tunes.has(key):
		_tunes[key] = {}
	_tunes[key][machine] = kit
	league_bank.tune(key, machine, kit)
	var run: Run = runs.get(actor)
	if run != null and run.machine == machine and run.phase in ["grid", "waiting"]:
		run.kit = kit
		fit(run.vehicle, kit)
		run_changed.emit(actor)
	actor.notice.emit("%s · %s · %s" % [ItemDB.item_name(machine), RaceLeague.kit_name(kit),
			str(RaceLeague.KITS[kit].about)])
	return {"ok": true, "kit": kit}


## The race control desk for a track and machine `actor` stands at, or null.
func desk_near(actor: Actor, track_id: String, machine: String) -> Node3D:
	if map == null:
		return null
	for node: Node in _map_nodes("race_desk"):
		var desk := node as Node3D
		if desk != null and str(desk.get_meta("track", "")) == track_id and str(desk.get_meta("machine", "")) == machine \
				and Vector2(desk.global_position.x - actor.global_position.x,
						desk.global_position.z - actor.global_position.z).length() <= DESK_REACH:
			return desk
	return null


## A desk at race control: `actor` goes straight onto the grid of the
## track's next race on a fresh `machine` (one of the track's own),
## leaving any run or machine they had. A race forms if none is.
func sign_up(actor: Actor, track_id: String, machine: String) -> Dictionary:
	var rt := track_by_id(track_id)
	if rt == null or rt.id != track_id or machine not in _class_machines(rt):
		return {"ok": false, "error": "No such race"}
	if desk_near(actor, track_id, machine) == null:
		return {"ok": false, "error": "Sign up at race control's desk"}
	var heat: Heat = heats.get(rt.id)
	if heat != null and heat.ambient:
		_call_to_grid(heat)
	if heat != null and heat.phase == "racing":
		return {"ok": false, "error": "%s's race is on: the next forms once it is over. Watch it from the desk beside" \
				% rt.display_name}
	if heat != null and heat.phase == "forming" and heat.people() >= GRID_SIZE:
		return {"ok": false, "error": "The grid is full"}
	var run: Run = runs.get(actor)
	if run != null and run.heat == heat and heat != null and heat.phase == "forming" and run.machine == machine:
		return {"ok": true}
	if actor.vehicle != null:
		# Off the old machine first (a desk's own goes as you get off).
		actor.vehicle.call("dismount")
	retire(actor)
	var slot: Transform3D = rt.start_slots[0]
	var vehicle := spawn_vehicle(machine, slot.origin + Vector3(0, 0.4, 0), slot.basis.get_euler().y)
	if not vehicle.call("mount", actor):
		remove_vehicle(vehicle)
		return {"ok": false, "error": "Could not get on"}
	run = runs.get(actor)
	if run == null:
		start_run(actor, vehicle)
		run = runs.get(actor)
	if run == null:
		return {"ok": false, "error": "No machine to race"}
	run.desk_made = true
	return join_race(actor)


## Puts `run` on `heat`'s grid, held at a free slot.
func _join(run: Run, heat: Heat) -> void:
	_leave_heat(run)
	var taken := {}
	for other: Run in heat.runs:
		taken[other.slot] = true
	var slots := mini(GRID_SIZE, run.track.start_slots.size())
	run.slot = 0
	while taken.has(run.slot) and run.slot < slots:
		run.slot += 1
	if run.slot >= slots:
		# A full grid: a person takes an AI racer's place.
		run.slot = _bump_ai(heat)
	heat.runs.append(run)
	run.heat = heat
	_place_at_slot(run)
	run.phase = "waiting"
	run.place = 0
	run.finish_place = 0
	run.off_laps = 0
	if heat.people() >= GRID_SIZE:
		heat.starts_at = minf(heat.starts_at, clock + FULL_FORM)
	# The AI take their places on the grid at once, so a forming race shows
	# its field (Caleb's "nothing happened").
	_fill_grid(heat)
	if not run.ai:
		run.actor.notice.emit("Race · %s · %d laps · starts in %s" % [heat.track.display_name, heat.track.laps,
				format_countdown(heat.starts_at - clock)])
	run_changed.emit(run.actor)
	heat_changed.emit()


## Takes `run` out of the race it is in, if one is still forming or
## running.
func _leave_heat(run: Run) -> void:
	var heat := run.heat
	if heat == null:
		return
	run.heat = null
	run.place = 0
	run.finish_place = 0
	if heat.phase == "forming":
		heat.runs.erase(run)
	heat_changed.emit()


## Sets a run's machine at its start slot, stopped and held.
func _place_at_slot(run: Run) -> void:
	var at: Transform3D = run.track.start_slots[mini(run.slot, run.track.start_slots.size() - 1)]
	var vehicle := run.vehicle
	var yaw := at.basis.get_euler().y
	vehicle.global_position = at.origin + Vector3(0, 0.4, 0)
	vehicle.set("heading", yaw)
	vehicle.rotation = Vector3(0, yaw, 0)
	vehicle.set("speed", 0.0)
	vehicle.set("slip", 0.0)
	vehicle.set("velocity", Vector3.ZERO)
	vehicle.set("held", true)
	run.last_pos = vehicle.global_position
	run.hint = run.track.locate(run.last_pos)


func _tick_heats(delta: float) -> void:
	for id: String in heats.keys():
		var heat: Heat = heats[id]
		match heat.phase:
			"forming":
				# Racers who got off or went: their slot is free again.
				var left := false
				for run: Run in heat.runs.duplicate():
					if run.heat != heat or not runs.has(run.actor):
						heat.runs.erase(run)
						left = true
				if heat.people() == 0:
					_end_heat(id)
					continue
				if left:
					_fill_grid(heat)
				if _all_on_grid(heat):
					heat.starts_at = minf(heat.starts_at, clock + ALL_IN_FORM)
				if clock >= heat.starts_at:
					_start_heat(heat)
			"racing":
				_drive_ai(heat, delta)
				_update_places(heat)
				var running := heat.runs.filter(func(r: Run) -> bool:
					return (heat.ambient or not r.ai) and r.phase in ["grid", "racing"] and r.heat == heat)
				if clock >= heat.ends_at or running.is_empty() \
						or (heat.ambient and clock - heat.started_at > AMBIENT_LIMIT):
					_close_heat(heat)
			"done":
				_drive_ai(heat, delta)
				if clock >= heat.closes_at:
					_end_heat(id)


## A track's race is over and gone: the AI leave, and the next ambient race
## there waits `AMBIENT_GAP`.
func _end_heat(id: String) -> void:
	var heat: Heat = heats.get(id)
	if heat != null:
		_close_out(heat)
	heats.erase(id)
	_ambient_wait = maxf(_ambient_wait, AMBIENT_GAP)
	heat_changed.emit()


## Whether every person in the world is on `heat`'s grid.
func _all_on_grid(heat: Heat) -> bool:
	var here := _people_here()
	if here.is_empty():
		return false
	for actor in here:
		var run: Run = runs.get(actor)
		if run == null or run.heat != heat:
			return false
	return true


## The people in the world, alive (never an AI racer).
func _people_here() -> Array[Actor]:
	var out: Array[Actor] = []
	for state in players:
		if is_instance_valid(state.actor) and not state.actor.is_dead and not is_ai_racer(state.actor):
			out.append(state.actor)
	return out


## The lights: AI racers take every slot left (the league's named rivals
## first), and everyone goes together.
func _start_heat(heat: Heat) -> void:
	_fill_grid(heat)
	heat.phase = "racing"
	var go := clock + LIGHTS * LIGHT_STEP
	heat.started_at = go
	for run: Run in heat.runs:
		if not is_instance_valid(run.vehicle):
			continue
		_place_at_slot(run)
		run.phase = "grid"
		run.go_at = go
		run.lap = 1
		run.next_gate = 1
		run.clean = true
		run.splits.clear()
		run.last_gate = -1
		run.last_delta = NAN
		run.last_lap = -1.0
		run.total = -1.0
		run.off_laps = 0
		run_changed.emit(run.actor)
	_update_places(heat)
	heat_changed.emit()
	# A rival on the grid says something to each person at the lights.
	var on_grid := heat.runs.filter(func(r: Run) -> bool: return r.rival != "")
	if not on_grid.is_empty():
		for run: Run in heat.runs:
			if not run.ai:
				_rival_says(run, on_grid[rng.randi() % on_grid.size()], "lights")


## AI racers take every empty slot of `heat`'s grid up to its `field`: the
## named rivals of its best person's league first (an ambient race keeps
## the league it was given), then others at that league's skill. Should a
## better rider join, the grid is filled again from their league.
func _fill_grid(heat: Heat) -> void:
	var league := heat.league
	if heat.people() > 0:
		league = 0
		for run: Run in heat.runs:
			if not run.ai:
				league = maxi(league, int(_league_state(run).league))
	if league != heat.league:
		for run: Run in heat.runs.duplicate():
			if run.ai:
				heat.runs.erase(run)
				_remove_ai(run)
		heat.league = league
	var taken := {}
	var rivals: Array = RaceLeague.rivals_in(heat.league).duplicate()
	for run: Run in heat.runs:
		taken[run.slot] = true
		rivals.erase(run.rival)
	var slots := mini(heat.field, heat.track.start_slots.size())
	var spread_rng := RandomNumberGenerator.new()
	spread_rng.seed = rng.randi()
	for slot in slots:
		if taken.has(slot):
			continue
		var run := _add_ai(heat, slot, spread_rng, str(rivals.pop_front()) if not rivals.is_empty() else "")
		if run == null:
			continue
		heat.runs.append(run)
		if heat.phase == "forming":
			_place_at_slot(run)
			run.phase = "waiting"
	heat_changed.emit()


## Takes an AI racer off a full grid for a person; returns the slot it
## leaves. The back of the grid goes first, a named rival last.
func _bump_ai(heat: Heat) -> int:
	var out: Run = null
	for run: Run in heat.runs:
		if run.ai and (out == null or (out.rival != "" and run.rival == "")
				or ((out.rival == "") == (run.rival == "") and run.slot > out.slot)):
			out = run
	if out == null:
		return heat.runs.size()
	heat.runs.erase(out)
	_remove_ai(out)
	return out.slot


## An ambient race becomes a real one: a person asked to race, so its AI
## racers come back to the grid, held, and the race forms for people.
func _call_to_grid(heat: Heat) -> void:
	heat.ambient = false
	heat.field = GRID_SIZE
	heat.phase = "forming"
	heat.starts_at = clock + FORM_TIME
	heat.ends_at = INF
	heat.closes_at = INF
	heat.results.clear()
	for run: Run in heat.runs.duplicate():
		if not run.ai or not is_instance_valid(run.vehicle) or not is_instance_valid(run.actor):
			heat.runs.erase(run)
			if run.ai:
				_remove_ai(run)
			continue
		run.heat = heat
		_place_at_slot(run)
		run.phase = "waiting"
		run.place = 0
		run.finish_place = 0
		run.off_laps = 0
		run.total = -1.0
		run.stuck_for = 0.0
	heat_changed.emit()


## Ambient races: while anyone is here, the track nearest them with no race
## and nobody riding it gets an AI-only race now and then, `AMBIENT_TRACKS`
## at a time. With nobody here, none run (a server pays nothing for an
## empty world).
func _tick_ambient(delta: float) -> void:
	var here := _people_here()
	var quiet := here.is_empty() or not ambient_races
	var running := 0
	for rt in circuits:
		var heat: Heat = heats.get(rt.id)
		if heat != null and heat.ambient:
			if quiet:
				_end_heat(rt.id)
			else:
				running += 1
	if quiet:
		_ambient_wait = maxf(_ambient_wait, AMBIENT_FIRST)
		return
	if running >= AMBIENT_TRACKS:
		return
	_ambient_wait -= delta
	if _ambient_wait > 0.0:
		return
	var best: RaceTrack = null
	var best_d := INF
	for rt in circuits:
		if heats.has(rt.id) or _track_ridden(rt):
			continue
		var pit := rt.pit_spot()
		for actor in here:
			var d := Vector2(actor.global_position.x - pit.x, actor.global_position.z - pit.z).length()
			if d < best_d:
				best_d = d
				best = rt
	if best != null:
		_start_ambient(best, here)


## Whether a person is riding a run on `rt` (no ambient race starts then).
func _track_ridden(rt: RaceTrack) -> bool:
	for run: Run in runs.values():
		if not run.ai and run.track == rt and run.phase in ["waiting", "grid", "racing"]:
			return true
	return false


## An AI-only race on `rt` at the league of the best person here.
func _start_ambient(rt: RaceTrack, here: Array[Actor]) -> void:
	var heat := Heat.new()
	heat.track = rt
	heat.ambient = true
	heat.field = mini(AMBIENT_FIELD, rt.start_slots.size())
	if league_bank != null:
		for actor in here:
			var state := state_for(actor)
			if state != null:
				heat.league = maxi(heat.league, int(league_bank.state(state.owner).get("league", 0)))
	heats[rt.id] = heat
	_start_heat(heat)


## An AI racer on a stock machine of the track's class at `slot`: the named
## rival `rival` (on the machine they favour), or another at the league's
## skill.
func _add_ai(heat: Heat, slot: int, spread_rng: RandomNumberGenerator, rival := "") -> Run:
	var machines := _class_machines(heat.track)
	if machines.is_empty():
		return null
	var callsign := RaceLeague.rival_name(rival) if rival != "" else _ai_name()
	var at: Transform3D = heat.track.start_slots[slot]
	var bot := spawn_bot("Racer%d" % _ai_made, at.origin + Vector3(2.0, 0.2, 0.0), spread_rng.randi(), false,
			"racer", -2, [Loadout.BARE])
	_ai_made += 1
	bot.display_name = callsign
	Look.set_appearance(bot, Human.for_name(callsign))
	bot.weapons_locked = true
	bot.set_meta("race_ai", true)
	actor_spawned.emit(bot)
	var machine: String = machines[spread_rng.randi() % machines.size()]
	if rival != "":
		var hover := str(RaceLeague.RIVALS[rival].machine) == "hover"
		for id in machines:
			if ItemDB.has_tag(id, "hover") == hover:
				machine = id
				break
	var vehicle := spawn_vehicle(machine, at.origin + Vector3(0, 0.4, 0), at.basis.get_euler().y)
	vehicle.call("mount", bot)
	var run := Run.new()
	run.actor = bot
	run.vehicle = vehicle
	run.track = heat.track
	run.machine = machine
	run.ai = true
	run.slot = slot
	run.heat = heat
	run.rival = rival
	runs[bot] = run
	var skill := RaceLeague.rival_skill(rival) if rival != "" \
			else clampf(RaceLeague.ai_skill(heat.league) + spread_rng.randf_range(-0.1, 0.04), 0.0, 1.0)
	drivers[bot] = RaceDriver.make(skill, spread_rng.randi())
	return run


## The machines that race `track`'s class: the ones in its pit bays.
func _class_machines(rt: RaceTrack) -> Array[String]:
	var out: Array[String] = []
	for v: Variant in vehicles:
		if not is_instance_valid(v):
			continue
		var id := str((v as Node3D).get("item_id"))
		if id != "" and id not in out and track_near((v as Node3D).global_position) == rt:
			out.append(id)
	out.sort()
	return out


## A callsign nobody here is using.
func _ai_name() -> String:
	var used := {}
	for actor: Variant in runs.keys():
		if is_instance_valid(actor):
			used[(actor as Actor).display_name] = true
	for state in players:
		if is_instance_valid(state.actor):
			used[state.actor.display_name] = true
	var start := _ai_made % AI_NAMES.size()
	for k in AI_NAMES.size():
		var callsign: String = AI_NAMES[(start + k) % AI_NAMES.size()]
		if not used.has(callsign):
			return callsign
	return "Racer %d" % (_ai_made + 1)


## Each AI racer of `heat` drives one tick. Home, it rolls on gently.
func _drive_ai(heat: Heat, delta: float) -> void:
	var machines: Array = []
	for run: Run in heat.runs:
		if is_instance_valid(run.vehicle):
			machines.append(run.vehicle)
	for run: Run in heat.runs:
		if not run.ai or not is_instance_valid(run.actor) or not is_instance_valid(run.vehicle):
			continue
		run.actor.thin(1)
		var driver: RaceDriver = drivers.get(run.actor)
		if driver == null:
			continue
		driver.drive(run.actor, run.vehicle, run.track, run.phase in ["racing", "done"], machines, delta)
		if run.phase == "racing" and absf(float(run.vehicle.get("speed"))) < 2.0:
			run.stuck_for += delta
			if run.stuck_for >= AI_STUCK:
				run.stuck_for = 0.0
				_back_on_track(run)
		else:
			run.stuck_for = 0.0
		if run.phase == "done":
			run.actor.cmd.move.y = minf(run.actor.cmd.move.y, 0.35)
			run.actor.cmd.sprint = false
			run.actor.cmd.jump = false


## How far round a run is, in metres from the line at the start: laps done,
## then the way along the centre line from the line, counted from the gates
## so a grid behind the line is a little under nothing.
func run_distance(run: Run) -> float:
	var rt := run.track
	var n := rt.points.size()
	var line_i := int(rt.gates[0].index)
	var hint := run.hint if run.hint >= 0 else rt.locate(run.last_pos)
	var along := posmod(hint - line_i, n)
	if run.next_gate == 1 and along > n * 3 / 4:
		along -= n
	elif run.next_gate == 0 and along < n / 4:
		along += n
	return ((run.lap - 1) * n + along) * RaceTrack.STEP


## Places in a running race: finishers in the order they came home, then
## everyone else by how far round they are.
func _update_places(heat: Heat) -> void:
	var home: Array[Run] = []
	var out: Array[Run] = []
	for run: Run in heat.runs:
		if run.phase == "done" and run.total >= 0.0:
			home.append(run)
		elif run.phase in ["grid", "racing"] and run.heat == heat:
			out.append(run)
	home.sort_custom(func(a: Run, b: Run) -> bool: return a.total < b.total)
	var far := {}
	for run in out:
		far[run] = run_distance(run)
	out.sort_custom(func(a: Run, b: Run) -> bool: return float(far[a]) > float(far[b]))
	var order := home + out
	var was := {}
	for run in order:
		was[run] = run.place
	for i in order.size():
		if order[i].place != i + 1:
			order[i].place = i + 1
			if not order[i].ai:
				run_changed.emit(order[i].actor)
	_radio_passes(order, was)


## The race radio on passes: a rival someone just got by, or who just got
## by them, says so.
func _radio_passes(order: Array[Run], was: Dictionary) -> void:
	for person in order:
		if person.ai or person.phase != "racing" or clock < person.go_at + RADIO_QUIET:
			continue
		var before := int(was.get(person, 0))
		if before == 0 or before == person.place:
			continue
		for rival in order:
			if rival.rival == "" or rival.phase != "racing":
				continue
			var then := int(was.get(rival, 0))
			if then == 0:
				continue
			if then < before and rival.place > person.place:
				_rival_says(person, rival, "pass")
				break
			if then > before and rival.place < person.place:
				_rival_says(person, rival, "passed")
				break


## `rival`'s line for `event` on `person`'s race radio, unless the radio was
## busy a moment ago (the lights and the finish always get through).
func _rival_says(person: Run, rival: Run, event: String) -> void:
	if rival == null or rival.rival == "" or person.ai or not is_instance_valid(person.actor):
		return
	var always := event in ["lights", "win", "beaten"]
	if not always and (clock - person.radio_at < RADIO_GAP
			or clock - float(person.heard.get(rival.rival, -INF)) < RIVAL_GAP):
		return
	var text := RaceLeague.line(rival.rival, event, person.actor.display_name, _league_state(person), rng.randi())
	if text == "":
		return
	person.radio_at = clock
	person.heard[rival.rival] = clock
	radio.emit(person.actor, RaceLeague.rival_name(rival.rival), text)


## The rival nearest `person` in the running order.
func _nearest_rival(person: Run) -> Run:
	if person.heat == null:
		return null
	var best: Run = null
	for other: Run in person.heat.runs:
		if other.rival != "" and (best == null or absi(other.place - person.place) < absi(best.place - person.place)):
			best = other
	return best


## A person's league standing, from the bank (a fresh rookie with none).
func _league_state(run: Run) -> Dictionary:
	return league_bank.state(run.key) if league_bank != null else RaceLeague.fresh()


## A racer in a live race crossed the line on their last lap.
func _finished_in_heat(run: Run) -> void:
	var heat := run.heat
	if heat.ends_at == INF:
		heat.ends_at = clock + FINISH_GRACE
		for other: Run in heat.runs:
			if other != run and not other.ai and other.phase == "racing":
				other.actor.notice.emit("%s won: %d s to finish" % [run.actor.display_name, int(FINISH_GRACE)])
	var penalty := run.off_laps * OFF_TRACK_PENALTY
	if not run.ai:
		run.actor.notice.emit("Home in %s%s" % [format_time(run.total),
				" · +%d s off the track" % int(penalty) if penalty > 0.0 else ""])
	heat_changed.emit()


## The race is over: the results, each finish with its penalty, then those
## who did not finish by how far round they got.
func _close_heat(heat: Heat) -> void:
	var home: Array[Run] = []
	var rest: Array[Run] = []
	for run: Run in heat.runs:
		if run.phase == "done" and run.total >= 0.0 and run.heat == heat:
			home.append(run)
		else:
			rest.append(run)
	var finish := func(r: Run) -> float: return r.total + r.off_laps * OFF_TRACK_PENALTY
	home.sort_custom(func(a: Run, b: Run) -> bool: return finish.call(a) < finish.call(b))
	var far := {}
	for run in rest:
		far[run] = run_distance(run) if run.phase == "racing" else -INF
	rest.sort_custom(func(a: Run, b: Run) -> bool: return float(far[a]) > float(far[b]))
	heat.results.clear()
	var order := home + rest
	for i in order.size():
		var run := order[i]
		var finished := home.has(run)
		heat.results.append({"name": run.actor.display_name if is_instance_valid(run.actor) else "?",
				"machine": run.machine, "time": finish.call(run) if finished else -1.0, "place": i + 1,
				"ai": run.ai, "penalty": run.off_laps * OFF_TRACK_PENALTY})
		if run.heat != heat:
			continue
		run.finish_place = i + 1
		run.place = i + 1
		if run.phase == "racing":
			# Out of time: the run ends where it is.
			run.phase = "done"
			run.done_at = clock
			run.total = -1.0
		if not run.ai and is_instance_valid(run.actor):
			run.actor.notice.emit("P%d of %d%s" % [i + 1, order.size(), "" if finished else " · did not finish"])
			run_changed.emit(run.actor)
	heat.phase = "done"
	heat.closes_at = clock + RESULTS_TIME
	heat_changed.emit()
	_record_heat(heat, order, home)


## Each person's finish goes to the league: who they beat and who beat
## them. Someone who left the race before the end counts as not finishing.
func _record_heat(heat: Heat, order: Array[Run], home: Array[Run]) -> void:
	for i in order.size():
		var run := order[i]
		if run.ai:
			continue
		var ahead: Array[String] = []
		var behind: Array[String] = []
		for j in order.size():
			if order[j].rival != "":
				(ahead if j < i else behind).append(order[j].rival)
		var finished := home.has(run) and run.heat == heat
		var result := {"track": heat.track.id, "place": i + 1, "field": order.size(), "finished": finished,
				"ahead": ahead, "behind": behind}
		_finish_talk(run, order, i, finished)
		if league_bank == null:
			continue
		var before := _league_state(run)
		var applied := RaceLeague.apply(before, result, Contracts.today())
		league_bank.record(run.key, result)
		if not is_instance_valid(run.actor):
			continue
		var now: Dictionary = applied.state
		var points := int(applied.points)
		var line := "%+d rating · %s" % [points, RaceLeague.standing_line(now)]
		if int(applied.scrip) > 0:
			line += " · +%d scrip" % int(applied.scrip)
		run.actor.notice.emit(line)
		if bool(applied.promoted):
			run.actor.notice.emit("Promoted to the %s league" % RaceLeague.league_name(int(now.league)))
		league_changed.emit(run.actor)


## The radio at the finish: the rival you beat (your league's top rival
## first) admits it, or the rival who won says so.
func _finish_talk(run: Run, order: Array[Run], at: int, finished: bool) -> void:
	if run.heat == null and not finished:
		return
	var top := RaceLeague.top_rival(int(_league_state(run).league))
	var beaten: Run = null
	if finished:
		for j in range(at + 1, order.size()):
			if order[j].rival != "" and (beaten == null or order[j].rival == top):
				beaten = order[j]
	if beaten != null:
		_rival_says(run, beaten, "beaten")
	elif order[0].rival != "":
		_rival_says(run, order[0], "win")


## The results come down: the AI racers leave with their machines, and
## the people's runs are time trials again.
func _close_out(heat: Heat) -> void:
	for run: Run in heat.runs:
		if run.ai:
			_remove_ai(run)
		elif run.heat == heat:
			run.heat = null
			run.place = 0
			if is_instance_valid(run.actor) and runs.has(run.actor):
				run_changed.emit(run.actor)
	heat.runs.clear()


func _remove_ai(run: Run) -> void:
	var bot := run.actor
	runs.erase(bot)
	drivers.erase(bot)
	var vehicle := run.vehicle
	if is_instance_valid(vehicle):
		vehicle.call("dismount")
	if is_instance_valid(bot):
		_remove_actor(bot)
	if is_instance_valid(vehicle):
		remove_vehicle(vehicle)


## Whether `actor` is an AI racer.
func is_ai_racer(actor: Actor) -> bool:
	return is_instance_valid(actor) and actor.has_meta("race_ai")


## A track's live race as plain data, for the pit board and to send to
## clients: empty with none. Times are from the moment it was made.
func heat_view(track_id: String) -> Dictionary:
	if mode == Mode.CLIENT:
		return remote_heats.get(track_id, {})
	var heat: Heat = heats.get(track_id)
	if heat == null:
		return {}
	return {
		"track": track_id,
		"phase": heat.phase,
		"people": heat.people(),
		"field": heat.runs.size() if heat.phase != "forming" else GRID_SIZE,
		"starts_in": maxf(heat.starts_at - clock, 0.0) if heat.phase == "forming" else 0.0,
		"results": heat.results.duplicate(true),
		"league": RaceLeague.league_name(heat.league),
		"ambient": heat.ambient,
		"made": Time.get_ticks_msec(),
	}


## Every track's live race, as sent to clients.
func public_heats() -> Array:
	var out: Array = []
	for t in circuits:
		var view := heat_view(t.id)
		if not view.is_empty():
			out.append(view)
	return out


## Online client: the races the server sent.
func set_remote_heats(rows: Array) -> void:
	remote_heats.clear()
	for row: Variant in rows:
		if row is Dictionary and row.has("track"):
			var view: Dictionary = (row as Dictionary).duplicate(true)
			view["made"] = Time.get_ticks_msec()
			remote_heats[str(view.track)] = view
	heat_changed.emit()


# --- Ghosts -------------------------------------------------------------------

static func _ghost_slot(pick: String, track_id: String, machine: String) -> String:
	return "%s|%s|%s" % [pick, track_id, machine]


## Asks for the ghost the local racer picked (`GHOST_PICKS`) on a track
## and machine, once: solo from the bank, online from the server. The
## answer lands in `ghosts` (`ghost_shown`) and `ghost_changed` says so.
func want_ghost(pick: String, track_id: String, machine: String) -> void:
	if pick not in GHOST_PICKS or pick == "off" or track_id == "" or machine == "":
		return
	var slot := _ghost_slot(pick, track_id, machine)
	if ghosts.has(slot):
		return
	ghosts[slot] = {"waiting": true}
	if mode == Mode.CLIENT:
		if send_ghost_ask.is_valid():
			send_ghost_ask.call(pick, track_id, machine)
		return
	var owners := ghost_owners(pick, player, track_id, machine)
	var answer: Dictionary = {"ok": false}
	if league_bank != null and not (owners.keys as Array).is_empty():
		answer = league_bank.ghost_of(owners.keys, track_id, owners.machine)
	take_ghost(pick, track_id, machine, answer)


## Whose ghosts a pick looks among, for `actor`: {"keys", "machine"} (an
## empty machine for any). A friend's needs the friends, which only the
## server knows, so here it is nobody's.
func ghost_owners(pick: String, actor: Actor, track_id: String, machine: String) -> Dictionary:
	var state := state_for(actor) if actor != null and is_instance_valid(actor) else null
	match pick:
		"mine":
			return {"keys": [state.owner if state != null else ""], "machine": machine}
		"leader":
			var rows := board_for(track_id)
			if not rows.is_empty():
				return {"keys": [str(rows[0].get("key", ""))], "machine": str(rows[0].machine)}
	return {"keys": [], "machine": machine}


## Keeps a ghost answer (`StashService.race_ghost`'s, its "ghost" packed
## text or a `RaceGhost`) for the pick it was asked for.
func take_ghost(pick: String, track_id: String, machine: String, answer: Dictionary) -> void:
	var slot := _ghost_slot(pick, track_id, machine)
	var shown := {}
	if answer.get("ok", false):
		var ghost: Variant = answer.get("ghost")
		var kept_machine := str(answer.get("machine", machine))
		var lap := float(answer.get("lap", -1.0))
		if not ghost is RaceGhost:
			ghost = RaceGhost.from_packed(ghost, kept_machine, lap)
		if ghost != null and lap > 0.0:
			ghost.machine = kept_machine
			ghost.lap_time = lap
			shown = {"name": str(answer.get("name", "?")).left(24), "machine": kept_machine, "lap": lap,
					"ghost": ghost}
	ghosts[slot] = shown
	ghost_changed.emit()


## The ghost for a pick on a track and machine: {"name", "machine", "lap",
## "ghost"}, or {} (none, or not here yet).
func ghost_shown(pick: String, track_id: String, machine: String) -> Dictionary:
	var shown: Dictionary = ghosts.get(_ghost_slot(pick, track_id, machine), {})
	return shown if shown.has("ghost") else {}


## Forgets the board leader's ghosts where a track's leader changed, so
## they are asked for again.
func _forget_leader_ghosts() -> void:
	var now := {}
	for row: Dictionary in board:
		if not now.has(row.track):
			now[row.track] = "%s|%s|%s" % [row.get("key", row.name), row.machine, row.time]
	for slot: String in ghosts.keys():
		var track_id := slot.get_slice("|", 1)
		if slot.begins_with("leader|") and _leaders.get(track_id, "") != now.get(track_id, ""):
			ghosts.erase(slot)
	_leaders = now


## Online client: the local racer's friends' best laps.
func set_friend_bests(rows: Array) -> void:
	friend_bests.clear()
	for row: Variant in rows.slice(0, 64):
		if row is Dictionary and float(row.get("time", -1.0)) > 0.0:
			friend_bests.append({"name": str(row.get("name", "?")).left(24), "track": str(row.get("track", "")),
					"machine": str(row.get("machine", "")), "time": float(row.time)})
	board_changed.emit()


## A track's friends' best laps, fastest first.
func friends_on(track_id: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for row: Dictionary in friend_bests:
		if row.track == track_id:
			rows.append(row)
	return rows


# --- Views --------------------------------------------------------------------

## A run as plain data, for the watch, the visor and `RaceView`, and to send
## to the racer online. Empty when there is none. Times are from the moment
## it was made: `run_lap_time` and `run_go_in` move them on.
func run_view(actor: Actor) -> Dictionary:
	var run: Run = runs.get(actor)
	if run == null:
		return {}
	return {
		"phase": run.phase,
		"machine": run.machine,
		"kit": run.kit,
		"track": run.track.id,
		"lap": run.lap,
		"laps": run.track.laps,
		"gates": run.track.gates.size(),
		"next_gate": run.next_gate,
		"clean": run.clean,
		"go_in": maxf(run.go_at - clock, 0.0),
		"lap_elapsed": maxf(clock - run.lap_start, 0.0) if run.phase == "racing" else 0.0,
		"last_gate": run.last_gate,
		"last_delta": run.last_delta,
		"last_lap": run.last_lap,
		"best_lap": run.best_lap,
		"total": run.total,
		"heat": run.heat.phase if run.heat != null else "",
		"place": run.place,
		"field": run.heat.runs.size() if run.heat != null else 0,
		"people": run.heat.people() if run.heat != null else 0,
		"finish_place": run.finish_place,
		"starts_in": maxf(run.heat.starts_at - clock, 0.0) if run.heat != null and run.heat.phase == "forming" else 0.0,
		"made": Time.get_ticks_msec(),
	}


## The local player's run, here or online.
func view_run() -> Dictionary:
	if mode == Mode.CLIENT:
		return remote_run
	return run_view(player) if player != null and is_instance_valid(player) else {}


## Seconds until the lights go out, from a run view.
static func run_go_in(view: Dictionary) -> float:
	if view.is_empty():
		return 0.0
	var since := (Time.get_ticks_msec() - int(view.get("made", 0))) / 1000.0
	return maxf(float(view.get("go_in", 0.0)) - since, 0.0)


## The time on the lap being run, from a run view.
static func run_lap_time(view: Dictionary) -> float:
	if view.is_empty() or str(view.get("phase", "")) != "racing":
		return 0.0
	var since := (Time.get_ticks_msec() - int(view.get("made", 0))) / 1000.0
	return float(view.get("lap_elapsed", 0.0)) + since


## How many of the lights are lit, from a run view (0 once they are out).
static func lights_lit(view: Dictionary) -> int:
	if str(view.get("phase", "")) != "grid":
		return 0
	var left := run_go_in(view)
	if left <= 0.0:
		return 0
	return clampi(LIGHTS - ceili(left / LIGHT_STEP) + 1, 1, LIGHTS)


## The run in one short line, for the watch and the visor: the lights, the
## lap and its time with the last split, or the finish.
static func run_line(view: Dictionary) -> String:
	if view.is_empty():
		return ""
	var place := place_tag(view)
	match str(view.get("phase", "")):
		"waiting":
			return "Next race in %s · %d/%d on the grid" % [format_countdown(run_starts_in(view)),
					int(view.get("people", 1)), GRID_SIZE]
		"grid":
			return "On the grid · lights %d/%d" % [lights_lit(view), LIGHTS]
		"racing":
			var line := "Lap %d/%d · %s" % [int(view.get("lap", 1)), int(view.get("laps", 1)),
					format_time(run_lap_time(view))]
			if place != "":
				line = place + " · " + line
			var delta := format_delta(float(view.get("last_delta", NAN)))
			if delta != "":
				line += " · " + delta
			if not bool(view.get("clean", true)):
				line += " · off track"
			return line
		"done":
			if str(view.get("heat", "")) != "":
				var finish := int(view.get("finish_place", 0))
				if finish <= 0:
					return "%s · finished %s · head to the pits" % [place, format_time(float(view.get("total", -1.0)))]
				if float(view.get("total", -1.0)) < 0.0:
					return "P%d/%d · did not finish" % [finish, int(view.get("field", 1))]
				return "P%d/%d · %s · head to the pits" % [finish, int(view.get("field", 1)),
						format_time(float(view.get("total", -1.0)))]
			return "Finished %s · best %s · head to the pits" % [format_time(float(view.get("total", -1.0))),
					format_time(float(view.get("best_lap", -1.0)))]
	return ""


## "P3/8" in a live race, else "".
static func place_tag(view: Dictionary) -> String:
	if str(view.get("heat", "")) == "" or int(view.get("place", 0)) <= 0:
		return ""
	return "P%d/%d" % [int(view.place), int(view.get("field", 1))]


## Seconds until a forming race goes, from a run view.
static func run_starts_in(view: Dictionary) -> float:
	if view.is_empty():
		return 0.0
	var since := (Time.get_ticks_msec() - int(view.get("made", 0))) / 1000.0
	return maxf(float(view.get("starts_in", 0.0)) - since, 0.0)


## A countdown as 0:25.
static func format_countdown(seconds: float) -> String:
	var whole := ceili(maxf(seconds, 0.0))
	return "%d:%02d" % [whole / 60, whole % 60]


## How far round the run is, from 0 at the line to 1 at the finish.
static func run_progress(view: Dictionary) -> float:
	if view.is_empty():
		return -1.0
	if str(view.get("phase", "")) == "done":
		return 1.0
	var gates := maxi(int(view.get("gates", 1)), 1)
	var passed := (int(view.get("next_gate", 1)) - 1 + gates) % gates
	return clampf((int(view.get("lap", 1)) - 1 + float(passed) / gates) / maxf(float(view.get("laps", 1)), 1.0), 0.0, 1.0)


## A lap time as 1:08.21.
static func format_time(seconds: float) -> String:
	if seconds < 0.0 or is_nan(seconds):
		return "--:--.--"
	var whole := int(seconds)
	return "%d:%02d.%02d" % [whole / 60, whole % 60, int((seconds - whole) * 100.0)]


## A split against the best as -0.42 or +1.10.
static func format_delta(delta: float) -> String:
	if is_nan(delta):
		return ""
	return ("−" if delta < 0.0 else "+") + "%.2f" % absf(delta)


## Online client: the run the server sent for the local player.
func set_remote_run(view: Dictionary) -> void:
	var was := remote_run
	remote_run = view.duplicate()
	# The machine under you runs with the kit the server fitted, so it
	# predicts the same.
	if player != null and is_instance_valid(player) and player.vehicle != null \
			and str(view.get("kit", "stock")) != str(was.get("kit", "stock")):
		fit(player.vehicle, str(view.get("kit", "stock")))
	if not remote_run.is_empty():
		remote_run["made"] = Time.get_ticks_msec()
	if player != null and is_instance_valid(player):
		run_changed.emit(player)
		var laps_before := int(was.get("lap", 0)) + (1 if str(was.get("phase", "")) == "done" else 0)
		var laps_now := int(view.get("lap", 0)) + (1 if str(view.get("phase", "")) == "done" else 0)
		if not was.is_empty() and laps_now > laps_before and float(view.get("last_lap", -1.0)) > 0.0:
			lap_finished.emit(player, float(view.last_lap), float(view.last_lap) == float(view.get("best_lap", -2.0)))


## Online client: the board the server sent.
func set_remote_board(rows: Array) -> void:
	board.clear()
	for row: Variant in rows:
		if row is Dictionary and row.has("time"):
			board.append({"name": str(row.get("name", "?")), "machine": str(row.get("machine", "")),
					"time": float(row.time), "key": str(row.get("name", "?")),
					"track": str(row.get("track", track.id if track != null else ""))})
	_forget_leader_ghosts()
	board_changed.emit()
