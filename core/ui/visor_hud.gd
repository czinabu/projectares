class_name VisorHud
extends Control
## What a helmet shows its wearer. Two halves:
##
## The glass. Drawn over the view in first person only, and only while a
## helmet is worn: the visor projects its readouts into your view. It is a
## display of thin lines of light, never a frame: nothing is blacked out or
## tinted, and nothing sits over the middle of the view but the reticle.
## Everything hugs the rim of the glass and the middle stays clear (Caleb's
## redesign, after a reference he liked, made our own): every helmet has its
## vitals as a short row of hex cells along the lower left curve (health,
## armor, stamina, a flight rig's heat and cue, the ability), each filling
## like a gauge with its number over it (`vital_cells`). A working helmet
## also has a heading tape across the top, bowed with the glass, numbered
## every 15 degrees with the heading in a notch under it, marking the squad,
## pings and the nearest depot (`compass_marks`); a contact scope top left
## plotting those same marks round you, never a map (`scope_points`), with
## the squad's size on its rim; the helmet's name, role and system beside the
## scope; an objective block top right under a thin bracket, a hex bullet,
## progress bar and count per contract held, then the tour's step
## (`objective_lines`); faint pitch ticks up both edges; and a ring round the
## crosshair. Each helmet has a role (`role_name`), shown as it comes on, its own reticle,
## and the rest depends on its `mode` (see `Visor`): range finder, lock-on
## brackets, binocular scale and tagged targets on the strip for "zoom"
## (recon); a sweep, contact count and the scan's contacts on the strip for
## "scan" (intel); for "threat" (tactical) the health of whoever is under
## the crosshair, what nearby loot holds, the war's hot zone on the strip
## and where a hit came from; for "thermal" a heat picture of the whole view
## and how warm you look yourself. A scrap visor only manages a bearing and
## the vitals.
## The display is alive: it sweeps in when it comes on (`boot`),
## trails the view a little as you turn (`sway`), sits dim until something
## happens (`alert`) and closes on what you aim at (`lock`). With no helmet,
## or in third person, nothing is drawn. It works wherever a helmet is worn:
## a world, the plaza and the arena (`setup`, a `Raid`) and the home base
## (`setup_base`).
##
## The world. Things a visor puts out there, seen in either view: the frozen
## snapshots of a scan, markers over tagged targets, the ring of a scan pulse
## (anyone's), the outlines of Threat Sense, the glint off a lens that is
## looking your way, and the ember of a thermal visor seen up close.
##
## A view only: it reads `Visor` state and never decides what is revealed.

const Contracts := preload("res://core/economy/contracts.gd")

## How long the mark for a scan that caught you stays on the glass.
var felt_time := 2.5
## How long a pulse's ring takes to cross its radius.
var ring_time := 0.7
## How squarely a lens must face you to glint, as the cosine of the angle.
var glint_facing := 0.94
## Seconds between range finder readings.
var range_interval := 0.1
var range_max := 600.0
## How long the mark for a hit stays on a tactical visor.
var hit_mark_time := 1.6
## How close a thermal visor's ember can be seen from.
var ember_range := 18.0
## Seconds the display takes to sweep in when it comes on.
var boot_time := 0.9
## How far the display trails the view, in pixels per radian turned per
## second, how far it may drift at most, and how fast it settles.
var sway_gain := 26.0
var sway_max := 22.0
var sway_settle := 7.0
## How bright the standing lines are while nothing is happening (0 to 1),
## and how fast an alert fades.
var idle_dim := 0.55
var alert_fade := 0.7
## How far the brackets lock on to someone, and how fast they close.
var lock_range := 220.0
var lock_rate := 6.0
## The armor arc's colour (stamina takes the glass's own).
const ARMOR_INK := Color(0.5, 0.75, 1.0)
## Colours of the heading strip's marks that are not the glass's own.
const SQUAD_INK := Color(0.45, 1.0, 0.6)
const PING_INK := Color(0.35, 0.95, 1.0)
const HOT_INK := Color(1.0, 0.55, 0.15)
const TAG_INK := Color(1.0, 0.3, 0.2)
## How many degrees either side of straight ahead the heading strip shows.
var strip_reach := 45.0
## How far the heading strip bows down at its ends, as a share of the
## screen's height: the glass is curved.
var strip_bow := 0.018
## How far out the contact scope reaches, in metres, before a mark sits on
## its rim.
var scope_range := 80.0
## Where the vitals cells sit along the glass's lower left curve: how far in
## the first is and how low the row runs (shares of the view's height), and
## how much the row lifts toward the left edge, as the glass curves up there.
var vitals_left := 0.075
var vitals_low := 0.9
var vitals_lift := 0.07
## Pitch ticks: pixels per degree, as a share of the view's height.
var pitch_scale := 0.009
## The weapon readout, bottom right: how long it stays lit after a switch,
## below what share of a mag it counts as low, how bright it rests, and how
## fast it wakes and settles.
var weapon_show_time := 2.5
var weapon_low_share := 0.25
var weapon_rest := 0.22
var weapon_fade := 2.5
## The war must be at least this hot before a tactical visor marks its centre.
var hot_from := 0.25
## How long the helmet's name stays up after the display comes on.
var ident_time := 2.4
## Seconds the glass's scan line takes to run down the view.
var scanline_time := 5.5

## Where the wearer is: a `Raid` (a world, the plaza, the arena) or, with
## `setup_base`, a `HomeBase`. The glass works the same in both, so a helmet
## shows its display wherever it is worn.
var raid: Raid
var base: HomeBase
var controller: PlayerController
## The range finder's last reading in metres, below zero for nothing in reach.
var range_reading := -1.0
## Scans that caught the wearer: {"origin": Vector3, "left": float}.
var felt: Array[Dictionary] = []
## Hits a tactical visor is pointing out: {"origin": Vector3, "left": float}.
var hit_marks: Array[Dictionary] = []
## Who a tactical visor is reading under the crosshair, or null.
var read_target: Actor
## True while the view is the thermal picture.
var thermal_shown := false
## How far the display has swept in, 0 off to 1 fully on.
var boot := 0.0
## How far the display is trailing the view right now, in pixels.
var sway := Vector2.ZERO
## How awake the display is, 0 calm to 1: a hit, a scan or a threat raises it.
var alert := 0.0
## Whoever is under the crosshair within `lock_range`, and how far the
## brackets have closed on them (0 to 1).
var aim_target: Actor
var lock := 0.0
## How lit the weapon readout is, 0 resting to 1 (`weapon_awake`).
var weapon_lit := 0.0
## How far the binocular scale has opened, 0 to 1.
var zoom_shown := 0.0
## Height above the ground while off it, below zero when standing on it.
var altitude := -1.0
## Everyone on the wearer's squad in this world, alive (see `squadmate`).
var squad: Array[Actor] = []
## Spots the wearer's side pinged: {"at": Vector3, "left": float}.
var pings: Array[Dictionary] = []
## The HUD this glass belongs to (`Hud`, or the home base's), for the
## contracts held and the tour's objective. May be null.
var hud: Node

var _world: Node3D
var _ghosts: Array[MeshInstance3D] = []
var _tag_marks := {}
## Everyone tagged for the wearer's side right now, for the heading strip.
var _tagged: Array[Actor] = []
## Seconds since the display last came on, for the helmet's name.
var _since_boot := 0.0
var _glints := {}
var _embers := {}
var _threat_marks := {}
var _heat := {}
var _thermal: ColorRect
var _rings: Array[Dictionary] = []
var _heard := {}
var _range_wait := 0.0
var _time := 0.0
var _last_look := Vector2.ZERO
var _look_known := false
## The actor whose signals the glass listens to. The home base swaps its
## actor out when it has to, so this is followed rather than set once.
var _wired: Actor
## The weapon in hand last frame, and seconds since it changed.
var _last_weapon: Weapon
var _since_switch := 99.0


func setup(p_raid: Raid, p_controller: PlayerController) -> void:
	raid = p_raid
	controller = p_controller


## The glass in a home base: the same display, with nothing a world adds
## (pings, depots, the war).
func setup_base(p_base: HomeBase, p_controller: PlayerController) -> void:
	base = p_base
	controller = p_controller


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world = Node3D.new()
	_world.name = "VisorWorld"
	var host: Node = raid if raid != null else base
	if host != null:
		host.add_child.call_deferred(_world)
	_thermal = ColorRect.new()
	_thermal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_thermal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_thermal.show_behind_parent = true
	_thermal.visible = false
	var shader := Shader.new()
	shader.code = THERMAL_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	_thermal.material = material
	add_child(_thermal)
	_wire(_player())
	if raid != null:
		raid.pinged.connect(_on_pinged)


## Listens to the wearer's scans, hits and damage, moving over when the
## wearer is a new actor.
func _wire(p: Actor) -> void:
	if p == _wired:
		return
	if _wired != null and is_instance_valid(_wired):
		_wired.visor.felt_scan.disconnect(_on_felt_scan)
		_wired.visor.threatened.disconnect(_on_threatened)
		_wired.health.damaged.disconnect(_on_damaged)
	_wired = p
	if p != null:
		p.visor.felt_scan.connect(_on_felt_scan)
		p.visor.threatened.connect(_on_threatened)
		p.health.damaged.connect(_on_damaged)


func _on_damaged(_info: DamageInfo) -> void:
	alert = 1.0


func _exit_tree() -> void:
	if _world != null and is_instance_valid(_world):
		_world.queue_free()


## True while the wearer is looking through the glass: a helmet on, alive,
## and the camera in their head.
func glass_shown() -> bool:
	var p := _player()
	if p == null or p.is_dead or not p.visor.enabled:
		return false
	return controller == null or not controller.is_third_person()


## The thermal picture: the view's brightness run through a heat ramp, cold
## blue to hot white. The world is dimmed so it stays cold; warm bodies are
## drawn bright (see `_sync_heat`) and so come out hot.
const THERMAL_SHADER := """
shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_linear;

void fragment() {
	vec3 seen = texture(screen, SCREEN_UV).rgb;
	float heat = dot(seen, vec3(0.299, 0.587, 0.114));
	// Bodies are drawn far brighter than anything the world has.
	float warm = smoothstep(0.82, 1.0, heat);
	float cold = clamp(heat * 0.6, 0.0, 0.5);
	vec3 ramp = mix(vec3(0.01, 0.02, 0.09), vec3(0.16, 0.2, 0.42), cold * 2.0);
	vec3 hot = mix(vec3(1.0, 0.45, 0.05), vec3(1.0, 0.98, 0.85), smoothstep(0.9, 1.0, heat));
	float line = 0.94 + 0.06 * sin(FRAGCOORD.y * 2.4);
	COLOR = vec4(mix(ramp, hot, warm) * line, 1.0);
}
"""


## Compass bearing in degrees for a yaw: 0 north (-Z), 90 east (+X).
static func bearing(yaw: float) -> float:
	return fposmod(-rad_to_deg(yaw), 360.0)


## Where `origin` lies for someone at `at` facing `yaw`, as an angle from
## straight ahead: positive to the right, PI behind.
static func angle_to(origin: Vector3, at: Vector3, yaw: float) -> float:
	var local := Basis(Vector3.UP, yaw).inverse() * (origin - at)
	return atan2(local.x, -local.z)


## The short name of a compass bearing: N, NE, E and so on.
static func compass_name(degrees: float) -> String:
	var names := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	return names[posmod(roundi(degrees / 45.0), 8)]


func _player() -> Actor:
	var p: Actor = null
	if raid != null:
		p = raid.player
	elif base != null and is_instance_valid(base):
		p = base.player
	if p == null or not is_instance_valid(p) or p.is_queued_for_deletion():
		return null
	return p


func _process(delta: float) -> void:
	_time += delta
	var p := _player()
	_wire(p)
	for mark in felt:
		mark.left -= delta
	felt = felt.filter(func(m: Dictionary) -> bool: return m.left > 0.0)
	for mark in hit_marks:
		mark.left -= delta
	hit_marks = hit_marks.filter(func(m: Dictionary) -> bool: return m.left > 0.0)
	for mark in pings:
		mark.left -= delta
	pings = pings.filter(func(m: Dictionary) -> bool: return m.left > 0.0)
	thermal_shown = p != null and glass_shown() and p.visor.thermal_on
	_thermal.visible = thermal_shown
	_animate(p, delta)
	if p == null or _world == null or not _world.is_inside_tree():
		queue_redraw()
		return
	_read_range(p, delta)
	_sync_ghosts(p)
	# One pass over everyone in the wearer's world, shared by what follows.
	var around: Array[Actor] = []
	for node in get_tree().get_nodes_in_group("actors"):
		var other := node as Actor
		if other != null and Raid.together(other, p):
			around.append(other)
	squad.clear()
	for other in around:
		if squadmate(raid, p, other):
			squad.append(other)
	_sync_actors(p, around)
	_sync_heat(p, around)
	_tick_rings(delta)
	queue_redraw()


## Moves the display's own motion along: the sweep in, the trail behind
## the view, the alert level, the lock and the binocular scale.
func _animate(p: Actor, delta: float) -> void:
	if p == null or not (glass_shown() or reticle_shown()):
		boot = 0.0
		sway = Vector2.ZERO
		lock = 0.0
		zoom_shown = 0.0
		_look_known = false
		return
	if not glass_shown():
		# Third person keeps only the ring and the lock: no glass to boot or trail.
		boot = 0.0
		sway = Vector2.ZERO
		_look_known = false
		var held := aim_target != null and is_instance_valid(aim_target) and not aim_target.is_dead
		lock = move_toward(lock, 1.0 if held else 0.0, lock_rate * delta)
		return
	if boot <= 0.0:
		_since_boot = 0.0
	_since_boot += delta
	boot = minf(1.0, boot + delta / maxf(boot_time, 0.01))
	var look := Vector2(p.cmd.yaw, p.cmd.pitch)
	if _look_known and delta > 0.0:
		# Turning right (yaw falls) leaves the display behind, to the left.
		var turned := Vector2(wrapf(look.x - _last_look.x, -PI, PI), look.y - _last_look.y) / delta
		sway += Vector2(turned.x, turned.y) * sway_gain * delta
	_last_look = look
	_look_known = true
	sway = sway.limit_length(sway_max) * exp(-sway_settle * delta)
	var busy := p.visor.is_sensing() or not p.visor.threats.is_empty() or p.visor.is_zoomed() \
			or p.visor.thermal_on or not felt.is_empty() or not hit_marks.is_empty() \
			or p.health.health < p.health.max_health * 0.35
	alert = 1.0 if busy else maxf(0.0, alert - alert_fade * delta)
	var locked := aim_target != null and is_instance_valid(aim_target) and not aim_target.is_dead
	lock = move_toward(lock, 1.0 if locked else 0.0, lock_rate * delta)
	zoom_shown = move_toward(zoom_shown, 1.0 if p.visor.is_zoomed() else 0.0, 5.0 * delta)
	var held := p.get_active_weapon()
	if held != _last_weapon:
		_last_weapon = held
		_since_switch = 0.0
	_since_switch += delta
	weapon_lit = move_toward(weapon_lit, 1.0 if weapon_awake(held) else 0.0, weapon_fade * delta)


func _on_felt_scan(origin: Vector3) -> void:
	felt.append({"origin": origin, "left": felt_time})
	Sfx.play("ability", null, -9.0)


## A ping from the wearer or their side (others never reach a client; solo
## they are filtered here like the HUD's own marker).
func _on_pinged(pinger: Actor, at: Vector3) -> void:
	var p := _player()
	if p == null or not is_instance_valid(pinger):
		return
	if pinger != p and raid.mode != Raid.Mode.CLIENT and not Visor.allied(p, pinger):
		return
	pings.append({"at": at, "left": raid.ping_time})


## True if `other` is on the wearer's squad: another living player in the
## same world who shares a clan with them, or anyone in a world where all
## players fight together. Never a bot, never an enemy (DESIGN.md section 5).
## Clans are what a client is told about, so this works the same online.
static func squadmate(p_raid: Raid, p: Actor, other: Actor) -> bool:
	if p_raid == null or other == null or other == p or other.is_dead or p_raid.state_for(other) == null:
		return false
	if p_raid.world != null and p_raid.world.players_allied:
		return true
	return p.clan != "" and p.clan == other.clan


## What each helmet is for, shown as it comes on.
static func role_name(mode: String) -> String:
	match mode:
		"zoom":
			return "RECON"
		"scan":
			return "INTEL"
		"threat":
			return "TACTICAL"
		"thermal":
			return "THERMAL"
	return "SCRAP"


## How warm the wearer looks to a thermal visor (`Visor.heat_of`), for an
## Ember's own readout.
static func signature_text(heat: float) -> String:
	if heat >= 1.2:
		return "SIG HIGH"
	if heat >= 0.7:
		return "SIG MED"
	return "SIG LOW"


## The visor's contract tracker: the job nearest done (`Hud.contract_slot`),
## or "" with none held.
static func tracker_text(held: Array[Dictionary], tally: Dictionary) -> String:
	if held.is_empty():
		return ""
	return str(Hud.contract_slot(held, tally).detail).to_upper()


## What the heading strip marks, nearest the middle last so it draws on top:
## {"kind", "at" (Vector3), "label"}. Kinds: "squad", "ping" and "depot" on
## every working visor; "tag" (Spotter), "contact" (Seeker's snapshots) and
## "hot" (the war's centre, Warden). A scrap visor marks nothing.
func compass_marks(p: Actor) -> Array[Dictionary]:
	var marks: Array[Dictionary] = []
	var v := p.visor
	if v.mode == "":
		return marks
	var nearest: Node3D = null
	for depot in raid.depots if raid != null else []:
		if is_instance_valid(depot) and Raid.together(depot, p) and (nearest == null
				or depot.global_position.distance_to(p.global_position)
				< nearest.global_position.distance_to(p.global_position)):
			nearest = depot
	if nearest != null:
		marks.append({"kind": "depot", "at": nearest.global_position, "label": "DEPOT"})
	if v.mode == "threat" and raid != null and raid.war.intensity >= hot_from:
		marks.append({"kind": "hot", "at": raid.war.centre, "label": "HOT"})
	for ghost in v.ghosts if v.mode == "scan" else []:
		marks.append({"kind": "contact", "at": ghost.at, "label": ""})
	for target in _tagged if v.mode == "zoom" else []:
		if is_instance_valid(target):
			marks.append({"kind": "tag", "at": target.global_position, "label": ""})
	for ping in pings:
		marks.append({"kind": "ping", "at": ping.at, "label": "PING"})
	for mate in squad:
		if is_instance_valid(mate):
			marks.append({"kind": "squad", "at": mate.global_position, "label": mate.display_name.left(8).to_upper()})
	return marks


func _on_threatened(origin: Vector3) -> void:
	hit_marks.append({"origin": origin, "left": hit_mark_time})


## What the wearer's eyes see along their aim: how far it is (the range
## finder), who it is (the lock, and a tactical visor's readout), and how
## high the wearer is.
func _read_range(p: Actor, delta: float) -> void:
	_range_wait -= delta
	if _range_wait > 0.0 or p.visor.mode == "" or not p.visor.enabled or not p.is_inside_tree():
		return
	_range_wait = range_interval
	var from := p.get_eye_position()
	var query := PhysicsRayQueryParameters3D.create(from, from + p.get_aim_dir() * range_max,
			Actor.LAYER_WORLD | Actor.LAYER_ACTORS)
	query.exclude = [p.get_rid()]
	var hit := p.get_world_3d().direct_space_state.intersect_ray(query)
	range_reading = -1.0 if hit.is_empty() else from.distance_to(hit.position)
	var seen := hit.get("collider") as Actor
	var found := seen if seen != null and not seen.is_dead and range_reading <= lock_range else null
	if found != aim_target:
		aim_target = found
		lock = 0.0
	read_target = found if found != null and p.visor.mode == "threat" \
			and range_reading <= p.visor.read_range else null
	# How high the wearer is, for the readout that shows in the air.
	altitude = -1.0
	if p.airborne_time > 0.35 and p.vehicle == null:
		var feet := p.global_position + Vector3(0.0, 0.5, 0.0)
		var down := PhysicsRayQueryParameters3D.create(feet, feet + Vector3.DOWN * 400.0, Actor.LAYER_WORLD)
		var ground := p.get_world_3d().direct_space_state.intersect_ray(down)
		altitude = 400.0 if ground.is_empty() else maxf(0.0, feet.y - 0.5 - ground.position.y)


# --- The world -----------------------------------------------------------------

## One frozen figure per snapshot of the wearer's last scan, seen through walls.
func _sync_ghosts(p: Actor) -> void:
	var wanted := p.visor.ghosts
	while _ghosts.size() > wanted.size():
		_ghosts.pop_back().queue_free()
	while _ghosts.size() < wanted.size():
		var mesh := CapsuleMesh.new()
		mesh.radius = Actor.BODY_RADIUS
		mesh.height = Actor.BODY_HEIGHT
		mesh.material = _see_through(p.visor.glass_color)
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_world.add_child(node)
		_ghosts.append(node)
	for i in wanted.size():
		var ghost: Dictionary = wanted[i]
		_ghosts[i].global_position = ghost.at + Vector3(0.0, Actor.BODY_HEIGHT * 0.5, 0.0)
		var mat: StandardMaterial3D = _ghosts[i].mesh.material
		mat.albedo_color.a = 0.5 * clampf(ghost.left / maxf(p.visor.ghost_time, 0.01), 0.0, 1.0)


## Everything that follows another actor: pulse rings, tag marks and glints.
func _sync_actors(p: Actor, around: Array[Actor]) -> void:
	var camera := get_viewport().get_camera_3d()
	var tagged := {}
	var glinting := {}
	for other in around:
		if not _heard.has(other):
			_heard[other] = true
			other.visor.pulsed.connect(_on_pulsed.bind(other.visor.scan_radius, other.visor.glass_color))
			other.tree_exiting.connect(func() -> void: _heard.erase(other))
		# Tags held by the wearer's side. Online the server only sends those.
		# Most visors hold no tags: ask that before the dearer question of sides.
		if not other.visor.tags.is_empty() and (other == p or not Combat.authoritative or Visor.allied(p, other)):
			for target: Variant in other.visor.tags:
				if is_instance_valid(target):
					tagged[target] = true
		if other != p and not other.is_dead and other.visor.is_zoomed() and camera != null:
			var eye := other.get_eye_position()
			var to_me := camera.global_position - eye
			if to_me.length() > 1.0 and other.get_aim_dir().dot(to_me.normalized()) >= glint_facing:
				glinting[other] = eye + to_me.normalized() * 0.4
	var embers := {}
	if camera != null:
		for other in around:
			if other != p and not other.is_dead and other.visor.thermal_on \
					and camera.global_position.distance_to(other.global_position) <= ember_range:
				embers[other] = true
	var sensed := {}
	for other in p.visor.threats:
		if is_instance_valid(other) and not other.is_dead:
			sensed[other] = true
	_tagged.clear()
	for target: Variant in tagged:
		if target is Actor and not (target as Actor).is_dead:
			_tagged.append(target)
	_sync_marks(_tag_marks, tagged, _new_tag_mark)
	_sync_marks(_glints, glinting, _new_glint)
	_sync_marks(_embers, embers, _new_ember)
	_sync_marks(_threat_marks, sensed, _new_threat_mark)
	for other: Actor in _embers:
		_embers[other].global_position = other.get_eye_position() + other.get_aim_dir() * 0.3
	for other: Actor in _threat_marks:
		_threat_marks[other].global_position = other.global_position + Vector3(0.0, Actor.BODY_HEIGHT * 0.5, 0.0)
	for target: Actor in _tag_marks:
		_tag_marks[target].global_position = target.global_position + Vector3(0.0, 2.5, 0.0)
	for other: Actor in _glints:
		var glint: MeshInstance3D = _glints[other]
		glint.global_position = glinting[other]
		# Far away a glint would be a single pixel: it grows with distance.
		var away: float = camera.global_position.distance_to(glint.global_position)
		glint.scale = Vector3.ONE * clampf(away * 0.03, 1.0, 9.0) * (0.8 + 0.2 * sin(_time * 23.0))


## Keeps one node in `marks` for every key of `wanted`, built by `make`.
func _sync_marks(marks: Dictionary, wanted: Dictionary, make: Callable) -> void:
	for key: Variant in marks.keys():
		if not wanted.has(key) or not is_instance_valid(key):
			marks[key].queue_free()
			marks.erase(key)
	for key: Variant in wanted:
		if not marks.has(key):
			var node: Node3D = make.call()
			_world.add_child(node)
			marks[key] = node


func _new_tag_mark() -> Node3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.28
	mesh.bottom_radius = 0.0
	mesh.height = 0.45
	mesh.radial_segments = 4
	mesh.material = _see_through(Color(1.0, 0.25, 0.15, 0.9))
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


func _new_glint() -> Node3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.07
	mesh.height = 0.14
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 1.0, 0.92)
	mesh.material = mat
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## The dull red point of a thermal visor that is switched on.
func _new_ember() -> Node3D:
	var node := _new_glint() as MeshInstance3D
	var mat: StandardMaterial3D = node.mesh.material
	mat.albedo_color = Color(1.0, 0.2, 0.08)
	return node


## The outline Threat Sense puts on someone aiming at the wearer.
func _new_threat_mark() -> Node3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = Actor.BODY_RADIUS
	mesh.height = Actor.BODY_HEIGHT
	mesh.material = _see_through(Color(1.0, 0.2, 0.12, 0.5))
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## Thermal: every living body in view gets a bright shell the heat picture
## turns hot. It is hidden by walls like the body it covers, and fog does
## not touch it. The hotter the body, the brighter the shell.
func _sync_heat(p: Actor, around: Array[Actor]) -> void:
	var warm := {}
	if thermal_shown:
		for other in around:
			if other != p and not other.is_dead \
					and other.global_position.distance_to(p.global_position) <= Visor.reach_to(other, INF):
				warm[other] = true
	_sync_marks(_heat, warm, _new_heat_shell)
	for other: Actor in _heat:
		var shell: MeshInstance3D = _heat[other]
		shell.global_position = other.global_position + Vector3(0.0, Actor.BODY_HEIGHT * 0.5, 0.0)
		var mat: StandardMaterial3D = shell.mesh.material
		mat.albedo_color.a = clampf(0.35 + 0.45 * Visor.heat_of(other), 0.0, 1.0)


func _new_heat_shell() -> Node3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = Actor.BODY_RADIUS * 0.95
	mesh.height = Actor.BODY_HEIGHT
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.disable_fog = true
	mat.albedo_color = Color(4.0, 4.0, 4.0, 1.0)
	mat.render_priority = 10
	mesh.material = mat
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


func _on_pulsed(origin: Vector3, radius: float, color: Color) -> void:
	if _world == null or not _world.is_inside_tree():
		return
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(color.r, color.g, color.b, 0.22)
	mesh.material = mat
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.add_child(node)
	node.global_position = origin
	_rings.append({"node": node, "age": 0.0, "radius": radius})


func _tick_rings(delta: float) -> void:
	for ring in _rings:
		ring.age += delta
		var done := clampf(ring.age / ring_time, 0.0, 1.0)
		var node: MeshInstance3D = ring.node
		node.scale = Vector3.ONE * maxf(0.5, ring.radius * done)
		var mat: StandardMaterial3D = node.mesh.material
		mat.albedo_color.a = 0.22 * (1.0 - done)
		if done >= 1.0:
			node.queue_free()
	_rings = _rings.filter(func(r: Dictionary) -> bool: return r.age < ring_time)


## A flat colour that shows through walls.
func _see_through(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.albedo_color = color
	return mat


# --- The glass -----------------------------------------------------------------
# A projected display, not a window frame: thin lines of light that hang in
# the view, drift a little behind it when you turn, sweep in when the visor
# comes on, sit dim while nothing is happening and brighten when something is.

func _draw() -> void:
	if reticle_shown():
		_draw_third_person()
		return
	if not glass_shown() or boot <= 0.0:
		return
	var p := _player()
	var v := p.visor
	var ink := v.glass_color
	var centre := size * 0.5 + sway
	if v.mode == "":
		# A scrap visor's projector is failing: the picture drops out now and then.
		if sin(_time * 1.7) * sin(_time * 4.3) > 0.82:
			return
		_draw_cracks(ink)
	_draw_glass(ink)
	_draw_vitals(p, ink)
	_draw_weapon(p, ink)
	_draw_ident(v, ink)
	if v.mode == "":
		_draw_heading(p, ink)
	else:
		_draw_reticle(ink, centre, v.mode)
		_draw_pitch(p, ink)
		_draw_compass(p, ink)
		_draw_scope(p, ink)
		_draw_objectives(p, ink)
	match v.mode:
		"zoom":
			_draw_lock(p, ink, "%d m" % roundi(range_reading) if range_reading >= 0.0 else "")
			_draw_range(ink, centre)
			_draw_system(ink, float(v.zoom_level) / maxf(v.zoom_levels.size(), 1.0),
					"OPTIC %dx" % roundi(v.zoom_factor()) if v.is_zoomed() else "OPTIC READY", v.is_zoomed())
			if zoom_shown > 0.01:
				_draw_binoculars(v, ink, centre)
		"scan":
			_draw_system(ink, 1.0 - clampf(v.cooldown_left / maxf(v.cooldown, 0.01), 0.0, 1.0),
					"SCAN READY" if v.cooldown_left <= 0.0 else "SCAN IN %d" % ceili(v.cooldown_left),
					v.cooldown_left <= 0.0)
			_draw_sweep(v, ink, centre)
		"threat":
			_draw_lock(p, ink, "")
			_draw_target(ink)
			_draw_loot(p, ink)
			if v.is_sensing():
				_draw_system(Color(1.0, 0.3, 0.2), v.active_left / maxf(v.threat_time, 0.01),
						"THREATS %d" % v.threats.size(), true)
			else:
				_draw_system(ink, 1.0 - clampf(v.cooldown_left / maxf(v.cooldown, 0.01), 0.0, 1.0),
						"SENSE READY" if v.cooldown_left <= 0.0 else "SENSE IN %d" % ceili(v.cooldown_left),
						v.cooldown_left <= 0.0)
		"thermal":
			_draw_system(ink, v.charge_fraction(), "THERMAL ON" if v.thermal_on else "CELL %d%%" %
					roundi(v.charge_fraction() * 100.0), v.thermal_on)
			_draw_signature(p, ink)
	_draw_slivers(p, centre, felt, felt_time, Color(1.0, 0.2, 0.12), 0.4)
	_draw_slivers(p, centre, hit_marks, hit_mark_time, Color(1.0, 0.6, 0.1), 0.34)


## In third person the glass is out of view, so only the turning ring at the
## crosshair and the brackets on whoever is under it stay, with no text: the
## wider view already shows what is around you. The helmet's health and system
## readouts are worn on the back of the head instead (`ActorSkin`).
func reticle_shown() -> bool:
	var p := _player()
	return p != null and not p.is_dead and p.visor.enabled and p.visor.mode != "" \
			and controller != null and controller.is_third_person()


func _draw_third_person() -> void:
	var p := _player()
	var ink := p.visor.glass_color
	_draw_reticle(ink, size * 0.5, p.visor.mode)
	_draw_lock(p, ink, "")


## The visor's colour at `alpha`, dimmed while the display is still coming
## on and while nothing needs the wearer's eye.
func _lit(ink: Color, alpha: float, ambient := true) -> Color:
	var level := (1.0 if reticle_shown() else boot) * (lerpf(idle_dim, 1.0, alert) if ambient else 1.0)
	return Color(ink.r, ink.g, ink.b, clampf(alpha * level, 0.0, 1.0))


## How much of something to show while the display sweeps in.
func _swept() -> float:
	return 1.0 if reticle_shown() else ease(boot, 0.4)


## Small capitals, the way every readout is lettered. They type themselves in,
## with a faint dark halo so they read against a bright sky.
func _text(at: Vector2, text: String, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := 220.0,
		font_size := 13) -> void:
	var shown := text.substr(0, ceili(text.length() * _swept()))
	var from := at if align == HORIZONTAL_ALIGNMENT_LEFT else at - Vector2(width * (0.5 if align
			== HORIZONTAL_ALIGNMENT_CENTER else 1.0), 0.0)
	var font := ThemeDB.fallback_font
	draw_string_outline(font, from, shown, align, width, font_size, 3, Color(0.0, 0.02, 0.04, color.a * 0.45))
	draw_string(font, from, shown, align, width, font_size, color)


## A band of short ticks along an arc, turned by `turn` radians.
func _ticks(centre: Vector2, radius: float, from: float, to: float, step: float, length: float,
		color: Color, turn := 0.0) -> void:
	var angle := from + fposmod(turn, step)
	while angle <= to:
		var dir := Vector2(cos(angle), sin(angle))
		draw_line(centre + dir * radius, centre + dir * (radius + length), color, 1.0, true)
		angle += step


## The ability's state under the vitals: its name when ready, the seconds
## left while it runs or recharges, "" with none.
static func ability_text(ability: Ability) -> String:
	if not ability.enabled:
		return ""
	var name := ability.display_name.to_upper()
	if ability.is_active():
		return "%s %.1f" % [name, ability.active_left]
	if ability.cooldown_left > 0.0:
		return "%s %d" % [name, ceili(ability.cooldown_left)]
	return name


## A broken ring around the crosshair that turns slowly, and closes in when
## something is under it. Each helmet breaks it its own way: three arcs for
## recon, four for intel, two heavy brackets for tactical, six short ticks
## for thermal.
func _draw_reticle(ink: Color, centre: Vector2, mode := "") -> void:
	var locked := aim_target != null and is_instance_valid(aim_target)
	var radius := lerpf(30.0, 20.0, lock) * lerpf(2.2, 1.0, _swept())
	var turn := _time * (1.4 if locked else 0.35)
	var parts := {"scan": 4, "threat": 2, "thermal": 6}.get(mode, 3) as int
	var gap := {"threat": 1.3, "thermal": 0.75}.get(mode, 0.5) as float
	var width := 2.0 if mode == "threat" else 1.0
	for i in parts:
		var from := turn + TAU * i / parts
		draw_arc(centre, radius, from, from + TAU / parts - gap, 12, _lit(ink, 0.55 + 0.35 * lock), width, true)


## A plain visor has seen better days.
func _draw_cracks(ink: Color) -> void:
	var color := _lit(ink, 0.3)
	var from := Vector2(size.x * 0.13, size.y * 0.1)
	var unit := size.y * 0.05
	draw_polyline(PackedVector2Array([from, from + Vector2(1.4, 0.9) * unit, from + Vector2(1.7, 2.2) * unit,
			from + Vector2(3.0, 2.9) * unit]), color, 1.5, true)
	draw_polyline(PackedVector2Array([from + Vector2(1.4, 0.9) * unit, from + Vector2(2.8, 0.7) * unit,
			from + Vector2(3.6, 1.5) * unit]), color, 1.2, true)
	draw_polyline(PackedVector2Array([from + Vector2(1.7, 2.2) * unit, from + Vector2(0.9, 3.3) * unit]),
			color, 1.2, true)


## Where the curved heading strip is at `off` degrees from straight ahead:
## it bows down toward its ends, the way the glass curves.
func _strip_point(off: float) -> Vector2:
	var share := clampf(off / strip_reach, -1.0, 1.0)
	return Vector2(size.x * 0.5 + sway.x + off * size.x * 0.0045,
			size.y * 0.075 + sway.y + share * share * size.y * strip_bow)


func _draw_strip_mark(p: Actor, ink: Color, mark: Dictionary, off: float, waiting: int) -> void:
	var off_strip := absf(off) > strip_reach
	var at := _strip_point(clampf(off, -strip_reach, strip_reach)) + Vector2(0.0, 34.0)
	at.x -= signf(off) * waiting * 70.0
	var away := roundi((mark.at as Vector3).distance_to(p.global_position))
	var tint: Color = {"squad": SQUAD_INK, "ping": PING_INK, "hot": HOT_INK, "tag": TAG_INK}.get(mark.kind, ink)
	var urgent: bool = mark.kind in ["tag", "contact", "ping"]
	var color := _lit(tint, 0.95 if not off_strip else 0.7, not urgent)
	match mark.kind:
		"squad":
			draw_colored_polygon(PackedVector2Array([at + Vector2(-6, 4), at + Vector2(6, 4), at + Vector2(0, -6)]), color)
		"depot":
			draw_rect(Rect2(at - Vector2(5, 5), Vector2(10, 10)), color, false, 1.5)
		"hot":
			var flicker := 0.7 + 0.3 * sin(_time * 4.0)
			draw_arc(at, 6.0, 0.0, TAU, 16, Color(color, color.a * flicker), 2.0, true)
			draw_circle(at, 2.0, color)
		"contact":
			draw_arc(at, 5.0, 0.0, TAU, 12, color, 1.5, true)
		_:
			# Pings and tags are diamonds.
			draw_colored_polygon(PackedVector2Array([at + Vector2(0, -6), at + Vector2(6, 0), at + Vector2(0, 6),
					at + Vector2(-6, 0)]), color)
	if off_strip:
		# Waiting at the end of the strip: a chevron says which way to turn.
		var side := signf(off)
		draw_polyline(PackedVector2Array([at + Vector2(side * 9.0, -5.0), at + Vector2(side * 14.0, 0.0),
				at + Vector2(side * 9.0, 5.0)]), color, 1.5, true)
	var label: String = mark.label
	label = "%d m" % away if label == "" else "%s %d m" % [label, away]
	_text(at + Vector2(0.0, 20.0), label, color, HORIZONTAL_ALIGNMENT_CENTER, 140.0, 11)


## A scrap visor's failing projector manages a bearing and nothing more.
func _draw_heading(p: Actor, ink: Color) -> void:
	var heading := bearing(p.cmd.yaw)
	_text(Vector2(size.x * 0.5, size.y * 0.08), "%03d %s" % [roundi(heading), compass_name(heading)],
			_lit(ink, 0.7), HORIZONTAL_ALIGNMENT_CENTER, 120.0)


## The helmet's name and role, typed in as it comes on and gone again
## once it has settled, under the heading strip.
func _draw_ident(v: Visor, ink: Color) -> void:
	if _since_boot > ident_time:
		return
	var fade := clampf((ident_time - _since_boot) / 0.6, 0.0, 1.0)
	var text := "%s · %s" % [v.display_name.to_upper(), role_name(v.mode)]
	_text(Vector2(size.x * 0.5 + sway.x, size.y * 0.2 + sway.y), text, _lit(ink, 0.9 * fade, false),
			HORIZONTAL_ALIGNMENT_CENTER, 400.0, 14)


## The look of the glass itself, never a frame or a tint: a faint scan line
## that rolls down the view, kept to the outer edges so the middle stays
## clear, and two thin glints where the curved glass catches the light.
func _draw_glass(ink: Color) -> void:
	var y := fposmod(_time / maxf(scanline_time, 0.1), 1.0) * size.y
	var line := _lit(ink, 0.06)
	draw_line(Vector2(0.0, y), Vector2(size.x * 0.2, y), line, 2.0)
	draw_line(Vector2(size.x * 0.8, y), Vector2(size.x, y), line, 2.0)
	var glint := _lit(Color(1.0, 1.0, 1.0), 0.05)
	var radius := size.y * 0.9
	draw_arc(Vector2(size.x * 0.5, size.y * 0.95) + sway * 0.5, radius, PI * 1.12, PI * 1.2, 24, glint, 2.0, true)
	draw_arc(Vector2(size.x * 0.5, size.y * 0.95) + sway * 0.5, radius, PI * 1.8, PI * 1.88, 24, glint, 2.0, true)


func _draw_range(ink: Color, centre: Vector2) -> void:
	_text(centre + Vector2(0.0, 58.0), "--- m" if range_reading < 0.0 else "%d m" % roundi(range_reading),
			_lit(ink, 0.9, false), HORIZONTAL_ALIGNMENT_CENTER, 120.0, 13)


## Where `target` stands on the screen, as a box around the body. Empty when
## it is behind the camera.
func _box_of(target: Actor) -> Rect2:
	var camera := get_viewport().get_camera_3d()
	var feet := target.global_position
	var head := feet + Vector3(0.0, Actor.BODY_HEIGHT + 0.1, 0.0)
	if camera == null or camera.is_position_behind(feet) or camera.is_position_behind(head):
		return Rect2()
	var top := camera.unproject_position(head)
	var bottom := camera.unproject_position(feet)
	var tall := maxf(bottom.y - top.y, 14.0)
	var wide := tall * 0.5
	return Rect2(Vector2((top.x + bottom.x) * 0.5 - wide * 0.5, top.y), Vector2(wide, tall))


## Four corner brackets that snap onto whoever is under the crosshair.
func _draw_lock(_p: Actor, ink: Color, note: String) -> void:
	if aim_target == null or not is_instance_valid(aim_target) or aim_target.is_dead:
		return
	var box := _box_of(aim_target)
	if box.size == Vector2.ZERO:
		return
	box = box.grow(lerpf(box.size.y * 0.6, 6.0, ease(lock, 0.3)))
	var arm := clampf(box.size.x * 0.3, 5.0, 26.0)
	var color := _lit(ink, 0.5 + 0.5 * lock, false)
	for corner: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		var at := box.position + box.size * corner
		var inward := Vector2(1.0 - 2.0 * corner.x, 1.0 - 2.0 * corner.y)
		draw_line(at, at + Vector2(arm * inward.x, 0.0), color, 1.5, true)
		draw_line(at, at + Vector2(0.0, arm * inward.y), color, 1.5, true)
	if note != "" and lock > 0.8:
		_text(Vector2(box.end.x + 8.0, box.position.y + 10.0), note, color)


## Looking through the binoculars: a wide ring opens around the view with a
## turning scale on it and marks for judging drop and lead. Nothing is
## blacked out.
func _draw_binoculars(v: Visor, ink: Color, centre: Vector2) -> void:
	var radius := size.y * 0.36 * lerpf(0.35, 1.0, ease(zoom_shown, 0.35))
	var color := _lit(ink, 0.7 * zoom_shown, false)
	draw_arc(centre, radius, 0.0, TAU, 96, _lit(ink, 0.35 * zoom_shown, false), 1.0, true)
	_ticks(centre, radius + 4.0, 0.0, TAU, TAU / 72.0, 5.0, _lit(ink, 0.45 * zoom_shown, false), _time * 0.12)
	_ticks(centre, radius + 4.0, 0.0, TAU, TAU / 12.0, 11.0, color, _time * 0.12)
	# Short hairlines at the ring only: the middle stays clear.
	for dir: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		draw_line(centre + dir * radius * 0.72, centre + dir * radius, color, 1.0, true)
	for step in range(1, 5):
		var down := radius * 0.14 * step
		draw_line(centre + Vector2(-6.0 + step, down), centre + Vector2(6.0 - step, down), color, 1.0, true)
	_text(centre + Vector2(radius * 0.74, radius * 0.74), "%.1fx" % v.zoom_factor(), color)


## A scan going out: a ring that races from the crosshair to the edge of the
## display, and a count of what came back.
func _draw_sweep(v: Visor, ink: Color, centre: Vector2) -> void:
	var since := v.cooldown - v.cooldown_left
	if v.cooldown_left > 0.0 and since < 0.6:
		var done := since / 0.6
		draw_arc(centre, size.y * 0.5 * ease(done, 0.5), 0.0, TAU, 96, _lit(ink, 0.8 * (1.0 - done), false),
				2.0, true)
	if not v.ghosts.is_empty():
		_text(centre + Vector2(0.0, 58.0), "%d CONTACT%s" % [v.ghosts.size(), "" if v.ghosts.size() == 1 else "S"],
				_lit(ink, 0.6 + 0.4 * sin(_time * 10.0), false), HORIZONTAL_ALIGNMENT_CENTER, 200.0, 13)


## Chevrons on the side something came from: a scan that caught the wearer,
## or a hit on a tactical visor.
func _draw_slivers(p: Actor, centre: Vector2, marks: Array[Dictionary], life: float, color: Color,
		radius_share: float) -> void:
	for mark in marks:
		var angle := angle_to(mark.origin, p.global_position, p.cmd.yaw) - PI * 0.5
		var alpha := clampf(mark.left / life, 0.0, 1.0)
		var tint := Color(color.r, color.g, color.b, alpha)
		var radius := size.y * radius_share * (1.0 + 0.06 * (1.0 - alpha))
		draw_arc(centre, radius, angle - 0.16, angle + 0.16, 16, tint, 2.5, true)
		draw_arc(centre, radius + 9.0, angle - 0.09, angle + 0.09, 12, Color(tint.r, tint.g, tint.b, alpha * 0.6),
				1.5, true)


## Tactical: the name, health and armor of whoever is under the crosshair,
## on a leader line beside their brackets.
func _draw_target(ink: Color) -> void:
	if read_target == null or not is_instance_valid(read_target) or read_target.is_dead:
		return
	var box := _box_of(read_target)
	if box.size == Vector2.ZERO:
		return
	var at := Vector2(box.end.x + 22.0, box.position.y + 4.0)
	var width := 110.0 * ease(lock, 0.4)
	var health := read_target.health
	draw_line(Vector2(box.end.x + 6.0, box.position.y + 10.0), at + Vector2(-4.0, 6.0), _lit(ink, 0.6, false), 1.0, true)
	_text(at + Vector2(0.0, -4.0), read_target.display_name.to_upper(), _lit(ink, 0.95, false))
	draw_rect(Rect2(at, Vector2(width, 3.0)), _lit(ink, 0.18, false))
	draw_rect(Rect2(at, Vector2(width * clampf(health.health / maxf(health.max_health, 1.0), 0.0, 1.0), 3.0)),
			Color(1.0, 0.3, 0.22, 0.95 * boot))
	if health.max_armor > 0.0:
		draw_rect(Rect2(at + Vector2(0.0, 6.0), Vector2(width, 2.0)), _lit(ink, 0.18, false))
		draw_rect(Rect2(at + Vector2(0.0, 6.0), Vector2(width * clampf(health.armor / health.max_armor, 0.0, 1.0),
				2.0)), Color(0.45, 0.7, 1.0, 0.95 * boot))


## What a tactical visor says about a container: its best item, and how
## many more there are. Empty for an empty one.
static func loot_text(items: Array) -> String:
	if items.is_empty():
		return ""
	var best: String = items[0]
	for id: String in items:
		if ItemDB.item_value(id) > ItemDB.item_value(best):
			best = id
	return ItemDB.item_name(best) if items.size() == 1 else "%s +%d" % [ItemDB.item_name(best), items.size() - 1]


## Tactical: a callout on every container close by, naming what is inside.
func _draw_loot(p: Actor, ink: Color) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	for node in get_tree().get_nodes_in_group("loot_containers"):
		var container := node as LootContainer
		if container == null or not Raid.together(container, p):
			continue
		var spot := container.global_position + Vector3(0.0, 0.9, 0.0)
		if spot.distance_to(p.global_position) > p.visor.loot_range or camera.is_position_behind(spot):
			continue
		var text := loot_text(container.items)
		if text == "":
			continue
		var at := camera.unproject_position(spot)
		var elbow := at + Vector2(26.0, -30.0)
		draw_circle(at, 2.5, _lit(ink, 0.9, false))
		draw_line(at, elbow, _lit(ink, 0.6, false), 1.0, true)
		draw_line(elbow, elbow + Vector2(120.0, 0.0), _lit(ink, 0.6, false), 1.0, true)
		_text(elbow + Vector2(4.0, -5.0), text.to_upper(), _lit(ink, 0.95, false), HORIZONTAL_ALIGNMENT_LEFT, 300.0)


# --- The layout around the edges --------------------------------------------------
# Everything hugs the rim of the glass and the middle stays clear. Each
# helmet keeps its own glass colour; nothing here is a box laid over the view.

## Where the vitals cell at `slot` (0 the leftmost, fractions between)
## sits: along the lower left curve of the glass, lifting toward the left
## edge the way the visor curves, so they follow its rim, not a straight row.
func cell_point(slot: float) -> Vector2:
	var radius := cell_radius()
	var x := size.y * vitals_left + slot * radius * 2.3
	var from_middle := clampf((size.x * 0.5 - x) / maxf(size.x * 0.5, 1.0), 0.0, 1.0)
	return Vector2(x, size.y * vitals_low - from_middle * from_middle * size.y * vitals_lift) + sway


func cell_radius() -> float:
	return clampf(size.y * 0.028, 18.0, 40.0)


## A flat-topped hexagon's corners.
static func hex_points(at: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 6:
		var angle := TAU * i / 6.0
		points.append(at + Vector2(cos(angle), sin(angle)) * radius)
	return points


## A hex cell, outlined, filled from the bottom by `share` (0 to 1).
func _hex_cell(at: Vector2, radius: float, share: float, color: Color, fill_alpha: float) -> void:
	var hex := hex_points(at, radius)
	var closed := hex.duplicate()
	closed.append(hex[0])
	draw_colored_polygon(hex, Color(color.r, color.g, color.b, color.a * 0.08))
	if share > 0.0:
		var top := at.y + radius - 2.0 * radius * clampf(share, 0.0, 1.0)
		var cut := PackedVector2Array([Vector2(at.x - radius * 2.0, top), Vector2(at.x + radius * 2.0, top),
				Vector2(at.x + radius * 2.0, at.y + radius * 2.0), Vector2(at.x - radius * 2.0, at.y + radius * 2.0)])
		for part in Geometry2D.intersect_polygons(hex_points(at, radius - 3.0), cut):
			draw_colored_polygon(part, Color(color.r, color.g, color.b, color.a * fill_alpha))
	draw_polyline(closed, color, 1.5, true)


## A line glyph for a vitals cell, drawn in `color` around `at`.
func _glyph(kind: String, at: Vector2, unit: float, color: Color) -> void:
	var pts := func(list: Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		for point: Vector2 in list:
			out.append(at + point * unit)
		return out
	match kind:
		"health":
			draw_polyline(pts.call([Vector2(-1, 0), Vector2(-0.35, 0), Vector2(-0.1, -0.7), Vector2(0.25, 0.7),
					Vector2(0.45, 0), Vector2(1, 0)]), color, 2.0, true)
		"armor":
			var shield: PackedVector2Array = pts.call([Vector2(0, -0.95), Vector2(0.8, -0.6), Vector2(0.65, 0.35),
					Vector2(0, 0.95), Vector2(-0.65, 0.35), Vector2(-0.8, -0.6), Vector2(0, -0.95)])
			draw_polyline(shield, color, 2.0, true)
		"stamina":
			draw_polyline(pts.call([Vector2(0.35, -1), Vector2(-0.4, 0.1), Vector2(0.4, 0.1), Vector2(-0.35, 1)]),
					color, 2.0, true)
		"heat":
			draw_polyline(pts.call([Vector2(-0.6, 0.8), Vector2(-0.7, 0.1), Vector2(-0.25, -0.35), Vector2(-0.1, 0.1),
					Vector2(0.15, -0.95), Vector2(0.65, -0.1), Vector2(0.6, 0.8), Vector2(-0.6, 0.8)]), color, 2.0, true)
		"ability":
			draw_arc(at, unit * 0.8, 0.0, TAU, 20, color, 2.0, true)
			draw_polyline(pts.call([Vector2(-0.4, 0), Vector2(0.45, 0)]), color, 2.0, true)
			draw_polyline(pts.call([Vector2(0.15, -0.3), Vector2(0.45, 0), Vector2(0.15, 0.3)]), color, 2.0, true)


## What the vitals cells show, left to right: {"kind", "share" (0 to 1),
## "value" (the number beside it), "label", "ink", "warn"}. Health always;
## armor with an armor frame; stamina always; flight heat with a rig on;
## the ability with one fitted. These are your always-in-view readings: the
## watch no longer carries them.
func vital_cells(p: Actor, ink: Color) -> Array[Dictionary]:
	var cells: Array[Dictionary] = []
	var health := clampf(p.health.health / maxf(p.health.max_health, 1.0), 0.0, 1.0)
	var low := health < 0.35
	cells.append({"kind": "health", "share": health, "value": "%d%%" % roundi(health * 100.0),
			"label": "CRITICAL" if low else "HEALTH", "ink": Color(1.0, 0.25, 0.15) if low else ink, "warn": low})
	if p.health.max_armor > 0.0:
		var armor := clampf(p.health.armor / p.health.max_armor, 0.0, 1.0)
		cells.append({"kind": "armor", "share": armor, "value": "%d%%" % roundi(armor * 100.0),
				"label": "ARMOR", "ink": ARMOR_INK, "warn": false})
	var stamina := clampf(p.stamina / maxf(p.max_stamina, 1.0), 0.0, 1.0)
	cells.append({"kind": "stamina", "share": stamina, "value": "%d%%" % roundi(stamina * 100.0),
			"label": "STAMINA", "ink": ink, "warn": false})
	var rig := p.flight
	if rig.enabled:
		var heat := rig.heat_fraction()
		var cue := Hud.rig_text(p).to_upper()
		cells.append({"kind": "heat", "share": heat, "value": Hud.heat_text(rig),
				"label": cue if cue != "" else "RIG HEAT", "ink": Hud.heat_color(heat, rig.overheated),
				"warn": rig.overheated or heat > 0.6})
	var ability := p.ability
	if ability.enabled:
		var share := 1.0
		var value := "RDY"
		if ability.is_active():
			share = ability.active_left / maxf(ability.duration, 0.01)
			value = "%.1f" % ability.active_left
		elif ability.cooldown_left > 0.0:
			share = 1.0 - ability.cooldown_left / maxf(ability.cooldown, 0.01)
			value = str(ceili(ability.cooldown_left))
		cells.append({"kind": "ability", "share": clampf(share, 0.0, 1.0), "value": value,
				"label": ability.display_name.to_upper(), "ink": ink, "warn": false})
	return cells


## The vitals: a short row of hex cells along the lower left curve of the
## glass, each filling like a gauge, its number beside it. Hurt, the health
## cell goes red and beats.
func _draw_vitals(p: Actor, ink: Color) -> void:
	var cells := vital_cells(p, ink)
	var radius := cell_radius()
	var swept := _swept()
	for i in cells.size():
		var cell: Dictionary = cells[i]
		# Health sits highest, by the left edge; the rest run down the rim
		# toward the bottom. Booting, they slide out along it from the edge.
		var at := cell_point(lerpf(-1.5, float(i), swept))
		var warn: bool = cell.warn
		var beat := 0.6 + 0.4 * sin(_time * 9.0) if warn and cell.kind == "health" else 1.0
		var color := _lit(cell.ink, 0.85 * beat, not warn)
		_hex_cell(at, radius, float(cell.share) * swept, color, 0.4)
		_glyph(cell.kind, at, radius * 0.42, _lit(Color.WHITE.lerp(cell.ink, 0.35), 0.9 * beat, not warn))
		# The number over the cell, and its name under it.
		_text(at + Vector2(0.0, -radius - 6.0), str(cell.value), color, HORIZONTAL_ALIGNMENT_CENTER, 100.0,
				roundi(radius * 0.6))
		_text(at + Vector2(0.0, radius + 14.0), str(cell.label), _lit(cell.ink, 0.65, not warn),
				HORIZONTAL_ALIGNMENT_CENTER, 110.0, 11)
	if altitude >= 0.0:
		var top := cell_point(0.0) + Vector2(-radius, -radius * 2.6)
		_text(top, "ALT %d m" % roundi(altitude), _lit(ink, 0.9, false), HORIZONTAL_ALIGNMENT_LEFT, 140.0, 13)
		var climb := clampf(p.velocity.y / 12.0, -1.0, 1.0)
		draw_line(top + Vector2(-8.0, -4.0), top + Vector2(-8.0, -4.0 - 14.0 * climb), _lit(ink, 0.9, false), 2.0, true)


## Faint pitch ticks up both edges of the glass, sliding as the head tips,
## with where the view points marked at the middle.
func _draw_pitch(p: Actor, ink: Color) -> void:
	var degrees := rad_to_deg(p.cmd.pitch)
	var per := size.y * pitch_scale
	var mid := size.y * 0.5 + sway.y
	var band := size.y * 0.23 * _swept()
	for side: float in [-1.0, 1.0]:
		var edge := size.y * 0.035 + sway.x if side < 0.0 else size.x - size.y * 0.035 + sway.x
		var first := int(floor((degrees - band / per) / 5.0)) * 5
		var mark := first
		while mark <= degrees + band / per + 5.0:
			var y := mid - (mark - degrees) * per
			var off := absf(y - mid)
			if off <= band:
				var fade := 1.0 - off / maxf(band, 1.0)
				var major := posmod(mark, 15) == 0
				var length := 16.0 if major else 7.0
				var from := Vector2(edge, y)
				var to := from + Vector2(-side * length, 0.0)
				draw_line(from, to, _lit(ink, (0.5 if major else 0.3) * fade), 1.5 if major else 1.0, true)
				if major and mark != 0:
					_text(to + Vector2(-side * 6.0, 4.0), "%+d" % mark,
							_lit(ink, 0.45 * fade), HORIZONTAL_ALIGNMENT_RIGHT if side > 0.0 else HORIZONTAL_ALIGNMENT_LEFT,
							60.0, 11)
			mark += 5
		var caret := Vector2(edge - side * 22.0, mid)
		draw_colored_polygon(PackedVector2Array([caret, caret + Vector2(-side * 9.0, -5.0),
				caret + Vector2(-side * 9.0, 5.0)]), _lit(SQUAD_INK, 0.85))
		_text(caret + Vector2(-side * 14.0, 5.0), "%+d" % roundi(degrees),
				_lit(SQUAD_INK, 0.85), HORIZONTAL_ALIGNMENT_RIGHT if side > 0.0 else HORIZONTAL_ALIGNMENT_LEFT, 60.0, 13)


## A strip of bearings across the top that slides as the wearer turns, bowed
## with the glass, with what the helmet knows marked under it
## (`compass_marks`): squad, pings and the nearest depot on every working
## visor, and the helmet's own finds. Bearings are numbered every 15 degrees,
## the eight winds named, and the heading is read out in a notch under the
## middle. Something off the strip waits at its end, pointing.
func _draw_compass(p: Actor, ink: Color) -> void:
	var heading := bearing(p.cmd.yaw)
	var reach := strip_reach * _swept()
	var first := int(floor((heading - strip_reach) / 5.0)) * 5
	for mark in range(first, first + int(strip_reach * 2.0) + 5, 5):
		var off := mark - heading
		if absf(off) > reach:
			continue
		# Marks fade toward the ends of the strip.
		var color := _lit(ink, 0.85 * (1.0 - absf(off) / (strip_reach + 5.0)))
		var at := _strip_point(off)
		var major := posmod(mark, 15) == 0
		draw_line(at, at + Vector2(0.0, 9.0 if major else 4.0), color, 1.5 if major else 1.0, true)
		if major:
			var name := compass_name(posmod(mark, 360)) if posmod(mark, 45) == 0 else "%03d" % posmod(mark, 360)
			_text(at + Vector2(0.0, -5.0), name, color, HORIZONTAL_ALIGNMENT_CENTER, 60.0,
					14 if posmod(mark, 45) == 0 else 11)
	# The heading in a notch under the middle, a thin bracket open at the top.
	var mid := _strip_point(0.0) + Vector2(0.0, 13.0)
	draw_colored_polygon(PackedVector2Array([mid, mid + Vector2(-5.0, 6.0), mid + Vector2(5.0, 6.0)]), _lit(ink, 0.9))
	var notch := PackedVector2Array([mid + Vector2(-26.0, 8.0), mid + Vector2(-26.0, 26.0), mid + Vector2(26.0, 26.0),
			mid + Vector2(26.0, 8.0)])
	draw_polyline(notch, _lit(ink, 0.55), 1.0, true)
	_text(mid + Vector2(0.0, 22.0), "%03d" % roundi(heading), _lit(ink, 0.95), HORIZONTAL_ALIGNMENT_CENTER, 52.0, 15)
	# Marks off the strip queue at its ends, inward, so they never sit on each other.
	var queued := {-1.0: 0, 1.0: 0}
	for mark in compass_marks(p):
		var off := rad_to_deg(angle_to(mark.at, p.global_position, p.cmd.yaw))
		var waiting := 0
		if absf(off) > strip_reach:
			waiting = queued[signf(off)]
			queued[signf(off)] += 1
		_draw_strip_mark(p, ink, mark, off, waiting)


## Where the contact scope sits, and its radius: top left, in the corner of
## the glass.
func scope_rect() -> Rect2:
	var radius := clampf(size.y * 0.075, 48.0, 110.0)
	var at := Vector2(size.y * 0.05 + radius, size.y * 0.06 + radius) + sway
	return Rect2(at - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)


## Where each of the heading strip's marks lands on the contact scope: the
## wearer at the middle facing up, `scope_range` metres to the rim; further
## off it sits on the rim. {"mark", "at" (Vector2), "inside" (bool)}.
func scope_points(p: Actor) -> Array[Dictionary]:
	var rect := scope_rect()
	var centre := rect.get_center()
	var radius := rect.size.x * 0.5
	var out: Array[Dictionary] = []
	for mark in compass_marks(p):
		var flat := Vector2(mark.at.x - p.global_position.x, mark.at.z - p.global_position.z)
		var away := flat.length()
		var angle := angle_to(mark.at, p.global_position, p.cmd.yaw)
		var reach := minf(away / maxf(scope_range, 1.0), 1.0) * (radius - 6.0)
		out.append({"mark": mark, "at": centre + Vector2(sin(angle), -cos(angle)) * reach,
				"inside": away <= scope_range})
	return out


## The contact scope: a small round plot of what the heading strip already
## marks (squad, pings, the depot and the helmet's finds) around the wearer,
## turned so ahead is up. It is not a map: no ground, walls or roads, which
## stay on the watch. The squad's size rides on its rim.
func _draw_scope(p: Actor, ink: Color) -> void:
	var rect := scope_rect()
	var centre := rect.get_center()
	var radius := rect.size.x * 0.5 * lerpf(0.4, 1.0, _swept())
	draw_arc(centre, radius, 0.0, TAU, 64, _lit(ink, 0.5), 1.5, true)
	draw_arc(centre, radius * 0.6, 0.0, TAU, 48, _lit(ink, 0.16), 1.0, true)
	draw_arc(centre, radius * 0.25, 0.0, TAU, 32, _lit(ink, 0.14), 1.0, true)
	# Rim ticks turn with the heading; north gets its letter.
	var turn := -deg_to_rad(bearing(p.cmd.yaw))
	_ticks(centre, radius - 5.0, -PI, PI, TAU / 24.0, 5.0, _lit(ink, 0.35), turn - PI * 0.5)
	var north := centre + Vector2(sin(turn), -cos(turn)) * (radius + 9.0)
	_text(north + Vector2(-20.0, 4.0), "N", _lit(ink, 0.8), HORIZONTAL_ALIGNMENT_CENTER, 40.0, 11)
	# The view's cone and a slow sweep.
	for edge: float in [-0.6, 0.6]:
		draw_line(centre, centre + Vector2(sin(edge), -cos(edge)) * radius, _lit(ink, 0.18), 1.0, true)
	var sweep := fposmod(_time * 1.3, TAU)
	draw_arc(centre, radius * 0.55, sweep, sweep + 0.5, 12, _lit(ink, 0.1), radius * 0.9, false)
	draw_colored_polygon(PackedVector2Array([centre + Vector2(0, -6), centre + Vector2(4.5, 5),
			centre + Vector2(-4.5, 5)]), _lit(ink, 0.95))
	for point in scope_points(p):
		var mark: Dictionary = point.mark
		var tint: Color = {"squad": SQUAD_INK, "ping": PING_INK, "hot": HOT_INK, "tag": TAG_INK}.get(mark.kind, ink)
		var color := _lit(tint, 0.95 if point.inside else 0.55, mark.kind not in ["tag", "contact", "ping"])
		var at: Vector2 = point.at
		if not point.inside:
			var dir := (at - centre).normalized()
			draw_line(centre + dir * (radius - 2.0), centre + dir * (radius + 5.0), color, 2.0, true)
			continue
		match mark.kind:
			"squad":
				draw_polyline(PackedVector2Array([at + Vector2(-5, 4), at + Vector2(5, 4), at + Vector2(0, -5),
						at + Vector2(-5, 4)]), color, 1.5, true)
			"depot":
				draw_rect(Rect2(at - Vector2(4, 4), Vector2(8, 8)), color, false, 1.5)
			"contact":
				draw_arc(at, 4.0, 0.0, TAU, 10, color, 1.5, true)
			_:
				draw_colored_polygon(PackedVector2Array([at + Vector2(0, -5), at + Vector2(5, 0), at + Vector2(0, 5),
						at + Vector2(-5, 0)]), color)
	# The rim's readouts: the squad on the lower left of it, the range on the right.
	var lower := centre + Vector2(0.0, radius + 18.0)
	if not squad.is_empty():
		_text(lower + Vector2(-radius - 10.0, 0.0), "SQUAD %d" % (squad.size() + 1), _lit(SQUAD_INK, 0.85),
				HORIZONTAL_ALIGNMENT_LEFT, 120.0, 12)
	_text(lower + Vector2(radius + 10.0, 0.0), "%d M" % roundi(scope_range), _lit(ink, 0.5),
			HORIZONTAL_ALIGNMENT_RIGHT, 90.0, 11)


## Beside the scope: the helmet's name and role, and its system. How full the
## bar is shows a recharge, a battery or time left; `lit` means it is ready
## or running.
func _draw_system(ink: Color, share: float, text: String, lit: bool) -> void:
	var p := _player()
	var rect := scope_rect()
	var at := Vector2(rect.end.x + 22.0, rect.position.y + rect.size.y * 0.3)
	var width := 190.0 * _swept()
	var glow := 0.75 + 0.25 * sin(_time * 5.0) if lit else 0.6
	_text(at, p.visor.display_name.to_upper() if p != null else "", _lit(ink, 0.95), HORIZONTAL_ALIGNMENT_LEFT, 190.0, 16)
	_text(at + Vector2(0.0, 15.0), role_name(p.visor.mode) if p != null else "", _lit(ink, 0.5),
			HORIZONTAL_ALIGNMENT_LEFT, 190.0, 11)
	var bar := at + Vector2(0.0, 26.0)
	draw_line(bar, bar + Vector2(width, 0.0), _lit(ink, 0.2), 3.0)
	if share > 0.0:
		draw_line(bar, bar + Vector2(width * clampf(share, 0.0, 1.0), 0.0), _lit(ink, 0.9 * glow, not lit), 3.0)
	# Hash marks every tenth, so the bar reads as a gauge, not a loading bar.
	for i in range(1, 10):
		var x := bar.x + width * i / 10.0
		draw_line(Vector2(x, bar.y + 3.0), Vector2(x, bar.y + 6.0), _lit(ink, 0.25), 1.0)
	_text(bar + Vector2(0.0, 22.0), text, _lit(ink, 0.9, not lit), HORIZONTAL_ALIGNMENT_LEFT, 190.0, 13)


## Thermal: how warm the wearer looks to another thermal visor, under the
## helmet's system, so an Ember wearer knows when their own rig gives them away.
func _draw_signature(p: Actor, ink: Color) -> void:
	var heat := Visor.heat_of(p)
	var hot := heat >= 1.2
	var rect := scope_rect()
	var at := Vector2(rect.end.x + 22.0, rect.position.y + rect.size.y * 0.3 + 66.0)
	_text(at, signature_text(heat), _lit(HOT_INK if hot else ink, 0.85, not hot), HORIZONTAL_ALIGNMENT_LEFT, 220.0, 12)


## What the objective block lists, in order: {"title", "have", "goal",
## "share", "done", "tour"}. The contracts held, nearest done first, with this
## life's counts on top, then the new player's tour objective.
func objective_lines(held: Array[Dictionary], tally: Dictionary, objective: String) -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	for entry in held:
		var have: int = int(entry.get("have", 0)) + Contracts.live(str(entry.get("stat", "")), tally)
		var goal: int = maxi(int(entry.get("goal", 1)), 1)
		lines.append({"title": str(entry.get("title", "")), "have": mini(have, goal), "goal": goal,
				"share": clampf(float(have) / goal, 0.0, 1.0), "done": have >= goal, "tour": false})
	lines.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.share > b.share)
	if objective != "":
		lines.append({"title": objective, "have": 0, "goal": 0, "share": -1.0, "done": false, "tour": true})
	return lines


## The objective block, top right: a thin bracket that draws itself along the
## top and down the right edge as the visor comes on, and under it one line per
## objective with a hex bullet, its progress as a thin bar and the count in
## colour. A finished one goes green; the tour's step is marked in the ping
## colour. Nothing is boxed in.
func _draw_objectives(p: Actor, ink: Color) -> void:
	if hud == null:
		return
	var held: Array[Dictionary] = []
	held.assign(hud.get("contracts") if hud.get("contracts") is Array else [])
	var objective := str(hud.get("objective")) if hud.get("objective") != null else ""
	var lines := objective_lines(held, p.tally, objective)
	if lines.is_empty():
		return
	var right := size.x - size.y * 0.06 + sway.x
	var width := clampf(size.x * 0.2, 260.0, 420.0)
	var top := size.y * 0.075 + sway.y
	var row := 36.0
	var drawn := _swept()
	var tall := 34.0 + row * lines.size()
	# The bracket: a rule along the top that runs out from the right, a tick
	# down at its far end, and a line down the right edge.
	draw_line(Vector2(right, top), Vector2(right - width * drawn, top), _lit(ink, 0.6), 1.5, true)
	draw_line(Vector2(right - width * drawn, top), Vector2(right - width * drawn, top + 7.0), _lit(ink, 0.6), 1.5, true)
	draw_line(Vector2(right, top), Vector2(right, top + tall * drawn), _lit(ink, 0.35), 1.0, true)
	draw_line(Vector2(right - 6.0, top + tall * drawn), Vector2(right, top + tall * drawn), _lit(ink, 0.35), 1.0, true)
	var contracts := held.size()
	_text(Vector2(right - width, top - 7.0), "OBJECTIVES" if contracts == 0 else "CONTRACTS", _lit(ink, 0.55),
			HORIZONTAL_ALIGNMENT_LEFT, 200.0, 12)
	if contracts > 0:
		_text(Vector2(right - 8.0, top - 7.0), "%d HELD" % contracts, _lit(ink, 0.55), HORIZONTAL_ALIGNMENT_RIGHT,
				150.0, 12)
	var y := top + 28.0
	for line in lines:
		var x := right - width
		var done: bool = line.done
		var tour: bool = line.tour
		var tint := SQUAD_INK if done else (PING_INK if tour else HOT_INK)
		var bullet := hex_points(Vector2(x + 6.0, y - 5.0), 6.0)
		if done:
			draw_colored_polygon(bullet, _lit(tint, 0.9, false))
		else:
			var closed := bullet.duplicate()
			closed.append(bullet[0])
			draw_polyline(closed, _lit(tint, 0.95, false), 1.5, true)
			if tour:
				draw_circle(Vector2(x + 6.0, y - 5.0), 2.0, _lit(tint, 0.95, false))
		var title: String = line.title
		_text(Vector2(x + 20.0, y), title, _lit(SQUAD_INK if done else Color.WHITE.lerp(ink, 0.4), 0.92),
				HORIZONTAL_ALIGNMENT_LEFT, width - 80.0, 16)
		if not tour:
			_text(Vector2(right - 14.0, y), "%d/%d" % [line.have, line.goal],
					_lit(SQUAD_INK if float(line.share) > 0.0 else ink, 0.95), HORIZONTAL_ALIGNMENT_RIGHT, 60.0, 15)
			var bar := Vector2(x + 20.0, y + 8.0)
			var long := (width - 34.0) * drawn
			draw_line(bar, bar + Vector2(long, 0.0), _lit(ink, 0.18), 2.0)
			if float(line.share) > 0.0:
				draw_line(bar, bar + Vector2(long * float(line.share), 0.0), _lit(SQUAD_INK if done else ink, 0.85), 2.0)
		y += row


## True while the weapon readout should be lit: reloading, the mag low or
## empty, or just after a switch. Otherwise it rests dim: the gun's own
## counter is where ammo is read.
func weapon_awake(held: Weapon) -> bool:
	if held == null:
		return false
	if _since_switch < weapon_show_time:
		return true
	var gun := held as Gun
	if gun == null:
		return false
	return gun.is_reloading() or gun.ammo_in_mag <= floori(gun.mag_size * weapon_low_share)


## The weapon readout, bottom right, mirroring the vitals: the weapon in hand,
## and for a gun the rounds in the mag over a row of ticks, the rounds in the
## pack beside it and a bar while reloading. It rests dim and lights up when
## it matters (`weapon_awake`). Ammo still lives on the gun's own counter.
func _draw_weapon(p: Actor, ink: Color) -> void:
	var held := p.get_active_weapon()
	if held == null:
		return
	var level := lerpf(weapon_rest, 1.0, weapon_lit) * _swept()
	var radius := cell_radius()
	var right := size.x - size.y * vitals_left + sway.x
	var base := size.y * vitals_low + sway.y + radius * 0.3
	var gun := held as Gun
	var low := gun != null and not gun.is_reloading() and gun.ammo_in_mag <= floori(gun.mag_size * weapon_low_share)
	var tint := Color(1.0, 0.3, 0.2) if low else ink
	_text(Vector2(right, base - radius * 2.2), held.display_name.to_upper(), _lit(ink, 0.8 * level, false),
			HORIZONTAL_ALIGNMENT_RIGHT, 260.0, 13)
	draw_line(Vector2(right - 150.0 * _swept(), base - radius * 1.9), Vector2(right, base - radius * 1.9),
			_lit(ink, 0.4 * level, false), 1.0, true)
	draw_line(Vector2(right, base - radius * 1.9), Vector2(right, base - radius * 1.5),
			_lit(ink, 0.4 * level, false), 1.0, true)
	if gun == null:
		return
	if gun.is_reloading():
		var done := 1.0 - gun.reload_left() / maxf(gun.reload_time, 0.01)
		_text(Vector2(right, base - 4.0), "RELOADING", _lit(ink, 0.95 * level, false), HORIZONTAL_ALIGNMENT_RIGHT, 200.0, 18)
		draw_line(Vector2(right - 150.0, base + 8.0), Vector2(right, base + 8.0), _lit(ink, 0.2 * level, false), 3.0)
		draw_line(Vector2(right - 150.0, base + 8.0), Vector2(right - 150.0 + 150.0 * done, base + 8.0),
				_lit(ink, 0.9 * level, false), 3.0)
		return
	# The mag count large, the pack's rounds small beside it.
	var reserve := "/ %d" % gun.reserve_ammo
	_text(Vector2(right, base - 4.0), reserve, _lit(ink, 0.6 * level, false), HORIZONTAL_ALIGNMENT_RIGHT, 90.0, 14)
	var font := ThemeDB.fallback_font
	var reserve_w := font.get_string_size(reserve, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	_text(Vector2(right - reserve_w - 8.0, base - 4.0), str(gun.ammo_in_mag), _lit(tint, 0.95 * level, false),
			HORIZONTAL_ALIGNMENT_RIGHT, 90.0, roundi(radius * 0.9))
	# A tick a round, up to a mag of 40; beyond that, one bar.
	var row := Vector2(right, base + 8.0)
	if gun.mag_size <= 40:
		var step := minf(5.0, 150.0 / maxf(gun.mag_size, 1.0))
		for i in gun.mag_size:
			var x := row.x - i * step
			var full := i < gun.ammo_in_mag
			draw_line(Vector2(x, row.y), Vector2(x, row.y + 6.0), _lit(tint if full else ink, (0.85 if full else 0.15) * level,
					false), 2.0)
	else:
		var share := clampf(float(gun.ammo_in_mag) / maxf(gun.mag_size, 1.0), 0.0, 1.0)
		draw_line(row, row + Vector2(-150.0, 0.0), _lit(ink, 0.2 * level, false), 3.0)
		draw_line(row, row + Vector2(-150.0 * share, 0.0), _lit(tint, 0.9 * level, false), 3.0)
