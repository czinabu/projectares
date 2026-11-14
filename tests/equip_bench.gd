extends Node
## Measures what putting gear on costs in the home base: the frame time of
## the frames after each equip, and whether the player's movement carries
## on through it (a walk that stops dead, or a jump in position, is felt as
## a stutter even when the frame is quick).
##
##   godot --path . res://tests/equip_bench.tscn
##
## Needs a display (or xvfb) to see rendering and dressing costs; headless it
## measures only the game's own processing.

const MainScene := "res://scenes/main.tscn"
const GEAR := ["rifle_carbine", "smg_stinger", "blade_arc", "pistol_machine", "frame_trooper",
		"frame_bulwark", "helm_spotter", "helm_warden", "boots_thruster", "wings_glide", "chip_blink"]
## Each step: slot, item ("" takes it off).
const STEPS := [
	["primary", "rifle_scrap"], ["primary", "rifle_carbine"], ["primary", "smg_stinger"],
	["melee", "blade_scrap"], ["melee", "blade_arc"], ["sidearm", "pistol_machine"],
	["frame", "frame_trooper"], ["frame", "frame_bulwark"], ["helmet", "helm_spotter"],
	["helmet", "helm_warden"], ["rig", "jetpack_mk1"], ["rig", "boots_thruster"],
	["primary", "rifle_carbine"], ["helmet", ""], ["frame", ""], ["primary", "smg_stinger"],
]
const AFTER := 20

var _main: Node
var _made := 0


func _ready() -> void:
	Profile.persist = false
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_size(Vector2i(1280, 720))
	Profile.onboarding = {"skipped": true}
	Profile.add_to_stash(GEAR)
	Profile.loadout = {}
	_main = load(MainScene).instantiate()
	add_child(_main)
	await _frames(60)
	var base: HomeBase = _main.base
	if base == null:
		print("Equip bench: no base")
		get_tree().quit(1)
		return
	var walking := "--walk" in OS.get_cmdline_user_args()
	print("Equip bench: idle frame %.1f ms, idle game time %.1f ms" % [await _worst_frame(AFTER), await _worst_cpu(AFTER)])
	var worst := 0.0
	var total := 0.0
	var actor_swaps := 0
	var nodes_total := 0
	get_tree().node_added.connect(func(_n: Node) -> void: _made += 1)
	print("Equip bench: %s" % ("walking" if walking else "standing"))
	for step: Array in STEPS:
		if walking:
			Input.action_press("move_forward")
			# Walk back and forth across the middle of the room.
			base.player.position = Vector3(0, base.player.position.y, 2)
			await _frames(4)
		var before: Actor = base.player
		var speed_before := Vector2(before.velocity.x, before.velocity.z).length()
		var pos_before := before.global_position
		var made_before := _made
		var t0 := Time.get_ticks_usec()
		_main._on_base_equip(step[0], step[1])
		# The suit-up is deferred to the end of the frame; run it here so its
		# cost is counted with the call (the deferred one then has nothing to do).
		base.suit_up()
		var call_ms := (Time.get_ticks_usec() - t0) / 1000.0
		var frame_max := 0.0
		var cpu_max := 0.0
		var last := Time.get_ticks_usec()
		var speed_min := INF
		var jump := 0.0
		var prev_pos := pos_before
		for i in AFTER:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			frame_max = maxf(frame_max, (now - last) / 1000.0)
			cpu_max = maxf(cpu_max, _cpu_ms())
			last = now
			var who: Actor = base.player
			if i < 3:
				# Only just after the equip: walking on, the room's wall stops you.
				speed_min = minf(speed_min, Vector2(who.velocity.x, who.velocity.z).length())
			jump = maxf(jump, who.global_position.distance_to(prev_pos))
			prev_pos = who.global_position
		if base.player != before:
			actor_swaps += 1
		var made := _made - made_before
		nodes_total += made
		var hitch := call_ms + cpu_max
		worst = maxf(worst, hitch)
		total += hitch
		print("  %-8s %-16s call %6.1f ms  game time after %6.1f ms  frame %6.1f ms  speed %4.1f -> min %4.1f  nodes made %5d  new actor %s" % [
				step[0], step[1] if step[1] != "" else "(off)", call_ms, cpu_max, frame_max,
				speed_before, speed_min, made, base.player != before])
		if walking:
			Input.action_release("move_forward")
		await _frames(10)
	print("Equip bench: worst hitch (call + game time) %.1f ms, mean %.1f ms, actor replaced %d of %d, %d nodes made an equip" % [
			worst, total / STEPS.size(), actor_swaps, STEPS.size(), nodes_total / STEPS.size()])
	get_tree().quit(0)


func _worst_frame(n: int) -> float:
	var worst := 0.0
	var last := Time.get_ticks_usec()
	for i in n:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - last) / 1000.0)
		last = now
	return worst


func _cpu_ms() -> float:
	return (Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0


func _worst_cpu(n: int) -> float:
	var worst := 0.0
	for i in n:
		await get_tree().process_frame
		worst = maxf(worst, _cpu_ms())
	return worst


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
