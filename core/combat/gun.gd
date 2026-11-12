class_name Gun
extends Weapon
## Hitscan firearm. The shot always starts at the actor's eyes, never at the
## camera, so a third-person camera cannot shoot around corners.

signal fired(from: Vector3, to: Vector3)

var damage := 20.0
## Fires once per trigger pull instead of while the trigger is held.
var semi_auto := false
## Damage multiplier for a shot that lands on an actor's head.
var headshot_mult := 1.0
## Projectiles per shot. Each one deals `damage` and gets its own spread.
var pellets := 1
var fire_interval := 0.11
var mag_size := 30
var ammo_in_mag := 30
var reserve_ammo := 120
var reload_time := 1.7
var max_range := 150.0
var spread_deg := 1.2
var ads_spread_mult := 0.3
## Sustained fire widens the spread; it settles when you let go.
var bloom_per_shot := 0.35
var max_bloom := 2.6
var bloom_recovery := 5.0
## How far each shot kicks the shooter's view, in degrees.
var recoil_kick_deg := 0.55
var recoil_side_deg := 0.22
## How far the view magnifies while aiming: 1 is the plain sights. Optics raise it.
var ads_zoom := 1.0
## A suppressed gun leaves no tracer or muzzle flash and is much quieter.
var quiet := false
## The attachment item ids fitted to this gun (see `fit`).
var attachments: Array[String] = []

## Where each attachment slot sits on the greybox gun, in the visual's space
## (the gun points along -Z). `Look` moves them onto the real model.
const MOUNTS := {
	"optic": Vector3(0, 0.05, -0.1),
	"muzzle": Vector3(0, 0.02, -0.51),
	"grip": Vector3(0, -0.05, -0.38),
	"magazine": Vector3(0, -0.04, -0.22),
}

var _cooldown := 0.0
var _reload_left := 0.0
var _aiming := false
var _bloom := 0.0
var _rng := RandomNumberGenerator.new()


## Fits attachments (item ids tagged "attachment"): one per slot, later ones
## in the same slot ignored. Each one's "mult" stats scale this gun's tuning
## values, "zoom" sets how far it magnifies when aimed, and "quiet" suppresses
## it. Call once, after the gun's own stats are set and before it is equipped.
func fit(ids: Array) -> void:
	var taken := {}
	for id: String in ids:
		var slot := Loadout.attachment_slot(id)
		if slot == "" or taken.has(slot):
			continue
		taken[slot] = true
		attachments.append(id)
		var stats := ItemDB.item_stats(id)
		ads_zoom = maxf(ads_zoom, float(stats.get("zoom", 1.0)))
		quiet = quiet or bool(stats.get("quiet", false))
		var mult: Dictionary = stats.get("mult", {})
		for key: String in mult:
			if not key in self:
				push_warning("Gun.fit: %s scales unknown stat '%s'" % [id, key])
				continue
			var value: Variant = get(key)
			if typeof(value) == TYPE_INT:
				set(key, maxi(1, roundi(value * float(mult[key]))))
			else:
				set(key, value * float(mult[key]))
	ammo_in_mag = mag_size


## The attachment in a slot ("optic", "muzzle", "grip", "magazine"), or "".
func attachment_in(slot: String) -> String:
	for id in attachments:
		if Loadout.attachment_slot(id) == slot:
			return id
	return ""


func aim_zoom() -> float:
	return ads_zoom


func build_visual() -> Node3D:
	var root := Node3D.new()
	if is_sidearm:
		root.add_child(Weapon.make_part(Vector3(0.05, 0.08, 0.24), Vector3(0, 0, -0.06), Color(0.16, 0.16, 0.18)))
		root.add_child(Weapon.make_part(Vector3(0.045, 0.13, 0.06), Vector3(0, -0.09, 0.03), Color(0.1, 0.1, 0.1)))
		return root
	root.add_child(Weapon.make_part(Vector3(0.07, 0.1, 0.62), Vector3(0, 0, -0.2), Color(0.16, 0.16, 0.18)))
	root.add_child(Weapon.make_part(Vector3(0.06, 0.16, 0.08), Vector3(0, -0.12, 0.0), Color(0.3, 0.22, 0.16)))
	root.add_child(Weapon.make_part(Vector3(0.05, 0.14, 0.1), Vector3(0, -0.1, -0.22), Color(0.1, 0.1, 0.1)))
	if not attachments.is_empty():
		var holder := Node3D.new()
		holder.name = "Attachments"
		for id in attachments:
			var part := build_attachment(id)
			if part:
				part.position = MOUNTS.get(part.name, Vector3.ZERO)
				holder.add_child(part)
		root.add_child(holder)
	return root


## The shape of an attachment, named after its slot, with its origin where it
## mounts: under an optic, behind a muzzle device, on top of a grip or
## magazine. It points along -Z like the gun. They are built sci-fi: angular
## hex housings in gunmetal with lit energy details, holographic sight panes
## and lit reticles. An optic has a "Sight" child on its line of sight, at the
## eyepiece, which a first-person view lines up with the camera when aiming.
static func build_attachment(id: String) -> Node3D:
	var slot := Loadout.attachment_slot(id)
	if slot == "":
		return null
	var root := Node3D.new()
	root.name = slot
	root.set_meta("attachment", id)
	var metal := Color(0.1, 0.11, 0.13)
	var plate := Color(0.42, 0.44, 0.48)
	var cyan := Color(0.25, 0.9, 1.0)
	var amber := Color(1.0, 0.55, 0.15)
	var sight := Vector3.ZERO
	var model := str(ItemDB.item_stats(id).get("model", ""))
	match model:
		"reflex":
			# A holo emitter: a low angular base, a single arch, a glass pane
			# and a lit ring-and-dot reticle projected on it.
			root.add_child(Weapon.make_part(Vector3(0.034, 0.012, 0.075), Vector3(0, 0.006, 0.005), metal))
			root.add_child(Weapon.make_part(Vector3(0.036, 0.004, 0.03), Vector3(0, 0.013, 0.03), plate))
			root.add_child(Weapon.make_part(Vector3(0.02, 0.003, 0.004), Vector3(0, 0.014, 0.046), cyan, true))
			root.add_child(Weapon.make_part(Vector3(0.006, 0.05, 0.012), Vector3(0.022, 0.035, -0.022), metal))
			var arch := Weapon.make_part(Vector3(0.05, 0.006, 0.012), Vector3(0.0, 0.062, -0.022), metal)
			root.add_child(arch)
			root.add_child(_pane(Vector2(0.038, 0.044), Vector3(-0.002, 0.037, -0.022), cyan))
			_ring(root, 0.008, Vector3(-0.002, 0.037, -0.023), cyan, 10, 0.5)
			root.add_child(Weapon.make_part(Vector3(0.0018, 0.0018, 0.001), Vector3(-0.002, 0.037, -0.023), cyan, true))
			sight = Vector3(-0.002, 0.037, 0.14)
		"scope", "longscope":
			# A hex-section tube, open at both ends so you look down it, with
			# a lit lens ring, a rangefinder pod and a lit reticle inside.
			var long := model == "longscope"
			var length := 0.3 if long else 0.2
			var radius := 0.026 if long else 0.027
			var axis := 0.05 if long else 0.043
			for z: float in [-0.05, 0.05]:
				root.add_child(Weapon.make_part(Vector3(0.016, axis - radius * 0.6, 0.02), Vector3(0, (axis - radius * 0.6) * 0.5, z), metal))
			root.add_child(_tube(radius, length, Vector3(0, axis, 0), metal, false, 6))
			root.add_child(_tube(radius * 1.3, 0.05, Vector3(0, axis, -length * 0.5 + 0.025), plate, false, 6))
			root.add_child(_tube(radius * 1.32, 0.006, Vector3(0, axis, -length * 0.5 + 0.002), cyan, false, 6, true))
			root.add_child(_tube(radius * 1.12, 0.03, Vector3(0, axis, length * 0.5 - 0.015), plate, false, 6))
			var pod := length * 0.35
			root.add_child(Weapon.make_part(Vector3(0.018, 0.022, pod), Vector3(radius + 0.009, axis + 0.004, -0.01), plate))
			root.add_child(Weapon.make_part(Vector3(0.002, 0.006, pod * 0.8), Vector3(radius + 0.019, axis + 0.006, -0.01), cyan, true))
			if long:
				root.add_child(Weapon.make_part(Vector3(0.01, 0.01, 0.004), Vector3(radius + 0.009, axis + 0.004, -0.01 - pod * 0.5), Color(1.0, 0.2, 0.2), true))
			# The reticle: a fine lit ring, cross ticks and a centre dot.
			var at := Vector3(0, axis, -length * 0.5 + 0.06)
			var ink := Color(0.2, 0.85, 1.0)
			_ring(root, radius * 0.4, at, ink, 16, 0.25)
			for tick: Vector3 in [Vector3(radius * 0.72, 0, 0), Vector3(-radius * 0.72, 0, 0), Vector3(0, -radius * 0.72, 0)]:
				var size := Vector3(radius * 0.45, 0.0004, 0.0004) if tick.y == 0.0 else Vector3(0.0004, radius * 0.45, 0.0004)
				root.add_child(_glow(Weapon.make_part(size, at + tick, ink, true), 0.25))
			root.add_child(_glow(Weapon.make_part(Vector3(0.0009, 0.0009, 0.0004), at, Color(1.0, 0.3, 0.2), true), 0.6))
			sight = Vector3(0, axis, length * 0.5 + 0.022)
		"compensator":
			root.add_child(_tube(0.02, 0.07, Vector3(0, 0, -0.035), metal, true, 6))
			for z: float in [-0.018, -0.035, -0.052]:
				for x: float in [-0.012, 0.012]:
					root.add_child(Weapon.make_part(Vector3(0.006, 0.004, 0.008), Vector3(x, 0.018, z), cyan, true))
		"booster":
			root.add_child(_tube(0.015, 0.06, Vector3(0, 0, -0.03), metal, true, 6))
			for z: float in [-0.012, -0.03, -0.048]:
				root.add_child(_tube(0.0175, 0.005, Vector3(0, 0, z), amber, true, 6, true))
			root.add_child(_tube(0.021, 0.014, Vector3(0, 0, -0.064), plate, true, 6))
		"suppressor":
			root.add_child(_tube(0.022, 0.2, Vector3(0, 0, -0.1), metal, true, 6))
			root.add_child(_tube(0.024, 0.02, Vector3(0, 0, -0.012), plate, true, 6))
			for z: float in [-0.07, -0.12, -0.17]:
				root.add_child(_tube(0.0232, 0.004, Vector3(0, 0, z), cyan.darkened(0.3), true, 6, true))
		"vertical_grip":
			root.add_child(Weapon.make_part(Vector3(0.028, 0.105, 0.034), Vector3(0, -0.055, 0), metal))
			root.add_child(Weapon.make_part(Vector3(0.034, 0.012, 0.06), Vector3(0, -0.006, 0), plate))
			root.add_child(Weapon.make_part(Vector3(0.03, 0.06, 0.004), Vector3(0, -0.06, -0.018), cyan, true))
		"angled_grip":
			var wedge := Weapon.make_part(Vector3(0.028, 0.03, 0.1), Vector3(0, -0.02, 0), metal)
			wedge.rotation.x = -0.45
			root.add_child(wedge)
			root.add_child(Weapon.make_part(Vector3(0.034, 0.01, 0.1), Vector3(0, -0.005, 0), plate))
			root.add_child(Weapon.make_part(Vector3(0.03, 0.004, 0.05), Vector3(0, -0.012, 0.02), cyan, true))
		"extended_mag", "quick_mag":
			# An energy cell with a lit charge window down its side.
			var tall := 0.24 if model == "extended_mag" else 0.15
			var cell := Node3D.new()
			cell.rotation.x = -0.15 if model == "extended_mag" else 0.0
			cell.add_child(Weapon.make_part(Vector3(0.038, tall, 0.07), Vector3(0, -tall * 0.42, 0.0), metal))
			for x: float in [-0.0195, 0.0195]:
				cell.add_child(Weapon.make_part(Vector3(0.002, tall * 0.6, 0.012), Vector3(x, -tall * 0.45, 0.01), cyan, true))
			cell.add_child(Weapon.make_part(Vector3(0.042, 0.012, 0.074), Vector3(0, -tall * 0.92, 0), plate))
			root.add_child(cell)
			if model == "quick_mag":
				root.add_child(Weapon.make_part(Vector3(0.048, 0.02, 0.08), Vector3(0, -0.035, 0), plate))
				root.add_child(Weapon.make_part(Vector3(0.016, 0.03, 0.01), Vector3(0, -0.16, 0.03), amber, true))
		"drum":
			# A power drum: a hex cell side-on with a lit core.
			root.add_child(Weapon.make_part(Vector3(0.038, 0.06, 0.06), Vector3(0, -0.03, 0), metal))
			var drum := _tube(0.07, 0.06, Vector3(0, -0.1, 0.0), metal, true, 6)
			drum.rotation = Vector3(0, 0, PI / 2.0)
			root.add_child(drum)
			for x: float in [-0.031, 0.031]:
				var core := _tube(0.035, 0.002, Vector3(x, -0.1, 0.0), cyan, true, 6, true)
				core.rotation = Vector3(0, 0, PI / 2.0)
				root.add_child(core)
		_:
			root.add_child(Weapon.make_part(Vector3(0.04, 0.04, 0.06), Vector3.ZERO, metal))
	if slot == "optic":
		var marker := Marker3D.new()
		marker.name = "Sight"
		marker.position = sight
		root.add_child(marker)
	return root


## A cylinder along Z (`sides` 6 makes a hex section). Open at both ends unless
## `capped`, so you can look down an optic's tube. `lit` makes it glow.
static func _tube(radius: float, length: float, at: Vector3, color: Color, capped := false, sides := 20,
		lit := false) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = sides
	mesh.rings = 1
	mesh.cap_top = capped
	mesh.cap_bottom = capped
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if lit:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 1.6
	else:
		mat.metallic = 0.7
		mat.roughness = 0.35
	mesh.material = mat
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.rotation.x = PI / 2.0
	part.position = at
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return part


## A faint holographic glass pane facing along Z.
static func _pane(size: Vector2, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := QuadMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, 0.12)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material = mat
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = at
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return part


## A lit ring of `count` short bars facing along Z: a holographic reticle.
static func _ring(root: Node3D, radius: float, at: Vector3, color: Color, count: int, energy := 1.2) -> void:
	var bar := TAU * radius / float(count) * 0.8
	for i in count:
		var angle := TAU * float(i) / float(count)
		var part := Weapon.make_part(Vector3(bar, 0.0005, 0.0005), at + Vector3(cos(angle), sin(angle), 0) * radius, color, true)
		part.rotation.z = angle + PI / 2.0
		root.add_child(_glow(part, energy))


## Sets how brightly a lit part glows. Reticles stay dim so they read as
## fine lines, not a blaze.
static func _glow(part: MeshInstance3D, energy: float) -> MeshInstance3D:
	var mat := (part.mesh as BoxMesh).material as StandardMaterial3D
	mat.emission_energy_multiplier = energy
	return part


func controls_hint() -> String:
	return "Left mouse fire   Right mouse aim   R reload"


func tick(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_bloom = maxf(0.0, _bloom - bloom_recovery * delta)
	if visual:
		# Recoil kick settles back to rest.
		visual.position.z = move_toward(visual.position.z, 0.0, delta * 0.6)
		visual.rotation.x = move_toward(visual.rotation.x, 0.0, delta * 1.5)
	if _reload_left > 0.0:
		_reload_left -= delta
		if _reload_left <= 0.0:
			var need := mini(mag_size - ammo_in_mag, reserve_ammo)
			ammo_in_mag += need
			reserve_ammo -= need


func handle_input(cmd: ActorCommand, _delta: float) -> void:
	_aiming = cmd.secondary and _reload_left <= 0.0
	if cmd.reload_pressed:
		start_reload()
	var trigger := cmd.primary_pressed if semi_auto else cmd.primary
	if trigger and _cooldown <= 0.0 and _reload_left <= 0.0:
		if ammo_in_mag > 0:
			_fire()
		else:
			start_reload()


func on_holster() -> void:
	_aiming = false


func is_aiming() -> bool:
	return _aiming


func is_empty() -> bool:
	return ammo_in_mag <= 0 and _reload_left <= 0.0


func is_reloading() -> bool:
	return _reload_left > 0.0


func start_reload() -> void:
	if _reload_left <= 0.0 and ammo_in_mag < mag_size and reserve_ammo > 0:
		_reload_left = reload_time


func current_spread_deg() -> float:
	return (spread_deg + _bloom) * (ads_spread_mult if _aiming else 1.0)


func status_text() -> String:
	if is_reloading():
		return "%s  reloading" % display_name
	return "%s  %d / %d" % [display_name, ammo_in_mag, reserve_ammo]


func _fire() -> void:
	ammo_in_mag -= 1
	_cooldown = fire_interval
	if visual:
		visual.position.z = 0.05
		visual.rotation.x = 0.06
	var from := actor.get_eye_position()
	var aim := actor.get_aim_dir()
	var spread := deg_to_rad(spread_deg + _bloom) * (ads_spread_mult if _aiming else 1.0)
	_bloom = minf(max_bloom, _bloom + bloom_per_shot)
	var to := from + aim * max_range
	for i in pellets:
		var jitter := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1))
		var dir := (aim + jitter * tan(spread)).normalized()
		to = from + dir * max_range
		var hit := Combat.trace(actor, from, to)
		if not hit.is_empty():
			to = hit.position
			var info := DamageInfo.make(damage, actor, "bullet", to)
			if Combat.is_headshot(hit):
				info.headshot = true
				info.amount *= headshot_mult
			Combat.deal(hit.collider, info)
		if not quiet:
			Fx.tracer(actor.get_parent(), from + dir * 0.8 - Vector3(0, 0.15, 0), to)
	fired.emit(from, to)
	Sfx.play("shot", null if actor.is_player else from, -14.0 if quiet else 0.0)
