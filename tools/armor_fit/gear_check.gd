extends Node
## Finds where worn gear cuts into the armor or the body: a real body in a
## world wearing each armor frame (and none) with each flight rig, weapons
## put away where they are worn (slung on the back or a rig's rails, a
## sidearm and a blade on the hips), a backpack and a helmet clipped to the
## belt, all as `ActorSkin` hangs them. Every piece of gear is tested against
## the armor, the body and the other gear (`clip_check.gd`'s edge against
## triangle test). Prints each clash ("m frame_bulwark jetpack_mk1 kit 1:
## rig/RigBack x armor/Frame, crossings, where, actor frame in metres") and
## exits 1 if any. A hand or the weapon in it meeting gear is the stance's,
## counted apart and listed with `--arms`. Needs a display or xvfb:
##
##   godot --path . res://tools/armor_fit/gear_check.tscn [-- --frames frame_bulwark --rigs jetpack_mk1 --kits 0 --builds m --arms]
##
## The armor against itself and the body is `clip_check.tscn`'s.

const ClipCheck := preload("res://tools/armor_fit/clip_check.gd")
const FRAMES := ["", "plate_light", "frame_runner", "frame_trooper", "frame_thermal", "frame_bulwark"]
const RIGS := ["", "jetpack_mk1", "wings_glide", "boots_thruster"]
## What is carried: long gun, melee, sidearm, then a backpack and a helmet,
## the helmet taken off and clipped to the belt.
const KITS := [
	["rifle_carbine", "blade_scrap", "pistol_service", "pack_mule", "helm_warden"],
	["dmr_longshot", "hammer_breaker", "pistol_hand_cannon", "pack_rucksack"],
	["shotgun_breacher", "spear_lancer", "pistol_machine", "pack_hauler", "helm_ember"],
	["smg_stinger", "axe_splitter", "pistol_service", "helm_spotter"],
]

var show_arms := false
var arm_contacts := 0
var _clip: Node


func _ready() -> void:
	var frames: Array = FRAMES
	var rigs: Array = RIGS
	var kits: Array = range(KITS.size())
	var builds: Array = ["m", "f"]
	var args := OS.get_cmdline_user_args()
	for i in args.size() - 1:
		var list := Array(args[i + 1].split(","))
		match args[i]:
			"--frames":
				frames = list.map(func(s: String) -> String: return "" if s == "none" else s)
			"--rigs":
				rigs = list.map(func(s: String) -> String: return "" if s == "none" else s)
			"--kits":
				kits = list.map(func(s: String) -> int: return int(s))
			"--builds":
				builds = list
	show_arms = "--arms" in args
	_clip = ClipCheck.new()
	var raid := Raid.new()
	add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 42, [Loadout.BARE])
	await get_tree().process_frame
	await get_tree().process_frame
	var bodies := _bodies(raid, builds)
	# Standing on the ground, then held still where they stand.
	for i in 90:
		await get_tree().physics_frame
	for build: String in bodies:
		var still: Actor = bodies[build]
		still.set_physics_process(false)
		still.velocity = Vector3.ZERO
	var cam := Camera3D.new()
	raid.add_child(cam)
	cam.current = true
	var total := 0
	var missing := 0
	for build: String in builds:
		if not bodies.has(build):
			# Headless, `Look` dresses no body, so there is nothing to test:
			# fail rather than report an empty 0.
			push_error("gear check: no body of build " + build + " (needs a display or xvfb)")
			missing += 1
			continue
		var actor: Actor = bodies[build]
		cam.global_position = actor.global_position + actor.global_basis.z * -3.0 + Vector3(0, 1.2, 0)
		cam.look_at(actor.global_position + Vector3(0, 1.0, 0))
		for frame: String in frames:
			for rig: String in rigs:
				for k: int in kits:
					var kit: Array = KITS[k].duplicate()
					if frame != "":
						kit.append(frame)
					if rig != "":
						kit.append(rig)
					total += await _check(actor, kit, "%s %s %s kit %d" % [build, frame if frame != "" else "none",
							rig if rig != "" else "norig", k])
	print("gear check: ", total, " clashes; hands and held weapons against gear: ", arm_contacts, "" if show_arms else " (--arms lists them)")
	get_tree().quit(1 if total > 0 or missing > 0 else 0)


## One standing body of each build, everyone else out of the way.
func _bodies(raid: Raid, builds: Array) -> Dictionary:
	var out := {}
	var all: Array = [raid.player]
	all.append_array(raid.bots)
	for a: Variant in all:
		if not is_instance_valid(a):
			continue
		var actor := a as Actor
		var brain := actor.get_node_or_null("Brain")
		if brain:
			brain.set_physics_process(false)
		var skin: Node = actor.get_node_or_null("Skin")
		var build: String = str(skin._appearance.get("build", "")) if skin else ""
		if skin and build in builds and not out.has(build) and skin._def.get("frame", "") == "" \
				and (actor == raid.player or skin._def.has("people")):
			out[build] = actor
			# Nothing (a shell landing near) ends it partway through.
			actor.protected_left = 1.0e9
			actor.cmd.yaw = actor.rotation.y
			actor.cmd.pitch = 0.0
			actor.cmd.aim_dir = -actor.global_basis.z
		else:
			actor.global_position += Vector3(0, -300, 0)
			actor.set_physics_process(false)
	return out


func _check(actor: Actor, kit: Array, label: String) -> int:
	Loadout.refit(actor, kit)
	Loadout.arrive_unarmed(actor)
	actor.helmet_stow = 1.0 if actor.visor.enabled else 0.0
	var skin: Node = actor.get_node("Skin")
	for i in 40:
		await get_tree().process_frame
	var groups := _groups(actor, skin)
	var boxes := {}
	for name: String in groups:
		boxes[name] = _clip._bounds(groups[name][0])
	var clashes := 0
	var names: Array = groups.keys()
	for i in names.size():
		for j in range(i + 1, names.size()):
			var a: String = names[i]
			var b: String = names[j]
			# The armor against itself and the body is clip_check's.
			if _kind(a) in ["armor", "skin"] and _kind(b) in ["armor", "skin"]:
				continue
			if not (boxes[a] as AABB).intersects(boxes[b]):
				continue
			var box: AABB = (boxes[a] as AABB).intersection(boxes[b]).grow(0.01)
			var near_a: Array = _clip._near(groups[a], box)
			var near_b: Array = _clip._near(groups[b], box)
			if near_a[0].is_empty() or near_b[0].is_empty():
				continue
			var found := {}
			for h: Array in _clip._cross(near_a[0], near_b[0], _clip._grid(near_b[0])):
				_clip._add(found, "%s/%s x %s/%s" % [a, near_a[1][h[1]], b, near_b[1][h[2]]], h[0])
			for h: Array in _clip._cross(near_b[0], near_a[0], _clip._grid(near_a[0])):
				_clip._add(found, "%s/%s x %s/%s" % [a, near_a[1][h[2]], b, near_b[1][h[1]]], h[0])
			for pair: String in found:
				var f: Array = found[pair]
				if "skin:held/" in pair or "armor:UpperArm" in pair or "armor:LowerArm" in pair or _clip._arm(pair):
					arm_contacts += 1
					if not show_arms:
						continue
				else:
					clashes += 1
				print("%s: %s, %d crossings, %s to %s" % [label, pair, f[0], _clip._v(f[1]), _clip._v(f[2])])
	return clashes


func _kind(group: String) -> String:
	return group.get_slice(":", 0)


## The triangles of everything worn, in the actor's frame, by group:
## "skin" (the posed body, each triangle named by its bone), "armor:<piece>",
## "rig:<part>", "stowed:<weapon>", "pack", "helmet"; an armor piece on a
## limb by its bone ("armor:LowerArm.L").
func _groups(actor: Actor, skin: Node) -> Dictionary:
	var to_actor := actor.global_transform.affine_inverse()
	var out := {}
	var sk: Skeleton3D = skin._skeleton
	out["skin"] = _skin(sk, to_actor)
	for part: Variant in skin._frame_parts:
		if is_instance_valid(part):
			# A limb piece by the bone it rides (an arm's is the stance's).
			var attach := part as BoneAttachment3D
			var piece := (attach.bone_name + ":" if attach != null else "") + str((part as Node).name)
			out["armor:" + piece] = _meshes(part, to_actor)
	for part: Variant in skin._rig_holders:
		if is_instance_valid(part):
			out["rig:" + str((part as Node).name)] = _meshes(part, to_actor)
	for weapon: Variant in skin._stowed:
		var root: Variant = skin._stowed[weapon]
		if is_instance_valid(weapon) and root != null and is_instance_valid(root):
			out["stowed:" + str((weapon as Weapon).item_id)] = _meshes(root, to_actor)
	if skin._pack_part != null and is_instance_valid(skin._pack_part):
		out["pack"] = _meshes(skin._pack_part, to_actor)
	if skin._helmet_clip != null and is_instance_valid(skin._helmet_clip):
		out["helmet"] = _meshes(skin._helmet_clip, to_actor)
	var held := actor.get_active_weapon()
	if held != null and held.visual != null:
		out["skin:held"] = _meshes(held.visual, to_actor)
	for key: String in out.keys():
		if (out[key][0] as PackedVector3Array).is_empty():
			out.erase(key)
	return out


func _meshes(root: Node, to_actor: Transform3D) -> Array:
	var tris := PackedVector3Array()
	var parts := PackedStringArray()
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or not mi.is_visible_in_tree() or mi.skin != null:
			continue
		var xf := to_actor * mi.global_transform
		var part := str(mi.name)
		for s in mi.mesh.get_surface_count():
			if mi.mesh is ArrayMesh and (mi.mesh as ArrayMesh).surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arr := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var index := PackedInt32Array(arr[Mesh.ARRAY_INDEX]) if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if index.is_empty():
				index = PackedInt32Array(range(verts.size()))
			for i in index.size():
				tris.append(xf * verts[index[i]])
			for i in index.size() / 3:
				parts.append(part)
	return [tris, parts]


## The body as posed now, each triangle named by the bone that moves its
## first corner most.
func _skin(sk: Skeleton3D, to_actor: Transform3D) -> Array:
	var pose := {}
	for bi in sk.get_bone_count():
		pose[bi] = sk.get_bone_global_pose(bi)
	var tris := PackedVector3Array()
	var parts := PackedStringArray()
	for mi: MeshInstance3D in sk.find_children("*", "MeshInstance3D", true, false):
		if mi.skin == null or mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var at_sk := to_actor * sk.global_transform
		var binds := {}
		for i in mi.skin.get_bind_count():
			var bn := mi.skin.get_bind_name(i)
			var bone := sk.find_bone(bn) if bn != "" else mi.skin.get_bind_bone(i)
			binds[i] = [(pose[bone] as Transform3D) * mi.skin.get_bind_pose(i), sk.get_bone_name(bone)]
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
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
				var p := Vector3.ZERO
				var bw := 0.0
				for j in per:
					var w := weights[k * per + j]
					if w > 0.0 and binds.has(bones[k * per + j]):
						var bind: Array = binds[bones[k * per + j]]
						p += w * ((bind[0] as Transform3D) * verts[k])
						if w > bw:
							bw = w
							owner[k] = bind[1]
				at[k] = at_sk * p
			if index.is_empty():
				index = PackedInt32Array(range(verts.size()))
			for i in index.size():
				tris.append(at[index[i]])
			for i in range(0, index.size(), 3):
				parts.append(owner[index[i]])
	return [tris, parts]
