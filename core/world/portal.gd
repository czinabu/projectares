class_name Portal
extends Node3D
## A squad portal: a ring of light opened from the watch (the Mission tab's
## portal icon, `Hud.portal_slot`) that leads to a world or the arena. It
## unfolds in front of whoever opened it, stays open `open_time` seconds for
## their squad (`Raid.squad_of`: their clan online) to walk through, then
## folds away.
##
## Where a portal can lead depends on where it opens (`choices_for`, Caleb's
## call: anywhere from anywhere):
## - your home base: every world, the arena and the plaza (`PLAZA`);
## - a safe-zone world such as the plaza: every world, the arena and `HOME`
##   (`Raid.open_portal`, where only the authority opens them and
##   `NetSession` shows them to everyone there);
## - a world where gear is at stake: `HOME` first, then every other world,
##   the arena and the plaza, and opening any of them is a sign-out
##   (`Raid.begin_sign_out`) with a door. It takes the sign-out's own time
##   (quick at a gate outpost, 15 s on the ground, 25 s and a beacon in the
##   air), a fight or a bounty still refuses it or cancels it (and the ring
##   folds away with it), the ring unfolds over the countdown where everyone
##   can see it, and a squadmate who steps in starts their own sign-out
##   through the same door. When the countdown ends everything carried goes
##   home first, as with any sign-out (the result's "door" says where the
##   ring led), and only then does the trip go on from the base to the
##   destination, with the loadout as it now stands at home. So a portal is
##   never an escape hatch out of a fight, and no gear goes from one world
##   straight into another.
## Walking through to a world lands you with the "portal" drop
## (`Raid.PORTAL_DROP`), at the world's gate outpost where it has one.
##
## The portal decides nothing itself. It knows where it leads, whose side may
## use it, how old it is and whether a point is inside it; whoever owns it
## (the base or the raid) ticks it, sends walkers through and frees it. The
## ring is the same object in every view, built as greybox here.

## The destination home: your base. Out in a world it is a sign-out, as is
## every other destination there.
const HOME := "home"
## The destination out of your base to the social world (the plaza): the
## base's door, as a portal.
const PLAZA := "plaza"

## How long a portal stays open, in seconds, counting its unfolding.
var open_time := 15.0
## How long it takes to unfold (a sign-out's countdown for a portal home out
## in a world, see `set_unfold`), and to fold away at the end.
var unfold_time := 0.6
var fold_time := 0.6
## How long a portal home stays open for the squad once it has unfolded.
var hold_time := 15.0
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
## A portal out of a world where gear is at stake: walking in starts a
## sign-out (through to `destination` once it ends, by way of home) rather
## than sending anyone anywhere, and it unfolds over its opener's countdown.
var signs_out := false
## Seconds since it opened.
var age := 0.0
## On a client: whether the viewer's side may use it (the server says).
var usable := true
## Actors already sent through, so nobody is sent twice.
var sent: Array[Actor] = []

var _ring: MeshInstance3D
var _veil: MeshInstance3D
var _label: Label3D


## Every world a portal can deploy you into: each raid world, then the arena
## (unless the launch holds it back, `LaunchScope`).
static func destinations() -> Array[String]:
	var out: Array[String] = []
	for world in Worlds.raid_worlds():
		out.append(world.id)
	if not LaunchScope.holds("arena"):
		out.append(Arena.ArenaVenue.ID)
	return out


## Where a portal from your own home base can lead: every world, the arena,
## then out to the plaza.
static func from_base() -> Array[String]:
	var out := destinations()
	out.append(PLAZA)
	return out


## Every destination a portal can have anywhere, for checking one sent over
## the network.
static func is_place(id: String) -> bool:
	return id == HOME or id == PLAZA or id in destinations()


## Where `actor` may open a portal to in `raid` (null for the home base):
## from the base every world, the arena and the plaza; in a safe zone every
## world, the arena and home; in a world where gear is at stake `HOME`
## first, then every other world, the arena and the plaza, each a sign-out
## that ends at home before the trip goes on; nowhere in the arena (leaving
## it has its own way) or while down. The authority checks it again in
## `Raid.open_portal`.
static func choices_for(raid: Raid, actor: Actor) -> Array[String]:
	if actor == null or not is_instance_valid(actor) or actor.is_dead:
		return []
	if raid == null:
		return from_base()
	if raid.world == null:
		return []
	if raid.world.safe_zone:
		var out := destinations()
		out.append(HOME)
		return out
	if raid.world.portal_home:
		return from_world(raid.world.id)
	return []


## Where a portal out of the world `here` (gear at stake) can lead: home
## first, so the watch starts on it, then every other world, the arena and
## the plaza. Each one signs you out.
static func from_world(here: String) -> Array[String]:
	var out: Array[String] = [HOME]
	for id in destinations():
		if id != here:
			out.append(id)
	out.append(PLAZA)
	return out


## Whether a portal to `id` opened out in a world signs you out and then
## travels on from home (anywhere but home itself).
static func goes_on(id: String) -> bool:
	return id != "" and id != HOME and is_place(id)


## The name a destination is shown by.
static func title_of(id: String) -> String:
	if id == HOME:
		return "home"
	if id == PLAZA:
		var plaza := Worlds.social_world()
		return plaza.display_name if plaza != null else "the plaza"
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


## Makes it unfold over `seconds` (a sign-out's countdown), then stay open
## `hold_time` for the squad.
func set_unfold(seconds: float) -> void:
	unfold_time = maxf(seconds, 0.1)
	open_time = unfold_time + hold_time


## How far unfolded the ring is, 0 to 1: it opens, holds, then folds away.
func openness() -> float:
	var t := minf(age / maxf(unfold_time, 0.01), 1.0)
	var closing := minf(time_left() / maxf(fold_time, 0.01), 1.0)
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
	if age < unfold_time and unfold_time > fold_time:
		# A portal out of a world, still unfolding over a sign-out.
		var to := "" if destination == HOME else " · to %s" % title_of(destination)
		_label.text = "%sSigning out%s · %d s" % [who, to, ceili(unfold_time - age)]
	else:
		_label.text = "%sTo %s · %d s" % [who, title_of(destination), ceili(time_left())]
	if not usable:
		_label.text += "\nnot your squad"
