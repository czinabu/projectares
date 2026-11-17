class_name Artifact
extends Node
## The artifact carried on the watch for this outing (DESIGN.md section 6).
## One per actor, set up from the item's stats like an `Ability`; the
## `effect` stat picks what it does:
##   "rewind"    - Time Rewind: snaps you back to where you were, and how
##                 healthy you were, `rewind_seconds` ago. Leaves a trail
##                 along the way you came back, so the shooter knows.
##   "cloak"     - Phase Cloak: near-invisible for `duration` seconds. Firing
##                 or swinging breaks it, and a sign-out pauses while it runs.
##   "overclock" - Overclock Core: your rig makes no heat for `duration`
##                 seconds, then locks up overheated.
##   "bloom"     - Static Bloom: shuts off every flight rig within
##                 `bloom_radius` for `jam_time` seconds, yours included.
## Used from the watch (`ActorCommand.artifact_pressed`), so bots and remote
## players can use them the same way the local player does.

signal used(effect: String)

var actor: Actor
var item_id := ""
var display_name := "No artifact"
## False until an artifact is equipped.
var enabled := false

var effect := ""
## Uses per outing; 0 or less means no limit (then `cooldown` spaces them).
var charges := 1
var cooldown := 0.0
## How long a cloak or an overclock lasts.
var duration := 0.0
## Rewind: how far back it snaps you.
var rewind_seconds := 4.0
## Bloom: its reach and how long rigs stay off.
var bloom_radius := 14.0
var jam_time := 3.0
## Cloak: bots still notice a cloaked actor this close.
var cloak_sense_range := 4.0

var uses_left := 0
var cooldown_left := 0.0
var active_left := 0.0
## Rewind: where the actor came back along, newest last (for views).
var last_trail := PackedVector3Array()

## Rewind history: one [position, health] sample every `SAMPLE_EVERY`.
const SAMPLE_EVERY := 0.2
var _history: Array = []
var _sample_left := 0.0


## Puts the artifact `id` on, with its stats already applied by `Loadout`.
func attune(id: String) -> void:
	enabled = true
	item_id = id
	display_name = ItemDB.item_name(id)
	uses_left = charges
	cooldown_left = 0.0
	active_left = 0.0
	_history.clear()


func tick(delta: float) -> void:
	if not enabled:
		return
	cooldown_left = maxf(0.0, cooldown_left - delta)
	if active_left > 0.0:
		active_left = maxf(0.0, active_left - delta)
		if active_left <= 0.0:
			_end()
	if effect == "rewind" and actor != null:
		_sample_left -= delta
		if _sample_left <= 0.0:
			_sample_left = SAMPLE_EVERY
			_history.append([actor.global_position, actor.health.health])
			var keep := ceili(rewind_seconds / SAMPLE_EVERY) + 1
			while _history.size() > keep:
				_history.pop_front()


func is_ready() -> bool:
	return enabled and cooldown_left <= 0.0 and active_left <= 0.0 and (charges <= 0 or uses_left > 0)


func is_active() -> bool:
	return active_left > 0.0


func is_cloaked() -> bool:
	return effect == "cloak" and active_left > 0.0


## True once a limited artifact has no uses left this outing.
func is_spent() -> bool:
	return enabled and charges > 0 and uses_left <= 0


## Uses the artifact if it can. Returns true if it went off.
func activate() -> bool:
	if not is_ready() or actor == null or actor.is_dead:
		return false
	match effect:
		"rewind":
			if _history.is_empty():
				return false
			_rewind()
		"cloak":
			active_left = duration
			_shimmer()
		"overclock":
			if not actor.flight.enabled:
				return false
			active_left = duration
			actor.flight.heat_free = true
		"bloom":
			_bloom()
		_:
			push_warning("Artifact: unknown effect '%s'" % effect)
			return false
	if charges > 0:
		uses_left -= 1
	cooldown_left = cooldown
	actor.notice.emit(display_name)
	used.emit(effect)
	Sfx.play("ability", null if actor.is_player else actor.global_position)
	return true


## The actor attacked: a cloak breaks.
func on_attack() -> void:
	if is_cloaked():
		active_left = 0.0
		_end()


## A shimmer of light where a cloak starts or ends, so it is seen going on.
func _shimmer() -> void:
	if actor.is_inside_tree():
		Fx.burst(actor.get_parent(), actor.global_position + Vector3(0, 1.0, 0), 1.3, Color(0.7, 0.8, 1.0))


## What the watch's artifact icon says, one short line.
func status_text() -> String:
	if not enabled:
		return "No artifact"
	if is_active():
		return "%s · %.0f s" % [display_name, ceilf(active_left)]
	if is_spent():
		return "%s · spent" % display_name
	if cooldown_left > 0.0:
		return "%s · %d s" % [display_name, ceili(cooldown_left)]
	return display_name


func _end() -> void:
	match effect:
		"cloak":
			_shimmer()
		"overclock":
			actor.flight.heat_free = false
			actor.flight.lock_up()
			actor.notice.emit("%s burnt out" % display_name)


func _rewind() -> void:
	var back: Array = _history[0]
	last_trail = PackedVector3Array()
	for sample: Array in _history:
		last_trail.append(sample[0])
	last_trail.append(actor.global_position)
	actor.global_position = back[0]
	actor.velocity = Vector3.ZERO
	# Back to how healthy you were, never less healthy than now.
	if float(back[1]) > actor.health.health:
		actor.health.heal(float(back[1]) - actor.health.health)
	_history.clear()
	if actor.is_inside_tree():
		Fx.rewind_trail(actor.get_parent(), last_trail, Color(0.55, 0.85, 1.0))


func _bloom() -> void:
	if not actor.is_inside_tree():
		actor.flight.jam(jam_time)
		return
	var seen := Combat.positions_seen_by(actor)
	for node in actor.get_tree().get_nodes_in_group("actors"):
		var other := node as Actor
		if other == null or other.is_dead or not Raid.together(actor, other):
			continue
		var at: Vector3 = seen.get(other, other.global_position)
		if other == actor or at.distance_to(actor.global_position) <= bloom_radius:
			other.flight.jam(jam_time)
	Fx.ring(actor.get_parent(), actor.global_position + Vector3(0, 1.0, 0), bloom_radius, Color(0.6, 0.9, 1.0))
