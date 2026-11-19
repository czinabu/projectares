extends RefCounted
## `--tour-only`, a mode `visual_check.gd` finds by itself.
## `--tour-only` shows the new player's tour objective: on the base's
## watch card in both views, and on a helmet's visor glass out in a world.


static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	var line := "Hit a plate on the test lane"
	var base := HomeBase.new()
	base.show_gear(["rifle_carbine"], {"primary": "rifle_carbine"})
	v.add_child(base)
	var controller := PlayerController.new()
	controller.setup(base.player)
	base.add_child(controller)
	var base_hud: CanvasLayer = preload("res://core/ui/base_hud.gd").new()
	base_hud.setup(base)
	base_hud.objective = line
	base.add_child(base_hud)
	await v._settle(60)
	controller.wrist_raised = true
	await v._settle(30)
	await v._shot(out_dir.path_join("tour_watch_first.png"))
	controller.toggle_view()
	await v._settle(40)
	await v._shot(out_dir.path_join("tour_watch_third.png"))
	base.queue_free()
	await v._settle(3)
	var raid := Raid.new()
	v.add_child(raid)
	raid.start(Worlds.get_world("frostline"), 42, ["rifle_scrap", "helm_seeker"] as Array[String])
	v._armed(raid)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	var raider := PlayerController.new()
	raider.setup(raid.player)
	raid.add_child(raider)
	var hud := Hud.new()
	hud.setup(raid, raider)
	hud.objective = "Bank your loot at a depot"
	raid.add_child(hud)
	await v._settle(80)
	await v._shot(out_dir.path_join("tour_visor.png"))
	raider.wrist_raised = true
	await v._settle(30)
	await v._shot(out_dir.path_join("tour_visor_watch.png"))
	raid.queue_free()
	await v._settle(3)
