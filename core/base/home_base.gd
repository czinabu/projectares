class_name HomeBase
extends Node3D
## A player's home base: a steel hub you walk around in, with a room off it
## in each of its six sockets (`BasePlan`) and everything in your stash on
## show in those rooms: every weapon on the armory's rack, armor, helmets,
## rigs and chips in the gear hall, vehicles in the garage, supplies and
## trophies in the stores, the gunsmith bench and fabricator in the
## workshop, and the wardrobe, records, mastery and trader consoles in ops.
## Which room stands in which socket is the owner's choice, made at the plan
## table in the middle of the hub (`plan_used`, `room_placed`); the hub
## keeps the door, the locker, the wall mirror and room for a portal, and the
## firing range and flight course always lie behind it, down the corridor
## between the back sockets. There is no launch pad: you leave for a world
## through a squad portal opened from the watch (`open_portal`).
##
## The base is a view of a stash, never a second store. `show_gear` is given a
## stash and a loadout (the local `Profile`'s, or the account a server keeps)
## and rebuilds the displays. Using a display asks for a loadout change through
## `equip_requested`; whoever owns the stash decides and calls `show_gear` again.
##
## The base grows with the account's upgrades (`BaseUpgrades`, the third
## thing `show_gear` is given). With none it is the starter bunker: the
## armory is a shallow nook, the garage has one bay, the firing range is
## replaced by a small test lane (`_build_test_lane`) and a few displays have fewer spots (`BaseLayout.spots`). What is not
## owned yet is sealed behind a `Bulkhead` that shows its name and price in
## the room; using one twice asks to buy it through `upgrade_requested`, and
## whoever owns the account decides and calls `show_gear` again. Each room
## starts in its small form, sealed halfway back, and its upgrade
## (`BasePlan.ROOMS`) opens the rest of it, wherever it stands; its bulkhead
## is inside that room, never out in the hub.
##
## Like `Raid`, this has no camera, HUD or input code. `player` is an `Actor`
## driven through its `ActorCommand`, so it runs headless.

## The player used a piece of gear on show. `item_id` is "" to take the slot's
## item off.
signal equip_requested(slot: String, item_id: String)
## The player used the door.
signal leave_requested
## The player used a station (a key of `STATIONS`): the locker, the mastery
## bench, the wardrobe, the records board or the trader. (Going online is
## the phone's Servers app, not a station.) Whoever owns the base opens what it offers.
signal station_requested(station: String)
## The player confirmed buying an upgrade (an id from `BaseUpgrades`) at its
## bulkhead. Whoever owns the account checks the price and takes the scrip.
signal upgrade_requested(id: String)
## The displays were rebuilt.
signal gear_shown
## The player used the gunsmith bench. Whoever drives the player brings the
## view to the bench and works it with `bench_scroll`, `bench_select`,
## `bench_back` and `leave_bench`.
signal bench_used
## The player walked into the squad portal they opened from the watch
## (`open_portal`). Whoever owns the base sends them to `destination` (a
## `Portal.from_base()` id: a world, the arena or the plaza).
signal portal_entered(destination: String)
## The loadout changed and the player now wears it: `player` is a new actor
## in the same spot. Whoever drives the player (a controller, a camera)
## takes it over.
signal player_replaced(actor: Actor)
## The player used the plan table. Whoever drives the player brings the view
## to it and works it with `plan_scroll`, `plan_select`, `plan_back` and
## `leave_plan`, like the bench.
signal plan_used
## The player moved `room` into `socket` at the plan table (the room there
## takes its old socket). Whoever owns the account keeps the plan and calls
## `show_gear` again with it.
signal room_placed(socket: String, room: String)
## A shot hit a plate on the test lane or a target on the firing range.
## Nothing there is real damage; the new player's tour listens for it.
signal target_hit

const StashRules := preload("res://core/account/stash_rules.gd")
const BaseLayout := preload("res://core/base/base_layout.gd")
const BaseUpgrades := preload("res://core/base/base_upgrades.gd")
const BasePlan := preload("res://core/base/base_plan.gd")
const VehicleScript := preload("res://core/vehicle/vehicle.gd")
const MirrorScript := preload("res://core/visual/mirror.gd")
const SkinScript := preload("res://core/visual/actor_skin.gd")

# Room tuning.
## The hub, inside its walls: width (x), height (y) and depth (z). The door
## out is in the middle of its front wall (+Z).
var room_size := Vector3(23.0, 6.0, 20.0)
## Every room off the hub, inside its walls: width (x, along the hub's wall),
## height (y) and depth (z, away from the hub). All sockets are this size.
var socket_size := Vector3(9.5, 6.0, 9.75)
## How wide and high a room's doorway through the hub's wall is.
var room_door := Vector2(4.0, 3.4)
## How deep a room is in its small form, before its upgrade opens the rest.
var small_depth := 5.0
## The corridor from the hub's back wall to the range, between the two back
## sockets: this wide inside and this high.
var corridor := Vector2(3.0, 3.4)
## The firing range past the end of the corridor (-Z, `range_from`): width
## (x), height (y) and length (z), entered through a door `range_door` wide
## and high.
var range_size := Vector3(12.0, 10.0, 50.0)
var range_door := Vector2(1.6, 3.0)
## The starter bunker's test lane, in the first stretch of the range's hall
## behind the same door: width (x), height (y) and length (z) from the back
## wall's face, a counter `lane_counter` in from the wall, and a plate this
## far past the counter for each of `lane_plates`. A plate that is hit drops
## and stands again after `lane_pop`. Buying the firing range takes it away.
var lane_size := Vector3(3.0, 3.5, 15.0)
var lane_counter := 1.5
var lane_plates: Array[float] = [4.0, 8.0, 12.0]
var lane_pop := 1.5
## The flight course (Caleb's balance pass): an open-topped yard past the
## far end of the range, entered through a door `course_door` (x offset,
## width, height) in the range's end wall, to time each rig on a climb, a
## gap and a sprint. Its size is width (x), wall height (y) and length (z);
## the walls stand taller than any rig's ceiling, so nothing flies out.
## The climb is a tower `course_tower` (width, height, depth) with a ramp up
## its side for rigs that cannot climb, the gap is `course_gap` meters of
## open air to a second tower, and the sprint `course_sprint` meters on to
## the finish line. Touching the floor in the gap ends the run.
var course_size := Vector3(30.0, 56.0, 88.0)
var course_door := Vector3(-4.0, 2.4, 3.0)
var course_tower := Vector3(6.0, 8.0, 6.0)
var course_gap := 14.0
var course_sprint := 40.0
## How far past the back wall the firing line stands: a clear lobby between
## the door and the line.
var firing_line := 8.0
var spawn_point := Vector3(0.0, 0.1, 6.0)
## Weapons hang a little larger than life so they read from across the room.
var weapon_scale := 1.5
## How long a first press on a bulkhead waits for the second that confirms.
var confirm_time := 4.0
## How long the full garage's lift takes to turn the bike on it once.
var lift_turn_time := 16.0
## How big the gun in the gunsmith bench's vise is shown.
var bench_scale := 1.4
## Long guns on the armory's back wall hang bigger still, so they read from
## the way in.
var rack_gun_scale := 2.1
## The shell: floor plates, ceiling beams and wall ribs are this far apart.
var plate_size := 2.0
var beam_spacing := 3.0
var rib_spacing := 2.5

## Whose base this is, shown on the HUD. "" for your own.
var owner_name := ""
## True when visiting someone else's base: gear can be looked at, not equipped.
var read_only := false
## What the door says it does. Whoever owns the base sets it to where the door
## leads from here (online, back to the plaza, home from a visit).
var door_text := "Head out: play online"

## Where each station stands and which way it faces (local +Z toward whoever
## uses it), in the space of the room it stands in ("room": a `BasePlan` room,
## or "hub"; see `room_transform`), with its title and prompt. The locker
## stands in the hub by the door; the rest are the ops room's consoles, two
## down each side.
const STATIONS := {
	"locker": {"prompt": "Pick your loadout", "title": "Locker", "room": "hub", "at": Vector3(-4.6, 0.0, 9.45), "yaw": PI, "color": Color(0.45, 0.75, 1.0)},
	"wardrobe": {"prompt": "Change how you look", "title": "Wardrobe", "room": "ops", "at": Vector3(-4.2, 0.0, -2.5), "yaw": PI / 2.0, "color": Color(0.85, 0.6, 1.0)},
	"records": {"prompt": "Read your record and stash", "title": "Records", "room": "ops", "at": Vector3(-4.2, 0.0, -6.8), "yaw": PI / 2.0, "color": Color(0.9, 0.9, 0.85)},
	"mastery": {"prompt": "Pick mastery variants", "title": "Mastery bench", "room": "ops", "at": Vector3(4.2, 0.0, -6.8), "yaw": -PI / 2.0, "color": Color(1.0, 0.8, 0.3)},
	"trader": {"prompt": "Buy and sell", "title": "Trader", "room": "ops", "at": Vector3(4.2, 0.0, -2.5), "yaw": -PI / 2.0, "color": Color(0.45, 1.0, 0.6)},
}

## The gunsmith bench: where it stands in the workshop and which way it faces
## (local +Z is where you stand to use it), against the workshop's back wall.
## One gun sits on it at a time: using the bench brings the view to it, where
## the wheel turns through your guns and then each attachment slot's choices,
## shown on the gun as you go (`bench_used`).
const BENCH_AT := Vector3(-1.2, 0.0, -9.1)
const BENCH_YAW := 0.0
## The fabricator: the crafting console beside the bench, in the bench's own
## space (local +Z is where you stand to use the bench). It faces across the
## workshop toward the bench.
const CRAFT_ID := "craft"
const CRAFT_TITLE := "Fabricator"
const CRAFT_AT := Vector3(2.7, 0.0, 0.9)
const CRAFT_YAW := -PI / 2.0
const CRAFT_COLOR := Color(0.3, 0.9, 1.0)
## Until the ops consoles are bought, each of these stations also shows the
## station named beside it, which has no console of its own yet.
const MERGED := {"trader": "mastery", "wardrobe": "records"}

## The wall mirror (Caleb's call: every base has one): on the hub's front
## wall in the deploy area by the door, its glass facing into the room
## (local +Z), so you see what you are wearing before you head out.
const MIRROR_AT := Vector3(5.0, 0.35, 9.84)
const MIRROR_YAW := PI
## The deploy area: the hub's front wall between these x, this deep. The
## wall mirror stands in it, with room in front to open a squad portal from
## the watch.
const DEPLOY_FROM_X := 2.2
const DEPLOY_TO_X := 10.6
const DEPLOY_DEPTH := 4.4
## The plan table: where it stands in the hub, its top this high, and how far
## across its round top is.
const PLAN_AT := Vector3(0.0, 0.0, 0.0)
const PLAN_TOP := 1.0
const PLAN_RADIUS := 1.3
## How high the helmet shelf over the armor stands is.
const HELMET_SHELF_Y := 3.0
## The shelves' heights in the stores (supplies, trophies) and the gear
## hall's chip shelf.
const STORAGE_ROWS := {"supplies": 0.95, "chip_case": 1.5, "trophy": 2.2}
## Each display kind's room (`BasePlan.ROOMS`).
const KIND_ROOMS := {
	"rack_guns": "armory", "rack_sidearms": "armory", "rack_melee": "armory", "heavy_wall": "armory",
	"armor_stand": "gear", "helmet_shelf": "gear", "rig_stand": "gear", "chip_case": "gear",
	"artifact_case": "gear", "bay": "garage", "supplies": "stores", "trophy": "stores",
}
## Each room's colour: the lit edge of its name plate over the doorway and
## its tile on the plan table.
const ROOM_COLORS := {
	"armory": Color(1.0, 0.55, 0.25), "workshop": Color(1.0, 0.78, 0.35), "garage": Color(0.95, 0.8, 0.3),
	"ops": Color(0.75, 0.55, 1.0), "gear": Color(0.4, 0.75, 1.0), "stores": Color(0.45, 0.9, 0.6),
}

## The size of every station's screen, in metres (16:9).
const SCREEN_SIZE := Vector2(1.6, 0.9)

var player: Actor
## The squad portal open in the room (`open_portal`), or null.
var portal: Portal
var displays: Array[Display] = []
var door: Door
var stations: Array[Station] = []
## The mirror on the wall (`core/visual/mirror.gd`, view only). Whoever
## drives the player tells it who looks into it (`Mirror.setup`).
var wall_mirror: Node3D
## True while the player wears the owner's loadout (`suited_kit`). In your
## own base that is always: gear you equip goes straight on (Caleb's call).
var suited := false
var suited_kit: Array[String] = []
## The firing range's targets, its score and the board that shows it.
var targets: Array[RangeTarget] = []
var range_shots := 0
var range_hits := 0
var range_last := ""
var range_board: Label3D
var range_sign: Node3D
## The starter bunker's test lane: its plates, its score and the small board
## that shows it. Empty once the firing range is bought.
var lane_targets: Array[RangeTarget] = []
var lane_shots := 0
var lane_hits := 0
var lane_board: Label3D
## The flight course's run: -1 waiting at the start line, then 0 climbing,
## 1 crossing the gap, 2 sprinting. Seconds since the start, the time at
## each stage's end, the rig flown, the last result and each rig's best
## time (rig name -> seconds), written on `course_board`.
var course_stage := -1
var course_time := 0.0
var course_splits: Array[float] = []
var course_rig := ""
var course_last := ""
var course_best := {}
var course_board: Label3D
var _course_prev_z := INF
var _range_time := 0.0
var stash: Array = []
var loadout := {}
## The upgrade ids this base's owner has (see `BaseUpgrades`). Empty is the
## starter bunker.
var upgrades: Array[String] = []
## Which room stands in which socket (`BasePlan`), as `show_gear` was given.
var base_plan: Dictionary = BasePlan.clean(null)
## The owner's scrip, shown on the price panels. Set it with `set_scrip`.
var scrip := 0
## The sealed upgrades on show, each with its price panel.
var bulkheads: Array[Bulkhead] = []
## Everything built from the upgrades, rebuilt when they change.
var _gated: Array[Node] = []
## The gunsmith bench in use. While `bench_open`, `bench_row` is the row the
## bench card points at (0 the gun, then each of `Loadout.ATTACHMENT_SLOTS`)
## and, while `bench_picking`, the wheel turns through that row's choices
## and `bench_choice` is the one on show. Nothing is equipped until a choice
## is picked (`bench_select`), which asks through `equip_requested`. View
## state only: the loadout stays whatever its owner says it is.
var bench_open := false
var bench_row := 0
var bench_picking := false
var bench_choice := ""
## The plan table's state while in use, like the bench's (view only): open,
## which socket the wheel is on (an index into `BasePlan.SOCKETS`), whether a
## room is being picked for it, and the room the wheel is on.
var plan_open := false
var plan_socket := 0
var plan_picking := false
var plan_choice := ""
## The table in the hub.
var plan_table: PlanTable

var _display_root := Node3D.new()
## The room `_build_rooms` is building into (see `_target`), or null.
var _into: Node3D


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
		var title: String = base.station_title(id) if base else str(HomeBase.STATIONS[id]["title"])
		if base and base.read_only:
			return "%s (not yours)" % title
		var prompt: String = HomeBase.STATIONS[id]["prompt"]
		if base:
			for other: String in base.also_shows(id):
				var more: String = HomeBase.STATIONS[other]["prompt"]
				prompt += ", " + more.left(1).to_lower() + more.substr(1)
		return "[F] %s: %s" % [title, prompt]

	func interact(_actor: Actor) -> void:
		if base and not base.read_only:
			base.station_requested.emit(id)


## The fabricator on the gunsmith bench: the console that crafts gear from
## blueprints (`Hub.STATIONS["craft"]`, DESIGN.md section 10). A station like
## the others, but it stands with the bench, not at a spot of its own.
class CraftConsole:
	extends Station

	func get_prompt() -> String:
		if base and base.read_only:
			return "%s (not yours)" % HomeBase.CRAFT_TITLE
		return "[F] %s: craft from blueprints" % HomeBase.CRAFT_TITLE


## Something to shoot at on the firing range: a plate on a post, one that
## slides across the lane, or a drone circling overhead. It stops shots like a
## wall; `HomeBase` scores the shots that end on it.
class RangeTarget:
	extends StaticBody3D

	var kind := "plate"
	var home := Vector3.ZERO
	var phase := 0.0
	var size := Vector3.ONE
	var centre := Vector3.ZERO
	var plate: MeshInstance3D
	var hits := 0
	## More than 0: a hit drops it, and it stands again after this many seconds.
	var pop_time := 0.0
	var _flash := 0.0
	var _down := 0.0

	func _init() -> void:
		collision_layer = Actor.LAYER_WORLD
		collision_mask = 0

	## Where it should be `time` seconds into the visit.
	func place(time: float) -> void:
		match kind:
			"slider":
				position = home + Vector3(sin(time * 0.9) * 3.0, 0, 0)
			"drone":
				var turn := time * 0.6 + phase
				position = home + Vector3(cos(turn) * 2.8, sin(time * 1.3 + phase) * 0.8, sin(turn) * 3.0)

	## True if a shot that stopped at `point` (global) stopped on this.
	func took(point: Vector3) -> bool:
		if _down > 0.0:
			return false
		var local := to_local(point) - centre
		var half := size * 0.5 + Vector3.ONE * 0.12
		return absf(local.x) <= half.x and absf(local.y) <= half.y and absf(local.z) <= half.z

	func flash() -> void:
		hits += 1
		_flash = 0.15
		if pop_time > 0.0:
			_down = pop_time
			rotation.x = -1.45
			collision_layer = 0
		elif plate:
			plate.scale = Vector3.ONE * 1.12

	func cool(delta: float) -> void:
		if _flash > 0.0:
			_flash -= delta
			if _flash <= 0.0 and plate:
				plate.scale = Vector3.ONE
		if _down > 0.0:
			_down -= delta
			if _down <= 0.0:
				rotation.x = 0.0
				collision_layer = Actor.LAYER_WORLD
			elif _down < 0.2:
				rotation.x = -1.45 * _down / 0.2


## A sealed upgrade: a bulkhead, shutter or post with a panel that names
## what is behind it, what it adds and what it costs. The first use arms it
## and a second within `HomeBase.confirm_time` asks to buy it.
class Bulkhead:
	extends Interactable

	var base: HomeBase
	## The upgrade's id in `BaseUpgrades`.
	var id := ""
	var status: Label3D
	var _armed_until := 0

	func armed() -> bool:
		return Time.get_ticks_msec() < _armed_until

	func get_prompt() -> String:
		var title := BaseUpgrades.title(id)
		if base == null or base.read_only:
			return "%s (sealed)" % title
		var cost := "%s scrip" % HomeBase.commas(BaseUpgrades.price(id))
		var why := base.upgrade_blocked(id)
		if why != "":
			return "%s, %s. %s" % [title, cost, why]
		if armed():
			return "[F] Press again to confirm: %s for %s" % [title, cost]
		return "[F] Buy %s: %s" % [title, cost]

	func interact(_actor: Actor) -> void:
		if base == null or base.read_only or base.upgrade_blocked(id) != "":
			return
		if armed():
			_armed_until = 0
			base.upgrade_requested.emit(id)
		else:
			_armed_until = Time.get_ticks_msec() + int(base.confirm_time * 1000.0)

	## Writes the panel's last line: whether it can be bought, and if not, why.
	func refresh() -> void:
		if status == null:
			return
		if base == null or base.read_only:
			status.text = "Sealed"
			status.modulate = Color(0.7, 0.7, 0.72)
			return
		var why := base.upgrade_blocked(id)
		status.text = "Press F to buy" if why == "" else why
		status.modulate = Color(0.5, 1.0, 0.6) if why == "" else Color(1.0, 0.8, 0.4)


## The gun on the gunsmith bench. Using it takes up the bench (`bench_used`).
class Bench:
	extends Interactable

	var base: HomeBase
	var item_id := ""

	func get_prompt() -> String:
		var shown := ItemDB.item_name(item_id)
		if base == null or base.read_only:
			return "%s on the bench" % shown
		return "[F] %s: pick your gun and fit it out" % base.bench_name()

	func interact(_actor: Actor) -> void:
		if base and not base.read_only and not base.bench_open:
			base.use_bench()


## The plan table in the middle of the hub: using it takes it up
## (`plan_used`), like the bench.
class PlanTable:
	extends Interactable

	var base: HomeBase

	func get_prompt() -> String:
		if base == null or base.read_only:
			return "Plan table (not yours)"
		return "[F] Plan table: move the rooms of your base"

	func interact(_actor: Actor) -> void:
		if base and not base.read_only and not base.plan_open:
			base.use_plan()


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
	_build_range()
	_build_course()
	_display_root.name = "Displays"
	add_child(_display_root)
	_build_door()
	_build_wall_mirror()
	_build_upgrades()
	_spawn_player()
	_rebuild()
	# Your own base: you stand in it wearing your loadout.
	suit_up()


## Shows this stash and loadout, in a base with these upgrades (ids from
## `BaseUpgrades`) and this plan (`BasePlan`: which room is in which
## socket); leave either out to keep the one it has. Safe to call before the
## base is in the tree.
func show_gear(p_stash: Array, p_loadout: Dictionary, p_upgrades: Variant = null, p_plan: Variant = null) -> void:
	stash = p_stash.duplicate()
	loadout = p_loadout.duplicate()
	var changed := false
	if p_upgrades != null:
		var fresh := BaseUpgrades.clean(p_upgrades)
		if fresh != upgrades:
			upgrades = fresh
			changed = true
	if p_plan != null:
		var placed := BasePlan.clean(p_plan)
		if placed != base_plan:
			base_plan = placed
			changed = true
	if changed and is_inside_tree():
		_build_upgrades()
		_keep_player_inside()
	if is_inside_tree():
		_rebuild()
		# What you equip goes straight on. Deferred: the change may come from
		# the player's own tick (using a display), and the player is replaced.
		if suited and suited_kit != suit_kit():
			suit_up.call_deferred()


## After the rooms are built again: a player left standing where no room is
## now (a room that moved) is put back in the hub.
func _keep_player_inside() -> void:
	if player != null and is_instance_valid(player) and not inside(to_local(player.global_position)):
		player.global_position = to_global(spawn_point)
		player.velocity = Vector3.ZERO


## Shows the owner's scrip on the price panels.
func set_scrip(amount: int) -> void:
	scrip = amount
	for gate in bulkheads:
		gate.refresh()


## True if the base's owner has this upgrade.
func owns(id: String) -> bool:
	return id in upgrades


## Why the owner cannot buy this upgrade right now, or "" if they can.
func upgrade_blocked(id: String) -> String:
	var why := BaseUpgrades.blocked(upgrades, id)
	if why == "" and scrip < BaseUpgrades.price(id):
		why = "Not enough scrip: you have %s." % commas(scrip)
	return why


## The bulkhead selling this upgrade, or null if it is owned or not on show.
func bulkhead(id: String) -> Bulkhead:
	for gate in bulkheads:
		if gate.id == id:
			return gate
	return null


## True if this station has a console in the room. The mastery bench and the
## records board share another station's console until the ops consoles are
## bought (`MERGED`). The fabricator comes with the bench.
func has_station(id: String) -> bool:
	if id == CRAFT_ID:
		return true
	return STATIONS.has(id) and (owns("ops_consoles") or id not in MERGED.values())


## The other stations this station's console shows as well, for now.
func also_shows(id: String) -> Array[String]:
	var out: Array[String] = []
	if id == CRAFT_ID:
		return out
	if MERGED.has(id) and not owns("ops_consoles"):
		out.append(MERGED[id])
	return out


## The name on a station's console.
func station_title(id: String) -> String:
	var title: String = STATIONS[id]["title"]
	for other in also_shows(id):
		title += " and " + str(STATIONS[other]["title"]).to_lower()
	return title


## Where the gunsmith bench stands in the base and which way it faces: at the
## back of the workshop, wherever the workshop stands.
func bench_transform() -> Transform3D:
	return room_transform("workshop") * _spot(BENCH_AT, BENCH_YAW)


## A number with thousands separators: 1200 -> "1,200".
static func commas(amount: int) -> String:
	var digits := str(absi(amount))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if amount < 0 else "") + digits + out


## What you wear in your base: each loadout slot's item, as a deploy would
## take it. An empty slot is bare. Vehicles stay parked, supplies stay on
## the shelf, and a heavy stays on the wall: only what is worn or carried
## in hand. A PvP deploy is what puts the heavy in the chamber.
func suit_kit() -> Array[String]:
	var kit: Array[String] = []
	for slot: String in Loadout.SLOTS:
		var id: String = loadout.get(slot, "")
		# A heavy stays on the wall until a PvP deploy puts it in the chamber.
		# The base is not a world that carries one.
		if id != "" and slot != "power" and not ItemDB.has_tag(id, "vehicle"):
			kit.append(id)
	return kit


## Puts the loadout on the player where they stand, wearing `suit_kit()`,
## its weapons locked (nobody fights at home, the range aside). The player
## is dressed in place (`Loadout.refit`): only the pieces that changed are
## swapped, so they keep moving and the view never drops a beat. A new actor
## is made only when there is none standing (`player_replaced` says who it
## is). Called whenever the loadout changes, so your own base always shows
## you in what you will deploy with; a base you visit leaves you as you came.
func suit_up() -> void:
	if read_only or not is_inside_tree() or (suited and suited_kit == suit_kit()):
		return
	var kit := suit_kit()
	if player != null and is_instance_valid(player) and player.is_inside_tree() and not player.is_dead:
		Loadout.refit(player, kit)
		suited_kit = kit
		_suit_locked(player)
		suited = true
		return
	var fresh := _new_player(spawn_point)
	add_child(fresh)
	player = fresh
	# Equipped once it stands in the room: the hand holds weapons in the world.
	suited_kit = kit
	Loadout.equip(fresh, suited_kit)
	_suit_locked(fresh)
	suited = true
	player_replaced.emit(fresh)


## Locks the suited player's weapons and has the range score their shots.
func _suit_locked(actor: Actor) -> void:
	actor.weapons_locked = true
	for weapon in actor.weapons:
		var gun := weapon as Gun
		if gun and not gun.has_meta("range_scored"):
			gun.set_meta("range_scored", true)
			gun.fired.connect(_on_range_shot.bind(gun))


## The watch's squad portal: opens a portal to `destination` (a
## `Portal.from_base()` id) in front of the player, in place of any open
## one. The base is a safe space, so it always may. Returns "" if it opened,
## or why not. Online your squad joins you on the other side; only you are
## in your base.
func open_portal(destination: String) -> String:
	if read_only:
		return "Not your base"
	if player == null or not is_instance_valid(player):
		return "not now"
	if destination not in Portal.from_base():
		return "No portal goes there"
	close_portal()
	portal = Portal.new()
	portal.name = "Portal"
	portal.destination = destination
	add_child(portal)
	portal.global_transform = Portal.spot(get_world_3d().direct_space_state, player.get_eye_position(),
			player.get_aim_dir(), global_position.y, portal.distance, portal.wall_gap)
	return ""


func close_portal() -> void:
	if portal != null and is_instance_valid(portal):
		portal.queue_free()
	portal = null


func _tick_portal(delta: float) -> void:
	if portal == null or not is_instance_valid(portal):
		portal = null
		return
	portal.tick(delta)
	if not portal.is_open():
		close_portal()
	elif player != null and is_instance_valid(player) and player not in portal.sent \
			and portal.contains(player.global_position):
		portal.sent.append(player)
		portal_entered.emit(portal.destination)


func _physics_process(delta: float) -> void:
	_tick_portal(delta)
	_tick_toy_throws(delta)
	_range_time += delta
	for target in targets:
		target.place(_range_time)
		target.cool(delta)
	for target in lane_targets:
		target.cool(delta)
	if not suited or player == null or not is_instance_valid(player):
		return
	_tick_course(delta)
	# Weapons are free only past the firing line, and never run dry there.
	var on_range := in_range(to_local(player.global_position))
	player.weapons_locked = not on_range
	if on_range:
		for weapon in player.weapons:
			var gun := weapon as Gun
			if gun and gun.reserve_ammo < gun.mag_size * 4:
				gun.reserve_ammo = gun.mag_size * 4


## A shot from the player's gun: scored if it was fired on the range.
func _on_range_shot(from: Vector3, to: Vector3, gun: Gun) -> void:
	if in_lane(to_local(from)):
		lane_shots += 1
		for target in lane_targets:
			if target.took(to):
				target.flash()
				lane_hits += 1
				target_hit.emit()
				break
		_update_lane_board()
		return
	if not in_range(to_local(from)):
		return
	range_shots += 1
	for target in targets:
		if target.took(to):
			target.flash()
			range_hits += 1
			range_last = "%s at %d m" % [gun.display_name, int(round(from.distance_to(to)))]
			target_hit.emit()
			break
	_update_board()


func _update_board() -> void:
	if range_board == null:
		return
	var accuracy := int(round(100.0 * range_hits / range_shots)) if range_shots > 0 else 0
	range_board.text = "SHOTS %d    HITS %d    ACCURACY %d%%" % [range_shots, range_hits, accuracy]
	if range_last != "":
		range_board.text += "\nLast hit: %s" % range_last
	else:
		range_board.text += "\nStep past the line and fire. Nothing here is lost."


func _update_lane_board() -> void:
	if lane_board == null:
		return
	lane_board.text = "HITS %d    SHOTS %d" % [lane_hits, lane_shots]
	var marks := PackedStringArray()
	for metres in lane_plates:
		marks.append(str(int(metres)))
	lane_board.text += "\nPlates at %s m" % ", ".join(marks)


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


## True if `point` (local to the base) is inside the hub or one of the
## spaces off it: a room, the corridor, the firing range or the course.
func inside(point: Vector3) -> bool:
	var half := room_size * 0.5
	if absf(point.x) < half.x and absf(point.z) < half.z:
		return true
	return room_at(point) != "" or in_corridor(point) or in_range(point) or in_course(point)


## The room (`BasePlan.ROOMS` id) whose open space holds `point` (local to the
## base), or "" for none. A room in its small form holds only its front part.
func room_at(point: Vector3) -> String:
	for socket: String in BasePlan.SOCKETS:
		var room: String = base_plan.get(socket, "")
		var local := socket_transform(socket).affine_inverse() * point
		if absf(local.x) <= socket_size.x * 0.5 and local.z <= 0.0 and local.z >= -room_depth(room):
			return room
	return ""


## The room's transform in the base: its origin on the floor in the middle of
## its doorway, local +Z out through the doorway into the hub, its space at
## negative z. "hub" is the base's own space.
func room_transform(room: String) -> Transform3D:
	if room == "hub":
		return Transform3D.IDENTITY
	return socket_transform(BasePlan.socket_of(base_plan, room))


## Where a socket's room stands (see `room_transform`). Two sockets in each
## side wall, two in the back wall either side of the corridor.
func socket_transform(socket: String) -> Transform3D:
	var side_x := room_size.x * 0.5 + 0.5
	var back_z := room_size.z * 0.5 + 0.5
	var pair := room_size.z * 0.25
	var back := corridor.x * 0.5 + 0.25 + socket_size.x * 0.5
	match socket:
		"W1":
			return _spot(Vector3(-side_x, 0, -pair), PI / 2.0)
		"W2":
			return _spot(Vector3(-side_x, 0, pair), PI / 2.0)
		"E1":
			return _spot(Vector3(side_x, 0, -pair), -PI / 2.0)
		"E2":
			return _spot(Vector3(side_x, 0, pair), -PI / 2.0)
		"N1":
			return _spot(Vector3(-back, 0, -back_z), 0.0)
		"N2":
			return _spot(Vector3(back, 0, -back_z), 0.0)
	return Transform3D.IDENTITY


## True if the room is in its whole form: its upgrade is owned (or it has
## none).
func room_open(room: String) -> bool:
	var opens := str(BasePlan.ROOMS.get(room, {}).get("opens", ""))
	return opens == "" or owns(opens)


## How deep the room is now: all of its socket once opened, else its small
## form.
func room_depth(room: String) -> float:
	return socket_size.z if room_open(room) else small_depth


## True if `point` (local to the base) is in the corridor between the back
## sockets that leads to the range.
func in_corridor(point: Vector3) -> bool:
	return absf(point.x) < corridor.x * 0.5 and point.z <= -room_size.z * 0.5 and point.z > -range_from()


## How far behind the hub's middle the range begins: past the back rooms and
## their back wall.
func range_from() -> float:
	return room_size.z * 0.5 + 0.5 + socket_size.z + 0.5


## True if `point` (local to the base) is inside the garage.
func in_garage(point: Vector3) -> bool:
	return room_at(point) == "garage"


## True if `point` (local to the base) is inside the firing range.
func in_range(point: Vector3) -> bool:
	var start := range_from()
	return point.z < -start and point.z > -start - range_size.z and absf(point.x) < range_size.x * 0.5


## True if `point` (local to the base) is inside the starter bunker's test
## lane (never once the firing range is bought: it takes its place).
func in_lane(point: Vector3) -> bool:
	if owns("firing_range"):
		return false
	var start := range_from()
	return point.z < -start and point.z > -start - lane_size.z and absf(point.x) < lane_size.x * 0.5


## True if `point` (local to the base) is inside the flight course's yard.
func in_course(point: Vector3) -> bool:
	var start := _course_z()
	return point.z < start and point.z > start - course_size.z and absf(point.x) < course_size.x * 0.5


## Where the flight course's yard begins: the range's end wall.
func _course_z() -> float:
	return -range_from() - range_size.z - 0.5


## The course's marks along the yard, as z (local to the base): the start
## line, each tower's centre and the finish line.
func course_marks() -> Dictionary:
	var start := _course_z() - 4.0
	var tower_a := start - 14.0
	var tower_b := tower_a - course_tower.z - course_gap
	return {"start": start, "tower_a": tower_a, "tower_b": tower_b,
			"finish": tower_b - course_tower.z * 0.5 - course_sprint}


## True if `lp` (local) stands on top of the tower centred at z `at`.
func _on_tower(lp: Vector3, at: float) -> bool:
	return absf(lp.x - _tower_x()) < course_tower.x * 0.5 + 0.2 and absf(lp.z - at) < course_tower.z * 0.5 + 0.2 \
			and lp.y > course_tower.y - 0.5 and player.is_on_floor()


func _tower_x() -> float:
	return course_size.x * 0.5 - course_tower.x * 0.5 - 4.0


## Times a run of the flight course: crossing the start line starts it,
## standing on the first tower ends the climb, landing on the second without
## touching the floor ends the gap, and crossing the finish line ends the
## sprint. Going back over the start line or leaving the yard cancels it.
func _tick_course(delta: float) -> void:
	var lp := to_local(player.global_position)
	var marks := course_marks()
	var crossed: bool = _course_prev_z >= marks.start and lp.z < marks.start and in_course(lp)
	_course_prev_z = lp.z
	if course_stage < 0:
		if crossed:
			course_stage = 0
			course_time = 0.0
			course_splits.clear()
			course_rig = player.flight.display_name if player.flight.enabled else "On foot"
			_update_course_board()
		return
	course_time += delta
	if not in_course(lp) or lp.z > marks.start:
		_end_course("Run cancelled. Cross the start line to go again.")
		return
	match course_stage:
		0:
			if _on_tower(lp, marks.tower_a):
				_course_split()
		1:
			if _on_tower(lp, marks.tower_b):
				_course_split()
			elif player.is_on_floor() and lp.y < 0.5:
				_end_course("%s fell in the gap. Back to the start line." % course_rig)
		2:
			if lp.z < marks.finish:
				_course_split()
				var total := course_time
				var best: float = course_best.get(course_rig, INF)
				course_best[course_rig] = minf(best, total)
				_end_course("%s: %.1f s   (climb %.1f, gap %.1f, sprint %.1f)%s" % [course_rig, total,
						course_splits[0], course_splits[1] - course_splits[0], course_splits[2] - course_splits[1],
						"   BEST" if total < best else ""])


func _course_split() -> void:
	course_splits.append(course_time)
	course_stage += 1
	_update_course_board()


func _end_course(result: String) -> void:
	course_stage = -1
	course_last = result
	_update_course_board()


func _update_course_board() -> void:
	if course_board == null:
		return
	var lines: Array[String] = ["CLIMB  >  GAP  >  SPRINT"]
	if course_stage >= 0 and course_stage < 3:
		lines.append("%s   %s" % [course_rig, ["climb", "gap", "sprint"][course_stage]])
	else:
		lines.append(course_last if course_last != "" else "Cross the start line with any rig. Nothing here is lost.")
	var bests: Array[String] = []
	for rig: String in course_best:
		bests.append("%s %.1f s" % [rig, course_best[rig]])
	if not bests.is_empty():
		lines.append("Best: " + "   ".join(bests))
	course_board.text = "\n".join(lines)


## True if `point` (local to the base) is inside the armory.
func in_armory(point: Vector3) -> bool:
	return room_at(point) == "armory"


## True if `point` (local to the base) is inside the workshop, the gunsmith's
## room.
func in_workshop(point: Vector3) -> bool:
	return room_at(point) == "workshop"


## Where a spot is in the base, and which way it faces: local +Z points out
## toward whoever looks at it. Each display kind has its room
## (`KIND_ROOMS`), and its spot is laid out in that room's space
## (`room_spot`), so it follows the room to whichever socket it stands in.
func spot_transform(kind: String, index: int) -> Transform3D:
	return room_transform(str(KIND_ROOMS.get(kind, "stores"))) * room_spot(kind, index)


## A spot in its room's own space (see `room_transform`: the doorway at z 0,
## the room at negative z, its side walls at x of plus and minus half its
## width). The small form puts what it has on its sealed wall, halfway back.
func room_spot(kind: String, index: int) -> Transform3D:
	var room := str(KIND_ROOMS.get(kind, "stores"))
	var whole := room_open(room)
	var back := -room_depth(room)
	var side := socket_size.x * 0.5
	var i := float(index)
	match kind:
		"rack_guns":
			# The back wall: three rows of four, facing the way in. The small
			# form's short rack is one row of four on its sealed wall.
			var col := float(index % 4)
			var row := float(index / 4)
			if not whole:
				return _spot(Vector3(-3.4 + 1.95 * col, 1.95, back + 0.3), 0.0)
			return _spot(Vector3(-3.0 + 2.0 * col, 3.05 - 1.1 * row, back + 0.3), 0.0)
		"heavy_wall":
			# Over the long guns on the back wall: one row of four.
			return _spot(Vector3(-3.0 + 2.0 * i, 4.4, back + 0.3), 0.0)
		"rack_sidearms":
			# The left-hand wall going in: two rows of four.
			var col := float(index % 4)
			var row := float(index / 4)
			return _spot(Vector3(-side + 0.3, 2.3 - 0.95 * row, -1.8 - 1.2 * col), PI / 2.0)
		"rack_melee":
			# The right-hand wall going in: one row, standing upright.
			return _spot(Vector3(side - 0.3, 1.3, -1.8 - 1.05 * i), -PI / 2.0)
		"armor_stand":
			# Along the back wall; the small form's one stands left.
			if not whole:
				return _spot(Vector3(-2.6, 0.0, back + 0.9), 0.0)
			return _spot(Vector3(-3.75 + 1.5 * i, 0.0, back + 1.0), 0.0)
		"helmet_shelf":
			# A shelf over the armor stands.
			if not whole:
				return _spot(Vector3(-3.1 + 1.0 * i, HELMET_SHELF_Y, back + 0.3), 0.0)
			return _spot(Vector3(-3.75 + 1.5 * i, HELMET_SHELF_Y, back + 0.3), 0.0)
		"rig_stand":
			# Down the right-hand wall; the small form's one stands right.
			if not whole:
				return _spot(Vector3(1.2, 0.0, back + 0.9), 0.0)
			return _spot(Vector3(side - 1.0, 0.0, -2.0 - 2.0 * i), -PI / 2.0)
		"chip_case":
			# A shelf down the left-hand wall.
			return _spot(Vector3(-side + 0.4, STORAGE_ROWS["chip_case"], -2.0 - 0.95 * i), PI / 2.0)
		"artifact_case":
			# The chip shelf's far end, past its six spots; the small form's
			# one by the way in.
			if not whole:
				return _spot(Vector3(-side + 0.4, STORAGE_ROWS["chip_case"], -2.2), PI / 2.0)
			return _spot(Vector3(-side + 0.4, STORAGE_ROWS["chip_case"], -2.0 - 0.95 * (6 + i)), PI / 2.0)
		"supplies":
			if not whole:
				return _spot(Vector3(-0.95 + 0.95 * i, STORAGE_ROWS[kind], back + 0.45), 0.0)
			return _spot(Vector3(-2.375 + 0.95 * i, STORAGE_ROWS[kind], back + 0.45), 0.0)
		"trophy":
			return _spot(Vector3(-3.325 + 0.95 * i, STORAGE_ROWS[kind], back + 0.45), 0.0)
		"bay":
			# Two by two, parked nose-out toward the way in.
			var col := float(index % 2)
			var row := float(index / 2)
			return _spot(Vector3(-2.3 + 4.6 * col, 0.0, -2.6 - 4.3 * row), 0.0)
	return _spot(Vector3(-3.0 + 1.1 * i, 1.1, back + 0.4), 0.0)


func _spot(at: Vector3, yaw: float) -> Transform3D:
	return Transform3D(Basis.from_euler(Vector3(0.0, yaw, 0.0)), at)


# --- The room ----------------------------------------------------------------

## The hub: floor, ceiling and walls, with a doorway in its side and back
## walls for each socket and the corridor to the range, and its lights. The
## rooms in the sockets are built with the upgrades (`_build_rooms`).
func _build_room() -> void:
	var x := room_size.x
	var y := room_size.y
	var z := room_size.z
	_floor(Vector2(x, z), Vector3.ZERO)
	_ceiling(Vector2(x, z), Vector3.ZERO, y)
	var door := room_door
	var pair := z * 0.25
	# Side walls: a doorway for each socket.
	for side: float in [-1.0, 1.0]:
		_wall_run(Vector3(side * (x * 0.5 + 0.25), 0, 0), Vector3(0, 0, 1), z + 1.0,
				[Vector2(-pair, door.x), Vector2(pair, door.x)], door.y, Vector3(-side, 0, 0))
	# The back wall: a doorway for each back socket and the corridor between.
	var back := corridor.x * 0.5 + 0.25 + socket_size.x * 0.5
	_wall_run(Vector3(0, 0, -z * 0.5 - 0.25), Vector3(1, 0, 0), x,
			[Vector2(-back, door.x), Vector2(0.0, corridor.x), Vector2(back, door.x)], door.y, Vector3.BACK)
	# The front wall, whole: the door out stands against it.
	_wall(Vector3(x + 1.0, y, 0.5), Vector3(0, y * 0.5, z * 0.5 + 0.25), Vector3.FORWARD)
	_build_corridor()
	_build_deploy_area()
	Look.interior(self, Color(0.56, 0.6, 0.66), 1.3)
	if Look.enabled:
		# Ceiling lamps over the floor, and a softer wash toward each wall.
		for at: Vector3 in [Vector3(-6, 4.8, -4), Vector3(6, 4.8, -4), Vector3(-6, 4.8, 5),
				Vector3(6, 4.8, 5), Vector3(0, 4.8, 0.5)]:
			var light := Look.lamp(Color(1.0, 0.9, 0.76), 3.2, 16.0)
			light.position = at
			add_child(light)


## A straight wall `length` long through `centre` (on the floor) along unit
## axis `along`, 0.5 thick, panelled on its `inward` face, with doorways cut
## through it: each `Vector2(at, width)` along the wall, `high` metres high,
## with the wall carried on over it.
func _wall_run(centre: Vector3, along: Vector3, length: float, gaps: Array, high: float, inward: Vector3) -> void:
	var y := room_size.y
	var cuts: Array = gaps.duplicate()
	cuts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var from := -length * 0.5
	var thick := Vector3(absf(along.z), 0, absf(along.x)) * 0.5
	for gap: Vector2 in cuts + [Vector2(length * 0.5 + 1.0, 0.0)]:
		var to := minf(gap.x - gap.y * 0.5, length * 0.5)
		if to - from > 0.01:
			var mid := centre + along * ((from + to) * 0.5)
			_wall(along.abs() * (to - from) + thick + Vector3(0, y, 0), mid + Vector3(0, y * 0.5, 0), inward)
		if gap.y > 0.0:
			var over := centre + along * gap.x
			_wall(along.abs() * gap.y + thick + Vector3(0, y - high, 0), over + Vector3(0, (y + high) * 0.5, 0), Vector3.ZERO)
			# A steel frame round the doorway on the hub's side.
			var frame := Color(0.2, 0.21, 0.23)
			var face := over + inward * 0.27
			for end: float in [-1.0, 1.0]:
				_target().add_child(_part(along.abs() * 0.14 + inward.abs() * 0.06 + Vector3(0, high, 0),
						face + along * (end * (gap.y * 0.5 + 0.07)) + Vector3(0, high * 0.5, 0), frame))
			_target().add_child(_part(along.abs() * (gap.y + 0.28) + inward.abs() * 0.06 + Vector3(0, 0.14, 0),
					face + Vector3(0, high + 0.07, 0), frame))
		from = gap.x + gap.y * 0.5


## The corridor from the hub's back wall to the range, between the two back
## sockets: a floor, a low ceiling and a light. Its walls are the back rooms'
## side walls; the range's door closes its far end (`_build_range`).
func _build_corridor() -> void:
	var start := room_size.z * 0.5
	var length := range_from() - start
	var mid := Vector3(0, 0, -start - length * 0.5)
	_floor(Vector2(corridor.x, length), mid)
	# The ceiling starts past the hub's wall, so it never lies along the
	# lintel over the way in (two faces in one plane shimmer).
	_ceiling(Vector2(corridor.x, length - 0.5), mid - Vector3(0, 0, 0.25), corridor.y)
	# Its side walls are the back rooms' walls: panel their faces.
	for side: float in [-1.0, 1.0]:
		_trim(Vector3(0.25, corridor.y, length - 0.5), Vector3(side * (corridor.x * 0.5 + 0.125), corridor.y * 0.5, mid.z - 0.25),
				Vector3(-side, 0, 0))
	if Look.enabled:
		var light := Look.lamp(Color(1.0, 0.94, 0.85), 2.0, 7.0)
		light.position = mid + Vector3(0, corridor.y - 0.5, 0)
		add_child(light)


## A small name plate over a doorway, on the hub's side: a dark plate with a
## lit edge in `color` along its top and the name on it. The one sign a room
## has. `where` is the doorway's middle on the floor, local +Z toward the
## reader.
func _name_plate(text: String, where: Transform3D, color: Color, high: float) -> Node3D:
	var plate := Node3D.new()
	plate.name = "Plate_%s" % text.to_pascal_case()
	# `where` is on the wall's far face: the plate stands just off its near one.
	plate.transform = where * Transform3D(Basis.IDENTITY, Vector3(0, high + 0.42, 0.53))
	var width := 0.32 + 0.17 * float(text.length())
	plate.add_child(_part(Vector3(width, 0.36, 0.04), Vector3.ZERO, Color(0.08, 0.085, 0.095)))
	plate.add_child(_part(Vector3(width, 0.025, 0.05), Vector3(0, 0.17, 0.005), color, true))
	var label := _label(text.to_upper(), color.lightened(0.25), 0.2)
	label.name = "Name"
	label.outline_size = 0
	label.position = Vector3(0, -0.01, 0.025)
	plate.add_child(label)
	return plate


## Builds every room in its socket (`base_plan`), each in its own node in its
## room's space: floor, ceiling and walls to its depth (`room_depth`), a
## sealed wall closing off the rest until its upgrade is owned, its
## furniture, lights and the name plate over its doorway. Called again
## whenever the plan or the upgrades change.
func _build_rooms() -> void:
	for socket: String in BasePlan.SOCKETS:
		var room: String = base_plan[socket]
		var node := Node3D.new()
		node.name = "Room_%s" % socket
		node.transform = socket_transform(socket)
		_keep(node)
		_into = node
		_build_shell(room)
		match room:
			"armory":
				_furnish_armory()
			"gear":
				_furnish_gear()
			"stores":
				_furnish_stores()
			"garage":
				_furnish_garage()
		_into = null
		_keep(_name_plate(BasePlan.title(room), socket_transform(socket), ROOM_COLORS.get(room, Color.WHITE), room_door.y))


## A room's shell in its own space, into `_into`: floor and ceiling to its
## depth, side walls, and a back wall (the sealed wall in its small form,
## dark steel with amber stripes), panelled inside, its front face panelled
## either side of the doorway, and two lamps.
func _build_shell(room: String) -> void:
	var w := socket_size.x
	var y := socket_size.y
	var depth := room_depth(room)
	var mid := Vector3(0, 0, -depth * 0.5)
	# The floor runs on under the doorway in the hub's wall.
	_floor(Vector2(w, depth + 0.5), mid + Vector3(0, 0, 0.25))
	_ceiling(Vector2(w, depth), mid, y)
	for side: float in [-1.0, 1.0]:
		_wall(Vector3(0.25, y, depth + 0.5), Vector3(side * (w * 0.5 + 0.125), y * 0.5, mid.z), Vector3(-side, 0, 0))
	if room_open(room):
		_wall(Vector3(w, y, 0.5), Vector3(0, y * 0.5, -depth - 0.25), Vector3.BACK)
	else:
		var seal := _box(Vector3(w, y, 0.5), Vector3(0, y * 0.5, -depth - 0.25), _shell("seal"))
		seal.name = "SealedWall"
		_trim(Vector3(w, y, 0.5), Vector3(0, y * 0.5, -depth - 0.25), Vector3.BACK)
		for at_y: float in [0.45, y - 0.75]:
			_target().add_child(_part(Vector3(w - 0.4, 0.12, 0.04), Vector3(0, at_y, -depth + 0.11), Color(1.0, 0.62, 0.22), true))
	# The hub's wall is the room's front: panel it either side of the doorway.
	var piece := (w - room_door.x) * 0.5
	for side: float in [-1.0, 1.0]:
		_trim(Vector3(piece, y, 0.5), Vector3(side * (room_door.x * 0.5 + piece * 0.5), y * 0.5, 0.25), Vector3.FORWARD)
	if Look.enabled:
		for at_z: float in ([-depth * 0.3, -depth * 0.75] if room_open(room) else [-depth * 0.5]):
			var light := Look.lamp(Color(1.0, 0.92, 0.8), 2.8, 9.0)
			light.position = Vector3(0, y - 1.3, at_z)
			_target().add_child(light)


## The armory's rack: a dark band behind the weapons on each of its walls and
## a light bar over each, so they read as one rack.
func _furnish_armory() -> void:
	var w := socket_size.x
	var back := -room_depth("armory")
	var band := Color(0.13, 0.13, 0.14)
	var glow := Color(1.0, 0.93, 0.8)
	var high := 4.0 if room_open("armory") else 2.8
	_target().add_child(_part(Vector3(w - 0.8, high - 0.2, 0.03), Vector3(0, (high + 0.2) * 0.5 + 0.05, back + 0.12), band))
	_target().add_child(_part(Vector3(w - 1.0, 0.05, 0.12), Vector3(0, high + 0.25, back + 0.2), glow, true))
	var along := -back - 1.2
	for side: float in [-1.0, 1.0]:
		_target().add_child(_part(Vector3(0.03, 2.5, along), Vector3(side * (w * 0.5 - 0.12), 1.85, -0.6 - along * 0.5), band))
		_target().add_child(_part(Vector3(0.12, 0.05, along - 0.2), Vector3(side * (w * 0.5 - 0.2), 3.25, -0.6 - along * 0.5), glow, true))


## The gear hall: a low plate the stands stand on along the back wall (and
## down the right-hand wall once whole), the chip shelf down the left-hand
## wall, and the helmet shelf over the armor stands.
func _furnish_gear() -> void:
	var w := socket_size.x
	var back := -room_depth("gear")
	var plate := Color(0.2, 0.21, 0.23)
	var accent := Color(0.45, 0.9, 1.0)
	var steel := Color(0.24, 0.25, 0.27)
	_target().add_child(_part(Vector3(w - 0.6, 0.03, 1.8), Vector3(0, 0.016, back + 1.0), plate))
	_target().add_child(_part(Vector3(w - 0.6, 0.035, 0.06), Vector3(0, 0.02, back + 1.9), accent, true))
	_target().add_child(_part(Vector3(w - 0.6, 0.05, 0.4), Vector3(0, HELMET_SHELF_Y - 0.22, back + 0.3), steel))
	if room_open("gear"):
		_target().add_child(_part(Vector3(1.8, 0.03, -back - 3.0), Vector3(w * 0.5 - 1.0, 0.016, back * 0.5 - 0.5), plate))
		_shelf(Vector3(-w * 0.5 + 0.4, STORAGE_ROWS["chip_case"], -5.3), 8.0, true)
	else:
		_shelf(Vector3(-w * 0.5 + 0.4, STORAGE_ROWS["chip_case"], -2.2), 1.2, true)


## The stores: shelving across the back wall, a shelf for the supplies and
## one over it for the trophies once the room is whole.
func _furnish_stores() -> void:
	var back := -room_depth("stores")
	var whole := room_open("stores")
	var width := 7.6 if whole else 3.0
	var steel := Color(0.24, 0.25, 0.27)
	for kind: String in (["supplies", "trophy"] if whole else ["supplies"]):
		_shelf(Vector3(0, STORAGE_ROWS[kind], back + 0.45), width, false)
	for side: float in [-1.0, 1.0]:
		_target().add_child(_part(Vector3(0.08, (2.7 if whole else 1.5), 0.6), Vector3(side * (width * 0.5 + 0.05), (1.35 if whole else 0.75), back + 0.45), steel))


## One shelf: a steel board with a lit lip, `length` long, its top just under
## `at` (where what is on it stands), along the wall the room's x (`side_on`
## false) or z (`side_on` true) runs.
func _shelf(at: Vector3, length: float, side_on: bool) -> void:
	var steel := Color(0.24, 0.25, 0.27)
	var board := Vector3(0.55, 0.05, length) if side_on else Vector3(length, 0.05, 0.55)
	_target().add_child(_part(board, at + Vector3(0, -0.33, 0), steel))
	var lip := Vector3(0.02, 0.02, length) if side_on else Vector3(length, 0.02, 0.02)
	var out := Vector3(0.28, 0, 0) if side_on else Vector3(0, 0, 0.28)
	_target().add_child(_part(lip, at + Vector3(0, -0.31, 0) + out, Color(0.45, 0.9, 1.0), true))


## The garage: hazard stripes framing the way in and a tool wall at the back
## once whole. The bays are painted by each parked vehicle's display.
func _furnish_garage() -> void:
	var w := socket_size.x
	var hazard := Color(0.85, 0.65, 0.15)
	for side: float in [-1.0, 1.0]:
		_target().add_child(_part(Vector3(0.2, 0.025, 1.0), Vector3(side * (room_door.x * 0.5 - 0.1), 0.015, -0.5), hazard.darkened(0.3)))
	if room_open("garage"):
		_target().add_child(_part(Vector3(w - 1.4, 1.6, 0.04), Vector3(0, 1.9, -socket_size.z + 0.15), Color(0.2, 0.2, 0.22)))


## The firing range: a long hall behind the back wall. Past the firing line
## your weapons are free and never run dry, and targets stand, slide and fly
## at set distances. A board over the lane keeps score. Nothing here is real:
## no damage is dealt and no mastery is earned (only use in a world pays).
func _build_range() -> void:
	var wall_mat := _shell("wall")
	var wall_z := range_from()
	var width := range_size.x
	var y := range_size.y
	var length := range_size.z
	var mid_z := -wall_z - length * 0.5
	_floor(Vector2(width, length), Vector3(0, 0, mid_z))
	_ceiling(Vector2(width, length), Vector3(0, 0, mid_z), y)
	# The end wall, with the door out to the flight course near its left end.
	var end_z := -wall_z - length - 0.25
	var door_x := course_door.x
	var door_w := course_door.y
	var left := (door_x - door_w * 0.5) - (-width * 0.5 - 0.5)
	var right := (width * 0.5 + 0.5) - (door_x + door_w * 0.5)
	_wall(Vector3(left, y, 0.5), Vector3(-width * 0.5 - 0.5 + left * 0.5, y * 0.5, end_z), Vector3.BACK)
	_wall(Vector3(right, y, 0.5), Vector3(width * 0.5 + 0.5 - right * 0.5, y * 0.5, end_z), Vector3.BACK)
	_wall(Vector3(door_w, y - course_door.z, 0.5), Vector3(door_x, (y + course_door.z) * 0.5, end_z), Vector3.ZERO)
	for side: float in [-1.0, 1.0]:
		_wall(Vector3(0.5, y, length), Vector3(side * (width * 0.5 + 0.25), y * 0.5, mid_z), Vector3(-side, 0, 0))
	# The near wall: the back rooms' back walls either side, the end of the
	# corridor with the door in it, and over all of them the wall goes on up.
	var near := -wall_z + 0.25
	_wall_run(Vector3(0, 0, near), Vector3(1, 0, 0), corridor.x, [Vector2(0.0, range_door.x)], range_door.y, Vector3.BACK)
	_wall(Vector3(width + 1.0, y - socket_size.y, 0.5), Vector3(0, (y + socket_size.y) * 0.5, near), Vector3.ZERO)
	# Panelled on the range's side either side of the door.
	var piece := (width - range_door.x) * 0.5
	for side: float in [-1.0, 1.0]:
		_trim(Vector3(piece, socket_size.y, 0.5), Vector3(side * (range_door.x * 0.5 + piece * 0.5), socket_size.y * 0.5, near), Vector3.FORWARD)
	var accent := Color(1.0, 0.62, 0.22)
	var line_z := -wall_z - firing_line
	# The firing line: a counter either side of a gap to walk through, and a
	# stripe on the floor.
	var counter := (width - 3.0) * 0.5
	for side: float in [-1.0, 1.0]:
		_box(Vector3(counter, 1.0, 0.5), Vector3(side * (1.5 + counter * 0.5), 0.5, line_z), wall_mat)
	var stripe := _part(Vector3(width, 0.03, 0.12), Vector3(0, 0.02, line_z - 0.4), accent, true)
	stripe.name = "FiringLine"
	add_child(stripe)
	# Distance marks down the lane, every 5 m.
	for metres: int in range(5, int(length - firing_line), 5):
		var mark := _part(Vector3(width, 0.02, 0.06), Vector3(0, 0.015, line_z - float(metres)), Color(0.75, 0.75, 0.72))
		add_child(mark)
		var number := _label("%d m" % metres, Color(0.85, 0.85, 0.8), 0.25)
		number.position = Vector3(-width * 0.5 + 0.4, 0.05, line_z - float(metres))
		number.rotation.x = -PI / 2.0
		add_child(number)
	# The corridor's name plate in the hub, over its way in.
	range_sign = _name_plate("Firing range", _spot(Vector3(0, 0, -room_size.z * 0.5 - 0.5), 0.0), accent, corridor.y)
	range_sign.name = "RangeSign"
	add_child(range_sign)
	# The scoreboard: a screen hung over the lane on two rods, facing the
	# line, with the score written on it.
	var board := Node3D.new()
	board.name = "ScoreBoard"
	board.position = Vector3(0, 4.2, line_z - 4.0)
	add_child(board)
	board.add_child(_part(Vector3(4.2, 1.15, 0.12), Vector3(0, 0, -0.08), Color(0.1, 0.11, 0.12)))
	board.add_child(_part(Vector3(4.0, 0.98, 0.02), Vector3(0, 0, -0.01), Color(0.02, 0.05, 0.07), true))
	board.add_child(_part(Vector3(4.2, 0.04, 0.03), Vector3(0, -0.6, 0.0), accent, true))
	for x: float in [-1.6, 1.6]:
		board.add_child(_part(Vector3(0.05, y - 4.8, 0.05), Vector3(x, (y - 4.2) * 0.5 + 0.3, -0.08), Color(0.3, 0.31, 0.33)))
	range_board = _label("", Color(0.6, 0.95, 1.0), 0.17)
	range_board.name = "RangeBoard"
	range_board.outline_size = 0
	range_board.position = Vector3(0, 0, 0.02)
	board.add_child(range_board)
	_update_board()
	_build_targets(line_z)
	if Look.enabled:
		for at_z: float in [-wall_z - 3.0, line_z, line_z - 12.0, line_z - 24.0, line_z - 36.0]:
			var light := Look.lamp(Color(1.0, 0.94, 0.85), 3.5, 14.0)
			light.position = Vector3(0, y - 1.0, at_z)
			add_child(light)


## The starter bunker's test lane: bare concrete behind the back wall's door,
## 3 m wide and about 15 m long, with a waist-high counter to shoot over and
## three plates that drop when hit and stand again, at set distances from the
## counter, and a small board on the end wall that counts hits. It sits in
## the range's own hall, so the weapons are free there like on the range
## (`in_range`), but it is sealed at its far end by the firing range's
## bulkhead; buying the range clears all of this. Nothing here is real damage.
func _build_test_lane() -> void:
	var width := lane_size.x
	var height := lane_size.y
	var length := lane_size.z
	var start := -range_from()
	var mid := start - length * 0.5
	var end := start - length
	var accent := Color(1.0, 0.62, 0.22)
	var first := get_child_count()
	for side: float in [-1.0, 1.0]:
		_wall(Vector3(0.5, height, length), Vector3(side * (width * 0.5 + 0.25), height * 0.5, mid), Vector3(-side, 0, 0))
	_ceiling(Vector2(width, length), Vector3(0, 0, mid), height)
	# Bare concrete over the range's floor marks.
	add_child(_part(Vector3(width, 0.04, length), Vector3(0, 0.02, mid), Color(0.38, 0.38, 0.37)))
	var line_z := start - lane_counter
	_box(Vector3(width, 1.0, 0.5), Vector3(0, 0.5, line_z), _shell("wall"))
	add_child(_part(Vector3(width, 0.04, 0.6), Vector3(0, 1.02, line_z), accent, true))
	var plate_x: Array[float] = [-0.8, 0.8, -0.8]
	for i in lane_plates.size():
		var metres := lane_plates[i]
		var at := Vector3(plate_x[i % plate_x.size()], 0, line_z - metres)
		var target := _make_target("plate", at)
		target.pop_time = lane_pop
		target.name = "LanePlate_%d" % i
		add_child(target)
		lane_targets.append(target)
		var number := _label("%d m" % int(metres), Color(0.85, 0.85, 0.8), 0.25)
		number.position = Vector3(-width * 0.5 + 0.5, 0.06, line_z - metres)
		number.rotation.x = -PI / 2.0
		add_child(number)
	var board := Node3D.new()
	board.name = "LaneBoard"
	board.position = Vector3(0, 2.95, end + 0.08)
	board.add_child(_part(Vector3(2.4, 0.55, 0.05), Vector3(0, 0, -0.03), Color(0.1, 0.11, 0.12)))
	board.add_child(_part(Vector3(2.28, 0.45, 0.02), Vector3(0, 0, 0.0), Color(0.02, 0.05, 0.07), true))
	lane_board = _label("", Color(0.6, 0.95, 1.0), 0.12)
	lane_board.name = "LaneScore"
	lane_board.outline_size = 0
	lane_board.position = Vector3(0, 0, 0.02)
	board.add_child(lane_board)
	add_child(board)
	_update_lane_board()
	if Look.enabled:
		var light := Look.lamp(Color(1.0, 0.94, 0.85), 3.0, 10.0)
		light.position = Vector3(0, height - 0.4, mid)
		add_child(light)
	# All of it goes with the upgrade: one node to clear.
	var lane := Node3D.new()
	lane.name = "TestLane"
	for node in get_children().slice(first):
		remove_child(node)
		lane.add_child(node)
	_keep(lane)
	_add_bulkhead("firing_range", _spot(Vector3(0, 0, end - 0.25), 0.0), "slab", Vector2(width, height))


## The flight course's yard past the range: open to the sky, low walls,
## the climb tower with its ramp, the gap to the second tower, the sprint
## to the finish, and the board at the start that times each run.
func _build_course() -> void:
	var start := _course_z()
	var w := course_size.x
	var h := course_size.y
	var length := course_size.z
	var mid := start - length * 0.5
	var accent := Color(0.45, 0.85, 1.0)
	_floor(Vector2(w, length), Vector3(0, 0, mid))
	_wall(Vector3(w + 1.0, h, 0.5), Vector3(0, h * 0.5, start - length - 0.25), Vector3.BACK)
	for side: float in [-1.0, 1.0]:
		_wall(Vector3(0.5, h, length), Vector3(side * (w * 0.5 + 0.25), h * 0.5, mid), Vector3(-side, 0, 0))
	# The range's end wall closes the yard's near end either side of the door;
	# past the range's width the yard is closed by a wall of its own.
	var reach := (w - range_size.x) * 0.5
	for side: float in [-1.0, 1.0]:
		_wall(Vector3(reach, h, 0.5), Vector3(side * (range_size.x * 0.5 + 0.5 + reach * 0.5), h * 0.5, start + 0.25), Vector3.FORWARD)
	var marks := course_marks()
	var tx := _tower_x()
	var tower := _shell("wall")
	for at: float in [marks.tower_a, marks.tower_b]:
		var block := _box(course_tower, Vector3(tx, course_tower.y * 0.5, at), tower)
		block.name = "CourseTower"
		add_child(_part(Vector3(course_tower.x, 0.04, course_tower.z), Vector3(tx, course_tower.y + 0.02, at), accent.darkened(0.5), true))
	# The ramp up the first tower's side, for rigs that cannot climb.
	var rise := course_tower.y
	var run := rise / tan(deg_to_rad(34.0))
	var slope := sqrt(rise * rise + run * run)
	var ramp := _box(Vector3(slope, 0.4, 3.0), Vector3(tx - course_tower.x * 0.5 - run * 0.5, rise * 0.5 - 0.2, marks.tower_a), tower)
	ramp.name = "CourseRamp"
	ramp.rotation.z = atan2(rise, run)
	for line: Array in [["START", marks.start], ["FINISH", marks.finish]]:
		add_child(_part(Vector3(w, 0.03, 0.2), Vector3(0, 0.02, line[1]), accent, true))
		var word := _label(line[0], accent, 0.5)
		word.position = Vector3(0, 0.05, line[1] + 0.8)
		word.rotation.x = -PI / 2.0
		add_child(word)
	for stage: Array in [["CLIMB", marks.tower_a], ["GAP", (marks.tower_a + marks.tower_b) * 0.5],
			["SPRINT", marks.tower_b - course_tower.z * 0.5 - course_sprint * 0.5]]:
		var word := _label(stage[0], accent, 0.4)
		word.position = Vector3(-w * 0.5 + 0.06, 3.0, stage[1])
		word.rotation.y = PI / 2.0
		add_child(word)
	var title := _label("FLIGHT COURSE", accent, 0.36)
	# Over the door, on the range's side of its end wall.
	title.position = Vector3(course_door.x, course_door.z + 0.5, start + 0.56)
	add_child(title)
	# The board: hung over the yard just past the start, facing the way in.
	var board := Node3D.new()
	board.name = "CourseBoard"
	board.position = Vector3(-w * 0.25, 3.4, marks.start - 3.0)
	add_child(board)
	board.add_child(_part(Vector3(6.2, 1.3, 0.12), Vector3(0, 0, -0.08), Color(0.1, 0.11, 0.12)))
	board.add_child(_part(Vector3(6.0, 1.12, 0.02), Vector3(0, 0, -0.01), Color(0.02, 0.05, 0.07), true))
	for x: float in [-2.6, 2.6]:
		board.add_child(_part(Vector3(0.05, 3.4, 0.05), Vector3(x, -1.7, -0.08), Color(0.3, 0.31, 0.33)))
	course_board = _label("", Color(0.6, 0.95, 1.0), 0.16)
	course_board.name = "CourseText"
	course_board.outline_size = 0
	course_board.position = Vector3(0, 0, 0.02)
	board.add_child(course_board)
	_update_course_board()
	if Look.enabled:
		for at_z: float in [marks.start, marks.tower_a, marks.tower_b, marks.finish]:
			var light := Look.lamp(Color(0.85, 0.92, 1.0), 4.0, 22.0)
			light.position = Vector3(0, 9.0, at_z)
			add_child(light)


## Standing plates at 10, 20, 30 and 40 m, sliders at 15 and 35 m, and drones
## circling high up at 14 to 30 m for shooting from a rig.
func _build_targets(line_z: float) -> void:
	var specs := [
		{"at": Vector3(-3.0, 0, line_z - 10.0), "kind": "plate"},
		{"at": Vector3(3.0, 0, line_z - 20.0), "kind": "plate"},
		{"at": Vector3(-2.0, 0, line_z - 30.0), "kind": "plate"},
		{"at": Vector3(0.0, 0, line_z - 40.0), "kind": "plate"},
		{"at": Vector3(0.0, 0, line_z - 15.0), "kind": "slider"},
		{"at": Vector3(0.0, 0, line_z - 35.0), "kind": "slider"},
		{"at": Vector3(0.0, 6.0, line_z - 18.0), "kind": "drone", "phase": 0.0},
		{"at": Vector3(0.0, 7.0, line_z - 26.0), "kind": "drone", "phase": TAU / 3.0},
		{"at": Vector3(0.0, 5.0, line_z - 14.0), "kind": "drone", "phase": TAU * 2.0 / 3.0},
		{"at": Vector3(0.0, 7.0, line_z - 30.0), "kind": "drone", "phase": TAU / 2.0},
	]
	for spec: Dictionary in specs:
		var target := _make_target(spec["kind"], spec["at"], spec.get("phase", 0.0))
		target.name = "Target_%s_%d" % [target.kind, targets.size()]
		add_child(target)
		targets.append(target)


## One range target of this kind standing (or flying) at `at`: a plate on a
## post or a drone, with its collision. The caller names it and adds it.
func _make_target(kind: String, at: Vector3, phase := 0.0) -> RangeTarget:
	var target := RangeTarget.new()
	target.kind = kind
	target.home = at
	target.phase = phase
	target.position = at
	var face := Color(0.95, 0.9, 0.8)
	var size := Vector3(0.8, 1.6, 0.1)
	var centre := Vector3(0, 1.3, 0)
	if kind == "drone":
		size = Vector3(0.7, 0.3, 0.7)
		centre = Vector3.ZERO
		face = Color(0.4, 0.9, 1.0)
	else:
		target.add_child(_part(Vector3(0.08, 0.5, 0.08), Vector3(0, 0.25, 0), Color(0.3, 0.3, 0.32)))
	target.size = size
	target.centre = centre
	target.plate = _part(size, centre, face, kind == "drone")
	target.add_child(target.plate)
	if kind != "drone":
		# Rings on the plate, so a hit near the middle reads as one.
		target.add_child(_part(Vector3(0.4, 0.4, 0.02), centre + Vector3(0, 0.2, 0.06), Color(0.8, 0.25, 0.2)))
		target.add_child(_part(Vector3(0.14, 0.14, 0.03), centre + Vector3(0, 0.2, 0.07), Color(0.95, 0.9, 0.8)))
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = centre
	target.add_child(col)
	return target


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
	_target().add_child(body)
	return body


## Where the shell's builders put what they make: the room being built
## (`_into`, in that room's own space) or the base itself.
func _target() -> Node3D:
	return _into if _into != null else self


## The base's shell is steel, not rock: dark plated floors, panelled walls
## between ribs and a ceiling grid. One material for each part.
func _shell(part: String) -> Material:
	match part:
		"floor":
			return Look.surface("metal", {"tint": Color(0.62, 0.64, 0.68), "grime": 0.3, "scale": 0.5, "metal": 0.1, "rough_mult": 1.5})
		"ceiling":
			return Look.surface("metal", {"tint": Color(0.42, 0.44, 0.47), "grime": 0.2, "scale": 0.5, "metal": 0.1, "rough_mult": 1.4})
		"seal":
			return Look.surface("metal", {"tint": Color(0.42, 0.43, 0.46), "grime": 0.3, "scale": 0.4, "metal": 0.15, "rough_mult": 1.3})
	return Look.surface("metal", {"tint": Color(0.66, 0.69, 0.73), "grime": 0.15, "scale": 0.4, "metal": 0.15, "rough_mult": 1.3})


## A plated floor `size` across (x, z) centred on `at`, its top at y 0, with a
## seam every `plate_size` metres.
func _floor(size: Vector2, at: Vector3) -> void:
	_box(Vector3(size.x, 0.5, size.y), at + Vector3(0, -0.25, 0), _shell("floor"))
	var seam := Color(0.14, 0.15, 0.17)
	var x := -size.x * 0.5 + plate_size
	while x < size.x * 0.5 - 0.1:
		_target().add_child(_part(Vector3(0.035, 0.008, size.y), at + Vector3(x, 0.004, 0), seam))
		x += plate_size
	var z := -size.y * 0.5 + plate_size
	while z < size.y * 0.5 - 0.1:
		_target().add_child(_part(Vector3(size.x, 0.008, 0.035), at + Vector3(0, 0.004, z), seam))
		z += plate_size


## A ceiling over a space `size` across centred on `at`, `height` up: a grid of
## beams with a light panel in every other bay of it.
func _ceiling(size: Vector2, at: Vector3, height: float) -> void:
	_box(Vector3(size.x, 0.5, size.y), at + Vector3(0, height + 0.25, 0), _shell("ceiling"))
	var beam := Color(0.2, 0.21, 0.23)
	var glow := Color(0.92, 0.95, 1.0)
	var cols := maxi(1, int(round(size.x / beam_spacing)))
	var rows := maxi(1, int(round(size.y / beam_spacing)))
	var step := Vector2(size.x / cols, size.y / rows)
	for i in range(1, cols):
		_target().add_child(_part(Vector3(0.16, 0.2, size.y), at + Vector3(-size.x * 0.5 + step.x * i, height - 0.1, 0), beam))
	for j in range(1, rows):
		_target().add_child(_part(Vector3(size.x, 0.2, 0.16), at + Vector3(0, height - 0.1, -size.y * 0.5 + step.y * j), beam))
	for i in cols:
		for j in rows:
			if (i + j) % 2 == 0:
				var centre := Vector3(-size.x * 0.5 + step.x * (i + 0.5), height - 0.02, -size.y * 0.5 + step.y * (j + 0.5))
				_target().add_child(_part(Vector3(minf(step.x * 0.5, 1.6), 0.03, minf(step.y * 0.3, 0.6)), at + centre, glow, true))


## A wall: a box like `_box`, panelled on the face toward `inward` (a unit
## axis, or zero for a wall that shows no face) with ribs every
## `rib_spacing` metres, a kick plate at the floor and a rail at the top.
func _wall(size: Vector3, at: Vector3, inward: Vector3) -> void:
	_box(size, at, _shell("wall"))
	_trim(size, at, inward)


## The panelling `_wall` puts on a wall `size` big centred on `at`, on its
## face toward `inward`, without the wall itself: for a face of a wall built
## by someone else (the hub's wall seen from a room). Every part stands a
## little off the face, and the ribs further than the kick plate and rail,
## so no two faces share a plane.
func _trim(size: Vector3, at: Vector3, inward: Vector3) -> void:
	if inward == Vector3.ZERO:
		return
	var along_x := absf(inward.z) > 0.5
	var length := size.x if along_x else size.z
	var depth := (size.z if along_x else size.x) * 0.5
	var face := at + inward * depth
	var bottom := at.y - size.y * 0.5
	var rib := Color(0.3, 0.32, 0.35)
	var kick := Color(0.18, 0.19, 0.21)
	var span := func(long: float, high: float, thick: float) -> Vector3:
		return Vector3(long, high, thick) if along_x else Vector3(thick, high, long)
	_target().add_child(_part(span.call(length, 0.25, 0.06), face + inward * 0.03 + Vector3(0, bottom + 0.125 - at.y, 0), kick))
	_target().add_child(_part(span.call(length, 0.12, 0.06), face + inward * 0.03 + Vector3(0, bottom + size.y - 0.3 - at.y, 0), rib))
	var count := int(floor(length / rib_spacing))
	if count < 1:
		return
	var gap := length / float(count + 1)
	for i in range(1, count + 1):
		var offset := -length * 0.5 + gap * i
		var rib_at := face + inward * 0.04 + (Vector3(offset, 0, 0) if along_x else Vector3(0, 0, offset))
		_target().add_child(_part(span.call(0.16, size.y - 0.4, 0.08), rib_at + Vector3(0, 0.05, 0), rib))


## The deploy area along the hub's front wall, right of the door: a darker
## plate in the floor where the wall mirror hangs, with room in front to open
## a portal. No sign: the mirror says what it is for.
func _build_deploy_area() -> void:
	var wall_z := room_size.z * 0.5
	var mid_x := (DEPLOY_FROM_X + DEPLOY_TO_X) * 0.5
	var width := DEPLOY_TO_X - DEPLOY_FROM_X
	add_child(_part(Vector3(width, 0.012, DEPLOY_DEPTH), Vector3(mid_x, 0.006, wall_z - DEPLOY_DEPTH * 0.5), Color(0.2, 0.21, 0.23)))
	add_child(_part(Vector3(width, 0.014, 0.05), Vector3(mid_x, 0.007, wall_z - DEPLOY_DEPTH), Color(0.3, 0.31, 0.33)))


func _build_door() -> void:
	door = Door.new()
	door.name = "Door"
	door.base = self
	door.position = Vector3(0, 1.3, room_size.z * 0.5 - 0.15)
	# Like the displays, its local +Z points into the room.
	door.rotation.y = PI
	var size := Vector3(2.2, 2.6, 0.3)
	_add_collision(door, size, Vector3.ZERO)
	# A pair of steel leaves in a heavy frame, with a lit seam between them
	# and a lit header: a door, not a glowing slab.
	var steel := Color(0.3, 0.32, 0.35)
	var frame := Color(0.16, 0.17, 0.19)
	var accent := Color(1.0, 0.62, 0.22)
	door.add_child(_part(Vector3(2.7, 0.3, 0.36), Vector3(0, 1.45, 0), frame))
	for side: float in [-1.0, 1.0]:
		door.add_child(_part(Vector3(0.25, 2.9, 0.36), Vector3(side * 1.22, 0.15, 0), frame))
		door.add_child(_part(Vector3(1.04, 2.56, 0.12), Vector3(side * 0.54, 0.0, 0), steel))
		door.add_child(_part(Vector3(0.6, 0.08, 0.02), Vector3(side * 0.54, 0.2, 0.07), frame))
	door.add_child(_part(Vector3(0.04, 2.56, 0.13), Vector3.ZERO, accent, true))
	door.add_child(_part(Vector3(2.2, 0.06, 0.05), Vector3(0, 1.36, 0.17), accent, true))
	var sign_label := _label("EXIT", accent, 0.3)
	sign_label.position = Vector3(0, 1.85, 0.06)
	door.add_child(sign_label)
	add_child(door)


func _build_stations() -> void:
	for id: String in STATIONS:
		if not has_station(id):
			continue
		var info: Dictionary = STATIONS[id]
		var console := Station.new()
		console.name = "Station_%s" % id
		console.base = self
		console.id = id
		console.transform = station_transform(id)
		_dress_console(console, info["color"], str(info["prompt"]), station_title(id))
		add_child(console)
		_gated.append(console)
		stations.append(console)


## Where a station stands in the base and which way it faces (local +Z toward
## whoever uses it): its spot in its room's space, wherever that room stands.
func station_transform(id: String) -> Transform3D:
	var info: Dictionary = STATIONS[id]
	return room_transform(str(info["room"])) * _spot(info["at"], info["yaw"])


## A console's cabinet, stripe and screen: a cabinet with a stripe of `color`
## and a monitor on top whose idle face carries its name and `prompt`. The
## live screen is mounted in front of it (`Station.screen`). Its name is on
## the screen and on a small plate on the cabinet's front, never floating
## over it.
func _dress_console(console: Station, color: Color, prompt: String, title: String) -> void:
	var dark := Color(0.17, 0.17, 0.19)
	console.add_child(_part(Vector3(1.2, 1.0, 0.5), Vector3(0, 0.5, 0), dark))
	console.add_child(_part(Vector3(1.22, 0.06, 0.52), Vector3(0, 0.3, 0), color, true))
	console.add_child(_part(Vector3(0.12, 0.25, 0.12), Vector3(0, 1.1, 0), dark))
	_add_collision(console, Vector3(1.3, 1.7, 0.7), Vector3(0, 0.85, 0))
	var screen := Node3D.new()
	screen.name = "Screen"
	screen.position = Vector3(0, 1.62, 0.05)
	screen.rotation.x = -0.08
	screen.add_child(_part(Vector3(SCREEN_SIZE.x + 0.08, SCREEN_SIZE.y + 0.08, 0.06), Vector3(0, 0, -0.035), dark))
	var idle := _part(Vector3(SCREEN_SIZE.x, SCREEN_SIZE.y, 0.01), Vector3.ZERO, color.darkened(0.82), true)
	idle.name = "Idle"
	screen.add_child(idle)
	var hint := _label("%s\n%s" % [title.to_upper(), prompt], color.lightened(0.2), 0.11)
	hint.name = "IdleText"
	hint.position = Vector3(0, 0, 0.012)
	screen.add_child(hint)
	console.add_child(screen)
	console.screen = screen
	var name_plate := _label(title.to_upper(), color, 0.09)
	name_plate.name = "Title"
	name_plate.outline_size = 0
	name_plate.position = Vector3(0, 0.72, 0.26)
	console.add_child(name_plate)


## Builds everything that depends on the upgrades and the plan: the rooms
## in their sockets, the consoles, the bench, the plan table, and a bulkhead
## for every upgrade still to buy, each in the room it opens. Called again
## whenever either changes.
func _build_upgrades() -> void:
	for node in _gated:
		if is_instance_valid(node):
			if node.get_parent():
				node.get_parent().remove_child(node)
			node.queue_free()
	_gated.clear()
	stations.clear()
	bulkheads.clear()
	lane_targets.clear()
	lane_board = null
	_build_rooms()
	_build_bench()
	_build_stations()
	_build_plan_table()
	_build_gates()


## The bulkheads: each room still in its small form has one by its sealed
## wall, the garage a hatch where its second bay will be, the armory's heavy
## wall a post at the back once the armory is whole, the range a slab at the
## test lane's end, the bench's own upgrades a tag on the bench and the
## finish a post beside the plan table. Plus what an upgrade adds once owned: the
## garage's lift and the finish's trim.
func _build_gates() -> void:
	var side := socket_size.x * 0.5
	var hazard := Color(1.0, 0.62, 0.22)
	var dark := Color(0.15, 0.15, 0.17)
	for room: String in BasePlan.ROOMS:
		var opens := str(BasePlan.ROOMS[room]["opens"])
		var xf := room_transform(room)
		if opens != "" and not owns(opens):
			_add_bulkhead(opens, xf * _spot(Vector3(side - 0.6, 0, -small_depth + 0.45), 0.0), "post")
	var garage := room_transform("garage")
	if not owns("bay_second"):
		var bay := room_spot("bay", 1).origin
		_add_bulkhead("bay_second", garage * _spot(bay + Vector3(0, 0, -1.4), 0.0), "hatch")
	if owns("garage_full"):
		# The lift: a turntable under the first bay (the bike on it turns, see `_rebuild`).
		var lift := Node3D.new()
		lift.name = "Lift"
		lift.transform = spot_transform("bay", 0)
		lift.add_child(_part(Vector3(2.7, 0.05, 2.7), Vector3(0, 0.035, 0), dark))
		for edge: float in [-1.0, 1.0]:
			lift.add_child(_part(Vector3(2.7, 0.06, 0.08), Vector3(0, 0.04, edge * 1.35), hazard, true))
			lift.add_child(_part(Vector3(0.08, 0.06, 2.7), Vector3(edge * 1.35, 0.04, 0), hazard, true))
		_keep(lift)
	if owns("armory_alcove") and not owns("heavy_wall"):
		_add_bulkhead("heavy_wall", room_transform("armory") * _spot(Vector3(side - 0.4, 0, -socket_size.z + 0.9), -PI / 2.0), "post")
	# The firing range: the starter bunker has a small test lane at the end
	# of the corridor, sealed off at its far end from the range hall.
	if range_sign:
		range_sign.get_node("Name").text = "FIRING RANGE" if owns("firing_range") else "TEST LANE"
	if not owns("firing_range"):
		_build_test_lane()
	if not owns("finish"):
		# On a post beside the table, clear of its edge so the table is
		# always the thing you look at over it.
		_add_bulkhead("finish", _spot(PLAN_AT + Vector3(PLAN_RADIUS + 1.6, 0, 1.4), -0.6), "post")
	else:
		# Lit trim round the top of the hub and a light column in each corner.
		var trim := Color(0.45, 0.9, 1.0)
		var top := room_size.y - 0.2
		var wall_x := room_size.x * 0.5
		var wall_z := room_size.z * 0.5
		for end: float in [-1.0, 1.0]:
			_keep(_part(Vector3(room_size.x, 0.08, 0.05), Vector3(0, top, end * (wall_z - 0.11)), trim, true))
			_keep(_part(Vector3(0.05, 0.08, room_size.z), Vector3(end * (wall_x - 0.11), top, 0), trim, true))
			for far: float in [-1.0, 1.0]:
				_keep(_part(Vector3(0.12, room_size.y, 0.12), Vector3(end * (wall_x - 0.14), room_size.y * 0.5, far * (wall_z - 0.14)), trim, true))
	# The bench's own upgrades are bought at the bench.
	for id: String in ["bench_workshop", "bench_master"]:
		if not owns(id):
			_add_bulkhead(id, bench_transform() * Transform3D(Basis.from_euler(Vector3(-0.5, 0, 0)), Vector3(-0.9, 1.12, 0.3)), "tag")
			break


## Adds a part built from the upgrades, so it is cleared when they change.
func _keep(node: Node3D) -> Node3D:
	add_child(node)
	_gated.append(node)
	return node


## Builds one sealed upgrade with its price panel. `where` is where it stands
## and faces (local +Z toward the reader). Styles: "slab" fills a doorway
## `size` across and blocks it, "post" is a panel on a post, "hatch" a post
## beside a sealed plate in the floor, "tag" a small panel on a bench.
func _add_bulkhead(id: String, where: Transform3D, style: String, size := Vector2(2.2, 3.0)) -> void:
	var gate := Bulkhead.new()
	gate.name = "Bulkhead_%s" % id
	gate.base = self
	gate.id = id
	gate.transform = where
	# Amber if it can be bought some day soon, grey while it is not built.
	var accent := Color(1.0, 0.62, 0.22) if BaseUpgrades.is_ready(id) else Color(0.55, 0.58, 0.62)
	var dark := Color(0.15, 0.15, 0.17)
	var glass := Color(0.05, 0.06, 0.07)
	var text_at := Vector3.ZERO
	var s := 1.0
	match style:
		"slab":
			# It blocks the way as well as carrying the panel.
			gate.collision_layer = Actor.LAYER_WORLD | Actor.LAYER_INTERACT
			gate.add_child(_part(Vector3(size.x, size.y, 0.5), Vector3(0, size.y * 0.5, 0), Color(0.2, 0.21, 0.23)))
			for y: float in [0.1, size.y - 0.1]:
				gate.add_child(_part(Vector3(size.x, 0.14, 0.02), Vector3(0, y, 0.26), accent, true))
			s = clampf(size.x / 2.2, 0.6, 1.0)
			text_at = Vector3(0, minf(1.8, size.y * 0.55), 0.3)
			gate.add_child(_part(Vector3(1.9 * s, 1.35 * s, 0.03), text_at - Vector3(0, 0, 0.03), glass))
			_add_collision(gate, Vector3(size.x, size.y, 0.5), Vector3(0, size.y * 0.5, 0))
		"tag":
			s = 0.2
			gate.add_child(_part(Vector3(0.4, 0.29, 0.02), Vector3(0, 0, -0.012), glass))
			_add_collision(gate, Vector3(0.42, 0.3, 0.12), Vector3.ZERO)
		_:
			if style == "hatch":
				# A sealed plate in the floor, where you stand to read the post.
				gate.add_child(_part(Vector3(1.6, 0.05, 1.6), Vector3(0, 0.025, 1.3), Color(0.2, 0.21, 0.23)))
				for side: float in [-1.0, 1.0]:
					gate.add_child(_part(Vector3(1.6, 0.055, 0.08), Vector3(0, 0.03, 1.3 + side * 0.76), accent, true))
					gate.add_child(_part(Vector3(0.08, 0.055, 1.6), Vector3(side * 0.76, 0.03, 1.3), accent, true))
			gate.add_child(_part(Vector3(0.24, 1.0, 0.24), Vector3(0, 0.5, 0), dark))
			gate.add_child(_part(Vector3(0.06, 1.0, 0.02), Vector3(0, 0.5, 0.125), accent, true))
			s = 0.5
			text_at = Vector3(0, 1.42, 0.06)
			gate.add_child(_part(Vector3(0.98, 0.7, 0.04), text_at - Vector3(0, 0, 0.03), glass))
			_add_collision(gate, Vector3(1.0, 1.8, 0.4), Vector3(0, 0.9, 0))
	var title := _label(BaseUpgrades.title(id).to_upper(), accent, 0.16 * s)
	title.name = "Title"
	title.position = text_at + Vector3(0, 0.46 * s, 0)
	gate.add_child(title)
	var what := _label(BaseUpgrades.adds(id), Color(0.85, 0.83, 0.8), 0.085 * s)
	what.name = "Adds"
	what.position = text_at + Vector3(0, 0.14 * s, 0)
	gate.add_child(what)
	var price := _label("%s SCRIP" % commas(BaseUpgrades.price(id)), Color(1.0, 0.85, 0.4), 0.17 * s)
	price.name = "Price"
	price.position = text_at + Vector3(0, -0.2 * s, 0)
	gate.add_child(price)
	gate.status = _label("", Color(1.0, 0.8, 0.4), 0.085 * s)
	gate.status.name = "Status"
	gate.status.position = text_at + Vector3(0, -0.47 * s, 0)
	gate.add_child(gate.status)
	gate.refresh()
	add_child(gate)
	_gated.append(gate)
	bulkheads.append(gate)


func _spawn_player() -> void:
	player = _new_player(spawn_point)
	add_child(player)


func _new_player(at: Vector3) -> Actor:
	var actor := Actor.new()
	actor.name = "Player"
	actor.is_player = true
	actor.display_name = "You"
	actor.position = at
	# Flight ceilings count from the base's own floor.
	actor.ground_map = self
	return actor


## The mirror on the front wall, by the door, in every base.
func _build_wall_mirror() -> void:
	wall_mirror = MirrorScript.new()
	wall_mirror.name = "WallMirror"
	wall_mirror.wall_mounted = true
	wall_mirror.position = MIRROR_AT
	wall_mirror.rotation.y = MIRROR_YAW
	add_child(wall_mirror)


# --- Displays ----------------------------------------------------------------

## The bench's nodes under the displays, built by `_build_bench_gun`.
const BENCH_NODES := ["BenchGun", "SpecTablet", "SpecCard", "SpecStats"]
## What the bench was last built for (see `_rebuild`).
var _bench_key := ""


func _rebuild() -> void:
	# A display whose plan is unchanged keeps its node and its dressed model:
	# rebuilding every model in the room on each equip was a hitch. Only the
	# displays that changed, the signs and the bench are built again.
	var old_displays := {}
	for display in displays:
		if is_instance_valid(display):
			old_displays[display.get_meta("plan_key", "")] = display
	# The bench likewise stays when what it shows is the same.
	var keep_bench := _bench_key_now() == _bench_key
	for child in _display_root.get_children():
		if child is Display and old_displays.values().has(child):
			continue
		if keep_bench and str(child.name) in BENCH_NODES:
			continue
		_display_root.remove_child(child)
		child.queue_free()
	displays.clear()
	# In your own base the free scrap pieces are on show too, last in their
	# sections: every player owns them, and taking one off leaves its slot
	# bare. A base you visit shows only its owner's stash.
	var shown: Array = stash if read_only else StashRules.equippable(stash)
	var plan := BaseLayout.plan(shown, loadout, upgrades)
	var keys: Array[String] = []
	for entry: Dictionary in plan:
		keys.append(var_to_str([entry, spot_transform(entry["kind"], entry["index"]), upgrades]))
	# What is no longer on show goes first, so a new display can take its name.
	for key: String in old_displays.keys():
		if key not in keys:
			var gone: Display = old_displays[key]
			old_displays.erase(key)
			_display_root.remove_child(gone)
			gone.queue_free()
	for i in plan.size():
		var entry: Dictionary = plan[i]
		var at := spot_transform(entry["kind"], entry["index"])
		var key := keys[i]
		var reused: Display = old_displays.get(key)
		if reused != null:
			old_displays.erase(key)
			displays.append(reused)
			continue
		var display := Display.new()
		display.base = self
		display.item_id = entry["id"]
		display.kind = entry["kind"]
		display.index = entry["index"]
		display.count = entry["count"]
		display.slot = entry["slot"]
		display.equipped = entry["equipped"]
		display.name = "%s_%d" % [display.kind, display.index]
		display.transform = at
		display.set_meta("plan_key", key)
		# `Look` swaps in real models for displays tagged like this.
		display.set_meta("display_item", display.item_id)
		_fill(display)
		_display_root.add_child(display)
		displays.append(display)
		if display.kind == "bay" and display.index == 0 and owns("garage_full"):
			# The lift turns the bike parked on it. View only.
			var turn := display.create_tween().set_loops()
			turn.tween_property(display.get_node("Model"), "rotation:y", PI + TAU, lift_turn_time).from(PI)
	if not keep_bench:
		_build_bench_gun()
	gear_shown.emit()


## A weapon's place on the armory rack: a lit panel behind it, so it stands
## out from the wall, with a strip of its rarity colour along the bottom.
func _build_mount(display: Display, size: Vector2, at: Vector3, color: Color) -> void:
	var mount := Node3D.new()
	mount.name = "Mount"
	mount.position = at
	mount.add_child(_part(Vector3(size.x, size.y, 0.03), Vector3(0, 0, -0.12), Color(0.3, 0.31, 0.33)))
	var edge := _part(Vector3(size.x + 0.04, size.y + 0.04, 0.02), Vector3(0, 0, -0.135), Color(0.1, 0.1, 0.11))
	mount.add_child(edge)
	var strip := _part(Vector3(size.x * 0.9, 0.025, 0.02), Vector3(0, -size.y * 0.5 + 0.04, -0.1), color, true)
	strip.name = "RarityStrip"
	mount.add_child(strip)
	display.add_child(mount)


## Fades a label out past `reach` metres from the camera.
func _near_only(label: Label3D, reach: float) -> void:
	label.visibility_range_end = reach
	label.visibility_range_end_margin = reach * 0.15
	label.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


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
		"rack_guns", "rack_sidearms", "heavy_wall":
			var gun := Gun.new()
			gun.item_id = id
			var visual := gun.build_visual()
			gun.free()
			# Side-on to the room, hanging on two pegs.
			visual.rotation.y = PI / 2.0
			var small := display.kind == "rack_sidearms"
			var heavy := display.kind == "heavy_wall"
			visual.scale = Vector3.ONE * (weapon_scale if small else (1.6 if heavy else rack_gun_scale))
			model.add_child(visual)
			model.position.z = 0.15
			for x: float in ([-0.15, 0.15] if small else [-0.3, 0.3]):
				display.add_child(_part(Vector3(0.05, 0.05, 0.3), Vector3(x, -0.18, 0.05), Color(0.2, 0.2, 0.22)))
			box = Vector3(0.8, 0.7, 0.6) if small else Vector3(1.8, 1.0, 0.6)
			plate_at = Vector3(0, -0.45, 0.12) if small else Vector3(0, -0.6, 0.12)
			_build_mount(display, Vector2(1.0, 0.62) if small else Vector2(1.82, 1.05), Vector3(0, 0, 0.0), color)
			if display.equipped and display.kind == "rack_guns" and Loadout.is_primary(id):
				# The primary you deploy with is on the bench, not on the wall:
				# its pegs stand empty.
				model.visible = false
				model.set_meta("on_bench", true)
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
			_build_mount(display, Vector2(0.8, 2.3), Vector3(0, 0.3, 0.0), color)
		"armor_stand":
			_build_armor(model, id, color)
			box = Vector3(1.2, 2.0, 1.0)
			box_at = Vector3(0, 1.0, 0)
			plate_at = Vector3(0, 2.25, 0)
		"helmet_shelf":
			# A bracket off the wall, the helmet resting on it as it is worn.
			model.add_child(_part(Vector3(0.6, 0.05, 0.45), Vector3(0, -0.2, 0.1), Color(0.2, 0.2, 0.22)))
			var stats := ItemDB.item_stats(id)
			var helmet := SkinScript.build_helmet(str(stats.get("mode", "")), stats.get("glass_color", Color.WHITE),
					Vector3(0.27, 0.31, 0.31), Color(0.22, 0.23, 0.25), int(stats.get("tier", 1)))
			helmet.position = Vector3(0, -0.02, 0.12)
			model.add_child(helmet)
			box = Vector3(0.7, 0.55, 0.55)
			box_at = Vector3(0, -0.05, 0.1)
			plate_at = Vector3(0, -0.36, 0.38)
			plate_size = 0.09
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
			box = Vector3(0.7, 0.8, 0.6)
			plate_at = Vector3(0, 0.42, 0)
		"artifact_case":
			# A dark plinth, the artifact a glowing core standing on its point.
			model.add_child(_part(Vector3(0.5, 0.08, 0.5), Vector3(0, -0.3, 0), Color(0.12, 0.12, 0.14)))
			var core := _part(Vector3(0.18, 0.18, 0.18), Vector3(0, -0.02, 0), color, true)
			core.rotation = Vector3(PI / 4.0, 0.0, PI / 4.0)
			core.name = "Core"
			model.add_child(core)
			box = Vector3(0.7, 0.8, 0.6)
			plate_at = Vector3(0, 0.42, 0)
		"bay":
			var vehicle: Node3D = VehicleScript.new()
			vehicle.setup(id)
			var visual: Node3D = vehicle.build_visual()
			# A bike fills the bay; bigger vehicles park as smaller models.
			visual.scale = Vector3.ONE * float(vehicle.bay_scale)
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
			model.add_child(_part(Vector3(0.8, 0.04, 0.45), Vector3(0, -0.29, 0), Color(0.2, 0.2, 0.22)))
			var glow: bool = ItemDB.item_rarity(id) >= ItemDB.Rarity.EPIC
			# A taller stack the more copies you hold.
			var stack := mini(display.count, 4)
			for n in stack:
				model.add_child(_part(Vector3(0.36, 0.16, 0.3), Vector3(0, -0.19 + 0.17 * n, 0), color, glow))
			box = Vector3(0.85, 0.8, 0.6)
			plate_at = Vector3(0, 0.45, 0)
	display.add_child(model)
	_add_collision(display, box, box_at)
	var text := ItemDB.item_name(id)
	if display.count > 1:
		text += "  x%d" % display.count
	if model.has_meta("on_bench"):
		text += "\nON THE BENCH"
	elif display.equipped:
		text += "\nEQUIPPED"
	var plate := _label(text, color, plate_size)
	# A name shows once you walk up to the item, not from across the room.
	_near_only(plate, 5.0)
	plate.name = "Plate"
	plate.position = plate_at
	display.add_child(plate)
	if display.equipped:
		# A lit bar under whatever you are taking on your next run.
		var bar := _part(Vector3(box.x * 0.8, 0.03 * plate_size / 0.13, 0.06), plate_at + Vector3(0, -0.16 * plate_size / 0.13 - 0.02, 0),
				Color(1.0, 0.62, 0.22), true)
		bar.name = "EquippedMark"
		display.add_child(bar)


## The gunsmith bench: a heavy table against the workshop's back wall, with a
## cradle in the middle for the one gun on it and a lit card on the panel
## behind that says what is on the gun and what can go on it. The gun and
## the card are rebuilt with the rest of the displays.
func _build_bench() -> void:
	var bench := StaticBody3D.new()
	bench.name = "GunsmithBench"
	bench.collision_layer = Actor.LAYER_WORLD
	bench.collision_mask = 0
	bench.transform = bench_transform()
	var top := Color(0.2, 0.21, 0.23)
	var steel := Color(0.24, 0.25, 0.27)
	var dark := Color(0.1, 0.1, 0.11)
	bench.add_child(_part(Vector3(2.0, 0.08, 0.8), Vector3(0, 0.92, 0), top))
	for x: float in [-0.92, 0.92]:
		for z: float in [-0.34, 0.34]:
			bench.add_child(_part(Vector3(0.08, 0.88, 0.08), Vector3(x, 0.44, z), steel))
	bench.add_child(_part(Vector3(1.9, 0.04, 0.7), Vector3(0, 0.25, 0), steel))
	# The cradle the gun lies in, lit along its front edge.
	bench.add_child(_part(Vector3(1.2, 0.05, 0.3), Vector3(0, 0.985, 0.0), dark))
	bench.add_child(_part(Vector3(1.2, 0.012, 0.02), Vector3(0, 1.01, 0.16), Color(0.25, 0.9, 1.0), true))
	for x: float in [-0.35, 0.35]:
		bench.add_child(_part(Vector3(0.06, 0.16, 0.2), Vector3(x, 1.06, 0.0), steel))
	# The panel behind, which carries the card, and a lamp over the cradle.
	bench.add_child(_part(Vector3(2.0, 1.3, 0.05), Vector3(0, 1.62, -0.38), Color(0.15, 0.15, 0.17)))
	bench.add_child(_part(Vector3(0.5, 0.03, 0.12), Vector3(0, 2.36, -0.25), Color(1.0, 0.85, 0.6), true))
	if owns("bench_workshop"):
		# A workshop bench: a parts cabinet under the top and a second lamp.
		bench.add_child(_part(Vector3(0.6, 0.6, 0.6), Vector3(0.6, 0.57, 0.0), steel))
		for y: float in [0.42, 0.72]:
			bench.add_child(_part(Vector3(0.5, 0.02, 0.01), Vector3(0.6, y, 0.305), Color(1.0, 0.85, 0.6), true))
		bench.add_child(_part(Vector3(0.4, 0.03, 0.12), Vector3(-0.7, 2.36, -0.25), Color(1.0, 0.85, 0.6), true))
	if owns("bench_master"):
		# A master's bench: lit edges.
		for z: float in [-0.4, 0.4]:
			bench.add_child(_part(Vector3(2.0, 0.03, 0.03), Vector3(0, 0.95, z), Color(0.25, 0.9, 1.0), true))
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.1, 1.0, 0.85)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0, 0.5, 0)
	bench.add_child(col)
	# Its name on the panel's top edge, under the lamp.
	var title := _label(bench_name().to_upper(), Color(1.0, 0.62, 0.22), 0.08)
	title.name = "Title"
	title.outline_size = 0
	title.position = Vector3(0, 2.22, -0.35)
	bench.add_child(title)
	_keep(bench)
	_build_craft_console()
	if Look.enabled:
		var light := Look.lamp(Color(1.0, 0.9, 0.75), 2.0, 5.0)
		light.position = bench_transform() * Vector3(0, 2.2, 0.2)
		_keep(light)


## The fabricator: a cabinet beside the bench, facing it across the
## workshop, with a screen on top, where gear is crafted from blueprints.
func _build_craft_console() -> void:
	var console := CraftConsole.new()
	console.name = "Station_%s" % CRAFT_ID
	console.base = self
	console.id = CRAFT_ID
	console.transform = bench_transform() * _spot(CRAFT_AT, CRAFT_YAW)
	_dress_console(console, CRAFT_COLOR, "Craft from blueprints", CRAFT_TITLE)
	# A print bed beside the monitor post, lit like something is being made.
	console.add_child(_part(Vector3(0.4, 0.03, 0.3), Vector3(0.36, 1.02, 0.05), CRAFT_COLOR, true))
	_keep(console)
	stations.append(console)


## What the bench is called, by how far it has been upgraded.
func bench_name() -> String:
	if owns("bench_master"):
		return "Master bench"
	return "Workshop bench" if owns("bench_workshop") else "Gunsmith bench"


## The one gun on the bench, its attachments on, and the card behind it. At
## rest that is the primary you will deploy with; in use it is whatever the
## wheel has turned to (`bench_shown_gun`, `bench_shown_fitted`), so every
## change shows on the gun before it is picked.
func _build_bench_gun() -> void:
	_bench_key = _bench_key_now()
	var id := bench_shown_gun()
	if id == "":
		return
	var fitted := bench_shown_fitted()
	var gun := bench_gun(id, fitted)
	var bare := bench_gun(id, [])
	var visual := gun.build_visual()
	var shown := Bench.new()
	shown.base = self
	shown.item_id = id
	shown.name = "BenchGun"
	shown.transform = bench_transform() * _spot(Vector3(0.0, 1.2, 0.0), 0.0)
	var model := Node3D.new()
	model.name = "Model"
	visual.rotation.y = PI / 2.0
	# Bigger than on the rack, so what is fitted shows from the bench.
	visual.scale = Vector3.ONE * bench_scale
	model.add_child(visual)
	shown.add_child(model)
	_add_collision(shown, Vector3(1.6, 0.5, 0.6), Vector3.ZERO)
	# `Look` swaps in the real model and moves the attachments onto it.
	shown.set_meta("display_item", id)
	_display_root.add_child(shown)
	# The card: a lit panel on the board above the gun, the rows on its left
	# and what the attachments change on its right.
	var where := bench_transform() * Transform3D(Basis.IDENTITY, Vector3(0, 1.93, -0.35))
	var tablet := _part(Vector3(1.84, 0.62, 0.02), Vector3.ZERO, Color(0.05, 0.06, 0.07))
	tablet.name = "SpecTablet"
	tablet.transform = where
	_display_root.add_child(tablet)
	var columns := [["SpecCard", bench_card(), -0.46], ["SpecStats", bench_stats(gun, bare), 0.46]]
	for column: Array in columns:
		var label := _label(column[1], Color(0.55, 0.95, 1.0), 0.036)
		label.name = column[0]
		label.outline_size = 4
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		# Each column is 0.84 m wide, its text from its left edge.
		label.width = 0.84 / label.pixel_size
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.transform = where * Transform3D(Basis.IDENTITY, Vector3(column[2], 0.27, 0.012))
		_display_root.add_child(label)
	gun.free()
	bare.free()


# --- Using the bench -----------------------------------------------------------

## The rows on the bench card: the gun, then each attachment slot.
func bench_rows() -> Array[String]:
	var rows: Array[String] = ["primary"]
	for slot: String in Loadout.ATTACHMENT_SLOTS:
		rows.append(slot)
	return rows


## What a row can be turned to. The gun: every primary in the stash, one of
## each, then "" (nothing equipped: the free scrap gun). An attachment slot:
## "" (nothing fitted), then every attachment in the stash that fits it.
func bench_choices(slot: String) -> Array[String]:
	var out: Array[String] = []
	if slot == "primary":
		out = bench_guns()
		out.append("")
		return out
	out.append("")
	for id: Variant in stash:
		if typeof(id) == TYPE_STRING and Loadout.fits(slot, id) and id not in out:
			out.append(id)
	return out


## Every gun that can go on the bench: the primaries in the stash, in stash
## order, one of each, then the free scrap gun.
func bench_guns() -> Array[String]:
	var out: Array[String] = []
	for id: Variant in StashRules.equippable(stash):
		if typeof(id) == TYPE_STRING and Loadout.is_primary(id) and id not in out:
			out.append(id)
	return out


## What a row holds in the loadout now ("" for nothing).
func bench_current(slot: String) -> String:
	var id: String = loadout.get(slot, "")
	if slot == "primary" and (id == "" or not ItemDB.has_tag(id, "firearm")):
		return ""
	return id


## The gun on the bench: the one the wheel is on while the gun row is being
## picked, else the primary in the loadout (or the free scrap gun).
func bench_shown_gun() -> String:
	var id := bench_current("primary")
	if bench_open and bench_picking and bench_row == 0:
		id = bench_choice
	return id if id != "" else starter_primary()


## The attachments on the bench's gun: the loadout's, with the one the wheel
## is on in place of its slot's while an attachment row is being picked.
func bench_shown_fitted() -> Array[String]:
	var out: Array[String] = []
	var picking := bench_rows()[bench_row] if bench_open and bench_picking and bench_row > 0 else ""
	for slot: String in Loadout.ATTACHMENT_SLOTS:
		var id := bench_choice if slot == picking else bench_current(slot)
		if id != "":
			out.append(id)
	return out


## Takes up the bench: the wheel starts on the gun row, on the gun in the
## loadout.
func use_bench() -> void:
	if read_only:
		return
	bench_open = true
	bench_row = 0
	bench_picking = true
	bench_choice = bench_current("primary")
	bench_used.emit()
	_refresh_bench()


## Steps away from the bench. Anything turned to but not picked is dropped.
func leave_bench() -> void:
	if not bench_open:
		return
	bench_open = false
	bench_picking = false
	bench_row = 0
	_refresh_bench()


## A notch of the wheel (`step` 1 down, -1 up): picking, the next choice of
## the row, shown on the gun at once; otherwise the next attachment row.
func bench_scroll(step: int) -> void:
	if not bench_open or step == 0:
		return
	if bench_picking:
		var choices := bench_choices(bench_rows()[bench_row])
		var at := maxi(choices.find(bench_choice), 0)
		bench_choice = choices[posmod(at + signi(step), choices.size())]
	else:
		var count := bench_rows().size() - 1
		bench_row = 1 + posmod(bench_row - 1 + signi(step), count)
	_refresh_bench()


## A click: on a row, start turning through its choices; picking, take the
## choice on show. A gun picked moves on to its attachments.
func bench_select() -> void:
	if not bench_open:
		return
	if not bench_picking:
		bench_picking = true
		bench_choice = bench_current(bench_rows()[bench_row])
		_refresh_bench()
		return
	var slot := bench_rows()[bench_row]
	var choice := bench_choice
	bench_picking = false
	if slot == "primary":
		bench_row = 1
	_refresh_bench()
	if choice != bench_current(slot):
		equip_requested.emit(slot, choice)


## A step back: picking, drop the choice on show and return to the rows.
## Returns false when there is nothing to step back from (time to leave).
func bench_back() -> bool:
	if not bench_open:
		return false
	if not bench_picking:
		return false
	bench_picking = false
	if bench_row == 0:
		bench_row = 1
	_refresh_bench()
	return true


## What the bench shows, to tell when it needs building again.
func _bench_key_now() -> String:
	return var_to_str([bench_shown_gun(), bench_shown_fitted(), bench_card()])


## Rebuilds the bench's gun and card from the bench state.
func _refresh_bench() -> void:
	if not is_inside_tree():
		return
	for node_name: String in BENCH_NODES:
		var old := _display_root.get_node_or_null(node_name)
		if old:
			_display_root.remove_child(old)
			old.queue_free()
	_build_bench_gun()


## The bench card's left column: a row for the gun and each attachment slot
## with what is on it, the row in use marked (‹ › while the wheel turns
## through it), and in use the controls under them.
func bench_card() -> String:
	var lines: Array[String] = []
	var rows := bench_rows()
	for i in rows.size():
		var slot := rows[i]
		var id := bench_shown_gun() if slot == "primary" else ""
		if slot != "primary":
			var shown := bench_shown_fitted()
			for fitted: String in shown:
				if Loadout.attachment_slot(fitted) == slot:
					id = fitted
		var label := "GUN" if slot == "primary" else slot.to_upper()
		var value := ItemDB.item_name(id) if id != "" else "—"
		if slot == "primary" and bench_current("primary") == "" and not (bench_open and bench_picking and bench_row == 0):
			# No primary: the scrap gun stands in so attachments show on something.
			value = "— none equipped"
		if slot != "primary":
			var spare := bench_choices(slot).size() - 1
			if id == "" and spare == 0:
				value = "— (none owned)"
		var here := bench_open and bench_row == i
		if here and bench_picking:
			value = "‹ %s ›" % value
		lines.append("%s %s   %s" % ["▶" if here else "   ", label, value])
	if bench_open:
		lines.append("")
		lines.append("◎ turn   ● pick   ○ back   Esc leave")
	return "\n".join(lines)


## The bench card's right column: the gun's name and what its attachments
## change, from the bare gun's value to the fitted one.
func bench_stats(gun: Gun, bare: Gun) -> String:
	var lines: Array[String] = [gun.display_name.to_upper()]
	var diffs := spec_lines(gun, bare)
	if diffs.is_empty():
		lines.append("Nothing fitted changes it")
	lines.append_array(diffs)
	return "\n".join(lines)


## What the attachments change on a gun, one line per stat, from the bare
## gun's value to the fitted one.
static func spec_lines(gun: Gun, bare: Gun) -> Array[String]:
	var lines: Array[String] = []
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
	return lines


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


static func _spec_value(gun: Gun, key: String) -> float:
	match key:
		"rpm":
			return 60.0 / maxf(gun.fire_interval, 0.001)
		"ads":
			return gun.spread_deg * gun.ads_spread_mult
	return float(gun.get(key))


# --- The plan table ------------------------------------------------------------

## The plan table: a round table in the middle of the hub with the base
## drawn over it in light, one tile per socket in its room's colour, and a
## card standing at its right that names the sockets and what is in them.
## Using it takes it up (`use_plan`): the wheel turns through the sockets, a
## click opens one, the wheel turns through the rooms (shown in place on the
## tiles as you go) and a click moves the room there (`room_placed`).
func _build_plan_table() -> void:
	var table := PlanTable.new()
	table.name = "PlanTable"
	table.base = self
	table.transform = plan_transform()
	var dark := Color(0.14, 0.15, 0.17)
	var glow := Color(0.35, 0.85, 1.0)
	table.add_child(_part(Vector3(0.8, PLAN_TOP - 0.06, 0.8), Vector3(0, (PLAN_TOP - 0.06) * 0.5, 0), dark))
	table.add_child(_part(Vector3(1.3, 0.06, 1.3), Vector3(0, 0.03, 0), dark))
	var top := MeshInstance3D.new()
	top.name = "Top"
	var disc := CylinderMesh.new()
	disc.top_radius = PLAN_RADIUS
	disc.bottom_radius = PLAN_RADIUS - 0.08
	disc.height = 0.08
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.12, 0.14)
	disc.material = mat
	top.mesh = disc
	top.position = Vector3(0, PLAN_TOP - 0.04, 0)
	table.add_child(top)
	var rim := MeshInstance3D.new()
	rim.name = "Rim"
	var ring := TorusMesh.new()
	ring.inner_radius = PLAN_RADIUS - 0.02
	ring.outer_radius = PLAN_RADIUS + 0.02
	var rim_mat := StandardMaterial3D.new()
	rim_mat.albedo_color = glow
	rim_mat.emission_enabled = true
	rim_mat.emission = glow
	rim_mat.emission_energy_multiplier = 1.2
	ring.material = rim_mat
	rim.mesh = ring
	rim.position = Vector3(0, PLAN_TOP, 0)
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	table.add_child(rim)
	var shape := CylinderShape3D.new()
	shape.radius = PLAN_RADIUS
	shape.height = PLAN_TOP
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0, PLAN_TOP * 0.5, 0)
	table.add_child(col)
	# The table takes up the room in the middle: it stands in the way like
	# the bench, so it is part of the world too.
	table.collision_layer = Actor.LAYER_WORLD | Actor.LAYER_INTERACT
	add_child(table)
	_gated.append(table)
	plan_table = table
	_refresh_plan()


## Where the plan table stands and which way it faces (local +Z is where you
## stand to use it: toward the door, so the base lies on it as you see it).
func plan_transform() -> Transform3D:
	return _spot(PLAN_AT, 0.0)


## The plan the table shows: the one in use, or while a room is being picked,
## the plan as it would be with that room moved in.
func plan_shown() -> Dictionary:
	if plan_open and plan_picking and plan_choice != "":
		return BasePlan.place(base_plan, BasePlan.SOCKETS[plan_socket], plan_choice)
	return base_plan


## Draws the base over the table and the card beside it again, from the plan
## and the table's state.
func _refresh_plan() -> void:
	if plan_table == null or not is_instance_valid(plan_table):
		return
	for node_name: String in ["Holo", "Card", "CardText", "CardRoom"]:
		var old := plan_table.get_node_or_null(node_name)
		if old:
			plan_table.remove_child(old)
			old.queue_free()
	var shown := plan_shown()
	var holo := Node3D.new()
	holo.name = "Holo"
	# A miniature of the base: the hub, the corridor and a tile per socket,
	# centred over the table (the back rooms reach further than the front).
	var k := (PLAN_RADIUS * 2.0 - 0.5) / (room_size.x + socket_size.z * 2.0 + 1.0)
	var middle_z := (room_size.z * 0.5 - range_from()) * 0.5
	holo.position = Vector3(0, PLAN_TOP + 0.2, -middle_z * k)
	plan_table.add_child(holo)
	var cyan := Color(0.35, 0.85, 1.0)
	holo.add_child(_holo(Vector3(room_size.x, 0.3, room_size.z) * k, Vector3.ZERO, cyan, 0.12))
	var lane := Vector3(corridor.x, 0.4, range_from() - room_size.z * 0.5) * k
	holo.add_child(_holo(lane, Vector3(0, 0, -(room_size.z * 0.5 + lane.z / k * 0.5) * k), cyan, 0.1))
	for i in BasePlan.SOCKETS.size():
		var socket: String = BasePlan.SOCKETS[i]
		var room: String = shown[socket]
		var here := plan_open and i == plan_socket
		var xf := socket_transform(socket)
		var centre := xf * Vector3(0, 0, -socket_size.z * 0.5)
		var color: Color = ROOM_COLORS.get(room, cyan)
		var lift := 0.06 if here else 0.0
		var tile := _holo(Vector3(socket_size.x - 0.8, 0.8, socket_size.z - 0.8) * k, centre * k + Vector3(0, lift, 0),
				Color(1.0, 0.62, 0.22) if here and plan_picking else color, 0.6 if here else 0.28)
		tile.basis = xf.basis * tile.basis
		tile.name = "Tile_%s" % socket
		holo.add_child(tile)
		var name_label := _label(BasePlan.title(room).to_upper(), color.lightened(0.5), 0.065)
		name_label.name = "Name_%s" % socket
		name_label.outline_size = 4
		name_label.position = centre * k + Vector3(0, 0.1 + lift, 0)
		name_label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		holo.add_child(name_label)
	# The card: standing at the table's right edge, facing the reader.
	var where := Transform3D(Basis.from_euler(Vector3(0, -0.35, 0)), Vector3(PLAN_RADIUS + 0.35, PLAN_TOP + 0.6, -0.1))
	var card := _part(Vector3(1.1, 0.8, 0.02), Vector3.ZERO, Color(0.04, 0.07, 0.08))
	card.name = "Card"
	card.transform = where
	plan_table.add_child(card)
	for column: Array in [["CardText", plan_card(), Vector3(-0.51, 0.37, 0.012)]]:
		var label := _label(column[1], Color(0.55, 0.95, 1.0), 0.042)
		label.name = column[0]
		label.outline_size = 4
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		label.width = 1.02 / label.pixel_size
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.transform = where * Transform3D(Basis.IDENTITY, column[2])
		plan_table.add_child(label)


## A see-through lit box for the table's hologram.
func _holo(size: Vector3, at: Vector3, color: Color, alpha: float) -> MeshInstance3D:
	var part := _part(size, at, color, true)
	var mat := (part.mesh as BoxMesh).material as StandardMaterial3D
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color, alpha)
	mat.emission_energy_multiplier = 0.8
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return part


## The plan card's text: each socket and its room, the one the wheel is on
## marked (‹ › while a room is being picked for it), what that room holds
## and how far it is opened, and in use the controls under them.
func plan_card() -> String:
	var shown := plan_shown()
	var lines: Array[String] = ["BASE PLAN"]
	for i in BasePlan.SOCKETS.size():
		var socket: String = BasePlan.SOCKETS[i]
		var here := plan_open and i == plan_socket
		var room := BasePlan.title(shown[socket])
		if here and plan_picking:
			room = "‹ %s ›" % room
		lines.append("%s %s:  %s" % ["▶" if here else "   ", BasePlan.SOCKET_NAMES[socket], room])
	lines.append("")
	if plan_open:
		var room: String = shown[BasePlan.SOCKETS[plan_socket]]
		lines.append("%s: %s" % [BasePlan.title(room), BasePlan.ROOMS[room]["holds"]])
		var opens := str(BasePlan.ROOMS[room]["opens"])
		if not room_open(room):
			lines.append("Half sealed: the %s opens the rest (%s scrip)" % [BaseUpgrades.title(opens).to_lower(),
					commas(BaseUpgrades.price(opens))])
		var stored := 0
		var away := BaseLayout.stored_away(StashRules.equippable(stash) if not read_only else stash, upgrades)
		for kind: String in KIND_ROOMS:
			if KIND_ROOMS[kind] == room:
				stored += int(away.get(kind, 0))
		if stored > 0:
			lines.append("%d more owned than fit on show" % stored)
		lines.append("")
		lines.append("◎ turn   ● pick   ○ back   Esc leave")
	else:
		lines.append("Moving a room is free.")
	return "\n".join(lines)


## Takes up the plan table: the wheel starts on the first socket.
func use_plan() -> void:
	if read_only:
		return
	plan_open = true
	plan_socket = 0
	plan_picking = false
	plan_choice = ""
	plan_used.emit()
	_refresh_plan()


## Steps away from the table. A room turned to but not picked stays where it
## was.
func leave_plan() -> void:
	if not plan_open:
		return
	plan_open = false
	plan_picking = false
	_refresh_plan()


## A notch of the wheel: picking, the next room, shown in the socket at once;
## otherwise the next socket.
func plan_scroll(step: int) -> void:
	if not plan_open or step == 0:
		return
	if plan_picking:
		var rooms := BasePlan.rooms()
		var at := maxi(rooms.find(plan_choice), 0)
		plan_choice = rooms[posmod(at + signi(step), rooms.size())]
	else:
		plan_socket = posmod(plan_socket + signi(step), BasePlan.SOCKETS.size())
	_refresh_plan()


## A click: on a socket, start turning through the rooms for it; picking,
## move the room on show there (the room there takes its old socket).
func plan_select() -> void:
	if not plan_open:
		return
	var socket: String = BasePlan.SOCKETS[plan_socket]
	if not plan_picking:
		plan_picking = true
		plan_choice = base_plan[socket]
		_refresh_plan()
		return
	var choice := plan_choice
	plan_picking = false
	_refresh_plan()
	if choice != base_plan[socket]:
		room_placed.emit(socket, choice)


## A step back: picking, drop the room on show and return to the sockets.
## Returns false when there is nothing to step back from (time to leave).
func plan_back() -> bool:
	if not plan_open or not plan_picking:
		return false
	plan_picking = false
	_refresh_plan()
	return true


## A mannequin wearing the frame: the same plates it is worn as
## (`ActorSkin.build_frame`, `build_pad`), so the stand shows its look and
## its weight.
func _build_armor(model: Node3D, id: String, _color: Color) -> void:
	var dummy := Color(0.22, 0.22, 0.24)
	model.add_child(_part(Vector3(0.7, 0.08, 0.7), Vector3(0, 0.04, 0), dummy))
	model.add_child(_part(Vector3(0.1, 0.9, 0.1), Vector3(0, 0.5, 0), dummy))
	# A torso the plates fit, about a body's (0.26 m by 0.22 m at the chest).
	model.add_child(_part(Vector3(0.25, 0.5, 0.2), Vector3(0, 1.22, 0), dummy))
	model.add_child(_part(Vector3(0.14, 0.2, 0.14), Vector3(0, 1.6, 0), dummy))
	# The mannequin faces +Z, the plates are built facing -Z.
	var plates := SkinScript.build_frame(id)
	plates.position = Vector3(0, 1.36, 0)
	plates.rotation.y = PI
	model.add_child(plates)
	if int(SkinScript.FRAME_BULK[SkinScript.frame_weight(id)]["pads"]) > 0:
		for out: float in [-1.0, 1.0]:
			var pad := SkinScript.build_pad(id, out)
			pad.position = Vector3(-out * 0.17, 1.43, 0)
			pad.rotation.y = PI
			model.add_child(pad)


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
	# Writing on a wall is read from the front only, never mirrored from
	# behind. Labels that turn to face you (billboards) are unaffected.
	label.double_sided = false
	return label


# ------------------------------------------------ the watch's summon at home ----
# Every vehicle and weapon the account owns can be summoned off the watch at
# home (Caleb's call). Like the rest of the room this is a view of the stash:
# a vehicle thrown here unpacks to be ridden around the base and packs back
# onto the watch, and nothing here is stored, risked or sent anywhere. A
# weapon picked on the watch is equipped through `equip_requested`.

## How far ahead of the thrower a vehicle unpacks, at most.
var toy_reach := 7.0
## The room a vehicle needs to unpack, unless its `footprint` stat says.
var toy_room := Vector3(1.3, 1.2, 2.6)
## The vehicles out in the base, item id -> vehicle.
var out_vehicles := {}
## Seconds from a throw to the toy leaving the hand (as `Raid.toy_windup`),
## and how fast it flies to where it unpacks, in m/s along the ground.
var toy_windup := 0.3
var toy_fly_speed := 11.0
## Throws on their way: { id, at, heading, windup, from, age, time, node }.
var _toy_throws: Array[Dictionary] = []


## The base a node is in, or null.
static func of(node: Node) -> HomeBase:
	while node != null:
		if node is HomeBase:
			return node
		node = node.get_parent()
	return null


## The vehicles on the watch at home: every one the owner has, one of each,
## less those already out in the base.
func watch_vehicles() -> Array[String]:
	var ids: Array[String] = []
	if read_only:
		return ids
	for id: String in stash + [str(loadout.get("vehicle", ""))]:
		if ItemDB.has_tag(id, "vehicle") and id not in ids and not is_instance_valid(out_vehicles.get(id)) \
				and not _toy_throws.any(func(t: Dictionary) -> bool: return t.id == id):
			ids.append(id)
	return ids


## The weapons the owner has that are not worn, for the watch's carousel at
## home, one of each.
func watch_weapons() -> Array[String]:
	var ids: Array[String] = []
	if read_only:
		return ids
	var worn: Array = [loadout.get("primary", ""), loadout.get("sidearm", ""), loadout.get("melee", "")]
	for id: String in StashRules.equippable(stash):
		if Loadout.summonable(id) and id not in ids and id not in worn:
			ids.append(id)
	return ids


## Throws vehicle `item_id` off the watch: it unpacks on the floor ahead of
## `actor`, where they aim, if there is room. Returns "" if it did, or why
## not (also sent as a notice).
func throw_toy(actor: Actor, item_id: String) -> String:
	var why := ""
	var at := Vector3.INF
	var heading := actor.cmd.yaw if actor != null else 0.0
	var room: Vector3 = ItemDB.item_stats(item_id).get("footprint", toy_room)
	if actor == null or actor != player or actor.is_dead:
		why = "not now"
	elif item_id not in watch_vehicles():
		why = "That is not on your watch"
	elif actor.vehicle != null:
		why = "Get off first"
	elif not _toy_throws.is_empty():
		why = "Throwing"
	else:
		at = toy_spot(actor, room)
		if at == Vector3.INF:
			why = "No room there"
	if why != "":
		if actor != null:
			actor.notice.emit(why)
		return why
	# The arm draws back and comes through; the toy flies at the release and
	# unpacks where it comes down (`_tick_toy_throws`).
	actor.toy_in_hand = item_id
	actor.toy_throws += 1
	_toy_throws.append({"id": item_id, "at": at, "heading": heading, "windup": toy_windup})
	if toy_windup <= 0.0:
		_tick_toy_throws(0.0)
	return ""


## Takes vehicle `item_id` off the watch into the player's hand to throw,
## or puts it back with "". Only the look. "" if it is in hand, or why not.
func hold_toy(actor: Actor, item_id: String) -> String:
	if actor == null or actor != player or actor.is_dead or not _toy_throws.is_empty():
		return "not now"
	var why := ""
	if item_id != "" and item_id not in watch_vehicles():
		why = "That is not on your watch"
	elif item_id != "" and actor.vehicle != null:
		why = "Get off first"
	actor.toy_in_hand = item_id if why == "" else ""
	return why


## Thrown toys at home: each leaves the hand after the windup, flies an arc
## to the spot picked when it was thrown, and unpacks there.
func _tick_toy_throws(delta: float) -> void:
	for toy in _toy_throws.duplicate():
		if toy.has("windup"):
			toy.windup -= delta
			if toy.windup > 0.0:
				continue
			toy.erase("windup")
			if player == null or not is_instance_valid(player) or player.is_dead or player.vehicle != null:
				_toy_throws.erase(toy)
				if player != null and is_instance_valid(player):
					player.toy_in_hand = ""
				continue
			var aim := player.get_aim_dir()
			toy.from = player.get_eye_position() + aim * 0.6 - Vector3(0.0, 0.25, 0.0)
			var flat: float = Vector2(toy.at.x - toy.from.x, toy.at.z - toy.from.z).length()
			toy.time = clampf(flat / maxf(toy_fly_speed, 0.1), 0.25, 0.9)
			toy.age = 0.0
			var node: Node3D = VehicleScript.toy_model(toy.id)
			add_child(node)
			node.global_position = toy.from
			toy.node = node
			player.toy_in_hand = ""
			continue
		toy.age += delta
		var u := clampf(toy.age / toy.time, 0.0, 1.0)
		var node: Node3D = toy.node
		# A lob: along the line to the spot, with an arc over it.
		var lift: float = toy.time * toy.time * 2.5
		node.global_position = (toy.from as Vector3).lerp(toy.at, u) + Vector3.UP * 4.0 * lift * u * (1.0 - u)
		node.basis = VehicleScript.toy_flight_basis(toy.heading, VehicleScript.TOY_FLIP_TIME * u / 0.8).scaled(Vector3.ONE * VehicleScript.TOY_SCALE)
		if u < 1.0:
			continue
		_toy_throws.erase(toy)
		node.queue_free()
		var vehicle: Node3D = VehicleScript.new()
		vehicle.name = "Out_%s" % toy.id
		vehicle.setup(toy.id)
		vehicle.set("local_only", true)
		vehicle.rotation.y = toy.heading
		add_child(vehicle)
		vehicle.global_position = toy.at + Vector3(0.0, 0.25, 0.0)
		vehicle.call("unpack")
		out_vehicles[toy.id] = vehicle


## Where a vehicle needing `room` unpacks for `actor`: on the floor along
## their aim, short of any wall, or `Vector3.INF` if it does not fit.
func toy_spot(actor: Actor, room: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var flat := Vector3(actor.get_aim_dir().x, 0.0, actor.get_aim_dir().z)
	if flat.length() < 0.01:
		flat = Vector3(-sin(actor.cmd.yaw), 0.0, -cos(actor.cmd.yaw))
	flat = flat.normalized()
	var chest := actor.global_position + Vector3(0.0, 1.0, 0.0)
	var reach := toy_reach
	var wall := space.intersect_ray(PhysicsRayQueryParameters3D.create(chest, chest + flat * reach, Actor.LAYER_WORLD))
	if not wall.is_empty():
		reach = chest.distance_to(wall.position) - room.z * 0.5 - 0.3
	# Out from under the thrower's own feet, then as far as it goes.
	var near := room.z * 0.5 + 1.2
	var d := reach
	while d >= near:
		var over := chest + flat * d
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(over, over + Vector3.DOWN * 4.0, Actor.LAYER_WORLD))
		if not hit.is_empty() and Raid.room_to_unpack(space, hit.position, actor.cmd.yaw, room):
			return hit.position
		d -= 0.75
	return Vector3.INF


## Packs the vehicle `actor` is looking at back onto the watch, if it is one
## of theirs out in the base with nobody on it. "" if it was packed.
func pack_vehicle(actor: Actor) -> String:
	var seat := actor.find_interactable() if actor != null and actor.vehicle == null else null
	var vehicle: Variant = seat.get("vehicle") if seat != null else null
	var id := ""
	for key: String in out_vehicles:
		if out_vehicles[key] == vehicle:
			id = key
	if id == "" or vehicle.call("is_occupied"):
		var why := "Look at a vehicle to pack it" if id == "" else "Someone is riding it"
		if actor != null:
			actor.notice.emit(why)
		return why
	out_vehicles.erase(id)
	vehicle.queue_free()
	actor.notice.emit("Packed %s onto your watch" % ItemDB.item_name(id))
	return ""
