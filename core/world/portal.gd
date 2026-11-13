class_name Portal
extends Node3D
## A squad portal: a ring of light opened from the watch (the Mission tab's
## portal icon, `Hud.portal_slot`) that leads to a world or the arena. It
## unfolds in front of whoever opened it, stays open `open_time` seconds for
## their squad (`Raid.squad_of`: their clan online) to walk through, then
## folds away.
##
## Portals open only in safe spaces: your home base (`HomeBase.open_portal`)
## and safe-zone worlds such as the plaza (`Raid.open_portal`, where only the
## authority opens them and `NetSession` shows them to everyone there). They
## are a way out to a fight, never out of one: leaving a world still means
## signing out (`Raid.begin_sign_out`). Walking through lands you with the
## "portal" drop (`Raid.PORTAL_DROP`), at the world's gate outpost where it
## has one.
##
## The portal decides nothing itself. It knows where it leads, whose side may
## use it, how old it is and whether a point is inside it; whoever owns it
## (the base or the raid) ticks it, sends walkers through and frees it. The
## ring is the same object in every view, built as greybox here.

## How long a portal stays open, in seconds.
var open_time := 15.0
## How long it takes to unfold, and to fold away at the end.
var unfold_time := 0.6
## How far in front of the opener it opens, and how far from a wall it keeps.
var distance := 2.6
var wall_gap := 0.7
## The ring's radius, and the space inside it that counts as walking in:
## half its width, its height and half its depth.
var ring_radius := 1.25
var inside := Vector3(0.95, 2.6, 0.55)

## A destination id (a raid world's id or the arena's) this portal leads to.
var destination := ""
## The squad key (`Raid.squad_of`) that may walk through. "" lets anyone.
var side := ""
## The owner key of whoever opened it (`Raid.PlayerState.owner`).
var opener := ""
## Shown over the ring.
var opener_name := ""
## Seconds since it opened.
var age := 0.0
## On a client: whether the viewer's side may use it (the server says).
var usable := true
## Actors already sent through, so nobody is sent twice.
var sent: Array[Actor] = []

var _ring: MeshInstance3D
var _veil: MeshInstance3D
var _label: Label3D


## Every place a portal can lead: each raid world, then the arena.
static func destinations() -> Array[String]:
	var out: Array[String] = []
	for world in Worlds.raid_worlds():
		out.append(world.id)
	out.append(Arena.ArenaVenue.ID)
	return out


## The name a destination is shown by.
static func title_of(id: String) -> String:
	if id == Arena.ArenaVenue.ID:
		return "the arena"
	var world := Worlds.get_world(id)
	return world.display_name if world != null else id


## Where a portal opened by someone at `eye`, looking along `forward`, stands:
## `distance` ahead on the floor (`floor_y`), brought in short of a wall.
## Facing back at them.
static func spot(space: PhysicsDirectSpaceState3D, eye: Vector3, forward: Vector3, floor_y: float,
		p_distance := 2.6, p_wall_gap := 0.7) -> Transform3D:
	var flat := Vector3(forward.x, 0.0, forward.z)
	flat = flat.normalized() if flat.length() > 0.01 else Vector3.FORWARD
	var reach := p_distance
	if space != null:
		var query := PhysicsRayQueryParameters3D.create(eye, eye + flat * (p_distance + p_wall_gap), Actor.LAYER_WORLD)
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			reach = maxf(eye.distance_to(hit.position) - p_wall_gap, 0.8)
	var at := Vector3(eye.x, floor_y, eye.z) + flat * reach
	# Its local +Z faces back at the opener, like the base's displays.
	return Transform3D(Basis(Vector3.UP, atan2(-flat.x, -flat.z)), at)


func _ready() -> void:
	add_to_group("squad_portal")
	_build()
	_update_view()


## True until it has been open its full time.
func is_open() -> bool:
	return age < open_time


func time_left() -> float:
	return maxf(open_time - age, 0.0)


## How far unfolded the ring is, 0 to 1: it opens, holds, then folds away.
func openness() -> float:
	var t := minf(age / maxf(unfold_time, 0.01), 1.0)
	var closing := minf(time_left() / maxf(unfold_time, 0.01), 1.0)
	return clampf(minf(t, closing), 0.0, 1.0)


## Whether `point` (an actor's feet) is inside the ring.
func contains(point: Vector3) -> bool:
	if not is_open() or openness() < 1.0:
		return false
	var local := global_transform.affine_inverse() * point
	return absf(local.x) <= inside.x and absf(local.z) <= inside.z and local.y >= -0.6 and local.y <= inside.y


## Ages the portal. Whoever owns it calls this every physics tick.
func tick(delta: float) -> void:
	age += delta
	_update_view()


func _build() -> void:
	var color := Color(0.35, 0.95, 1.0) if usable else Color(1.0, 0.45, 0.35)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = color
	var torus := TorusMesh.new()
	torus.inner_radius = ring_radius - 0.09
	torus.outer_radius = ring_radius
	torus.rings = 48
	torus.ring_segments = 8
	_ring = MeshInstance3D.new()
	_ring.name = "Ring"
	_ring.mesh = torus
	_ring.material_override = glow
	# Stood up on its edge, its hole facing the opener.
	_ring.rotation.x = PI / 2.0
	_ring.position.y = ring_radius + 0.05
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	var veil_mat := StandardMaterial3D.new()
	veil_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	veil_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	veil_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	veil_mat.albedo_color = Color(color, 0.35)
	var disc := CylinderMesh.new()
	disc.top_radius = ring_radius - 0.08
	disc.bottom_radius = ring_radius - 0.08
	disc.height = 0.02
	disc.radial_segments = 40
	_veil = MeshInstance3D.new()
	_veil.name = "Veil"
	_veil.mesh = disc
	_veil.material_override = veil_mat
	_veil.rotation.x = PI / 2.0
	_veil.position.y = ring_radius + 0.05
	_veil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_veil)
	_label = Label3D.new()
	_label.name = "Sign"
	_label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_label.pixel_size = 0.0035
	_label.font_size = 64
	_label.outline_size = 10
	_label.modulate = color.lightened(0.3)
	_label.no_depth_test = false
	_label.position.y = ring_radius * 2.0 + 0.45
	add_child(_label)


func _update_view() -> void:
	if _ring == null:
		return
	var open := openness()
	# It unfolds out of a point at its foot, and folds back into it.
	var shown := maxf(open, 0.001)
	_ring.scale = Vector3(shown, shown, shown)
	_ring.position.y = (ring_radius + 0.05) * shown
	_veil.scale = _ring.scale
	_veil.position.y = _ring.position.y
	(_veil.material_override as StandardMaterial3D).albedo_color.a = 0.15 + 0.2 * open * (0.8 + 0.2 * sin(age * 6.0))
	_label.visible = open > 0.5
	var who := "" if opener_name == "" else "%s · " % opener_name
	_label.text = "%sTo %s · %d s" % [who, title_of(destination), ceili(time_left())]
	if not usable:
		_label.text += "\nnot your squad"
