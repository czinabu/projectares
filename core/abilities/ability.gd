class_name Ability
extends Node
## An active ability on a cooldown, set up from an item's stats like any other
## gear. The `effect` stat picks what it does:
##   "blink"   - step instantly in the aim direction, stopping short of walls.
##   "barrier" - for a few seconds, bullets and melee hits do less damage.
##   "pulse"   - a shockwave that hurts and staggers everyone close by.
## Abilities are triggered by `ActorCommand.ability_pressed`, so bots and remote
## players can use them the same way the local player does.

signal activated(effect: String)

var actor: Actor
var item_id := ""
var display_name := "No ability"
## False until an ability item is equipped.
var enabled := false

var effect := ""
var cooldown := 10.0
## Blink: how far the step carries.
var blink_range := 9.0
## Blink: seconds of barrier-strength protection on arrival (a mastery variant).
var blink_shield := 0.0
## Barrier: how long it lasts and the share of damage it removes.
var duration := 4.0
var damage_reduction := 0.6
## Pulse: reach, damage and how long targets are staggered.
var pulse_radius := 6.5
var pulse_damage := 18.0
var pulse_stagger := 1.3

var cooldown_left := 0.0
var active_left := 0.0


func tick(delta: float) -> void:
	cooldown_left = maxf(0.0, cooldown_left - delta)
	active_left = maxf(0.0, active_left - delta)


func is_ready() -> bool:
	return enabled and cooldown_left <= 0.0


func is_active() -> bool:
	return active_left > 0.0


## Uses the ability if it is off cooldown. Returns true if it fired.
func activate() -> bool:
	if not is_ready() or actor == null or actor.is_dead:
		return false
	match effect:
		"blink":
			_blink()
			active_left = blink_shield
		"barrier":
			active_left = duration
		"pulse":
			_pulse()
		_:
			push_warning("Ability: unknown effect '%s'" % effect)
			return false
	cooldown_left = cooldown
	actor.notice.emit(display_name)
	activated.emit(effect)
	Sfx.play("ability", null if actor.is_player else actor.global_position)
	return true


## Called for every hit on the actor, after the weapon's guard.
func modify_incoming(info: DamageInfo) -> void:
	if effect in ["barrier", "blink"] and is_active() and info.kind in ["bullet", "melee", "slam", "pulse"]:
		info.amount *= 1.0 - damage_reduction


func status_text() -> String:
	if not enabled:
		return ""
	if is_active():
		return "%s  active %.1f" % [display_name, active_left]
	if cooldown_left > 0.0:
		return "%s  %.1f" % [display_name, cooldown_left]
	return "%s  ready" % display_name


func _blink() -> void:
	var dir := actor.get_aim_dir()
	if dir.length() < 0.01:
		return
	dir = dir.normalized()
	var from := actor.get_eye_position()
	var distance := blink_range
	if actor.is_inside_tree():
		var query := PhysicsRayQueryParameters3D.create(from, from + dir * blink_range, Actor.LAYER_WORLD)
		var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			distance = maxf(0.0, from.distance_to(hit.position) - 0.8)
	var to := actor.global_position + dir * distance
	if actor.is_inside_tree():
		# The step is measured from the eyes, so on a slope or aiming down the
		# feet can end up under the ground. Stand them back on it.
		var head := to + Vector3(0, from.y - actor.global_position.y, 0)
		var down := PhysicsRayQueryParameters3D.create(head, to, Actor.LAYER_WORLD)
		var floor_hit := actor.get_world_3d().direct_space_state.intersect_ray(down)
		if not floor_hit.is_empty():
			to.y = floor_hit.position.y + 0.05
	actor.global_position = to
	# Arrive without the fall speed you left with.
	actor.velocity.y = maxf(actor.velocity.y, 0.0)


func _pulse() -> void:
	if not actor.is_inside_tree():
		return
	var seen := Combat.positions_seen_by(actor)
	for node in actor.get_tree().get_nodes_in_group("actors"):
		var other := node as Actor
		if other == null or other == actor or other.is_dead or not Raid.together(actor, other):
			continue
		var at: Vector3 = seen.get(other, other.global_position)
		if at.distance_to(actor.global_position) > pulse_radius:
			continue
		var info := DamageInfo.make(pulse_damage, actor, "pulse", at)
		if Combat.deal(other, info) and not other.is_dead:
			other.stagger(pulse_stagger)
