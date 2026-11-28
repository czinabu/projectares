extends RefCounted
## The deploy gates' art (`Look.gate_window`, `gate_teaser`, `gate_meter`,
## `gate_trim`): the live glimpse of a world through its gate, a sealed
## gate's hologram teaser, the slatted panels that show how full a world is
## and the fins' trims that pulse when someone steps through. View only:
## built by a map's dressing when `Look` draws, never on a server, and
## nothing here names a world. The glimpse is read from the world's
## `PlanetType` (its sky, rock, ground and weather), so a new world's gate
## shows its world without a line of art code.
##
## Load with `preload("res://core/visual/gate_look.gd")`.

const WINDOW_SHADER := preload("res://assets/shaders/gate_window.gdshader")
const METER_SHADER := preload("res://assets/shaders/gate_meter.gdshader")

## `Planet.weather` kinds, as the window shader numbers them.
const WEATHER := {"": 0, "embers": 1, "ash": 2, "snow": 3, "rain": 4, "sand": 5, "spores": 6}
## The colour of each kind of speck; embers take the planet's crack glow.
const SPECK_COLORS := {"ash": Color(0.62, 0.6, 0.58), "snow": Color(0.95, 0.97, 1.0),
	"rain": Color(0.6, 0.7, 0.8), "sand": Color(0.85, 0.72, 0.5), "spores": Color(0.65, 1.0, 0.55)}

static var _meter_mats := {}


## A world's glimpse on a sheet `size` metres (its floor at the bottom
## edge), facing +Z, edged in `rim`. `type` is the world's planet; with none
## the sheet shows a plain dusk.
static func window(type: PlanetType, size: Vector2, rim: Color, seed := 0.0) -> MeshInstance3D:
	var mat := ShaderMaterial.new()
	mat.shader = WINDOW_SHADER
	mat.set_shader_parameter("size", size)
	mat.set_shader_parameter("rim", rim)
	mat.set_shader_parameter("seed", seed)
	if type != null:
		for key: String in window_params(type):
			mat.set_shader_parameter(key, window_params(type)[key])
	return _sheet(size, mat, "Glimpse")


## The window shader's planet uniforms for a planet type.
static func window_params(type: PlanetType) -> Dictionary:
	var sky := type.sky
	var ground := type.ground
	var calm := type.calm
	var air := str(type.weather.get("air", ""))
	var storm := str(type.weather.get("storm", ""))
	if storm == "":
		storm = air
	var glow: Color = ground.get("crack_glow", Color(1.0, 0.4, 0.1))
	var out := {
		"zenith": sky.get("zenith_color", Color(0.2, 0.3, 0.6)),
		"horizon": sky.get("horizon_color", Color(0.7, 0.75, 0.8)),
		"haze": calm.get("fog_color", Color(0.5, 0.5, 0.55)),
		"rock": ground.get("rock_a", Color(0.3, 0.3, 0.3)),
		"ground": ground.get("base_a", Color(0.4, 0.4, 0.4)),
		"glow": glow,
		"glow_amount": clampf(float(ground.get("cracks", 0.0)) * float(ground.get("crack_energy", 1.0)), 0.0, 1.2),
		"peaks": float(type.horizon.get("peaks", 140.0)),
		"air": int(WEATHER.get(air, 0)),
		"storm": int(WEATHER.get(storm, 0)),
		"air_color": glow if air == "embers" else SPECK_COLORS.get(air, Color.WHITE),
		"storm_color": glow if storm == "embers" else SPECK_COLORS.get(storm, Color.WHITE),
	}
	if ground.has("cap_color"):
		out["cap"] = ground["cap_color"]
		out["cap_amount"] = 1.0
	if float(sky.get("body2_size", 0.0)) > 0.0:
		out["moon"] = sky.get("body2_color", Color(0.85, 0.85, 0.9))
		out["moon_size"] = clampf(float(sky.get("body2_size", 0.0)) * 2.0, 0.04, 0.12)
	return out


## A sealed gate's shutter: frost, hazard stripes and a dim hologram of a
## planet nobody has been to yet, in `rim`.
static func teaser(size: Vector2, rim: Color) -> MeshInstance3D:
	var mat := ShaderMaterial.new()
	mat.shader = WINDOW_SHADER
	mat.set_shader_parameter("size", size)
	mat.set_shader_parameter("mode", 1)
	mat.set_shader_parameter("rim", rim)
	return _sheet(size, mat, "Teaser")


## A slatted panel `size` metres facing +Z, one slat for each of `slats`
## places. Its fill, pulse and idle are instance uniforms ("filled",
## "pulse", "idle"), so panels of one colour share a material.
static func meter(size: Vector2, color: Color, slats: int) -> MeshInstance3D:
	var key := [color, size, slats]
	var mat: ShaderMaterial = _meter_mats.get(key)
	if mat == null:
		mat = ShaderMaterial.new()
		mat.shader = METER_SHADER
		mat.set_shader_parameter("color", color)
		mat.set_shader_parameter("height", size.y)
		mat.set_shader_parameter("width", size.x)
		mat.set_shader_parameter("slats", float(slats))
		_meter_mats[key] = mat
	return _sheet(size, mat, "Meter")


## Puts the pulsing light on a strip of trim (a thin box, `height` metres
## tall), lit full; a pulse runs up it with its "pulse" instance uniform.
static func trim(strip: MeshInstance3D, color: Color, height: float) -> void:
	var key := [color, height, "trim"]
	var mat: ShaderMaterial = _meter_mats.get(key)
	if mat == null:
		mat = ShaderMaterial.new()
		mat.shader = METER_SHADER
		mat.set_shader_parameter("color", color)
		mat.set_shader_parameter("height", height)
		mat.set_shader_parameter("slatted", 0.0)
		_meter_mats[key] = mat
	strip.material_override = mat
	strip.set_instance_shader_parameter("filled", 1.0)


static func _sheet(size: Vector2, mat: Material, name: String) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = size
	var node := MeshInstance3D.new()
	node.name = name
	node.mesh = quad
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node
