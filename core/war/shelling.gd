class_name Shelling
extends RefCounted
## The war's artillery (DESIGN.md "Shelling", Caleb's call: the shells are
## real and marked before they land). Every so often, sooner the hotter the
## war, a salvo is called down near the fighting: a line of shells walking
## across the ground past an army soldier. Each spot is marked for `warning`
## seconds (`Raid.shells_called`, which every client is sent), then the shell
## lands (`Raid.shell_landed`) and hurts everyone near it through
## `Combat.deal` (`Gun.splash`, kind "shell"), unless cover stands between.
## Nobody owns a shell: it pays no kill, renown or bounty.
##
## Authority only, and only where `Raid.zone_rules` hold. Never near a gate
## outpost or a player spawn, never on a player still under drop-in
## protection, and bots who see the mark run from it like a rocket
## (`Gun.live_rounds`, `BotBrain._think_danger`). A world turns it on with
## `WorldDef.shelling` (a rate, 0 off).

## Seconds between salvos when quiet and in all-out war (divided by the
## world's rate), and before the first.
var every := Vector2(75.0, 20.0)
var first := 45.0
## Seconds a spot is marked before its shell lands, and between the shells
## of one salvo landing.
var warning := 4.0
var stagger := 0.45
## Shells in a salvo (fewest, most), how far apart they land along the line
## and how far from the soldier it was aimed past the line runs.
var shells := Vector2i(3, 6)
var spacing := 8.0
var miss := Vector2(8.0, 22.0)
## How far a shell hurts and how much at its heart (a third at the edge).
var radius := 9.0
var damage := 95.0
## The column of smoke a shell leaves (`ShellView` draws it): how wide, how
## tall and how long it hides people from bots (`Raid.smoke`).
var smoke_radius := 6.0
var smoke_height := 14.0
var smoke_life := 13.0
## How close to a gate outpost or a player spawn no shell may land, and to a
## player still under drop-in protection.
var keep_clear := 35.0
var protected_clear := 20.0

## Shells on their way: each a `Marker` with the seconds until it lands.
var pending: Array[Marker] = []
var _next := 0.0
var _rng := RandomNumberGenerator.new()


func reset(seed_value: int) -> void:
	_rng.seed = seed_value
	_next = first
	for marker in pending:
		if is_instance_valid(marker):
			marker.queue_free()
	pending.clear()


## Seconds until the next salvo is called at war intensity `intensity`.
func gap(intensity: float, rate: float) -> float:
	return lerpf(every.x, every.y, clampf(intensity, 0.0, 1.0)) / maxf(rate, 0.01)


func tick(raid: Raid, delta: float) -> void:
	for marker: Variant in pending.duplicate():
		if not is_instance_valid(marker):
			pending.erase(marker)
			continue
		var shell := marker as Marker
		shell.left -= delta
		if shell.left <= 0.0:
			pending.erase(shell)
			land(raid, shell.global_position)
			shell.queue_free()
	_next -= delta
	if _next > 0.0:
		return
	_next = gap(raid.war.intensity, raid.world.shelling) * _rng.randf_range(0.8, 1.2)
	call_salvo(raid)


## Calls a salvo down past a soldier near the fighting. Returns where the
## shells will land (empty when nowhere was clear).
func call_salvo(raid: Raid) -> PackedVector3Array:
	var aim := _pick_aim(raid)
	if aim == Vector3.INF:
		return PackedVector3Array()
	return call_at(raid, aim, _rng.randf() * TAU)


## Calls a salvo whose line runs through `aim` at heading `heading`, keeping
## only the spots that are clear. Authority only.
func call_at(raid: Raid, aim: Vector3, heading: float) -> PackedVector3Array:
	var count := _rng.randi_range(shells.x, shells.y)
	var along := Vector3(sin(heading), 0.0, cos(heading))
	var points := PackedVector3Array()
	var delays := PackedFloat32Array()
	for k in count:
		var spot := aim + along * (k - (count - 1) * 0.5) * spacing
		spot += Vector3(_rng.randf_range(-1.5, 1.5), 0.0, _rng.randf_range(-1.5, 1.5))
		var hit := surface(raid, spot)
		if not clear(raid, hit):
			continue
		var marker := Marker.new()
		marker.splash_radius = radius
		marker.left = warning + points.size() * stagger
		raid.add_child(marker)
		marker.global_position = hit
		pending.append(marker)
		points.append(hit)
		delays.append(marker.left)
	if not points.is_empty():
		raid.shells_called.emit(points, delays)
	return points


## A shell lands: everyone near it with nothing between is hurt.
func land(raid: Raid, at: Vector3) -> void:
	Gun.splash(null, at + Vector3(0.0, 0.6, 0.0), radius, damage, "shell", raid)
	raid.smoke.add(at, smoke_radius, smoke_height, smoke_life)
	raid.shell_landed.emit(at)


## Whether a shell may land at `at`.
func clear(raid: Raid, at: Vector3) -> bool:
	if at == Vector3.INF:
		return false
	var flat := Vector2(at.x, at.z)
	for marker in raid.outposts:
		var gate := Vector2(marker.global_position.x, marker.global_position.z)
		if flat.distance_to(gate) < float(marker.get_meta("radius", 10.0)) + keep_clear:
			return false
	for marker in raid._map_nodes("spawn_player"):
		if flat.distance_to(Vector2(marker.global_position.x, marker.global_position.z)) < keep_clear:
			return false
	for state in raid.players:
		var actor := state.actor
		if state.finished or not is_instance_valid(actor) or actor.is_dead:
			continue
		if (actor.protected_left > 0.0 or state.sheltered) \
				and flat.distance_to(Vector2(actor.global_position.x, actor.global_position.z)) < protected_clear:
			return false
	return true


## Where a shell coming straight down at `at` strikes: a roof if there is
## one, else the ground. INF if nothing is there.
static func surface(raid: Raid, at: Vector3) -> Vector3:
	var ground := at.y
	if raid.map.has_method("ground_height"):
		ground = float(raid.map.call("ground_height", at.x, at.z))
	if raid.is_inside_tree():
		var space := raid.get_world_3d().direct_space_state
		var top := Vector3(at.x, ground + 200.0, at.z)
		var query := PhysicsRayQueryParameters3D.create(top, Vector3(at.x, ground - 2.0, at.z), Actor.LAYER_WORLD)
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			return hit["position"]
	return Vector3(at.x, ground, at.z)


## An army soldier near the fighting to aim past: the nearest to the war's
## centre of a few picked at random, then off to one side of them.
func _pick_aim(raid: Raid) -> Vector3:
	var best: Actor = null
	var best_dist := INF
	for i in 4:
		if raid.bots.is_empty():
			break
		var bot: Variant = raid.bots[_rng.randi() % raid.bots.size()]
		if not is_instance_valid(bot) or (bot as Actor).is_dead:
			continue
		var dist := (bot as Actor).global_position.distance_to(raid.war.centre)
		if dist < best_dist:
			best = bot
			best_dist = dist
	if best == null:
		return Vector3.INF
	var side := _rng.randf() * TAU
	return best.global_position + Vector3(sin(side), 0.0, cos(side)) * _rng.randf_range(miss.x, miss.y)


## A marked spot with a shell on its way: a burst bots run from, read like a
## round in flight (`Gun.live_rounds`), with no velocity and no shooter.
class Marker extends Node3D:
	var left := 0.0
	var splash_radius := 0.0
	var velocity := Vector3.ZERO
	var kind := "shell"
	var gun_shooter: Actor = null

	func _enter_tree() -> void:
		name = "Shell"
		if not Gun.live_rounds.has(self):
			Gun.live_rounds.append(self)

	func _exit_tree() -> void:
		Gun.live_rounds.erase(self)
