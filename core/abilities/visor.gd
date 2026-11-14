class_name Visor
extends Node
## The helmet an actor wears. Like `Ability`, one class set up from an item's
## stats; the `mode` stat picks what the visor can do:
##   ""     - a plain visor. It shows its wearer a little and does nothing.
##   "zoom" - binoculars. `ActorCommand.visor_level` picks the magnification.
##            While zoomed you walk slowly, cannot use your weapon, and the
##            fire button tags whoever you are looking at for your side.
##   "scan" - `ActorCommand.visor_pressed` sends out a pulse. Everyone on
##            another side inside it is shown to the wearer where they stood
##            at that moment (a snapshot, never live tracking), and each of
##            them is told they were scanned and from where.
##   "threat" - a tactical visor. It tells its wearer where a hit came from,
##            and `visor_pressed` starts Threat Sense: for a few seconds
##            everyone on another side who is aiming at the wearer from
##            nearby is outlined, and each of them is told they were sensed.
##   "thermal" - `visor_level` 1 switches the visor to thermal on a battery
##            that drains while on and refills while off. Seeing heat is the
##            view's job (`VisorHud`); how warm someone looks is `heat_of`.
##
## What a visor reveals is decided by the authority only. Online the server
## works it out and `NetSession` tells just the players allowed to know; a
## client's own visor only keeps time and shows what it is told.
##
## The picture on the glass is `VisorHud`, a view. Nothing here draws.

## A scan went out from `origin`. Everyone nearby can see and hear it.
signal pulsed(origin: Vector3)
## The wearer's scan came back: `ghosts` is what `ghosts` now holds.
signal revealed(ghosts: Array)
## The wearer tagged `target`.
signal tagged(target: Actor)
## Someone else's scan caught this actor. `origin` is where it came from.
signal felt_scan(origin: Vector3)
## A tactical visor's wearer was hit from `origin`.
signal threatened(origin: Vector3)
## Who Threat Sense shows changed: `threats` now holds them.
signal threats_changed(threats: Array)

var actor: Actor
var item_id := ""
var display_name := "No helmet"
## False until a helmet is equipped.
var enabled := false

var mode := ""
## The colour of everything the visor draws on its glass.
var glass_color := Color(0.55, 0.85, 1.0)

## Zoom: the magnification of each level, weakest first.
var zoom_levels: Array = [4.0, 8.0]
## Zoom: the share of walking speed left while looking through it.
var zoom_move_mult := 0.5
## Zoom: how long off the ground still counts as standing. No zoom in flight.
var zoom_air_grace := 0.25
## Zoom: how far a tag reaches, how long it lasts, and the wait between tags.
var tag_range := 260.0
var tag_time := 5.0
var tag_cooldown := 2.0

## Scan: the wait between pulses, how far one reaches, and how long the
## snapshots stay on the glass.
var cooldown := 25.0
var scan_radius := 40.0
var ghost_time := 3.0

## Threat: how long Threat Sense runs, how far it reaches, how squarely
## someone must be aiming at the wearer (degrees off), and how often it looks.
var threat_time := 5.0
var threat_range := 60.0
var threat_cone_deg := 10.0
var threat_interval := 0.2
## Threat: how far the visor reads a target's health and a container's loot.
var read_range := 30.0
var loot_range := 5.0

## Thermal: seconds of charge, seconds to refill from empty, and the share
## of charge needed before it switches on again after running flat.
var battery := 12.0
var battery_refill := 18.0
var battery_restart := 0.25

var cooldown_left := 0.0
## Seconds of Threat Sense left.
var active_left := 0.0
## Who Threat Sense shows right now.
var threats: Array[Actor] = []
## Thermal: seconds of charge left, and whether the visor is in thermal.
var charge := -1.0
var thermal_on := false
## The zoom level in use: 0 is off, 1 the first of `zoom_levels`.
var zoom_level := 0
## The last scan's snapshots, each {"at": Vector3, "yaw": float, "left": float}.
var ghosts: Array[Dictionary] = []
## Tagged actors and the seconds each tag has left.
var tags := {}

var _threat_wait := 0.0
var _sensed: Array[Actor] = []
var _ran_flat := false


## Takes the helmet's stats back to a new visor's, so the next helmet put on
## starts clean (`Loadout.wear_helmet`). Who wears it stays.
func reset() -> void:
	_end_threat_sense()
	var fresh := Visor.new()
	for prop in get_script().get_script_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and prop.name != "actor":
			set(prop.name, fresh.get(prop.name))
	fresh.free()


## Runs one tick from the actor's command.
func tick(cmd: ActorCommand, delta: float) -> void:
	cooldown_left = maxf(0.0, cooldown_left - delta)
	for ghost in ghosts:
		ghost.left -= delta
	ghosts = ghosts.filter(func(g: Dictionary) -> bool: return g.left > 0.0)
	for target: Variant in tags.keys():
		tags[target] -= delta
		if tags[target] <= 0.0 or not is_instance_valid(target) or target.is_dead:
			tags.erase(target)
	if charge < 0.0:
		charge = battery
	if not enabled or actor == null or actor.is_dead:
		zoom_level = 0
		thermal_on = false
		_end_threat_sense()
		return
	var usable := actor.stagger_left <= 0.0 and not actor.weapons_locked
	match mode:
		"zoom":
			var steady := actor.vehicle != null or actor.airborne_time <= zoom_air_grace
			zoom_level = clampi(cmd.visor_level, 0, zoom_levels.size()) if usable and steady else 0
			if zoom_level > 0 and cmd.primary_pressed:
				_tag()
		"scan":
			if cmd.visor_pressed and usable:
				scan()
		"threat":
			if cmd.visor_pressed and usable:
				sense_threats()
			_tick_threat_sense(delta)
		"thermal":
			_tick_thermal(cmd.visor_level > 0 and usable, delta)


## How many settings `ActorCommand.visor_level` has above off for this helmet.
func levels() -> int:
	if not enabled:
		return 0
	match mode:
		"zoom":
			return zoom_levels.size()
		"thermal":
			return 1
	return 0


func is_zoomed() -> bool:
	return zoom_level > 0


## How much closer things look right now: 1 when not zoomed.
func zoom_factor() -> float:
	if zoom_level <= 0 or zoom_level > zoom_levels.size():
		return 1.0
	return maxf(1.0, float(zoom_levels[zoom_level - 1]))


## What looking through the visor does to walking speed.
func move_mult() -> float:
	return zoom_move_mult if is_zoomed() else 1.0


## Sends out a scan pulse if the visor is ready. Returns true if it fired.
func scan() -> bool:
	if not enabled or mode != "scan" or cooldown_left > 0.0 or actor == null or actor.is_dead:
		return false
	cooldown_left = cooldown
	var origin := actor.global_position + Vector3(0.0, actor.eye_height, 0.0)
	pulsed.emit(origin)
	Sfx.play("ability", null if actor.is_player else actor.global_position, -4.0)
	if not Combat.authoritative or not actor.is_inside_tree():
		return true
	var found: Array[Dictionary] = []
	for node in actor.get_tree().get_nodes_in_group("actors"):
		var other := node as Actor
		if other == null or other == actor or other.is_dead or not Raid.together(actor, other):
			continue
		if other.global_position.distance_to(actor.global_position) > reach_to(other, scan_radius) or allied(actor, other):
			continue
		found.append({"at": other.global_position, "yaw": other.cmd.yaw, "left": ghost_time})
		# Every reveal is felt: the target hears it and learns where it came from.
		other.visor.felt_scan.emit(origin)
		other.notice.emit("Scanned")
	show_ghosts(found)
	return true


## Puts a scan's snapshots on the glass. Online this is the server's answer.
func show_ghosts(found: Array) -> void:
	ghosts.clear()
	for entry: Variant in found:
		if typeof(entry) == TYPE_DICTIONARY and typeof(entry.get("at")) == TYPE_VECTOR3:
			ghosts.append({"at": entry.at, "yaw": float(entry.get("yaw", 0.0)),
					"left": float(entry.get("left", ghost_time))})
	revealed.emit(ghosts)


## Marks `target` for this visor's side. Online this is the server's word.
func add_tag(target: Actor, seconds: float) -> void:
	if target == null or not is_instance_valid(target) or target.is_dead:
		return
	tags[target] = seconds
	tagged.emit(target)


## Starts Threat Sense if the visor is ready. Returns true if it started.
func sense_threats() -> bool:
	if not enabled or mode != "threat" or cooldown_left > 0.0 or actor == null or actor.is_dead:
		return false
	cooldown_left = cooldown
	active_left = threat_time
	_threat_wait = 0.0
	Sfx.play("ability", null if actor.is_player else actor.global_position, -4.0)
	return true


func is_sensing() -> bool:
	return active_left > 0.0


## Shows who Threat Sense found. Online this is the server's word.
func show_threats(found: Array) -> void:
	threats.clear()
	for entry: Variant in found:
		if typeof(entry) != TYPE_OBJECT or not is_instance_valid(entry) or not entry is Actor:
			continue
		var other: Actor = entry
		if not other.is_dead:
			threats.append(other)
	threats_changed.emit(threats)


## True when `other` is aiming at this visor's wearer from within reach.
func is_aimed_at_by(other: Actor) -> bool:
	var to_me := actor.global_position + Vector3(0.0, Actor.BODY_HEIGHT * 0.5, 0.0) - other.get_eye_position()
	if to_me.length() > threat_range or to_me.length() < 0.01:
		return false
	return other.get_aim_dir().angle_to(to_me) <= deg_to_rad(threat_cone_deg)


## The wearer was hit by something at `origin`. A tactical visor shows where.
func note_hit_from(origin: Vector3) -> void:
	if enabled and mode == "threat" and actor != null and not actor.is_dead:
		threatened.emit(origin)


## How far a scan or a thermal visor picks `other` up: its flight rig's
## `FlightRig.scan_range` while one is worn (a jetpack carries far, boots
## hardly at all), else `base`.
static func reach_to(other: Actor, base: float) -> float:
	if other.flight.enabled and other.flight.scan_range > 0.0:
		return other.flight.scan_range
	return base


## How warm `other` looks through a thermal visor, about 0.4 to 2: a body's
## own warmth, scaled by what it wears, plus whatever its flight rig has
## built up. A hot jetpack shines.
static func heat_of(other: Actor) -> float:
	var rig := other.flight.heat_fraction() if other.flight.enabled else 0.0
	return clampf(other.heat_signature * (0.75 + 0.9 * rig), 0.4, 2.0)


func charge_fraction() -> float:
	return clampf(charge / maxf(battery, 0.01), 0.0, 1.0)


func _tick_threat_sense(delta: float) -> void:
	if active_left <= 0.0:
		return
	active_left = maxf(0.0, active_left - delta)
	if active_left <= 0.0:
		_end_threat_sense()
		return
	_threat_wait -= delta
	if _threat_wait > 0.0 or not Combat.authoritative or not actor.is_inside_tree():
		return
	_threat_wait = threat_interval
	var found: Array[Actor] = []
	for node in actor.get_tree().get_nodes_in_group("actors"):
		var other := node as Actor
		if other == null or other == actor or other.is_dead or not Raid.together(actor, other):
			continue
		if allied(actor, other) or not is_aimed_at_by(other):
			continue
		found.append(other)
		# Every reveal is felt: the first time it shows someone, they are told.
		if other not in _sensed:
			_sensed.append(other)
			other.notice.emit("Sensed")
	if found != threats:
		show_threats(found)


func _end_threat_sense() -> void:
	active_left = 0.0
	_sensed.clear()
	if not threats.is_empty() and (Combat.authoritative or actor == null):
		show_threats([])
	elif not threats.is_empty():
		# A client's list is the server's, but it never outlives the ability.
		threats.clear()
		threats_changed.emit(threats)


func _tick_thermal(wanted: bool, delta: float) -> void:
	if thermal_on:
		charge = maxf(0.0, charge - delta)
		if charge <= 0.0 or not wanted:
			thermal_on = false
	else:
		charge = minf(battery, charge + battery / maxf(battery_refill, 0.01) * delta)
		if wanted and charge >= battery * battery_restart and not _ran_flat:
			thermal_on = true
	# Run flat and it stays off until the key is let go, so it cannot flicker.
	if charge <= 0.0:
		_ran_flat = true
	elif not wanted:
		_ran_flat = false


## True when `a` and `b` fight on the same side (see `Raid.side_of`). Outside
## a raid nobody is allied.
static func allied(a: Actor, b: Actor) -> bool:
	var raid := Raid.of(a)
	if raid == null:
		return false
	return raid.side_of(a)[0] == raid.side_of(b)[0]


func status_text() -> String:
	if not enabled:
		return ""
	match mode:
		"zoom":
			return "%s  %dx" % [display_name, roundi(zoom_factor())] if is_zoomed() else "%s  ready" % display_name
		"scan":
			return "%s  %.0f" % [display_name, ceilf(cooldown_left)] if cooldown_left > 0.0 \
					else "%s  ready" % display_name
		"threat":
			if is_sensing():
				return "%s  sensing %.0f" % [display_name, ceilf(active_left)]
			return "%s  %.0f" % [display_name, ceilf(cooldown_left)] if cooldown_left > 0.0 \
					else "%s  ready" % display_name
		"thermal":
			return "%s  %s %d%%" % [display_name, "on" if thermal_on else "off", roundi(charge_fraction() * 100.0)]
	return display_name


func _tag() -> void:
	if cooldown_left > 0.0:
		return
	cooldown_left = tag_cooldown
	if not Combat.authoritative or not actor.is_inside_tree():
		return
	var from := actor.get_eye_position()
	var hit := Combat.trace(actor, from, from + actor.get_aim_dir() * tag_range)
	var target := hit.get("collider") as Actor
	if target != null and not target.is_dead and not allied(actor, target):
		add_tag(target, tag_time)
