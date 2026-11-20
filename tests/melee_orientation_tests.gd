extends RefCounted
## Every melee weapon swings with its striking face leading: an axe's bit,
## a hammer's face, a blade's edge. Each pack model is turned so its face
## points along `Look.STRIKE_FACE` (the face is the last field of
## `Look.MELEE_MODELS`), and every swing of every technique carries the
## head along the way that face points, through the hit, in the one body
## both views show. A model held sideways (the axe and hammer once were)
## fails here.

## Each melee weapon, and what its head looks like from the side once it is
## built (in the holder's space, the length along +Y and the face toward
## `Look.STRIKE_FACE`): "even" faces both ways (a hammer, a double edge), so
## only the axis is checked; "bit" reaches furthest toward its face (an
## axe); "spine" has its tip on the back, away from the edge (a knife);
## "bow" bows out toward its edge (a curved sword's edge is on the outside
## of its curve).
const WEAPONS := {
	"hammer_breaker": "even",
	"axe_splitter": "bit",
	"knife_gutter": "spine",
	"spear_lancer": "even",
	"blade_scrap": "even",
	"blade_arc": "bow",
}


static func run(t: Node) -> void:
	print("Melee weapons swing face first")
	_check_turn(t)
	for id: String in WEAPONS:
		await _check_weapon(t, id)


## `Look.strike_turn` takes any face across the length to the strike face.
static func _check_turn(t: Node) -> void:
	for face: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD, Vector3(1, 0, 1).normalized()]:
		var got := Look.strike_turn(face) * face
		t.check(got.distance_to(Look.STRIKE_FACE) < 0.001, "a face toward %s is turned to the strike face (%s)" % [face, got])
	t.check((Look.strike_turn(Vector3.LEFT) * Vector3.UP).distance_to(Vector3.UP) < 0.001, "the turn keeps the length standing")


static func _check_weapon(t: Node, id: String) -> void:
	Look.enabled = true
	var raid := Raid.new()
	t.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 37, ["rifle_carbine", id, "plate_light"])
	await t.frames(10)
	# Alone: nobody to lunge at or be hit by.
	for bot in raid.bots.duplicate():
		raid.bots.erase(bot)
		bot.queue_free()
	raid.zone_rules = false
	var p := raid.player
	p.weapons_locked = false
	var blade: MeleeWeapon = null
	for i in p.weapons.size():
		if p.weapons[i] is MeleeWeapon:
			blade = p.weapons[i]
			p.active_weapon_index = i
	await t.frames(40)
	var holder: Node3D = blade.visual.get_node_or_null("Model") if blade != null and blade.visual != null else null
	t.check(holder != null, "%s is held as a model" % id)
	if holder == null:
		Look.enabled = false
		raid.queue_free()
		await t.frames(2)
		return
	var tip := _check_shape(t, id, holder)
	blade.light_stamina = 0.0
	blade.heavy_stamina = 0.0
	var pose := ActionPose.of(p)
	var start := p.global_transform
	var D := MeleeWeapon.Dir
	for kind: String in ["light", "heavy"]:
		for dir: int in [D.RIGHT, D.LEFT, D.OVERHEAD]:
			p.global_transform = start
			p.velocity = Vector3.ZERO
			p.stagger_left = 0.0
			await t.frames(30)
			# The blade picks its own sides: start the combo at the step
			# that swings from `dir` (a heavy from a side comes straight
			# off a light, from the middle on its own).
			blade.combo_step = [D.RIGHT, D.LEFT, D.OVERHEAD].find(dir)
			blade._combo_timer = 1.0 if blade.combo_step > 0 else 0.0
			if kind == "heavy":
				# Chained off a light, a heavy comes from the side the next
				# cut would; on its own, from the middle.
				blade.combo_step = {D.RIGHT: 3, D.LEFT: 1, D.OVERHEAD: 0}[dir]
				blade._combo_timer = 1.0 if blade.combo_step > 0 else 0.0
			if kind == "heavy":
				p.cmd.tertiary_pressed = true
			else:
				p.cmd.primary_pressed = true
			# Played for real, frame by frame, in the actor's own frame (a
			# heavy lunges; the eyes go with the body).
			var points: Array[Vector3] = []
			var faces: Array[Vector3] = []
			var flats: Array[Vector3] = []
			var tech := ""
			var shown := -1
			var key := ""
			for f in 90:
				await t.frames(1)
				p.cmd.primary_pressed = false
				p.cmd.tertiary_pressed = false
				var arc := blade.swing_arc()
				if arc < 0.25 or arc > 0.72:
					if not points.is_empty() and arc < 0.0:
						break
					continue
				tech = pose.technique(blade)
				shown = blade.attack_dir
				key = str(pose.technique_key(blade, shown))
				var held := p.global_basis.orthonormalized().inverse() * holder.global_basis.orthonormalized()
				points.append(p.to_local(holder.global_transform * tip))
				faces.append((held * Look.STRIKE_FACE).normalized())
				flats.append((held * Look.STRIKE_FACE.cross(Vector3.UP)).normalized())
			var label := "%s %s from %s (%s)" % [id, kind, MeleeWeapon.Dir.keys()[shown] if shown >= 0 else "?", tech]
			t.check(points.size() >= 2, "%s: the swing is played" % label)
			# A thrust drives the point straight out: no face leads it.
			if points.size() < 2 or tech in ["stab", "thrust2"] or key == "heavy":
				await t.frames(40)
				continue
			# Through the hit, frame to frame, the tip moves the way its
			# face points, and more that way than flat on.
			var lead := 1.0
			var slap := -1.0
			for k in points.size() - 1:
				var way := points[k + 1] - points[k]
				if way.length() < 0.01:
					continue
				way = way.normalized()
				var face := (faces[k] + faces[k + 1]).normalized()
				var flat := (flats[k] + flats[k + 1]).normalized()
				lead = minf(lead, face.dot(way))
				slap = maxf(slap, absf(flat.dot(way)) - face.dot(way))
			t.check(lead > 0.3 and slap < 0.0, "%s: the striking face leads the swing (lead %.2f, flat on %.2f, %d frames)"
					% [label, lead, slap, points.size()])
			await t.frames(40)
	Look.enabled = false
	raid.queue_free()
	await t.frames(2)


## Checks the built model's head faces `Look.STRIKE_FACE` the way its kind
## says, and gives the top of its head (the holder's space), where a swing
## moves fastest.
static func _check_shape(t: Node, id: String, holder: Node3D) -> Vector3:
	var points := PackedVector3Array()
	for node in holder.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null or _under(mesh_node, "Scrap", holder) or _under(mesh_node, "Kit", holder):
			continue
		var xform := holder.global_transform.affine_inverse() * mesh_node.global_transform
		for v in mesh_node.mesh.get_faces():
			points.append(xform * v)
	var top := -INF
	var bottom := INF
	for v in points:
		top = maxf(top, v.y)
		bottom = minf(bottom, v.y)
	var length := top - bottom
	var face := Look.STRIKE_FACE
	var side := face.cross(Vector3.UP).normalized()
	var kind: String = WEAPONS[id]
	# Measured from the line of the handle, its lowest part.
	var handle := _face_at(points, bottom + length * 0.08, length, face)
	# The head: the top of an axe or hammer, the whole blade of a blade.
	var from := top - length * (0.3 if id in ["hammer_breaker", "axe_splitter"] else 0.55)
	var ahead := -INF
	var behind := INF
	var wide := 0.0
	var tip := Vector3(0, -INF, 0)
	for v in points:
		if v.y < from:
			continue
		var along := v.dot(face) - handle
		ahead = maxf(ahead, along)
		behind = minf(behind, along)
		wide = maxf(wide, absf(v.dot(side)))
		if v.y > tip.y:
			tip = v
	t.check(ahead - behind > wide * 2.0 * 1.2, "%s: its head runs along the strike face, not across it (%.3f along, %.3f across)"
			% [id, ahead - behind, wide * 2.0])
	match kind:
		"bit":
			t.check(ahead > -behind * 1.15, "%s: the bit reaches out toward the face (%.3f ahead, %.3f behind)" % [id, ahead, -behind])
		"spine":
			t.check(tip.dot(face) - handle < 0.0, "%s: the point sits on the spine, away from the edge (%.3f)" % [id, tip.dot(face) - handle])
		"bow":
			# Part way up the blade it bows out past the line from its
			# base to its tip.
			var base_y := bottom + length * 0.3
			var mid_y := bottom + length * 0.65
			var base := _face_at(points, base_y, length, face)
			var chord := lerpf(base, tip.dot(face), (mid_y - base_y) / (tip.y - base_y))
			var mid := _face_at(points, mid_y, length, face)
			t.check(mid > chord, "%s: the blade bows out toward its edge (%.3f past the line)" % [id, mid - chord])
	return Vector3(0, top, 0)


## Where the model is across its face this far up: the middle of its
## points nearest that height (a long face has points only at its ends).
static func _face_at(points: PackedVector3Array, y: float, length: float, face: Vector3) -> float:
	var band := length * 0.03
	for tries in 6:
		var sum := 0.0
		var n := 0
		for v in points:
			if absf(v.y - y) < band:
				sum += v.dot(face)
				n += 1
		if n > 0:
			return sum / n
		band *= 2.0
	return 0.0


static func _under(node: Node, name: String, stop: Node) -> bool:
	var up := node.get_parent()
	while up != null and up != stop:
		if up.name == name:
			return true
		up = up.get_parent()
	return false
