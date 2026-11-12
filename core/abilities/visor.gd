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

var cooldown_left := 0.0
## The zoom level in use: 0 is off, 1 the first of `zoom_levels`.
var zoom_level := 0
## The last scan's snapshots, each {"at": Vector3, "yaw": float, "left": float}.
var ghosts: Array[Dictionary] = []
## Tagged actors and the seconds each tag has left.
var tags := {}


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
	if not enabled or actor == null or actor.is_dead:
		zoom_level = 0
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
		if other.global_position.distance_to(actor.global_position) > scan_radius or allied(actor, other):
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
