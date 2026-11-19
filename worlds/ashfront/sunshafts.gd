extends Node3D
## Sunlight breaking through the smoke over Ashfront (DESIGN.md "Scale you
## can see"): a few great soft shafts slanting down along the sun, each
## opening where the smoke parts, standing a while and closing again
## somewhere else. They are timed by the wall clock, so every player sees
## the same sky. The war's smoke dims them (the map's "war_intensity") and a
## storm's ash hides them (`Look.weather_cover`). View only: the map adds
## them only where `Look` is on. They cast no light and no shadow: each is
## one open cone (`Look.trim("sun_shaft")`).

## How many shafts the sky has.
const SHAFTS := 5
## How long a break in the smoke lasts, from opening to closing (s).
const OPEN_TIME := Vector2(45.0, 80.0)
## Where a shaft comes down: how far from the map's middle (m).
const REACH := Vector2(140.0, 560.0)
## How high over the floor the smoke it breaks through hangs (m).
const SMOKE_HEIGHT := 300.0
## The shaft's width at the break and where it meets the ground (m).
const TOP_WIDTH := Vector2(14.0, 30.0)
const FOOT_WIDTH := Vector2(45.0, 95.0)
## How much of a shaft the war's smoke leaves at its height.
const WAR_DIM := 0.35

var floor_y := 38.0

var _shafts: Array[MeshInstance3D] = []
## The break each shaft was last shaped for, so a cone is rebuilt only
## when it opens somewhere new.
var _shaped: Array[int] = []
## The way to the sun, from the map's light (up toward it).
var _to_sun := Vector3(0.0, 1.0, 0.0)


func _ready() -> void:
	name = "SunShafts"
	var sun := get_parent().get_node_or_null("Sun") as Node3D if get_parent() != null else null
	if sun != null:
		_to_sun = sun.global_basis.z.normalized()
	if _to_sun.y < 0.2:
		_to_sun = (_to_sun + Vector3.UP * (0.2 - _to_sun.y)).normalized()
	for i in SHAFTS:
		var node := MeshInstance3D.new()
		node.name = "Shaft%d" % i
		var cone := CylinderMesh.new()
		cone.cap_top = false
		cone.cap_bottom = false
		cone.radial_segments = 24
		cone.rings = 1
		cone.material = Look.trim("sun_shaft")
		node.mesh = cone
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.visibility_range_end = 2000.0
		add_child(node)
		_shafts.append(node)
		_shaped.append(-1)
	_place(clock())


func _process(_delta: float) -> void:
	_place(clock())


## The time the sky keeps: the wall clock, so every machine agrees.
static func clock() -> float:
	return fmod(Time.get_unix_time_from_system(), 100000.0)


## Which break in the smoke shaft `i` is in at time `t`, and how far
## through it (0 to 1). Shafts are spread out so they never open together.
static func cycle_of(i: int, t: float) -> Vector2:
	var length := lerpf(OPEN_TIME.x, OPEN_TIME.y, fposmod(i * 0.37, 1.0))
	var shifted := t + i * length / SHAFTS
	var cycle := floorf(shifted / length)
	return Vector2(cycle, (shifted - cycle * length) / length)


## How open a break is, `p` of the way through it: it widens, stands, and
## closes again, never snapping on or off.
static func openness(p: float) -> float:
	return smoothstep(0.0, 0.25, p) * (1.0 - smoothstep(0.7, 1.0, p))


## How bright the shafts are at war intensity `heat` and storm `cover`.
static func strength(heat: float, cover: float) -> float:
	return lerpf(1.0, WAR_DIM, clampf(heat, 0.0, 1.0)) * (1.0 - clampf(cover, 0.0, 1.0))


func _place(t: float) -> void:
	var map := get_parent()
	var heat := float(map.get_meta("war_intensity", 0.0)) if map != null else 0.0
	var lit := strength(heat, Look.weather_cover)
	var up := _to_sun
	var length := SMOKE_HEIGHT / up.y
	for i in _shafts.size():
		var at := cycle_of(i, t)
		var fade := openness(at.y) * lit
		var node := _shafts[i]
		node.visible = fade > 0.01
		if not node.visible:
			continue
		node.set_instance_shader_parameter("fade", fade)
		# Each break opens somewhere new: picked from the shaft and its break,
		# so every machine puts it in the same place.
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(Vector2i(i, int(at.x)))
		var angle := rng.randf() * TAU
		var reach := rng.randf_range(REACH.x, REACH.y)
		var foot := Vector3(cos(angle) * reach, floor_y, sin(angle) * reach)
		if map != null and map.has_method("ground_height"):
			foot.y = float(map.call("ground_height", foot.x, foot.z))
		var top := rng.randf_range(TOP_WIDTH.x, TOP_WIDTH.y) * 0.5
		var bottom := rng.randf_range(FOOT_WIDTH.x, FOOT_WIDTH.y) * 0.5
		if _shaped[i] != int(at.x):
			_shaped[i] = int(at.x)
			var cone := node.mesh as CylinderMesh
			cone.height = length
			cone.top_radius = top
			cone.bottom_radius = bottom
		# The smoke drifts, and the break with it.
		foot += Vector3(1.0, 0.0, 0.4) * at.y * 30.0
		var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
		var basis := Basis(side, up, side.cross(up).normalized())
		node.global_transform = Transform3D(basis, foot + up * length * 0.5)
