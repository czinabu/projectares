extends Node
## Measures the people's bodies for the armor (`core/visual/body_fit.gd`):
## the rest body cut across in slices, round the trunk and down each limb,
## written to `core/visual/body_fit_data.gd`. Run again whenever the bodies
## change (needs a display or xvfb: a headless run keeps no mesh data):
##
##   godot --path . res://tools/body_fit/body_fit.tscn
##
## Trunk: the body cut level every `TRUNK_STEP` metres from `TRUNK_LOW` to
## `TRUNK_HIGH` (actor frame, feet at 0, front -Z), each slice the distance
## out from the upright axis through (0, y, `TRUNK_Z`) at `ANGLES` angles
## (0 toward -Z, PI/2 toward +X), arms left out. Limbs: the left limb cut
## square to its bone at `LIMB_CUTS` steps from the joint to the next one,
## in the frame `ActorSkin._hang_limb` builds a piece in (Y up the limb
## toward the joint, front -Z, angle 0 at -Z and PI/2 at +X); a right limb
## is its mirror. Each distance is the furthest the skin reaches that way.

const Human := preload("res://core/visual/human.gd")
const OUT := "res://core/visual/body_fit_data.gd"
const TRUNK_LOW := 0.76
const TRUNK_HIGH := 1.64
const TRUNK_STEP := 0.02
const TRUNK_Z := 0.015
const ANGLES := 32
const LIMB_CUTS := 12
## Each limb: its bone, the next joint down it, and the bones whose skin is
## counted as the limb's.
const LIMBS := {
	"UpperArm": ["LowerArm", ["UpperArm", "Shoulder"]],
	"LowerArm": ["Wrist", ["LowerArm", "UpperArm"]],
	"UpperLeg": ["LowerLeg", ["UpperLeg"]],
	"LowerLeg": ["Foot", ["LowerLeg", "UpperLeg", "Foot"]],
}
## The stances the trunk is measured in (`Look.HUMAN_ANIMS`): standing, a
## gun held low, a gun up, a blade held.
const POSES := ["Idle_Stand", "Idle_Gun", "Idle_Gun_Pointing", "Idle_Sword"]
const BONES := ["Hips", "Abdomen", "Torso", "Chest", "Neck", "Head"]


func _ready() -> void:
	var text := "extends RefCounted\n## Made by `tools/body_fit` from the people's bodies: do not edit by hand.\n"
	text += "## See `body_fit.gd` for what it holds.\n\n"
	text += "const TRUNK_LOW := %s\nconst TRUNK_STEP := %s\nconst TRUNK_Z := %s\nconst ANGLES := %d\nconst LIMB_CUTS := %d\n\n" % [
			TRUNK_LOW, TRUNK_STEP, TRUNK_Z, ANGLES, LIMB_CUTS]
	text += "const DATA := {\n"
	for build: String in Human.BUILDS:
		text += _measure(build)
	text += "}\n"
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print("wrote ", OUT)
	get_tree().quit()


func _measure(build: String) -> String:
	print(build, " start ", Time.get_ticks_msec())
	var rig: Node3D = (load(Human.rig_path(build)) as PackedScene).instantiate()
	add_child(rig)
	# Pack models face +Z; actors face -Z (`ActorSkin._ready`).
	rig.rotation.y = PI
	var sk := rig.find_child("Skeleton3D", true, false) as Skeleton3D
	var to_actor := sk.global_transform
	var rest := {}
	for b in sk.get_bone_count():
		rest[b] = sk.get_bone_global_rest(b)
	var bone_at := func(name: String) -> Vector3:
		return to_actor * (rest[sk.find_bone(name)] as Transform3D).origin
	# Every triangle of the body, at rest, with the bone that moves it most.
	var tris := _skin(sk, rest, to_actor)
	print(build, " skinned ", Time.get_ticks_msec())
	var out := "\t\"%s\": {\n" % build
	out += "\t\t\"bones\": {"
	for name: String in BONES:
		out += "\"%s\": %s, " % [name, _v(bone_at.call(name))]
	for name: String in ["Shoulder", "UpperArm", "LowerArm", "Wrist", "UpperLeg", "LowerLeg", "Foot"]:
		out += "\"%s\": %s, " % [name, _v(bone_at.call(name + ".L"))]
	out += "},\n"
	# The trunk is measured as the armor on it sees it: in each stance a
	# person stands in (`POSES`), arms down, relative to the bone the piece
	# hangs on (the chest above the waist, the hips below) and put back
	# where that bone stands at rest; the widest of them all. The arms are
	# left out.
	var player := rig.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var waist: float = (bone_at.call("Torso") as Vector3).y
	var chest := sk.find_bone("Chest")
	var hips := sk.find_bone("Hips")
	var arm := sk.find_bone("UpperArm.L")
	var trunk := []
	var arm_poses := []
	for pose: String in POSES:
		var posed := rest
		var found := ""
		for anim: String in player.get_animation_list() if player else PackedStringArray():
			if anim == pose or anim.ends_with("/" + pose) or anim.ends_with("|" + pose):
				found = anim
		if found != "":
			player.play(found)
			player.seek(0.0, true)
			posed = {}
			for bi in sk.get_bone_count():
				posed[bi] = sk.get_bone_global_pose(bi)
		else:
			push_warning("body_fit: no animation " + pose)
		var back := {}
		for bi: int in [chest, hips]:
			back[bi] = to_actor * (rest[bi] as Transform3D) * (posed[bi] as Transform3D).affine_inverse() * to_actor.affine_inverse()
		arm_poses.append((back[chest] as Transform3D) * to_actor * (posed[arm] as Transform3D) * (rest[arm] as Transform3D).affine_inverse() \
				* to_actor.affine_inverse())
		for t: Array in _skin(sk, posed, to_actor):
			var keep := true
			for o: String in t[3]:
				if o in ["UpperArm", "LowerArm", "Wrist"] or o.begins_with("Thumb") or o.begins_with("Index") \
						or o.begins_with("Middle") or o.begins_with("Ring") or o.begins_with("Pinky"):
					keep = false
			if not keep:
				continue
			var mid: Vector3 = ((t[0] as Vector3) + t[1] + t[2]) / 3.0
			var xf: Transform3D = back[chest] if mid.y > waist else back[hips]
			trunk.append([xf * (t[0] as Vector3), xf * (t[1] as Vector3), xf * (t[2] as Vector3), t[3], t[4]])
	if player:
		player.stop()
	out += "\t\t\"arm_poses\": [%s],\n" % ", ".join(arm_poses.map(func(x: Transform3D) -> String: return _t(x)))
	print(build, ": ", tris.size(), " triangles")
	out += "\t\t\"trunk\": [\n"
	var heights := []
	var y := TRUNK_LOW
	while y <= TRUNK_HIGH + 0.0001:
		heights.append(Vector3(0, y, TRUNK_Z))
		y += TRUNK_STEP
	var trunk_buckets := _buckets(trunk, heights, Vector3.UP)
	for k in heights.size():
		var row := _slice(trunk_buckets[k], heights[k], Vector3.UP, Vector3.FORWARD, Vector3.RIGHT, 0.32)
		out += "\t\t\t" + _row(row) + ",\n"
	out += "\t\t],\n"
	for limb: String in LIMBS:
		var next: String = LIMBS[limb][0]
		var own: Array = LIMBS[limb][1]
		var a: Vector3 = bone_at.call(limb + ".L")
		var b: Vector3 = bone_at.call(next + ".L")
		# The frame `ActorSkin._hang_limb` builds a piece in.
		var up := (a - b).normalized()
		var front := Vector3.FORWARD - up * up.dot(Vector3.FORWARD)
		front = front.normalized() if front.length() > 0.1 else Vector3.FORWARD
		var x_axis := up.cross(-front).normalized()
		var tris_here := []
		for t: Array in tris:
			if (t[4] as float) > 0.0:
				continue
			var mine := false
			for o: String in t[3]:
				if o in own:
					mine = true
			if mine:
				tris_here.append(t)
		out += "\t\t\"%s\": {\"length\": %.4f, \"cuts\": [\n" % [limb, a.distance_to(b)]
		var cuts := []
		for k in LIMB_CUTS + 1:
			cuts.append(a.lerp(b, float(k) / LIMB_CUTS))
		var limb_buckets := _buckets(tris_here, cuts, up)
		for k in cuts.size():
			# Square to the limb; angle 0 toward the piece's -Z (front), PI/2 toward its +X.
			out += "\t\t\t" + _row(_slice(limb_buckets[k], cuts[k], up, front, x_axis, 0.16)) + ",\n"
		out += "\t\t]},\n"
	out += "\t},\n"
	rig.free()
	return out


## Every triangle of the body posed by `pose` (bone -> global pose), actor
## frame: its corners, the bone that moves each most, and its side.
func _skin(sk: Skeleton3D, pose: Dictionary, to_actor: Transform3D) -> Array:
	var tris := []
	for mi: MeshInstance3D in sk.find_children("*", "MeshInstance3D", true, false):
		if not String(mi.name) in ["PartBody", "PartLegs", "PartFeet"] or mi.skin == null:
			continue
		var binds := {}
		for i in mi.skin.get_bind_count():
			var bn := mi.skin.get_bind_name(i)
			binds[i] = [sk.find_bone(bn) if bn != "" else mi.skin.get_bind_bone(i), mi.skin.get_bind_pose(i)]
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
				var best := ""
				var bw := 0.0
				for j in per:
					var w := weights[k * per + j]
					if w <= 0.0:
						continue
					var bind: Array = binds[bones[k * per + j]]
					p += w * ((pose[bind[0]] as Transform3D) * (bind[1] as Transform3D) * verts[k])
					if w > bw:
						bw = w
						best = sk.get_bone_name(bind[0])
				at[k] = to_actor * p
				owner[k] = best.trim_suffix(".L").trim_suffix(".R")
			if index.is_empty():
				index = PackedInt32Array(range(verts.size()))
			for t in range(0, index.size(), 3):
				var o := [owner[index[t]], owner[index[t + 1]], owner[index[t + 2]]]
				var side := 0.0
				for q in 3:
					side += at[index[t + q]].x
				tris.append([at[index[t]], at[index[t + 1]], at[index[t + 2]], o, signf(side)])
	return tris


## The triangles each cut through `centres` (square to `normal`) crosses.
func _buckets(tris: Array, centres: Array, normal: Vector3) -> Array:
	var out := []
	var at := PackedFloat32Array()
	for c: Vector3 in centres:
		out.append([])
		at.append(c.dot(normal))
	for t: Array in tris:
		var d0: float = (t[0] as Vector3).dot(normal)
		var d1: float = (t[1] as Vector3).dot(normal)
		var d2: float = (t[2] as Vector3).dot(normal)
		var lo := minf(d0, minf(d1, d2))
		var hi := maxf(d0, maxf(d1, d2))
		for k in at.size():
			if at[k] >= lo and at[k] <= hi:
				(out[k] as Array).append(t)
	return out


## How far out the skin reaches from `centre` at each angle in the plane
## square to `normal`: angle 0 along `zero`, PI/2 along `quarter`. The cut
## is made through every triangle the plane crosses; a ray that meets none
## takes its neighbours' reach.
func _slice(tris: Array, centre: Vector3, normal: Vector3, zero: Vector3, quarter: Vector3, reach: float) -> PackedFloat32Array:
	var segs := []
	for t: Array in tris:
		var d := [(t[0] - centre).dot(normal), (t[1] - centre).dot(normal), (t[2] - centre).dot(normal)]
		var pts := []
		for e in 3:
			var d0: float = d[e]
			var d1: float = d[(e + 1) % 3]
			if (d0 < 0.0) != (d1 < 0.0):
				var p0: Vector3 = t[e]
				var p1: Vector3 = t[(e + 1) % 3]
				var p := p0.lerp(p1, d0 / (d0 - d1)) - centre
				pts.append(Vector2(p.dot(quarter), p.dot(zero)))
		if pts.size() == 2:
			segs.append(pts)
	var out := PackedFloat32Array()
	out.resize(ANGLES)
	for i in ANGLES:
		var ang := TAU * i / ANGLES
		# In the plane: x along `quarter`, y along `zero`.
		var dir := Vector2(sin(ang), cos(ang))
		var best := -1.0
		for s: Array in segs:
			var p: Vector2 = s[0]
			var q: Vector2 = s[1]
			var e := q - p
			var den := dir.x * e.y - dir.y * e.x
			if absf(den) < 0.000001:
				continue
			var u := (p.x * e.y - p.y * e.x) / den
			var v := (p.x * dir.y - p.y * dir.x) / den
			if u > 0.0 and u < reach and v >= 0.0 and v <= 1.0:
				best = maxf(best, u)
		out[i] = best
	# Fill the rays that met nothing from their neighbours.
	for pass_ in ANGLES:
		var missing := false
		for i in ANGLES:
			if out[i] < 0.0:
				var l := out[(i + ANGLES - 1) % ANGLES]
				var r := out[(i + 1) % ANGLES]
				if l >= 0.0 and r >= 0.0:
					out[i] = (l + r) * 0.5
				elif l >= 0.0 or r >= 0.0:
					out[i] = maxf(l, r)
				else:
					missing = true
		if not missing:
			break
	for i in ANGLES:
		out[i] = maxf(out[i], 0.0)
	return out


func _row(row: PackedFloat32Array) -> String:
	var parts := PackedStringArray()
	for r in row:
		parts.append("%.3f" % r)
	return "[" + ", ".join(parts) + "]"


func _t(x: Transform3D) -> String:
	return "Transform3D(%s, %s, %s, %s)" % [_v(x.basis.x), _v(x.basis.y), _v(x.basis.z), _v(x.origin)]


func _v(p: Vector3) -> String:
	return "Vector3(%.4f, %.4f, %.4f)" % [p.x, p.y, p.z]
