class_name Footsteps
extends Node3D
## A body's footsteps, heard (`docs/systems/audio.md`). `Sfx` hangs one on every
## actor as it comes into the game; view only, so it is never made on a
## headless server. Steps come from how far the body has really moved on
## the ground since the last one, not from its animation, so a remote
## player, a thinned far bot and your own body all step the same way, and
## a step's ground is whatever the feet stand on (`ground_at`).
##
## Kept affordable: nothing is done past `reach` from the ear but one
## distance check, the bodies in earshot share one budget of steps a second
## (`Sfx.take_step`), and both shrink with the sound detail (`Sfx.sound_detail`,
## turned down on the Low and Lowest presets).

## How far off (m) steps are heard at full sound detail.
var reach := 32.0
## The step's volume (dB) crouched, walking and at a full sprint.
var crouch_db := -20.0
var walk_db := -13.0
var sprint_db := -5.0
## Your own steps sit this much (dB) under everyone else's, so walking
## about never drowns out what you listen for.
var own_trim_db := -5.0
## Seconds in the air after which coming down is a landing (heavier, louder).
var land_after := 0.35
## The ground straight under the feet is looked up again only this often.
var ground_every := 0.4

var actor: Actor
var _player: AudioStreamPlayer3D
var _last := Vector3.INF
var _travel := 0.0
var _airborne := 0.0
var _ground := "hard"
var _ground_age := 99.0


func _ready() -> void:
	actor = get_parent() as Actor
	if actor == null:
		set_process(false)
		return
	_player = AudioStreamPlayer3D.new()
	_player.max_polyphony = 2
	_player.unit_size = 4.0
	_player.max_distance = reach
	add_child(_player)


## How long one step is (m) at `speed` (m/s): a walk's short steps, a run's
## long ones, so a sprint is a few more steps a second than a walk, not
## many more.
static func step_length(speed: float) -> float:
	return clampf(0.45 + speed * 0.22, 0.7, 2.2)


## A step's volume (dB) at `speed`, crouched or not.
func step_db(speed: float, crouched: bool) -> float:
	if crouched:
		return crouch_db
	return lerpf(walk_db, sprint_db, clampf((speed - 1.5) / 6.5, 0.0, 1.0))


## The ground a body standing on `collider` at `at` steps on: a piece that
## names its own ("footstep" meta) is that, the open ground is what the
## world says it is there (`WorldDef.footstep_ground`), and anything else
## built (floors, decks, roads, rock) is hard.
static func ground_for(collider: Object, world: WorldDef, at: Vector3) -> String:
	if collider == null:
		return "hard"
	if collider is Node and (collider as Node).has_meta("footstep"):
		return String((collider as Node).get_meta("footstep"))
	if collider is Terrain and world != null:
		return world.footstep_ground(at)
	return "hard"


## The ground under the feet now, looked up by a short ray straight down.
func ground_at(at: Vector3) -> String:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.3, at + Vector3.DOWN * 1.2,
			Actor.LAYER_WORLD)
	var hit := space.intersect_ray(query)
	return ground_for(hit.get("collider"), Worlds.current, at)


func _process(delta: float) -> void:
	var at := actor.global_position
	var moved := Vector2(at.x - _last.x, at.z - _last.z).length() if _last.is_finite() else 0.0
	_last = at
	var camera := get_viewport().get_camera_3d()
	var far := reach * lerpf(0.55, 1.0, Sfx.sound_detail())
	if actor.is_dead or actor.vehicle != null or camera == null \
			or camera.global_position.distance_squared_to(at) > far * far or moved > 3.0:
		_travel = 0.0
		_airborne = 0.0
		return
	if actor.airborne_time > 0.0 or actor.is_sliding():
		_airborne += delta
		return
	_ground_age += delta
	var landed := _airborne >= land_after
	_airborne = 0.0
	if landed:
		_step(at, camera, 9.0, 4.0)
		_travel = 0.0
		return
	_travel += moved
	var speed := moved / maxf(delta, 0.001)
	if _travel >= step_length(speed):
		_travel = 0.0
		_step(at, camera, speed, step_db(speed, actor.crouched))


func _step(at: Vector3, camera: Camera3D, speed: float, volume_db: float) -> void:
	var own := camera.global_position.distance_to(at) < 4.0 and actor.is_player
	if not own and not Sfx.take_step():
		return
	if _ground_age >= ground_every:
		_ground_age = 0.0
		_ground = ground_at(at)
	var stream := Sfx.get_stream("step_" + _ground)
	if stream == null:
		stream = Sfx.get_stream("step_hard")
	if stream == null:
		return
	if _player.stream != stream:
		_player.stream = stream
	_player.max_distance = reach
	_player.volume_db = volume_db + (own_trim_db if own else 0.0)
	# A heavier body (or a landing) is a touch lower.
	_player.pitch_scale = 0.92 if speed > 8.0 else 1.0
	_player.play()
