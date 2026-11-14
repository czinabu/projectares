class_name VisorHud
extends Control
## What a helmet shows its wearer. Two halves:
##
## The glass. Drawn over the view in first person only, and only while a
## helmet is worn: the visor projects its readouts into your view. It is a
## display of thin lines of light, never a frame: nothing is blacked out or
## tinted, and nothing sits over the middle of the view but the reticle.
## Every helmet has your vitals on the left: a health arc, with armor and
## stamina as thinner arcs inside it, and the ability's state under it. With
## a flight rig worn, its heat gauge and cue sit high on the right. A working
## helmet has its system on an arc on the right, a ring around the crosshair, and its height
## readout in the air. Every working helmet has a heading strip across the
## top, bowed with the glass, marking the squad, pings and the nearest depot
## (`compass_marks`), and the contract nearest done in the top left. Each
## helmet has a role (`role_name`), shown as it comes on, its own reticle,
## and the rest depends on its `mode` (see `Visor`): range finder, lock-on
## brackets, binocular scale and tagged targets on the strip for "zoom"
## (recon); a sweep, contact count and the scan's contacts on the strip for
## "scan" (intel); for "threat" (tactical) the health of whoever is under
## the crosshair, what nearby loot holds, the war's hot zone on the strip
## and where a hit came from; for "thermal" a heat picture of the whole view
## and how warm you look yourself. A scrap visor only manages a bearing.
## The display is alive: it sweeps in when it comes on (`boot`),
## trails the view a little as you turn (`sway`), sits dim until something
## happens (`alert`) and closes on what you aim at (`lock`). With no helmet,
## or in third person, nothing is drawn.
##
## The world. Things a visor puts out there, seen in either view: the frozen
## snapshots of a scan, markers over tagged targets, the ring of a scan pulse
## (anyone's), the outlines of Threat Sense, the glint off a lens that is
## looking your way, and the ember of a thermal visor seen up close.
##
## A view only: it reads `Visor` state and never decides what is revealed.

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
## The war must be at least this hot before a tactical visor marks its centre.
var hot_from := 0.25
## How long the helmet's name stays up after the display comes on.
var ident_time := 2.4
## Seconds the glass's scan line takes to run down the view.
var scanline_time := 5.5

var raid: Raid
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
## How far the binocular scale has opened, 0 to 1.
var zoom_shown := 0.0
## Height above the ground while off it, below zero when standing on it.
var altitude := -1.0
## Everyone on the wearer's squad in this world, alive (see `squadmate`).
var squad: Array[Actor] = []
## Spots the wearer's side pinged: {"at": Vector3, "left": float}.
var pings: Array[Dictionary] = []
## The `Hud` this glass belongs to, for the contracts held. May be null.
var hud: Hud

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


func setup(p_raid: Raid, p_controller: PlayerController) -> void:
	raid = p_raid
	controller = p_controller


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world = Node3D.new()
	_world.name = "VisorWorld"
	raid.add_child.call_deferred(_world)
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
	if raid.player != null:
		raid.player.visor.felt_scan.connect(_on_felt_scan)
		raid.player.visor.threatened.connect(_on_threatened)
		raid.player.health.damaged.connect(func(_info: DamageInfo) -> void: alert = 1.0)
	raid.pinged.connect(_on_pinged)


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
	if raid == null or raid.player == null or not is_instance_valid(raid.player):
		return null
	return raid.player


func _process(delta: float) -> void:
	_time += delta
	var p := _player()
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
	for depot in raid.depots:
		if is_instance_valid(depot) and Raid.together(depot, p) and (nearest == null
				or depot.global_position.distance_to(p.global_position)
				< nearest.global_position.distance_to(p.global_position)):
			nearest = depot
	if nearest != null:
		marks.append({"kind": "depot", "at": nearest.global_position, "label": "DEPOT"})
	if v.mode == "threat" and raid.war.intensity >= hot_from:
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
	_draw_vitals(p, ink, centre)
	_draw_heat(p, ink, centre)
	_draw_ident(v, ink)
	if v.mode == "":
		_draw_heading(p, ink)
	else:
		_draw_reticle(ink, centre, v.mode)
		_draw_altitude(p, ink, centre)
		_draw_compass(p, ink)
		_draw_tracker(p, ink)
	match v.mode:
		"zoom":
			_draw_lock(p, ink, "%d m" % roundi(range_reading) if range_reading >= 0.0 else "")
			_draw_range(ink, centre)
			_draw_system(ink, centre, float(v.zoom_level) / maxf(v.zoom_levels.size(), 1.0),
					"OPTIC %dx" % roundi(v.zoom_factor()) if v.is_zoomed() else "OPTIC", v.is_zoomed())
			if zoom_shown > 0.01:
				_draw_binoculars(v, ink, centre)
		"scan":
			_draw_system(ink, centre, 1.0 - clampf(v.cooldown_left / maxf(v.cooldown, 0.01), 0.0, 1.0),
					"SCAN" if v.cooldown_left <= 0.0 else "SCAN %d" % ceili(v.cooldown_left), v.cooldown_left <= 0.0)
			_draw_sweep(v, ink, centre)
		"threat":
			_draw_lock(p, ink, "")
			_draw_target(ink)
			_draw_loot(p, ink)
			if v.is_sensing():
				_draw_system(Color(1.0, 0.3, 0.2), centre, v.active_left / maxf(v.threat_time, 0.01),
						"THREATS %d" % v.threats.size(), true)
			else:
				_draw_system(ink, centre, 1.0 - clampf(v.cooldown_left / maxf(v.cooldown, 0.01), 0.0, 1.0),
						"SENSE" if v.cooldown_left <= 0.0 else "SENSE %d" % ceili(v.cooldown_left),
						v.cooldown_left <= 0.0)
		"thermal":
			_draw_system(ink, centre, v.charge_fraction(), "THERMAL" if v.thermal_on else "CELL %d%%" %
					roundi(v.charge_fraction() * 100.0), v.thermal_on)
			_draw_signature(p, ink, centre)
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


## The left arc: health, as a row of segments that empties from the top,
## with armor and then stamina as thin arcs just inside it, and the
## ability's state under it. These are your always-in-view readings: the
## watch no longer carries them. Hurt, the health arc goes red.
func _draw_vitals(p: Actor, ink: Color, centre: Vector2) -> void:
	var share := clampf(p.health.health / maxf(p.health.max_health, 1.0), 0.0, 1.0)
	var radius := size.y * 0.43
	var half := 0.36 * _swept()
	var low := share < 0.35
	var color := Color(1.0, 0.25, 0.15) if low else ink
	draw_arc(centre, radius, PI - half, PI + half, 40, _lit(color, 0.22), 1.0, true)
	_ticks(centre, radius + 5.0, PI - half, PI + half, 0.045, 5.0, _lit(color, 0.22), _time * 0.05)
	# Health fills from the bottom of the arc (PI - half) upward.
	var segments := 18
	var filled := ceili(segments * share)
	for i in filled:
		var a0 := PI - half + (2.0 * half) * (float(i) + 0.15) / segments
		var a1 := PI - half + (2.0 * half) * (float(i) + 0.85) / segments
		var beat := 0.6 + 0.4 * sin(_time * 9.0) if low else 1.0
		draw_arc(centre, radius - 6.0, a0, a1, 4,
				_lit(color, 0.85 * beat, not low), 3.0, true)
	# Armor and stamina: thin unbroken arcs inside, filling the same way.
	var armor := clampf(p.health.armor / p.health.max_armor, 0.0, 1.0) if p.health.max_armor > 0.0 else -1.0
	var stamina := clampf(p.stamina / maxf(p.max_stamina, 1.0), 0.0, 1.0)
	var inner := radius - 13.0
	for reading: Array in [[armor, ARMOR_INK], [stamina, ink]]:
		var value: float = reading[0]
		if value < 0.0:
			continue
		var tint: Color = reading[1]
		draw_arc(centre, inner, PI - half, PI + half, 32, _lit(tint, 0.14), 1.0, true)
		if value > 0.0:
			draw_arc(centre, inner, PI + half - 2.0 * half * value, PI + half, 32,
					_lit(tint, 0.7, value > 0.3), 2.0, true)
		inner -= 5.0
	if low:
		_text(centre + Vector2(-radius + 16.0, 4.0), "CRITICAL", _lit(color, 0.6 + 0.4 * sin(_time * 9.0), false))
	var ability := ability_text(p.ability)
	if ability != "":
		var ready := p.ability.cooldown_left <= 0.0 and not p.ability.is_active()
		_text(centre + Vector2(-radius + 4.0, size.y * 0.43 * sin(half) + 22.0), ability,
				_lit(ink, 0.85, not ready))


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


## High on the right, while a flight rig is worn: its heat as a gauge that
## fills upward and warms from green to red, with a notch at the heat it
## must cool to after an overheat, and the rig's cue under it
## (`Hud.rig_text`). It brightens as it gets hot.
func _draw_heat(p: Actor, _ink: Color, centre: Vector2) -> void:
	var rig := p.flight
	if not rig.enabled:
		return
	var heat := rig.heat_fraction()
	var color := Hud.heat_color(heat, rig.overheated)
	var radius := size.y * 0.43
	# High on the right, above the system arc: clear of the gun in the hand.
	var bottom := -0.46
	var top := bottom - 0.3 * _swept()
	var hot := rig.overheated or heat > 0.6
	draw_arc(centre, radius, top, bottom, 24, _lit(color, 0.22), 1.0, true)
	if heat > 0.0:
		# Fills from the bottom end upward, away from the system arc.
		draw_arc(centre, radius - 6.0, bottom - (bottom - top) * heat, bottom, 24, _lit(color, 0.9, not hot), 4.0, true)
	var notch := bottom - (bottom - top) * clampf(rig.recover_heat / maxf(rig.max_heat, 1.0), 0.0, 1.0)
	var dir := Vector2(cos(notch), sin(notch))
	draw_line(centre + dir * (radius - 11.0), centre + dir * (radius + 3.0), _lit(color, 0.6, not hot), 1.0, true)
	var end := centre + Vector2(cos(top), sin(top)) * radius
	var cue := Hud.rig_text(p).to_upper()
	_text(end + Vector2(-10.0, -10.0), Hud.heat_text(rig) + ("   " + cue if cue != "" else ""),
			_lit(color, 0.9, not hot), HORIZONTAL_ALIGNMENT_RIGHT, 320.0)


## The right arc: the helmet's own system. How full it is shows a recharge,
## a battery or time left; `lit` means it is ready or running.
func _draw_system(ink: Color, centre: Vector2, share: float, text: String, lit: bool) -> void:
	var radius := size.y * 0.43
	var half := 0.36 * _swept()
	draw_arc(centre, radius, -half, half, 40, _lit(ink, 0.22), 1.0, true)
	_ticks(centre, radius + 5.0, -half, half, 0.045, 5.0, _lit(ink, 0.22), -_time * (0.3 if lit else 0.05))
	var glow := 0.75 + 0.25 * sin(_time * 5.0) if lit else 0.6
	if share > 0.0:
		draw_arc(centre, radius - 6.0, half - 2.0 * half * clampf(share, 0.0, 1.0), half, 32,
				_lit(ink, 0.85 * glow, not lit), 3.0, true)
	_text(centre + Vector2(radius - 16.0, 4.0), text, _lit(ink, 0.9, not lit), HORIZONTAL_ALIGNMENT_RIGHT, 160.0)


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


## Height above the ground, shown only while the wearer is off it.
func _draw_altitude(p: Actor, ink: Color, centre: Vector2) -> void:
	if altitude < 0.0:
		return
	var at := centre + Vector2(-size.y * 0.43 + 16.0, size.y * 0.2)
	_text(at, "ALT %d m" % roundi(altitude), _lit(ink, 0.9, false))
	var climb := clampf(p.velocity.y / 12.0, -1.0, 1.0)
	draw_line(at + Vector2(-8.0, -4.0), at + Vector2(-8.0, -4.0 - 14.0 * climb), _lit(ink, 0.9, false), 2.0, true)


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


## A strip of bearings across the top that slides as the wearer turns, bowed
## with the glass, with what the helmet knows marked on it (`compass_marks`):
## squad, pings and the nearest depot on every working visor, and the
## helmet's own finds. Something off the strip waits at its end, pointing.
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
		var cardinal := posmod(mark, 45) == 0
		draw_line(at, at + Vector2(0.0, 10.0 if cardinal else 5.0), color, 1.0, true)
		if cardinal:
			_text(at + Vector2(0.0, -6.0), compass_name(mark), color, HORIZONTAL_ALIGNMENT_CENTER, 60.0, 13)
	var mid := _strip_point(0.0)
	draw_line(mid + Vector2(-5.0, 22.0), mid + Vector2(0.0, 15.0), _lit(ink, 0.9), 1.5, true)
	draw_line(mid + Vector2(5.0, 22.0), mid + Vector2(0.0, 15.0), _lit(ink, 0.9), 1.5, true)
	_text(mid + Vector2(0.0, -22.0), "%03d" % roundi(heading), _lit(ink, 0.9), HORIZONTAL_ALIGNMENT_CENTER, 80.0)
	# Marks off the strip queue at its ends, inward, so they never sit on each other.
	var queued := {-1.0: 0, 1.0: 0}
	for mark in compass_marks(p):
		var off := rad_to_deg(angle_to(mark.at, p.global_position, p.cmd.yaw))
		var waiting := 0
		if absf(off) > strip_reach:
			waiting = queued[signf(off)]
			queued[signf(off)] += 1
		_draw_strip_mark(p, ink, mark, off, waiting)


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


## The contract nearest done, small and dim in the top left (DESIGN.md
## section 10: "a small tracker on the visor"). Held contracts come from the
## `Hud`; this life's counts ride on top.
func _draw_tracker(p: Actor, ink: Color) -> void:
	if hud == null:
		return
	var at := Vector2(size.x * 0.06, size.y * 0.075) + sway
	var text := tracker_text(hud.contracts, p.tally)
	if text != "":
		draw_rect(Rect2(at + Vector2(0.0, -9.0), Vector2(7.0, 7.0)), _lit(ink, 0.7), false, 1.0)
		_text(at + Vector2(13.0, 0.0), text, _lit(ink, 0.75), HORIZONTAL_ALIGNMENT_LEFT, 360.0, 12)
		at.y += 18.0
	# The new player's tour: what the handler asked for next, under it.
	if hud.objective != "":
		var c := at + Vector2(3.5, -5.5)
		draw_polyline(PackedVector2Array([c + Vector2(0, -4), c + Vector2(4, 0), c + Vector2(0, 4),
				c + Vector2(-4, 0), c + Vector2(0, -4)]), _lit(ink, 0.8), 1.0, true)
		_text(at + Vector2(13.0, 0.0), hud.objective.to_upper(), _lit(ink, 0.8), HORIZONTAL_ALIGNMENT_LEFT, 360.0, 12)


## Thermal: how warm the wearer looks to another thermal visor, under the
## system arc, so an Ember wearer knows when their own rig gives them away.
func _draw_signature(p: Actor, ink: Color, centre: Vector2) -> void:
	var heat := Visor.heat_of(p)
	var hot := heat >= 1.2
	var at := centre + Vector2(size.y * 0.43 - 16.0, 24.0)
	_text(at, signature_text(heat), _lit(HOT_INK if hot else ink, 0.85, not hot), HORIZONTAL_ALIGNMENT_RIGHT, 160.0, 12)


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
