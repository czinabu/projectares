class_name SalvageCrate
extends Interactable
## A salvage crate (DESIGN.md "The Dune Sea"): too big for a pack. Someone
## lifts it in both hands (`Actor.crate`: slow, no weapon, no flight) and
## sets it down, or loads it into a vehicle's cargo (`Vehicle.cargo`, at its
## `cargo_points`), and it is banked at a depot, carried or in the cargo of
## the vehicle its banker rides (`hauled_by`). Its contents (`items`) are
## decided when it is placed and only seen once banked.
##
## The `Raid` moves it (`lift_crate`, `set_down_crate`, `drop_crate`); a
## client is told where it is by `NetSession`. Where it is shown follows its
## holder every frame, the same everywhere.

## Its box: what it is in the hands, on the ground and in the cargo.
const SIZE := Vector3(0.9, 0.62, 0.62)
## Held in front of the chest, this far out and up from the body's feet.
const HELD_AT := Vector3(0.0, 0.95, -0.62)

## It moved: lifted, set down, loaded or dropped (`Raid` tells clients).
signal moved

var items: Array[String] = []
## Who has it: the actor carrying it, the vehicle it rides in (cargo slot
## `slot`), or null when it stands on the ground.
var holder: Node = null
var slot := -1

var _shape: CollisionShape3D


func _ready() -> void:
	add_to_group("salvage_crates")
	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = SIZE
	_shape.shape = box
	add_child(_shape)
	var mesh := MeshInstance3D.new()
	mesh.name = "Body"
	var cube := BoxMesh.new()
	cube.size = SIZE
	mesh.mesh = cube
	mesh.set_meta("look", "crate")
	add_child(mesh)
	_settle_layers()


## Standing on the ground it is solid and can be lifted; in a cargo bay it
## can only be lifted out (the vehicle carrying it never bumps it); in the
## hands it is neither.
func _settle_layers() -> void:
	if holder is Actor:
		collision_layer = 0
	elif holder != null:
		collision_layer = Actor.LAYER_INTERACT
	else:
		collision_layer = Actor.LAYER_INTERACT | Actor.LAYER_WORLD


func place(p_holder: Node, p_slot := -1) -> void:
	holder = p_holder
	slot = p_slot
	_settle_layers()
	follow()
	moved.emit()


## Puts it where its holder has it: in front of the carrier's chest, or at
## its cargo point on the vehicle.
func follow() -> void:
	if holder == null or not is_instance_valid(holder):
		return
	var actor := holder as Actor
	if actor != null:
		global_transform = Transform3D(Basis(Vector3.UP, actor.cmd.yaw), actor.global_position
				+ Basis(Vector3.UP, actor.cmd.yaw) * HELD_AT)
		return
	var points: Array = holder.get("cargo_points")
	if slot >= 0 and slot < points.size():
		var vehicle := holder as Node3D
		global_transform = vehicle.global_transform * Transform3D(Basis.IDENTITY,
				(points[slot] as Vector3) + Vector3(0, SIZE.y * 0.5, 0))


func _physics_process(_delta: float) -> void:
	if holder != null:
		if not is_instance_valid(holder):
			holder = null
			_settle_layers()
			return
		follow()


func get_prompt() -> String:
	return "Unload salvage crate" if holder != null else "Lift salvage crate"


func interact(actor: Actor) -> void:
	var raid := Raid.of(self)
	if raid != null:
		raid.lift_crate(actor, self)


## Every crate `actor` would bank at a depot: the one in their hands, and
## the cargo of the vehicle they drive.
static func hauled_by(actor: Actor) -> Array:
	var out := []
	if actor == null:
		return out
	if actor.crate != null and is_instance_valid(actor.crate):
		out.append(actor.crate)
	var vehicle: Node = actor.vehicle
	if vehicle != null and is_instance_valid(vehicle) and vehicle.get("rider") == actor:
		for crate: Variant in vehicle.get("cargo"):
			if crate != null and is_instance_valid(crate):
				out.append(crate)
	return out
