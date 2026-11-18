class_name IceView
extends Node3D
## Draws thin ice giving way (`Raid.ice_cracked`, `Raid.ice_holes`): white
## cracks spreading where a heavy vehicle strains it, heard as they go, and
## the open holes as dark water ringed with broken plates until they freeze
## over. View only: the raid adds it only where `Look` is on, and nothing
## reads it back.

## Seconds a crack stays drawn, and how far each stage reaches.
const CRACK_LIFE := 25.0
const CRACK_REACH := [0.0, 3.0, 5.0, 6.5]
## How far a crack or a breaking is heard.
const REACH := 140.0
## How far over the ground the water and cracks are drawn, so they sit on
## top of a map's own dressed ice.
const LIFT := 0.13
const WATER := Color(0.03, 0.07, 0.11, 0.96)
const CRACK := Color(0.92, 0.97, 1.0, 0.85)
const SHARD := Color(0.78, 0.88, 0.96)

var raid: Raid
var _holes: Array[Node3D] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	name = "Ice"
	_rng.seed = 7
	raid.ice_cracked.connect(_on_cracked)
	raid.ice_changed.connect(_show_holes)
	_show_holes()


func _on_cracked(at: Vector3, stage: int) -> void:
	var breaks := stage > Raid.ICE_WARNINGS.size()
	Sfx.play("ice_break" if breaks else "ice_crack", at, 4.0 if breaks else -2.0 + stage * 3.0, REACH)
	var cracks := _cracks(at, CRACK_REACH[clampi(stage, 0, CRACK_REACH.size() - 1)])
	add_child(cracks)
	var tween := cracks.create_tween()
	tween.tween_interval(CRACK_LIFE)
	tween.tween_callback(cracks.queue_free)
	if breaks:
		Fx.burst(self, at + Vector3(0.0, 0.5, 0.0), 2.5, SHARD)


## White lines running out from a point over the ice, forking as they go.
func _cracks(at: Vector3, reach: float) -> Node3D:
	var node := Node3D.new()
	node.position = at + Vector3(0.0, LIFT, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = CRACK
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var lines := 7
	for k in lines:
		var angle := TAU * k / lines + _rng.randf_range(-0.3, 0.3)
		var from := Vector3.ZERO
		var length := reach * _rng.randf_range(0.6, 1.0)
		var step := length / 3.0
		for piece in 3:
			angle += _rng.randf_range(-0.5, 0.5)
			var to := from + Vector3(sin(angle), 0.0, cos(angle)) * step
			node.add_child(_line(from, to, 0.05 - piece * 0.012, mat))
			from = to
	return node


func _line(from: Vector3, to: Vector3, width: float, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, 0.01, from.distance_to(to))
	mesh.material = mat
	var line := MeshInstance3D.new()
	line.mesh = mesh
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	line.position = (from + to) * 0.5
	line.rotation.y = atan2(to.x - from.x, to.z - from.z)
	return line


## Rebuilds the open holes from `Raid.ice_holes`.
func _show_holes() -> void:
	for hole in _holes:
		hole.queue_free()
	_holes.clear()
	for entry: Array in raid.ice_holes:
		var hole := _hole(entry[0])
		add_child(hole)
		_holes.append(hole)


## Dark open water with broken plates tipped round its edge.
func _hole(at: Vector3) -> Node3D:
	var node := Node3D.new()
	node.position = at + Vector3(0.0, LIFT - 0.03, 0.0)
	var water := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = Raid.ICE_HOLE_RADIUS
	disc.bottom_radius = Raid.ICE_HOLE_RADIUS
	disc.height = 0.02
	disc.radial_segments = 20
	var water_mat := StandardMaterial3D.new()
	water_mat.albedo_color = WATER
	water_mat.metallic = 0.3
	water_mat.roughness = 0.05
	disc.material = water_mat
	water.mesh = disc
	water.position.y = 0.03
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(water)
	var shard_mat := StandardMaterial3D.new()
	shard_mat.albedo_color = SHARD
	shard_mat.roughness = 0.2
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(roundi(at.x), roundi(at.z)))
	for k in 14:
		var angle := TAU * k / 14.0 + rng.randf_range(-0.15, 0.15)
		var size := Vector3(rng.randf_range(0.6, 1.4), 0.12, rng.randf_range(0.5, 1.1))
		var plate := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		box.material = shard_mat
		plate.mesh = box
		var r := Raid.ICE_HOLE_RADIUS + rng.randf_range(-0.4, 0.3)
		plate.position = Vector3(sin(angle) * r, 0.08, cos(angle) * r)
		plate.rotation = Vector3(rng.randf_range(-0.35, 0.35), angle, rng.randf_range(-0.35, 0.35))
		node.add_child(plate)
	return node
