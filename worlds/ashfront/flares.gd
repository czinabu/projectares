extends Node3D
## Flares over the real fighting (DESIGN.md "The battle around you"): where
## soldiers near you are trading fire, now and then one of them sends up an
## illumination flare, which bursts high over the fight and drifts down
## under its chute, lighting the ground round it in a slow, swinging glare.
## More of them the hotter the war (the map's "war_intensity"), none in an
## ash storm. View only and never in a server: the map adds it only where
## `Look` is on, and each screen picks its own (as the scenery army's
## fallen are its own). Nothing here touches the simulation; it only reads
## how many rounds a soldier's gun has fired (`Gun.shots_fired`).
##
## Cheap by design: it looks at a few soldiers a second, never all of them,
## and at most `LIGHTS` flares are up at once, each one quad and one
## shadowless light.

const GameSettings := preload("res://core/settings/game_settings.gd")

## Flares up at once (each carries a light).
const LIGHTS := 2
## Seconds between flares, in a quiet war and in all-out war.
const GAP := Vector2(45.0, 12.0)
## How far from the camera a fight may be to get one (m).
const REACH := Vector2(35.0, 240.0)
## How high over the fight it bursts (m), how fast it climbs there (m/s)
## and sinks under its chute (m/s).
const BURST_HEIGHT := Vector2(55.0, 75.0)
const CLIMB := 70.0
const SINK := 2.6
## How long it burns once lit (s), and the light's reach (m) and energy.
const BURN := 22.0
const LIGHT_RANGE := 75.0
const LIGHT_ENERGY := 4.0
## Soldiers looked at a second.
const LOOKS := 6

var _rng := RandomNumberGenerator.new()
## One flare: { node, light, from, at, t, lit (s burning, -1 climbing), sway }.
var _flares: Array[Dictionary] = []
var _next := 8.0
var _look_wait := 0.0
var _cursor := 0
## Each soldier looked at: the gun's shot count when last seen.
var _counts := {}
## Soldiers seen firing since the last flare: [actor, ...].
var _firing: Array = []
var _material: StandardMaterial3D


func _ready() -> void:
	name = "Flares"
	_rng.randomize()
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_material.albedo_color = Color(1.0, 0.85, 0.7)
	_material.albedo_texture = _glow_texture()
	_material.disable_fog = true


func _heat() -> float:
	var map := get_parent()
	return clampf(float(map.get_meta("war_intensity", 0.0)), 0.0, 1.0) if map != null else 0.0


func _process(delta: float) -> void:
	delta = minf(delta, 0.1)
	_look_wait -= delta
	if _look_wait <= 0.0:
		_look_wait = 1.0
		_look()
	_next -= delta
	if _next <= 0.0:
		var heat := _heat()
		_next = lerpf(GAP.x, GAP.y, heat) / maxf(GameSettings.war_share(), 0.2) * _rng.randf_range(0.7, 1.3)
		if Look.weather_cover < 0.4 and _flares.size() < LIGHTS:
			launch_over_fight()
	_tick_flares(delta)


## Looks at a few soldiers: any whose gun has fired since the last look is
## in a fight.
func _look() -> void:
	var actors := get_tree().get_nodes_in_group("actors")
	if actors.is_empty():
		return
	for i in mini(LOOKS, actors.size()):
		_cursor = (_cursor + 1) % actors.size()
		var node: Variant = actors[_cursor]
		if not is_instance_valid(node):
			continue
		var actor := node as Actor
		if actor == null or actor.is_dead:
			continue
		var gun := actor.get_active_weapon() as Gun
		if gun == null:
			continue
		var id := actor.get_instance_id()
		var was := int(_counts.get(id, gun.shots_fired))
		_counts[id] = gun.shots_fired
		if gun.shots_fired > was and not _firing.has(actor):
			_firing.append(actor)
	if _counts.size() > 400:
		_counts.clear()


## Sends a flare up over one of the soldiers seen firing, within reach of
## the camera; false when there is none.
func launch_over_fight() -> bool:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	var picked := Vector3.INF
	for each: Variant in _firing:
		if not is_instance_valid(each):
			continue
		var at: Vector3 = (each as Node3D).global_position
		var reach := camera.global_position.distance_to(at) if camera != null else REACH.x
		if reach >= REACH.x and reach <= REACH.y:
			picked = at
			break
	_firing.clear()
	if not picked.is_finite():
		return false
	launch(picked)
	return true


## A flare from `ground` (a fight's spot), bursting high over it.
func launch(ground: Vector3) -> Dictionary:
	var node := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(5.0, 5.0)
	quad.material = _material
	node.mesh = quad
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_end = 1500.0
	add_child(node)
	var light := OmniLight3D.new()
	light.omni_range = LIGHT_RANGE
	light.light_color = Color(1.0, 0.82, 0.62)
	light.light_energy = 0.0
	light.shadow_enabled = false
	node.add_child(light)
	var drift := Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0)).normalized() * _rng.randf_range(8.0, 20.0)
	var flare := {"node": node, "light": light, "from": ground + Vector3(0, 2.0, 0),
			"at": ground + drift + Vector3(0, _rng.randf_range(BURST_HEIGHT.x, BURST_HEIGHT.y), 0),
			"t": 0.0, "lit": -1.0, "sway": _rng.randf() * TAU}
	node.global_position = flare.from
	_flares.append(flare)
	return flare


func _tick_flares(delta: float) -> void:
	for flare in _flares.duplicate():
		var node: MeshInstance3D = flare.node
		var light: OmniLight3D = flare.light
		flare.t = float(flare.t) + delta
		var from: Vector3 = flare.from
		var at: Vector3 = flare.at
		if float(flare.lit) < 0.0:
			# Climbing: a small hot spark.
			var k := clampf(float(flare.t) * CLIMB / from.distance_to(at), 0.0, 1.0)
			node.global_position = from.lerp(at, 1.0 - (1.0 - k) * (1.0 - k))
			node.scale = Vector3.ONE * 0.4
			if k >= 1.0:
				flare.lit = 0.0
			continue
		flare.lit = float(flare.lit) + delta
		var lit := float(flare.lit)
		if lit >= BURN:
			node.queue_free()
			_flares.erase(flare)
			continue
		# Swinging under its chute as it sinks.
		var sway := float(flare.sway) + lit * 1.3
		node.global_position = at + Vector3(sin(sway) * 1.6, -lit * SINK, cos(sway * 0.8) * 1.2)
		var flicker := 0.85 + 0.15 * sin(lit * 23.0) * sin(lit * 9.0)
		var strength := smoothstep(0.0, 0.6, lit) * (1.0 - smoothstep(BURN - 4.0, BURN, lit)) * (1.0 - Look.weather_cover)
		node.scale = Vector3.ONE * (0.6 + 0.4 * strength)
		light.light_energy = LIGHT_ENERGY * strength * flicker


## Flares up now (for tests).
func flares() -> Array[Dictionary]:
	return _flares


static func _glow_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.add_point(0.18, Color(1, 0.9, 0.75, 0.9))
	gradient.set_color(gradient.get_point_count() - 1, Color(1, 0.6, 0.3, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	return tex
