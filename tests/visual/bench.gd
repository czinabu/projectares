extends RefCounted
## `--bench-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --bench-only` shoots the gunsmith's workshop off the
## armory and the bench in use: at rest, turning through the guns, and
## turning through an attachment slot, as the player sees it.

const BaseUpgrades := preload("res://core/base/base_upgrades.gd")


## The gunsmith's workshop off the armory, and the bench in use.
static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	var every: Array = ["rifle_carbine", "smg_stinger", "dmr_longshot"]
	for id: String in ItemDB.all_ids():
		if ItemDB.has_tag(id, "attachment"):
			every.append(id)
	var loadout := {"primary": "rifle_carbine", "optic": "optic_reflex", "grip": "grip_vertical"}
	for full: bool in [true, false]:
		var base := HomeBase.new()
		base.show_gear(every, loadout, BaseUpgrades.full() if full else [])
		v.add_child(base)
		var camera := Camera3D.new()
		camera.fov = 60.0
		base.add_child(camera)
		camera.make_current()
		base.player.global_position = Vector3(0, 0.1, 6)
		await v._settle(20)
		var tag := "armory" if full else "bunker"
		# From the hub, through the way into the workshop.
		var shop := base.room_transform("workshop")
		camera.look_at_from_position(shop * Vector3(0, 2.4, 5.0), shop * Vector3(0, 1.4, -6.0))
		await v._settle(4)
		await v._shot(out_dir.path_join("bench_%s_way_in.png" % tag))
		# Inside the workshop, at the bench.
		camera.look_at_from_position(shop * Vector3(2.5, 2.2, -2.5), base.bench_transform() * Vector3(0, 1.3, 0))
		await v._settle(4)
		await v._shot(out_dir.path_join("bench_%s_workshop.png" % tag))
		if full:
			var view: Node3D = load("res://core/ui/bench_view.gd").new()
			view.base = base
			var at := base.bench_transform()
			camera.global_transform = Transform3D(Basis.looking_at(at * view.look_at_point - at * view.eye, Vector3.UP), at * view.eye)
			camera.fov = view.fov
			view.free()
			await v._settle(4)
			await v._shot(out_dir.path_join("bench_rest.png"))
			base.use_bench()
			base.bench_scroll(1)
			await v._settle(6)
			await v._shot(out_dir.path_join("bench_pick_gun.png"))
			base.bench_select()
			base.show_gear(every, {"primary": "smg_stinger", "optic": "optic_reflex", "grip": "grip_vertical"})
			base.bench_scroll(1)
			base.bench_select()
			base.bench_scroll(1)
			base.bench_scroll(1)
			await v._settle(6)
			await v._shot(out_dir.path_join("bench_pick_muzzle.png"))
		base.queue_free()
		await v._settle(2)
