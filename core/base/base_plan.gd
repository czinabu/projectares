extends RefCounted
## The home base's plan: which room stands in which socket off the hub.
## Shared by the local `Profile` and the server's `StashService`, so solo and
## online play follow the same rules. Pure functions on plain data, like
## `BaseUpgrades`: no files, no network.
##
## Load with `const BasePlan := preload("res://core/base/base_plan.gd")`.
##
## The base is a hub with `SOCKETS` doorways, all the same size; every room
## fits every socket. A plan maps each socket to one room, every room once.
## Changing it is free and moves nothing in or out of the stash: it is only
## where things stand. The range and flight course always sit behind the hub.
## A room starts in its small form; its upgrade (`ROOMS[room]["opens"]`)
## opens the rest of it, wherever it stands.

## The hub's sockets, in the order the plan table turns through them.
const SOCKETS: Array[String] = ["W1", "W2", "N1", "N2", "E1", "E2"]

## Where each socket is, said the way a player reads it.
const SOCKET_NAMES := {
	"W1": "Left, back", "W2": "Left, front", "N1": "Back, left",
	"N2": "Back, right", "E1": "Right, back", "E2": "Right, front",
}

## Room id -> its entry:
##   title   its name, on the plate over its doorway and on the plan table
##   opens   the upgrade that opens its small form into the whole room ("" if
##           it is whole from the start)
##   holds   one line on what is in it, for the plan table
const ROOMS := {
	"armory": {"title": "Armory", "opens": "armory_alcove", "holds": "Every weapon on one rack"},
	"workshop": {"title": "Workshop", "opens": "", "holds": "Gunsmith bench and fabricator"},
	"garage": {"title": "Garage", "opens": "garage_full", "holds": "Your vehicles, parked"},
	"ops": {"title": "Ops", "opens": "ops_consoles", "holds": "Wardrobe, records, mastery, trader"},
	"gear": {"title": "Gear hall", "opens": "gear_hall", "holds": "Armor, helmets, rigs, chips"},
	"stores": {"title": "Stores", "opens": "trophy_hall", "holds": "Supplies and trophies"},
}

## A new account's base.
const DEFAULT := {"W1": "armory", "W2": "workshop", "N1": "gear", "N2": "stores", "E1": "garage", "E2": "ops"}


static func rooms() -> Array[String]:
	var out: Array[String] = []
	for id: String in ROOMS:
		out.append(id)
	return out


static func title(room: String) -> String:
	return str(ROOMS[room]["title"]) if ROOMS.has(room) else room


## A saved or sent plan made safe: every socket holds exactly one known room
## and every room stands once. Anything missing, unknown or doubled falls back
## to the default placing, so a broken save still builds a whole base.
static func clean(saved: Variant) -> Dictionary:
	var out := {}
	var placed := {}
	if typeof(saved) == TYPE_DICTIONARY:
		for socket: String in SOCKETS:
			var room: Variant = saved.get(socket)
			if typeof(room) == TYPE_STRING and ROOMS.has(room) and not placed.has(room):
				out[socket] = room
				placed[room] = true
	# Whatever is left goes where the default puts it, else the first free
	# socket.
	var left: Array[String] = []
	for room: String in ROOMS:
		if not placed.has(room):
			left.append(room)
	for room: String in left.duplicate():
		for socket: String in SOCKETS:
			if DEFAULT[socket] == room and not out.has(socket):
				out[socket] = room
				left.erase(room)
				break
	for room: String in left:
		for socket: String in SOCKETS:
			if not out.has(socket):
				out[socket] = room
				break
	var ordered := {}
	for socket: String in SOCKETS:
		ordered[socket] = out[socket]
	return ordered


## The socket a room stands in.
static func socket_of(plan: Dictionary, room: String) -> String:
	for socket: String in SOCKETS:
		if plan.get(socket, "") == room:
			return socket
	return ""


## `plan` with `room` moved into `socket`; the room that stood there takes
## the moved room's old socket. Never changes `plan` itself.
static func place(plan: Dictionary, socket: String, room: String) -> Dictionary:
	var out := clean(plan)
	if socket not in SOCKETS or not ROOMS.has(room):
		return out
	var from := socket_of(out, room)
	var there: String = out[socket]
	out[socket] = room
	out[from] = there
	return out
