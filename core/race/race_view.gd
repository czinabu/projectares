class_name RaceView
extends Node

const RaceLeague := preload("res://core/race/race_league.gd")

## The local racer's view of a `Race` (DESIGN.md section 9), all in the
## world: the gantry's lights counting the run down, the split written big
## on each checkpoint's arch as you pass it (green ahead of your best, amber
## behind), the best laps and your friends' on the pit board, and the ghost
## you picked on the race icon (`ghost_pick`: your best lap on this machine,
## a friend's, the board leader's) running beside you. Reads only
## `Race.view_run`, `Race.board`, `Race.friend_bests` and the ghosts the
## race was sent (`Race.want_ghost`, `ghost_shown`), so it is the same solo
## and online, and changes nothing in the race. Never made on a headless
## server. Solo, the board starts with the profile's best laps.
##
## Race control's desks are here too: standing at one shows what it does
## and how the next race stands (its "Status" label and a prompt), and the
## interact key signs up (`Race.ask("signup:...")`, the race decides) or,
## at a watch desk, watches: the view follows the racers on that track
## from behind (`watching`, `watching_changed`), the wheel picks another,
## and the interact key or Esc comes back. Watching is a view only; `Main`
## holds the player still while it lasts.
##
## With several tracks each gantry, arch and board carries the meta "track"
## (a track id; none means the first track), and only the run's own track's
## gantry and arches answer it.

## The view went to watching a track's racers, or came back.
signal watching_changed(on: bool)

## Seconds a split stays on an arch.
const SPLIT_TIME := 4.0
const AHEAD := Color(0.35, 1.0, 0.55)
const BEHIND := Color(1.0, 0.72, 0.25)
const NEUTRAL := Color(0.6, 0.9, 1.0)
const LIGHT_ON := Color(1.0, 0.12, 0.08)
const LIGHT_GO := Color(0.3, 1.0, 0.45)
const LIGHT_OFF := Color(0.15, 0.05, 0.05)
## Friends' best laps shown under a board's own.
const FRIENDS_SHOWN := 3
const GHOST_COLOR := Color(0.45, 0.85, 1.0)

var race: Race
## Which ghost is shown (`Race.GHOST_PICKS`, the race icon's ghost pick).
var ghost_pick := "mine"

var _lights: Array[MeshInstance3D] = []
var _light_mats: Array[StandardMaterial3D] = []
var _light_tracks: Array[String] = []
var _splits := {}       # "track:gate" -> Label3D
var _split_left := {}   # "track:gate" -> seconds still shown
var _boards: Array[Label3D] = []
var _ghost_node: Node3D
var _ghost_machine := ""
## The track being watched from a watch desk, or "".
var watching := ""
var _desks: Array[Node3D] = []
var _benches: Array[Node3D] = []
## Online: the account's racing state (`RaceLeague`), for the pit benches'
## words; `Main` sets it. Solo the race's own is read.
var league_source := Callable()
var _desk_in := 0.0
var _hud: CanvasLayer
var _prompt: Label
var _caption: Label
var _camera: Camera3D
var _previous: Camera3D
var _watched: Node3D
var _watch_list: Array = []
var _watch_pick := 0
var _list_in := 0.0
## The frame watching stopped on, so the same press does not start it again.
var _stopped_frame := -1
var _go_flash := 0.0
var _board_in := 0.0
var _was_phase := ""


func setup(p_race: Race) -> void:
	race = p_race
	name = "RaceView"


func _ready() -> void:
	if race == null or race.track == null:
		return
	for node: Node in race.map.find_children("*", "", true, false) if race.map != null else []:
		if node.is_in_group("race_light") and node is MeshInstance3D:
			_lights.append(node)
		elif node.is_in_group("race_gate"):
			var label := node.get_node_or_null("Split") as Label3D
			if label != null:
				_splits[_key(_track_of(node), int(node.get_meta("gate", 0)))] = label
		elif node.is_in_group("race_board") and node is Label3D:
			_boards.append(node)
		elif node.is_in_group("race_desk") and node is Node3D:
			_desks.append(node)
		elif node.is_in_group("race_tune") and node is Node3D:
			_benches.append(node)
	_lights.sort_custom(func(a: MeshInstance3D, b: MeshInstance3D) -> bool:
		return int(a.get_meta("index", 0)) < int(b.get_meta("index", 0)))
	for light in _lights:
		_light_tracks.append(_track_of(light))
		# Each light gets a material of its own to light.
		var mat: StandardMaterial3D = light.mesh.material.duplicate() if light.mesh.material is StandardMaterial3D \
				else StandardMaterial3D.new()
		mat.emission_enabled = true
		light.material_override = mat
		_light_mats.append(mat)
	race.run_changed.connect(_on_run_changed)
	race.board_changed.connect(_draw_board)
	race.heat_changed.connect(_draw_board)
	if race.mode != Raid.Mode.CLIENT:
		# Solo: your saved bests are the board's first times.
		_seed_board()
	_draw_board()
	_make_hud()


## The track a gantry light, arch or board belongs to.
func _track_of(node: Node) -> String:
	return str(node.get_meta("track", race.track.id))


static func _key(track_id: String, gate: int) -> String:
	return "%s:%d" % [track_id, gate]


## The track the local racer's run is on (the first track with none).
func _run_track(view: Dictionary) -> String:
	return str(view.get("track", race.track.id))


func _process(delta: float) -> void:
	if race == null or race.track == null:
		return
	var view := race.view_run()
	_update_lights(view, delta)
	for g: String in _split_left.keys():
		_split_left[g] -= delta
		if _split_left[g] <= 0.0:
			_split_left.erase(g)
			if _splits.has(g):
				_splits[g].text = ""
	_update_ghost(view)
	_update_desks(delta)
	_update_watch(delta)
	# A forming race's countdown on the board.
	_board_in -= delta
	if _board_in <= 0.0:
		_board_in = 0.5
		for t in race.circuits:
			if str(race.heat_view(t.id).get("phase", "")) == "forming":
				_draw_board()
				break
	_was_phase = str(view.get("phase", ""))


# --- Race control's desks and watching --------------------------------------------

func _make_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 2
	add_child(_hud)
	_prompt = _label(22, Color(1.0, 0.8, 0.45), 110.0)
	_caption = _label(24, Color(0.75, 0.95, 1.0), -160.0, 1.0)


func _label(font_size: int, color: Color, y: float, anchor_y := 0.5) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 5)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.anchor_left = 0.5
	label.anchor_right = 0.5
	label.anchor_top = anchor_y
	label.anchor_bottom = anchor_y
	label.offset_left = -500.0
	label.offset_right = 500.0
	label.offset_top = y
	label.offset_bottom = y + 64.0
	_hud.add_child(label)
	return label


## The desk the local player stands at, or null.
func desk_here() -> Node3D:
	var me := race.player
	if me == null or not is_instance_valid(me) or me.vehicle != null or me.is_dead:
		return null
	for desk in _desks:
		if Vector2(desk.global_position.x - me.global_position.x,
				desk.global_position.z - me.global_position.z).length() <= Race.DESK_REACH:
			return desk
	return null


## The pit bench the local player stands at, or null.
func bench_here() -> Node3D:
	var me := race.player
	if me == null or not is_instance_valid(me) or me.is_dead:
		return null
	for bench in _benches:
		if Vector2(bench.global_position.x - me.global_position.x,
				bench.global_position.z - me.global_position.z).length() <= Race.DESK_REACH:
			return bench
	return null


## The local racer's league state: the race's own solo, the account's online.
func my_league() -> Dictionary:
	if race.mode != Raid.Mode.CLIENT and race.player != null and is_instance_valid(race.player):
		var state := race.state_for(race.player)
		if state != null:
			return race.tune_state(state.owner)
	if league_source.is_valid():
		return RaceLeague.clean(league_source.call())
	return RaceLeague.fresh()


## A pit bench's words: the machine, its kits (the fitted one marked) and
## the league each locked one opens in.
static func bench_text(machine: String, league: Dictionary) -> String:
	var text := "%s TUNING" % ("SCRAPPER" if machine == "bike_scrapper" else _machine_tag(machine))
	var fitted := RaceLeague.kit_of(league, machine)
	for kit in RaceLeague.KIT_ORDER:
		if RaceLeague.kit_unlocked(league, kit):
			text += "\n%s %s" % ["▶" if kit == fitted else "  ", RaceLeague.kit_name(kit)]
		else:
			text += "\n   %s · %s" % [RaceLeague.kit_name(kit),
					RaceLeague.league_name(int(RaceLeague.KITS[kit].league))]
	return text


## The prompt at a pit bench.
static func bench_prompt(machine: String, league: Dictionary) -> String:
	if RaceLeague.kits_for(league).size() < 2:
		return "Tuning kits open in the %s league" % RaceLeague.league_name(1)
	var next := RaceLeague.next_kit(league, machine)
	return "%s  Fit %s: %s" % [key(), RaceLeague.kit_name(next), str(RaceLeague.KITS[next].about).to_lower()]


## The interact key as the player has it bound, for the desks' and
## benches' prompts ("[F]"): never a letter of its own, which once said E
## (free look) and left the desks doing nothing (Caleb's report).
static func key() -> String:
	if InputMap.has_action("interact"):
		for event: InputEvent in InputMap.action_get_events("interact"):
			if event is InputEventKey:
				var code := (event as InputEventKey).physical_keycode
				if code == KEY_NONE:
					code = (event as InputEventKey).keycode
				return "[%s]" % OS.get_keycode_string(code)
	return "[F]"


## What a desk says now: its own words and the next race there.
static func desk_text(title: String, heat: Dictionary) -> String:
	match str(heat.get("phase", "")):
		"forming":
			var since := (Time.get_ticks_msec() - int(heat.get("made", 0))) / 1000.0
			return "%s\nNext race %s · %d/%d riders" % [title, Race.format_countdown(float(heat.get("starts_in", 0.0)) - since),
					int(heat.get("people", 0)), Race.GRID_SIZE]
		"racing":
			if bool(heat.get("ambient", false)):
				return "%s\nAI racing now · sign up to race them" % title
			return "%s\nRace on · %d on the grid" % [title, int(heat.get("field", 0))]
	return "%s\nNo race yet: start one" % title


## The prompt at a desk.
static func desk_prompt(machine: String, heat: Dictionary) -> String:
	if machine == "":
		return "%s  Watch the racers here" % key()
	if bool(heat.get("ambient", false)):
		# The AI's own race: signing up calls its field back to the grid.
		return "%s  Race the AI: they line up on the grid" % key()
	if str(heat.get("phase", "")) == "racing":
		return "A race is on: the next forms once it is over"
	if str(heat.get("phase", "")) == "forming":
		return "%s  Join the next race on the grid" % key()
	return "%s  Start the next race (AI fill the grid)" % key()


func _update_desks(delta: float) -> void:
	_desk_in -= delta
	if _desk_in <= 0.0:
		_desk_in = 0.5
		for desk in _desks:
			var label := desk.get_node_or_null("Status") as Label3D
			if label == null:
				continue
			if not desk.has_meta("title"):
				desk.set_meta("title", label.text)
			var heat := race.heat_view(str(desk.get_meta("track", "")))
			label.text = desk_text(str(desk.get_meta("title")), heat) if str(desk.get_meta("machine", "")) != "" \
					else str(desk.get_meta("title"))
		var league := my_league()
		for bench in _benches:
			var label := bench.get_node_or_null("Status") as Label3D
			if label != null:
				label.text = bench_text(str(bench.get_meta("machine", "")), league)
	var desk := desk_here() if watching == "" else null
	var bench := bench_here() if watching == "" and desk == null else null
	if desk != null:
		_prompt.text = desk_prompt(str(desk.get_meta("machine", "")), race.heat_view(str(desk.get_meta("track", ""))))
	elif bench != null:
		_prompt.text = bench_prompt(str(bench.get_meta("machine", "")), my_league())
	else:
		_prompt.text = ""
	if (desk != null or bench != null) and Input.is_action_just_pressed("interact") \
			and not get_viewport().gui_get_focus_owner() and Engine.get_process_frames() != _stopped_frame:
		if desk != null:
			use_desk(desk)
		else:
			race.ask("tune:%s" % str(bench.get_meta("machine", "")))
			_desk_in = 0.3


## Uses a desk: signs up for its race, or watches its track.
func use_desk(desk: Node3D) -> void:
	var track_id := str(desk.get_meta("track", ""))
	var machine := str(desk.get_meta("machine", ""))
	if machine == "":
		watch(track_id)
	else:
		race.ask("signup:%s:%s" % [track_id, machine])


## Starts (a track id) or stops ("") watching a track's racers.
func watch(track_id: String) -> void:
	if track_id == watching:
		return
	watching = track_id
	_watched = null
	_watch_pick = 0
	_list_in = 0.0
	if track_id != "":
		if _camera == null:
			_camera = Camera3D.new()
			_camera.name = "WatchCamera"
			_camera.top_level = true
			_camera.fov = 70.0
			_camera.far = 4000.0
			add_child(_camera)
		_previous = get_viewport().get_camera_3d()
		var desk_at := race.track_by_id(track_id).pit_spot()
		_camera.global_transform = Transform3D(Basis.looking_at(Vector3.FORWARD, Vector3.UP), desk_at + Vector3(0, 12, 20))
		_camera.make_current()
	else:
		if _previous != null and is_instance_valid(_previous) and _previous.is_inside_tree():
			_previous.make_current()
		_caption.text = ""
		_stopped_frame = Engine.get_process_frames()
	watching_changed.emit(track_id != "")


## Who can be watched on a track: the riders on its road, people first.
func watch_list(track_id: String) -> Array:
	var rt := race.track_by_id(track_id)
	var people: Array = []
	var ai: Array = []
	for v: Variant in race.vehicles:
		if not is_instance_valid(v):
			continue
		var vehicle := v as Node3D
		var rider: Variant = vehicle.get("rider")
		if rider == null or not is_instance_valid(rider) or rider == race.player or race.track_near(vehicle.global_position) != rt:
			continue
		(ai if (rider as Node).has_meta("race_ai") else people).append(vehicle)
	return people + ai


func _update_watch(delta: float) -> void:
	if watching == "":
		return
	_list_in -= delta
	if _list_in <= 0.0 or _watched == null or not is_instance_valid(_watched) or _watched.get("rider") == null:
		_list_in = 1.0
		_watch_list = watch_list(watching)
		if _watched == null or not is_instance_valid(_watched) or _watched not in _watch_list:
			_watched = _watch_list[clampi(_watch_pick, 0, _watch_list.size() - 1)] if not _watch_list.is_empty() else null
	var rt := race.track_by_id(watching)
	if _watched == null:
		_caption.text = "WATCHING %s · nobody on the track yet\nE or Esc: back" % rt.display_name.to_upper()
		return
	var rider: Actor = _watched.get("rider")
	var velocity: Vector3 = _watched.get("velocity") if _watched.get("velocity") is Vector3 else Vector3.ZERO
	var back := -_watched.global_basis.z
	if Vector2(velocity.x, velocity.z).length() > 3.0:
		back = Vector3(velocity.x, 0, velocity.z).normalized()
	var want := _watched.global_position - back * 9.0 + Vector3(0, 3.6, 0)
	var weight := 1.0 - exp(-delta * 4.0)
	_camera.global_position = _camera.global_position.lerp(want, weight)
	var look := _watched.global_position + Vector3(0, 1.2, 0) + back * 4.0
	if _camera.global_position.distance_to(look) > 0.5:
		_camera.look_at(look, Vector3.UP)
	_caption.text = "WATCHING %s · %s · %s  (%d/%d)\nWheel: another racer · E or Esc: back" % [rt.display_name.to_upper(),
			rider.display_name if is_instance_valid(rider) else "?", _machine_tag(str(_watched.get("item_id"))),
			_watch_list.find(_watched) + 1, _watch_list.size()]


## Another racer to watch (`step` +1 or -1).
func watch_next(step: int) -> void:
	if _watch_list.is_empty():
		return
	var at := _watch_list.find(_watched)
	_watch_pick = posmod(at + step, _watch_list.size())
	_watched = _watch_list[_watch_pick]


func _input(event: InputEvent) -> void:
	if watching == "":
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			watch_next(1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1)
			get_viewport().set_input_as_handled()
	elif (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE) \
			or event.is_action_pressed("interact"):
		watch("")
		get_viewport().set_input_as_handled()


# --- The gantry -----------------------------------------------------------------

func _update_lights(view: Dictionary, delta: float) -> void:
	var lit := Race.lights_lit(view)
	var phase := str(view.get("phase", ""))
	if phase == "racing" and _was_phase == "grid":
		_go_flash = 1.2
	_go_flash = maxf(_go_flash - delta, 0.0)
	var on := _run_track(view)
	for k in _light_mats.size():
		var mat := _light_mats[k]
		var color := LIGHT_OFF
		var energy := 0.2
		var index := int(_lights[k].get_meta("index", 0))
		var mine := _light_tracks[k] == on
		if mine and _go_flash > 0.0:
			color = LIGHT_GO
			energy = 4.0
		elif mine and index < lit:
			color = LIGHT_ON
			energy = 5.0
		mat.albedo_color = color
		mat.emission = color
		mat.emission_energy_multiplier = energy


# --- Splits and the board ---------------------------------------------------------

func _on_run_changed(actor: Actor) -> void:
	if actor != race.player:
		return
	var view := race.view_run()
	var gate := _key(_run_track(view), int(view.get("last_gate", -1)))
	if int(view.get("last_gate", -1)) <= 0 or not _splits.has(gate) or str(view.get("phase", "")) != "racing":
		return
	var delta := float(view.get("last_delta", NAN))
	var label: Label3D = _splits[gate]
	if is_nan(delta):
		label.text = Race.format_time(_split_time(view))
		label.modulate = NEUTRAL
	else:
		label.text = Race.format_delta(delta)
		label.modulate = AHEAD if delta < 0.0 else BEHIND
	_split_left[gate] = SPLIT_TIME


## The time at the gate just passed: the lap's time when it changed.
func _split_time(view: Dictionary) -> float:
	return Race.run_lap_time(view)


func _draw_board() -> void:
	for board in _boards:
		var on := _track_of(board)
		board.text = board_text(race.board_for(on), race.heat_view(on), race.friends_on(on))


## A board's rows as its screen shows them: a live race forming or running
## on top, its results while they are up, else the best laps.
## Your friends' best laps there follow under FRIENDS (`FRIENDS_SHOWN`).
static func board_text(rows: Array[Dictionary], heat := {}, friends: Array[Dictionary] = []) -> String:
	var text := heat_text(heat)
	if str(heat.get("phase", "")) == "done":
		return text
	if text != "":
		text += "\n"
	if rows.is_empty():
		text = "No times yet\nTake a machine from the pit bays\n"
	for i in rows.size():
		var row: Dictionary = rows[i]
		text += "%d   %-14s %-8s %s\n" % [i + 1, str(row.name).left(14), _machine_tag(str(row.machine)),
				Race.format_time(float(row.time))]
	if not friends.is_empty():
		text += "FRIENDS\n"
		for row: Dictionary in friends.slice(0, FRIENDS_SHOWN):
			text += "    %-14s %-8s %s\n" % [str(row.name).left(14), _machine_tag(str(row.machine)),
					Race.format_time(float(row.time))]
	return text.strip_edges(false, true)


## A live race's lines on the board, or "" with none.
static func heat_text(heat: Dictionary) -> String:
	match str(heat.get("phase", "")):
		"forming":
			var since := (Time.get_ticks_msec() - int(heat.get("made", 0))) / 1000.0
			return "NEXT RACE %s · %d/%d riders, AI fill the rest\n" % [
					Race.format_countdown(float(heat.get("starts_in", 0.0)) - since), int(heat.get("people", 0)),
					Race.GRID_SIZE]
		"racing":
			if bool(heat.get("ambient", false)):
				return "AI RACE ON · %s league · %d riders · sign up to race them\n" % [
						str(heat.get("league", "Rookie")), int(heat.get("field", 0))]
			return "RACE ON · %s league · %d on the grid\n" % [str(heat.get("league", "Rookie")),
					int(heat.get("field", 0))]
		"done":
			var text := "RESULTS\n"
			for row: Dictionary in heat.get("results", []):
				var time := float(row.get("time", -1.0))
				text += "%d   %-14s %-8s %s\n" % [int(row.get("place", 0)), str(row.get("name", "?")).left(14),
						_machine_tag(str(row.get("machine", ""))), Race.format_time(time) if time >= 0.0 else "DNF"]
			return text.strip_edges(false, true)
	return ""


static func _machine_tag(id: String) -> String:
	match id:
		"bike_scrapper":
			return "SCRAP"
		"bike_raider":
			return "RAIDER"
	return ItemDB.item_name(id).left(8).to_upper()


# --- Ghosts ---------------------------------------------------------------------

## The ghost picked for the local racer's run, asked for when first
## needed: {"name", "machine", "lap", "ghost"} or {} (none, or on its way).
func shown_ghost(view: Dictionary) -> Dictionary:
	var machine := str(view.get("machine", ""))
	if view.is_empty() or ghost_pick == "off" or machine == "":
		return {}
	var on := _run_track(view)
	race.want_ghost(ghost_pick, on, machine)
	return race.ghost_shown(ghost_pick, on, machine)


func _update_ghost(view: Dictionary) -> void:
	var shown := shown_ghost(view) if str(view.get("phase", "")) == "racing" else {}
	if shown.is_empty():
		if _ghost_node != null:
			_ghost_node.visible = false
		return
	var ghost: RaceGhost = shown.ghost
	if _ghost_node == null or _ghost_machine != ghost.machine:
		if _ghost_node != null:
			_ghost_node.queue_free()
		_ghost_node = build_ghost(ghost.machine)
		_ghost_machine = ghost.machine
		race.add_child(_ghost_node)
	var time := Race.run_lap_time(view)
	_ghost_node.visible = time <= ghost.lap_time
	_ghost_node.global_transform = ghost.sample(time)


## A machine and rider in see-through hard light: the ghost of a lap.
static func build_ghost(machine: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Ghost"
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(GHOST_COLOR, 0.4)
	mat.emission_enabled = true
	mat.emission = GHOST_COLOR
	mat.emission_energy_multiplier = 1.4
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var source = preload("res://core/vehicle/vehicle.gd").new()
	source.setup(machine)
	var body: Node3D = source.build_visual()
	var seat: Vector3 = source.seat_point
	source.free()
	root.add_child(body)
	# The rider: a plain figure leaning over the bars.
	var torso := MeshInstance3D.new()
	torso.mesh = CapsuleMesh.new()
	torso.mesh.radius = 0.22
	torso.mesh.height = 0.85
	torso.position = seat + Vector3(0, 0.38, -0.12)
	torso.rotation.x = -0.6
	root.add_child(torso)
	var head := MeshInstance3D.new()
	head.mesh = SphereMesh.new()
	head.mesh.radius = 0.16
	head.mesh.height = 0.32
	head.position = seat + Vector3(0, 0.82, -0.42)
	root.add_child(head)
	for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = mat
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


func _seed_board() -> void:
	var name := race.player.display_name if race.player != null and is_instance_valid(race.player) else "You"
	if race.league_bank is Race.ProfileLeagueBank:
		(race.league_bank as Race.ProfileLeagueBank).load_kept()
	var state := race.league_bank.state("") if race.league_bank != null else RaceLeague.fresh()
	var bests: Dictionary = state.get("bests", {})
	for key: String in bests:
		race.add_record(name, key.get_slice("|", 1), float(bests[key]), "", key.get_slice("|", 0))
