extends RefCounted
## Checks for the aiming mark (`core/ui/crosshair.gd`): its gap follows the
## gun's real spread, and its colour and shape say reload, empty, out of
## range and an enemy under it.

const CrosshairScript := preload("res://core/ui/crosshair.gd")


static func run(t: Node) -> void:
	_numbers(t)
	await _in_raid(t)


static func _numbers(t: Node) -> void:
	print("Crosshair: spread and states")
	t.check(is_zero_approx(CrosshairScript.spread_px(0.0, 75.0, 1000.0)), "no spread, no gap")
	t.check(is_equal_approx(CrosshairScript.spread_px(37.5, 75.0, 1000.0), 500.0),
			"a cone as wide as half the view reaches the screen's edge")
	t.check(CrosshairScript.spread_px(2.0, 55.0, 1000.0) > CrosshairScript.spread_px(2.0, 80.0, 1000.0),
			"zoomed in, the same spread opens the ticks wider")
	var gun := Gun.new()
	gun.max_range = 100.0
	t.check(CrosshairScript.state_for(null, -1.0, false) == "dot", "no gun in hand: the dot alone")
	t.check(CrosshairScript.state_for(gun, -1.0, false) == "ready", "a loaded gun over the sky: ready")
	t.check(CrosshairScript.state_for(gun, 50.0, true) == "hostile", "an enemy in range: hostile")
	t.check(CrosshairScript.state_for(gun, 150.0, true) == "far", "past the gun's reach: far, even over an enemy")
	gun.falloff_start = 10.0
	gun.falloff_end = 30.0
	t.check(CrosshairScript.state_for(gun, 40.0, true) == "far", "past where the damage has fallen off: far")
	gun.ammo_in_mag = 0
	t.check(CrosshairScript.state_for(gun, 5.0, true) == "empty", "an empty magazine shows empty")
	gun.free()


static func _in_raid(t: Node) -> void:
	print("Crosshair: in a raid")
	var raid := Raid.new()
	t.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 71, ["rifle_carbine"])
	await t.frames(3)
	var p := raid.player
	p.protected_left = 0.0
	var controller := PlayerController.new()
	controller.setup(p)
	raid.add_child(controller)
	var hud := Hud.new()
	hud.setup(raid, controller)
	raid.add_child(hud)
	await t.frames(5)
	var mark: Variant = hud.crosshair
	p._draw_weapon(0)
	await t.frames(2)
	var gun := p.get_active_weapon() as Gun
	t.check(mark != null and mark.visible and gun != null, "a raid shows the aiming mark over a gun in hand")
	if gun == null:
		await t._end_raid(raid)
		return
	controller.yaw = t.open_heading(p, 75.0)
	controller.pitch = 0.3
	await t.frames(6)
	t.check(mark.state in ["ready", "far"], "a loaded gun shows its ticks (%s)" % mark.state)
	# Headless the window is tiny; give it a real height so pixels mean something.
	var window := t.get_tree().root
	var was := window.size
	window.size = Vector2i(1280, 720)
	await t.frames(6)
	var still: float = mark.gap
	for i in 6:
		gun._bloom = gun.max_bloom
		await t.frames(1)
	window.size = was
	t.check(mark.gap > still + 1.0, "spraying opens the ticks (%.1f to %.1f px)" % [still, mark.gap])
	gun._bloom = 0.0
	gun.ammo_in_mag = 0
	await t.frames(2)
	t.check(mark.state == "empty", "an empty magazine dims the ticks red (%s)" % mark.state)
	gun.start_reload()
	await t.frames(2)
	t.check(mark.state == "reload", "reloading swaps the ticks for a filling ring (%s)" % mark.state)
	await t.frames(int(gun.reload_time * 60.0) + 10)
	controller.pitch = 0.0

	# An enemy under the mark turns it red.
	var bot: Actor = raid.bots[0]
	var ahead := Basis(Vector3.UP, controller.yaw) * Vector3(0, 0, -10)
	bot.global_position = p.global_position + ahead + Vector3(0, 0.2, 0)
	bot.velocity = Vector3.ZERO
	bot.set_physics_process(false)
	await t.frames(3)
	var to_bot := bot.global_position + Vector3(0, 1.0, 0) - p.get_eye_position()
	controller.yaw = atan2(-to_bot.x, -to_bot.z)
	controller.pitch = asin(to_bot.normalized().y)
	await t.frames(12)
	t.check(mark.probe_hostile and mark.state == "hostile",
			"an enemy under the mark turns it red (%s, %.1f m)" % [mark.state, mark.probe_distance])

	hud._on_hit_confirmed(bot, DamageInfo.make(5.0, p, "bullet", bot.global_position), true)
	t.check(hud._hit_marker.kind == "kill", "a kill flashes the kill mark")
	hud.show_aim(false)
	t.check(not mark.visible, "hidden for the phone's mirror")
	await t._end_raid(raid)
