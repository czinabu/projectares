extends Node
## Builds a person's rig from Quaternius' Universal Base Characters body and
## Universal Animation Library clips (both CC0), in the shape the game
## already reads: bones named as the old modular rig named them (`BONES`),
## the clips the game asks for under the names it asks for (`CLIPS`), and
## every other library clip kept under its own name.
##
##   godot --headless --path . res://tools/human_rig/build_rig.tscn -- \
##       --body <Superhero_Male_FullBody.gltf> --ual <UAL1_Standard.glb>,<UAL2_Standard.glb> \
##       --hair <Hair_Buzzed.gltf>,... --old res://assets/characters/humans/rig_m.glb \
##       --out res://assets/characters/humans/body_m.glb
##
## A clip the library lacks (`CLIPS` names a list of old clips for those) is
## retargeted from the old rig: each bone keeps the turn it makes from its
## rest in world space, with a limb's new rest first bent to the old rest's
## direction (the trunk and collarbones are not bent, `UNBENT`, and a
## collarbone's turn is scaled down by how much longer it is), feet placed
## relative to the old idle stance, fingers given only the old curl about
## their own curl axis, and the hips' travel scaled by leg length. Body textures are shrunk first with
## `shrink_textures.py` (2048 for the body, 1024 for hair).

## Library bone -> the game's name for it.
const BONES := {
	"root": "Root", "pelvis": "Hips", "spine_01": "Abdomen", "spine_02": "Torso", "spine_03": "Chest",
	"neck_01": "Neck", "Head": "Head",
}
const SIDE_BONES := {
	"clavicle": "Shoulder", "upperarm": "UpperArm", "lowerarm": "LowerArm", "hand": "Wrist",
	"thigh": "UpperLeg", "calf": "LowerLeg", "foot": "Foot", "ball": "Toe", "ball_leaf": "ToeEnd",
}
const FINGERS := {"index": "Index", "middle": "Middle", "ring": "Ring", "pinky": "Pinky", "thumb": "Thumb"}

## The game's clip name -> library clip, or ["old", <old clip>] to retarget.
## The stand, run and sword clips stay the old ones for now: the legs'
## stride, the relaxed stand and the melee holds are tuned to them.
## Godot's import drops a clip's "_Loop" ending ("Walk_Loop" is "Walk",
## "Sprint_Loop" "Sprint", "Idle_Loop" "Idle"), so those need no entry.
const CLIPS := {
	"Idle_Neutral": ["old", "Idle_Neutral"], "Run": ["old", "Run"], "Death": "Death01", "Roll": "Roll",
	"Idle_Sword": ["old", "Idle_Sword"], "Sword_Slash": ["old", "Sword_Slash"], "Wave": ["old", "Wave"], "Interact": "Interact",
	"Punch_Left": "Punch_Jab", "Punch_Right": "Punch_Cross",
	"Idle_Gun": ["old", "Idle_Gun"], "Idle_Gun_Pointing": ["old", "Idle_Gun_Pointing"],
	"Idle_Gun_Shoot": ["old", "Idle_Gun_Shoot"], "Gun_Shoot": ["old", "Gun_Shoot"],
	"Run_Shoot": ["old", "Run_Shoot"], "Run_Back": ["old", "Run_Back"], "Run_Left": ["old", "Run_Left"],
	"Run_Right": ["old", "Run_Right"], "Kick_Left": ["old", "Kick_Left"], "Kick_Right": ["old", "Kick_Right"],
	"HitRecieve": "Hit_Chest", "HitRecieve_2": "Hit_Head",
}
const FPS := 30.0
## The library clip whose closed hands give each finger joint the axis it
## curls about (`_curl_axes`).
const CURL_CLIP := "Idle"
## Finger bone -> the axis it curls about, in its rest frame.
var _curl := {}
## Bones whose skin the suit covers with a glove.
const HAND_BONES: Array[String] = ["Wrist", "Thumb", "Index", "Middle", "Ring", "Pinky"]
## Part -> its mesh node, as `Human.SLOT_NODES` names them.
const PART_NODES := {"head": "PartHead", "body": "PartBody", "legs": "PartLegs", "feet": "PartFeet"}


static func game_bone(name: String) -> String:
	if BONES.has(name):
		return BONES[name]
	var side := ""
	var base := name
	if name.ends_with("_l") or name.ends_with("_r"):
		side = ".L" if name.ends_with("_l") else ".R"
		base = name.substr(0, name.length() - 2)
	if side == "":
		return name
	if SIDE_BONES.has(base):
		return SIDE_BONES[base] + side
	for finger: String in FINGERS:
		if base.begins_with(finger + "_"):
			var n := base.substr(finger.length() + 1, 2).to_int()
			return "%s%d%s" % [FINGERS[finger], n, side]
	return name


func _ready() -> void:
	var args := _args()
	if not args.has("body") or not args.has("out"):
		printerr("needs --body and --out")
		get_tree().quit(1)
		return
	var err := build(args)
	get_tree().quit(err)


func _args() -> Dictionary:
	var out := {}
	var raw := OS.get_cmdline_user_args()
	var i := 0
	while i < raw.size():
		if raw[i].begins_with("--"):
			out[raw[i].substr(2)] = raw[i + 1] if i + 1 < raw.size() and not raw[i + 1].begins_with("--") else ""
		i += 1
	return out


static func load_gltf(path: String) -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(path), state) != OK:
		return null
	return doc.generate_scene(state)


static func find_one(node: Node, cls: String) -> Node:
	var found := node.find_children("*", cls, true, false)
	return found[0] if found.size() > 0 else null


func build(args: Dictionary) -> int:
	var body := load_gltf(args["body"])
	if body == null:
		printerr("cannot read ", args["body"])
		return 1
	add_child(body)
	var skeleton := find_one(body, "Skeleton3D") as Skeleton3D
	# Rename bones, and the skins' binds with them.
	for b in skeleton.get_bone_count():
		skeleton.set_bone_name(b, game_bone(skeleton.get_bone_name(b)))
	for mesh: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		var skin := mesh.skin
		if skin:
			skin = skin.duplicate()
			for i in skin.get_bind_count():
				var bind_name := skin.get_bind_name(i)
				if bind_name != "":
					skin.set_bind_name(i, game_bone(bind_name))
			mesh.skin = skin
	# The body cut into the four parts the game dresses (`Human.SLOT_NODES`),
	# each triangle going to the part of the bone that moves it most; the
	# eyes and brows go with the head, and each hairstyle is a mesh of its own.
	var sources: Array = []
	for mesh: MeshInstance3D in skeleton.find_children("*", "MeshInstance3D", true, false):
		sources.append(mesh)
		mesh.get_parent().remove_child(mesh)
	var parts := {}
	for slot: String in PART_NODES:
		parts[slot] = ArrayMesh.new()
	var bind_skin: Skin = null
	for mesh: MeshInstance3D in sources:
		var source := mesh.mesh as ArrayMesh
		for s in source.get_surface_count():
			var arrays := source.surface_get_arrays(s)
			var material := source.surface_get_material(s)
			var material_name := material.resource_name if material else ""
			if "Eye" in material_name or "Hair" in material_name:
				# Eyes and brows.
				_add_surface(parts["head"], arrays, PackedInt32Array(arrays[Mesh.ARRAY_INDEX]), material, source.surface_get_format(s), _hand_binds(mesh.skin, skeleton))
				continue
			bind_skin = mesh.skin
			var by_slot := _split(arrays, mesh.skin, skeleton)
			for slot: String in by_slot:
				_add_surface(parts[slot], arrays, by_slot[slot], material, source.surface_get_format(s), _hand_binds(mesh.skin, skeleton))
	for slot: String in PART_NODES:
		var part := MeshInstance3D.new()
		part.name = PART_NODES[slot]
		part.mesh = parts[slot]
		part.skin = bind_skin
		skeleton.add_child(part)
		part.skeleton = NodePath("..")
	for path: String in String(args.get("hair", "")).split(",", false):
		var hair_scene := load_gltf(path)
		if hair_scene == null:
			printerr("cannot read ", path)
			return 1
		var hair_skeleton := find_one(hair_scene, "Skeleton3D") as Skeleton3D
		for mesh: MeshInstance3D in hair_scene.find_children("*", "MeshInstance3D", true, false):
			var skin := mesh.skin.duplicate() as Skin
			for i in skin.get_bind_count():
				var bone_name := hair_skeleton.get_bone_name(skin.get_bind_bone(i)) if skin.get_bind_name(i) == "" else String(skin.get_bind_name(i))
				skin.set_bind_bone(i, skeleton.find_bone(game_bone(bone_name)))
				skin.set_bind_name(i, "")
			mesh.get_parent().remove_child(mesh)
			mesh.name = path.get_file().get_basename()
			mesh.skin = skin
			skeleton.add_child(mesh)
			mesh.skeleton = NodePath("..")
		hair_scene.free()
	# One material per name: every hair file brings its own copy of the
	# same textures.
	var shared := {}
	for mesh: MeshInstance3D in skeleton.find_children("*", "MeshInstance3D", true, false):
		var surfaces := mesh.mesh as ArrayMesh
		for i in surfaces.get_surface_count():
			var material := surfaces.surface_get_material(i)
			if material == null:
				continue
			if shared.has(material.resource_name):
				surfaces.surface_set_material(i, shared[material.resource_name])
			else:
				shared[material.resource_name] = material
	# The finished rig: CharacterArmature/Skeleton3D, the shape the old one had.
	var rig := Node3D.new()
	rig.name = "Rig"
	var armature := Node3D.new()
	armature.name = "CharacterArmature"
	rig.add_child(armature)
	var out_skeleton := skeleton
	skeleton.get_parent().remove_child(skeleton)
	armature.add_child(out_skeleton)
	out_skeleton.name = "Skeleton3D"
	_own(rig, rig)
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	rig.add_child(player)
	player.owner = rig
	var library := AnimationLibrary.new()
	var track_root := "CharacterArmature/Skeleton3D"
	# The library's clips, retracked onto our bone names.
	var ual := {}
	for path: String in String(args.get("ual", "")).split(",", false):
		var scene := load_gltf(path)
		if scene == null:
			printerr("cannot read ", path)
			return 1
		var source_player := find_one(scene, "AnimationPlayer") as AnimationPlayer
		for anim_name in source_player.get_animation_list():
			var anim := source_player.get_animation(anim_name).duplicate(true) as Animation
			_retrack(anim, track_root)
			ual[String(anim_name).get_slice("|", String(anim_name).get_slice_count("|") - 1)] = anim
		scene.free()
	for clip: String in ual:
		library.add_animation(clip, ual[clip])
	_curl = _curl_axes(ual.get(CURL_CLIP, ual.get(CURL_CLIP + "_Loop")), out_skeleton)
	print("finger joints with a curl axis: ", _curl.size())
	# The old rig, for clips the library has no match for.
	var old: Node3D = null
	if args.has("old"):
		var packed := load(args["old"]) as PackedScene
		old = packed.instantiate() if packed else null
		if old:
			add_child(old)
	for clip: String in CLIPS:
		var source: Variant = CLIPS[clip]
		var anim: Animation = null
		if source is String:
			if ual.has(source):
				anim = (ual[source] as Animation).duplicate(true)
		elif old:
			anim = _retarget(old, source[1], out_skeleton, track_root)
		if anim == null:
			print("  missing: ", clip, " <- ", source)
			continue
		if library.has_animation(clip):
			library.remove_animation(clip)
		library.add_animation(clip, anim)
	player.add_animation_library("", library)
	if old:
		old.queue_free()
	# Write it out. Shrink the pack's textures first (`shrink_textures.py`).
	add_child(rig)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(rig, state)
	if err == OK:
		var bytes := _restore_dots(doc.generate_buffer(state))
		var file := FileAccess.open(ProjectSettings.globalize_path(args["out"]), FileAccess.WRITE)
		if file == null:
			err = FileAccess.get_open_error()
		else:
			file.store_buffer(bytes)
			file.close()
	print("wrote ", args["out"], " clips ", library.get_animation_list().size(), " err ", err)
	return 0 if err == OK else 1


## glTF export writes "Wrist.L" as "Wrist_L"; the game's names keep the dot.
static func _restore_dots(glb: PackedByteArray) -> PackedByteArray:
	var json_length := glb.decode_u32(12)
	var source := glb.slice(20, 20 + json_length).get_string_from_utf8()
	var dots := RegEx.create_from_string('"name":"([A-Za-z]+[0-9]?)_([LR])"')
	source = dots.sub(source, '"name":"$1.$2"', true)
	var text := source.to_utf8_buffer()
	while text.size() % 4 != 0:
		text.append(0x20)
	var rest := glb.slice(20 + json_length)
	var out := PackedByteArray()
	out.resize(20)
	out.encode_u32(0, 0x46546C67)
	out.encode_u32(4, 2)
	out.encode_u32(8, 20 + text.size() + rest.size())
	out.encode_u32(12, text.size())
	out.encode_u32(16, 0x4E4F534A)
	out.append_array(text)
	out.append_array(rest)
	return out


## Triangle indices of `arrays` by part, each triangle going to the part of
## the bone that carries most of its weight.
func _split(arrays: Array, skin: Skin, skeleton: Skeleton3D) -> Dictionary:
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var slot_of := {}
	for i in skin.get_bind_count():
		slot_of[i] = part_of(skeleton.get_bone_name(skin.get_bind_bone(i)))
	var out := {}
	for slot: String in PART_NODES:
		out[slot] = PackedInt32Array()
	for t in range(0, indices.size(), 3):
		var score := {}
		for k in 3:
			var v := indices[t + k]
			for j in per:
				var slot: String = slot_of.get(bones[v * per + j], "body")
				score[slot] = score.get(slot, 0.0) + weights[v * per + j]
		var best := "body"
		for slot: String in score:
			if score[slot] > score.get(best, 0.0):
				best = slot
		# Packed arrays come out of a dictionary as copies.
		var picked: PackedInt32Array = out[best]
		picked.append_array(indices.slice(t, t + 3))
		out[best] = picked
	return out


## Which part a bone's skin belongs to.
static func part_of(bone: String) -> String:
	if bone == "Head":
		return "head"
	if bone.begins_with("Foot") or bone.begins_with("Toe"):
		return "feet"
	if bone == "Hips" or bone.begins_with("UpperLeg") or bone.begins_with("LowerLeg"):
		return "legs"
	return "body"


## Adds the triangles `indices` of `arrays` to `mesh` as a surface of their
## own, keeping only the vertices they use.
func _add_surface(mesh: ArrayMesh, arrays: Array, indices: PackedInt32Array, material: Material, format: int, hands: Dictionary) -> void:
	if indices.is_empty():
		return
	var remap := {}
	var order := PackedInt32Array()
	var new_indices := PackedInt32Array()
	new_indices.resize(indices.size())
	for i in indices.size():
		var v := indices[i]
		if not remap.has(v):
			remap[v] = order.size()
			order.append(v)
		new_indices[i] = remap[v]
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	var count := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	for a in Mesh.ARRAY_MAX:
		var data = arrays[a]
		# The pack's own extra channels are dropped: CUSTOM0 becomes ours.
		if data == null or a == Mesh.ARRAY_INDEX or a >= Mesh.ARRAY_CUSTOM0 and a <= Mesh.ARRAY_CUSTOM3:
			continue
		var per: int = data.size() / count
		var picked = data.duplicate()
		picked.resize(order.size() * per)
		for n in order.size():
			for k in per:
				picked[n * per + k] = data[order[n] * per + k]
		out[a] = picked
	out[Mesh.ARRAY_INDEX] = new_indices
	# Each vertex's place at rest and its hand share, for the suit's
	# patterns and gloves (`character.gdshader`). glTF carries it as
	# TEXCOORD_2 and _3, which Godot imports back as CUSTOM0.
	out[Mesh.ARRAY_CUSTOM0] = _rest_marks(out, hands)
	var flags := format & (Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
	flags |= Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out, [], {}, flags)
	mesh.surface_set_material(mesh.get_surface_count() - 1, material)


## The skin's binds that are a hand's bones.
static func _hand_binds(skin: Skin, skeleton: Skeleton3D) -> Dictionary:
	var out := {}
	for i in skin.get_bind_count():
		var bone := skeleton.get_bone_name(skin.get_bind_bone(i))
		for prefix: String in HAND_BONES:
			if bone.begins_with(prefix):
				out[i] = true
	return out


## Each vertex's place on the body at rest (xyz) and how much it belongs to
## a hand (w).
static func _rest_marks(arrays: Array, hands: Dictionary) -> PackedFloat32Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / maxi(verts.size(), 1)
	var out := PackedFloat32Array()
	out.resize(verts.size() * 4)
	for v in verts.size():
		var hand := 0.0
		for k in per:
			if hands.has(bones[v * per + k]):
				hand += weights[v * per + k]
		out[v * 4] = verts[v].x
		out[v * 4 + 1] = verts[v].y
		out[v * 4 + 2] = verts[v].z
		out[v * 4 + 3] = clampf(hand, 0.0, 1.0)
	return out


func _own(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_own(child, owner_node)


## Points every track of `anim` at our skeleton and bone names; drops
## tracks for bones we do not have.
func _retrack(anim: Animation, track_root: String) -> void:
	for t in range(anim.get_track_count() - 1, -1, -1):
		var path := anim.track_get_path(t)
		if path.get_subname_count() == 0:
			anim.remove_track(t)
			continue
		anim.track_set_path(t, NodePath("%s:%s" % [track_root, game_bone(path.get_concatenated_subnames())]))


## A clip of the old rig, played on the new skeleton.
func _retarget(old: Node3D, clip: String, target: Skeleton3D, track_root: String) -> Animation:
	var player := find_one(old, "AnimationPlayer") as AnimationPlayer
	var source := find_one(old, "Skeleton3D") as Skeleton3D
	var found := ""
	for anim_name in player.get_animation_list():
		if String(anim_name).get_slice("|", String(anim_name).get_slice_count("|") - 1) == clip:
			found = anim_name
	if found == "":
		return null
	var src_anim := player.get_animation(found)
	# Rest globals of both, and where each target bone's rest must bend to
	# point the way the old rest does.
	var pairs := []  # [target bone, source bone]
	for b in target.get_bone_count():
		var s := source.find_bone(target.get_bone_name(b))
		if s >= 0:
			pairs.append([b, s])
	var src_rest := {}
	var tgt_rest := {}
	for p in pairs:
		src_rest[p[1]] = source.get_bone_global_rest(p[1])
		tgt_rest[p[0]] = target.get_bone_global_rest(p[0])
	# A bone's direction runs from it to the next bone down the limb
	# (`_next`), measured the same way in both rigs whatever their
	# hierarchy; a bone with no next keeps its rest turn.
	var bend := {}
	for p in pairs:
		var next := _next(target.get_bone_name(p[0]))
		if target.get_bone_name(p[0]).trim_suffix(".L").trim_suffix(".R") in UNBENT:
			# The trunk and collarbones keep their own lie and take only the
			# old body's turns: bent, a differently curved spine would tip
			# the chest and head, and the long collarbone, bent up the way
			# the old short one points, would shrug the shoulder a hand high.
			next = ""
		var tn := target.find_bone(next)
		var sn := source.find_bone(next)
		if next == "" or tn < 0 or sn < 0:
			bend[p[0]] = Quaternion.IDENTITY
			continue
		var ds: Vector3 = (source.get_bone_global_rest(sn).origin - src_rest[p[1]].origin).normalized()
		var dt: Vector3 = (target.get_bone_global_rest(tn).origin - tgt_rest[p[0]].origin).normalized()
		bend[p[0]] = Quaternion(dt, ds) if dt.cross(ds).length() > 1e-5 else Quaternion.IDENTITY
	# The old feet are IK bones whose rest lies differently from the foot
	# they move, so a foot is placed relative to how it stands in the old
	# idle: standing there, the new foot is at its own rest (flat, ahead).
	for idle_name in player.get_animation_list():
		if String(idle_name).get_slice("|", String(idle_name).get_slice_count("|") - 1) != "Idle_Neutral":
			continue
		player.play(idle_name)
		player.seek(0.0, true)
		source.force_update_all_bone_transforms()
		for p in pairs:
			if target.get_bone_name(p[0]).begins_with("Foot"):
				var stand: Quaternion = source.get_bone_global_pose(p[1]).basis.get_rotation_quaternion() \
						* src_rest[p[1]].basis.get_rotation_quaternion().inverse()
				bend[p[0]] = stand.inverse()
	var src_hips := source.find_bone("Hips")
	var tgt_hips := target.find_bone("Hips")
	var scale: float = tgt_rest[tgt_hips].origin.y / maxf(src_rest[src_hips].origin.y, 0.01) if tgt_hips >= 0 and src_hips >= 0 else 1.0
	# A collarbone turns less than the old one did, by how much longer it
	# is, so its end (the shoulder) moves as far as the old one's did: the
	# same shrug on a long collarbone would throw the shoulder about.
	var damp := {}
	for p in pairs:
		var bone_name := target.get_bone_name(p[0])
		if not bone_name.begins_with("Shoulder"):
			continue
		var next := _next(bone_name)
		var tn := target.find_bone(next)
		var sn := source.find_bone(next)
		if tn < 0 or sn < 0:
			continue
		var src_len: float = (source.get_bone_global_rest(sn).origin - src_rest[p[1]].origin).length() * scale
		var tgt_len: float = (target.get_bone_global_rest(tn).origin - tgt_rest[p[0]].origin).length()
		damp[p[0]] = clampf(src_len / maxf(tgt_len, 0.001), 0.0, 1.0)
	var anim := Animation.new()
	anim.length = src_anim.length
	anim.loop_mode = src_anim.loop_mode
	var rot_tracks := {}
	for p in pairs:
		var t := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(t, NodePath("%s:%s" % [track_root, target.get_bone_name(p[0])]))
		rot_tracks[p[0]] = t
	var pos_track := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(pos_track, NodePath("%s:Hips" % track_root))
	player.play(found)
	var frames := int(ceil(src_anim.length * FPS))
	for f in frames + 1:
		var time := minf(f / FPS, src_anim.length)
		player.seek(time, true)
		source.force_update_all_bone_transforms()
		# Target globals, parents first (bones are listed parents first).
		var globals := {}
		var basis_of := {}
		for p in pairs:
			var g := source.get_bone_global_pose(p[1])
			var delta: Quaternion = g.basis.get_rotation_quaternion() * src_rest[p[1]].basis.get_rotation_quaternion().inverse()
			if damp.has(p[0]):
				delta = Quaternion.IDENTITY.slerp(delta, damp[p[0]])
			basis_of[p[0]] = delta * bend[p[0]] * tgt_rest[p[0]].basis.get_rotation_quaternion()
		for p in pairs:
			var b: int = p[0]
			var parent := target.get_bone_parent(b)
			var parent_rot := _global_rot(target, parent, basis_of)
			var local: Quaternion = parent_rot.inverse() * basis_of[b]
			if _curl.has(b):
				# A finger takes only how far the old one curls, about its own
				# curl axis: the old fingers bend about other axes, and turned
				# over whole they splay into a claw.
				var bent: Quaternion = source.get_bone_rest(p[1]).basis.get_rotation_quaternion().inverse() \
						* source.get_bone_pose_rotation(p[1])
				if bent.w < 0.0:
					bent = -bent
				local = target.get_bone_rest(b).basis.get_rotation_quaternion() * Quaternion(_curl[b], bent.get_angle())
				basis_of[b] = parent_rot * local
			anim.rotation_track_insert_key(rot_tracks[b], time, local.normalized())
		if tgt_hips >= 0 and src_hips >= 0:
			var moved: Vector3 = source.get_bone_global_pose(src_hips).origin - src_rest[src_hips].origin
			var hips_global: Vector3 = tgt_rest[tgt_hips].origin + moved * scale
			var parent := target.get_bone_parent(tgt_hips)
			var parent_global := target.get_bone_global_rest(parent) if parent >= 0 else Transform3D.IDENTITY
			anim.position_track_insert_key(pos_track, time, parent_global.affine_inverse() * hips_global)
	return anim


## A bone's global turn this frame: its own if retargeted, else its parent's
## turn times its rest.
func _global_rot(skeleton: Skeleton3D, bone: int, basis_of: Dictionary) -> Quaternion:
	if bone < 0:
		return Quaternion.IDENTITY
	if basis_of.has(bone):
		return basis_of[bone]
	var q := _global_rot(skeleton, skeleton.get_bone_parent(bone), basis_of) * skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
	basis_of[bone] = q
	return q


## Bones carried across without bending (see `_retarget`).
const UNBENT := ["Hips", "Abdomen", "Torso", "Chest", "Neck", "Head", "Shoulder"]


## Each finger joint's curl axis (in its rest frame), from how it turns in
## `clip`'s closed hand.
static func _curl_axes(clip: Animation, skeleton: Skeleton3D) -> Dictionary:
	var out := {}
	if clip == null:
		return out
	for t in clip.get_track_count():
		if clip.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		var bone := skeleton.find_bone(String(clip.track_get_path(t).get_concatenated_subnames()))
		if bone < 0:
			continue
		var name := skeleton.get_bone_name(bone)
		if not (name.begins_with("Index") or name.begins_with("Middle") or name.begins_with("Ring")
				or name.begins_with("Pinky") or name.begins_with("Thumb")):
			continue
		var turn := skeleton.get_bone_rest(bone).basis.get_rotation_quaternion().inverse() \
				* clip.rotation_track_interpolate(t, 0.0)
		if turn.w < 0.0:
			turn = -turn
		if turn.get_angle() > 0.05:
			out[bone] = turn.get_axis().normalized()
	return out


## The bone a bone points at, by the game's names.
static func _next(bone: String) -> String:
	var side := bone.right(2) if bone.ends_with(".L") or bone.ends_with(".R") else ""
	var base := bone.trim_suffix(side)
	const CHAIN := {"Hips": "Abdomen", "Abdomen": "Torso", "Torso": "Chest", "Chest": "Neck", "Neck": "Head",
		"Shoulder": "UpperArm", "UpperArm": "LowerArm", "LowerArm": "Wrist", "Wrist": "Middle1",
		"UpperLeg": "LowerLeg", "LowerLeg": "Foot"}
	if CHAIN.has(base):
		return CHAIN[base] + side
	for finger in ["Index", "Middle", "Ring", "Pinky", "Thumb"]:
		if base.begins_with(finger) and base.length() == finger.length() + 1:
			var n := base.right(1).to_int()
			return "%s%d%s" % [finger, n + 1, side] if n < 3 else ""
	return ""
