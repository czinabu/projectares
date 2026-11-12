extends CanvasLayer
## What a safe zone shows you: the prompt for the portal you are standing in
## on screen, and what the player you are looking at is wearing on a tag over
## their head (`tag`). The map's own signs say where you are. UI only. It
## reads the raid and never changes it; using a portal is reported with
## `portal_used` and the game's flow (`core/main.gd`) decides what happens.
##
## Load with `preload("res://core/social/plaza_view.gd")`.

signal portal_used(destination: String)

const RaidRoster := preload("res://core/ui/raid_roster.gd")

## How far away, in metres, another player's gear can be read.
var inspect_range := 16.0
## How close to the crosshair they have to be, in degrees.
var inspect_cone_deg := 9.0

var raid: Raid
## Where each world runs on this server (world id -> port). A gate to a world
## that is missing here is shown as closed.
var routes := {}
## The gear of the player you look at, floating over them.
var tag: Label3D
var _prompt: Label
var _notice: Label
var _notice_left := 0.0


func setup(p_raid: Raid, p_routes := {}) -> void:
	raid = p_raid
	routes = p_routes


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


func _process(delta: float) -> void:
	if raid == null or not is_instance_valid(raid) or raid.player == null or not is_instance_valid(raid.player):
		return
	var me := raid.player
	_notice_left = maxf(0.0, _notice_left - delta)
	_notice.visible = _notice_left > 0.0

	var portal := portal_at(raid, me.global_position)
	_prompt.text = prompt_for(portal, routes)
	if portal != null and Input.is_action_just_pressed("interact"):
		var destination: String = portal.get_meta("destination", "")
		if is_open(destination, routes):
			portal_used.emit(destination)
		else:
			show_notice("That world is not running on this server.")

	var target := inspect_target(raid, me, me.get_eye_position(), me.get_aim_dir(), inspect_range, inspect_cone_deg)
	tag.visible = target != null
	if target != null:
		tag.text = gear_tag(target)
		tag.global_position = target.global_position + Vector3(0, 2.35, 0)


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


static func prompt_for(portal: Node3D, p_routes: Dictionary) -> String:
	if portal == null:
		return ""
	var label: String = portal.get_meta("label", "Go")
	if not is_open(portal.get_meta("destination", ""), p_routes):
		return "%s  (closed: not running on this server)" % label
	return "[E]  %s" % label


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
