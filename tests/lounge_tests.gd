extends RefCounted
## The `lounge` checks: the seventh room, its doorway in every hub shape, its
## three styles whole and small, and buying it. The test runner finds this
## file by itself and calls `run(t)`.

const BasePlan := preload("res://core/base/base_plan.gd")
const BaseUpgrades := preload("res://core/base/base_upgrades.gd")


static func run(t: Node) -> void:
	_rules(t)
	await _styles(t)
	await _walk_in(t)


## The plan and the upgrade: a seventh socket holding the lounge, the Den
## free, the Bar and the Quarters unlocked, the whole room bought.
static func _rules(t: Node) -> void:
	print("Lounge rules")
	t.check(BasePlan.SOCKETS.size() == 7 and "F1" in BasePlan.SOCKETS and BasePlan.DEFAULT["F1"] == "lounge"
			and BasePlan.ROOMS.has("lounge") and BasePlan.ROOMS["lounge"]["opens"] == "lounge",
			"the lounge is the seventh room, in its own socket, and opened by its upgrade")
	t.check(BasePlan.styles("lounge").size() == 3 and BasePlan.default_style("lounge") == "den"
			and BasePlan.unlock_for("style:lounge", "den") == "" and BasePlan.unlock_for("style:lounge", "bar") == "style_lounge_bar",
			"the lounge has three styles and the Den is free")
	t.check(not BasePlan.change(BasePlan.DEFAULT, [], "style:lounge", "bar").ok
			and BasePlan.change(BasePlan.DEFAULT, ["style_lounge_bar"], "style:lounge", "bar").ok
			and BasePlan.change(BasePlan.DEFAULT, ["style_lounge_quarters"], "style:lounge", "quarters").ok,
			"the Bar and the Quarters are unlocked by their designs")
	t.check(BaseUpgrades.blocked([], "lounge") == "" and BaseUpgrades.is_ready("lounge"), "the lounge upgrade is on sale")
	var owned: Array[String] = []
	var bought := BaseUpgrades.buy(owned, 1000, "lounge")
	t.check(bought.ok and bought.scrip == 1000 - BaseUpgrades.price("lounge") and "lounge" in owned,
			"buying the lounge spends its price and keeps it")
	# The lounge can stand in any socket, and another room in its own.
	var moved := BasePlan.place(BasePlan.DEFAULT, "N1", "lounge")
	t.check(moved["N1"] == "lounge" and moved["F1"] == BasePlan.DEFAULT["N1"], "the lounge swaps sockets like any room")


## Each style builds its pieces inside the room, whole and small, with
## something solid to bump into and nothing poking through the walls.
static func _styles(t: Node) -> void:
	print("Lounge styles")
	var base := HomeBase.new()
	t.add_child(base)
	await t.frames(5)
	for style: String in BasePlan.styles("lounge"):
		for whole: bool in [true, false]:
			var plan := BasePlan.clean(null)
			plan["styles"]["lounge"] = style
			var owned: Array[String] = []
			if whole:
				owned = BaseUpgrades.full()
			base.show_gear(["rifle_carbine"], {"primary": "rifle_carbine"}, owned, plan)
			await t.frames(2)
			var label := "%s, %s" % [style, "whole" if whole else "small"]
			var room: Node3D = base.get_node_or_null("Room_F1")
			var pieces: Node3D = room.get_node_or_null("LoungePieces") if room else null
			t.check(pieces != null and base.room_open("lounge") == whole, "%s: the lounge is furnished" % label)
			if pieces == null:
				continue
			var meshes := pieces.find_children("*", "MeshInstance3D", true, false)
			var solids := room.find_children("*", "StaticBody3D", true, false)
			t.check(meshes.size() >= 3 and solids.size() >= 4, "%s: it has pieces and something solid (%d, %d)"
					% [label, meshes.size(), solids.size()])
			var depth := base.room_depth("lounge")
			var half := base.socket_size.x * 0.5
			var inside := true
			var stray := ""
			for node: Node in meshes:
				var mesh := node as MeshInstance3D
				if mesh.mesh == null:
					continue
				var box: AABB = room.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
				var fits := box.position.x > -half - 0.05 and box.end.x < half + 0.05 \
						and box.position.z > -depth - 0.05 and box.end.z < 0.3 and box.end.y < base.socket_size.y + 0.05
				if not fits and stray == "":
					stray = "%s at %s" % [mesh.name, box]
				inside = inside and fits
			t.check(inside, "%s: every piece stays inside the room %s" % [label, stray])
	base.queue_free()
	await t.frames(2)


## In the hall the lounge opens off the hub; in the spine off the corridor.
## Either way you can walk in, and walk out.
static func _walk_in(t: Node) -> void:
	print("Lounge walk-in")
	var base := HomeBase.new()
	base.show_gear(["rifle_carbine"], {"primary": "rifle_carbine"}, BaseUpgrades.full())
	t.add_child(base)
	await t.frames(10)
	for shape: String in ["hall", "spine"]:
		var plan := BasePlan.clean(null)
		plan["shape"] = shape
		base.show_gear(base.stash, base.loadout, null, plan)
		await t.frames(3)
		var door := base.room_transform("lounge")
		var walker := base.player
		walker.global_position = base.to_global(door * Vector3(0, 0.1, 1.5))
		walker.velocity = Vector3.ZERO
		await t.frames(2)
		var into := -door.basis.z
		walker.cmd.yaw = atan2(-into.x, -into.z)
		walker.cmd.move = Vector2(0, 1)
		await t.frames(60)
		walker.cmd.move = Vector2.ZERO
		await t.frames(2)
		var at := base.to_local(walker.global_position)
		t.check(base.room_at(at) == "lounge" and (door.affine_inverse() * at).z < -1.5,
				"%s: you can walk into the lounge" % shape)
	base.queue_free()
	await t.frames(2)
