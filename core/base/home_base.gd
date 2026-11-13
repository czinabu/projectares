class_name HomeBase
extends Node3D
## A player's home base: a room you walk around in, with everything in your
## stash on show. Every weapon hangs on one rack in the armory, an alcove off
## the left of the room with the locker at its entrance and the gunsmith bench
## in a workshop corner of its own, off to the side of the way in. The main room holds armor and flight rigs along the back
## wall, the garage, ability chips, and shelves for supplies and loot. There
## is no launch pad: you leave for a world through a squad portal opened from
## the watch (`open_portal`).
##
## The base is a view of a stash, never a second store. `show_gear` is given a
## stash and a loadout (the local `Profile`'s, or the account a server keeps)
## and rebuilds the displays. Using a display asks for a loadout change through
## `equip_requested`; whoever owns the stash decides and calls `show_gear` again.
##
## The base grows with the account's upgrades (`BaseUpgrades`, the third
## thing `show_gear` is given). With none it is the starter bunker: the
## armory is a shallow nook, the garage has one bay, the firing range is shut
## and a few displays have fewer spots (`BaseLayout.spots`). What is not
## owned yet is sealed behind a `Bulkhead` that shows its name and price in
## the room; using one twice asks to buy it through `upgrade_requested`, and
## whoever owns the account decides and calls `show_gear` again.
##
## Like `Raid`, this has no camera, HUD or input code. `player` is an `Actor`
## driven through its `ActorCommand`, so it runs headless.

## The player used a piece of gear on show. `item_id` is "" to take the slot's
## item off.
signal equip_requested(slot: String, item_id: String)
## The player used the door.
signal leave_requested
## The player used a station (a key of `STATIONS`): the locker, the mastery
## bench, the wardrobe, the records board, the trader or the uplink.
## Whoever owns the base opens what it offers.
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
## `Portal.destinations()` id).
signal portal_entered(destination: String)
## The loadout changed and the player now wears it: `player` is a new actor
## in the same spot. Whoever drives the player (a controller, a camera)
## takes it over.
signal player_replaced(actor: Actor)

const BaseLayout := preload("res://core/base/base_layout.gd")
const BaseUpgrades := preload("res://core/base/base_upgrades.gd")
const VehicleScript := preload("res://core/vehicle/vehicle.gd")
const MirrorScript := preload("res://core/visual/mirror.gd")

# Room tuning.
var room_size := Vector3(24.0, 6.0, 18.0)
## The armory alcove off the room's left wall (-X): how deep it goes (x), how
## high (y) and how wide (z). It is centred on the wall.
var armory_size := Vector3(10.5, 6.0, 12.0)
## How wide the way into the armory is, through the room's left wall.
var armory_opening := 8.0
## Until the armory alcove is bought the armory is a nook this deep, closed
## off by a sealed wall that carries the short starter rack.
var nook_depth := 3.0
## The garage off the room's right wall (+X), laid out like the armory:
## depth (x), height (y), width (z), and how wide its way in is.
var garage_size := Vector3(8.0, 6.0, 12.0)
var garage_opening := 10.0
## The firing range behind the back wall (-Z): width (x), height (y) and
## length (z), entered through a door `range_door` wide and high.
var range_size := Vector3(12.0, 10.0, 50.0)
var range_door := Vector2(1.6, 3.0)
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
var spawn_point := Vector3(0.0, 0.1, 5.5)
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

## Where each station stands and which way it faces (local +Z into the room),
## with its title and prompt. The locker stands
## beside the way into the armory, the wardrobe and records along the left
## wall nearer the door, and the rest along the right wall either side of the
## way into the garage.
const STATIONS := {
	"locker": {"prompt": "Pick your loadout", "title": "Locker", "at": Vector3(-11.1, 0.0, -5.4), "yaw": PI / 2.0, "color": Color(0.45, 0.75, 1.0)},
	"wardrobe": {"prompt": "Change how you look", "title": "Wardrobe", "at": Vector3(-11.1, 0.0, 5.3), "yaw": PI / 2.0, "color": Color(0.85, 0.6, 1.0)},
	"records": {"prompt": "Read your record and stash", "title": "Records", "at": Vector3(-11.1, 0.0, 7.2), "yaw": PI / 2.0, "color": Color(0.9, 0.9, 0.85)},
	"mastery": {"prompt": "Pick mastery variants", "title": "Mastery bench", "at": Vector3(11.1, 0.0, 7.9), "yaw": -PI / 2.0, "color": Color(1.0, 0.8, 0.3)},
	"trader": {"prompt": "Buy and sell", "title": "Trader", "at": Vector3(11.1, 0.0, 6.0), "yaw": -PI / 2.0, "color": Color(0.45, 1.0, 0.6)},
	"uplink": {"prompt": "Play online", "title": "Uplink", "at": Vector3(11.1, 0.0, -6.0), "yaw": -PI / 2.0, "color": Color(0.4, 0.95, 1.0)},
}

## The workshop: the gunsmith's corner, a recess off the armory's left-hand
## side wall (going in) just inside the way in, behind the room's left wall.
## It spans these x and z (local to the base), so the bench and the
## fabricator stand out of the walkway and never hide the rack. It is there
## in the starter bunker too: the nook's wall stops short of it.
const WORKSHOP_X := Vector2(-16.0, -12.5)
const WORKSHOP_Z := Vector2(6.5, 9.0)
## The gunsmith bench: where it stands and which way it faces (local +Z is
## where you stand to use it), against the workshop's back wall. One gun sits
## on it at a time: using the bench brings the view to it, where the wheel
## turns through your guns and then each attachment slot's choices, shown on
## the gun as you go (`bench_used`).
const BENCH_AT := Vector3(-13.75, 0.0, 8.55)
const BENCH_YAW := PI
## The fabricator: the crafting console beside the bench, against the
## workshop's far wall, in the bench's own space (local +Z is where you
## stand to use the bench). It faces across the workshop toward its way in.
const CRAFT_ID := "craft"
const CRAFT_TITLE := "Fabricator"
const CRAFT_AT := Vector3(2.0, 0.0, 0.8)
const CRAFT_YAW := -PI / 2.0
const CRAFT_COLOR := Color(0.3, 0.9, 1.0)
## Until the ops consoles are bought, each of these stations also shows the
## station named beside it, which has no console of its own yet.
const MERGED := {"trader": "mastery", "wardrobe": "records"}

## The wall mirror (Caleb's call: every base has one): on the front wall in
## the deploy area by the door, its glass facing into the room
## (local +Z), so you see what you are wearing before you head out.
const MIRROR_AT := Vector3(3.8, 0.35, 8.84)
const MIRROR_YAW := PI
## The deploy area: the front wall between these x, this deep, clear of the
## trader and mastery consoles in the corner. The wall mirror stands in it,
## with room in front to open a squad portal from the watch.
const DEPLOY_FROM_X := 1.9
const DEPLOY_TO_X := 10.2
const DEPLOY_DEPTH := 4.4
## The storage wall: shelves along the front wall from this x, left of the
## door, and the height of each kind's shelf.
const STORAGE_FROM_X := -10.6
const STORAGE_ROWS := {"supplies": 0.95, "chip_case": 1.9, "trophy": 2.85}

## Display kinds whose title is already on the room or the furniture.
const SIGNED_ELSEWHERE := ["bay", "gunsmith"]

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
	var _flash := 0.0

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
		var local := to_local(point) - centre
		var half := size * 0.5 + Vector3.ONE * 0.12
		return absf(local.x) <= half.x and absf(local.y) <= half.y and absf(local.z) <= half.z

	func flash() -> void:
		hits += 1
		_flash = 0.15
		if plate:
			plate.scale = Vector3.ONE * 1.12

	func cool(delta: float) -> void:
		if _flash > 0.0:
			_flash -= delta
			if _flash <= 0.0 and plate:
				plate.scale = Vector3.ONE


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
	_build_garage()
	_build_range()
	_build_course()
	_display_root.name = "Displays"
	add_child(_display_root)
	_build_door()
	_build_wall_mirror()
	_build_banner()
	_build_upgrades()
	_spawn_player()
	_rebuild()
	# Your own base: you stand in it wearing your loadout.
	suit_up()


## Shows this stash and loadout, in a base with these upgrades (ids from
## `BaseUpgrades`; leave them out to keep the ones it has). Safe to call
## before the base is in the tree.
func show_gear(p_stash: Array, p_loadout: Dictionary, p_upgrades: Variant = null) -> void:
	stash = p_stash.duplicate()
	loadout = p_loadout.duplicate()
	if p_upgrades != null:
		var fresh := BaseUpgrades.clean(p_upgrades)
		if fresh != upgrades:
			upgrades = fresh
			if is_inside_tree():
				_build_upgrades()
	if is_inside_tree():
		_rebuild()
		# What you equip goes straight on. Deferred: the change may come from
		# the player's own tick (using a display), and the player is replaced.
		if suited and suited_kit != suit_kit():
			suit_up.call_deferred()


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


## Where the gunsmith bench stands and which way it faces: in the workshop,
## the same place in the starter bunker and the full armory.
func bench_transform() -> Transform3D:
	return _spot(BENCH_AT, BENCH_YAW)


## A number with thousands separators: 1200 -> "1,200".
static func commas(amount: int) -> String:
	var digits := str(absi(amount))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if amount < 0 else "") + digits + out


## What you wear in your base: each loadout slot's item, or the free starter
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


## Puts the loadout on where the player stands: a new actor in the same
## spot, facing the same way, wearing `suit_kit()`, its weapons holstered and
## locked (nobody fights at home, the range aside). `player_replaced` says
## who it is. Called whenever the loadout changes, so your own base always
## shows you in what you will deploy with; a base you visit leaves you as
## you came.
func suit_up() -> void:
	if read_only or not is_inside_tree() or (suited and suited_kit == suit_kit()):
		return
	var old := player
	var at := spawn_point
	var yaw := 0.0
	if old and is_instance_valid(old):
		at = old.position
		yaw = old.cmd.yaw
	var fresh := _new_player(at)
	fresh.cmd.yaw = yaw
	if old and is_instance_valid(old):
		fresh.cmd.pitch = old.cmd.pitch
		fresh.rotation.y = old.rotation.y
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
	for weapon in fresh.weapons:
		var gun := weapon as Gun
		if gun:
			gun.fired.connect(_on_range_shot.bind(gun))
	suited = true
	player_replaced.emit(fresh)


## The watch's squad portal: opens a portal to `destination` (a
## `Portal.destinations()` id) in front of the player, in place of any open
## one. The base is a safe space, so it always may. Returns "" if it opened,
## or why not. Online your squad joins you on the other side; only you are
## in your base.
func open_portal(destination: String) -> String:
	if read_only:
		return "Not your base"
	if player == null or not is_instance_valid(player):
		return "not now"
	if destination not in Portal.destinations():
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
	_range_time += delta
	for target in targets:
		target.place(_range_time)
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
	if not in_range(to_local(from)):
		return
	range_shots += 1
	for target in targets:
		if target.took(to):
			target.flash()
			range_hits += 1
			range_last = "%s at %d m" % [gun.display_name, int(round(from.distance_to(to)))]
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


## True if `point` (local to the base) is inside the room or one of the
## spaces off it: the armory, the garage or the firing range.
func inside(point: Vector3) -> bool:
	var half := room_size * 0.5
	if absf(point.x) < half.x and absf(point.z) < half.z:
		return true
	return in_armory(point) or in_garage(point) or in_range(point) or in_course(point)


## True if `point` (local to the base) is inside the garage.
func in_garage(point: Vector3) -> bool:
	var wall_x := room_size.x * 0.5
	return point.x > wall_x and point.x < wall_x + garage_size.x and absf(point.z) < garage_size.z * 0.5


## True if `point` (local to the base) is inside the firing range.
func in_range(point: Vector3) -> bool:
	var wall_z := room_size.z * 0.5
	return point.z < -wall_z and point.z > -wall_z - range_size.z and absf(point.x) < range_size.x * 0.5


## True if `point` (local to the base) is inside the flight course's yard.
func in_course(point: Vector3) -> bool:
	var start := _course_z()
	return point.z < start and point.z > start - course_size.z and absf(point.x) < course_size.x * 0.5


## Where the flight course's yard begins: the range's end wall.
func _course_z() -> float:
	return -room_size.z * 0.5 - range_size.z - 0.5


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


## True if `point` (local to the base) is inside the armory alcove or its
## workshop.
func in_armory(point: Vector3) -> bool:
	var wall_x := room_size.x * 0.5
	if in_workshop(point):
		return true
	return point.x < -wall_x and point.x > -wall_x - armory_size.x and absf(point.z) < armory_size.z * 0.5


## True if `point` (local to the base) is inside the workshop, the gunsmith's
## corner off the armory.
func in_workshop(point: Vector3) -> bool:
	return point.x > WORKSHOP_X.x and point.x < WORKSHOP_X.y and point.z > WORKSHOP_Z.x - 0.5 and point.z < WORKSHOP_Z.y


## Where a spot is, and which way it faces: local +Z points into the room.
func spot_transform(kind: String, index: int) -> Transform3D:
	var wall_x := room_size.x * 0.5
	var wall_z := room_size.z * 0.5
	# The armory's back wall (the nook's sealed wall until the alcove is
	# bought), and its side walls either side of the bench.
	var alcove := owns("armory_alcove")
	var back_x := -wall_x - (armory_size.x if alcove else nook_depth)
	var side_z := armory_size.z * 0.5
	var i := float(index)
	match kind:
		"rack_guns":
			# The armory's back wall: two rows of six, facing the way in. The
			# nook's short rack is one row of four.
			var cols := 6 if alcove else 4
			var col := float(index % cols)
			var row := float(index / cols)
			return _spot(Vector3(back_x + 0.3, 2.55 - 1.2 * row, -0.95 * float(cols - 1) + 1.9 * col), PI / 2.0)
		"rack_sidearms":
			# The armory's right-hand wall (going in): two rows of four.
			var col := float(index % 4)
			var row := float(index / 4)
			return _spot(Vector3(back_x + 1.4 + 1.2 * col, 2.3 - 0.95 * row, -side_z + 0.3), 0.0)
		"rack_melee":
			# The armory's left-hand wall: one row, standing upright, short of
			# the workshop's way in. In the nook that wall is the way in, so
			# its two hang upright on the sealed wall, past the long guns.
			if not alcove:
				return _spot(Vector3(back_x + 0.3, 1.3, side_z - 1.6 + 0.9 * i), PI / 2.0)
			return _spot(Vector3(back_x + 0.6 + 1.05 * i, 1.3, side_z - 0.3), PI)
		"armor_stand":
			# The back wall, left of the door to the range.
			return _spot(Vector3(-10.5 + 1.8 * i, 0.0, -wall_z + 1.0), 0.0)
		"rig_stand":
			# The back wall, right of the door to the range.
			return _spot(Vector3(2.0 + 2.0 * i, 0.0, -wall_z + 1.0), 0.0)
		"chip_case", "supplies", "trophy":
			# A shelf each on the storage wall, left of the door.
			return _spot(Vector3(STORAGE_FROM_X + 0.95 * i, STORAGE_ROWS[kind], wall_z - 0.4), PI)
		"artifact_case":
			# The chip shelf's far end, past its six spots.
			return _spot(Vector3(STORAGE_FROM_X + 0.95 * (6 + i), STORAGE_ROWS["chip_case"], wall_z - 0.4), PI)
		"bay":
			# Side by side in the garage, parked nose-out toward the room.
			return _spot(Vector3(wall_x + garage_size.x * 0.5, 0.0, -4.2 + 2.8 * i), -PI / 2.0)
		_:
			return _spot(Vector3(-10.5 + 1.1 * i, 1.1, wall_z - 0.3), PI)


func _spot(at: Vector3, yaw: float) -> Transform3D:
	return Transform3D(Basis.from_euler(Vector3(0.0, yaw, 0.0)), at)


# --- The room ----------------------------------------------------------------

func _build_room() -> void:
	var x := room_size.x
	var y := room_size.y
	var z := room_size.z
	_floor(Vector2(x, z), Vector3.ZERO)
	_ceiling(Vector2(x, z), Vector3.ZERO, y)
	# The back wall has a door through to the firing range.
	var door_w := range_door.x
	var side_w := (x + 1.0 - door_w) * 0.5
	for side: float in [-1.0, 1.0]:
		_wall(Vector3(side_w, y, 0.5), Vector3(side * (door_w + side_w) * 0.5, y * 0.5, -z * 0.5 - 0.25), Vector3.BACK)
	_wall(Vector3(door_w, y - range_door.y, 0.5), Vector3(0, (y + range_door.y) * 0.5, -z * 0.5 - 0.25), Vector3.ZERO)
	_wall(Vector3(x + 1.0, y, 0.5), Vector3(0, y * 0.5, z * 0.5 + 0.25), Vector3.FORWARD)
	# The left wall stops either side of the way into the armory.
	var piece := (z - armory_opening) * 0.5
	for side: float in [-1.0, 1.0]:
		_wall(Vector3(0.5, y, piece), Vector3(-x * 0.5 - 0.25, y * 0.5, side * (armory_opening * 0.5 + piece * 0.5)), Vector3.RIGHT)
	# The right wall stops either side of the way into the garage.
	var right_piece := (z - garage_opening) * 0.5
	for side: float in [-1.0, 1.0]:
		_wall(Vector3(0.5, y, right_piece), Vector3(x * 0.5 + 0.25, y * 0.5, side * (garage_opening * 0.5 + right_piece * 0.5)), Vector3.LEFT)
	_build_deploy_area()
	_build_storage_wall()
	_build_gear_bays()
	Look.interior(self, Color(0.56, 0.6, 0.66), 1.3)
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
## displays of the `BaseLayout.ARMORY` kinds, and the gunsmith's workshop
## opens off its left-hand wall just inside the way in (`_build_workshop`).
func _build_armory() -> void:
	var wall_x := room_size.x * 0.5
	var depth := armory_size.x
	var y := armory_size.y
	var width := armory_size.z
	var mid_x := -wall_x - depth * 0.5
	var back := -wall_x - depth
	_floor(Vector2(depth, width), Vector3(mid_x, 0, 0))
	_ceiling(Vector2(depth, width), Vector3(mid_x, 0, 0), y)
	_wall(Vector3(0.5, y, width + 1.0), Vector3(back - 0.25, y * 0.5, 0), Vector3.RIGHT)
	# The right-hand side wall runs the whole way; the left-hand one stops at
	# the workshop's way in.
	var left_long := WORKSHOP_X.x - back
	_wall(Vector3(depth, y, 0.5), Vector3(mid_x, y * 0.5, -(width * 0.5 + 0.25)), Vector3.BACK)
	_wall(Vector3(left_long, y, 0.5), Vector3(back + left_long * 0.5, y * 0.5, width * 0.5 + 0.25), Vector3.FORWARD)
	var accent := Color(1.0, 0.62, 0.22)
	# A dark band behind the rack on each wall, so the weapons read as one rack.
	var band := Color(0.13, 0.13, 0.14)
	add_child(_part(Vector3(0.04, 2.6, width - 0.6), Vector3(back + 0.1, 2.0, 0), band))
	add_child(_part(Vector3(depth - 0.8, 2.4, 0.04), Vector3(mid_x - 0.1, 1.9, -(width * 0.5 - 0.1)), band))
	add_child(_part(Vector3(left_long - 0.6, 2.4, 0.04), Vector3(back + left_long * 0.5, 1.9, width * 0.5 - 0.1), band))
	# A light bar over each wall of the rack, so the weapons are lit from above.
	var bar_glow := Color(1.0, 0.93, 0.8)
	add_child(_part(Vector3(0.12, 0.05, width - 0.8), Vector3(back + 0.35, 3.45, 0), bar_glow, true))
	add_child(_part(Vector3(depth - 1.0, 0.05, 0.12), Vector3(mid_x - 0.1, 3.25, -(width * 0.5 - 0.35)), bar_glow, true))
	add_child(_part(Vector3(left_long - 0.8, 0.05, 0.12), Vector3(back + left_long * 0.5, 3.25, width * 0.5 - 0.35), bar_glow, true))
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
		for at: Vector3 in [Vector3(mid_x, 4.6, 0), Vector3(back + 1.4, 3.2, -3.0),
				Vector3(back + 1.4, 3.2, 3.0), Vector3(mid_x, 3.0, -width * 0.5 + 1.2),
				Vector3(back + left_long * 0.5, 3.0, width * 0.5 - 1.2)]:
			var light := Look.lamp(Color(1.0, 0.92, 0.82), 3.6, 9.0)
			light.position = at
			add_child(light)
	_build_workshop()


## The workshop: the gunsmith's corner, a recess off the armory's left-hand
## wall (`WORKSHOP_X`, `WORKSHOP_Z`) with its own floor, walls, a warm lamp
## and its name over the way in. The bench and the fabricator stand in it.
func _build_workshop() -> void:
	var y := armory_size.y
	var from_z := armory_size.z * 0.5
	var size := Vector2(WORKSHOP_X.y - WORKSHOP_X.x, WORKSHOP_Z.y - from_z)
	var mid := Vector3((WORKSHOP_X.x + WORKSHOP_X.y) * 0.5, 0, (from_z + WORKSHOP_Z.y) * 0.5)
	_floor(size, mid)
	_ceiling(size, mid, y)
	_wall(Vector3(size.x + 1.0, y, 0.5), Vector3(mid.x, y * 0.5, WORKSHOP_Z.y + 0.25), Vector3.FORWARD)
	_wall(Vector3(0.5, y, size.y + 0.5), Vector3(WORKSHOP_X.x - 0.25, y * 0.5, mid.z + 0.25), Vector3.RIGHT)
	# The armory's wall carries on over the way in.
	var head := 3.2
	_wall(Vector3(size.x, y - head, 0.5), Vector3(mid.x, (y + head) * 0.5, from_z + 0.25), Vector3.FORWARD)
	var accent := Color(1.0, 0.62, 0.22)
	# A lit sill across the way in, and the workshop's name over it.
	var sill := _part(Vector3(size.x, 0.04, 0.14), Vector3(mid.x, 0.02, from_z + 0.25), accent, true)
	sill.name = "WorkshopSill"
	add_child(sill)
	var title := _label("GUNSMITH", accent, 0.36)
	title.name = "WorkshopSign"
	title.position = Vector3(mid.x, 3.9, from_z - 0.1)
	title.rotation.y = PI
	add_child(title)
	if Look.enabled:
		var light := Look.lamp(Color(1.0, 0.9, 0.75), 3.0, 7.0)
		light.position = Vector3(mid.x, 3.6, mid.z + 0.4)
		add_child(light)


## The garage: a bay off the right wall, like the armory, where every bike
## you own is parked nose-out on its own painted bay.
func _build_garage() -> void:
	var wall_x := room_size.x * 0.5
	var depth := garage_size.x
	var y := garage_size.y
	var width := garage_size.z
	var mid_x := wall_x + depth * 0.5
	_floor(Vector2(depth, width), Vector3(mid_x, 0, 0))
	_ceiling(Vector2(depth, width), Vector3(mid_x, 0, 0), y)
	_wall(Vector3(0.5, y, width + 1.0), Vector3(wall_x + depth + 0.25, y * 0.5, 0), Vector3.LEFT)
	for side: float in [-1.0, 1.0]:
		_wall(Vector3(depth, y, 0.5), Vector3(mid_x, y * 0.5, side * (width * 0.5 + 0.25)), Vector3(0, 0, -side))
	var hazard := Color(0.85, 0.65, 0.15)
	# A roll-up door frame across the way in, raised, and hazard stripes.
	var steel := Color(0.28, 0.29, 0.31)
	add_child(_part(Vector3(0.4, 0.5, garage_opening), Vector3(wall_x + 0.1, 4.6, 0), steel))
	for side: float in [-1.0, 1.0]:
		add_child(_part(Vector3(0.3, 4.4, 0.3), Vector3(wall_x + 0.1, 2.2, side * (garage_opening * 0.5 - 0.15)), hazard))
	var sill := _part(Vector3(0.14, 0.04, garage_opening), Vector3(wall_x, 0.02, 0), hazard, true)
	sill.name = "GarageSill"
	add_child(sill)
	var title := _label("GARAGE", Color(1.0, 0.62, 0.22), 0.5)
	title.name = "GarageSign"
	title.position = Vector3(wall_x - 0.06, 5.2, 0)
	title.rotation.y = -PI / 2.0
	add_child(title)
	# A tool wall at the back.
	add_child(_part(Vector3(0.04, 1.6, width - 1.0), Vector3(wall_x + depth - 0.02, 1.8, 0), Color(0.2, 0.2, 0.22)))
	if Look.enabled:
		for at: Vector3 in [Vector3(mid_x, 4.6, -3.0), Vector3(mid_x, 4.6, 3.0)]:
			var light := Look.lamp(Color(1.0, 0.92, 0.8), 3.0, 10.0)
			light.position = at
			add_child(light)


## The firing range: a long hall behind the back wall. Past the firing line
## your weapons are free and never run dry, and targets stand, slide and fly
## at set distances. A board over the lane keeps score. Nothing here is real:
## no damage is dealt and no mastery is earned (only use in a world pays).
func _build_range() -> void:
	var wall_mat := _shell("wall")
	var wall_z := room_size.z * 0.5
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
	# Above the room's own ceiling the range's end of the back wall goes on up.
	_wall(Vector3(width, y - room_size.y, 0.5), Vector3(0, (y + room_size.y) * 0.5, -wall_z - 0.25), Vector3.ZERO)
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
	var title := _label("FIRING RANGE", accent, 0.36)
	title.name = "RangeSign"
	title.position = Vector3(0, range_door.y + 0.5, -wall_z + 0.06)
	add_child(title)
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
		var target := RangeTarget.new()
		target.kind = spec["kind"]
		target.home = spec["at"]
		target.phase = spec.get("phase", 0.0)
		target.name = "Target_%s_%d" % [target.kind, targets.size()]
		target.position = target.home
		var face := Color(0.95, 0.9, 0.8)
		var size := Vector3(0.8, 1.6, 0.1)
		var centre := Vector3(0, 1.3, 0)
		if target.kind == "drone":
			size = Vector3(0.7, 0.3, 0.7)
			centre = Vector3.ZERO
			face = Color(0.4, 0.9, 1.0)
		else:
			target.add_child(_part(Vector3(0.08, 0.5, 0.08), Vector3(0, 0.25, 0), Color(0.3, 0.3, 0.32)))
		target.size = size
		target.centre = centre
		target.plate = _part(size, centre, face, target.kind == "drone")
		target.add_child(target.plate)
		if target.kind != "drone":
			# Rings on the plate, so a hit near the middle reads as one.
			target.add_child(_part(Vector3(0.4, 0.4, 0.02), centre + Vector3(0, 0.2, 0.06), Color(0.8, 0.25, 0.2)))
			target.add_child(_part(Vector3(0.14, 0.14, 0.03), centre + Vector3(0, 0.2, 0.07), Color(0.95, 0.9, 0.8)))
		var shape := BoxShape3D.new()
		shape.size = size
		var col := CollisionShape3D.new()
		col.shape = shape
		col.position = centre
		target.add_child(col)
		add_child(target)
		targets.append(target)


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


## The base's shell is steel, not rock: dark plated floors, panelled walls
## between ribs and a ceiling grid. One material for each part.
func _shell(part: String) -> Material:
	match part:
		"floor":
			return Look.surface("metal", {"tint": Color(0.62, 0.64, 0.68), "grime": 0.3, "scale": 0.5, "metal": 0.1, "rough_mult": 1.5})
		"ceiling":
			return Look.surface("metal", {"tint": Color(0.42, 0.44, 0.47), "grime": 0.2, "scale": 0.5, "metal": 0.1, "rough_mult": 1.4})
		"seal":
			return Look.surface("metal", {"tint": Color(0.3, 0.31, 0.34), "grime": 0.3, "scale": 0.4, "metal": 0.4})
	return Look.surface("metal", {"tint": Color(0.66, 0.69, 0.73), "grime": 0.15, "scale": 0.4, "metal": 0.15, "rough_mult": 1.3})


## A plated floor `size` across (x, z) centred on `at`, its top at y 0, with a
## seam every `plate_size` metres.
func _floor(size: Vector2, at: Vector3) -> void:
	_box(Vector3(size.x, 0.5, size.y), at + Vector3(0, -0.25, 0), _shell("floor"))
	var seam := Color(0.14, 0.15, 0.17)
	var x := -size.x * 0.5 + plate_size
	while x < size.x * 0.5 - 0.1:
		add_child(_part(Vector3(0.035, 0.008, size.y), at + Vector3(x, 0.004, 0), seam))
		x += plate_size
	var z := -size.y * 0.5 + plate_size
	while z < size.y * 0.5 - 0.1:
		add_child(_part(Vector3(size.x, 0.008, 0.035), at + Vector3(0, 0.004, z), seam))
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
		add_child(_part(Vector3(0.16, 0.2, size.y), at + Vector3(-size.x * 0.5 + step.x * i, height - 0.1, 0), beam))
	for j in range(1, rows):
		add_child(_part(Vector3(size.x, 0.2, 0.16), at + Vector3(0, height - 0.1, -size.y * 0.5 + step.y * j), beam))
	for i in cols:
		for j in rows:
			if (i + j) % 2 == 0:
				var centre := Vector3(-size.x * 0.5 + step.x * (i + 0.5), height - 0.02, -size.y * 0.5 + step.y * (j + 0.5))
				add_child(_part(Vector3(minf(step.x * 0.5, 1.6), 0.03, minf(step.y * 0.3, 0.6)), at + centre, glow, true))


## A wall: a box like `_box`, panelled on the face toward `inward` (a unit
## axis, or zero for a wall that shows no face) with ribs every
## `rib_spacing` metres, a kick plate at the floor and a rail at the top.
func _wall(size: Vector3, at: Vector3, inward: Vector3) -> void:
	_box(size, at, _shell("wall"))
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
	add_child(_part(span.call(length, 0.25, 0.06), face + inward * 0.03 + Vector3(0, bottom + 0.125 - at.y, 0), kick))
	add_child(_part(span.call(length, 0.12, 0.06), face + inward * 0.03 + Vector3(0, bottom + size.y - 0.3 - at.y, 0), rib))
	var count := int(floor(length / rib_spacing))
	if count < 1:
		return
	var gap := length / float(count + 1)
	for i in range(1, count + 1):
		var offset := -length * 0.5 + gap * i
		var rib_at := face + inward * 0.04 + (Vector3(offset, 0, 0) if along_x else Vector3(0, 0, offset))
		add_child(_part(span.call(0.16, size.y - 0.4, 0.08), rib_at + Vector3(0, 0.05, 0), rib))


## The deploy area along the front wall, right of the door: the wall mirror,
## inside one marked bay with its name on the wall. You
## check your gear in the mirror, raise the watch and open a portal; the door out is
## beside it.
func _build_deploy_area() -> void:
	var wall_z := room_size.z * 0.5
	var hazard := Color(1.0, 0.62, 0.22)
	var from_x := DEPLOY_FROM_X
	var to_x := DEPLOY_TO_X
	var near_z := wall_z - DEPLOY_DEPTH
	var mid_x := (from_x + to_x) * 0.5
	var width := to_x - from_x
	add_child(_part(Vector3(width, 0.012, DEPLOY_DEPTH), Vector3(mid_x, 0.006, wall_z - DEPLOY_DEPTH * 0.5), Color(0.2, 0.21, 0.23)))
	add_child(_part(Vector3(width, 0.02, 0.1), Vector3(mid_x, 0.01, near_z), hazard, true))
	for x: float in [from_x, to_x]:
		add_child(_part(Vector3(0.1, 0.02, DEPLOY_DEPTH), Vector3(x, 0.01, wall_z - DEPLOY_DEPTH * 0.5), hazard, true))
	# A panel on the wall behind with the area's name, lit along its top.
	add_child(_part(Vector3(width - 0.4, 2.2, 0.06), Vector3(mid_x, 2.9, wall_z - 0.08), Color(0.16, 0.17, 0.19)))
	add_child(_part(Vector3(width - 0.4, 0.06, 0.08), Vector3(mid_x, 4.04, wall_z - 0.1), hazard, true))
	var title := _label("DEPLOY", hazard, 0.5)
	title.name = "DeploySign"
	title.position = Vector3(mid_x, 3.5, wall_z - 0.13)
	title.rotation.y = PI
	add_child(title)


## The storage wall: shelving along the front wall left of the door, one
## shelf each for the supplies, the ability chips and the trophies.
func _build_storage_wall() -> void:
	var wall_z := room_size.z * 0.5
	var left := STORAGE_FROM_X - 0.6
	var right := STORAGE_FROM_X + 7.6
	var mid := (left + right) * 0.5
	var width := right - left
	var steel := Color(0.24, 0.25, 0.27)
	var back := Color(0.16, 0.17, 0.19)
	add_child(_part(Vector3(width, 3.2, 0.05), Vector3(mid, 1.9, wall_z - 0.08), back))
	for kind: String in STORAGE_ROWS:
		var y: float = STORAGE_ROWS[kind]
		add_child(_part(Vector3(width, 0.05, 0.55), Vector3(mid, y - 0.33, wall_z - 0.36), steel))
		add_child(_part(Vector3(width, 0.02, 0.02), Vector3(mid, y - 0.31, wall_z - 0.64), Color(0.45, 0.9, 1.0), true))
	for x: float in [left, right]:
		add_child(_part(Vector3(0.08, 3.3, 0.6), Vector3(x, 1.65, wall_z - 0.36), steel))
	add_child(_part(Vector3(width, 0.06, 0.08), Vector3(mid, 3.52, wall_z - 0.12), Color(0.92, 0.95, 1.0), true))


## Gear bays along the back wall, either side of the range door: a low plate
## with lit edges that the armor and rig stands stand on, a panel behind
## them and a light bar over it, so each reads as one bay.
func _build_gear_bays() -> void:
	var wall_z := room_size.z * 0.5
	var accent := Color(0.45, 0.9, 1.0)
	for bay: Vector2 in [Vector2(-11.6, -0.9), Vector2(1.1, 9.0)]:
		var mid := (bay.x + bay.y) * 0.5
		var width := bay.y - bay.x
		var z := -wall_z + 1.0
		add_child(_part(Vector3(width, 0.03, 1.9), Vector3(mid, 0.015, z), Color(0.2, 0.21, 0.23)))
		add_child(_part(Vector3(width, 0.035, 0.06), Vector3(mid, 0.02, z + 0.95), accent, true))
		add_child(_part(Vector3(width, 3.0, 0.05), Vector3(mid, 1.7, -wall_z + 0.08), Color(0.16, 0.17, 0.19)))
		add_child(_part(Vector3(width, 0.06, 0.1), Vector3(mid, 3.24, -wall_z + 0.12), Color(0.92, 0.95, 1.0), true))
		if Look.enabled:
			for at_x: float in [bay.x + width * 0.25, bay.x + width * 0.75]:
				var light := Look.lamp(Color(0.92, 0.95, 1.0), 2.2, 5.0)
				light.position = Vector3(at_x, 3.0, z + 0.4)
				add_child(light)


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
		console.position = info["at"]
		console.rotation.y = info["yaw"]
		var color: Color = info["color"]
		var dark := Color(0.17, 0.17, 0.19)
		var title_at := Vector3(0, 2.2, 0)
		var screen := Node3D.new()
		screen.name = "Screen"
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
		var title := _label(station_title(id).to_upper(), color, 0.22)
		title.name = "Title"
		title.position = title_at
		title.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		console.add_child(title)
		add_child(console)
		_gated.append(console)
		stations.append(console)


## Builds everything that depends on the upgrades: the consoles, the bench,
## the walls that seal what is not owned, and a bulkhead for every upgrade
## still to buy. Called again whenever the upgrades change.
func _build_upgrades() -> void:
	for node in _gated:
		if is_instance_valid(node):
			if node.get_parent():
				node.get_parent().remove_child(node)
			node.queue_free()
	_gated.clear()
	stations.clear()
	bulkheads.clear()
	_build_bench()
	_build_stations()
	_build_gates()


func _build_gates() -> void:
	var wall_x := room_size.x * 0.5
	var wall_z := room_size.z * 0.5
	var seal_mat := _shell("seal")
	var hazard := Color(1.0, 0.62, 0.22)
	var dark := Color(0.15, 0.15, 0.17)
	# The armory: a nook closed by a sealed wall until the alcove is bought.
	if not owns("armory_alcove"):
		var x := -wall_x - nook_depth
		_gated.append(_box(Vector3(0.5, armory_size.y, armory_size.z), Vector3(x - 0.25, armory_size.y * 0.5, 0), seal_mat))
		_keep(_part(Vector3(0.04, 2.6, armory_size.z - 0.6), Vector3(x + 0.02, 2.0, 0), Color(0.13, 0.13, 0.14)))
		for y: float in [0.12, 3.9]:
			_keep(_part(Vector3(0.05, 0.14, armory_size.z - 0.6), Vector3(x + 0.03, y, 0), hazard, true))
		# The workshop's way in is wider than the nook: wall off the part of it
		# past the sealed wall, so it leads only into the nook.
		var cut := x - WORKSHOP_X.x
		if cut > 0.0:
			_gated.append(_box(Vector3(cut, armory_size.y, 0.5), Vector3(WORKSHOP_X.x + cut * 0.5, armory_size.y * 0.5, armory_size.z * 0.5 + 0.25), seal_mat))
		_add_bulkhead("armory_alcove", _spot(Vector3(-wall_x - 0.6, 0, armory_opening * 0.5 - 0.7), PI / 2.0), "post")
	elif not owns("heavy_wall"):
		_add_bulkhead("heavy_wall", _spot(Vector3(-wall_x + 0.5, 0, -6.9), PI / 2.0), "post")
	# The garage: the bays not owned yet are walled off behind a lowered shutter.
	var bays := BaseLayout.spots("bay", upgrades)
	if bays < int(BaseLayout.KINDS["bay"]["spots"]):
		var edge := spot_transform("bay", bays - 1).origin.z + 1.4
		var mid_x := wall_x + garage_size.x * 0.5
		_gated.append(_box(Vector3(garage_size.x, garage_size.y, 0.4), Vector3(mid_x, garage_size.y * 0.5, edge + 0.2), seal_mat))
		var width := garage_opening * 0.5 - edge
		_add_bulkhead("garage_full" if owns("bay_second") else "bay_second",
				_spot(Vector3(wall_x + 0.25, 0, edge + width * 0.5), -PI / 2.0), "slab", Vector2(width, 4.35))
	else:
		# The lift: a turntable under the first bay (the bike on it turns, see `_rebuild`).
		var lift := spot_transform("bay", 0).origin
		_keep(_part(Vector3(2.7, 0.05, 2.7), lift + Vector3(0, 0.035, 0), dark))
		for side: float in [-1.0, 1.0]:
			_keep(_part(Vector3(2.7, 0.06, 0.08), lift + Vector3(0, 0.04, side * 1.35), hazard, true))
			_keep(_part(Vector3(0.08, 0.06, 2.7), lift + Vector3(side * 1.35, 0.04, 0), hazard, true))
	# The firing range: its door is shut.
	if not owns("firing_range"):
		_add_bulkhead("firing_range", _spot(Vector3(0, 0, -wall_z - 0.25), 0.0), "slab", range_door)
	# Upgrades that add spots to what is already in the room have a post
	# where the new spots will be.
	if not owns("gear_hall"):
		_add_bulkhead("gear_hall", _spot(Vector3(-6.0, 0, -wall_z + 0.7), 0.0), "post")
	if not owns("trophy_hall"):
		_add_bulkhead("trophy_hall", _spot(Vector3(-6.6, 0, wall_z - 1.1), PI), "post")
	if not owns("lounge"):
		_add_bulkhead("lounge", _spot(Vector3(9.6, 0, -wall_z + 0.6), 0.0), "post")
	if not owns("ops_consoles"):
		_add_bulkhead("ops_consoles", _spot(STATIONS["mastery"]["at"], STATIONS["mastery"]["yaw"]), "post")
	if not owns("finish"):
		_add_bulkhead("finish", _spot(Vector3(-1.75, 0, wall_z - 0.55), PI), "post")
	else:
		# Lit trim round the top of the room and a light column in each corner.
		var trim := Color(0.45, 0.9, 1.0)
		var top := room_size.y - 0.2
		for side: float in [-1.0, 1.0]:
			_keep(_part(Vector3(room_size.x, 0.08, 0.05), Vector3(0, top, side * (wall_z - 0.03)), trim, true))
			_keep(_part(Vector3(0.05, 0.08, room_size.z), Vector3(side * (wall_x - 0.03), top, 0), trim, true))
			for end: float in [-1.0, 1.0]:
				_keep(_part(Vector3(0.12, room_size.y, 0.12), Vector3(side * (wall_x - 0.06), room_size.y * 0.5, end * (wall_z - 0.06)), trim, true))
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
	return "Look at gear and press F to equip it. Walk up to a console and press F to use its screen.\n" \
			+ "Sealed parts of the base open for scrip: look at one and press F twice to buy it."


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

func _rebuild() -> void:
	for child in _display_root.get_children():
		_display_root.remove_child(child)
		child.queue_free()
	displays.clear()
	for entry: Dictionary in BaseLayout.plan(stash, loadout, upgrades):
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
		if display.kind == "bay" and display.index == 0 and owns("garage_full"):
			# The lift turns the bike parked on it. View only.
			var turn := display.create_tween().set_loops()
			turn.tween_property(display.get_node("Model"), "rotation:y", PI + TAU, lift_turn_time).from(PI)
	_build_signs()
	_build_bench_gun()
	gear_shown.emit()


## A small rail label just over each section, with how much did not fit on
## show. Rooms carry the big signs (one over each way in); a section that is
## a room of its own (the garage) or has its own title (the bench) needs none.
## Rail labels only show from nearby, so the room is not a cloud of text.
func _build_signs() -> void:
	var stored := BaseLayout.stored_away(stash, upgrades)
	for kind: String in BaseLayout.KINDS:
		# A kind with no spots yet has no section: its upgrade's panel names it.
		var room := BaseLayout.spots(kind, upgrades)
		if room <= 0 or kind in SIGNED_ELSEWHERE:
			continue
		var text: String = str(BaseLayout.KINDS[kind]["title"]).to_upper()
		if stored.has(kind):
			text += "  (+%d in storage)" % stored[kind]
		var sign_label := _label(text, Color(1.0, 0.62, 0.22), 0.16)
		sign_label.name = "Sign_%s" % kind
		var first := spot_transform(kind, 0)
		var last := spot_transform(kind, room - 1)
		var mid := first.origin.lerp(last.origin, 0.5)
		var top := maxf(first.origin.y, last.origin.y)
		if STORAGE_ROWS.has(kind) or kind == "artifact_case":
			# On the lip of its shelf, under what is on it.
			sign_label.pixel_size *= 0.7
			sign_label.position = Vector3(mid.x, top - 0.43, mid.z) + first.basis.z * 0.27
		elif top < 0.1:
			# Stands stand in a bay: the sign is on the panel behind them.
			sign_label.position = Vector3(mid.x, 2.75, mid.z) - first.basis.z * 0.86
		else:
			sign_label.position = Vector3(mid.x, top + 0.95, mid.z) + first.basis.z * 0.05
		sign_label.rotation.y = first.basis.get_euler().y
		_near_only(sign_label, 14.0)
		_display_root.add_child(sign_label)


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
		"rack_guns", "rack_sidearms":
			var gun := Gun.new()
			gun.item_id = id
			var visual := gun.build_visual()
			gun.free()
			# Side-on to the room, hanging on two pegs.
			visual.rotation.y = PI / 2.0
			var small := display.kind == "rack_sidearms"
			visual.scale = Vector3.ONE * (weapon_scale if small else rack_gun_scale)
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
	var title := _label(bench_name().to_upper(), Color(1.0, 0.62, 0.22), 0.2)
	title.name = "Title"
	title.position = Vector3(0, 2.5, -0.35)
	bench.add_child(title)
	_keep(bench)
	_build_craft_console()
	if Look.enabled:
		var light := Look.lamp(Color(1.0, 0.9, 0.75), 2.0, 5.0)
		light.position = bench_transform() * Vector3(0, 2.2, 0.2)
		_keep(light)


## The fabricator: a cabinet beside the bench, against the workshop's far
## wall, with a screen on top, where gear is crafted from blueprints.
func _build_craft_console() -> void:
	var console := CraftConsole.new()
	console.name = "Station_%s" % CRAFT_ID
	console.base = self
	console.id = CRAFT_ID
	console.transform = bench_transform() * _spot(CRAFT_AT, CRAFT_YAW)
	var dark := Color(0.17, 0.17, 0.19)
	console.add_child(_part(Vector3(1.2, 1.0, 0.5), Vector3(0, 0.5, 0), dark))
	console.add_child(_part(Vector3(1.22, 0.06, 0.52), Vector3(0, 0.3, 0), CRAFT_COLOR, true))
	console.add_child(_part(Vector3(0.12, 0.25, 0.12), Vector3(0, 1.1, 0), dark))
	# A print bed beside the monitor post, lit like something is being made.
	console.add_child(_part(Vector3(0.4, 0.03, 0.3), Vector3(0.36, 1.02, 0.05), CRAFT_COLOR, true))
	_add_collision(console, Vector3(1.3, 1.7, 0.7), Vector3(0, 0.85, 0))
	var screen := Node3D.new()
	screen.name = "Screen"
	screen.position = Vector3(0, 1.62, 0.05)
	screen.rotation.x = -0.08
	screen.add_child(_part(Vector3(SCREEN_SIZE.x + 0.08, SCREEN_SIZE.y + 0.08, 0.06), Vector3(0, 0, -0.035), dark))
	var idle := _part(Vector3(SCREEN_SIZE.x, SCREEN_SIZE.y, 0.01), Vector3.ZERO, CRAFT_COLOR.darkened(0.78), true)
	idle.name = "Idle"
	screen.add_child(idle)
	var hint := _label("Craft from blueprints", CRAFT_COLOR.lightened(0.2), 0.12)
	hint.name = "IdleText"
	hint.position = Vector3(0, 0, 0.012)
	screen.add_child(hint)
	console.add_child(screen)
	console.screen = screen
	var title := _label(CRAFT_TITLE.to_upper(), CRAFT_COLOR, 0.22)
	title.name = "Title"
	title.position = Vector3(0, 2.3, 0)
	title.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	console.add_child(title)
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
## order, one of each.
func bench_guns() -> Array[String]:
	var out: Array[String] = []
	for id: Variant in stash:
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


## Rebuilds the bench's gun and card from the bench state.
func _refresh_bench() -> void:
	if not is_inside_tree():
		return
	for node_name: String in ["BenchGun", "SpecTablet", "SpecCard", "SpecStats"]:
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
		if slot == "primary" and bench_current("primary") == "" and id == starter_primary():
			value += " (free)"
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
		if ItemDB.has_tag(id, "vehicle") and id not in ids and not is_instance_valid(out_vehicles.get(id)):
			ids.append(id)
	return ids


## The weapons the owner has that are not worn, for the watch's carousel at
## home, one of each.
func watch_weapons() -> Array[String]:
	var ids: Array[String] = []
	if read_only:
		return ids
	var worn: Array = [loadout.get("primary", ""), loadout.get("sidearm", ""), loadout.get("melee", "")]
	for id: String in stash:
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
	else:
		at = toy_spot(actor, room)
		if at == Vector3.INF:
			why = "No room there"
	if why != "":
		if actor != null:
			actor.notice.emit(why)
		return why
	var vehicle: Node3D = VehicleScript.new()
	vehicle.name = "Out_%s" % item_id
	vehicle.setup(item_id)
	vehicle.set("local_only", true)
	vehicle.rotation.y = heading
	add_child(vehicle)
	vehicle.global_position = at + Vector3(0.0, 0.25, 0.0)
	vehicle.call("unpack")
	out_vehicles[item_id] = vehicle
	return ""


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
	if id == "" or vehicle.get("rider") != null:
		var why := "Look at a vehicle to pack it" if id == "" else "Someone is riding it"
		if actor != null:
			actor.notice.emit(why)
		return why
	out_vehicles.erase(id)
	vehicle.queue_free()
	actor.notice.emit("Packed %s onto your watch" % ItemDB.item_name(id))
	return ""
