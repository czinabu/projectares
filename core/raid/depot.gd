class_name Depot
extends Area3D
## Stand inside for `hold_time` seconds to bank what you carry: it goes to
## your stash and you stay in the world. Maps place these and put them in
## the "depot" group; the Raid wires them up.

## The hold finished. The Raid moves `bankable(actor)` into the stash.
signal actor_banked(actor: Actor)

var hold_time := 4.0
var size := Vector3(8.0, 4.0, 8.0)
## Set by the Raid: true for an actor who has a stash to bank into (a player
## who is still in the world).
var can_bank := Callable()
var _progress := {}


func _ready() -> void:
	collision_layer = 0
	collision_mask = Actor.LAYER_ACTORS
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)

	var box := BoxMesh.new()
	box.size = size
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.2, 1.0, 0.5, 0.18)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 1.0, 0.5)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	box.material = mat
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)

	# A tall beacon so depots can be found from across the map.
	var beam := BoxMesh.new()
	beam.size = Vector3(0.4, 60.0, 0.4)
	beam.material = mat
	var beam_node := MeshInstance3D.new()
	beam_node.mesh = beam
	beam_node.position.y = 30.0
	beam_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam_node)


## What an actor would bank here: everything in the backpack except healing,
## which stays with them for the fight.
static func bankable(actor: Actor) -> Array[String]:
	var out: Array[String] = []
	for id in actor.inventory.items:
		if not ItemDB.has_tag(id, "heal"):
			out.append(id)
	return out


func _physics_process(delta: float) -> void:
	var inside := {}
	for body in get_overlapping_bodies():
		var actor := body as Actor
		if actor == null or actor.is_dead or not can_bank.is_valid() or not can_bank.call(actor) \
				or bankable(actor).is_empty():
			continue
		inside[actor] = true
		_progress[actor] = _progress.get(actor, 0.0) + delta
		if _progress[actor] >= hold_time:
			_progress.erase(actor)
			actor_banked.emit(actor)
	for actor: Actor in _progress.keys():
		if not inside.has(actor):
			_progress.erase(actor)


## 0..1 banking progress for an actor, 0 if they are not inside.
func progress_for(actor: Actor) -> float:
	return clampf(_progress.get(actor, 0.0) / hold_time, 0.0, 1.0)
