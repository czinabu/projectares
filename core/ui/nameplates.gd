extends CanvasLayer
## Names, ranks and health over other players you can see. Hidden behind
## walls, behind you, past `max_distance`, and once someone is down, so a
## nameplate never gives away more than your own eyes would. The exceptions
## are earned: a player on a long streak (`Actor.exposed`) and the Marked show
## to everyone, through walls and at any distance.

const RaidRoster := preload("res://core/ui/raid_roster.gd")
const RenownLedger := preload("res://core/progression/renown_ledger.gd")

## Nameplates show up to this far away, in metres, fading over the last part.
var max_distance := 45.0
var fade_distance := 10.0
## Height above an actor's feet where the plate sits.
var head_offset := 2.15
var plate_size := Vector2(220, 34)
## How strongly a hunted player's plate shows when eyes alone would not see them.
var hunted_alpha := 0.8

var raid: Raid
## The local player: never gets a plate, and does not block the view check.
var viewer: Actor
var _root: Control
var _plates := {}


func setup(p_raid: Raid, p_viewer: Actor = null) -> void:
	raid = p_raid
	viewer = p_viewer if p_viewer != null else p_raid.player


func _ready() -> void:
	layer = 1
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)


func _process(_delta: float) -> void:
	update_plates()


func update_plates() -> void:
	var seen := {}
	var camera := raid.get_viewport().get_camera_3d() if raid != null and is_instance_valid(raid) else null
	if camera != null:
		for actor in RaidRoster.players_in(raid):
			if actor == viewer or actor.is_dead:
				continue
			var at := actor.global_position + Vector3(0, head_offset, 0)
			var alpha := _visibility(camera, actor, at)
			if alpha <= 0.0:
				continue
			var id := actor.get_instance_id()
			seen[id] = true
			var plate: Control = _plates.get(id)
			if plate == null:
				plate = _make_plate()
				_plates[id] = plate
			var label: Label = plate.get_child(0)
			var bar: ProgressBar = plate.get_child(1)
			label.text = plate_text(actor)
			bar.value = actor.health.health / maxf(actor.health.max_health, 0.001) * 100.0
			plate.position = camera.unproject_position(at) - Vector2(plate_size.x * 0.5, plate_size.y)
			plate.modulate.a = alpha
			plate.visible = true
	for id: int in _plates.keys():
		if not seen.has(id):
			_plates[id].queue_free()
			_plates.erase(id)


## Whether a nameplate shows for `actor`: 0 hidden, up to 1 fully shown.
func _visibility(camera: Camera3D, actor: Actor, at: Vector3) -> float:
	if camera.is_position_behind(at):
		return 0.0
	var seen := _sight(camera, actor, at)
	if actor.exposed or actor.marked:
		return maxf(seen, hunted_alpha)
	return seen


## A name with its clan tag in front, when there is one.
static func tagged_name(actor: Actor) -> String:
	return "[%s] %s" % [actor.clan_tag, actor.display_name] if actor.clan_tag != "" else actor.display_name


## The words on a plate: name, rank, and what hunting them would pay.
static func plate_text(actor: Actor) -> String:
	var text := "%s  %s" % [tagged_name(actor), RenownLedger.rank_name(actor.rank)]
	if actor.marked:
		text += "  MARKED"
	if actor.bounty > 0:
		text += "  Bounty %d" % actor.bounty
	return text


func _sight(camera: Camera3D, actor: Actor, at: Vector3) -> float:
	var distance := camera.global_position.distance_to(at)
	if distance > max_distance:
		return 0.0
	var space := raid.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, at)
	query.collision_mask = Actor.LAYER_WORLD
	var exclude: Array[RID] = [actor.get_rid()]
	if viewer != null and is_instance_valid(viewer):
		exclude.append(viewer.get_rid())
	query.exclude = exclude
	if not space.intersect_ray(query).is_empty():
		return 0.0
	return clampf((max_distance - distance) / maxf(fade_distance, 0.001), 0.0, 1.0)


## Shown plates, by actor: { Actor instance id: Control }.
func plates() -> Dictionary:
	return _plates


func _make_plate() -> Control:
	var plate := VBoxContainer.new()
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.size = plate_size
	plate.add_theme_constant_override("separation", 2)
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.theme_type_variation = &"HeaderSmall"
	plate.add_child(label)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(plate_size.x, 5)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(bar)
	_root.add_child(plate)
	return plate
