class_name TrackView
extends Node3D
## Draws the footprints and wheel tracks a raid keeps (`Raid.tracks`) near
## the camera: pressed-in prints in the snow that fade as they age. View only:
## the raid adds it only where `Look` is on, and nothing reads it back.

## How far from the camera marks are drawn, how many at most, and how often
## the drawn set is refreshed.
const DRAW_RANGE := 55.0
const MAX_DRAWN := 2000
const REFRESH := 0.25
## A footprint's size, a wheel line's width and how far apart the two lines run.
const FOOT_SIZE := Vector2(0.2, 0.38)
const TREAD_WIDTH := 0.24
const TREAD_GAP := 0.9
## How far over the ground a mark is drawn, so it never sinks into it.
const LIFT := 0.05
## The pressed-in snow, at full strength on a fresh mark.
const COLOR := Color(0.3, 0.38, 0.56, 0.75)

var raid: Raid
var _feet: MultiMeshInstance3D
var _treads: MultiMeshInstance3D
var _refresh_in := 0.0


func _ready() -> void:
	name = "Tracks"
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_feet = _layer(material)
	_treads = _layer(material)


func _layer(material: Material) -> MultiMeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	plane.material = material
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = plane
	var node := MultiMeshInstance3D.new()
	node.multimesh = multi
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node


func _process(delta: float) -> void:
	_refresh_in -= delta
	if _refresh_in > 0.0 or raid == null:
		return
	_refresh_in = REFRESH
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var marks := raid.tracks.near(camera.global_position, DRAW_RANGE)
	if marks.size() > MAX_DRAWN:
		marks = marks.slice(marks.size() - MAX_DRAWN)
	var feet := []
	var treads := []
	for mark: Array in marks:
		(treads if int(mark[3]) == Tracks.Kind.TREAD else feet).append(mark)
	_fill(_feet.multimesh, feet, 1, Vector3(FOOT_SIZE.x, 1, FOOT_SIZE.y), 0.0)
	_fill(_treads.multimesh, treads, 2, Vector3(TREAD_WIDTH, 1, Raid.TREAD_STEP + 0.1), TREAD_GAP * 0.5)


## Puts `per` copies of the flat plane at each mark (two for wheel lines,
## `apart` either side of its middle), faded by its age.
func _fill(multi: MultiMesh, marks: Array, per: int, size: Vector3, apart: float) -> void:
	multi.instance_count = marks.size() * per
	var k := 0
	for mark: Array in marks:
		var basis := Basis(Vector3.UP, float(mark[2])) * Basis.from_scale(size)
		var at: Vector3 = mark[1] + Vector3(0, LIFT, 0)
		var fade := clampf(1.0 - (raid.clock - float(mark[4])) / raid.tracks.lifetime, 0.0, 1.0)
		var color := Color(COLOR, COLOR.a * sqrt(fade))
		for side in per:
			var off := Vector3.ZERO
			if per > 1:
				off = Basis(Vector3.UP, float(mark[2])) * Vector3(apart if side == 0 else -apart, 0, 0)
			multi.set_instance_transform(k, Transform3D(basis, at + off))
			multi.set_instance_color(k, color)
			k += 1
