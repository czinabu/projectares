class_name Depot
extends Area3D
## Stand inside for `hold_time` seconds to bank what you carry: it goes to
## your stash and you stay in the world. Maps place these and put them in
## the "depot" group; the Raid wires them up.

## The hold finished. The Raid moves `bankable(actor)` into the stash.
signal actor_banked(actor: Actor)

var hold_time := 4.0
var size := Vector3(8.0, 4.0, 8.0)
## The uplink terminal at the back of the pad, and the mast that rises off it.
const TERMINAL_SIZE := Vector3(1.8, 1.7, 0.9)
const MAST_HEIGHT := 9.0
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
	_build_station()


## The station itself, in plain greybox for `Look` to dress: a pad that is the
## bank area (deep, so it sits on a slope), and an uplink terminal at
## its back edge (local +Z) with a mast on it, the beacon you find it by. The
## terminal is solid; the pad and the middle stay open to stand on. A map turns
## the depot to point the terminal's back where it wants it.
func _build_station() -> void:
	var floor_y := -size.y * 0.5
	var pad := MeshInstance3D.new()
	pad.name = "Pad"
	var slab := BoxMesh.new()
	# Deep enough below that a pad on a slope never shows a gap under it.
	slab.size = Vector3(size.x, 1.3, size.z)
	pad.mesh = slab
	pad.position.y = floor_y + 0.1 - 0.65
	pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pad.set_meta("walk_through", "the floor of the bank area, level with the ground")
	add_child(pad)

	var terminal := StaticBody3D.new()
	terminal.name = "Terminal"
	terminal.collision_layer = Actor.LAYER_WORLD
	terminal.collision_mask = 0
	terminal.position = Vector3(0, floor_y, size.z * 0.5 - TERMINAL_SIZE.z * 0.5 - 0.3)
	add_child(terminal)
	var body_shape := BoxShape3D.new()
	body_shape.size = TERMINAL_SIZE
	var body_col := CollisionShape3D.new()
	body_col.shape = body_shape
	body_col.position.y = TERMINAL_SIZE.y * 0.5
	terminal.add_child(body_col)
	var body := MeshInstance3D.new()
	body.name = "Body"
	var box := BoxMesh.new()
	box.size = TERMINAL_SIZE
	body.mesh = box
	body.position.y = TERMINAL_SIZE.y * 0.5
	terminal.add_child(body)
	var mast := MeshInstance3D.new()
	mast.name = "Mast"
	var pole := BoxMesh.new()
	pole.size = Vector3(0.22, MAST_HEIGHT, 0.22)
	mast.mesh = pole
	mast.position = Vector3(TERMINAL_SIZE.x * 0.5 - 0.2, MAST_HEIGHT * 0.5, TERMINAL_SIZE.z * 0.5 - 0.15)
	terminal.add_child(mast)
	var mast_shape := BoxShape3D.new()
	mast_shape.size = pole.size
	var mast_col := CollisionShape3D.new()
	mast_col.shape = mast_shape
	mast_col.position = mast.position
	terminal.add_child(mast_col)


## What an actor would bank here: everything in the backpack except healing,
## which stays with them for the fight, and the heavy weapon in the chamber
## (DESIGN.md section 7). Healing stays. A spent heavy is already gone.
static func bankable(actor: Actor) -> Array[String]:
	var out: Array[String] = []
	for id in actor.inventory.items:
		if not ItemDB.has_tag(id, "heal"):
			out.append(id)
	var index := Loadout.power_index(actor)
	if index >= 0:
		var gun := actor.weapons[index] as Gun
		if gun != null and gun.item_id != "" and not gun.is_spent():
			out.append(gun.item_id)
	return out


func _physics_process(delta: float) -> void:
	var inside := {}
	for body in get_overlapping_bodies():
		var actor := body as Actor
		if actor == null or actor.is_dead or not can_bank.is_valid() or not can_bank.call(actor) \
				or (bankable(actor).is_empty() and actor.scrip <= 0 and SalvageCrate.hauled_by(actor).is_empty()):
			continue
		inside[actor] = true
		_progress[actor] = _progress.get(actor, 0.0) + delta
		if _progress[actor] >= hold_time:
			_progress.erase(actor)
			actor_banked.emit(actor)
	# Untyped: someone freed meanwhile cannot be assigned to an `Actor`.
	for actor: Variant in _progress.keys():
		if not is_instance_valid(actor) or not inside.has(actor):
			_progress.erase(actor)


## 0..1 banking progress for an actor, 0 if they are not inside.
func progress_for(actor: Actor) -> float:
	return clampf(_progress.get(actor, 0.0) / hold_time, 0.0, 1.0)
