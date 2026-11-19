extends RefCounted
## Meridian's surroundings, decoration only (the land and mesas past the
## circuits are the planet's, `Planet.horizon`): the dead launch works on the skyline
## (leaning launch towers with holo-ads, gantry cranes, a wrecked booster
## stage, a line of power pylons marching off), searchlights sweeping the
## haze over the stands and camera drones pacing the racers' lines. Nothing
## collides or is read by the race; built only where `Look` is on, from its
## own RNG and noise seed.

const CYAN := Color(0.3, 0.85, 1.0)
const AMBER := Color(1.0, 0.6, 0.2)
const MAGENTA := Color(1.0, 0.3, 0.7)
const RED := Color(1.0, 0.22, 0.12)
## The middle of the circuits, which the holo-ads face.
const CENTRE := Vector3(-40, 0, 100)

var stands: RefCounted
var root: Node3D
var rng := RandomNumberGenerator.new()


func _init(p_stands: RefCounted, p_seed: int) -> void:
	stands = p_stands
	root = stands.get("root")
	rng.seed = p_seed


func build(tracks: Array) -> void:
	_launch_tower(Vector3(430, 0, 300), 175.0, Vector2(0.12, -0.05), "COILRUN  ·  3 LAPS", AMBER)
	_launch_tower(Vector3(-560, 0, 230), 150.0, Vector2(-0.08, 0.1), "MERIDIAN CIRCUIT", CYAN)
	_launch_tower(Vector3(160, 0, -470), 190.0, Vector2(0.05, 0.09), "RIDE THE SKYHOOK", MAGENTA)
	_gantry_crane(Vector3(360, 0, -200), 0.6)
	_gantry_crane(Vector3(-520, 0, -300), -0.4)
	_booster(Vector3(-300, 0, 640), -0.6)
	_pylons(Vector3(620, 0, 520), Vector3(1, 0, 0.55).normalized(), 9)
	_pylons(Vector3(-420, 0, -620), Vector3(-0.8, 0, -1).normalized(), 9)
	for spec: Array in [[Vector3(-150, 0, 75), 0.0], [Vector3(-40, 0, 75), 1.7], [Vector3(60, 0, 75), 3.1],
			[Vector3(-60, 56, -62), 4.4], [Vector3(-230, 0, -175), 2.2]]:
		var light := SearchLight.new()
		light.position = spec[0]
		light.phase = spec[1]
		root.add_child(light)
	for track: RaceTrack in tracks:
		for k in 2:
			var drone := Drone.new()
			drone.track = track
			drone.offset = 0.25 + 0.5 * k
			root.add_child(drone)


# --- The dead launch works -------------------------------------------------------

## A lattice launch tower `h` tall, leaning by `lean` (radians about x and
## z), a red beacon on top and a holo-ad hung on its face.
func _launch_tower(at: Vector3, h: float, lean: Vector2, ad: String, color: Color) -> void:
	var basis := Basis(Vector3.RIGHT, lean.x) * Basis(Vector3.BACK, lean.y)
	var xf := Transform3D(basis, at)
	var dark: Material = stands.get("dark")
	var steel: Material = stands.get("steel")
	var w := 12.0
	for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		stands.call("box", Vector3(1.4, h, 1.4), xf * Transform3D(Basis(), Vector3(c.x * w * 0.5, h * 0.5, c.y * w * 0.5)), dark)
	var y := 8.0
	var k := 0
	while y < h:
		for side in 4:
			var yaw := PI * 0.5 * side
			var face := Transform3D(Basis(Vector3.UP, yaw), Vector3.ZERO) * Transform3D(Basis(), Vector3(0, y, w * 0.5))
			stands.call("box", Vector3(w, 0.6, 0.6), xf * face, steel)
			# A brace across each bay.
			var brace := face * Transform3D(Basis(Vector3.BACK, 0.68), Vector3(0, 5.0, 0))
			stands.call("box", Vector3(w * 1.25, 0.4, 0.4), xf * brace, steel)
		if k % 4 == 0:
			stands.call("box", Vector3(w + 0.6, 0.3, w + 0.6), xf * Transform3D(Basis(), Vector3(0, y, 0)), stands.call("glow", color, 2.0))
		y += 10.0
		k += 1
	# The service arm out from the top, and the beacon.
	stands.call("box", Vector3(3, 3, 34), xf * Transform3D(Basis(), Vector3(0, h - 12, 20)), dark)
	stands.call("box", Vector3(3.5, 3.5, 3.5), xf * Transform3D(Basis(), Vector3(0, h + 2, 0)), stands.call("glow", RED, 6.0))
	# The holo-ad: a lit frame and its words, facing the circuits.
	var to_centre := (CENTRE - at)
	var face_yaw := atan2(to_centre.x, to_centre.z)
	var ad_xf := Transform3D(Basis(Vector3.UP, face_yaw), at + Vector3(0, h * 0.55, 0)
			+ Vector3(to_centre.x, 0, to_centre.z).normalized() * (w * 0.5 + 3.0))
	var width := ad.length() * 4.6 + 10.0
	stands.call("box", Vector3(width, 16, 0.3), ad_xf, stands.call("glow", color * 0.15, 0.6, 0.35))
	for yy: float in [8.2, -8.2]:
		stands.call("box", Vector3(width, 0.5, 0.4), ad_xf * Transform3D(Basis(), Vector3(0, yy, 0)), stands.call("glow", color, 4.0))
	stands.call("label", ad, ad_xf * Transform3D(Basis(), Vector3(0, 0, 0.4)), 600, color, 0.02)


## A gantry crane frozen over the flats: two A-frame legs and a beam with a
## trolley, warning lamps on top.
func _gantry_crane(at: Vector3, yaw: float) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw), at)
	var dark: Material = stands.get("dark")
	var steel: Material = stands.get("steel")
	var span := 90.0
	var h := 64.0
	for s: float in [-1.0, 1.0]:
		for lean: float in [-0.22, 0.22]:
			stands.call("box", Vector3(2.4, h + 4, 2.4), xf * Transform3D(Basis(Vector3.RIGHT, lean), Vector3(s * span * 0.5, h * 0.5, 0)), dark)
		stands.call("box", Vector3(3, 2, 30), xf * Transform3D(Basis(), Vector3(s * span * 0.5, 2.0, 0)), steel)
	stands.call("box", Vector3(span + 14, 6, 5), xf * Transform3D(Basis(), Vector3(0, h, 0)), steel)
	stands.call("box", Vector3(10, 8, 8), xf * Transform3D(Basis(), Vector3(span * 0.18, h - 6, 0)), dark)
	stands.call("box", Vector3(0.5, 30, 0.5), xf * Transform3D(Basis(), Vector3(span * 0.18, h - 25, 0)), dark)
	for s: float in [-1.0, 1.0]:
		stands.call("box", Vector3(1.5, 1.5, 1.5), xf * Transform3D(Basis(), Vector3(s * (span * 0.5 + 6), h + 4, 0)),
				stands.call("glow", RED, 5.0))


## A spent booster stage lying where it came down, half sunk in the salt:
## the tank, its engine bells and two bent fins.
func _booster(at: Vector3, yaw: float) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, 0.08), at + Vector3(0, 6, 0))
	var hull := Look.surface("metal", {"metal": 0.5, "tint": Color(0.7, 0.68, 0.66), "grime": 0.7, "scale": 0.05})
	var tank := MeshInstance3D.new()
	tank.mesh = CylinderMesh.new()
	tank.mesh.top_radius = 9.0
	tank.mesh.bottom_radius = 9.0
	tank.mesh.height = 96.0
	tank.mesh.radial_segments = 24
	tank.mesh.material = hull
	tank.transform = xf * Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3.ZERO)
	root.add_child(tank)
	for k in 4:
		var bell := MeshInstance3D.new()
		bell.mesh = CylinderMesh.new()
		bell.mesh.top_radius = 1.6
		bell.mesh.bottom_radius = 3.6
		bell.mesh.height = 8.0
		bell.mesh.material = stands.get("dark")
		var off := Vector3(0, cos(k * PI * 0.5) * 4.0, sin(k * PI * 0.5) * 4.0)
		bell.transform = xf * Transform3D(Basis(Vector3.BACK, -PI * 0.5), Vector3(-52, 0, 0) + off)
		root.add_child(bell)
	for s: float in [-1.0, 1.0]:
		stands.call("box", Vector3(16, 0.6, 12), xf * Transform3D(Basis(Vector3.RIGHT, s * 0.5), Vector3(-38, 0, s * 12)),
				stands.get("steel"))
	# A band of the old livery, still lit.
	var band := MeshInstance3D.new()
	band.mesh = CylinderMesh.new()
	band.mesh.top_radius = 9.1
	band.mesh.bottom_radius = 9.1
	band.mesh.height = 1.2
	band.mesh.material = stands.call("glow", AMBER, 2.0)
	band.transform = xf * Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(20, 0, 0))
	root.add_child(band)


## Power pylons marching off from `from` along `dir`, cables between them.
func _pylons(from: Vector3, dir: Vector3, count: int) -> void:
	var dark: Material = stands.get("dark")
	var cable: Material = stands.call("glow", Color(0.1, 0.1, 0.12), 0.0)
	var yaw := atan2(dir.x, dir.z)
	var gap := 140.0
	for k in count:
		var at := from + dir * gap * k
		var xf := Transform3D(Basis(Vector3.UP, yaw), at)
		for s: float in [-1.0, 1.0]:
			stands.call("box", Vector3(1.2, 46, 1.2), xf * Transform3D(Basis(Vector3.FORWARD, s * 0.09), Vector3(s * 4.0, 23, 0)), dark)
		stands.call("box", Vector3(26, 1.2, 1.2), xf * Transform3D(Basis(), Vector3(0, 44, 0)), dark)
		stands.call("box", Vector3(18, 1.0, 1.0), xf * Transform3D(Basis(), Vector3(0, 36, 0)), dark)
		stands.call("box", Vector3(1, 1, 1), xf * Transform3D(Basis(), Vector3(0, 47, 0)), stands.call("glow", RED, 5.0))
		if k + 1 < count:
			for x: float in [-12.0, 0.0, 12.0]:
				var a := at + Basis(Vector3.UP, yaw) * Vector3(x, 43, 0)
				var b := a + dir * gap
				stands.call("box", Vector3(0.15, 0.15, gap), Transform3D(Basis.looking_at(b - a), (a + b) * 0.5 - Vector3(0, 3, 0)), cable)


# --- Moving lights (view only) ---------------------------------------------------

## A searchlight on the ground throwing a slow sweeping beam up into the
## haze over the stands.
class SearchLight:
	extends Node3D

	var phase := 0.0
	var _beam: MeshInstance3D

	func _ready() -> void:
		var mat := ShaderMaterial.new()
		mat.shader = load("res://assets/shaders/light_beam.gdshader") as Shader
		mat.set_shader_parameter("tint", Color(0.9, 0.95, 1.0))
		mat.set_shader_parameter("strength", 0.06)
		var cone := CylinderMesh.new()
		cone.top_radius = 0.6
		cone.bottom_radius = 14.0
		cone.height = 320.0
		cone.cap_top = false
		cone.cap_bottom = false
		cone.material = mat
		_beam = MeshInstance3D.new()
		_beam.mesh = cone
		_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# The cone hangs from its narrow end, pointing up.
		_beam.position = Vector3(0, 160, 0)
		var pivot := Node3D.new()
		pivot.name = "Pivot"
		pivot.add_child(_beam)
		add_child(pivot)
		var lamp := MeshInstance3D.new()
		lamp.mesh = CylinderMesh.new()
		lamp.mesh.top_radius = 1.2
		lamp.mesh.bottom_radius = 1.4
		lamp.mesh.height = 1.6
		var glow := StandardMaterial3D.new()
		glow.emission_enabled = true
		glow.emission = Color(1.0, 0.97, 0.9)
		glow.emission_energy_multiplier = 6.0
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lamp.mesh.material = glow
		lamp.position = Vector3(0, 0.8, 0)
		add_child(lamp)

	func _process(_delta: float) -> void:
		var t := Time.get_ticks_msec() / 1000.0 * 0.18 + phase
		var pivot := get_node("Pivot") as Node3D
		pivot.rotation = Vector3(0.35 + 0.2 * sin(t * 1.3), t, 0)


## A camera drone pacing round a track a few metres up, its lamp blinking,
## drifting on the air. Where it is comes from the clock alone.
class Drone:
	extends Node3D

	var track: RaceTrack
	## Where round the lap it starts, 0 to 1.
	var offset := 0.0
	## Metres a second along the line.
	var pace := 22.0
	var _lamp: StandardMaterial3D

	func _ready() -> void:
		var body := MeshInstance3D.new()
		body.mesh = BoxMesh.new()
		body.mesh.size = Vector3(1.2, 0.35, 1.2)
		var shell := StandardMaterial3D.new()
		shell.albedo_color = Color(0.12, 0.12, 0.15)
		shell.metallic = 0.6
		body.mesh.material = shell
		add_child(body)
		for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var rotor := MeshInstance3D.new()
			rotor.mesh = CylinderMesh.new()
			rotor.mesh.top_radius = 0.45
			rotor.mesh.bottom_radius = 0.45
			rotor.mesh.height = 0.04
			rotor.mesh.material = shell
			rotor.position = Vector3(c.x * 0.8, 0.2, c.y * 0.8)
			add_child(rotor)
		_lamp = StandardMaterial3D.new()
		_lamp.emission_enabled = true
		_lamp.emission = Color(1.0, 0.2, 0.15)
		_lamp.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var lamp := MeshInstance3D.new()
		lamp.mesh = SphereMesh.new()
		lamp.mesh.radius = 0.15
		lamp.mesh.height = 0.3
		lamp.mesh.material = _lamp
		lamp.position = Vector3(0, -0.25, -0.6)
		add_child(lamp)

	func _process(_delta: float) -> void:
		if track == null or track.points.is_empty():
			return
		var t := Time.get_ticks_msec() / 1000.0
		var n := track.points.size()
		var along := fposmod(offset * track.length() + t * pace, track.length()) / RaceTrack.STEP
		var i := int(along) % n
		var j := (i + 1) % n
		var p := track.points[i].lerp(track.points[j], along - floorf(along))
		var side := track.side(i)
		position = p + side * (track.width * 0.5 + 4.0) + Vector3(0, 9.0 + sin(t * 0.9 + offset * 9.0) * 0.8, 0)
		rotation.y = track.heading(i)
		_lamp.emission_energy_multiplier = 8.0 if fmod(t + offset, 1.0) < 0.15 else 0.5
