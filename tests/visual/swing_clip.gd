extends RefCounted
## `--swing-clip-only`, a mode `visual_check.gd` finds by itself: measures
## where the arms pass through the armor (and through the body) in every
## swing of every melee weapon, frame by frame, in the real game.
##
##   godot --path . res://tests/visual_check.tscn -- <dir> --swing-clip-only \
##       [weapons=a,b] [frames=frame_trooper,frame_bulwark] [moves=light_right,heavy] [shots] [noclear]
##
## `noclear` leaves the arms to go through (`WeaponArm.keep_clear`), to
## compare. Each frame the body is skinned on the processor from its pose,
## as the skeleton's modifiers left it (the arms' reach holds only until
## the frame ends, so it is kept from `skeleton_updated`) (as
## `tools/armor_fit/clip_check.gd` does in a stance) and the edges of the
## arms (the skin of the shoulders down, and the pads and bracers on them)
## are tested against the trunk's armor (chest, belt, thigh plates) and the
## skin of the trunk, both ways. A crossing deeper than `SLACK` counts.
## Writes `swing_clip.json` (every weapon, armor and move: the frames that
## clip, the worst frame and what met there) and prints a table; `shots`
## also saves the worst frame of each clipping move close up.

const CELL := 0.06
const SLACK := 0.004
const ARM_BONES := ["Shoulder", "UpperArm", "LowerArm", "Wrist", "Thumb", "Index", "Middle", "Ring", "Pinky"]
const TRUNK_BONES := ["Chest", "Torso", "Abdomen", "Hips", "Neck"]
## Each mesh's arrays, read once (`surface_get_arrays` copies them).
static var _arrays := {}
const MOVES := ["ready", "light_right", "light_left", "overhead", "heavy", "guard", "kick", "run"]
const ARMORS := ["frame_runner", "frame_trooper", "frame_bulwark"]


static func shoot(v: Node, out_dir: String, args: PackedStringArray) -> void:
	var weapons: Array = []
	for id: String in ItemDB.all_ids():
		if ItemDB.has_tag(id, "melee") and ItemDB.has_tag(id, "weapon"):
			weapons.append(id)
	var armors: Array = ARMORS.duplicate()
	var moves: Array = MOVES.duplicate()
	var shots := args.has("shots")
	for arg in args:
		if arg.begins_with("weapons="):
			weapons = Array(arg.substr(8).split(","))
		elif arg.begins_with("frames="):
			armors = Array(arg.substr(7).split(","))
		elif arg.begins_with("moves="):
			moves = Array(arg.substr(6).split(","))
	DirAccess.make_dir_recursive_absolute(out_dir)
	# Nothing is drawn while measuring (the poses run without it); a shot
	# turns drawing back on for its frame.
	RenderingServer.render_loop_enabled = false
	var report := {}
	var cam := Camera3D.new()
	for armor: String in armors:
		for weapon: String in weapons:
			var raid := Raid.new()
			v.add_child(raid)
			raid.start(Worlds.get_world("ashfront"), 42, [weapon, armor])
			for bot in raid.bots:
				bot.get_node("Brain").set_physics_process(false)
				bot.global_position += Vector3(0, -200, 0)
			raid.zone_rules = false
			var p := raid.player
			p.weapons_locked = false
			var blade: MeleeWeapon = null
			for i in p.weapons.size():
				if p.weapons[i] is MeleeWeapon:
					blade = p.weapons[i]
					p._draw_weapon(i)
			await v._settle(40)
			var floor := StaticBody3D.new()
			var shape := CollisionShape3D.new()
			shape.shape = BoxShape3D.new()
			(shape.shape as BoxShape3D).size = Vector3(400, 1, 400)
			floor.add_child(shape)
			raid.add_child(floor)
			floor.global_position = p.global_position + Vector3(0, 300, 0)
			p.global_position = floor.global_position + Vector3(0, 0.6, 0)
			p.velocity = Vector3.ZERO
			await v._settle(30)
			if cam.get_parent():
				cam.get_parent().remove_child(cam)
			raid.add_child(cam)
			cam.current = true
			cam.fov = 35.0
			var skin := p.get_node_or_null("Skin")
			if skin == null or blade == null:
				print("swing clip: no skin or blade for ", weapon)
				raid.queue_free()
				await v._settle(2)
				continue
			# The arms' reach and the hands' hold are worked out each frame by
			# the skeleton's modifiers, and their pose holds only until the
			# frame ends: it is kept as the skeleton finishes (as the worn
			# pieces on it are placed) for the skin to be measured in.
			if args.has("noclear") and skin.arm:
				skin.arm.keep_clear = false
			var sk: Skeleton3D = skin._skeleton
			var posed := {}
			sk.set_meta("posed", posed)
			sk.skeleton_updated.connect(func() -> void:
				for bi in sk.get_bone_count():
					posed[bi] = sk.global_transform * sk.get_bone_global_pose(bi))
			var start := p.global_transform
			for move: String in moves:
				p.global_transform = start
				p.velocity = Vector3.ZERO
				p.cmd.move = Vector2.ZERO
				p.cmd.sprint = false
				p.cmd.secondary = false
				blade.light_stamina = 0.0
				blade.heavy_stamina = 0.0
				p.stamina = p.max_stamina
				await v._settle(40)
				match move:
					"run":
						p.cmd.move = Vector2(0, 1)
						p.cmd.sprint = true
					"kick":
						p.cmd.kick_pressed = true
					"guard":
						p.cmd.secondary = true
					"light_right", "light_left", "overhead", "heavy":
						blade.combo_step = {"light_right": 0, "light_left": 1, "overhead": 2, "heavy": 0}[move]
						blade._combo_timer = 1.0 if blade.combo_step > 0 else 0.0
						if move == "heavy":
							p.cmd.tertiary_pressed = true
						else:
							p.cmd.primary_pressed = true
				var worst := {"hits": 0}
				var clipped := 0
				var measured := 0
				for i in 23:
					# Near and in view, so the body is posed every frame
					# (`ActorSkin.detail_step`).
					var chest := p.global_position + Vector3.UP * 1.2
					cam.look_at_from_position(chest - p.global_basis.z * 3.0, chest)
					for k in 4:
						await v.get_tree().process_frame
						p.cmd.primary_pressed = false
						p.cmd.tertiary_pressed = false
						p.cmd.kick_pressed = false
					if move == "run":
						p.global_transform.origin = start.origin
					var found := _measure(skin, p)
					measured += 1
					if found["hits"] > 0:
						clipped += 1
					if found["hits"] > worst["hits"]:
						worst = found
						worst["frame"] = i
						if shots:
							worst["image"] = await _shot(v, cam, p, found["at"])
				p.cmd.secondary = false
				p.cmd.move = Vector2.ZERO
				p.cmd.sprint = false
				var key := "%s|%s|%s" % [armor, weapon, move]
				var entry := {"clipped_frames": clipped, "of": measured, "worst_hits": worst["hits"],
						"worst_frame": worst.get("frame", -1), "worst_pairs": worst.get("pairs", {})}
				report[key] = entry
				print("swing clip  %-14s %-16s %-12s %2d/%d frames  worst %3d  %s" % [armor, weapon, move, clipped, measured,
						worst["hits"], _top(worst.get("pairs", {}))])
				if shots and worst.has("image"):
					(worst["image"] as Image).save_png(out_dir.path_join("swing_clip_%s_%s_%s.png" % [armor, weapon, move]))
			raid.remove_child(cam)
			raid.queue_free()
			await v._settle(3)
	var f := FileAccess.open(out_dir.path_join("swing_clip.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "\t"))
	f.close()
	var total := 0
	for key: String in report:
		total += int(report[key]["clipped_frames"])
	print("swing clip: ", total, " clipping frames over ", report.size(), " moves")


## "arm x trunk" for a meeting that shows, "" for one that never does: the
## skin of the shoulder and upper arm folds into the chest's at the armpit
## (where the skinning blends them, under the suit and the pad), and the
## shoulder's skin runs under the chest plate's collar by design.
static func _pair(arm: String, trunk: String) -> String:
	var hidden_arm := arm.begins_with("skin:Shoulder") or arm.begins_with("skin:UpperArm")
	if hidden_arm and trunk.begins_with("skin:"):
		return ""
	if arm.begins_with("skin:Shoulder"):
		return ""
	return "%s x %s" % [arm, trunk]


## The most common meetings, "arm part x trunk part (count)".
static func _top(pairs: Dictionary) -> String:
	var keys := pairs.keys()
	keys.sort_custom(func(a, b): return pairs[a] > pairs[b])
	var out := PackedStringArray()
	for k in keys.slice(0, 3):
		out.append("%s (%d)" % [k, pairs[k]])
	return ", ".join(out)


## A close shot of the body from the front quarter, centred on `at`.
static func _shot(v: Node, cam: Camera3D, p: Actor, at: Vector3) -> Image:
	var off := (p.global_basis.x - p.global_basis.z).normalized()
	cam.look_at_from_position(at + off * 1.6 + Vector3.UP * 0.2, at)
	RenderingServer.render_loop_enabled = true
	await v.get_tree().process_frame
	await RenderingServer.frame_post_draw
	RenderingServer.render_loop_enabled = false
	var img := v.get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	return img


## This frame's crossings: {"hits", "pairs" {"arm x trunk": count}, "at"}.
static func _measure(skin: Node, p: Actor) -> Dictionary:
	var sk: Skeleton3D = skin._skeleton
	var arms := [PackedVector3Array(), PackedStringArray()]
	var trunk := [PackedVector3Array(), PackedStringArray()]
	_skin_tris(skin, sk, arms, trunk)
	for part: Variant in skin._frame_parts:
		if not is_instance_valid(part):
			continue
		var node := part as Node3D
		var bone := String((node as BoneAttachment3D).bone_name) if node is BoneAttachment3D else ""
		var on_arm := false
		for b: String in ARM_BONES:
			on_arm = on_arm or bone.begins_with(b)
		_mesh_tris(node, arms if on_arm else trunk, "armor:" + (bone if bone != "" else String(node.name)))
	var grid := _grid(trunk[0])
	var pairs := {}
	var hits := 0
	var at := Vector3.ZERO
	for found: Array in _cross(arms[0], trunk[0], grid):
		var k := _pair(arms[1][found[1]], trunk[1][found[2]])
		if k != "":
			pairs[k] = pairs.get(k, 0) + 1
			hits += 1
			at += found[0]
	var back := _grid(arms[0])
	for found: Array in _cross(trunk[0], arms[0], back):
		var k := _pair(arms[1][found[2]], trunk[1][found[1]])
		if k != "":
			pairs[k] = pairs.get(k, 0) + 1
			hits += 1
			at += found[0]
	return {"hits": hits, "pairs": pairs, "at": at / hits if hits > 0 else p.global_position + Vector3.UP * 1.2}


## The body's skin, posed as it is now, in the world: arm triangles into
## `arms`, trunk triangles into `trunk`, each named by the bone that moves
## its first corner most.
static func _skin_tris(skin: Node, sk: Skeleton3D, arms: Array, trunk: Array) -> void:
	# Packed arrays are values: filled here and handed back at the end.
	var arm_tris: PackedVector3Array = arms[0]
	var arm_names: PackedStringArray = arms[1]
	var trunk_tris: PackedVector3Array = trunk[0]
	var trunk_names: PackedStringArray = trunk[1]
	var pose: Dictionary = sk.get_meta("posed", {})
	if pose.size() < sk.get_bone_count():
		for bi in sk.get_bone_count():
			pose[bi] = sk.global_transform * sk.get_bone_global_pose(bi)
	for node in skin.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		# The body's own skin (not its shadow copy, hair or head).
		if mi.skin == null or mi.mesh == null or not mi.is_visible_in_tree() or not String(mi.name) in ["PartBody", "PartLegs"]:
			continue
		var binds := {}
		for i in mi.skin.get_bind_count():
			var bn := mi.skin.get_bind_name(i)
			var bone := sk.find_bone(bn) if bn != "" else mi.skin.get_bind_bone(i)
			if bone < 0:
				continue
			binds[i] = [(pose[bone] as Transform3D) * mi.skin.get_bind_pose(i), sk.get_bone_name(bone)]
		for s in mi.mesh.get_surface_count():
			var arr := _surface(mi.mesh, s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			if arr[Mesh.ARRAY_BONES] == null:
				continue
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			var index := PackedInt32Array(arr[Mesh.ARRAY_INDEX]) if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var per := bones.size() / maxi(1, verts.size())
			var at := PackedVector3Array()
			var owner := PackedStringArray()
			at.resize(verts.size())
			owner.resize(verts.size())
			for k in verts.size():
				var q := Vector3.ZERO
				var bw := 0.0
				for j in per:
					var w := weights[k * per + j]
					if w > 0.0 and binds.has(bones[k * per + j]):
						var bind: Array = binds[bones[k * per + j]]
						q += w * ((bind[0] as Transform3D) * verts[k])
						if w > bw:
							bw = w
							owner[k] = bind[1]
				at[k] = q
			if index.is_empty():
				index = PackedInt32Array(range(verts.size()))
			for i in range(0, index.size(), 3):
				var name := owner[index[i]]
				var side := 0
				for b: String in ARM_BONES:
					if name.begins_with(b):
						side = 1
				if side == 0:
					for b: String in TRUNK_BONES:
						if name.begins_with(b):
							side = 2
				if side == 1:
					for e in 3:
						arm_tris.append(at[index[i + e]])
					arm_names.append("skin:" + name)
				elif side == 2:
					for e in 3:
						trunk_tris.append(at[index[i + e]])
					trunk_names.append("skin:" + name)
	arms[0] = arm_tris
	arms[1] = arm_names
	trunk[0] = trunk_tris
	trunk[1] = trunk_names


static func _mesh_tris(root: Node3D, into: Array, label: String) -> void:
	var tris: PackedVector3Array = into[0]
	var names: PackedStringArray = into[1]
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var xf := mi.global_transform
		for s in mi.mesh.get_surface_count():
			var arr := _surface(mi.mesh, s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var index := PackedInt32Array(arr[Mesh.ARRAY_INDEX]) if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if index.is_empty():
				index = PackedInt32Array(range(verts.size()))
			for i in range(0, index.size(), 3):
				for e in 3:
					tris.append(xf * verts[index[i + e]])
				names.append(label)
	into[0] = tris
	into[1] = names


static func _surface(mesh: Mesh, s: int) -> Array:
	var key := "%d:%d" % [mesh.get_instance_id(), s]
	if not _arrays.has(key):
		var arr := mesh.surface_get_arrays(s)
		if arr[Mesh.ARRAY_INDEX] == null or (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).is_empty():
			arr[Mesh.ARRAY_INDEX] = PackedInt32Array(range((arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()))
		_arrays[key] = arr
	return _arrays[key]


static func _grid(tris: PackedVector3Array) -> Dictionary:
	var g := {}
	for t in range(0, tris.size(), 3):
		var lo := tris[t].min(tris[t + 1]).min(tris[t + 2])
		var hi := tris[t].max(tris[t + 1]).max(tris[t + 2])
		for x in range(floori(lo.x / CELL), floori(hi.x / CELL) + 1):
			for y in range(floori(lo.y / CELL), floori(hi.y / CELL) + 1):
				for z in range(floori(lo.z / CELL), floori(hi.z / CELL) + 1):
					var key := Vector3i(x, y, z)
					if not g.has(key):
						g[key] = PackedInt32Array()
					g[key].append(t)
	return g


## Edges of `a` through triangles of `b`: [point, a's triangle, b's triangle].
static func _cross(a: PackedVector3Array, b: PackedVector3Array, grid: Dictionary) -> Array:
	var hits := []
	for t in range(0, a.size(), 3):
		for e in 3:
			var p := a[t + e]
			var q := a[t + (e + 1) % 3]
			var lo := p.min(q)
			var hi := p.max(q)
			var seen := {}
			for x in range(floori(lo.x / CELL), floori(hi.x / CELL) + 1):
				for y in range(floori(lo.y / CELL), floori(hi.y / CELL) + 1):
					for z in range(floori(lo.z / CELL), floori(hi.z / CELL) + 1):
						var key := Vector3i(x, y, z)
						if not grid.has(key):
							continue
						for u: int in grid[key]:
							if seen.has(u):
								continue
							seen[u] = true
							var hit = Geometry3D.segment_intersects_triangle(p, q, b[u], b[u + 1], b[u + 2])
							if hit == null:
								continue
							var n := (b[u + 1] - b[u]).cross(b[u + 2] - b[u])
							if n.length() < 1e-9:
								continue
							n = n.normalized()
							if absf((p - b[u]).dot(n)) > SLACK and absf((q - b[u]).dot(n)) > SLACK:
								hits.append([hit, t / 3, u / 3])
	return hits
