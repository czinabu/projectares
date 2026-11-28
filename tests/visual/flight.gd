extends RefCounted
## `--flight-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --flight-only [--move <name>]` (run with `--fixed-fps
## 60`, so a drawn frame is a tick and the moves keep time) flies each flight rig
## through its moves with the real controls, the camera following beside it,
## and saves every other tick's frame to `flight/<move>/NNN.png`, for GIFs
## and contact sheets: a jetpack's take-off, climb, hover and drop to a
## landing, its boost and the flare out of it, the boots' kicks, and the
## wings' glide down from a height to a landing.

## Each move: the rig, how high above the ground it starts, how many ticks
## it runs, and the controls held at each tick (`_controls`).
const MOVES := {
	"jetpack_takeoff": {"rig": "jetpack_mk1", "lift": 0.0, "ticks": 260},
	"jetpack_boost": {"rig": "jetpack_mk1", "lift": 0.0, "ticks": 240},
	"boots_kicks": {"rig": "boots_thruster", "lift": 0.0, "ticks": 200},
	"wings_glide": {"rig": "wings_glide", "lift": 9.0, "ticks": 330},
	"jetpack_cruise": {"rig": "jetpack_mk1", "lift": 0.0, "ticks": 420},
	"boots_skate": {"rig": "boots_thruster", "lift": 0.0, "ticks": 420},
	"wings_soar": {"rig": "wings_glide", "lift": 0.0, "ticks": 480},
	# The same flights seen square from the side, to judge a pose's lines
	# (`as`: whose controls; `side`: the camera off the right hand).
	"wings_soar_side": {"rig": "wings_glide", "lift": 20.0, "ticks": 300, "as": "wings_soar", "side": true},
	"wings_glide_side": {"rig": "wings_glide", "lift": 9.0, "ticks": 330, "as": "wings_glide", "side": true},
	# A jetpack cruise set down on the ground: it runs out on its feet,
	# braced in a skid (the wings' run-out is in `wings_glide_side`).
	"jetpack_land_side": {"rig": "jetpack_mk1", "lift": 0.0, "ticks": 300, "side": true},
	# The style pass: a hover that drifts off, stops, slides sideways and
	# stops (the lean into the push, the limbs swinging on), and a wing
	# swoop: a dive, a pull back up and a carve.
	"jetpack_hover": {"rig": "jetpack_mk1", "lift": 0.0, "ticks": 330},
	"wings_swoop": {"rig": "wings_glide", "lift": 30.0, "ticks": 360},
}


static func shoot(v: Node, out_dir: String, args: PackedStringArray) -> void:
	var only := ""
	var at := args.find("--move")
	if at >= 0 and at + 1 < args.size():
		only = args[at + 1]
	for move: String in MOVES:
		if only == "" or only == move:
			await _fly(v, out_dir, move)


static func _fly(v: Node, out_dir: String, move: String) -> void:
	var spec: Dictionary = MOVES[move]
	var raid := Raid.new()
	v.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42, ["rifle_carbine", spec["rig"], "frame_trooper"])
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.global_position += Vector3(0, -300, 0)
	var p := raid.player
	await v._settle(20)
	p.global_position += Vector3(0, float(spec["lift"]), 0)
	p.velocity = Vector3.ZERO
	p.cmd.yaw = p.rotation.y
	p.cmd.pitch = 0.0
	var cam := Camera3D.new()
	cam.fov = 55.0
	raid.add_child(cam)
	cam.make_current()
	var dir := out_dir.path_join("flight").path_join(move)
	DirAccess.make_dir_recursive_absolute(dir)
	var follow := p.global_position
	var yaw0 := p.cmd.yaw
	var start := p.global_position
	for tick in int(spec["ticks"]):
		_controls(p.cmd, spec.get("as", move), tick)
		# The cruises carve: the view swings left, then back right.
		if not spec.get("side", false) and (move.ends_with("cruise") or move.ends_with("skate") or move.ends_with("soar") or move.ends_with("swoop")):
			p.cmd.yaw = yaw0 - 0.5 * sin(float(tick - 180) / 120.0 * PI) * clampf((tick - 180) / 60.0, 0.0, 1.0)
		if tick % 60 == 0:
			print("%s t=%d pos=%s speed=%.1f h=%.1f heat=%.0f skate=%s soar=%s boost=%s glide=%s" % [move, tick,
					p.global_position - start, Vector2(p.velocity.x, p.velocity.z).length(),
					p.height_above_ground(50.0), p.flight.heat, p.flight.is_skating, p.flight.is_soaring,
					p.flight.is_boosting, p.flight.is_gliding])
		p.cmd.aim_dir = -p.global_basis.z
		if move == "jetpack_land_side" and tick == 138:
			p.global_position.y -= p.height_above_ground(50.0) - 0.2
		await v.get_tree().physics_frame
		# The signal comes before the tick's step: wait the step out, or the
		# next tick's controls would land on it and lose this one's presses.
		await v.get_tree().process_frame
		if tick % 2 != 0:
			continue
		# A chase camera beside and behind the way it flies, eased.
		var flat := Vector3(p.velocity.x, 0.0, p.velocity.z)
		var ahead := flat.normalized() if flat.length() > 2.0 else -p.global_basis.z
		var right := ahead.cross(Vector3.UP).normalized()
		var mid := p.global_position + Vector3(0, 1.0, 0)
		var want := mid - ahead * 4.2 + right * 2.6 + Vector3(0, 0.8, 0)
		if spec.get("side", false):
			want = mid + right * 5.0 + Vector3(0, 0.2, 0)
		follow = want if tick == 0 else follow.lerp(want, 0.6)
		cam.global_position = follow
		cam.look_at(mid)
		await RenderingServer.frame_post_draw
		var frame := v.get_viewport().get_texture().get_image()
		frame.resize(frame.get_width() / 3, frame.get_height() / 3)
		frame.save_png(dir.path_join("%03d.png" % (tick / 2)))
	print("saved flight/", move)
	raid.queue_free()
	await v._settle(2)


## What is held at `tick` (60 a second) for `move`.
static func _controls(cmd: ActorCommand, move: String, tick: int) -> void:
	cmd.jump_pressed = false
	cmd.sprint_pressed = false
	cmd.jump = false
	cmd.sprint = false
	cmd.secondary = false
	cmd.slide = false
	cmd.move = Vector2.ZERO
	match move:
		"jetpack_takeoff":
			# Stand, jump and hold to climb, hold aim to hover drifting
			# forward, then let go and drop to a landing.
			cmd.jump_pressed = tick == 15
			cmd.jump = tick >= 15 and tick < 80
			cmd.secondary = tick >= 80 and tick < 160
			if tick >= 110 and tick < 160:
				cmd.move = Vector2(0, 0.7)
		"jetpack_boost":
			# Up, a boost forward, the flare out of it into a hover, down.
			cmd.jump_pressed = tick == 10
			cmd.jump = tick >= 10 and tick < 50
			cmd.secondary = (tick >= 50 and tick < 70) or (tick >= 150 and tick < 190)
			cmd.sprint = tick >= 70 and tick < 150
			cmd.sprint_pressed = tick == 70
			if tick >= 70 and tick < 150:
				cmd.move = Vector2(0, 1.0)
		"boots_kicks":
			# A jump, three kicks forward, a landing.
			cmd.jump_pressed = tick in [15, 45, 75, 105]
			cmd.jump = cmd.jump_pressed
			if tick >= 40 and tick < 140:
				cmd.move = Vector2(0, 1.0)
		"jetpack_cruise":
			# Up a few meters, then Shift held: the rocket cruise.
			cmd.jump_pressed = tick == 10
			cmd.jump = tick >= 10 and tick < 70
			cmd.sprint = tick >= 70 and tick < 400
			cmd.sprint_pressed = tick == 70
			if cmd.sprint:
				cmd.move = Vector2(0, 1.0)
		"boots_skate":
			# A sprint, a jump into the skate, a kick over something, on.
			cmd.sprint = tick >= 5 and tick < 400
			cmd.move = Vector2(0, 1.0) if cmd.sprint else Vector2.ZERO
			cmd.jump_pressed = tick == 40 or tick == 240
			cmd.jump = cmd.jump_pressed
		"wings_soar":
			# A launch, the glide, Shift held to soar, pulled up to climb,
			# then level.
			cmd.jump_pressed = tick == 10
			cmd.jump = tick >= 10 and tick < 60
			cmd.sprint = tick >= 45 and tick < 460
			cmd.sprint_pressed = tick == 45
			if tick >= 120 and tick < 240:
				cmd.move = Vector2(0, -0.6)
		"jetpack_hover":
			# Up on held jump with aim held (the jets), then a drift ahead,
			# a stop, a slide right and a stop.
			cmd.secondary = tick >= 10
			cmd.jump_pressed = tick == 10
			cmd.jump = tick >= 10 and tick < 60
			if tick >= 90 and tick < 170:
				cmd.move = Vector2(0, 1.0)
			elif tick >= 220 and tick < 280:
				cmd.move = Vector2(1.0, 0.0)
		"wings_swoop":
			# Off a height: the glide, a dive for speed, a pull back up.
			cmd.jump = tick >= 15
			if tick >= 60 and tick < 160:
				cmd.move = Vector2(0, 1.0)
			elif tick >= 160 and tick < 250:
				cmd.move = Vector2(0, -1.0)
		"jetpack_land_side":
			# A hop and the rocket cruise, set down onto the ground while it
			# still cruises (`_fly`), as a cruise skimming into a rise does.
			cmd.jump_pressed = tick == 10
			cmd.jump = tick >= 10 and tick < 30
			cmd.sprint = tick >= 30 and tick < 140
			cmd.sprint_pressed = tick == 30
			if cmd.sprint:
				cmd.move = Vector2(0, 1.0)
		"wings_glide":
			# Off a height: the fall, the glide held, a dive straight into
			# the ground at speed (the run-out), then a step back.
			cmd.jump = tick >= 25
			if tick >= 110 and tick < 190:
				cmd.move = Vector2(0, 1.0)
			elif tick >= 200:
				cmd.move = Vector2(0, -1.0)
