extends RefCounted
## The katana and the hookblade (Caleb's call): the Arc Blade, the katana
## swung in both hands, is a two-hander in play as well as on screen; the
## Marsh Hookblade stays a one-hander with a model of its own, a sword whose
## point curls into a hook, not the katana.


static func run(t: Node) -> void:
	t.check(MeleeWeapon.is_two_handed_id("blade_arc") and not ItemDB.has_tag("blade_arc", "one_handed"),
			"the katana (Arc Blade) is held in both hands in play")
	t.check(not MeleeWeapon.is_two_handed_id("blade_hook") and ItemDB.has_tag("blade_hook", "one_handed"),
			"the hookblade stays one-handed")
	var hook_row: Array = []
	var katana_row: Array = []
	for row: Array in Look.MELEE_MODELS:
		if hook_row.is_empty() and ItemDB.has_tag("blade_hook", row[0]):
			hook_row = row
		if katana_row.is_empty() and ItemDB.has_tag("blade_arc", row[0]):
			katana_row = row
	t.check(not hook_row.is_empty() and hook_row[1] != "Katana.glb" and hook_row[5] == "upright",
			"the hookblade has its own model, held like a sword, not the katana (%s)" % [hook_row])
	t.check(not katana_row.is_empty() and katana_row[1] == "Katana.glb", "the Arc Blade keeps the katana")
