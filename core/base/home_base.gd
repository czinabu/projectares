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
## bench, the wardrobe, the records board, the trader, the launch pad or the
## uplink, or the arena gate. Whoever owns the base opens what it offers.
signal station_requested(station: String)
## The player confirmed buying an upgrade (an id from `BaseUpgrades`) at its
## bulkhead. Whoever owns the account checks the price and takes the scrip.
signal upgrade_requested(id: String)
## The displays were rebuilt.
signal gear_shown
## The player suited up: `player` is now a new actor wearing the loadout.
## Whoever drives the player (a controller, a camera) takes it over.
signal player_replaced(actor: Actor)

const BaseLayout := preload("res://core/base/base_layout.gd")
const BaseUpgrades := preload("res://core/base/base_upgrades.gd")
const VehicleScript := preload("res://core/vehicle/vehicle.gd")

# Room tuning.
var room_size := Vector3(24.0, 6.0, 18.0)
## The armory alcove off the room's left wall (-X): how deep it goes (x), how
## high (y) and how wide (z). It is centred on the wall.
var armory_size := Vector3(7.0, 6.0, 12.0)
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
var range_size := Vector3(8.0, 10.0, 30.0)
var range_door := Vector2(1.6, 3.0)
## How far past the back wall the firing line stands.
var firing_line := 2.0
var spawn_point := Vector3(0.0, 0.1, 5.5)
## Weapons hang a little larger than life so they read from across the room.
var weapon_scale := 1.5
## How long a first press on a bulkhead waits for the second that confirms.
var confirm_time := 4.0
## How long the full garage's lift takes to turn the bike on it once.
var lift_turn_time := 16.0
## How big the gun in the gunsmith bench's vise is shown.
var bench_scale := 1.6
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
## with its title and prompt. The launch pad stands in the deploy area along
## the front wall, the locker
## beside the way into the armory, the wardrobe and records along the left
## wall nearer the door, and the rest along the right wall either side of the
## way into the garage.
const STATIONS := {
	"launch": {"prompt": "Deploy", "title": "Launch pad", "at": Vector3(6.8, 0.0, 6.4), "yaw": PI, "color": Color(1.0, 0.55, 0.2)},
	"locker": {"prompt": "Pick your loadout", "title": "Locker", "at": Vector3(-11.1, 0.0, -5.4), "yaw": PI / 2.0, "color": Color(0.45, 0.75, 1.0)},
	"wardrobe": {"prompt": "Change how you look", "title": "Wardrobe", "at": Vector3(-11.1, 0.0, 5.3), "yaw": PI / 2.0, "color": Color(0.85, 0.6, 1.0)},
	"records": {"prompt": "Read your record and stash", "title": "Records", "at": Vector3(-11.1, 0.0, 7.2), "yaw": PI / 2.0, "color": Color(0.9, 0.9, 0.85)},
	"mastery": {"prompt": "Pick mastery variants", "title": "Mastery bench", "at": Vector3(11.1, 0.0, 7.9), "yaw": -PI / 2.0, "color": Color(1.0, 0.8, 0.3)},
	"trader": {"prompt": "Buy and sell", "title": "Trader", "at": Vector3(11.1, 0.0, 6.0), "yaw": -PI / 2.0, "color": Color(0.45, 1.0, 0.6)},
	"arena": {"prompt": "Enter the arena (no gear at risk)", "title": "Arena gate", "at": Vector3(11.1, 0.0, -7.9), "yaw": -PI / 2.0, "color": Color(1.0, 0.35, 0.3)},
	"uplink": {"prompt": "Play online", "title": "Uplink", "at": Vector3(11.1, 0.0, -6.0), "yaw": -PI / 2.0, "color": Color(0.4, 0.95, 1.0)},
}

## The gunsmith bench: where it stands and which way it faces (local +Z is
## where you stand to use it). It stands in the middle of the armory, long
## side along it, so from the way in you look past its end to the rack. Its
## pegboard holds the attachments in the stash and its vise the primary you
## will deploy with, wearing what is fitted.
const BENCH_AT := Vector3(-15.6, 0.0, 0.4)
const BENCH_YAW := 0.0
## Where the bench stands until the armory alcove is bought: on the room's
## floor beside the way into the nook, end-on to it so its pegboard does not
## hide the rack. See `bench_transform`.
const STARTER_BENCH_AT := Vector3(-9.0, 0.0, -2.8)
const STARTER_BENCH_YAW := 0.0
## Until the ops consoles are bought, each of these stations also shows the
## station named beside it, which has no console of its own yet.
const MERGED := {"trader": "mastery", "wardrobe": "records"}

## The suit-up bay: where you put your loadout on before you deploy. It
## stands in the deploy area beside the launch pad, its back to the front
## wall, facing into the room (local +Z).
const SUIT_AT := Vector3(3.8, 0.0, 7.2)
const SUIT_YAW := PI
## The deploy area: the front wall between these x, this deep, clear of the
## trader and mastery consoles in the corner. The suit-up bay, the launch
## pad and the teleporter's place stand in it, in that order.
const DEPLOY_FROM_X := 1.9
const DEPLOY_TO_X := 10.2
const DEPLOY_DEPTH := 4.4
## The storage wall: shelves along the front wall from this x, left of the
## door, and the height of each kind's shelf.
const STORAGE_FROM_X := -10.6
const STORAGE_ROWS := {"supplies": 0.95, "chip_case": 1.9, "trophy": 2.85}
## How long the bay's arms take to fit the gear, there and back (view only).
var suit_time := 0.9

## Display kinds whose title is already on the room or the furniture.
const SIGNED_ELSEWHERE := ["bay", "gunsmith"]

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
## The firing range's targets, its score and the board that shows it.
var targets: Array[RangeTarget] = []
var range_shots := 0
var range_hits := 0
var range_last := ""
var range_board: Label3D
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


## The gun in the gunsmith bench's vise. Using it puts the next gun from the
## rack in the vise as your primary, so any gun can be fitted out here.
class Vise:
	extends Interactable

	var base: HomeBase
	var item_id := ""

	func get_prompt() -> String:
		var shown := ItemDB.item_name(item_id)
		if base == null or base.read_only:
			return shown
		var next := base.next_bench_gun()
		if next == base.loadout.get("primary", ""):
			return "%s in the vise" % shown
		var next_name := ItemDB.item_name(next if next != "" else HomeBase.starter_primary())
		return "[F] Next gun in the vise: %s" % next_name

	func interact(_actor: Actor) -> void:
		if base and not base.read_only:
			var next := base.next_bench_gun()
			if next != base.loadout.get("primary", ""):
				base.equip_requested.emit("primary", next)


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
	_display_root.name = "Displays"
	add_child(_display_root)
	_build_door()
	_build_suit_bay()
	_build_banner()
	_build_upgrades()
	_spawn_player()
	_rebuild()


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
## bought (`MERGED`).
func has_station(id: String) -> bool:
	return STATIONS.has(id) and (owns("ops_consoles") or id not in MERGED.values())


## The other stations this station's console shows as well, for now.
func also_shows(id: String) -> Array[String]:
	var out: Array[String] = []
	if MERGED.has(id) and not owns("ops_consoles"):
		out.append(MERGED[id])
	return out


## The name on a station's console.
func station_title(id: String) -> String:
	var title: String = STATIONS[id]["title"]
	for other in also_shows(id):
		title += " and " + str(STATIONS[other]["title"]).to_lower()
	return title


## Where the gunsmith bench stands and which way it faces: in the middle of
## the armory once the alcove is open, in front of the nook until then.
func bench_transform() -> Transform3D:
	if owns("armory_alcove"):
		return _spot(BENCH_AT, BENCH_YAW)
	return _spot(STARTER_BENCH_AT, STARTER_BENCH_YAW)


## A number with thousands separators: 1200 -> "1,200".
static func commas(amount: int) -> String:
	var digits := str(absi(amount))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if amount < 0 else "") + digits + out


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
	for weapon in fresh.weapons:
		var gun := weapon as Gun
		if gun:
			gun.fired.connect(_on_range_shot.bind(gun))
	suited = true
	_play_suit_arms()
	player_replaced.emit(fresh)


func _physics_process(delta: float) -> void:
	_range_time += delta
	for target in targets:
		target.place(_range_time)
		target.cool(delta)
	if not suited or player == null or not is_instance_valid(player):
		return
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
		range_board.text += "\nSuit up, step past the line and fire. Nothing here is lost."


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
	return in_armory(point) or in_garage(point) or in_range(point)


## True if `point` (local to the base) is inside the garage.
func in_garage(point: Vector3) -> bool:
	var wall_x := room_size.x * 0.5
	return point.x > wall_x and point.x < wall_x + garage_size.x and absf(point.z) < garage_size.z * 0.5


## True if `point` (local to the base) is inside the firing range.
func in_range(point: Vector3) -> bool:
	var wall_z := room_size.z * 0.5
	return point.z < -wall_z and point.z > -wall_z - range_size.z and absf(point.x) < range_size.x * 0.5


## True if `point` (local to the base) is inside the armory alcove.
func in_armory(point: Vector3) -> bool:
	var wall_x := room_size.x * 0.5
	return point.x < -wall_x and point.x > -wall_x - armory_size.x and absf(point.z) < armory_size.z * 0.5


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
			# The armory's left-hand wall: one row, standing upright.
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
		"gunsmith":
			# Four across and three up on the pegboard behind the bench.
			var col := float(index % 4)
			var row := float(index / 4)
			return bench_transform() * _spot(Vector3(-0.78 + 0.52 * col, 1.92 - 0.4 * row, -0.36), 0.0)
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
## displays of the `BaseLayout.ARMORY` kinds; the bench stands in its middle.
func _build_armory() -> void:
	var wall_x := room_size.x * 0.5
	var depth := armory_size.x
	var y := armory_size.y
	var width := armory_size.z
	var mid_x := -wall_x - depth * 0.5
	_floor(Vector2(depth, width), Vector3(mid_x, 0, 0))
	_ceiling(Vector2(depth, width), Vector3(mid_x, 0, 0), y)
	_wall(Vector3(0.5, y, width + 1.0), Vector3(-wall_x - depth - 0.25, y * 0.5, 0), Vector3.RIGHT)
	for side: float in [-1.0, 1.0]:
		_wall(Vector3(depth, y, 0.5), Vector3(mid_x, y * 0.5, side * (width * 0.5 + 0.25)), Vector3(0, 0, -side))
	var accent := Color(1.0, 0.62, 0.22)
	# A dark band behind the rack on each wall, so the weapons read as one rack.
	var band := Color(0.13, 0.13, 0.14)
	add_child(_part(Vector3(0.04, 2.6, width - 0.6), Vector3(-wall_x - depth + 0.1, 2.0, 0), band))
	for side: float in [-1.0, 1.0]:
		add_child(_part(Vector3(depth - 0.8, 2.4, 0.04), Vector3(mid_x - 0.1, 1.9, side * (width * 0.5 - 0.1)), band))
	# A light bar over each wall of the rack, so the weapons are lit from above.
	var bar_glow := Color(1.0, 0.93, 0.8)
	add_child(_part(Vector3(0.12, 0.05, width - 0.8), Vector3(-wall_x - depth + 0.35, 3.45, 0), bar_glow, true))
	for side: float in [-1.0, 1.0]:
		add_child(_part(Vector3(depth - 1.0, 0.05, 0.12), Vector3(mid_x - 0.1, 3.25, side * (width * 0.5 - 0.35)), bar_glow, true))
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
		for at: Vector3 in [Vector3(mid_x, 4.6, 0), Vector3(-wall_x - depth + 1.4, 3.2, -3.0),
				Vector3(-wall_x - depth + 1.4, 3.2, 3.0), Vector3(mid_x, 3.0, -width * 0.5 + 1.2),
				Vector3(mid_x, 3.0, width * 0.5 - 1.2)]:
			var light := Look.lamp(Color(1.0, 0.92, 0.82), 3.6, 9.0)
			light.position = at
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
	_wall(Vector3(width + 1.0, y, 0.5), Vector3(0, y * 0.5, -wall_z - length - 0.25), Vector3.BACK)
	for side: float in [-1.0, 1.0]:
		_wall(Vector3(0.5, y, length), Vector3(side * (width * 0.5 + 0.25), y * 0.5, mid_z), Vector3(-side, 0, 0))
	# Above the room's own ceiling the range's end of the back wall goes on up.
	_wall(Vector3(width, y - room_size.y, 0.5), Vector3(0, (y + room_size.y) * 0.5, -wall_z - 0.25), Vector3.ZERO)
	var accent := Color(1.0, 0.62, 0.22)
	var line_z := -wall_z - firing_line
	# The firing line: a counter either side of a gap to walk through, and a
	# stripe on the floor.
	var counter := (width - 1.4) * 0.5
	for side: float in [-1.0, 1.0]:
		_box(Vector3(counter, 1.0, 0.5), Vector3(side * (0.7 + counter * 0.5), 0.5, line_z), wall_mat)
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
	board.position = Vector3(0, 4.2, line_z - 3.0)
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
		for at_z: float in [line_z, line_z - 9.0, line_z - 18.0, line_z - 26.0]:
			var light := Look.lamp(Color(1.0, 0.94, 0.85), 3.5, 14.0)
			light.position = Vector3(0, y - 1.0, at_z)
			add_child(light)


## Standing plates at 10, 20 and 27 m, one sliding across the lane at 15 m,
## and three drones circling high up for shooting from a rig.
func _build_targets(line_z: float) -> void:
	var specs := [
		{"at": Vector3(-2.0, 0, line_z - 10.0), "kind": "plate"},
		{"at": Vector3(2.0, 0, line_z - 20.0), "kind": "plate"},
		{"at": Vector3(0.0, 0, line_z - 27.0), "kind": "plate"},
		{"at": Vector3(0.0, 0, line_z - 15.0), "kind": "slider"},
		{"at": Vector3(0.0, 6.0, line_z - 18.0), "kind": "drone", "phase": 0.0},
		{"at": Vector3(0.0, 7.0, line_z - 22.0), "kind": "drone", "phase": TAU / 3.0},
		{"at": Vector3(0.0, 5.0, line_z - 14.0), "kind": "drone", "phase": TAU * 2.0 / 3.0},
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


## The deploy area along the front wall, right of the door: the suit-up bay,
## then the launch pad, inside one marked bay with its name on the wall. You
## suit up, step across and deploy; the door out is beside it.
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
	if not owns("teleporter"):
		_add_bulkhead("teleporter", _spot(Vector3(9.3, 0, 8.1), PI), "hatch")
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


## The gunsmith bench: a heavy table with a vise and a pegboard behind it.
## The gear on it is rebuilt with the rest of the displays.
func _build_bench() -> void:
	var bench := StaticBody3D.new()
	bench.name = "GunsmithBench"
	bench.collision_layer = Actor.LAYER_WORLD
	bench.collision_mask = 0
	bench.transform = bench_transform()
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
	var title := _label(bench_name().to_upper(), Color(1.0, 0.62, 0.22), 0.22)
	title.name = "Title"
	title.position = Vector3(0, 2.75, -0.42)
	bench.add_child(title)
	var how := _label("F on the gun: next gun in the vise.  F on an attachment: fit it.", Color(0.85, 0.83, 0.8), 0.08)
	how.name = "HowTo"
	how.position = Vector3(0, 2.6, -0.38)
	bench.add_child(how)
	if owns("bench_master"):
		# A master's bench: lit edges and a second lamp.
		for z: float in [-0.44, 0.44]:
			bench.add_child(_part(Vector3(2.2, 0.03, 0.03), Vector3(0, 0.95, z), Color(0.25, 0.9, 1.0), true))
		bench.add_child(_part(Vector3(0.4, 0.03, 0.12), Vector3(-0.7, 2.38, 0.1), Color(1.0, 0.85, 0.6), true))
	_keep(bench)
	if Look.enabled:
		var light := Look.lamp(Color(1.0, 0.9, 0.75), 2.0, 5.0)
		light.position = bench_transform() * Vector3(0.6, 2.2, 0)
		_keep(light)


## What the bench is called, by how far it has been upgraded.
func bench_name() -> String:
	if owns("bench_master"):
		return "Master bench"
	return "Workshop bench" if owns("bench_workshop") else "Gunsmith bench"


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
	var shown := Vise.new()
	shown.base = self
	shown.item_id = id
	shown.name = "BenchGun"
	shown.transform = bench_transform() * _spot(Vector3(-0.15, 1.36, 0.1), 0.0)
	var model := Node3D.new()
	model.name = "Model"
	visual.rotation.y = PI / 2.0
	# Bigger than on the rack, so what is fitted shows from the bench.
	visual.scale = Vector3.ONE * bench_scale
	model.add_child(visual)
	shown.add_child(model)
	_add_collision(shown, Vector3(1.4, 0.5, 0.4), Vector3.ZERO)
	# `Look` swaps in the real model and moves the attachments onto it.
	shown.set_meta("display_item", id)
	_display_root.add_child(shown)
	# The card: a small lit tablet propped on the bench beside the vise.
	var tablet := _part(Vector3(0.46, 0.62, 0.02), Vector3.ZERO, Color(0.08, 0.09, 0.1))
	tablet.name = "SpecTablet"
	tablet.transform = bench_transform() * Transform3D(Basis.from_euler(Vector3(-0.3, 0, 0)), Vector3(0.74, 1.27, -0.08))
	_display_root.add_child(tablet)
	var card := _label(spec_text(gun, bare), Color(0.55, 0.95, 1.0), 0.026)
	card.name = "SpecCard"
	card.outline_size = 4
	card.transform = tablet.transform * Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.012))
	_display_root.add_child(card)
	gun.free()
	bare.free()


## Every gun that can go in the vise: the primaries in the stash, in stash
## order, one of each.
func bench_guns() -> Array[String]:
	var out: Array[String] = []
	for id: String in stash:
		if Loadout.is_primary(id) and id not in out:
			out.append(id)
	return out


## The gun the vise takes next: the one after the primary in `bench_guns`,
## and after the last one "" (nothing equipped: the free scrap gun).
func next_bench_gun() -> String:
	var guns := bench_guns()
	var current: String = loadout.get("primary", "")
	var at := guns.find(current)
	if at + 1 < guns.size():
		return guns[at + 1]
	return "" if current != "" or guns.is_empty() else guns[0]


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
	# Writing on a wall is read from the front only, never mirrored from
	# behind. Labels that turn to face you (billboards) are unaffected.
	label.double_sided = false
	return label
