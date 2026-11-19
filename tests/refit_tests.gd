extends RefCounted
## The `refit` checks. The test runner finds this file by itself and calls
## `run(t)`.
##
## `Loadout.refit` dresses an actor in place (the home base's equip, which
## used to build a new actor and stuttered). Whatever it is changed to, it
## must end up wearing exactly what a fresh `Loadout.equip` would.


static func run(t: Node) -> void:
	print("Loadout refit: changing gear in place")
	var kits: Array = [
		["rifle_scrap", "blade_scrap", "pistol_service", "jetpack_mk1", "plate_light"],
		["rifle_carbine", "optic_reflex", "muzzle_compensator", "blade_scrap", "pistol_service", "boots_thruster", "frame_bulwark", "helm_spotter", "chip_blink", "artifact_cloak"],
		["rifle_carbine", "optic_scope", "blade_arc", "jetpack_mk1", "frame_bulwark", "helm_warden", "chip_pulse"],
		["smg_stinger", "pistol_machine", "wings_glide", "frame_trooper"],
		[],
		["dmr_longshot", "optic_longscope", "spear_lancer", "jetpack_mk1", "frame_trooper", "helm_ember", "artifact_rewind"],
	]
	var worn := Actor.new()
	t.add_child(worn)
	var all_match := true
	var why := ""
	var kept_blade: Weapon = null
	for i in kits.size():
		var kit: Array = kits[i]
		Loadout.refit(worn, kit)
		var fresh := Actor.new()
		t.add_child(fresh)
		Loadout.equip(fresh, kit)
		var a: Dictionary = t._refit_summary(worn)
		var b: Dictionary = t._refit_summary(fresh)
		if a != b:
			all_match = false
			why = "kit %d: %s vs %s" % [i, a, b]
		fresh.free()
		if i == 1:
			kept_blade = worn.weapons.filter(func(w: Weapon) -> bool: return w.item_id == "blade_scrap")[0]
		if i == 2:
			t.check(not is_instance_valid(kept_blade) or kept_blade.is_queued_for_deletion(),
					"a weapon taken off is freed")
	t.check(all_match, "after every change the actor wears exactly what a fresh equip would %s" % why)
	Loadout.refit(worn, kits[1])
	var blade: Weapon = worn.weapons.filter(func(w: Weapon) -> bool: return w.item_id == "blade_scrap")[0]
	var gun: Weapon = worn.weapons.filter(func(w: Weapon) -> bool: return w.item_id == "rifle_carbine")[0]
	worn.active_weapon_index = worn.weapons.find(blade)
	var changed: Array = kits[1].duplicate()
	changed.erase("optic_reflex")
	changed.erase("chip_blink")
	changed.append("frame_trooper")
	changed.erase("frame_bulwark")
	Loadout.refit(worn, changed)
	t.check(blade in worn.weapons and worn.get_active_weapon() == blade,
			"a weapon you keep keeps its node, and stays in hand")
	t.check(gun not in worn.weapons and worn.weapons.any(func(w: Weapon) -> bool: return w.item_id == "rifle_carbine"),
			"a primary whose attachments change is built again with them")
	worn.free()
