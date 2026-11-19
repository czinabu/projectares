extends Node3D
## Ashfront's scenery army (DESIGN.md "The battle around you", Caleb's call):
## squads of both armies fighting each other out in the mid distance, so the
## field looks like a war and not a few patrols. View only and never in a
## server: the map adds one only where `Look` is on. Nothing here is a bot,
## nothing collides and nothing goes through `Combat.deal`; the real fight
## near a player is still the real bots'.
##
## The extras are the armies' own riflemen, copied: once per run of the
## game a dressed soldier of each army is posed off in a world of its own
## (a run cycle, aiming, kneeling, fallen) and each pose is baked into one
## plain mesh, simplified to a far copy (`_Baker`). Each frame every extra
## is drawn as one instance of its pose's mesh (a MultiMesh per pose).
##
## Each fight is two squads facing across a line, placed toward the war's
## centre and kept well away from every player (`keep_off`): an extra
## dissolves before anyone could walk up to it, and a fight a player comes
## near ends and starts again elsewhere. The hotter the war, the more fights.
## They run up in hops, kneel or stand to fire (tracers and muzzle flashes,
## heard as far gunfire once the sound arrives), fall, lie a while and
## fade, and fresh ones come up from behind. A round the player's own gun
## sends through one, or a shell landing by one, drops it, on that screen
## only and for nothing.

## How many fights, quiet and in all-out war, and soldiers a side in each.
var fights := Vector2i(2, 5)
var squad := Vector2i(10, 16)
## Nothing of the scenery army is drawn nearer a player or the camera than
## `keep_off`; it dissolves in over `fade_band` past it. A fight is placed
## at least `place_off` from everyone and ends once anyone comes within
## `end_near` of its line.
var keep_off := 48.0
var fade_band := 12.0
var place_off := 85.0
var end_near := 62.0
## How long a fight goes on before it moves toward where the war is now.
var fight_life := Vector2(70.0, 140.0)
## How far apart the two squads start, and how near the line they get.
var start_gap := Vector2(30.0, 44.0)
var front_gap := Vector2(5.0, 13.0)
## A soldier's run speed (m/s), the metres of one run cycle, and a hop.
var run_speed := 5.2
var stride := 2.6
var hop := Vector2(5.0, 11.0)
## Seconds a soldier holds a spot firing before the next hop.
var hold := Vector2(2.5, 7.0)
## Chance a second a soldier holding a spot falls, quiet and in all-out war.
var fall_rate := Vector2(0.025, 0.06)
## How long a fallen soldier lies, and how long it takes to fade.
var lie_time := 8.0
var fade_time := 1.5
## A shell drops every extra within this of where it lands.
var shell_reach := 11.0
## A round passing this close to an extra drops it.
var shot_reach := 0.7
## Tracers: speed (m/s), length, and their colours by army.
var tracer_speed := 260.0
var tracer_length := 12.0
const TRACER_COLOURS := {"legion": Color(1.0, 0.55, 0.18), "tide": Color(0.3, 0.85, 1.0)}

## The armies, west and east, and each one's poses: `RUN_FRAMES` frames of
## the run cycle, then aiming, kneeling and fallen.
const ARMIES := ["legion", "tide"]
const RUN_FRAMES := 8
const AIM := RUN_FRAMES
const KNEEL := RUN_FRAMES + 1
const DEAD := RUN_FRAMES + 2
const POSES := RUN_FRAMES + 3
## Triangles a far copy keeps (the full body has over ten thousand).
const FAR_TRIANGLES := 900
## The most of one army drawn at once.
const CAP := 96

const RUN := 0
const HOLD := 1
const FALLEN := 2

## The poses, baked once per run of the game: army id to an Array of meshes.
static var baked := {}
static var _baking := {}

## Set by the map: the field's radius, and places the army keeps out of
## ([Vector2 centre, radius] each: sites, the Works).
var field := 260.0
var avoid: Array = []

var _raid: Raid
var _rng := RandomNumberGenerator.new()
var _fights: Array[Dictionary] = []
var _soldiers: Array[Dictionary] = []
var _tracers: Array[Dictionary] = []
var _watchers: PackedVector3Array = PackedVector3Array()
var _watch_wait := 0.0
var _incoming: Array[Array] = []
var _sounds: Array[Array] = []
var _gun: Gun
## Drawing: one MultiMeshInstance3D per army and pose, and the tracers.
var _draws: Array = []
var _buffers: Array = []
var _counts: Array = []
var _tracer_mesh: MultiMesh
var _tracer_buffer := PackedFloat32Array()
var _material: ShaderMaterial
var _tracer_material: ShaderMaterial


func _ready() -> void:
	name = "Battle"
	_rng.seed = 2207
	_raid = Raid.of(self)
	if _raid != null:
		_raid.shells_called.connect(_on_shells)
	if Look.enabled:
		_material = ShaderMaterial.new()
		_material.shader = load("res://assets/shaders/extras.gdshader") as Shader
		_tracer_material = ShaderMaterial.new()
		_tracer_material.shader = load("res://assets/shaders/tracer_streak.gdshader") as Shader
		_build_tracers()
		for army: String in ARMIES:
			_bake(army)


# --- The fights ---------------------------------------------------------

func _war_heat() -> float:
	var map := get_parent()
	return clampf(float(map.get_meta("war_intensity", 0.0)), 0.0, 1.0) if map else 0.0


func _war_centre() -> Vector3:
	var map := get_parent()
	var centre: Variant = map.get_meta("war_centre", Vector3.ZERO) if map else Vector3.ZERO
	return centre if centre is Vector3 else Vector3.ZERO


## Everyone the scenery army must keep clear of: the camera and every
## person in this raid (bots fight among themselves and do not count).
func _gather_watchers() -> void:
	_watchers = PackedVector3Array()
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera != null:
		_watchers.append(camera.global_position)
	if _raid == null:
		return
	var bots := {}
	for bot: Variant in _raid.bots:
		bots[bot] = true
	for node: Variant in get_tree().get_nodes_in_group("actors"):
		if not is_instance_valid(node) or bots.has(node):
			continue
		var actor := node as Actor
		if actor != null and Raid.together(actor, self):
			_watchers.append(actor.global_position)


## How far the nearest watcher is from `at` (flat).
func nearest_watcher(at: Vector3) -> float:
	var best := INF
	for w in _watchers:
		best = minf(best, Vector2(w.x - at.x, w.z - at.z).length())
	return best


## Whether a fight may stand at `at`: on the field, out of the places kept
## clear, far from everyone and from the other fights.
func spot_free(at: Vector3) -> bool:
	var flat := Vector2(at.x, at.z)
	if flat.length() > field:
		return false
	for entry: Array in avoid:
		if flat.distance_to(entry[0]) < float(entry[1]) + 12.0:
			return false
	if nearest_watcher(at) < place_off:
		return false
	for fight in _fights:
		if not fight.ending and (fight.centre as Vector3).distance_to(at) < 70.0:
			return false
	return true


func _place_fight() -> bool:
	var centre := _war_centre()
	var best := Vector3.INF
	var best_score := -INF
	for i in 28:
		var r := sqrt(_rng.randf()) * field
		var a := _rng.randf() * TAU
		var at := Vector3(cos(a) * r, 0.0, sin(a) * r)
		if not spot_free(at):
			continue
		var score := -Vector2(at.x - centre.x, at.z - centre.z).length() + _rng.randf() * 90.0
		if score > best_score:
			best_score = score
			best = at
	if not best.is_finite():
		return false
	var turn := _rng.randf_range(-0.6, 0.6)
	var fight := {"centre": best, "axis": Vector3(cos(turn), 0.0, sin(turn)), "left": _rng.randf_range(fight_life.x, fight_life.y),
			"ending": false, "sound": _rng.randf_range(0.5, 2.0)}
	_fights.append(fight)
	var size := _rng.randi_range(squad.x, squad.y)
	for side in 2:
		for i in size:
			_soldiers.append(_new_soldier(fight, side, true))
	return true


func _new_soldier(fight: Dictionary, side: int, first: bool) -> Dictionary:
	var sign := -1.0 if side == 0 else 1.0
	var axis: Vector3 = fight.axis
	var across := Vector3(-axis.z, 0.0, axis.x)
	var back := _rng.randf_range(start_gap.x, start_gap.y) * (_rng.randf_range(0.4, 1.0) if first else 1.0)
	var at: Vector3 = fight.centre + axis * sign * back + across * _rng.randf_range(-22.0, 22.0)
	var soldier := {"fight": fight, "side": side, "pos": _ground(at), "heading": 0.0, "state": RUN,
			"goal": at, "wait": 0.0, "phase": _rng.randf(), "fade": 0.0, "shown": 0.0, "dead_for": 0.0,
			"burst": 0, "next_shot": _rng.randf_range(0.5, 2.0), "scale": _rng.randf_range(0.95, 1.05),
			"kneel": _rng.randf() < 0.45}
	_next_goal(soldier)
	return soldier


## The soldier's next hop toward the line, never past its own side of it.
func _next_goal(soldier: Dictionary) -> void:
	var fight: Dictionary = soldier.fight
	var axis: Vector3 = fight.axis
	var sign := -1.0 if int(soldier.side) == 0 else 1.0
	var pos: Vector3 = soldier.pos
	var depth := (pos - (fight.centre as Vector3)).dot(axis) * sign
	var front := _rng.randf_range(front_gap.x, front_gap.y)
	var step := minf(_rng.randf_range(hop.x, hop.y), maxf(depth - front, 0.0))
	var across := Vector3(-axis.z, 0.0, axis.x) * _rng.randf_range(-3.0, 3.0)
	soldier.goal = pos - axis * sign * step + across
	soldier.state = RUN if step > 1.0 else HOLD
	soldier.wait = _rng.randf_range(hold.x, hold.y)


func _ground(at: Vector3) -> Vector3:
	var map := get_parent()
	if map != null and map.has_method("ground_height"):
		return Vector3(at.x, float(map.call("ground_height", at.x, at.z)), at.z)
	return at


## Drops a soldier where it is (a round, a shell, its luck).
func fell(soldier: Dictionary) -> void:
	if int(soldier.state) == FALLEN:
		return
	soldier.state = FALLEN
	soldier.dead_for = 0.0


func _tick(delta: float) -> void:
	var heat := _war_heat()
	var wanted := int(round(lerpf(fights.x, fights.y, heat)))
	var live := 0
	for fight in _fights:
		if not fight.ending:
			live += 1
	if live < wanted:
		_place_fight()
	for fight in _fights.duplicate():
		fight.left = float(fight.left) - delta
		if not fight.ending and (float(fight.left) <= 0.0 or nearest_watcher(fight.centre) < end_near):
			fight.ending = true
		if fight.ending and not _has_soldiers(fight):
			_fights.erase(fight)
		fight.sound = float(fight.sound) - delta
		if fight.sound <= 0.0 and not fight.ending:
			fight.sound = _rng.randf_range(1.5, 4.0) * lerpf(1.6, 0.8, heat)
			_far_fire(fight.centre)
	var rate := lerpf(fall_rate.x, fall_rate.y, heat)
	for soldier in _soldiers.duplicate():
		_tick_soldier(soldier, delta, rate)
	_tick_tracers(delta)
	_tick_incoming(delta)


func _has_soldiers(fight: Dictionary) -> bool:
	for soldier in _soldiers:
		if soldier.fight == fight:
			return true
	return false


func _tick_soldier(soldier: Dictionary, delta: float, rate: float) -> void:
	var fight: Dictionary = soldier.fight
	var pos: Vector3 = soldier.pos
	# How much of it is shown: fading in when it comes up, out once fallen
	# or when its fight ends, and never near anyone.
	var near := clampf((nearest_watcher(pos) - keep_off) / fade_band, 0.0, 1.0)
	var target := 1.0
	match int(soldier.state):
		RUN:
			var to: Vector3 = (soldier.goal as Vector3) - pos
			to.y = 0.0
			var step := run_speed * delta
			if to.length() <= step:
				soldier.pos = _ground(soldier.goal)
				soldier.state = HOLD
			else:
				soldier.pos = _ground(pos + to.normalized() * step)
				soldier.heading = atan2(to.x, to.z)
				soldier.phase = fmod(float(soldier.phase) + step / stride, 1.0)
		HOLD:
			var sign := 1.0 if int(soldier.side) == 0 else -1.0
			var face: Vector3 = fight.axis * sign
			soldier.heading = atan2(face.x, face.z)
			soldier.wait = float(soldier.wait) - delta
			if float(soldier.wait) <= 0.0:
				_next_goal(soldier)
			_shoot(soldier, delta)
			if _rng.randf() < rate * delta:
				fell(soldier)
		FALLEN:
			soldier.dead_for = float(soldier.dead_for) + delta
			if float(soldier.dead_for) > lie_time:
				target = 0.0
	if fight.ending:
		target = 0.0
	var shown := float(soldier.shown)
	shown = move_toward(shown, target, delta / fade_time)
	soldier.shown = shown
	soldier.fade = shown * near
	if shown <= 0.0 and target == 0.0:
		_soldiers.erase(soldier)
		if not fight.ending:
			_soldiers.append(_new_soldier(fight, int(soldier.side), false))


## A holding soldier fires in bursts at the other side's line.
func _shoot(soldier: Dictionary, delta: float) -> void:
	soldier.next_shot = float(soldier.next_shot) - delta
	if float(soldier.next_shot) > 0.0:
		return
	if int(soldier.burst) <= 0:
		soldier.burst = _rng.randi_range(2, 5)
	soldier.burst = int(soldier.burst) - 1
	soldier.next_shot = 0.11 if int(soldier.burst) > 0 else _rng.randf_range(0.8, 2.6)
	if float(soldier.fade) < 0.5:
		return
	var fight: Dictionary = soldier.fight
	var sign := 1.0 if int(soldier.side) == 0 else -1.0
	var axis: Vector3 = fight.axis
	var from: Vector3 = (soldier.pos as Vector3) + Vector3(0.0, 1.0 if soldier.kneel else 1.45, 0.0) + axis * sign * 0.8
	var aim: Vector3 = (fight.centre as Vector3) + axis * sign * _rng.randf_range(8.0, 30.0) \
			+ Vector3(-axis.z, 0.0, axis.x) * _rng.randf_range(-20.0, 20.0)
	aim = _ground(aim) + Vector3(0.0, _rng.randf_range(0.2, 2.5), 0.0)
	var colour: Color = TRACER_COLOURS[ARMIES[int(soldier.side)]]
	_tracers.append({"from": from, "dir": (aim - from).normalized(), "travel": 0.0, "reach": from.distance_to(aim) + 30.0,
			"colour": colour})
	# The muzzle's flash: a short fat burst, gone in a few frames.
	_tracers.append({"from": from, "dir": (aim - from).normalized(), "travel": 0.0, "reach": 12.0, "flash": true,
			"colour": Color(1.0, 0.75, 0.4)})


func _far_fire(at: Vector3) -> void:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		return
	var delay := Soundscape.boom_delay(camera.global_position.distance_to(at))
	_sounds.append([delay, at])


func _tick_tracers(delta: float) -> void:
	for i in range(_tracers.size() - 1, -1, -1):
		var tracer: Dictionary = _tracers[i]
		tracer.travel = float(tracer.travel) + tracer_speed * delta
		if float(tracer.travel) > float(tracer.reach):
			_tracers.remove_at(i)
	for i in range(_sounds.size() - 1, -1, -1):
		_sounds[i][0] -= delta
		if _sounds[i][0] <= 0.0:
			Sfx.play("far_fire", _sounds[i][1] + Vector3(0, 2, 0), _rng.randf_range(-10.0, -4.0), 320.0, 22.0)
			_sounds.remove_at(i)


# --- What drops an extra ------------------------------------------------

func _on_shells(points: PackedVector3Array, lands_in: PackedFloat32Array) -> void:
	for i in mini(points.size(), lands_in.size()):
		_incoming.append([lands_in[i], points[i]])


func _tick_incoming(delta: float) -> void:
	for i in range(_incoming.size() - 1, -1, -1):
		_incoming[i][0] -= delta
		if _incoming[i][0] <= 0.0:
			shell_landed(_incoming[i][1])
			_incoming.remove_at(i)


func shell_landed(at: Vector3) -> void:
	for soldier in _soldiers:
		if (soldier.pos as Vector3).distance_to(at) < shell_reach:
			fell(soldier)


## A round the player's gun sent from `from` to `to`: the first extra
## shown on that line drops.
func shot(from: Vector3, to: Vector3) -> void:
	var line := to - from
	var length := line.length()
	if length < 1.0:
		return
	var way := line / length
	var best: Dictionary = {}
	var best_along := INF
	for soldier in _soldiers:
		if int(soldier.state) == FALLEN or float(soldier.fade) < 0.5:
			continue
		var centre: Vector3 = (soldier.pos as Vector3) + Vector3(0.0, 0.7 if soldier.kneel and int(soldier.state) == HOLD else 1.0, 0.0)
		var along := (centre - from).dot(way)
		if along < 0.0 or along > length + 1.0 or along > best_along:
			continue
		var off := (from + way * along).distance_to(centre)
		if off < shot_reach + 0.3:
			best = soldier
			best_along = along
	if not best.is_empty():
		fell(best)


## Follows whatever gun the local player holds.
func _follow_gun() -> void:
	var controller := get_tree().get_first_node_in_group("player_controllers") as PlayerController
	var gun: Gun = null
	if controller != null and is_instance_valid(controller.actor) and Raid.together(controller.actor, self):
		gun = controller.actor.weapon as Gun
	if gun == _gun:
		return
	if is_instance_valid(_gun) and _gun.fired.is_connected(shot):
		_gun.fired.disconnect(shot)
	_gun = gun
	if _gun != null:
		_gun.fired.connect(shot)


func soldiers() -> Array[Dictionary]:
	return _soldiers


func fight_list() -> Array[Dictionary]:
	return _fights


func _process(delta: float) -> void:
	_watch_wait -= delta
	if _watch_wait <= 0.0:
		_watch_wait = 0.4
		_gather_watchers()
		if Look.enabled:
			_follow_gun()
	_tick(minf(delta, 0.1))
	if Look.enabled:
		_draw()


# --- Drawing ------------------------------------------------------------

func _build_draws() -> void:
	for a in ARMIES.size():
		var meshes: Array = baked[ARMIES[a]]
		var row: Array = []
		var buffers: Array = []
		for p in POSES:
			var multimesh := MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.use_custom_data = true
			multimesh.mesh = meshes[p]
			multimesh.instance_count = CAP
			multimesh.visible_instance_count = 0
			var node := MultiMeshInstance3D.new()
			node.multimesh = multimesh
			node.material_override = _material
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.custom_aabb = AABB(Vector3(-field - 60.0, -40.0, -field - 60.0), Vector3(field * 2.0 + 120.0, 160.0, field * 2.0 + 120.0))
			add_child(node)
			row.append(multimesh)
			var buffer := PackedFloat32Array()
			buffer.resize(CAP * 16)
			buffers.append(buffer)
		_draws.append(row)
		_buffers.append(buffers)


func _build_tracers() -> void:
	_tracer_mesh = MultiMesh.new()
	_tracer_mesh.transform_format = MultiMesh.TRANSFORM_3D
	_tracer_mesh.use_custom_data = true
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	_tracer_mesh.mesh = box
	_tracer_mesh.instance_count = 256
	_tracer_mesh.visible_instance_count = 0
	_tracer_buffer.resize(256 * 16)
	var node := MultiMeshInstance3D.new()
	node.multimesh = _tracer_mesh
	node.material_override = _tracer_material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.custom_aabb = AABB(Vector3(-field - 60.0, -40.0, -field - 60.0), Vector3(field * 2.0 + 120.0, 160.0, field * 2.0 + 120.0))
	add_child(node)


func _draw() -> void:
	if _draws.is_empty():
		if baked.has(ARMIES[0]) and baked.has(ARMIES[1]):
			_build_draws()
		else:
			return
	var counts := [[], []]
	for a in 2:
		counts[a].resize(POSES)
		counts[a].fill(0)
	for soldier in _soldiers:
		var fade := float(soldier.fade)
		if fade <= 0.01:
			continue
		var a := int(soldier.side)
		var pose := DEAD
		match int(soldier.state):
			RUN:
				pose = int(float(soldier.phase) * RUN_FRAMES) % RUN_FRAMES
			HOLD:
				pose = KNEEL if soldier.kneel else AIM
		var n: int = counts[a][pose]
		if n >= CAP:
			continue
		counts[a][pose] = n + 1
		var buffer: PackedFloat32Array = _buffers[a][pose]
		var h := float(soldier.heading)
		var s := float(soldier.scale)
		var c := cos(h) * s
		var si := sin(h) * s
		var at: Vector3 = soldier.pos
		var o := n * 16
		buffer[o] = c; buffer[o + 1] = 0.0; buffer[o + 2] = si; buffer[o + 3] = at.x
		buffer[o + 4] = 0.0; buffer[o + 5] = s; buffer[o + 6] = 0.0; buffer[o + 7] = at.y
		buffer[o + 8] = -si; buffer[o + 9] = 0.0; buffer[o + 10] = c; buffer[o + 11] = at.z
		buffer[o + 12] = fade; buffer[o + 13] = float(a); buffer[o + 14] = 0.0; buffer[o + 15] = 0.0
		_buffers[a][pose] = buffer
	for a in 2:
		for p in POSES:
			var multimesh: MultiMesh = _draws[a][p]
			var n: int = counts[a][p]
			if n > 0:
				multimesh.buffer = _buffers[a][p]
			multimesh.visible_instance_count = n
	_draw_tracers()


func _draw_tracers() -> void:
	var n := 0
	for tracer in _tracers:
		if n >= 256:
			break
		var dir: Vector3 = tracer.dir
		var travel := float(tracer.travel)
		var tail := maxf(0.0, travel - tracer_length)
		var mid: Vector3 = (tracer.from as Vector3) + dir * (tail + travel) * 0.5
		if nearest_watcher(mid) < keep_off * 0.6:
			continue
		var length := travel - tail
		var thick := 0.28
		if tracer.get("flash", false):
			mid = tracer.from
			length = 1.2
			thick = 0.9
		var basis := Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT)
		basis = basis.scaled_local(Vector3(thick, thick, length))
		var colour: Color = tracer.colour
		var o := n * 16
		_tracer_buffer[o] = basis.x.x; _tracer_buffer[o + 1] = basis.y.x; _tracer_buffer[o + 2] = basis.z.x; _tracer_buffer[o + 3] = mid.x
		_tracer_buffer[o + 4] = basis.x.y; _tracer_buffer[o + 5] = basis.y.y; _tracer_buffer[o + 6] = basis.z.y; _tracer_buffer[o + 7] = mid.y
		_tracer_buffer[o + 8] = basis.x.z; _tracer_buffer[o + 9] = basis.y.z; _tracer_buffer[o + 10] = basis.z.z; _tracer_buffer[o + 11] = mid.z
		_tracer_buffer[o + 12] = colour.r; _tracer_buffer[o + 13] = colour.g; _tracer_buffer[o + 14] = colour.b
		# A fresh round is the muzzle's flash: brighter for its first metres.
		_tracer_buffer[o + 15] = 4.0 if travel < 8.0 else 2.2
		n += 1
	if n > 0:
		_tracer_mesh.buffer = _tracer_buffer
	_tracer_mesh.visible_instance_count = n


# --- Baking the far copies ----------------------------------------------

func _bake(army: String) -> void:
	if baked.has(army) or _baking.has(army):
		return
	_baking[army] = true
	var baker := _Baker.new()
	baker.army = army
	var world: Variant = Worlds.of(self)
	baker.dress = Callable(world, "dress_extra") if world != null and world.has_method("dress_extra") else Callable()
	baker.done.connect(func(meshes: Array) -> void:
		baked[army] = meshes
		_baking.erase(army)
		baker.queue_free())
	add_child(baker)


## Poses one soldier of an army in a world of its own and bakes each pose
## into a far copy. Frees itself when done.
class _Baker:
	extends SubViewport

	signal done(meshes: Array)

	var army := ""
	var dress := Callable()
	var _actor: Actor
	var _skin: Node
	var _player: AnimationPlayer
	var _meshes: Array = []
	var _want := -1
	var _run_anim := ""
	var _images := {}

	func _ready() -> void:
		own_world_3d = true
		render_target_update_mode = SubViewport.UPDATE_DISABLED
		size = Vector2i(2, 2)
		_meshes.resize(POSES)
		var ground := StaticBody3D.new()
		ground.collision_layer = Actor.LAYER_WORLD
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(600, 2, 600)
		shape.shape = box
		ground.add_child(shape)
		add_child(ground)
		# Far off, so nothing it sounds (a footstep, its fall) is heard.
		ground.position = Vector3(0, -1, -3000)
		_actor = Actor.new()
		_actor.name = "Extra"
		add_child(_actor)
		_actor.remove_from_group("actors")
		_actor.collision_layer = 0
		_actor.collision_mask = Actor.LAYER_WORLD
		_actor.global_position = Vector3(0, 0.1, -3000)
		if dress.is_valid():
			dress.call(_actor, army)
		_run()

	func _run() -> void:
		var tree := get_tree()
		for i in 20:
			await tree.process_frame
		_skin = _actor.get_node_or_null("Skin")
		var skeleton: Skeleton3D = _actor.find_child("Skeleton3D", true, false) as Skeleton3D
		if _skin == null or skeleton == null:
			push_warning("battle: no soldier to bake for %s" % army)
			return
		_skin.set("detail_ranges", [INF, INF, INF] as Array[float])
		_player = _skin.get("_player") as AnimationPlayer
		skeleton.skeleton_updated.connect(_grab)
		# The run: forward, until each frame of a steady cycle is caught.
		_actor.cmd.yaw = 0.0
		_actor.cmd.move = Vector2(0, 1)
		for i in 40:
			await tree.process_frame
		_run_anim = _player.current_animation if _player else ""
		_want = 0
		for i in 600:
			await tree.process_frame
			if _ready_count(RUN_FRAMES) >= RUN_FRAMES:
				break
		_want = -1
		_actor.cmd.move = Vector2.ZERO
		_actor.cmd.secondary = true
		for i in 60:
			await tree.process_frame
		await _take(AIM)
		_actor.cmd.crouch = true
		for i in 50:
			await tree.process_frame
		await _take(KNEEL)
		_actor.cmd.crouch = false
		_actor.cmd.secondary = false
		_actor.kill("shell")
		for i in 150:
			await tree.process_frame
		await _take(DEAD)
		for p in POSES:
			if _meshes[p] == null:
				_meshes[p] = _meshes[0] if _meshes[0] != null else BoxMesh.new()
		done.emit(_meshes)

	func _ready_count(upto: int) -> int:
		var n := 0
		for p in upto:
			if _meshes[p] != null:
				n += 1
		return n

	func _take(pose: int) -> void:
		_want = pose
		for i in 10:
			await get_tree().process_frame
			if _meshes[pose] != null:
				break
		_want = -1

	func _grab() -> void:
		if _want < 0:
			return
		var pose := _want
		if _want < RUN_FRAMES:
			if _player == null or _player.current_animation != _run_anim or _player.current_animation_length <= 0.0:
				return
			var phase := _player.current_animation_position / _player.current_animation_length * RUN_FRAMES
			if absf(phase - round(phase)) > 0.3:
				return
			pose = int(round(phase)) % RUN_FRAMES
		if _meshes[pose] != null:
			return
		var merged := _merge()
		if (merged[Mesh.ARRAY_INDEX] as PackedInt32Array).size() >= 3:
			_meshes[pose] = _far(merged)

	## Every visible mesh on the body, posed, as one mesh coloured per vertex.
	func _merge() -> Array:
		var verts := PackedVector3Array()
		var normals := PackedVector3Array()
		var colours := PackedColorArray()
		var indices := PackedInt32Array()
		var inv := _actor.global_transform.affine_inverse()
		for node in _actor.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if mi.mesh == null or not mi.is_visible_in_tree():
				continue
			var mesh: Mesh = mi.bake_mesh_from_current_skeleton_pose() if mi.skin != null else mi.mesh
			var xf := inv * mi.global_transform
			var turn := Transform3D(xf.basis.inverse().transposed(), Vector3.ZERO)
			for s in mesh.get_surface_count():
				if mesh is ArrayMesh and (mesh as ArrayMesh).surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
					continue
				var arrays := mesh.surface_get_arrays(s)
				var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				if v.is_empty():
					continue
				var base := verts.size()
				verts.append_array(xf * v)
				var n: Variant = arrays[Mesh.ARRAY_NORMAL]
				if n is PackedVector3Array and (n as PackedVector3Array).size() == v.size():
					normals.append_array(turn * (n as PackedVector3Array))
				else:
					var up := PackedVector3Array()
					up.resize(v.size())
					up.fill(Vector3.UP)
					normals.append_array(up)
				colours.append_array(_colours(mi.get_active_material(s), arrays))
				var idx: Variant = arrays[Mesh.ARRAY_INDEX]
				if idx is PackedInt32Array and not (idx as PackedInt32Array).is_empty():
					for i: int in idx:
						indices.append(base + i)
				else:
					for i in v.size():
						indices.append(base + i)
		var out := []
		out.resize(Mesh.ARRAY_MAX)
		out[Mesh.ARRAY_VERTEX] = verts
		out[Mesh.ARRAY_NORMAL] = normals
		out[Mesh.ARRAY_COLOR] = colours
		out[Mesh.ARRAY_INDEX] = indices
		return out

	## A surface's colour at each vertex: its material's colour times its
	## texture where the vertex's UV falls.
	func _colours(material: Material, arrays: Array) -> PackedColorArray:
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colour := Color(0.5, 0.5, 0.5)
		var texture: Texture2D = null
		if material is ShaderMaterial:
			var sm := material as ShaderMaterial
			var base: Variant = sm.get_shader_parameter("base_color")
			if base is Color:
				colour = base
			elif base is Vector3:
				colour = Color(base.x, base.y, base.z)
			else:
				colour = Color.WHITE
			var tint: Variant = sm.get_shader_parameter("tint")
			if tint is Color:
				colour *= tint
			var tex: Variant = sm.get_shader_parameter("base_tex")
			if tex is Texture2D:
				texture = tex
		elif material is BaseMaterial3D:
			colour = (material as BaseMaterial3D).albedo_color
			texture = (material as BaseMaterial3D).albedo_texture
		colour.a = 1.0
		var out := PackedColorArray()
		out.resize(v.size())
		out.fill(colour)
		var uvs: Variant = arrays[Mesh.ARRAY_TEX_UV]
		if texture == null or not uvs is PackedVector2Array or (uvs as PackedVector2Array).size() != v.size():
			return out
		var image: Image = _images.get(texture)
		if image == null:
			image = texture.get_image()
			if image == null:
				return out
			if image.is_compressed():
				image.decompress()
			if image.get_width() > 128:
				image.resize(128, maxi(1, image.get_height() * 128 / image.get_width()))
			_images[texture] = image
		var w := image.get_width() - 1
		var h := image.get_height() - 1
		var uv_list: PackedVector2Array = uvs
		for i in v.size():
			var uv := uv_list[i]
			var texel := image.get_pixel(int(fposmod(uv.x, 1.0) * w), int(fposmod(uv.y, 1.0) * h))
			out[i] = Color(colour.r * texel.r, colour.g * texel.g, colour.b * texel.b, 1.0)
		return out

	## The far copy: the merged body simplified to about `FAR_TRIANGLES`.
	func _far(arrays: Array) -> ArrayMesh:
		var importer := ImporterMesh.new()
		importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
		importer.generate_lods(25.0, 60.0, [])
		var out_arrays := importer.get_surface_arrays(0)
		for l in importer.get_surface_lod_count(0):
			var idx := importer.get_surface_lod_indices(0, l)
			if idx.size() / 3 <= FAR_TRIANGLES:
				out_arrays[Mesh.ARRAY_INDEX] = idx
				break
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out_arrays)
		return mesh
