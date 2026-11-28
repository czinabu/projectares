extends Control
## The aiming mark in the middle of the screen, the same in first and third
## person (Caleb's call): a centre dot and, with a gun in hand, four short
## ticks whose gap is the gun's real spread right now (`Gun.current_spread_deg`
## turned into pixels at the camera's field of view), so walking, jumping,
## spraying and aiming open and close it by exactly what they do to the shots.
## Each shot kicks the ticks out a little more on top (`kick`).
##
## It says a few more things by colour and shape, never by text:
##   - "hostile": someone on the other side is under it, in range: red.
##   - "far": what is under it is past the gun's reach (`Gun.max_range`, or
##     past `Gun.falloff_end` where the damage has fallen off): dim grey.
##   - "empty": the magazine is out or the gun is jammed: dim red ticks (the
##     reload prompt under it says what to press).
##   - "reload": the ticks give way to a thin ring that fills as the reload
##     goes on; a charging or spinning power weapon fills the same ring.
##   - a melee weapon or empty hands: the dot alone (the swing marks round it
##     are `Hud.StanceIndicator`'s).
## Looking down the sights in first person the mark fades out, since the
## sight sits in the middle of the view; in third person aiming only closes
## the ticks, by the aimed spread. Hit and kill marks are `Hud.HitMarker`.
##
## View only: one ray along the aim every `probe_interval` for what is under
## it, nothing in the simulation. Load with
## `preload("res://core/ui/crosshair.gd")`.

## Whose weapon it reads and whose view it sits in. The HUD sets both.
var actor: Actor
var controller: PlayerController

var tick_length := 6.0
var tick_width := 2.0
var dot_radius := 1.5
## The smallest gap between the middle and the ticks, so a still, aimed gun
## still shows four ticks round the dot and not a blob.
var min_gap := 4.0
var max_gap := 90.0
## How far one shot kicks the ticks out, in pixels, before they settle.
var kick := 4.0
var kick_settle := 12.0
## How fast the gap follows the spread (per second, as a rate).
var follow := 22.0
var reload_radius := 11.0
var probe_interval := 0.08

const INK := Color(1.0, 1.0, 1.0, 0.92)
const HOSTILE := Color(1.0, 0.32, 0.26, 0.95)
const FAR := Color(0.8, 0.8, 0.8, 0.38)
const EMPTY := Color(1.0, 0.35, 0.28, 0.5)
const OUTLINE := Color(0.0, 0.0, 0.0, 0.55)

## What the mark is showing now (see the class notes), for tests.
var state := "none"
## The ticks' distance from the middle right now, in pixels.
var gap := 0.0
## How far what is under the mark is, -1 for nothing, and whether it is an
## enemy.
var probe_distance := -1.0
var probe_hostile := false

var _kicked := 0.0
var _shots := -1
var _gun: Gun
var _probe_wait := 0.0
var _fade := 1.0
var _ring := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## The gap, in pixels, at which a cone of `spread_deg` reaches the edge of a
## view `fov_deg` tall drawn `height` pixels high.
static func spread_px(spread_deg: float, fov_deg: float, height: float) -> float:
	var half := tan(deg_to_rad(clampf(fov_deg, 1.0, 179.0)) * 0.5)
	return tan(deg_to_rad(clampf(spread_deg, 0.0, 89.0))) / half * height * 0.5


## What a mark over `gun` shows, given how far what is under it is (-1 for
## nothing) and whether that is an enemy. `gun` null means no gun in hand.
static func state_for(gun: Gun, distance: float, hostile: bool) -> String:
	if gun == null:
		return "dot"
	if gun.is_reloading():
		return "reload"
	if gun.charge_fraction() > 0.0 or gun.spin_fraction() > 0.0 and gun.spin_fraction() < 1.0:
		return "charge"
	if gun.jammed or gun.ammo_in_mag <= 0:
		return "empty"
	if distance >= 0.0 and (distance > gun.max_range or gun.falloff_end > 0.0 and distance > gun.falloff_end):
		return "far"
	return "hostile" if hostile else "ready"


func _process(delta: float) -> void:
	if actor == null or not is_instance_valid(actor) or actor.is_dead:
		state = "none"
		queue_redraw()
		return
	var weapon := actor.get_active_weapon()
	var gun := weapon as Gun
	if gun != _gun:
		_gun = gun
		_shots = gun.shots_fired if gun != null else -1
		_kicked = 0.0
	_probe(delta)
	state = state_for(gun, probe_distance, probe_hostile)
	if gun != null:
		if gun.shots_fired != _shots:
			_kicked = minf(_kicked + kick, kick * 3.0)
			_shots = gun.shots_fired
		_kicked *= exp(-kick_settle * delta)
		var camera := controller.camera if controller != null and is_instance_valid(controller) else null
		var fov := camera.fov if camera != null else 75.0
		var want := clampf(spread_px(gun.current_spread_deg(), fov, get_viewport_rect().size.y) + _kicked,
				min_gap, max_gap)
		gap = want if gap <= 0.0 else lerpf(gap, want, 1.0 - exp(-follow * delta))
		if state == "reload":
			_ring = 1.0 - gun.reload_left() / maxf(gun.reload_time, 0.01)
		elif state == "charge":
			_ring = maxf(gun.charge_fraction(), gun.spin_fraction())
	var sighted := controller != null and is_instance_valid(controller) and controller.sighted
	_fade = move_toward(_fade, 0.0 if sighted else 1.0, delta * 10.0)
	modulate.a = _fade
	queue_redraw()


## One ray along the aim, every `probe_interval`: how far what is under the
## mark is, and whether it is someone on the other side.
func _probe(delta: float) -> void:
	_probe_wait -= delta
	if _probe_wait > 0.0:
		return
	_probe_wait = probe_interval
	probe_distance = -1.0
	probe_hostile = false
	if not actor.is_inside_tree() or _gun == null:
		return
	var from := actor.get_eye_position()
	var reach := minf(maxf(_gun.max_range, _gun.falloff_end) * 1.5, 400.0)
	var query := PhysicsRayQueryParameters3D.create(from, from + actor.get_aim_dir() * reach,
			Actor.LAYER_WORLD | Actor.LAYER_ACTORS)
	query.exclude = [actor.get_rid()]
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	probe_distance = from.distance_to(hit.position)
	var other := hit.get("collider") as Actor
	probe_hostile = other != null and not other.is_dead and not Visor.allied(actor, other) \
			and not Visor.peaceful(actor)


func _draw() -> void:
	if state == "none":
		return
	var c := size * 0.5
	var ink := INK
	match state:
		"hostile":
			ink = HOSTILE
		"far":
			ink = FAR
	_dot(c, ink if state != "empty" else EMPTY)
	if state == "dot":
		return
	if state == "reload" or state == "charge":
		var faint := INK
		faint.a = 0.2
		draw_arc(c, reload_radius, 0.0, TAU, 40, faint, 1.5, true)
		draw_arc(c, reload_radius, -PI / 2.0, -PI / 2.0 + TAU * clampf(_ring, 0.0, 1.0), 40, INK, 2.0, true)
		return
	var color := EMPTY if state == "empty" else ink
	for dir: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		var a := c + dir * gap
		var b := c + dir * (gap + tick_length)
		draw_line(a - dir, b + dir, Color(OUTLINE, OUTLINE.a * color.a), tick_width + 2.0)
		draw_line(a, b, color, tick_width)


func _dot(c: Vector2, color: Color) -> void:
	draw_circle(c, dot_radius + 1.0, Color(OUTLINE, OUTLINE.a * color.a))
	draw_circle(c, dot_radius, color)
