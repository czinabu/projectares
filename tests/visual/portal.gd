extends RefCounted
## `--portal-only`, a mode `visual_check.gd` finds by itself.
## `--portal-only` shows the watch's portal icon in the home base, then the
## squad portal it opens, in first and third person.


static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	var base := HomeBase.new()
	base.show_gear(["rifle_carbine"], {"primary": "rifle_carbine"})
	v.add_child(base)
	var controller := PlayerController.new()
	controller.setup(base.player)
	controller.portal_requested.connect(func(to: String) -> void: base.open_portal(to))
	base.add_child(controller)
	var base_hud: CanvasLayer = preload("res://core/ui/base_hud.gd").new()
	base_hud.setup(base)
	base.add_child(base_hud)
	# Face the open floor in front of the deploy area.
	base.player.global_position = Vector3(2.0, 0.1, 3.0)
	controller.yaw = PI * 0.6
	await v._settle(60)
	controller.wrist_raised = true
	controller.watch_focus = Hud.Wrist.SLOTS.find("portal")
	controller.watch_focus_moved = true
	controller.watch_open = "portal"
	controller.portal_pick = Portal.destinations().find("ashfront")
	await v._settle(30)
	await v._shot(out_dir.path_join("portal_watch_first.png"))
	controller.click_watch()
	await v._settle(12)
	await v._shot(out_dir.path_join("portal_unfolding_first.png"))
	await v._settle(40)
	await v._shot(out_dir.path_join("portal_open_first.png"))
	controller.toggle_view()
	await v._settle(40)
	await v._shot(out_dir.path_join("portal_open_third.png"))
	base.queue_free()
	await v._settle(3)
