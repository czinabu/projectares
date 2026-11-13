class_name HomeBase
extends Node3D
## A player's home base: a room you walk around in, with everything in your
## stash on show. Every weapon hangs on one rack in the armory, an alcove off
## the left of the room with the gunsmith bench in its middle and the locker
## at its entrance. The main room holds armor and flight rigs along the back
## wall, the garage, the launch pad, ability chips, and shelves for supplies
## and loot.
##
## The base is a view of a stash, never a second store. `show_gear` is given a
## stash and a loadout (the local `Profile`'s, or the account a server keeps)
## and rebuilds the displays. Using a display asks for a loadout change through
## `equip_requested`; whoever owns the stash decides and calls `show_gear` again.
##
## Like `Raid`, this has no camera, HUD or input code. `player` is an `Actor`
## driven through its `ActorCommand`, so it runs headless.

## The player used a piece of gear on show. `item_id` is "" to take the slot's
## item off.
signal equip_requested(slot: String, item_id: String)
## The player used the door.
signal leave_requested
## The player used a station (a key of `STATIONS`): the locker, the mastery
## bench, the wardrobe, the records board, the trader, the launch pad or the
## uplink, or the arena gate. Whoever owns the base opens what it offers.
signal station_requested(station: String)
## The displays were rebuilt.
signal gear_shown
## The player suited up: `player` is now a new actor wearing the loadout.
## Whoever drives the player (a controller, a camera) takes it over.
signal player_replaced(actor: Actor)

const BaseLayout := preload("res://core/base/base_layout.gd")
const VehicleScript := preload("res://core/vehicle/vehicle.gd")

# Room tuning.
var room_size := Vector3(24.0, 6.0, 18.0)
## The armory alcove off the room's left wall (-X): how deep it goes (x), how
## high (y) and how wide (z). It is centred on the wall.
var armory_size := Vector3(7.0, 6.0, 10.0)
## How wide the way into the armory is, through the room's left wall.
var armory_opening := 8.0
var spawn_point := Vector3(0.0, 0.1, 5.5)
## Weapons hang a little larger than life so they read from across the room.
var weapon_scale := 1.5

## Whose base this is, shown on the HUD. "" for your own.
var owner_name := ""
## True when visiting someone else's base: gear can be looked at, not equipped.
var read_only := false
## What the door says it does. Whoever owns the base sets it to where the door
## leads from here (online, back to the plaza, home from a visit).
var door_text := "Head out: play online"

## Where each station stands and which way it faces (local +Z into the room),
## with its title and prompt. The launch pad stands in the middle, the locker
## beside the way into the armory, the wardrobe and records along the left
## wall nearer the door, and the rest on the open floor right of the garage.
const STATIONS := {
	"launch": {"prompt": "Deploy", "title": "Launch pad", "at": Vector3(0.0, 0.0, 2.6), "yaw": 0.0, "color": Color(1.0, 0.55, 0.2)},
	"locker": {"prompt": "Pick your loadout", "title": "Locker", "at": Vector3(-11.1, 0.0, -5.4), "yaw": PI / 2.0, "color": Color(0.45, 0.75, 1.0)},
	"wardrobe": {"prompt": "Change how you look", "title": "Wardrobe", "at": Vector3(-11.1, 0.0, 5.3), "yaw": PI / 2.0, "color": Color(0.85, 0.6, 1.0)},
	"records": {"prompt": "Read your record and stash", "title": "Records", "at": Vector3(-11.1, 0.0, 7.2), "yaw": PI / 2.0, "color": Color(0.9, 0.9, 0.85)},
	"mastery": {"prompt": "Pick mastery variants", "title": "Mastery bench", "at": Vector3(6.6, 0.0, 0.9), "yaw": -PI / 2.0, "color": Color(1.0, 0.8, 0.3)},
	"trader": {"prompt": "Buy and sell", "title": "Trader", "at": Vector3(6.6, 0.0, 3.1), "yaw": -PI / 2.0, "color": Color(0.45, 1.0, 0.6)},
	"arena": {"prompt": "Enter the arena (no gear at risk)", "title": "Arena gate", "at": Vector3(6.6, 0.0, 7.4), "yaw": -PI / 2.0, "color": Color(1.0, 0.35, 0.3)},
	"uplink": {"prompt": "Play online", "title": "Uplink", "at": Vector3(6.6, 0.0, 5.3), "yaw": -PI / 2.0, "color": Color(0.4, 0.95, 1.0)},
}

## The gunsmith bench: where it stands and which way it faces (local +Z is
## where you stand to use it). It stands in the middle of the armory, long
## side along it, so from the way in you look past its end to the rack. Its
## pegboard holds the attachments in the stash and its vise the primary you
## will deploy with, wearing what is fitted.
const BENCH_AT := Vector3(-15.6, 0.0, 0.4)
const BENCH_YAW := 0.0

## The suit-up bay: where you put your loadout on before you deploy. It
## stands beside the launch pad, facing the way in (local +Z).
const SUIT_AT := Vector3(-3.7, 0.0, 3.0)
const SUIT_YAW := 0.0
## How long the bay's arms take to fit the gear, there and back (view only).
var suit_time := 0.9

## The size of every station's screen, in metres (16:9).
const SCREEN_SIZE := Vector2(1.6, 0.9)

var player: Actor
var displays: Array[Display] = []
var door: Door
var stations: Array[Station] = []
var suit_bay: SuitBay
## True once the player has suited up in this visit, wearing `suited_kit`.
var suited := false
var suited_kit: Array[String] = []
var stash: Array = []
var loadout := {}

var _display_root := Node3D.new()


## Something on show. Looking at it gives its name; using it equips it.
class Display:
	extends Interactable

	var base: HomeBase
	var item_id := ""
	var kind := ""
	var index := 0
	var count := 1
	var slot := ""
	var equipped := false

	func get_prompt() -> String:
		var shown := ItemDB.item_name(item_id)
		if count > 1:
			shown += " x%d" % count
		if slot == "" or (base and base.read_only):
			return shown + (" (equipped)" if equipped else "")
		if equipped:
			return "[F] Take off %s (equipped)" % shown
		return "[F] Equip %s" % shown

	func interact(_actor: Actor) -> void:
		if slot != "" and base and not base.read_only:
			base.equip_requested.emit(slot, "" if equipped else item_id)


## A console that opens one of the game's screens: what was the menu lives
## here, in the room.
class Station:
	extends Interactable

	var base: HomeBase
	var id := ""
	## Where the station's screen is: centred on it, facing out along its +Z,
	## `HomeBase.SCREEN_SIZE` across. Whoever shows the screen mounts it here.
	var screen: Node3D

	func get_prompt() -> String:
		var title: String = HomeBase.STATIONS[id]["title"]
		if base and base.read_only:
			return "%s (not yours)" % title
		return "[F] %s: %s" % [title, HomeBase.STATIONS[id]["prompt"]]

	func interact(_actor: Actor) -> void:
		if base and not base.read_only:
			base.station_requested.emit(id)


## The suit-up bay's control post. Using it puts the loadout on you.
class SuitBay:
	extends Interactable

	var base: HomeBase

	func get_prompt() -> String:
		if base == null or base.read_only:
			return "Suit-up bay (not yours)"
		if base.suited and base.suited_kit == base.suit_kit():
			return "[F] Suit-up bay: you are wearing your loadout"
		if base.suited:
			return "[F] Suit up again: your loadout changed"
		return "[F] Suit up: put your loadout on"

	func interact(_actor: Actor) -> void:
		# Deferred: the actor using the post is the one the bay replaces, and
		# it is still in the middle of its tick.
		if base and not base.read_only:
			base.suit_up.call_deferred()


## The way out.
class Door:
	extends Interactable

	var base: HomeBase

	func get_prompt() -> String:
		return "[F] %s" % (base.door_text if base else "Leave")

	func interact(_actor: Actor) -> void:
		if base:
			base.leave_requested.emit()


func _ready() -> void:
	_build_room()
	_build_armory()
	_display_root.name = "Displays"
	add_child(_display_root)
	_build_door()
	_build_bench()
	_build_suit_bay()
	_build_stations()
	_build_banner()
	_spawn_player()
	_rebuild()


## Shows this stash and loadout. Safe to call before the base is in the tree.
func show_gear(p_stash: Array, p_loadout: Dictionary) -> void:
	stash = p_stash.duplicate()
	loadout = p_loadout.duplicate()
	if is_inside_tree():
		_rebuild()


## What the bay puts on you: each loadout slot's item, or the free starter
## item that fits an empty slot, as a deploy would. Vehicles stay parked and
## supplies stay on the shelf: only what is worn or carried in hand.
func suit_kit() -> Array[String]:
	var kit: Array[String] = []
	for slot: String in Loadout.SLOTS:
		var id: String = loadout.get(slot, "")
		if id == "" and slot in Loadout.OPTIONAL_SLOTS:
			continue
		if id == "":
			for free_id: String in ItemDB.all_ids():
				if ItemDB.has_tag(free_id, "starter") and Loadout.fits(slot, free_id):
					id = free_id
					break
		if id != "" and not ItemDB.has_tag(id, "vehicle"):
			kit.append(id)
	return kit


## Puts the loadout on: the player steps into the bay as a new actor wearing
## `suit_kit()`, its weapons holstered and locked (nobody fights at home),
## while the bay's arms swing in and out. `player_replaced` says who it is.
func suit_up() -> void:
	if read_only or not is_inside_tree():
		return
	var old := player
	var fresh := _new_player(SUIT_AT + Vector3(0, 0.1, 0))
	# Facing out of the bay, toward the launch pad and the room.
	fresh.cmd.yaw = SUIT_YAW + PI
	if old and is_instance_valid(old):
		if old.has_meta("appearance"):
			fresh.set_meta("appearance", old.get_meta("appearance"))
		# Freed at the end of the frame, still in the tree until then, so
		# whatever is posing it this frame finishes cleanly.
		old.name = "OldPlayer"
		old.visible = false
		old.queue_free()
	add_child(fresh)
	player = fresh
	# Equipped once it stands in the room: the hand holds weapons in the world.
	suited_kit = suit_kit()
	Loadout.equip(fresh, suited_kit)
	fresh.weapons_locked = true
	suited = true
	_play_suit_arms()
	player_replaced.emit(fresh)


## The station with this id, or null.
func station(id: String) -> Station:
	for found in stations:
		if found.id == id:
			return found
	return null


## The display showing `item_id`, or null.
func display_for(item_id: String) -> Display:
	for display in displays:
		if display.item_id == item_id:
			return display
	return null


## True if `point` (local to the base) is inside the room or the armory.
func inside(point: Vector3) -> bool:
	var half := room_size * 0.5
	if absf(point.x) < half.x and absf(point.z) < half.z:
		return true
	return point.x <= -half.x and point.x > -half.x - armory_size.x and absf(point.z) < armory_size.z * 0.5


## True if `point` (local to the base) is inside the armory alcove.
func in_armory(point: Vector3) -> bool:
	var wall_x := room_size.x * 0.5
	return point.x < -wall_x and point.x > -wall_x - armory_size.x and absf(point.z) < armory_size.z * 0.5


## Where a spot is, and which way it faces: local +Z points into the room.
func spot_transform(kind: String, index: int) -> Transform3D:
	var wall_x := room_size.x * 0.5
	var wall_z := room_size.z * 0.5
	# The armory's back wall, and its side walls either side of the bench.
	var back_x := -wall_x - armory_size.x
	var side_z := armory_size.z * 0.5
	var i := float(index)
	match kind:
		"rack_guns":
			# The armory's back wall: two rows of six, facing the way in.
			var col := float(index % 6)
			var row := float(index / 6)
			return _spot(Vector3(back_x + 0.3, 2.55 - 1.15 * row, -3.75 + 1.5 * col), PI / 2.0)
		"rack_sidearms":
			# The armory's right-hand wall (going in): two rows of four.
			var col := float(index % 4)
			var row := float(index / 4)
			return _spot(Vector3(back_x + 1.4 + 1.2 * col, 2.3 - 0.95 * row, -side_z + 0.3), 0.0)
		"rack_melee":
			# The armory's left-hand wall: one row, standing upright.
			return _spot(Vector3(back_x + 0.6 + 1.05 * i, 1.3, side_z - 0.3), PI)
		"armor_stand":
			return _spot(Vector3(-10.0 + 1.8 * i, 0.0, -wall_z + 1.0), 0.0)
		"rig_stand":
			return _spot(Vector3(2.4 + 2.0 * i, 0.0, -wall_z + 1.0), 0.0)
		"chip_case":
			return _spot(Vector3(wall_x - 0.8, 1.1, 3.6 + 0.8 * i), -PI / 2.0)
		"bay":
			return _spot(Vector3(-4.5 + 3.0 * i, 0.0, -1.5), 0.0)
		"supplies":
			return _spot(Vector3(3.0 + 1.1 * i, 1.1, wall_z - 0.3), PI)
		"gunsmith":
			# Four across and three up on the pegboard behind the bench.
			var col := float(index % 4)
			var row := float(index / 4)
			var bench := _spot(BENCH_AT, BENCH_YAW)
			return bench * _spot(Vector3(-0.78 + 0.52 * col, 1.92 - 0.4 * row, -0.36), 0.0)
		_:
			return _spot(Vector3(-10.5 + 1.1 * i, 1.1, wall_z - 0.3), PI)


func _spot(at: Vector3, yaw: float) -> Transform3D:
	return Transform3D(Basis.from_euler(Vector3(0.0, yaw, 0.0)), at)


# --- The room ----------------------------------------------------------------

func _build_room() -> void:
	var floor_mat := Look.surface("concrete", {"tint": Color(0.5, 0.48, 0.46), "grime": 0.6})
	var wall_mat := Look.surface("concrete", {"tint": Color(0.62, 0.6, 0.58), "grime": 0.3, "scale": 0.3})
	var x := room_size.x
	var y := room_size.y
	var z := room_size.z
	_box(Vector3(x, 0.5, z), Vector3(0, -0.25, 0), floor_mat)
	_box(Vector3(x, 0.5, z), Vector3(0, y + 0.25, 0), wall_mat)
	_box(Vector3(x + 1.0, y, 0.5), Vector3(0, y * 0.5, -z * 0.5 - 0.25), wall_mat)
	_box(Vector3(x + 1.0, y, 0.5), Vector3(0, y * 0.5, z * 0.5 + 0.25), wall_mat)
	# The left wall stops either side of the way into the armory.
	var piece := (z - armory_opening) * 0.5
	for side: float in [-1.0, 1.0]:
		_box(Vector3(0.5, y, piece), Vector3(-x * 0.5 - 0.25, y * 0.5, side * (armory_opening * 0.5 + piece * 0.5)), wall_mat)
	_box(Vector3(0.5, y, z), Vector3(x * 0.5 + 0.25, y * 0.5, 0), wall_mat)
	Look.interior(self, Color(0.62, 0.58, 0.54), 1.3)
	if Look.enabled:
		# Ceiling lamps for the floor, and a wash low on each wall for the gear.
		for at: Vector3 in [Vector3(-6, 4.6, -3), Vector3(6, 4.6, -3), Vector3(-6, 4.6, 4),
				Vector3(6, 4.6, 4), Vector3(0, 4.6, 0)]:
			var light := Look.lamp(Color(1.0, 0.88, 0.72), 4.0, 20.0)
			light.position = at
			add_child(light)
		for at: Vector3 in [Vector3(-6.5, 2.6, -6.6), Vector3(6.5, 2.6, -6.6), Vector3(-9.0, 2.6, 0.5),
				Vector3(9.0, 2.6, 0.5), Vector3(-6.5, 2.6, 6.6), Vector3(6.5, 2.6, 6.6)]:
			var wash := Look.lamp(Color(1.0, 0.92, 0.82), 3.0, 12.0)
			wash.position = at
			add_child(wash)


## The armory: an alcove off the left wall with its own floor, walls and
## lights, a sign over the way in and a lit sill across it. Its rack is the
## displays of the `BaseLayout.ARMORY` kinds; the bench stands in its middle.
func _build_armory() -> void:
	var floor_mat := Look.surface("concrete", {"tint": Color(0.46, 0.45, 0.44), "grime": 0.5})
	var wall_mat := Look.surface("concrete", {"tint": Color(0.5, 0.5, 0.5), "grime": 0.3, "scale": 0.3})
	var wall_x := room_size.x * 0.5
	var depth := armory_size.x
	var y := armory_size.y
	var width := armory_size.z
	var mid_x := -wall_x - depth * 0.5
	_box(Vector3(depth, 0.5, width), Vector3(mid_x, -0.25, 0), floor_mat)
	_box(Vector3(depth, 0.5, width), Vector3(mid_x, y + 0.25, 0), wall_mat)
	_box(Vector3(0.5, y, width + 1.0), Vector3(-wall_x - depth - 0.25, y * 0.5, 0), wall_mat)
	for side: float in [-1.0, 1.0]:
		_box(Vector3(depth, y, 0.5), Vector3(mid_x, y * 0.5, side * (width * 0.5 + 0.25)), wall_mat)
	var accent := Color(1.0, 0.62, 0.22)
	# A dark band behind the rack on each wall, so the weapons read as one rack.
	var band := Color(0.13, 0.13, 0.14)
	add_child(_part(Vector3(0.04, 2.6, width - 0.6), Vector3(-wall_x - depth + 0.02, 2.0, 0), band))
	for side: float in [-1.0, 1.0]:
		add_child(_part(Vector3(depth - 0.8, 2.4, 0.04), Vector3(mid_x - 0.1, 1.9, side * (width * 0.5 - 0.02)), band))
	# A lit sill across the way in.
	var sill := _part(Vector3(0.14, 0.04, armory_opening), Vector3(-wall_x, 0.02, 0), accent, true)
	sill.name = "ArmorySill"
	add_child(sill)
	var title := _label("ARMORY", accent, 0.5)
	title.name = "ArmorySign"
	title.position = Vector3(-wall_x + 0.06, 4.6, 0)
	title.rotation.y = PI / 2.0
	add_child(title)
	if Look.enabled:
		for at: Vector3 in [Vector3(mid_x, 4.6, 0), Vector3(-wall_x - depth + 1.5, 3.2, 0),
				Vector3(mid_x, 3.0, -width * 0.5 + 1.2), Vector3(mid_x, 3.0, width * 0.5 - 1.2)]:
			var light := Look.lamp(Color(1.0, 0.9, 0.78), 3.0, 10.0)
			light.position = at
			add_child(light)


func _box(size: Vector3, at: Vector3, material: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Actor.LAYER_WORLD
	body.collision_mask = 0
	body.position = at
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var mesh_node := MeshInstance3D.new()
	mesh_node.mesh = mesh
	body.add_child(mesh_node)
	add_child(body)
	return body


func _build_door() -> void:
	door = Door.new()
	door.name = "Door"
	door.base = self
	door.position = Vector3(0, 1.3, room_size.z * 0.5 - 0.15)
	# Like the displays, its local +Z points into the room.
	door.rotation.y = PI
	var size := Vector3(2.2, 2.6, 0.3)
	_add_collision(door, size, Vector3.ZERO)
	door.add_child(_part(size, Vector3.ZERO, Color(0.9, 0.5, 0.2), true))
	var sign_label := _label("EXIT", Color(1.0, 0.62, 0.22), 0.3)
	sign_label.position = Vector3(0, 1.7, 0.2)
	door.add_child(sign_label)
	add_child(door)


func _build_stations() -> void:
	for id: String in STATIONS:
		var info: Dictionary = STATIONS[id]
		var console := Station.new()
		console.name = "Station_%s" % id
		console.base = self
		console.id = id
		console.position = info["at"]
		console.rotation.y = info["yaw"]
		var color: Color = info["color"]
		var dark := Color(0.17, 0.17, 0.19)
		var title_at := Vector3(0, 2.2, 0)
		var screen := Node3D.new()
		screen.name = "Screen"
		if id == "launch":
			# A lit ring on the floor round a drop console with a tilted screen.
			console.add_child(_part(Vector3(3.2, 0.04, 3.2), Vector3(0, 0.02, 0), dark))
			for side: Vector3 in [Vector3(0, 0, 1.5), Vector3(0, 0, -1.5)]:
				console.add_child(_part(Vector3(3.2, 0.05, 0.16), side + Vector3(0, 0.03, 0), color, true))
			for side: Vector3 in [Vector3(1.5, 0, 0), Vector3(-1.5, 0, 0)]:
				console.add_child(_part(Vector3(0.16, 0.05, 3.2), side + Vector3(0, 0.03, 0), color, true))
			console.add_child(_part(Vector3(0.9, 1.0, 0.6), Vector3(0, 0.5, 0), dark))
			screen.position = Vector3(0, 1.3, 0.1)
			screen.rotation.x = -0.45
			_add_collision(console, Vector3(1.0, 1.5, 0.8), Vector3(0, 0.75, 0))
			title_at = Vector3(0, 2.15, 0)
		else:
			# A cabinet with a stripe of the station's colour and a monitor on top.
			console.add_child(_part(Vector3(1.2, 1.0, 0.5), Vector3(0, 0.5, 0), dark))
			console.add_child(_part(Vector3(1.22, 0.06, 0.52), Vector3(0, 0.3, 0), color, true))
			console.add_child(_part(Vector3(0.12, 0.25, 0.12), Vector3(0, 1.1, 0), dark))
			screen.position = Vector3(0, 1.62, 0.05)
			screen.rotation.x = -0.08
			_add_collision(console, Vector3(1.3, 1.7, 0.7), Vector3(0, 0.85, 0))
			title_at = Vector3(0, 2.3, 0)
		# The screen's bezel, and a glow in the station's colour while nobody
		# is using it. The live screen is mounted in front of it.
		screen.add_child(_part(Vector3(SCREEN_SIZE.x + 0.08, SCREEN_SIZE.y + 0.08, 0.06), Vector3(0, 0, -0.035), dark))
		var idle := _part(Vector3(SCREEN_SIZE.x, SCREEN_SIZE.y, 0.01), Vector3.ZERO, color.darkened(0.78), true)
		idle.name = "Idle"
		screen.add_child(idle)
		var hint := _label(str(info["prompt"]), color.lightened(0.2), 0.12)
		hint.name = "IdleText"
		hint.position = Vector3(0, 0, 0.012)
		screen.add_child(hint)
		console.add_child(screen)
		console.screen = screen
		var title := _label(str(info["title"]).to_upper(), color, 0.22)
		title.name = "Title"
		title.position = title_at
		title.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		console.add_child(title)
		add_child(console)
		stations.append(console)


## A banner high on the far wall, facing the way in: whose base this is and
## how it works, written in the room instead of over the screen.
func _build_banner() -> void:
	var accent := Color(1.0, 0.62, 0.22)
	var banner := Node3D.new()
	banner.name = "Banner"
	banner.position = Vector3(0.0, 4.75, -room_size.z * 0.5 + 0.06)
	add_child(banner)
	banner.add_child(_part(Vector3(10.5, 1.6, 0.05), Vector3(0, -0.15, -0.03), Color(0.12, 0.11, 0.1)))
	var title := _label("%s'S BASE" % owner_name.to_upper() if read_only else "HOME BASE", accent, 0.6)
	title.name = "Title"
	title.position = Vector3(0.0, 0.3, 0.0)
	banner.add_child(title)
	var how := _label(banner_text(), Color(0.85, 0.83, 0.8), 0.21)
	how.name = "HowTo"
	how.position = Vector3(0.0, -0.4, 0.0)
	banner.add_child(how)


## The lines under the base's name on its banner.
func banner_text() -> String:
	if read_only:
		return "You are visiting. Look around: the gear stays where it is."
	return "Everything in your stash is on show. Look at gear and press F to equip it.\n" \
			+ "Walk up to a console and press F to use its screen. Esc steps back."


func _spawn_player() -> void:
	player = _new_player(spawn_point)
	add_child(player)


func _new_player(at: Vector3) -> Actor:
	var actor := Actor.new()
	actor.name = "Player"
	actor.is_player = true
	actor.display_name = "You"
	actor.position = at
	return actor


## The suit-up bay beside the launch pad: a lit disc to stand on between two
## frames whose arms swing in to fit the gear, and a control post to use.
func _build_suit_bay() -> void:
	var bay := Node3D.new()
	bay.name = "SuitUpBay"
	bay.position = SUIT_AT
	bay.rotation.y = SUIT_YAW
	add_child(bay)
	var accent := Color(0.4, 0.9, 1.0)
	var steel := Color(0.3, 0.31, 0.34)
	var dark := Color(0.15, 0.15, 0.17)
	bay.add_child(_part(Vector3(1.8, 0.06, 1.8), Vector3(0, 0.03, 0), dark))
	bay.add_child(_part(Vector3(1.3, 0.07, 1.3), Vector3(0, 0.035, 0), accent.darkened(0.5), true))
	for side: float in [-1.0, 1.0]:
		var frame := Node3D.new()
		frame.name = "Frame%s" % ("L" if side < 0 else "R")
		frame.position = Vector3(side * 0.95, 0, -0.1)
		bay.add_child(frame)
		frame.add_child(_part(Vector3(0.16, 2.5, 0.3), Vector3(0, 1.25, 0), steel))
		frame.add_child(_part(Vector3(0.04, 2.2, 0.04), Vector3(-side * 0.09, 1.2, 0.12), accent, true))
		# Two arms, folded back against the frame until the bay works.
		for height: float in [1.0, 1.55]:
			var arm := Node3D.new()
			arm.name = "Arm%d" % int(height * 100.0)
			arm.position = Vector3(0, height, 0)
			arm.set_meta("side", side)
			arm.add_child(_part(Vector3(0.5, 0.1, 0.12), Vector3(-side * 0.25, 0, 0), steel))
			arm.add_child(_part(Vector3(0.1, 0.16, 0.16), Vector3(-side * 0.5, 0, 0), accent, true))
			arm.rotation.y = side * 1.3
			frame.add_child(arm)
	# A gantry over the top with the bay's name.
	bay.add_child(_part(Vector3(2.06, 0.16, 0.3), Vector3(0, 2.55, -0.1), steel))
	var title := _label("SUIT-UP BAY", accent, 0.22)
	title.position = Vector3(0, 2.85, -0.1)
	title.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	bay.add_child(title)
	# The control post, front right, that you use.
	suit_bay = SuitBay.new()
	suit_bay.name = "Control"
	suit_bay.base = self
	suit_bay.position = Vector3(1.35, 0, 0.7)
	suit_bay.add_child(_part(Vector3(0.24, 1.1, 0.24), Vector3(0, 0.55, 0), dark))
	var panel := _part(Vector3(0.36, 0.26, 0.05), Vector3(0, 1.2, 0.05), accent, true)
	panel.rotation.x = -0.5
	suit_bay.add_child(panel)
	_add_collision(suit_bay, Vector3(0.5, 1.4, 0.5), Vector3(0, 0.7, 0))
	bay.add_child(suit_bay)


## The bay's arms swing in to the body and fold back again. View only.
func _play_suit_arms() -> void:
	for arm: Node in find_child("SuitUpBay", false, false).find_children("Arm*", "Node3D", true, false):
		if not arm.has_meta("side"):
			continue
		var side: float = arm.get_meta("side")
		var tween := create_tween()
		tween.tween_property(arm, "rotation:y", 0.0, suit_time * 0.4)
		tween.tween_interval(suit_time * 0.2)
		tween.tween_property(arm, "rotation:y", side * 1.3, suit_time * 0.4)


# --- Displays ----------------------------------------------------------------

func _rebuild() -> void:
	for child in _display_root.get_children():
		_display_root.remove_child(child)
		child.queue_free()
	displays.clear()
	for entry: Dictionary in BaseLayout.plan(stash, loadout):
		var display := Display.new()
		display.base = self
		display.item_id = entry["id"]
		display.kind = entry["kind"]
		display.index = entry["index"]
		display.count = entry["count"]
		display.slot = entry["slot"]
		display.equipped = entry["equipped"]
		display.name = "%s_%d" % [display.kind, display.index]
		display.transform = spot_transform(display.kind, display.index)
		# `Look` swaps in real models for displays tagged like this.
		display.set_meta("display_item", display.item_id)
		_fill(display)
		_display_root.add_child(display)
		displays.append(display)
	_build_signs()
	_build_bench_gun()
	gear_shown.emit()


## A title over each section, with how much did not fit on show.
func _build_signs() -> void:
	var stored := BaseLayout.stored_away(stash)
	for kind: String in BaseLayout.KINDS:
		var text: String = str(BaseLayout.KINDS[kind]["title"]).to_upper()
		if stored.has(kind):
			text += "\n+%d more in storage" % stored[kind]
		var sign_label := _label(text, Color(1.0, 0.62, 0.22), 0.26)
		var first := spot_transform(kind, 0)
		var last := spot_transform(kind, int(BaseLayout.KINDS[kind]["spots"]) - 1)
		var mid := first.origin.lerp(last.origin, 0.5)
		sign_label.position = Vector3(mid.x, 3.4, mid.z) + first.basis.z * 0.05
		sign_label.rotation.y = first.basis.get_euler().y
		_display_root.add_child(sign_label)


## Builds the greybox model, hit box and name plate for one display.
func _fill(display: Display) -> void:
	var id := display.item_id
	var color: Color = ItemDB.RARITY_COLORS[ItemDB.item_rarity(id)]
	var model := Node3D.new()
	model.name = "Model"
	var box := Vector3(1.0, 1.0, 0.6)
	var box_at := Vector3.ZERO
	var plate_at := Vector3(0, -0.55, 0.12)
	var plate_size := 0.13
	match display.kind:
		"rack_guns", "rack_sidearms":
			var gun := Gun.new()
			gun.item_id = id
			var visual := gun.build_visual()
			gun.free()
			# Side-on to the room, hanging on two pegs.
			visual.rotation.y = PI / 2.0
			visual.scale = Vector3.ONE * weapon_scale
			model.add_child(visual)
			model.position.z = 0.15
			var small := display.kind == "rack_sidearms"
			for x: float in ([-0.15, 0.15] if small else [-0.3, 0.3]):
				display.add_child(_part(Vector3(0.05, 0.05, 0.3), Vector3(x, -0.18, 0.05), Color(0.2, 0.2, 0.22)))
			box = Vector3(0.8, 0.7, 0.6) if small else Vector3(1.3, 0.9, 0.6)
			if small:
				plate_at = Vector3(0, -0.45, 0.12)
		"rack_melee":
			var blade := MeleeWeapon.new()
			blade.item_id = id
			var visual := blade.build_visual()
			blade.free()
			# Upright, handle down.
			visual.rotation = Vector3.ZERO
			visual.scale = Vector3.ONE * weapon_scale
			model.add_child(visual)
			model.position = Vector3(0, -0.5, 0.12)
			box = Vector3(1.0, 2.2, 0.6)
			box_at = Vector3(0, 0.3, 0)
			plate_at = Vector3(0, 1.6, 0.12)
		"armor_stand":
			_build_armor(model, id, color)
			box = Vector3(1.2, 2.0, 1.0)
			box_at = Vector3(0, 1.0, 0)
			plate_at = Vector3(0, 2.25, 0)
		"rig_stand":
			_build_rig(model, id, color)
			box = Vector3(1.2, 2.0, 1.0)
			box_at = Vector3(0, 1.0, 0)
			plate_at = Vector3(0, 2.25, 0)
		"gunsmith":
			var part := Gun.build_attachment(id)
			if part:
				part.name = "Attachment"
				part.position = Vector3.ZERO
				# Side-on to the room, like the guns on the rack.
				part.rotation.y = PI / 2.0
				part.scale = Vector3.ONE * 1.5
				model.add_child(part)
			# A peg to hang it on.
			display.add_child(_part(Vector3(0.02, 0.02, 0.1), Vector3(0, 0.02, -0.04), Color(0.55, 0.55, 0.5)))
			box = Vector3(0.46, 0.34, 0.3)
			plate_at = Vector3(0, -0.15, 0.06)
			plate_size = 0.045
		"chip_case":
			model.add_child(_part(Vector3(0.5, 0.08, 0.5), Vector3(0, -0.3, 0), Color(0.16, 0.16, 0.18)))
			var chip := _part(Vector3(0.26, 0.26, 0.04), Vector3(0, 0, 0), color, true)
			chip.rotation.z = PI / 4.0
			model.add_child(chip)
			box = Vector3(0.7, 0.9, 0.7)
			plate_at = Vector3(0, 0.5, 0)
		"bay":
			var vehicle: Node3D = VehicleScript.new()
			vehicle.setup(id)
			var visual: Node3D = vehicle.build_visual()
			vehicle.free()
			visual.name = "Body"
			model.add_child(visual)
			# Parked nose-out, on a painted bay.
			model.rotation.y = PI
			display.add_child(_part(Vector3(2.2, 0.02, 3.4), Vector3(0, 0.01, 0), Color(0.75, 0.6, 0.15)))
			display.add_child(_part(Vector3(2.0, 0.03, 3.2), Vector3(0, 0.012, 0), Color(0.2, 0.2, 0.21)))
			box = Vector3(1.2, 1.4, 2.4)
			box_at = Vector3(0, 0.7, 0)
			plate_at = Vector3(0, 1.75, 0)
		_:
			model.add_child(_part(Vector3(1.0, 0.06, 0.5), Vector3(0, -0.3, 0), Color(0.2, 0.2, 0.22)))
			var glow: bool = ItemDB.item_rarity(id) >= ItemDB.Rarity.EPIC
			# A taller stack the more copies you hold.
			var stack := mini(display.count, 4)
			for n in stack:
				model.add_child(_part(Vector3(0.36, 0.16, 0.3), Vector3(0, -0.19 + 0.17 * n, 0), color, glow))
			box = Vector3(1.0, 1.0, 0.7)
			plate_at = Vector3(0, 0.62, 0)
	display.add_child(model)
	_add_collision(display, box, box_at)
	var text := ItemDB.item_name(id)
	if display.count > 1:
		text += "  x%d" % display.count
	if display.equipped:
		text += "\nEQUIPPED"
	var plate := _label(text, color, plate_size)
	plate.name = "Plate"
	plate.position = plate_at
	display.add_child(plate)
	if display.equipped:
		# A lit bar under whatever you are taking on your next run.
		var bar := _part(Vector3(box.x * 0.8, 0.03 * plate_size / 0.13, 0.06), plate_at + Vector3(0, -0.16 * plate_size / 0.13 - 0.02, 0),
				Color(1.0, 0.62, 0.22), true)
		bar.name = "EquippedMark"
		display.add_child(bar)


## The gunsmith bench: a heavy table with a vise and a pegboard behind it.
## The gear on it is rebuilt with the rest of the displays.
func _build_bench() -> void:
	var bench := StaticBody3D.new()
	bench.name = "GunsmithBench"
	bench.collision_layer = Actor.LAYER_WORLD
	bench.collision_mask = 0
	bench.position = BENCH_AT
	bench.rotation.y = BENCH_YAW
	var wood := Color(0.36, 0.28, 0.2)
	var steel := Color(0.24, 0.25, 0.27)
	bench.add_child(_part(Vector3(2.2, 0.08, 0.9), Vector3(0, 0.92, 0), wood))
	for x: float in [-1.0, 1.0]:
		for z: float in [-0.38, 0.38]:
			bench.add_child(_part(Vector3(0.08, 0.88, 0.08), Vector3(x, 0.44, z), steel))
	bench.add_child(_part(Vector3(2.1, 0.04, 0.8), Vector3(0, 0.25, 0), steel))
	# The pegboard, framed, on two posts at the back.
	bench.add_child(_part(Vector3(2.2, 1.45, 0.04), Vector3(0, 1.72, -0.42), Color(0.55, 0.46, 0.34)))
	for x: float in [-1.12, 1.12]:
		bench.add_child(_part(Vector3(0.06, 1.55, 0.06), Vector3(x, 1.72, -0.42), steel))
	bench.add_child(_part(Vector3(2.3, 0.06, 0.06), Vector3(0, 2.47, -0.42), steel))
	# A vise in the middle of the bench, and a lamp over it.
	# The vise holds the gun by its receiver, just ahead of the grip.
	bench.add_child(_part(Vector3(0.12, 0.2, 0.16), Vector3(-0.3, 1.06, 0.1), steel))
	bench.add_child(_part(Vector3(0.16, 0.04, 0.04), Vector3(-0.3, 1.18, 0.1), Color(0.12, 0.13, 0.15)))
	bench.add_child(_part(Vector3(0.002, 0.12, 0.1), Vector3(-0.239, 1.06, 0.1), Color(0.25, 0.9, 1.0), true))
	bench.add_child(_part(Vector3(0.4, 0.03, 0.12), Vector3(0, 2.38, 0.1), Color(1.0, 0.85, 0.6), true))
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.3, 1.0, 0.95)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0, 0.5, 0)
	bench.add_child(col)
	var title := _label("GUNSMITH BENCH", Color(1.0, 0.62, 0.22), 0.22)
	title.name = "Title"
	title.position = Vector3(0, 2.75, -0.42)
	bench.add_child(title)
	var how := _label("Look at an attachment and press F to fit it to your primary", Color(0.85, 0.83, 0.8), 0.08)
	how.name = "HowTo"
	how.position = Vector3(0, 2.6, -0.38)
	bench.add_child(how)
	add_child(bench)
	if Look.enabled:
		var light := Look.lamp(Color(1.0, 0.9, 0.75), 2.0, 5.0)
		light.position = BENCH_AT + Vector3(0.6, 2.2, 0)
		add_child(light)


## The primary you will deploy with, in the bench's vise with its attachments
## on, and a card beside it saying what they change.
func _build_bench_gun() -> void:
	var id: String = loadout.get("primary", "")
	if id == "" or not ItemDB.has_tag(id, "firearm"):
		id = starter_primary()
	if id == "":
		return
	var fitted := fitted_attachments()
	var gun := bench_gun(id, fitted)
	var bare := bench_gun(id, [])
	var visual := gun.build_visual()
	var shown := Node3D.new()
	shown.name = "BenchGun"
	shown.transform = _spot(BENCH_AT, BENCH_YAW) * _spot(Vector3(-0.15, 1.3, 0.1), 0.0)
	var model := Node3D.new()
	model.name = "Model"
	visual.rotation.y = PI / 2.0
	model.add_child(visual)
	shown.add_child(model)
	# `Look` swaps in the real model and moves the attachments onto it.
	shown.set_meta("display_item", id)
	_display_root.add_child(shown)
	# The card: a small lit tablet propped on the bench beside the vise.
	var tablet := _part(Vector3(0.46, 0.62, 0.02), Vector3.ZERO, Color(0.08, 0.09, 0.1))
	tablet.name = "SpecTablet"
	tablet.transform = _spot(BENCH_AT, BENCH_YAW) * Transform3D(Basis.from_euler(Vector3(-0.3, 0, 0)), Vector3(0.74, 1.27, -0.08))
	_display_root.add_child(tablet)
	var card := _label(spec_text(gun, bare), Color(0.55, 0.95, 1.0), 0.026)
	card.name = "SpecCard"
	card.outline_size = 4
	card.transform = tablet.transform * Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.012))
	_display_root.add_child(card)
	gun.free()
	bare.free()


## The attachments in the loadout, one per slot.
func fitted_attachments() -> Array[String]:
	var out: Array[String] = []
	for slot: String in Loadout.ATTACHMENT_SLOTS:
		var id: String = loadout.get(slot, "")
		if id != "":
			out.append(id)
	return out


## The free primary, for when none is equipped.
static func starter_primary() -> String:
	for id: String in ItemDB.all_ids():
		if ItemDB.has_tag(id, "starter") and Loadout.fits("primary", id):
			return id
	return ""


## A gun set up as `id` with `fitted` attachments on, not in any tree.
static func bench_gun(id: String, fitted: Array) -> Gun:
	var gun := Gun.new()
	gun.item_id = id
	gun.display_name = ItemDB.item_name(id)
	Loadout._apply_stats(gun, ItemDB.item_stats(id))
	gun.fit(fitted)
	return gun


## The card by the bench gun: its name, what is fitted, and every stat the
## attachments change, from the bare gun's value to the fitted one.
static func spec_text(gun: Gun, bare: Gun) -> String:
	var lines: Array[String] = [gun.display_name.to_upper()]
	if gun.attachments.is_empty():
		lines.append("Nothing fitted")
	for id in gun.attachments:
		lines.append("+ %s" % ItemDB.item_name(id))
	var rows := [
		["Damage", "damage", "%.0f"], ["Fire rate", "rpm", "%.0f/min"], ["Magazine", "mag_size", "%d"],
		["Reload", "reload_time", "%.1fs"], ["Spread", "spread_deg", "%.2f°"], ["Aimed spread", "ads", "%.2f°"],
		["Recoil", "recoil_kick_deg", "%.2f°"], ["Range", "max_range", "%.0fm"], ["Zoom", "ads_zoom", "%.1fx"],
	]
	for row: Array in rows:
		var before := _spec_value(bare, row[1])
		var after := _spec_value(gun, row[1])
		if absf(after - before) > 0.001:
			lines.append("%s  %s → %s" % [row[0], row[2] % before, row[2] % after])
	if gun.quiet:
		lines.append("Suppressed: no tracer or flash")
	return "\n".join(lines)


static func _spec_value(gun: Gun, key: String) -> float:
	match key:
		"rpm":
			return 60.0 / maxf(gun.fire_interval, 0.001)
		"ads":
			return gun.spread_deg * gun.ads_spread_mult
	return float(gun.get(key))


## A mannequin wearing the frame. Heavier frames get bulkier plates.
func _build_armor(model: Node3D, id: String, color: Color) -> void:
	var armor: float = ItemDB.item_stats(id).get("armor", 30.0)
	var bulk := clampf(armor / 140.0, 0.25, 1.0)
	var dummy := Color(0.22, 0.22, 0.24)
	model.add_child(_part(Vector3(0.7, 0.08, 0.7), Vector3(0, 0.04, 0), dummy))
	model.add_child(_part(Vector3(0.1, 0.9, 0.1), Vector3(0, 0.5, 0), dummy))
	model.add_child(_part(Vector3(0.42, 0.6, 0.24), Vector3(0, 1.25, 0), dummy))
	model.add_child(_part(Vector3(0.24, 0.26, 0.24), Vector3(0, 1.72, 0), dummy))
	# Chest plate, shoulders and helmet brow.
	model.add_child(_part(Vector3(0.46 + 0.2 * bulk, 0.5, 0.08 + 0.14 * bulk), Vector3(0, 1.28, 0.14), color))
	for x: float in [-1.0, 1.0]:
		model.add_child(_part(Vector3(0.16 + 0.16 * bulk, 0.12 + 0.1 * bulk, 0.3),
				Vector3(x * (0.3 + 0.08 * bulk), 1.56, 0), color))
	model.add_child(_part(Vector3(0.28, 0.06 + 0.1 * bulk, 0.28), Vector3(0, 1.84, 0), color))


## A flight rig on a stand. Its stats pick the shape: wings glide, boots only
## kick, a jetpack thrusts.
func _build_rig(model: Node3D, id: String, color: Color) -> void:
	var stats := ItemDB.item_stats(id)
	var dark := Color(0.2, 0.2, 0.22)
	model.add_child(_part(Vector3(0.7, 0.08, 0.7), Vector3(0, 0.04, 0), dark))
	model.add_child(_part(Vector3(0.1, 1.3, 0.1), Vector3(0, 0.7, -0.1), dark))
	if stats.has("glide_fall_speed"):
		for x: float in [-1.0, 1.0]:
			var wing := _part(Vector3(0.9, 0.06, 0.4), Vector3(x * 0.5, 1.35, 0), color)
			wing.rotation.z = x * 0.35
			model.add_child(wing)
		model.add_child(_part(Vector3(0.24, 0.4, 0.2), Vector3(0, 1.3, 0), dark))
	elif float(stats.get("thrust_accel", 1.0)) <= 0.0:
		for x: float in [-0.16, 0.16]:
			model.add_child(_part(Vector3(0.18, 0.4, 0.34), Vector3(x, 0.3, 0.1), color))
			model.add_child(_part(Vector3(0.1, 0.08, 0.1), Vector3(x, 0.1, -0.02), Color(1.0, 0.6, 0.2), true))
	else:
		model.add_child(_part(Vector3(0.5, 0.6, 0.2), Vector3(0, 1.25, 0), color))
		for x: float in [-0.18, 0.18]:
			model.add_child(_part(Vector3(0.16, 0.5, 0.16), Vector3(x, 1.05, -0.16), dark))
			model.add_child(_part(Vector3(0.1, 0.06, 0.1), Vector3(x, 0.78, -0.16), Color(1.0, 0.6, 0.2), true))


func _add_collision(body: Interactable, size: Vector3, at: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = at
	body.add_child(col)


func _part(size: Vector3, at: Vector3, color: Color, glow := false) -> MeshInstance3D:
	return Weapon.make_part(size, at, color, glow)


func _label(text: String, color: Color, height: float) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.modulate = color
	label.font_size = 64
	label.pixel_size = height / 64.0
	label.outline_size = 12
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label
