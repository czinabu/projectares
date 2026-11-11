extends CanvasLayer
## The screen layer for a safe zone: who is here, what the player you are
## looking at is wearing, and the portal you are standing in. UI only. It
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
var _banner: Label
var _prompt: Label
var _card: PanelContainer
var _card_text: RichTextLabel
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
	_banner = _label(root, 15, Color(0.6, 0.95, 0.75))
	_place(_banner, 0.5, 0.0, Vector2(-300, 50), Vector2(600, 22))
	_prompt = _label(root, 22, Color(1.0, 0.8, 0.45))
	_place(_prompt, 0.5, 0.5, Vector2(-400, 110), Vector2(800, 32))
	_notice = _label(root, 18, Color(1.0, 1.0, 1.0))
	_place(_notice, 0.5, 0.5, Vector2(-400, 150), Vector2(800, 28))
	_card = PanelContainer.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.visible = false
	root.add_child(_card)
	_place(_card, 1.0, 0.5, Vector2(-360, -150), Vector2(330, 300))
	_card_text = RichTextLabel.new()
	_card_text.bbcode_enabled = true
	_card_text.fit_content = true
	_card_text.scroll_active = false
	_card_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(_card_text)


func _process(delta: float) -> void:
	if raid == null or not is_instance_valid(raid) or raid.player == null or not is_instance_valid(raid.player):
		return
	var me := raid.player
	var count := RaidRoster.players_in(raid).size()
	_banner.text = "SAFE ZONE   weapons locked   %d %s here" % [count, "player" if count == 1 else "players"]
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
	_card.visible = target != null
	if target != null:
		_card_text.text = gear_card(target)


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


static func gear_card(actor: Actor) -> String:
	var lines := gear_lines(actor)
	var text := "[font_size=22][b]%s[/b][/font_size]\n" % actor.display_name
	var worth := 0
	for line in lines:
		worth += int(line.value)
		text += "[color=#%s]%s[/color]  [color=#888888]%s[/color]\n" % [
				ItemDB.RARITY_COLORS[line.rarity].to_html(false), line.name, line.rarity_name]
	if lines.is_empty():
		text += "[color=#888888]Nothing equipped[/color]\n"
	text += "\n[color=#bbbbbb]Kit worth %d[/color]" % worth
	return text


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
