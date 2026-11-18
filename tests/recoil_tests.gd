extends RefCounted
## Recoil is a pattern you can learn (DESIGN.md "Recoil"): the kick builds
## through a spray, each gun drifts its own way, a little is left to chance,
## and bots feel it too and pull against it by skill. Called from the test
## runner (`-- --only recoil` runs just these).

const DT := 1.0 / 60.0


static func run(t: Node) -> void:
	print("Recoil: learnable patterns")
	for id: String in ItemDB.all_ids():
		if ItemDB.has_tag(id, "firearm"):
			var pattern: String = ItemDB.item_stats(id).get("recoil_pattern", "climb")
			t.check(pattern in Gun.PATTERNS, "%s has a known recoil pattern (%s)" % [id, pattern])

	var gun := Gun.new()
	gun.recoil_pattern = "climb"
	t.check(gun.recoil_for(1).x < gun.recoil_for(5).x and gun.recoil_for(5).x < gun.recoil_for(9).x,
			"the kick builds through a spray (%.2f, %.2f, %.2f deg)" % [gun.recoil_for(1).x, gun.recoil_for(5).x, gun.recoil_for(9).x])
	t.check(is_equal_approx(gun.recoil_for(9).x, gun.recoil_for(20).x), "and tops out")
	t.check(gun.recoil_for(1).x < gun.recoil_kick_deg, "the first shots are gentler than the gun's kick")
	t.check(gun.recoil_for(6).y == 0.0, "a climb goes straight up")
	gun.recoil_pattern = "kick"
	t.check(is_equal_approx(gun.recoil_for(1).x, gun.recoil_for(8).x), "a kick is the same jump every shot")
	t.check(Gun.pattern_side("climb_right", 2) == 0.0 and Gun.pattern_side("climb_right", 8) > 1.0,
			"climb right starts straight, then pulls right")
	t.check(Gun.pattern_side("climb_left", 8) < -1.0, "climb left pulls left")
	var signs := {}
	for shot in range(3, 12):
		signs[signf(Gun.pattern_side("sway", shot))] = true
	t.check(signs.has(1.0) and signs.has(-1.0), "a sway swings both ways")
	t.check(Gun.pattern_side("sway", 5) == Gun.pattern_side("sway", 5), "a pattern is the same every time")
	gun.free()

	# A spray is counted on the gun, and a rest starts a new one.
	var raid: Raid = await t._new_raid(47, false)
	var shooter: Actor
	for bot in raid.bots:
		if bot.get_active_weapon() is Gun:
			shooter = bot
			break
	t.check(shooter != null, "a bot with a gun")
	if shooter == null:
		await t._end_raid(raid)
		return
	var held := shooter.get_active_weapon() as Gun
	held.ammo_in_mag = held.mag_size
	held._since_fire = 99.0
	held._fire()
	held.tick(held.spray_reset * 0.5)
	held._fire()
	held.tick(held.spray_reset * 0.5)
	held._fire()
	t.check(held.spray_shot == 3, "shots close together are one spray (%d)" % held.spray_shot)
	t.check(held.last_recoil == held.recoil_for(3), "each shot kicks as its place in the spray says")
	held.tick(held.spray_reset + 0.05)
	held._fire()
	t.check(held.spray_shot == 1, "a rest starts a new spray")

	# Bots feel it, and a veteran holds it better than a rookie.
	var brain := shooter.get_node("Brain") as BotBrain
	var climbs := []
	for skill in [0.0, 1.0]:
		brain.skill = skill
		brain._recoil = Vector2.ZERO
		brain._recoil_gun = held
		brain._recoil_seen = held.shots_fired
		for i in 6:
			held._fire()
			held.tick(DT)
			brain._take_recoil(DT)
		climbs.append(brain._recoil.x)
	t.check(climbs[0] > 0.0 and climbs[1] > 0.0, "a bot's aim climbs as it sprays (%.2f, %.2f deg)" % climbs)
	t.check(climbs[0] > climbs[1] * 2.0, "a rookie climbs off far more than a veteran")
	for i in 60:
		brain._take_recoil(DT)
	t.check(brain._recoil.x < climbs[1] * 0.1, "once it stops firing the climb settles")
	await t._end_raid(raid)
