extends Node
## Finds where the armor cuts into itself or into the body: every frame
## look's pieces hung on each build's body as `ActorSkin` hangs them, in each
## stance the trunk is measured in (`body_fit.gd` POSES),
## then the edges of each piece tested against the triangles of every other
## piece and of the skin. Prints each clash by part ("torso/Chest x
## pad.L/Pad", how many crossings, where, actor frame in raw rig metres),
## and exits 1 if any. An arm meeting the armor in a stance (a hand on a
## pouch) is the stance's to fix, so it is only counted, or listed with
## `--arms`. Needs a display or xvfb (a headless run keeps no body
## mesh data):
##
##   godot --path . res://tools/armor_fit/clip_check.tscn [-- --frames frame_bulwark --builds m]
##
## Within one piece, parts meeting is how it is built (a pouch on a plate),
## so only pieces against each other and against the skin are checked. The
## undersuit is the skin, so a plate under the skin is a clash too.

const Human := preload("res://core/visual/human.gd")
const BodyFit := preload("res://core/visual/body_fit.gd")
const SkinScript := preload("res://core/visual/actor_skin.gd")
const ArmorModel := preload("res://core/visual/armor_model.gd")
const GearShapes := preload("res://core/visual/gear_shapes.gd")
const BodyFitTool := preload("res://tools/body_fit/body_fit.gd")
## Thin trims laid along a plate's face or edge, inset into it by design.
const TRIMS := ["PlateRim", "PanelLine", "VLine", "Keel", "Coil", "LameEdge", "PadEdge", "BracerEdge", "GreaveRidge", "CollarEdge"]
const CELL := 0.02
## How deep a crossing must be before it counts: a sliver where two surfaces
## touch is not seen.
const SLACK := 0.002


var show_arms := false
var arm_contacts := 0


func _ready() -> void:
	var frames: Array = SkinScript.FRAME_LOOKS.keys()
	var builds: Array = Human.BUILDS
	var args := OS.get_cmdline_user_args()
	for i in args.size() - 1:
		if args[i] == "--frames":
			frames = Array(args[i + 1].split(","))
		if args[i] == "--builds":
			builds = Array(args[i + 1].split(","))
	show_arms = "--arms" in args
	GearShapes.keep_parts = true
	var total := 0
	for build: String in builds:
		for pose: Dictionary in _bodies(build):
			for id: String in frames:
				total += _check(build, id, pose)
	print("clip check: ", total, " clashes; arms against the armor in a stance: ", arm_contacts, "" if show_arms else " (--arms lists them)")
	get_tree().quit(1 if total > 0 else 0)


## The body in each stance the armor is measured in (`body_fit.gd`
## POSES): its triangles, raw rig metres, actor frame, each named by the
## bone that moves its first corner most ("skin"), and for each bone a
## piece hangs on, what the stance does to it ("move", actor frame).
func _bodies(build: String) -> Array:
	var rig: Node3D = (load(Human.rig_path(build)) as PackedScene).instantiate()
	add_child(rig)
	rig.rotation.y = PI
	var sk := rig.find_child("Skeleton3D", true, false) as Skeleton3D
	var player := rig.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var to_actor := sk.global_transform
	var out := []
	for stance: String in BodyFitTool.POSES:
		var found := ""
		for anim: String in player.get_animation_list():
			if anim == stance or anim.ends_with("/" + stance) or anim.ends_with("|" + stance):
				found = anim
		if found == "":
			continue
		player.play(found)
		player.seek(0.0, true)
		var pose := {}
		for bi in sk.get_bone_count():
			pose[bi] = sk.get_bone_global_pose(bi)
		var move := {}
		for bone: String in ["Chest", "Hips", "UpperArm.L", "UpperArm.R", "LowerArm.L", "LowerArm.R", "UpperLeg.L", "UpperLeg.R",
				"LowerLeg.L", "LowerLeg.R"]:
			var bi := sk.find_bone(bone)
			move[bone] = to_actor * (pose[bi] as Transform3D) * sk.get_bone_global_rest(bi).affine_inverse() * to_actor.affine_inverse()
		out.append({"name": stance, "skin": _skin(sk, pose, to_actor), "move": move, "first": out.is_empty()})
	rig.free()
	return out


func _skin(sk: Skeleton3D, pose: Dictionary, to_actor: Transform3D) -> Array:
	var tris := PackedVector3Array()
	var parts := PackedStringArray()
	for mi: MeshInstance3D in sk.find_children("*", "MeshInstance3D", true, false):
		if not String(mi.name) in ["PartBody", "PartLegs", "PartFeet"] or mi.skin == null:
			continue
		var binds := {}
		for i in mi.skin.get_bind_count():
			var bn := mi.skin.get_bind_name(i)
			var bone := sk.find_bone(bn) if bn != "" else mi.skin.get_bind_bone(i)
			binds[i] = [(pose[bone] as Transform3D) * mi.skin.get_bind_pose(i), sk.get_bone_name(bone)]
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			var index: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
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
					if w > 0.0:
						var bind: Array = binds[bones[k * per + j]]
						p += w * ((bind[0] as Transform3D) * verts[k])
						if w > bw:
							bw = w
							owner[k] = bind[1]
				at[k] = to_actor * p
			if index.is_empty():
				index = PackedInt32Array(range(verts.size()))
			for i in index.size():
				tris.append(at[index[i]])
			for i in range(0, index.size(), 3):
				parts.append(owner[index[i]])
	return [tris, parts]


## Each piece of frame `id` on `build`: [triangles in the actor frame, the
## part each triangle belongs to].
func _pieces(build: String, id: String, move: Dictionary) -> Dictionary:
	var weight := SkinScript.frame_weight(id)
	var style := SkinScript.frame_style(id, "")
	var out := {}
	out["torso"] = _tris(ArmorModel.torso(weight, style, build), move["Chest"] * Transform3D(Basis.IDENTITY, BodyFit.bone(build, "Chest")))
	out["belt"] = _tris(ArmorModel.belt(weight, style, build), move["Hips"] * Transform3D(Basis.IDENTITY, BodyFit.bone(build, "Hips")))
	for side: float in [-1.0, 1.0]:
		var tag := "L" if side < 0.0 else "R"
		for limb: Array in [["UpperArm", "LowerArm", ArmorModel.pauldron(weight, style, side, build), "pad"],
				["LowerArm", "Wrist", ArmorModel.forearm(weight, style, side, build), "bracer"],
				["UpperLeg", "LowerLeg", ArmorModel.thigh(weight, style, side, build), "thigh"],
				["LowerLeg", "Foot", ArmorModel.shin(weight, style, side, build), "shin"]]:
			var mirror := Vector3(-side, 1, 1)
			var a: Vector3 = BodyFit.bone(build, limb[0]) * mirror
			var b: Vector3 = BodyFit.bone(build, limb[1]) * mirror
			var up := (a - b).normalized()
			var front := Vector3.FORWARD - up * up.dot(Vector3.FORWARD)
			front = front.normalized() if front.length() > 0.1 else Vector3.FORWARD
			out[limb[3] + "." + tag] = _tris(limb[2], move[limb[0] + "." + tag] * Transform3D(Basis(up.cross(-front).normalized(), up, -front), a))
	return out


func _tris(root: Node3D, at: Transform3D) -> Array:
	var tris := PackedVector3Array()
	var parts := PackedStringArray()
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var xf := at
		var chain := []
		var n: Node = mi
		while n != root:
			chain.push_front((n as Node3D).transform)
			n = n.get_parent()
		for t: Transform3D in chain:
			xf = xf * t
		# Only plates laid over the body are checked against each other
		# within a piece; something mounted on one (a pouch, a placard) is
		# marked "+" and only checked against other pieces and the skin.
		var part: String = mi.get_meta("part", str(mi.name))
		part += "" if mi.get_meta("sheet", false) and not part in TRIMS else "+"
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var index := PackedInt32Array(arr[Mesh.ARRAY_INDEX]) if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if index.is_empty():
				index = PackedInt32Array(range(verts.size()))
			for i in index.size():
				tris.append(xf * verts[index[i]])
			for i in index.size() / 3:
				parts.append(part)
	root.free()
	return [tris, parts]


## Triangles bucketed by the cells their bounds cover.
func _grid(tris: PackedVector3Array) -> Dictionary:
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


## Where edges of `a` pass through triangles of `b`: [point, a's triangle,
## b's triangle] each.
func _cross(a: PackedVector3Array, b: PackedVector3Array, grid: Dictionary) -> Array:
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
							# Deep enough: both ends further than the slack from the triangle.
							var n := (b[u + 1] - b[u]).cross(b[u + 2] - b[u]).normalized()
							if absf((p - b[u]).dot(n)) > SLACK and absf((q - b[u]).dot(n)) > SLACK:
								hits.append([hit, t / 3, u / 3])
	return hits


## The triangles of `piece` whose bounds touch `box`, with their parts.
func _near(piece: Array, box: AABB) -> Array:
	var tris: PackedVector3Array = piece[0]
	var parts: PackedStringArray = piece[1]
	var out := PackedVector3Array()
	var names := PackedStringArray()
	for t in range(0, tris.size(), 3):
		var b := AABB(tris[t], Vector3.ZERO).expand(tris[t + 1]).expand(tris[t + 2])
		if b.intersects(box):
			out.append(tris[t])
			out.append(tris[t + 1])
			out.append(tris[t + 2])
			names.append(parts[t / 3])
	return [out, names]


func _bounds(tris: PackedVector3Array) -> AABB:
	var box := AABB(tris[0], Vector3.ZERO)
	for p in tris:
		box = box.expand(p)
	return box


func _check(build: String, id: String, pose: Dictionary) -> int:
	var pieces := _pieces(build, id, pose["move"])
	pieces["skin"] = pose["skin"]
	var boxes := {}
	for name: String in pieces:
		boxes[name] = _bounds(pieces[name][0])
	var clashes := 0
	if pose["first"]:
		for name: String in pieces:
			if name != "skin":
				clashes += _within(build, id, name, pieces[name])
	var names: Array = pieces.keys()
	for i in names.size():
		for j in range(i + 1, names.size()):
			var a: String = names[i]
			var b: String = names[j]
			if not (boxes[a] as AABB).intersects(boxes[b]):
				continue
			var box: AABB = (boxes[a] as AABB).intersection(boxes[b]).grow(0.01)
			var near_a := _near(pieces[a], box)
			var near_b := _near(pieces[b], box)
			if near_a[0].is_empty() or near_b[0].is_empty():
				continue
			# Both ways: a small plate can pierce a big one with no edge of
			# the big one crossing it.
			var found := {}
			for h: Array in _cross(near_a[0], near_b[0], _grid(near_b[0])):
				_add(found, "%s/%s x %s/%s" % [a, near_a[1][h[1]], b, near_b[1][h[2]]], h[0])
			for h: Array in _cross(near_b[0], near_a[0], _grid(near_a[0])):
				_add(found, "%s/%s x %s/%s" % [a, near_a[1][h[2]], b, near_b[1][h[1]]], h[0])
			for pair: String in found:
				var f: Array = found[pair]
				# An arm hanging or swinging into the armor is the stance's to
				# keep clear (the arm's pose), not the fit's: counted apart.
				if _arm(pair):
					arm_contacts += 1
					if not show_arms:
						continue
				else:
					clashes += 1
				print("%s %s %s: %s, %d crossings, %s to %s" % [build, pose["name"], id, pair, f[0], _v(f[1]), _v(f[2])])
	return clashes


## Parts of one piece cutting through each other (a knee cap through the
## pad under it): the same in every stance, so checked once. Only plates:
## a part mounted on one (a pouch, a placard) or a trim along one (`TRIMS`)
## sits on or into it by design.
func _within(build: String, id: String, name: String, piece: Array) -> int:
	var tris: PackedVector3Array = piece[0]
	var parts: PackedStringArray = piece[1]
	var by := {}
	for t in parts.size():
		if not by.has(parts[t]):
			by[parts[t]] = PackedVector3Array()
		by[parts[t]].append_array([tris[t * 3], tris[t * 3 + 1], tris[t * 3 + 2]])
	var keys: Array = by.keys().filter(func(k: String) -> bool: return not k.ends_with("+"))
	var clashes := 0
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			var a: PackedVector3Array = by[keys[i]]
			var b: PackedVector3Array = by[keys[j]]
			var ba := _bounds(a)
			var bb := _bounds(b)
			if not ba.intersects(bb):
				continue
			var hits := _cross(a, b, _grid(b))
			hits.append_array(_cross(b, a, _grid(a)))
			if hits.is_empty():
				continue
			clashes += 1
			var lo: Vector3 = hits[0][0]
			var hi: Vector3 = hits[0][0]
			for h: Array in hits:
				lo = lo.min(h[0])
				hi = hi.max(h[0])
			print("%s %s: within %s, %s x %s, %d crossings, %s to %s" % [build, id, name, keys[i], keys[j], hits.size(), _v(lo), _v(hi)])
	return clashes


func _arm(pair: String) -> bool:
	for side: String in pair.split(" x "):
		var piece := side.get_slice("/", 0)
		var part := side.get_slice("/", 1).get_slice(".", 0)
		if piece.begins_with("bracer") or (piece == "skin" and (part in ["UpperArm", "LowerArm", "Wrist"] \
				or part.trim_suffix(part.right(1)) in ["Thumb", "Index", "Middle", "Ring", "Pinky"])):
			return true
	return false


func _add(found: Dictionary, pair: String, at: Vector3) -> void:
	if not found.has(pair):
		found[pair] = [0, at, at]
	var f: Array = found[pair]
	f[0] += 1
	f[1] = (f[1] as Vector3).min(at)
	f[2] = (f[2] as Vector3).max(at)


func _v(p: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [p.x, p.y, p.z]
