class_name Combat
extends RefCounted
## The single entry point for dealing damage.
## It asks the current world whether the hit is allowed, so PvP rules,
## friendly fire and safe zones are decided by the world, not by weapons.

## False on a client of an online raid. Hits are then decided by the server
## and arrive as health updates, so nothing is dealt here.
static var authoritative := true
## Lag compensation, set by an online server (`NetSession`). Called with an
## attacker, it returns where the other actors were on that attacker's screen
## when they attacked, as {Actor: Vector3}. Empty means "where they are now".
static var rewind := Callable()


static func deal(target: Object, info: DamageInfo) -> bool:
	var actor := target as Actor
	if actor == null or actor.is_dead or not authoritative:
		return false
	# Rules come from the raid the target stands in, and a hit never crosses
	# from one raid into another.
	var world := Worlds.of(actor)
	if world and not world.can_damage(info.source, actor, info):
		return false
	if info.source is Node and Raid.of(info.source) != null and not Raid.together(info.source, actor):
		return false
	# Attacking gives up your own drop-in protection, and nothing gets
	# through someone else's.
	var striker := info.source as Actor
	if striker and is_instance_valid(striker):
		striker.protected_left = 0.0
	if actor.protected_left > 0.0:
		return false
	actor.modify_incoming(info)
	if info.amount > 0.0:
		actor.health.apply_damage(info)
	var attacker := info.source as Actor
	if attacker and is_instance_valid(attacker):
		attacker.hit_confirmed.emit(actor, info, actor.is_dead)
	return true


## Where `attacker` saw the other actors, as {Actor: Vector3}. Attacks look up
## a target with `seen.get(target, target.global_position)`, so a player on a
## slow connection hits what was on their screen, not what the server has
## moved on to. Empty offline, for bots, and with no delay to make up.
static func positions_seen_by(attacker: Actor) -> Dictionary:
	if attacker == null:
		return {}
	# The attacker's own raid first: a server may run more than one.
	var raid := Raid.of(attacker)
	var source := raid.rewind if raid != null and raid.rewind.is_valid() else rewind
	if not source.is_valid():
		return {}
	var seen: Variant = source.call(attacker)
	return seen if seen is Dictionary else {}


## Traces a shot from `from` to `to` by `shooter`. Returns {"position", "collider"}
## for the first thing hit, or an empty Dictionary for a miss. Actors are hit
## where the shooter saw them (`positions_seen_by`).
static func trace(shooter: Actor, from: Vector3, to: Vector3) -> Dictionary:
	var space := shooter.get_world_3d().direct_space_state
	var seen := positions_seen_by(shooter)
	if seen.is_empty():
		var query := PhysicsRayQueryParameters3D.create(from, to, Actor.LAYER_WORLD | Actor.LAYER_ACTORS)
		query.exclude = [shooter.get_rid()]
		var hit := space.intersect_ray(query)
		return {} if hit.is_empty() else {"position": hit.position, "collider": hit.collider}
	# Rewound bodies cannot be moved inside the physics engine for one query,
	# so walls come from the engine and bodies are tested as their capsules.
	var result := {}
	var wall := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, Actor.LAYER_WORLD))
	if not wall.is_empty():
		to = wall.position
		result = {"position": wall.position, "collider": wall.collider}
	var nearest := from.distance_to(to)
	for node in shooter.get_tree().get_nodes_in_group("actors"):
		var other := node as Actor
		if other == null or other == shooter or other.is_dead or not Raid.together(shooter, other):
			continue
		var at: Vector3 = seen.get(other, other.global_position)
		var entry := capsule_entry(from, to, at)
		if entry.is_empty():
			continue
		var dist := from.distance_to(entry[0])
		if dist < nearest:
			nearest = dist
			result = {"position": entry[0], "collider": other}
	return result


## Where the segment `from`-`to` enters an actor body standing at `feet`, as
## [point], or [] if it misses.
static func capsule_entry(from: Vector3, to: Vector3, feet: Vector3) -> Array:
	var half := Actor.BODY_HEIGHT * 0.5 - Actor.BODY_RADIUS
	var center := feet + Vector3(0.0, Actor.BODY_HEIGHT * 0.5, 0.0)
	var closest := Geometry3D.get_closest_points_between_segments(from, to,
			center - Vector3(0.0, half, 0.0), center + Vector3(0.0, half, 0.0))
	if closest[0].distance_to(closest[1]) > Actor.BODY_RADIUS:
		return []
	# The ball around the nearest point of the body's spine gives the entry.
	var enter := Geometry3D.segment_intersects_sphere(from, to, closest[1], Actor.BODY_RADIUS)
	return [enter[0] if not enter.is_empty() else from]
