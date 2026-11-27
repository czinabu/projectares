extends RefCounted
## `--tour-flow-only`, a mode `visual_check.gd` finds by itself.
## Plays the new player's tour in the real game (`main.tscn`, a fresh
## profile) and shoots what the player sees at each step: the guide's light
## over the next thing to use with the step written on it, the key to press
## under the crosshair for the watch, and the handler's pop-up. Solo, so the
## plaza and the gentle world are opened directly.

const Onboarding := preload("res://core/progression/onboarding.gd")


static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	Profile.reset()
	Profile.welcome_granted = false
	Profile.grant_welcome_crate()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	v.add_child(main)
	await v._settle(40)
	await v._shot(out_dir.path_join("flow_1_arrive.png"))
	var guide: Node3D = main._tour_guide
	if guide != null:
		_face(main, guide.target)
		await v._settle(20)
		await v._shot(out_dir.path_join("flow_2_gear_guide.png"))
	var rifle: Node = main.base.display_for("rifle_carbine")
	if rifle != null:
		rifle.interact(main.base.player)
	await v._settle(20)
	await v._shot(out_dir.path_join("flow_3_watch_hint.png"))
	main.controller.wrist_raised = true
	await v._settle(40)
	await v._shot(out_dir.path_join("flow_4_watch_up.png"))
	main.controller.wrist_raised = false
	await v._settle(30)
	if main._tour_guide != null:
		_face(main, main._tour_guide.target)
	await v._settle(30)
	await v._shot(out_dir.path_join("flow_5_lane_guide.png"))
	main.base.target_hit.emit()
	await v._settle(30)
	if main._tour_guide != null:
		_face(main, main._tour_guide.target)
	await v._settle(30)
	await v._shot(out_dir.path_join("flow_6_door_guide.png"))
	main.start_raid(Worlds.social_world().id)
	await v._settle(30)
	# Solo there are no contracts: stand at the step that sends you to the board.
	Profile.onboarding = {"state": Onboarding.ACTIVE, "step": "contract"}
	main._tour_moved()
	await v._settle(30)
	if main._tour_guide != null:
		_face(main, main._tour_guide.target)
	await v._settle(40)
	await v._shot(out_dir.path_join("flow_7_board_guide.png"))
	Profile.onboarding = {"state": Onboarding.ACTIVE, "step": "deploy"}
	main._tour_moved()
	await v._settle(30)
	if main._tour_guide != null:
		_face(main, main._tour_guide.target)
	await v._settle(40)
	await v._shot(out_dir.path_join("flow_8_gate_guide.png"))
	var gentle := str(Onboarding.names().gentle_id)
	main._leave_raid()
	main.go_home()
	await v._settle(20)
	main.start_raid(gentle)
	await v._settle(60)
	if main._tour_guide != null:
		_face(main, main._tour_guide.target)
	await v._settle(40)
	await v._shot(out_dir.path_join("flow_9_depot_guide.png"))
	main.queue_free()
	await v._settle(5)


## Turns the player's view toward `at`.
static func _face(main: Node, at: Vector3) -> void:
	var controller: PlayerController = main.controller
	if controller == null or controller.actor == null:
		return
	var to := at - controller.actor.global_position
	controller.yaw = atan2(-to.x, -to.z)
	controller.pitch = 0.0
