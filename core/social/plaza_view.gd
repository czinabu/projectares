extends CanvasLayer
## What a safe zone shows you: the prompt for the portal you are standing in
## on screen, and what the player you are looking at is wearing on a tag over
## their head (`tag`). Over each doorway to a world hangs a sign with how that
## world is doing right now (`heat_signs`). The map's own signs say where you are. UI only. It
## reads the raid and never changes it; using a portal is reported with
## `portal_used` and the game's flow (`core/main.gd`) decides what happens.
##
## Load with `preload("res://core/social/plaza_view.gd")`.

signal portal_used(destination: String)
## A talker offered a job and the player took it (Rook's favour): ask the
## server, through the same contract request as the board.
signal contract_asked(action: String, job_id: String)

const RaidRoster := preload("res://core/ui/raid_roster.gd")
const PlazaLocals := preload("res://core/social/plaza_locals.gd")

## How far away, in metres, another player's gear can be read.
var inspect_range := 16.0
## How close to the crosshair they have to be, in degrees.
var inspect_cone_deg := 9.0

var raid: Raid
## Where each world runs on this server (world id -> port). A gate to a world
## that is missing here is shown as closed.
var routes := {}
## How each world on this server is doing (world id -> `Raid.status()`), as
## the server last told it. Shared with `NetSession.world_status`.
var world_status := {}
## The sign across the top of each world doorway: world id -> Label3D.
var heat_signs := {}
## World ids the new player's tour keeps closed for now (`Onboarding.locks`),
## set by `main.gd`; their gates say so.
var tour_closed: Array = []
## How high up the doorway its sign runs, under the risk line.
var heat_sign_height := 10.25
## How long, in seconds, a pulse takes to run up a gate's panels.
var gate_pulse_time := 1.4
## Seconds you stand in an open world gate before it takes you through
## (Caleb's ask: walk in like a teleporter, with a moment to step back out).
## [F] still goes at once.
var gate_walk_in_time := 1.2
## How often, in seconds, the gates look for someone stepping in.
var gate_check_every := 0.2
## The gear of the player you look at, floating over them.
var tag: Label3D
## The people of the place (`PlazaLocals`), made only where `Look` draws.
var locals: Node3D
## The big screen's live feed of the worlds (`WarRoom`), made only where
## `Look` draws and the map has a "screen_wall".
var war_room: Node3D
## The player's account snapshot from the server, for what a talker offers.
var account := {}
var _prompt: Label
var _notice: Label
var _notice_left := 0.0
## The arch lit because you stand in it.
var _lit_portal: Node3D = null
## Per gate bay (its index in the map's `gate_bays`): how many stood in it at
## the last look, and how long its pulse has left to run.
var _gate_counts := {}
var _gate_pulses := {}
var _gate_check_left := 0.0
## The world gate you are counting down in, how long is left, and the gate
## that already took you (it never fires again until you step out).
var _walk_in_portal: Node3D = null
var _walk_in_left := 0.0
var _walk_in_done: Node3D = null
## The countdown on the gate's face while you stand in it.
var _walk_in_sign: Label3D


func setup(p_raid: Raid, p_routes := {}, p_status := {}) -> void:
	raid = p_raid
	routes = p_routes
	world_status = p_status


func _ready() -> void:
	layer = 2
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_prompt = _label(root, 22, Color(1.0, 0.8, 0.45))
	_place(_prompt, 0.5, 0.5, Vector2(-400, 110), Vector2(800, 32))
	_notice = _label(root, 18, Color(1.0, 1.0, 1.0))
	_place(_notice, 0.5, 0.5, Vector2(-400, 150), Vector2(800, 28))
	tag = Label3D.new()
	tag.name = "GearTag"
	tag.font_size = 40
	tag.pixel_size = 0.004
	tag.outline_size = 10
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	tag.no_depth_test = true
	tag.top_level = true
	tag.visible = false
	add_child(tag)
	if Look.enabled and raid != null and raid.map != null and raid.map.has_method("locals_layout"):
		locals = PlazaLocals.new()
		locals.name = "Locals"
		locals.setup(raid)
		add_child(locals)
	if Look.enabled and raid != null and raid.map != null:
		war_room = WarRoom.new()
		war_room.name = "WarRoom"
		war_room.setup(raid, world_status)
		add_child(war_room)
	refresh_heat()


## Writes each world's news on the sign over its doorway. Call it when
## `world_status` changes.
func refresh_heat() -> void:
	if raid == null or not is_instance_valid(raid) or raid.map == null or not is_inside_tree():
		return
	for node in raid.get_tree().get_nodes_in_group("portal"):
		var portal := node as Node3D
		if portal == null or not raid.map.is_ancestor_of(portal):
			continue
		var destination: String = portal.get_meta("destination", "")
		if not destination.begins_with("world:"):
			continue
		var id := destination.trim_prefix("world:")
		var sign: Label3D = heat_signs.get(id)
		if sign == null:
			sign = Label3D.new()
			sign.name = "Heat_%s" % id
			sign.font_size = 48
			sign.pixel_size = 0.01
			sign.outline_size = 14
			sign.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			sign.width = 7.6 / sign.pixel_size
			sign.vertical_alignment = VERTICAL_ALIGNMENT_TOP
			sign.top_level = true
			add_child(sign)
			heat_signs[id] = sign
		# Flat on the gate's face, just in front of the doorway, under the
		# risk line, and turned the way the gate faces.
		sign.global_transform = Transform3D(portal.global_basis,
				portal.global_position + portal.global_basis * Vector3(0, heat_sign_height, -1.2))
		var status: Dictionary = world_status.get(id, {})
		sign.text = heat_text(status).to_upper()
		sign.modulate = heat_color(float(status.get("war", 0.0)))
		sign.visible = sign.text != ""
	_fill_gates()
	for node in raid.get_tree().get_nodes_in_group("wanted_board"):
		var board := node as Label3D
		if board != null and raid.map.is_ancestor_of(board):
			board.text = wanted_text(world_status)


## What the most-wanted board says: the biggest bounties in every world,
## with the Marked, by name and never by place (`Raid.wanted`).
static func wanted_text(status: Dictionary) -> String:
	var rows: Array[Dictionary] = []
	for id: Variant in status:
		var entry: Variant = status[id]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		for wanted: Variant in entry.get("wanted", []):
			if typeof(wanted) == TYPE_DICTIONARY:
				var row: Dictionary = wanted.duplicate()
				row["world"] = PlazaLocals.world_name(str(id))
				rows.append(row)
	if rows.is_empty():
		return "No bounties out right now.\n\nPlayers on a kill streak get a price on their head.\nTake one down and the bounty is yours, once you get it home."
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.bounty) > int(b.bounty))
	var lines: Array[String] = []
	for i in mini(rows.size(), 6):
		var row: Dictionary = rows[i]
		var who := str(row.name).to_upper()
		if str(row.get("clan", "")) != "":
			who = "[%s] %s" % [row.clan, who]
		var mark := "   THE MARKED" if bool(row.get("marked", false)) else ""
		lines.append("%d   %s   %d scrip   %s%s" % [i + 1, who, int(row.bounty), str(row.world).to_upper(), mark])
	lines.append("")
	lines.append("Take one down and the bounty is yours, once you get it home.")
	return "\n".join(lines)


## One line on how a world is doing, or "" when nothing is known.
static func heat_text(status: Dictionary) -> String:
	if status.is_empty():
		return ""
	var players := int(status.get("players", 0))
	var parts: Array[String] = [str(status.get("level", "Quiet")).to_upper(),
			"1 player" if players == 1 else "%d players" % players]
	if int(status.get("bounty", 0)) > 0:
		parts.append("Top bounty %d" % int(status.bounty))
	if str(status.get("event", "")) != "":
		parts.append(str(status.event))
	if str(status.get("storm", "")) != "":
		parts.append(str(status.storm))
	return "   ".join(parts)


## How full a world is, as a share of its places (0 to 1), from its status:
## at least one slat lights for one player.
static func gate_fill(status: Dictionary, max_players: int, slats: int) -> float:
	var players := int(status.get("players", 0))
	if players <= 0 or max_players <= 0 or slats <= 0:
		return 0.0
	var share := clampf(float(players) / float(max_players), 0.0, 1.0)
	return maxf(share, 1.0 / float(slats))


## Pale when a world is quiet, towards red as its war heats up.
static func heat_color(war: float) -> Color:
	return Color(0.8, 0.9, 1.0).lerp(Color(1.0, 0.3, 0.2), clampf(war, 0.0, 1.0))


func _process(delta: float) -> void:
	if raid == null or not is_instance_valid(raid) or raid.player == null or not is_instance_valid(raid.player):
		return
	var me := raid.player
	_notice_left = maxf(0.0, _notice_left - delta)
	_notice.visible = _notice_left > 0.0

	var portal := portal_at(raid, me.global_position)
	_prompt.text = prompt_for(portal, routes, tour_closed)
	_light_arch(portal)
	_tick_gates(delta)
	var walked := step_walk_in(portal, delta)
	_show_walk_in(portal)
	if walked != "":
		_prompt.text = ""
		portal_used.emit(walked)
	elif _walk_in_portal != null:
		_prompt.text = "Deploying to %s...  step back to stay  ·  [F] go now" % \
				str(portal.get_meta("label", "")).trim_prefix("Deploy to ")
	if portal != null and walked == "" and Input.is_action_just_pressed("interact"):
		var destination: String = portal.get_meta("destination", "")
		if destination.begins_with("talk:"):
			_talk(destination.trim_prefix("talk:"))
		elif is_open(destination, routes):
			_greet(portal)
			_walk_in_portal = null
			_walk_in_done = portal
			portal_used.emit(destination)
		else:
			show_notice("That world is not running on this server.")

	var target := inspect_target(raid, me, me.get_eye_position(), me.get_aim_dir(), inspect_range, inspect_cone_deg)
	tag.visible = target != null
	if target != null:
		tag.text = gear_tag(target)
		tag.global_position = target.global_position + Vector3(0, 2.35, 0)


## Walking into an open world gate takes you through after
## `gate_walk_in_time` seconds; stepping out first cancels it. Returns the
## destination on the step it fires, otherwise "". A gate to a world this
## server lacks, or one the tour keeps closed (`tour_closed`), never
## counts down, and a gate that already fired waits for you to step out.
func step_walk_in(portal: Node3D, delta: float) -> String:
	var destination := str(portal.get_meta("destination", "")) if portal != null else ""
	var walkable := destination.begins_with("world:") and is_open(destination, routes) \
			and not destination.trim_prefix("world:") in tour_closed
	if portal != _walk_in_done:
		_walk_in_done = null
	if not walkable or portal == _walk_in_done:
		_walk_in_portal = null
		return ""
	if portal != _walk_in_portal:
		_walk_in_portal = portal
		_walk_in_left = gate_walk_in_time
	_walk_in_left -= delta
	if _walk_in_left > 0.0:
		return ""
	_walk_in_portal = null
	_walk_in_done = portal
	return destination


## How far the walk-in countdown has run, 0 to 1, or -1 for none.
func walk_in_progress() -> float:
	if _walk_in_portal == null or gate_walk_in_time <= 0.0:
		return -1.0
	return clampf(1.0 - _walk_in_left / gate_walk_in_time, 0.0, 1.0)


## The countdown on the gate's face, under its live line, and the gate's
## glimpse brightening as it runs. Only where `Look` draws.
func _show_walk_in(portal: Node3D) -> void:
	if not Look.enabled:
		return
	if _walk_in_sign == null:
		_walk_in_sign = Label3D.new()
		_walk_in_sign.name = "WalkIn"
		_walk_in_sign.font_size = 64
		_walk_in_sign.pixel_size = 0.01
		_walk_in_sign.outline_size = 20
		_walk_in_sign.top_level = true
		add_child(_walk_in_sign)
	var progress := walk_in_progress()
	_walk_in_sign.visible = progress >= 0.0
	if progress < 0.0 or portal == null:
		return
	_walk_in_sign.global_transform = Transform3D(portal.global_basis,
			portal.global_position + portal.global_basis * Vector3(0, 3.6, -1.2))
	_walk_in_sign.text = "DEPLOYING  %.1f" % maxf(_walk_in_left, 0.0)
	_walk_in_sign.modulate = Color(1.0, 1.0, 1.0).lerp(Color(1.0, 0.85, 0.4), progress)
	var glimpse := portal.get_node_or_null("Glimpse") as GeometryInstance3D
	if glimpse != null:
		glimpse.set_instance_shader_parameter("lit", 1.0 + progress * 0.8)


## Talks to someone of the place: their line goes up over their head.
func _talk(id: String) -> void:
	if locals == null or not is_instance_valid(locals):
		return
	var job: String = locals.talk(id, world_status, account)
	if job != "":
		contract_asked.emit("take", job)


## Whoever works the counter says hello (the map's "keeper" meta).
func _greet(portal: Node3D) -> void:
	var keeper := str(portal.get_meta("keeper", ""))
	if keeper != "" and locals != null and is_instance_valid(locals):
		locals.greet(keeper, world_status, account)


## An arch you stand in lights up (its hidden "Lit" child, and its glimpse
## of the world brightens), and goes dark again when you step out. In place
## of the old glowing pads on the floor.
func _light_arch(portal: Node3D) -> void:
	if portal == _lit_portal:
		return
	if _lit_portal != null and is_instance_valid(_lit_portal):
		var old := _lit_portal.get_node_or_null("Lit") as Node3D
		if old != null:
			old.visible = false
		var old_glimpse := _lit_portal.get_node_or_null("Glimpse") as GeometryInstance3D
		if old_glimpse != null:
			old_glimpse.set_instance_shader_parameter("lit", 0.0)
	_lit_portal = portal
	if portal != null:
		var lit := portal.get_node_or_null("Lit") as Node3D
		if lit != null:
			lit.visible = true
		var glimpse := portal.get_node_or_null("Glimpse") as GeometryInstance3D
		if glimpse != null:
			glimpse.set_instance_shader_parameter("lit", 1.0)


## The map's gate bays (`gate_bays`), or none.
func _gate_bays() -> Array:
	if raid == null or not is_instance_valid(raid) or raid.map == null or not raid.map.has_method("gate_bays"):
		return []
	return raid.map.gate_bays()


## Fills the panels beside each open gate with how many are in its world.
## View only: the panels exist only where `Look` draws.
func _fill_gates() -> void:
	if not Look.enabled:
		return
	for bay: Dictionary in _gate_bays():
		var id := str(bay.get("world_id", ""))
		if id == "":
			continue
		var status: Dictionary = world_status.get(id, {})
		var slats := clampi(int(bay.get("max_players", 0)), 8, 24)
		var fill := gate_fill(status, int(bay.get("max_players", 0)), slats)
		for meter: Variant in bay.get("meters", []):
			if is_instance_valid(meter):
				(meter as GeometryInstance3D).set_instance_shader_parameter("filled", fill)


## Who stands in each gate, a few times a second: when someone steps into
## one, a pulse runs up the panels and fins either side of it, so a squad
## heading out shows from across the plaza. One pass over the players for
## every gate (a handful), and only where `Look` draws.
func _tick_gates(delta: float) -> void:
	if not Look.enabled:
		return
	var bays := _gate_bays()
	if bays.is_empty():
		return
	_gate_check_left -= delta
	if _gate_check_left <= 0.0:
		_gate_check_left = gate_check_every
		var players := RaidRoster.players_in(raid)
		for i in bays.size():
			var portal: Variant = bays[i].get("portal")
			if portal == null or not is_instance_valid(portal):
				continue
			var radius: float = (portal as Node3D).get_meta("radius", 3.0)
			var count := 0
			for other: Variant in players:
				if not is_instance_valid(other) or (other as Actor).is_dead:
					continue
				var gap: Vector3 = (other as Actor).global_position - (portal as Node3D).global_position
				gap.y = 0.0
				if gap.length() <= radius:
					count += 1
			if count > int(_gate_counts.get(i, 0)):
				_gate_pulses[i] = gate_pulse_time
			_gate_counts[i] = count
	for i: int in _gate_pulses.keys():
		var left: float = float(_gate_pulses[i]) - delta
		var at := -1.0 if left <= 0.0 else 1.0 - left / gate_pulse_time
		var parts: Array = []
		parts.append_array(bays[i].get("meters", []))
		parts.append_array(bays[i].get("fins", []))
		for part: Variant in parts:
			if is_instance_valid(part):
				(part as GeometryInstance3D).set_instance_shader_parameter("pulse", at)
		if left <= 0.0:
			_gate_pulses.erase(i)
		else:
			_gate_pulses[i] = left


## A line shown for a few seconds under the prompt.
func show_notice(text: String) -> void:
	_notice.text = text
	_notice_left = 4.0


## The portal marker `at` stands in, or null.
static func portal_at(p_raid: Raid, at: Vector3) -> Node3D:
	if p_raid == null or p_raid.map == null:
		return null
	var best: Node3D = null
	var best_distance := INF
	for node in p_raid.get_tree().get_nodes_in_group("portal"):
		var portal := node as Node3D
		if portal == null or not p_raid.map.is_ancestor_of(portal):
			continue
		var gap := portal.global_position - at
		if absf(gap.y) > 3.0:
			continue
		gap.y = 0.0
		var radius: float = portal.get_meta("radius", 3.0)
		if gap.length() <= radius and gap.length() < best_distance:
			best = portal
			best_distance = gap.length()
	return best


## False for a gate to a world this server does not run.
static func is_open(destination: String, p_routes: Dictionary) -> bool:
	return not destination.begins_with("world:") or p_routes.has(destination.trim_prefix("world:"))


static func prompt_for(portal: Node3D, p_routes: Dictionary, p_tour_closed: Array = []) -> String:
	if portal == null:
		return ""
	var label: String = portal.get_meta("label", "Go")
	var destination := str(portal.get_meta("destination", ""))
	if not is_open(destination, p_routes):
		return "%s  (closed: not running on this server)" % label
	if destination.trim_prefix("world:") in p_tour_closed:
		return "%s  (closed: full loot, finish the basics first)" % label
	return "[F]  %s" % label


## The other player closest to where `viewer` is looking, within range and
## not behind a wall, or null.
static func inspect_target(p_raid: Raid, viewer: Actor, eye: Vector3, aim: Vector3, reach: float,
		cone_deg: float) -> Actor:
	var best: Actor = null
	var best_angle := deg_to_rad(cone_deg)
	for other in RaidRoster.players_in(p_raid):
		if other == viewer or other.is_dead or not is_instance_valid(other):
			continue
		var chest := other.global_position + Vector3(0, 1.1, 0)
		var to := chest - eye
		if to.length() > reach or to.length() < 0.01:
			continue
		var angle := aim.angle_to(to)
		if angle >= best_angle:
			continue
		var query := PhysicsRayQueryParameters3D.create(eye, chest, Actor.LAYER_WORLD)
		if not viewer.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			continue
		best = other
		best_angle = angle
	return best


## What a player is showing off: every piece of gear, best first.
static func gear_lines(actor: Actor) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in actor.gear_items:
		out.append({"id": id, "name": ItemDB.item_name(id), "rarity": ItemDB.item_rarity(id),
				"rarity_name": ItemDB.rarity_name(id), "value": ItemDB.item_value(id)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.rarity > b.rarity if a.rarity != b.rarity else a.value > b.value)
	return out


## The tag's text: who it is, their gear best first, and what it is worth.
static func gear_tag(actor: Actor) -> String:
	var lines := gear_lines(actor)
	var text := actor.display_name.to_upper()
	if actor.clan_tag != "":
		text = "[%s] %s" % [actor.clan_tag, text]
	var worth := 0
	for line in lines:
		worth += int(line.value)
		text += "\n%s  (%s)" % [line.name, line.rarity_name]
	if lines.is_empty():
		text += "\nNothing equipped"
	return text + "\nKit worth %d" % worth


func _label(root: Control, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 5)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(label)
	return label


func _place(node: Control, anchor_x: float, anchor_y: float, offset: Vector2, size: Vector2) -> void:
	node.anchor_left = anchor_x
	node.anchor_right = anchor_x
	node.anchor_top = anchor_y
	node.anchor_bottom = anchor_y
	node.offset_left = offset.x
	node.offset_top = offset.y
	node.offset_right = offset.x + size.x
	node.offset_bottom = offset.y + size.y
