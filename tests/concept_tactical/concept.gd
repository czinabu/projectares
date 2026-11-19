extends Node
## Concept renders for the tactical armor and helmet pass.
## godot --path . res://tests/concept_tactical/concept.tscn -- <out_dir> [--sets a,b] [--outfits]

const Kit := preload("res://tests/concept_tactical/kit.gd")
const MirrorScript := preload("res://core/visual/mirror.gd")
const Human := preload("res://core/visual/human.gd")

var out_dir := "/tmp"
var actor: Actor
var cam: Camera3D
var afters := {}
const BEFORE := {"runner": ["frame_runner", "helm_spotter"], "trooper": ["frame_trooper", "helm_seeker"], "bulwark": ["frame_bulwark", "helm_warden"]}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_studio()
	cam = Camera3D.new()
	cam.fov = 30.0
	add_child(cam)
	cam.current = true
	var sets := ["runner", "trooper", "bulwark"]
	var i := args.find("--sets")
	if i >= 0 and i + 1 < args.size():
		sets = Array(args[i + 1].split(","))
	if "--outfits" in args:
		await _outfits()
	else:
		for s: String in sets:
			await _set_sheet(s, "--mirror" in args or "--all" in args)
		if "--before" in args:
			await _before()
	print("done")
	OS.kill(OS.get_process_id())


func _studio() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.095, 0.105)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.62)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(-0.75, 0.6, 0.0)
	key.light_energy = 1.6
	key.shadow_enabled = true
	add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation = Vector3(-0.3, PI + 0.9, 0.0)
	rim.light_energy = 0.9
	rim.light_color = Color(0.75, 0.85, 1.0)
	add_child(rim)
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(30, 30)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.16, 0.165, 0.175)
	fm.roughness = 0.85
	var floor_node := MeshInstance3D.new()
	floor_node.mesh = floor_mesh
	floor_node.material_override = fm
	add_child(floor_node)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 0.2, 30)
	shape.shape = box
	shape.position.y = -0.1
	body.add_child(shape)
	add_child(body)


func _spawn(appearance: Dictionary) -> void:
	if actor != null:
		actor.queue_free()
		await get_tree().process_frame
	actor = Actor.new()
	actor.set_meta("appearance", Human.sanitize(appearance))
	add_child(actor)
	actor.set_physics_process(false)
	actor.cmd.yaw = 0.0
	actor.cmd.pitch = 0.0
	actor.cmd.aim_dir = Vector3.FORWARD
	print("spawned")
	for k in 20:
		await get_tree().process_frame
	print("settled")


func _suit(skin: Node, s: Dictionary) -> void:
	var mats: Array = skin.get("_materials")
	for mat: ShaderMaterial in mats:
		mat.set_shader_parameter("suit", 1.0)
		mat.set_shader_parameter("suit_color", s["suit"])
		mat.set_shader_parameter("suit_trim", s["accent"])
		if int(mat.get_shader_parameter("surface_kind")) == 0:
			mat.set_shader_parameter("surface_kind", 2)


func _dress(set_id: String) -> void:
	var s: Dictionary = Kit.SETS[set_id]
	await _spawn({"build": "m", "head": "Casual_2", "body": "Swat", "legs": "Swat", "feet": "Swat"})
	var skin: Node = actor.get_node("Skin")
	_suit(skin, s)
	var sk: Skeleton3D = skin.get("_skeleton")
	for node in sk.get_children():
		if node is MeshInstance3D and node.get_meta("slot", "") == "head":
			node.visible = false
	skin.call("_hang", Kit.helmet(s["helmet"], s), "ConceptHelmet", "Head", skin.get("helmet_offset"),
			Vector3(0, 1.67, 0))
	Kit.dress(skin, set_id)
	var hh := actor.find_child("ConceptHelmet", true, false).get_child(0).get_child(0)
	print("helmet ", hh, " scale ", hh.scale if hh else null)
	for mi in hh.find_children("*", "MeshInstance3D", true, false):
		var mm := (mi as MeshInstance3D).material_override as StandardMaterial3D
		if mm and mm.metallic > 0.65 and mm.roughness < 0.1:
			print("glass ", mm.emission_energy_multiplier, " ", mm.albedo_color, " ", (mi as MeshInstance3D).get_surface_override_material(0))
	for k in 6:
		await get_tree().process_frame


func _grab(size: Vector2i, aspect: float) -> Image:
	await RenderingServer.frame_post_draw
	var frame := get_viewport().get_texture().get_image()
	var h := frame.get_height()
	var w := frame.get_width()
	var cw := int(h * aspect)
	var cut := frame.get_region(Rect2i(w / 2 - cw / 2, 0, cw, h))
	cut.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	cut.convert(Image.FORMAT_RGBA8)
	return cut


func _set_sheet(set_id: String, mirror: bool) -> void:
	await _dress(set_id)
	# Full body: front, three quarters, side, back.
	var cell := Vector2i(420, 630)
	var head_cell := Vector2i(420, 420)
	var sheet := Image.create(cell.x * 4, cell.y + head_cell.y, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.09, 0.095, 0.105))
	var views := [Vector3.FORWARD, Vector3(0.7, 0, -0.7).normalized(), Vector3.RIGHT, Vector3.BACK]
	for i in views.size():
		var mid := Vector3(0, 1.0, 0)
		cam.fov = 30.0
		cam.global_position = mid + (views[i] as Vector3) * 4.2 + Vector3(0, 0.25, 0)
		cam.look_at(mid)
		var shot := await _grab(cell, 2.0 / 3.0)
		afters["%s_%d" % [set_id, i]] = shot
		sheet.blit_rect(shot, Rect2i(Vector2i.ZERO, cell), Vector2i(i * cell.x, 0))
	# Close ups of the helmet: front three quarters, side, back three quarters, front.
	var hviews := [Vector3(-0.6, 0.1, -0.8).normalized(), Vector3(0.75, 0.05, -0.65).normalized(),
			Vector3(1, 0.05, 0.15).normalized(), Vector3(-0.5, 0.15, 0.85).normalized()]
	for i in hviews.size():
		var head := Vector3(0, 1.6, 0)
		cam.fov = 20.0
		cam.global_position = head + (hviews[i] as Vector3) * 1.5
		cam.look_at(head)
		sheet.blit_rect(await _grab(head_cell, 1.0), Rect2i(Vector2i.ZERO, head_cell), Vector2i(i * cell.x, cell.y))
	sheet.save_png(out_dir.path_join("%s_sheet.png" % set_id))
	print("saved ", set_id)
	if mirror:
		await _mirror_shot(set_id)


func _mirror_shot(set_id: String) -> void:
	var wall := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(6, 3.2, 0.1)
	wall.mesh = wm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.31, 0.33)
	mat.roughness = 0.7
	wall.material_override = mat
	wall.position = Vector3(0, 1.6, -1.9)
	add_child(wall)
	var mirror: Node3D = MirrorScript.new()
	mirror.wall_mounted = true
	mirror.setup(actor, cam)
	mirror.position = Vector3(0, 0.0, -1.83)
	add_child(mirror)
	cam.fov = 55.0
	cam.global_position = Vector3(0.55, 1.75, 1.35)
	cam.look_at(Vector3(-0.05, 1.25, -1.8))
	for k in 8:
		await get_tree().process_frame
	var img := await _grab(Vector2i(1280, 720), 16.0 / 9.0)
	img.save_png(out_dir.path_join("%s_mirror.png" % set_id))
	mirror.queue_free()
	wall.queue_free()
	await get_tree().process_frame


func _outfits() -> void:
	var looks := [["m", "Casual_2"], ["m", "Swat"], ["m", "Spacesuit"], ["f", "Soldier"], ["f", "SciFi"]]
	var cell := Vector2i(300, 450)
	var sheet := Image.create(cell.x * looks.size(), cell.y * 2, false, Image.FORMAT_RGBA8)
	for i in looks.size():
		var l: Array = looks[i]
		print("outfit ", l)
		await _spawn({"build": l[0], "head": l[1], "body": l[1], "legs": l[1], "feet": l[1]})
		_suit(actor.get_node("Skin"), Kit.SETS["trooper"])
		for k in 4:
			await get_tree().process_frame
		for j in 2:
			var mid := Vector3(0, 1.0, 0)
			cam.global_position = mid + (Vector3.FORWARD if j == 0 else Vector3.RIGHT) * 4.2 + Vector3(0, 0.25, 0)
			cam.look_at(mid)
			sheet.blit_rect(await _grab(cell, 2.0 / 3.0), Rect2i(Vector2i.ZERO, cell), Vector2i(i * cell.x, j * cell.y))
	sheet.save_png(out_dir.path_join("outfits.png"))


func _before() -> void:
	var cell := Vector2i(420, 630)
	var keys := BEFORE.keys().filter(func(k: String) -> bool: return afters.has(k + "_0"))
	var sheet := Image.create(cell.x * 4, cell.y * keys.size(), false, Image.FORMAT_RGBA8)
	for row in keys.size():
		var set_id: String = keys[row]
		await _spawn({"build": "m", "head": "Casual_2", "body": "Casual_2", "legs": "Casual_2", "feet": "Casual_2"})
		Loadout.wear_frame(actor, BEFORE[set_id][0])
		Loadout.wear_helmet(actor, BEFORE[set_id][1])
		for k in 10:
			await get_tree().process_frame
		var views := [Vector3.FORWARD, Vector3.BACK]
		for i in 2:
			var mid := Vector3(0, 1.0, 0)
			cam.fov = 30.0
			cam.global_position = mid + (views[i] as Vector3) * 4.2 + Vector3(0, 0.25, 0)
			cam.look_at(mid)
			sheet.blit_rect(await _grab(cell, 2.0 / 3.0), Rect2i(Vector2i.ZERO, cell), Vector2i(i * cell.x, row * cell.y))
		sheet.blit_rect(afters[set_id + "_0"], Rect2i(Vector2i.ZERO, cell), Vector2i(2 * cell.x, row * cell.y))
		sheet.blit_rect(afters[set_id + "_3"], Rect2i(Vector2i.ZERO, cell), Vector2i(3 * cell.x, row * cell.y))
	sheet.save_png(out_dir.path_join("before_after.png"))
	print("saved before_after")
