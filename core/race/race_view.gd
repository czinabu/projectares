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
## With several tracks each gantry, arch and board carries the meta "track"
## (a track id; none means the first track), and only the run's own track's
## gantry and arches answer it.

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
	# A forming race's countdown on the board.
	_board_in -= delta
	if _board_in <= 0.0:
		_board_in = 0.5
		for t in race.circuits:
			if str(race.heat_view(t.id).get("phase", "")) == "forming":
				_draw_board()
				break
	_was_phase = str(view.get("phase", ""))


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
