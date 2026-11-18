extends Node
## Renders every planet type (DESIGN.md "Planet kit") for a look by eye:
## a ground view, a high view over the land and the thick of its storm,
## each on a 640 m map of its own ground with the horizon, props, sky, light
## and weather a world on it would get, and a person for scale.
##
##   godot --path . res://tests/planet_check.tscn -- <dir> [type ids...]
##
## Needs a display (or xvfb). Saves <type>_ground.png, <type>_high.png and
## <type>_storm.png, plus sheet.png with every shot.

const HALF := 320.0

var _out := ""
var _shots: Array[Image] = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "user://planets"
	DirAccess.make_dir_recursive_absolute(_out)
	var ids: Array[String] = []
	for i in range(1, args.size()):
		ids.append(args[i])
	if ids.is_empty():
		ids = PlanetTypes.ids()
	get_window().size = Vector2i(1600, 900)
	for id in ids:
		await _planet(PlanetTypes.get_type(id))
	_sheet()
	get_tree().quit()


func _planet(type: PlanetType) -> void:
	var started := Time.get_ticks_msec()
	var map := Node3D.new()
	map.name = "Map"
	add_child(map)
	Planet.atmosphere(map, type)
	var ground := PlanetTerrain.new(type.terrain, 7)
	var terrain := Terrain.new()
	terrain.cell = 2.0
	terrain.side = 321
	terrain.shape(ground.height_at)
	terrain.build(Planet.ground_material(type))
	map.add_child(terrain)
	var built := Time.get_ticks_msec()
	map.add_child(Planet.horizon(type, ground, HALF))
	var height_of := func(x: float, z: float) -> float:
		return terrain.height_at(x, z) if maxf(absf(x), absf(z)) < HALF else ground.height_at(x, z)
	PlanetProps.scatter(map, type, height_of, HALF, 11)
	var air := Planet.weather(map, type.weather.get("air", ""))
	print("%s: ground %d ms, dressing %d ms" % [type.id, built - started, Time.get_ticks_msec() - built])

	var cam := Camera3D.new()
	cam.fov = 64.0
	cam.far = 6000.0
	map.add_child(cam)
	cam.current = true

	var look := _look_yaw(type)
	var spot := _find_spot(terrain, look)
	var person := _person(map, terrain, spot + Vector3(sin(look), 0, cos(look)) * 6.0 + Vector3(cos(look), 0, -sin(look)) * 1.8, look)
	var eye := spot + Vector3(0, 1.7, 0)
	cam.global_position = eye
	cam.rotation = Vector3(deg_to_rad(4.0), look + PI, 0)
	if air != null:
		air.global_position = eye + Vector3(0, 6, 0)
	await _shoot(type.id + "_ground")

	# High over the land, looking out across it.
	var high := spot + Vector3(sin(look), 0, cos(look)) * 60.0
	high.y = terrain.height_at(high.x, high.z) + 45.0
	cam.global_position = high
	cam.rotation = Vector3(deg_to_rad(-9.0), look + PI, 0)
	if is_instance_valid(person):
		person.visible = false
	await _shoot(type.id + "_high")

	# The thick of its storm, from the ground.
	if is_instance_valid(person):
		person.visible = true
	cam.global_position = eye
	cam.rotation = Vector3(deg_to_rad(3.0), look + PI + 0.25, 0)
	var mood := map.get_node_or_null("WarMood")
	if mood != null:
		mood.set_process(false)
		mood.storm_shown = 0.85
		mood.show_intensity(0.0, Vector3.ZERO)
	if is_instance_valid(air):
		air.queue_free()
	var storm := Planet.weather(map, type.weather.get("storm", ""), 30.0, 20.0, 2.5)
	if storm != null:
		storm.global_position = eye + Vector3(0, 4, 0)
	await _shoot(type.id + "_storm")
	Look.weather_cover = 0.0
	map.queue_free()
	await get_tree().process_frame


## Which way the views look: at the ringed giant or the moon if the sky has
## one, else across the light.
func _look_yaw(type: PlanetType) -> float:
	var dir: Vector3 = Vector3.ZERO
	if float(type.sky.get("body1_size", 0.0)) > 0.0:
		dir = type.sky["body1_dir"]
	elif float(type.sky.get("body2_size", 0.0)) > 0.0:
		dir = type.sky["body2_dir"]
	else:
		var sun: Vector3 = type.calm.get("sun_angles", Vector3(-45, 30, 0))
		var yaw := deg_to_rad(sun.y) + 0.6
		return yaw
	# The camera looks down its -Z; the yaw that points it along `dir`.
	return atan2(-dir.x, -dir.z) + PI + 0.18


## A standing spot with a view: on open ground out of the middle, with the
## land falling away ahead rather than a wall in the face.
func _find_spot(terrain: Terrain, look: float) -> Vector3:
	var ahead := Vector3(sin(look), 0, cos(look))
	var best := Vector3.ZERO
	var best_score := -INF
	for i in 120:
		var a := TAU * i / 120.0
		var r := 60.0 + (i % 5) * 35.0
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		p.y = terrain.height_at(p.x, p.z)
		var slope := terrain.slope_at(p.x, p.z)
		var front := terrain.height_at(p.x + ahead.x * 30.0, p.z + ahead.z * 30.0)
		var far := terrain.height_at(p.x + ahead.x * 140.0, p.z + ahead.z * 140.0)
		var score := -slope * 40.0 - maxf(front - p.y, 0.0) * 2.0 - maxf(far - p.y - 8.0, 0.0) + p.y * 0.15
		score -= 400.0 if p.x + ahead.x * 160.0 > HALF or p.x + ahead.x * 160.0 < -HALF else 0.0
		if score > best_score:
			best_score = score
			best = p
	return best


func _person(map: Node3D, terrain: Terrain, at: Vector3, look: float) -> Node3D:
	var holder := Node3D.new()
	map.add_child(holder)
	holder.global_position = Vector3(at.x, terrain.height_at(at.x, at.z), at.z)
	holder.rotation.y = look + PI * 0.75
	var made := Look.character("raider", {}, "scale")
	if made.is_empty():
		return holder
	holder.add_child(made["model"])
	Look.stand_model(holder, made["model"], 1.8)
	var player := made["model"].find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player != null:
		for anim in ["Idle_Gun", "Idle_Neutral"]:
			if player.has_animation(anim):
				player.play(anim)
				break
	return holder


func _shoot(file_name: String) -> void:
	for i in 24:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var calls := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	print("%s: %d draw calls, %d k triangles" % [file_name, calls, prims / 1000])
	var image := get_viewport().get_texture().get_image()
	image.save_png(_out.path_join(file_name + ".png"))
	_shots.append(image)
	print("saved ", file_name)


## Every shot on one sheet, three to a row (ground, high, storm).
func _sheet() -> void:
	if _shots.is_empty():
		return
	var w := 640
	var h := 360
	var rows := ceili(_shots.size() / 3.0)
	var sheet := Image.create(w * 3, h * rows, false, Image.FORMAT_RGB8)
	for i in _shots.size():
		var shot := _shots[i].duplicate() as Image
		shot.convert(Image.FORMAT_RGB8)
		shot.resize(w, h, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(shot, Rect2i(0, 0, w, h), Vector2i((i % 3) * w, (i / 3) * h))
	sheet.save_png(_out.path_join("sheet.png"))
