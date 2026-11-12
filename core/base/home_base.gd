class_name HomeBase
extends Node3D
## A player's home base: a room you walk around in, with everything in your
## stash on show. Guns on a rack, blades on the wall, armor on stands, flight
## rigs, ability chips, bikes parked in the garage, and shelves for supplies
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

const BaseLayout := preload("res://core/base/base_layout.gd")
const VehicleScript := preload("res://core/vehicle/vehicle.gd")

# Room tuning.
var room_size := Vector3(24.0, 6.0, 18.0)
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
## with its title and prompt. The launch pad stands in the middle, the rest along the
## open floor on either side of the garage.
const STATIONS := {
	"launch": {"prompt": "Deploy", "title": "Launch pad", "at": Vector3(0.0, 0.0, 2.6), "yaw": 0.0, "color": Color(1.0, 0.55, 0.2)},
	"locker": {"prompt": "Pick your loadout", "title": "Locker", "at": Vector3(-6.6, 0.0, 0.9), "yaw": PI / 2.0, "color": Color(0.45, 0.75, 1.0)},
	"wardrobe": {"prompt": "Change how you look", "title": "Wardrobe", "at": Vector3(-6.6, 0.0, 3.1), "yaw": PI / 2.0, "color": Color(0.85, 0.6, 1.0)},
	"records": {"prompt": "Read your record and stash", "title": "Records", "at": Vector3(-6.6, 0.0, 5.3), "yaw": PI / 2.0, "color": Color(0.9, 0.9, 0.85)},
	"mastery": {"prompt": "Pick mastery variants", "title": "Mastery bench", "at": Vector3(6.6, 0.0, 0.9), "yaw": -PI / 2.0, "color": Color(1.0, 0.8, 0.3)},
	"trader": {"prompt": "Buy and sell", "title": "Trader", "at": Vector3(6.6, 0.0, 3.1), "yaw": -PI / 2.0, "color": Color(0.45, 1.0, 0.6)},
	"arena": {"prompt": "Enter the arena (no gear at risk)", "title": "Arena gate", "at": Vector3(6.6, 0.0, 7.4), "yaw": -PI / 2.0, "color": Color(1.0, 0.35, 0.3)},
	"uplink": {"prompt": "Play online", "title": "Uplink", "at": Vector3(6.6, 0.0, 5.3), "yaw": -PI / 2.0, "color": Color(0.4, 0.95, 1.0)},
}

## The size of every station's screen, in metres (16:9).
const SCREEN_SIZE := Vector2(1.6, 0.9)

var player: Actor
var displays: Array[Display] = []
var door: Door
var stations: Array[Station] = []
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
	_display_root.name = "Displays"
	add_child(_display_root)
	_build_door()
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


## Where a spot is, and which way it faces: local +Z points into the room.
func spot_transform(kind: String, index: int) -> Transform3D:
	var wall_x := room_size.x * 0.5
	var wall_z := room_size.z * 0.5
	var i := float(index)
	match kind:
		"gun_rack":
			return _spot(Vector3(-10.5 + 1.5 * i, 1.5, -wall_z + 0.3), 0.0)
		"blade_wall":
			return _spot(Vector3(2.5 + 1.6 * i, 1.3, -wall_z + 0.3), 0.0)
		"armor_stand":
			return _spot(Vector3(-wall_x + 1.2, 0.0, -5.0 + 2.2 * i), PI / 2.0)
		"rig_stand":
			return _spot(Vector3(wall_x - 1.2, 0.0, -5.0 + 2.2 * i), -PI / 2.0)
		"chip_case":
			return _spot(Vector3(wall_x - 0.8, 1.1, 3.6 + 0.8 * i), -PI / 2.0)
		"bay":
			return _spot(Vector3(-4.5 + 3.0 * i, 0.0, -1.5), 0.0)
		"supplies":
			return _spot(Vector3(3.0 + 1.1 * i, 1.1, wall_z - 0.3), PI)
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
	_box(Vector3(0.5, y, z), Vector3(-x * 0.5 - 0.25, y * 0.5, 0), wall_mat)
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
	player = Actor.new()
	player.name = "Player"
	player.is_player = true
	player.display_name = "You"
	player.position = spawn_point
	add_child(player)


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
	match display.kind:
		"gun_rack":
			var gun := Gun.new()
			gun.item_id = id
			var visual := gun.build_visual()
			gun.free()
			# Side-on to the room, hanging on two pegs.
			visual.rotation.y = PI / 2.0
			visual.scale = Vector3.ONE * weapon_scale
			model.add_child(visual)
			model.position.z = 0.15
			for x: float in [-0.3, 0.3]:
				display.add_child(_part(Vector3(0.05, 0.05, 0.3), Vector3(x, -0.18, 0.05), Color(0.2, 0.2, 0.22)))
			box = Vector3(1.3, 0.9, 0.6)
		"blade_wall":
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
	var plate := _label(text, color, 0.13)
	plate.name = "Plate"
	plate.position = plate_at
	display.add_child(plate)
	if display.equipped:
		# A lit bar under whatever you are taking on your next run.
		var bar := _part(Vector3(box.x * 0.8, 0.03, 0.06), plate_at + Vector3(0, -0.16, 0), Color(1.0, 0.62, 0.22), true)
		bar.name = "EquippedMark"
		display.add_child(bar)


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
