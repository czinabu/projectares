class_name Gun
extends Weapon
## Firearm. The shot always starts at the actor's eyes, never at the camera,
## so a third-person camera cannot shoot around corners.
##
## One class covers every gun; item stats pick the behavior. Most guns are
## hitscan. Power weapons (items tagged "power") turn on the rest:
## `charge_time` (hold to charge, fires when full), `pierce` and `wall_pierce`
## (a shot that keeps going), `projectile` ("rocket" or "grenade": a moving
## round that bursts with `splash_radius`), `heat_seek` (rockets lock onto a
## thrusting jetpack) and `spin_up` (barrels spin before firing and slow you).

signal fired(from: Vector3, to: Vector3)

var damage := 20.0
## Fires once per trigger pull instead of while the trigger is held.
var semi_auto := false
## A semi-auto remembers a pull made this long before it is ready (between
## shots, or as a reload ends) and fires then, so a click a moment early is
## not swallowed.
var press_buffer := 0.12
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
## How far the held model jumps back and tips up at a shot from a gun that
## kicks `MODEL_KICK_AT` degrees. Harder kicking guns jump further (up to
## `MODEL_KICK_MAX` times), and less while aimed, so a scope stays off the eye.
const MODEL_KICK := Vector2(0.05, 0.06)
const MODEL_KICK_AT := 0.55
const MODEL_KICK_MAX := 3.0
const MODEL_KICK_AIMED := 0.4
## Effects. Power weapons use these to look and sound like what they are.
var tracer_color := Color(1.0, 0.85, 0.4)
var shot_sound := "shot"
## "bullet" for ordinary rounds. Power weapons name their own ("rail",
## "plasma", "arc") so feeds and guards can tell them apart.
var damage_kind := "bullet"
## Seconds the trigger must be held before the shot goes. 0 fires at once.
var charge_time := 0.0
## How many bodies one shot passes through, and how many walls.
var pierce := 0
var wall_pierce := 0
## A charged shot leaves a beam that hangs in the air this long, so everyone
## can see where it came from.
var beam_time := 0.0
## "" for hitscan, or "rocket" / "grenade" for a round that flies.
var projectile := ""
var projectile_speed := 40.0
## 0 flies straight, 1 drops like a thrown stone.
var projectile_gravity := 0.0
## Grenades: how many times a round bounces, and seconds before it bursts.
var bounces := 0
var fuse_time := 4.0
## Burst on impact: full `splash_damage` at the centre, falling to a third
## at the edge. Walls shelter whoever is behind them.
var splash_radius := 0.0
var splash_damage := 0.0
## Rockets steer onto a hostile actor whose flight rig is thrusting or hot,
## within this cone (degrees) of the aim when fired. 0 never locks.
var heat_seek_cone := 0.0
var heat_seek_range := 140.0
var heat_seek_turn := 2.2
## Barrels take this long to spin up. Holding aim keeps them spinning.
var spin_up := 0.0
## Walk speed multiplier with the barrels fully spun.
var spin_move_mult := 1.0
## How far the view magnifies while aiming: 1 is the plain sights. Optics raise it.
var ads_zoom := 1.0
## A suppressed gun leaves no tracer or muzzle flash and is much quieter.
var quiet := false
## How far a shot is heard (`Combat.noise`), and a suppressed one. Bots on
## patrol within it come to look; a blade makes no such noise.
var shot_noise := 45.0
var quiet_noise := 10.0
## A gun is heard at most this often, so a long burst costs one scan.
var noise_every := 0.5
var _noise_left := 0.0
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
var _charge := 0.0
var _spin := 0.0
## Seconds a semi-auto's last pull is still remembered (`press_buffer`).
var _press_left := 0.0


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
	if charge_time > 0.0:
		return "Hold left mouse to charge, it fires when full"
	if spin_up > 0.0:
		return "Hold left mouse to spin up and fire   Right mouse keeps it spinning"
	return "Left mouse fire   Right mouse aim   R reload"


func tick(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_noise_left = maxf(0.0, _noise_left - delta)
	_press_left = maxf(0.0, _press_left - delta)
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


func handle_input(cmd: ActorCommand, delta: float) -> void:
	_aiming = cmd.secondary and _reload_left <= 0.0 and spin_up <= 0.0
	if cmd.reload_pressed:
		start_reload()
	if spin_up > 0.0:
		var spinning := (cmd.primary or cmd.secondary) and _reload_left <= 0.0
		_spin = clampf(_spin + (delta if spinning else -delta * 1.5) / spin_up, 0.0, 1.0)
		if _spin < 1.0:
			return
	if charge_time > 0.0:
		if not cmd.primary or _cooldown > 0.0 or _reload_left > 0.0 or ammo_in_mag <= 0:
			_charge = 0.0
			if cmd.primary and ammo_in_mag <= 0 and _cooldown <= 0.0:
				start_reload()
			return
		_charge += delta
		if _charge < charge_time:
			return
		_charge = 0.0
	if cmd.primary_pressed:
		_press_left = press_buffer
	var trigger := (cmd.primary_pressed or _press_left > 0.0) if semi_auto else cmd.primary
	if trigger and _cooldown <= 0.0 and _reload_left <= 0.0:
		_press_left = 0.0
		if ammo_in_mag > 0:
			_fire()
		else:
			start_reload()


func drop_aim() -> void:
	_aiming = false


func on_holster() -> void:
	_aiming = false
	_charge = 0.0
	_spin = 0.0
	_press_left = 0.0


## How far a charge has built, 0 to 1.
func charge_fraction() -> float:
	return clampf(_charge / charge_time, 0.0, 1.0) if charge_time > 0.0 else 0.0


## How far the barrels have spun up, 0 to 1.
func spin_fraction() -> float:
	return _spin


func move_speed_mult() -> float:
	return lerpf(1.0, spin_move_mult, _spin) if spin_up > 0.0 else 1.0


## True for a raid-only power weapon (see `PowerArmory`).
func is_power() -> bool:
	return item_id != "" and ItemDB.has_tag(item_id, "power")


## True when a power weapon has nothing left to fire. It is never reloaded.
func is_spent() -> bool:
	return ammo_in_mag <= 0 and reserve_ammo <= 0 and _reload_left <= 0.0


func is_aiming() -> bool:
	return _aiming


func is_empty() -> bool:
	return ammo_in_mag <= 0 and _reload_left <= 0.0


func is_reloading() -> bool:
	return _reload_left > 0.0


## Seconds left of the reload under way (0 when not reloading).
func reload_left() -> float:
	return maxf(_reload_left, 0.0)


func start_reload() -> void:
	if _reload_left <= 0.0 and ammo_in_mag < mag_size and reserve_ammo > 0:
		_reload_left = reload_time


func current_spread_deg() -> float:
	return (spread_deg + _bloom + _air_spread()) * (ads_spread_mult if _aiming else 1.0)


## Extra spread from shooting in the air (`Actor.air_aim`).
func _air_spread() -> float:
	return actor.air_spread_deg * actor.air_aim() if actor else 0.0


func status_text() -> String:
	if is_reloading():
		return "%s  reloading" % display_name
	if is_power():
		if is_spent():
			return "%s  spent, swap it at a rack" % display_name
		var shots := "%s  %d shots" % [display_name, ammo_in_mag + reserve_ammo]
		if _charge > 0.0:
			shots += "  charging %d%%" % roundi(charge_fraction() * 100.0)
		elif _spin > 0.0 and _spin < 1.0:
			shots += "  spinning up"
		return shots
	return "%s  %d / %d" % [display_name, ammo_in_mag, reserve_ammo]


func _fire() -> void:
	ammo_in_mag -= 1
	_cooldown = fire_interval
	if visual:
		var kick := model_kick()
		visual.position.z = kick.x
		visual.rotation.x = kick.y
	var from := actor.get_eye_position()
	var aim := actor.get_aim_dir()
	var spread := deg_to_rad(spread_deg + _bloom + _air_spread()) * (ads_spread_mult if _aiming else 1.0)
	var air_bloom := lerpf(1.0, actor.air_bloom_mult, actor.air_aim())
	_bloom = minf(max_bloom * air_bloom, _bloom + bloom_per_shot * air_bloom)
	var to := from + aim * max_range
	for i in pellets:
		var dir := spread_dir(aim, spread, _rng.randf(), _rng.randf())
		var muzzle := from + dir * 0.8 - Vector3(0, 0.15, 0)
		if projectile != "":
			_launch(muzzle, dir)
			continue
		to = _trace_shot(from, dir)
		# The shot is judged from the eyes; what is drawn leaves the barrel.
		var drawn_from := muzzle_point(muzzle)
		if beam_time > 0.0:
			Fx.beam(actor.get_parent(), drawn_from, to, tracer_color, beam_time)
		elif not quiet:
			Fx.tracer(actor.get_parent(), drawn_from, to, tracer_color)
	fired.emit(from, to)
	if _noise_left <= 0.0:
		_noise_left = noise_every
		Combat.noise(actor, from, quiet_noise if quiet else shot_noise)
	Sfx.play(shot_sound, null if actor.is_player else from, -14.0 if quiet else 0.0)


## Where a shot's flash and tracer start: the "Muzzle" marker the art layer
## puts on the gun's model, as it is held in whichever view is drawn, or
## `fallback` when there is none (headless, greybox). View only: the shot
## itself always leaves the eyes, and nothing here changes the simulation.
func muzzle_point(fallback: Vector3) -> Vector3:
	var marker := visual.get_node_or_null("Muzzle") as Node3D if visual != null else null
	if marker == null or not marker.is_inside_tree():
		return fallback
	var at := marker.global_position
	# The actor parks its hand node every tick; the views move it to where
	# the weapon is drawn and leave that here as the "shown" meta.
	var hand := actor.hand if actor != null else null
	if hand != null and hand.has_meta("shown"):
		at = (hand.get_meta("shown") as Transform3D) * (hand.global_transform.affine_inverse() * at)
	return at


## How far back (m) and up (radians) the held model jumps at a shot.
func model_kick() -> Vector2:
	return MODEL_KICK * clampf(recoil_kick_deg / MODEL_KICK_AT, 0.6, MODEL_KICK_MAX) \
			* (MODEL_KICK_AIMED if _aiming else 1.0)


## A direction within `spread` radians of `aim`, spread evenly over a round
## cone (never a square one), picked by `turn` and `out`, each 0 to 1.
static func spread_dir(aim: Vector3, spread: float, turn: float, out: float) -> Vector3:
	var side := aim.cross(Vector3.UP)
	side = side.normalized() if side.length_squared() > 0.0001 else Vector3.RIGHT
	var up := side.cross(aim).normalized()
	var angle := turn * TAU
	return (aim + (side * cos(angle) + up * sin(angle)) * sqrt(out) * tan(spread)).normalized()


## One hitscan round along `dir`. Deals its damage and returns where it
## stopped. With `pierce` or `wall_pierce` it keeps going through bodies and
## walls, losing a quarter of its damage at each.
func _trace_shot(from: Vector3, dir: Vector3) -> Vector3:
	var start := from
	var end := from + dir * max_range
	var amount := damage
	var bodies_left := pierce
	var walls_left := wall_pierce
	var struck: Array[Actor] = []
	for step in 1 + pierce + wall_pierce:
		var hit := Combat.trace(actor, start, end)
		if hit.is_empty():
			return end
		var at: Vector3 = hit.position
		var body := hit.collider as Actor
		if body != null:
			if not body in struck:
				struck.append(body)
				var info := DamageInfo.make(amount, actor, damage_kind, at)
				info.weapon_id = item_id
				if Combat.is_headshot(hit):
					info.headshot = true
					info.amount *= headshot_mult
				Combat.deal(body, info)
			if bodies_left <= 0:
				return at
			bodies_left -= 1
			# Step past the body's far side before tracing again.
			start = at + dir * (Actor.BODY_RADIUS * 2.0 + 0.05)
		else:
			if walls_left <= 0:
				return at
			walls_left -= 1
			start = at + dir * 0.6
		amount *= 0.75
	return end


func _launch(at: Vector3, dir: Vector3) -> void:
	var shot := Round.new()
	shot.gun_shooter = actor
	shot.kind = projectile
	shot.damage_kind = damage_kind
	shot.velocity = dir * projectile_speed
	shot.gravity = projectile_gravity * 20.0
	shot.bounces_left = bounces
	shot.fuse = fuse_time
	shot.direct_damage = damage
	shot.splash_radius = splash_radius
	shot.splash_damage = splash_damage
	shot.color = tracer_color
	shot.turn_rate = heat_seek_turn
	if heat_seek_cone > 0.0:
		shot.target = heat_target(actor, dir, heat_seek_cone, heat_seek_range)
	actor.get_parent().add_child(shot)
	shot.global_position = at


## The hostile actor in front of `shooter` that a heat-seeker would lock
## onto: one whose flight rig is thrusting or still hot, inside `cone_deg` of
## `dir` and in sight. The nearest to the aim line wins. Null for none.
static func heat_target(shooter: Actor, dir: Vector3, cone_deg: float, reach: float) -> Actor:
	var world := Worlds.of(shooter)
	var eye := shooter.get_eye_position()
	var best: Actor = null
	var best_angle := deg_to_rad(cone_deg)
	for node in shooter.get_tree().get_nodes_in_group("actors"):
		var other := node as Actor
		if other == null or other == shooter or other.is_dead or not Raid.together(shooter, other):
			continue
		if not (other.flight.is_thrusting or other.flight.heat >= other.flight.max_heat * 0.3):
			continue
		if world and not world.can_damage(shooter, other, DamageInfo.make(0.0, shooter, "plasma")):
			continue
		var chest := other.global_position + Vector3(0.0, Actor.BODY_HEIGHT * 0.6, 0.0)
		var to := chest - eye
		if to.length() > reach:
			continue
		var angle := dir.angle_to(to)
		if angle > best_angle:
			continue
		var query := PhysicsRayQueryParameters3D.create(eye, chest, Actor.LAYER_WORLD)
		if not shooter.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			continue
		best = other
		best_angle = angle
	return best


## Bursts at `at`: damage to every actor in `radius`, full at the centre and
## a third at the edge, for anyone not sheltered by a wall. Goes through
## `Combat.deal` like every hit, so world rules and guards still apply.
static func splash(source: Actor, at: Vector3, radius: float, amount: float, kind: String,
		space_owner: Node3D) -> int:
	var hurt := 0
	if radius <= 0.0 or amount <= 0.0 or space_owner == null or not space_owner.is_inside_tree():
		return 0
	var space := space_owner.get_world_3d().direct_space_state
	for node in space_owner.get_tree().get_nodes_in_group("actors"):
		var other := node as Actor
		if other == null or other.is_dead:
			continue
		if source != null and is_instance_valid(source) and not Raid.together(source, other):
			continue
		var chest := other.global_position + Vector3(0.0, Actor.BODY_HEIGHT * 0.5, 0.0)
		var dist := at.distance_to(chest)
		if dist > radius:
			continue
		var query := PhysicsRayQueryParameters3D.create(at, chest, Actor.LAYER_WORLD)
		if not space.intersect_ray(query).is_empty():
			continue
		var share := lerpf(1.0, 1.0 / 3.0, dist / radius)
		var info := DamageInfo.make(amount * share, source if is_instance_valid(source) else null, kind, chest)
		if Combat.deal(other, info):
			hurt += 1
			# The blast throws people about a little.
			var push := (chest - at).normalized() if dist > 0.01 else Vector3.UP
			other.add_impulse((push + Vector3.UP * 0.6) * 6.0 * share)
	return hurt


## A round in flight: a plasma rocket or a bouncing arc grenade. Moves itself
## each physics tick, so it runs the same on a headless server. On a client
## it flies for show: `Combat.deal` refuses there, the server decides.
class Round extends Node3D:
	var gun_shooter: Actor
	var kind := "rocket"
	var damage_kind := "plasma"
	var velocity := Vector3.ZERO
	var gravity := 0.0
	var bounces_left := 0
	var fuse := 4.0
	var direct_damage := 0.0
	var splash_radius := 0.0
	var splash_damage := 0.0
	var color := Color.WHITE
	var target: Actor
	var turn_rate := 2.0
	var _age := 0.0
	var _done := false

	func _ready() -> void:
		var mesh := SphereMesh.new()
		mesh.radius = 0.14 if kind == "grenade" else 0.18
		mesh.height = mesh.radius * 2.0
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = color
		mesh.material = mat
		var body := MeshInstance3D.new()
		body.mesh = mesh
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(body)

	func _physics_process(delta: float) -> void:
		if _done:
			return
		_age += delta
		if target != null and is_instance_valid(target) and not target.is_dead:
			var chest := target.global_position + Vector3(0.0, Actor.BODY_HEIGHT * 0.6, 0.0)
			var want := (chest - global_position).normalized() * velocity.length()
			velocity = velocity.slerp(want, clampf(turn_rate * delta, 0.0, 1.0)) if velocity.length() > 0.01 else want
		velocity.y -= gravity * delta
		var from := global_position
		var to := from + velocity * delta
		var mask := Actor.LAYER_WORLD | Actor.LAYER_ACTORS
		var query := PhysicsRayQueryParameters3D.create(from, to, mask)
		# A round never hits its own shooter on the way out of the barrel.
		if gun_shooter != null and is_instance_valid(gun_shooter):
			query.exclude = [gun_shooter.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			var body := hit.collider as Actor
			if body != null:
				_burst(hit.position, body)
				return
			if kind == "grenade" and bounces_left > 0:
				bounces_left -= 1
				velocity = velocity.bounce(hit.normal) * 0.55
				global_position = hit.position + hit.normal * 0.05
				return
			_burst(hit.position, null)
			return
		global_position = to
		Fx.trail(get_parent(), from, to, color)
		if _age >= fuse:
			_burst(global_position, null)

	func _burst(at: Vector3, struck: Actor) -> void:
		_done = true
		var source := gun_shooter if is_instance_valid(gun_shooter) else null
		if struck != null and direct_damage > 0.0:
			Combat.deal(struck, DamageInfo.make(direct_damage, source, damage_kind, at))
		Gun.splash(source, at, splash_radius, splash_damage, damage_kind, self)
		Fx.burst(get_parent(), at, splash_radius, color)
		Sfx.play("plasma_burst", at)
		queue_free()
