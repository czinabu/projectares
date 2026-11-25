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
##
## A plan also picks the hub's shape (`SHAPES`: the hall, a ring, a spine, a
## courtyard; the six sockets stand round whichever it is) and each room's
## style (`STYLES`: how the room lays out what it holds and how it is
## furnished). The first of each is free; any other is unlocked once, for
## scrip, by its `BaseUpgrades` entry (track "Designs") and is then free to
## switch to and back. A plan keeps its choices whatever is owned: only a
## change is checked (`change`).

## The hub's sockets, in the order the plan table turns through them.
## "F1" is the lounge's doorway (DESIGN.md "The lounge"): on the hub's front
## wall left of the way out in the hall and the courtyard, and off the
## corridor to the range in the spine and the ring, whose front is the way
## out.
const SOCKETS: Array[String] = ["W1", "W2", "N1", "N2", "E1", "E2", "F1"]

## Where each socket is, said the way a player reads it.
const SOCKET_NAMES := {
	"W1": "Left, back", "W2": "Left, front", "N1": "Back, left",
	"N2": "Back, right", "E1": "Right, back", "E2": "Right, front", "F1": "Front, left",
}

## Room id -> its entry:
##   title   its name, on the plate over its doorway and on the plan table
##   opens   the upgrade that opens its small form into the whole room ("" if
##           it is whole from the start)
##   holds   one line on what is in it, for the plan table
##   held    the `LaunchScope` feature that holds it back, if any (`held`)
const ROOMS := {
	"armory": {"title": "Armory", "opens": "armory_alcove", "holds": "Every weapon on one rack"},
	"workshop": {"title": "Workshop", "opens": "", "holds": "Gunsmith bench and fabricator"},
	"garage": {"title": "Garage", "opens": "garage_full", "holds": "Your vehicles, parked"},
	"ops": {"title": "Ops", "opens": "ops_consoles", "holds": "Wardrobe, records, mastery, trader"},
	"gear": {"title": "Gear hall", "opens": "gear_hall", "holds": "Armor, helmets, rigs, chips"},
	"stores": {"title": "Stores", "opens": "trophy_hall", "holds": "Supplies and trophies"},
	"lounge": {"title": "Lounge", "opens": "lounge", "holds": "Somewhere to sit, and a window out", "held": "lounge"},
}

## The hub's shapes, in the order the plan table lists them:
##   title   its name on the plan table
##   blurb   one line on what it is like
##   unlock  the `BaseUpgrades` id that unlocks it ("" if free)
##   sockets where each socket is, said the way a player reads it
const SHAPES := {
	"hall": {"title": "Hall", "blurb": "A square hall, two rooms down each side and two at the back.", "unlock": "",
		"sockets": SOCKET_NAMES},
	"ring": {"title": "Ring", "blurb": "An eight-sided rotunda: every room opens onto the table.", "unlock": "hub_ring",
		"sockets": {"W1": "Left", "W2": "Left, front", "N1": "Left, back", "N2": "Right, back",
			"E1": "Right", "E2": "Right, front", "F1": "Down the corridor"}},
	"spine": {"title": "Spine", "blurb": "A long gallery, three rooms down each side.", "unlock": "hub_spine",
		"sockets": {"W1": "Left, middle", "W2": "Left, front", "N1": "Left, back", "N2": "Right, back",
			"E1": "Right, middle", "E2": "Right, front", "F1": "Down the corridor"}},
	"courtyard": {"title": "Courtyard", "blurb": "A big lit court under a skylight, with planters.", "unlock": "hub_courtyard",
		"sockets": SOCKET_NAMES},
}

## Each room's styles, the first its free one:
##   title   its name on the plan table
##   blurb   one line on what it is like
##   unlock  the `BaseUpgrades` id that unlocks it ("" if free)
const STYLES := {
	"armory": {
		"rack": {"title": "Wall rack", "blurb": "Every weapon on the walls, long guns at the back.", "unlock": ""},
		"vault": {"title": "Vault", "blurb": "A double-sided island rack down the middle.", "unlock": "style_armory_vault"},
		"gallery": {"title": "Gallery", "blurb": "Long guns stood in lit cases round the walls.", "unlock": "style_armory_gallery"},
	},
	"workshop": {
		"bench": {"title": "Back bench", "blurb": "The bench against the back wall.", "unlock": ""},
		"island": {"title": "Island", "blurb": "The bench in the middle under a lamp rig.", "unlock": "style_workshop_island"},
		"pit": {"title": "Pit", "blurb": "A side bench by an inspection pit and hoist.", "unlock": "style_workshop_pit"},
	},
	"garage": {
		"bays": {"title": "Bays", "blurb": "Two rows of painted bays.", "unlock": ""},
		"showroom": {"title": "Showroom", "blurb": "Your best ride on a turntable, the rest round it.", "unlock": "style_garage_showroom"},
		"lift": {"title": "Lift rack", "blurb": "Two lifts, a vehicle over each one parked.", "unlock": "style_garage_lift"},
	},
	"ops": {
		"consoles": {"title": "Consoles", "blurb": "Two consoles down each side.", "unlock": ""},
		"war_table": {"title": "War table", "blurb": "Consoles round a lit map table.", "unlock": "style_ops_war_table"},
		"bridge": {"title": "Bridge", "blurb": "Consoles in a row under a wide screen.", "unlock": "style_ops_bridge"},
	},
	"gear": {
		"stands": {"title": "Stands", "blurb": "Armor along the back, rigs down the side.", "unlock": ""},
		"ring": {"title": "Ring", "blurb": "Armor and helmets round a lit dais.", "unlock": "style_gear_ring"},
		"lockers": {"title": "Lockers", "blurb": "Each suit in its own locker.", "unlock": "style_gear_lockers"},
	},
	"stores": {
		"shelves": {"title": "Shelves", "blurb": "Shelving across the back wall.", "unlock": ""},
		"plinths": {"title": "Plinths", "blurb": "Trophies on lit plinths down an aisle.", "unlock": "style_stores_plinths"},
		"cargo": {"title": "Cargo", "blurb": "Crate stacks and a pallet rack.", "unlock": "style_stores_cargo"},
	},
	"lounge": {
		"den": {"title": "Den", "blurb": "A big sofa round a rug, a lamp and plants.", "unlock": ""},
		"bar": {"title": "Bar", "blurb": "A counter with stools and lit shelves, a booth.", "unlock": "style_lounge_bar"},
		"quarters": {"title": "Quarters", "blurb": "A curtained bunk, a desk and a small sofa.", "unlock": "style_lounge_quarters"},
	},
}

## The finishes a room or the hub can wear, the first the free one. Bought
## once (a "Designs" unlock), a finish can go on any room after.
##   title   its name on the plan table
##   blurb   one line on what it is like
##   unlock  the `BaseUpgrades` id that unlocks it ("" if free)
##   swatch  its colours on the plan table: floor, wall, trim, light
const FINISHES := {
	"steel": {"title": "Steel", "blurb": "Bare plated steel and white light.", "unlock": "",
		"swatch": [Color(0.62, 0.64, 0.68), Color(0.66, 0.69, 0.73), Color(0.3, 0.32, 0.35), Color(0.92, 0.95, 1.0)]},
	"gunmetal": {"title": "Gunmetal", "blurb": "Dark blued steel lit cold blue.", "unlock": "finish_gunmetal",
		"swatch": [Color(0.24, 0.27, 0.31), Color(0.3, 0.33, 0.38), Color(0.14, 0.16, 0.19), Color(0.5, 0.78, 1.0)]},
	"ceramic": {"title": "Ceramic", "blurb": "Clean white panels and grey trim, like a lab.", "unlock": "finish_ceramic",
		"swatch": [Color(0.82, 0.83, 0.84), Color(0.9, 0.91, 0.92), Color(0.5, 0.53, 0.56), Color(0.96, 0.98, 1.0)]},
	"brass": {"title": "Brass", "blurb": "Warm bronzed steel with brass trim.", "unlock": "finish_brass",
		"swatch": [Color(0.45, 0.4, 0.34), Color(0.55, 0.5, 0.43), Color(0.78, 0.6, 0.3), Color(1.0, 0.84, 0.6)]},
	"blackout": {"title": "Blackout", "blurb": "Matte black with lit strips.", "unlock": "finish_blackout",
		"swatch": [Color(0.12, 0.12, 0.13), Color(0.15, 0.15, 0.16), Color(0.08, 0.08, 0.09), Color(1.0, 0.35, 0.5)]},
}

## What can wear a finish: the hub (with the corridor, the range and the
## course behind it) and every room.
const HUB := "hub"

## A new account's base.
const DEFAULT := {"W1": "armory", "W2": "workshop", "N1": "gear", "N2": "stores", "E1": "garage", "E2": "ops",
	"F1": "lounge",
	"shape": "hall", "styles": {"armory": "rack", "workshop": "bench", "garage": "bays", "ops": "consoles",
		"gear": "stands", "stores": "shelves", "lounge": "den"},
	"finishes": {"hub": "steel", "armory": "steel", "workshop": "steel", "garage": "steel", "ops": "steel",
		"gear": "steel", "stores": "steel", "lounge": "steel"}}


static func rooms() -> Array[String]:
	var out: Array[String] = []
	for id: String in ROOMS:
		if not held(id):
			out.append(id)
	return out


## True while the launch holds a room back (`LaunchScope`, its "held"
## feature): its doorway is sealed and the plan table leaves it out.
static func held(room: String) -> bool:
	return ROOMS.has(room) and LaunchScope.holds(str(ROOMS[room].get("held", "")))


static func title(room: String) -> String:
	return str(ROOMS[room]["title"]) if ROOMS.has(room) else room


static func shapes() -> Array[String]:
	var out: Array[String] = []
	for id: String in SHAPES:
		out.append(id)
	return out


## A room's style ids, its free one first.
static func styles(room: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in STYLES.get(room, {}):
		out.append(id)
	return out


## A room's free style.
static func default_style(room: String) -> String:
	var all := styles(room)
	return all[0] if not all.is_empty() else ""


## Every finish id, the free one first.
static func finishes() -> Array[String]:
	var out: Array[String] = []
	for id: String in FINISHES:
		out.append(id)
	return out


## What can wear a finish: the hub, then every room.
static func areas() -> Array[String]:
	var out: Array[String] = [HUB]
	out.append_array(rooms())
	return out


static func finish_title(finish: String) -> String:
	return str(FINISHES[finish]["title"]) if FINISHES.has(finish) else finish


## What an area is called on the plan table.
static func area_title(area: String) -> String:
	return "Hub" if area == HUB else title(area)


static func shape_title(shape: String) -> String:
	return str(SHAPES[shape]["title"]) if SHAPES.has(shape) else shape


static func style_title(room: String, style: String) -> String:
	return str(STYLES[room][style]["title"]) if STYLES.get(room, {}).has(style) else style


## Where a socket is in a hub of this shape, said the way a player reads it.
static func socket_name(shape: String, socket: String) -> String:
	return str(SHAPES.get(shape, SHAPES["hall"])["sockets"].get(socket, socket))


## The `BaseUpgrades` id that unlocks a change (see `change` for the keys),
## or "" if it needs none: a room moved, a free shape or a free style.
static func unlock_for(key: String, value: String) -> String:
	if key == "shape":
		return str(SHAPES.get(value, {}).get("unlock", ""))
	if key.begins_with("style:"):
		return str(STYLES.get(key.substr(6), {}).get(value, {}).get("unlock", ""))
	if key.begins_with("finish:"):
		return str(FINISHES.get(value, {}).get("unlock", ""))
	return ""


## Every design unlock (`BaseUpgrades` track "Designs"): shapes, styles,
## then finishes.
static func unlocks() -> Array[String]:
	var out: Array[String] = []
	for shape: String in SHAPES:
		if str(SHAPES[shape]["unlock"]) != "":
			out.append(str(SHAPES[shape]["unlock"]))
	for room: String in STYLES:
		for style: String in STYLES[room]:
			if str(STYLES[room][style]["unlock"]) != "":
				out.append(str(STYLES[room][style]["unlock"]))
	for finish: String in FINISHES:
		if str(FINISHES[finish]["unlock"]) != "":
			out.append(str(FINISHES[finish]["unlock"]))
	return out


## One change to `plan` by someone who owns the upgrades `owned`. `key` is a
## socket (and `value` the room to move there, as `place`), "shape" (and a
## `SHAPES` id), "style:<room>" (and one of that room's `STYLES`) or
## "finish:<area>" (the hub or a room, and a `FINISHES` id). Returns
## {"ok": true, "plan"} with the changed plan, or {"ok": false, "error"}.
## Never changes `plan` itself.
static func change(plan: Dictionary, owned: Array, key: String, value: String) -> Dictionary:
	var out := clean(plan)
	if key in SOCKETS:
		if not ROOMS.has(value):
			return {"ok": false, "error": "No such room."}
		return {"ok": true, "plan": place(out, key, value)}
	var unlock := unlock_for(key, value)
	if key == "shape":
		if not SHAPES.has(value):
			return {"ok": false, "error": "No such layout."}
		if unlock != "" and unlock not in owned:
			return {"ok": false, "error": "Unlock the %s layout first." % shape_title(value).to_lower()}
		out["shape"] = value
		return {"ok": true, "plan": out}
	if key.begins_with("style:"):
		var room := key.substr(6)
		if not STYLES.get(room, {}).has(value):
			return {"ok": false, "error": "No such style."}
		if unlock != "" and unlock not in owned:
			return {"ok": false, "error": "Unlock the %s style first." % style_title(room, value).to_lower()}
		out["styles"][room] = value
		return {"ok": true, "plan": out}
	if key.begins_with("finish:"):
		var area := key.substr(7)
		if area not in areas():
			return {"ok": false, "error": "No such room."}
		if not FINISHES.has(value):
			return {"ok": false, "error": "No such finish."}
		if unlock != "" and unlock not in owned:
			return {"ok": false, "error": "Unlock the %s finish first." % finish_title(value).to_lower()}
		out["finishes"][area] = value
		return {"ok": true, "plan": out}
	return {"ok": false, "error": "No such change."}


## A saved or sent plan made safe: every socket holds exactly one known room
## and every room stands once. Anything missing, unknown or doubled falls back
## to the default placing, so a broken save still builds a whole base. An
## unknown shape is the hall, a room's unknown style its free one and an
## unknown finish steel.
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
			if str(DEFAULT[socket]) == room and not out.has(socket):
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
	var shape: Variant = saved.get("shape") if typeof(saved) == TYPE_DICTIONARY else null
	ordered["shape"] = shape if typeof(shape) == TYPE_STRING and SHAPES.has(shape) else "hall"
	var picked: Variant = saved.get("styles") if typeof(saved) == TYPE_DICTIONARY else null
	var styled := {}
	for room: String in STYLES:
		var style: Variant = picked.get(room) if typeof(picked) == TYPE_DICTIONARY else null
		styled[room] = style if typeof(style) == TYPE_STRING and STYLES[room].has(style) else default_style(room)
	ordered["styles"] = styled
	var worn: Variant = saved.get("finishes") if typeof(saved) == TYPE_DICTIONARY else null
	var finished := {}
	# Every room's finish, held-back ones too (`held`), so a plan keeps it.
	for area: Variant in [HUB] + ROOMS.keys():
		var finish: Variant = worn.get(area) if typeof(worn) == TYPE_DICTIONARY else null
		finished[area] = finish if typeof(finish) == TYPE_STRING and FINISHES.has(finish) else "steel"
	ordered["finishes"] = finished
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
