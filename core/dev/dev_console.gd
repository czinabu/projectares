extends RefCounted
## DEV MODE: the dev console's commands, typed on the phone's Console app
## (Caleb's call: on the phone, never a flat overlay). Solo only and only
## while dev mode is on: a solo `Raid` is its own authority, so the console
## changes the world the same way the world's own code would (its spawns,
## its event and weather calls). Online the server decides everything, so
## the console refuses there. `run` takes one typed line and answers with
## the lines the app shows.
##
## Load with `const DevConsole := preload("res://core/dev/dev_console.gd")`.

const DevMode := preload("res://core/dev/dev_mode.gd")

## Every command: [usage, what it does]. `help` prints these.
const COMMANDS := {
	"help": ["help", "this list"],
	"where": ["where", "your position, the ground under you and the zone"],
	"tp": ["tp <x> <z> | tp <x> <y> <z> | tp <marker group> [n] | tp ahead <metres>",
			"teleport, feet on the ground"],
	"markers": ["markers [group]", "the map's marker groups, or one group's spots"],
	"bots": ["bots <n> [faction]", "spawn bots 15 to 25 m around you"],
	"clear": ["clear [metres]", "remove every bot within range (30 m)"],
	"war": ["war <0-1>", "set the war's heat, centred on you"],
	"storm": ["storm start | here | stop", "start a storm (on you with 'here') or end it"],
	"event": ["event warlord | supply_pod | convoy | end", "start or end a world event"],
	"shells": ["shells", "call an artillery salvo near the fighting"],
	"skip": ["skip event | storm | shells | signout | all", "run out a timer now"],
	"heal": ["heal", "full health and armor"],
	"give": ["give <item id> [n]", "put an item in your pack"],
	"vehicle": ["vehicle <item id>", "a vehicle 6 m ahead of you"],
}


## Runs one line. `raid` and `body` are what the player is in and drives
## (either may be null); `online` is true when a server decides.
static func run(line: String, raid: Raid, body: Actor, online: bool) -> Array[String]:
	var words := line.strip_edges().split(" ", false)
	if words.is_empty():
		return []
	var command := words[0].to_lower()
	var args: Array[String] = []
	for i in range(1, words.size()):
		args.append(words[i])
	if command == "help" or command == "?":
		return help()
	if not COMMANDS.has(command):
		return ["Unknown command '%s'. Try help." % command]
	if not DevMode.active():
		return ["Dev mode is off (Settings, Dev tab)."]
	if online:
		return ["Solo only: online the server decides."]
	if raid == null or not is_instance_valid(raid) or raid.mode != Raid.Mode.SOLO:
		return ["Only out in a world (solo). Deploy first."]
	var alive := body != null and is_instance_valid(body) and not body.is_dead
	match command:
		"where": return _where(raid, body) if alive else ["No body."]
		"tp": return _teleport(raid, body, args) if alive else ["No body."]
		"markers": return _markers(raid, args)
		"bots": return _bots(raid, body, args) if alive else ["No body."]
		"clear": return _clear(raid, body, args) if alive else ["No body."]
		"war": return _war(raid, body, args)
		"storm": return _storm(raid, body, args)
		"event": return _event(raid, args)
		"shells": return _shells(raid)
		"skip": return _skip(raid, body, args)
		"heal": return _heal(body) if alive else ["No body."]
		"give": return _give(body, args) if alive else ["No body."]
		"vehicle": return _vehicle(raid, body, args) if alive else ["No body."]
	return []


static func help() -> Array[String]:
	var out: Array[String] = []
	for command: String in COMMANDS:
		out.append("%s: %s" % COMMANDS[command])
	return out


static func _where(raid: Raid, body: Actor) -> Array[String]:
	var at := body.global_position
	var out: Array[String] = ["At %.1f, %.1f, %.1f (%s)" % [at.x, at.y, at.z, raid.world.id]]
	if raid.map != null and raid.map.has_method("ground_height"):
		out.append("Ground %.1f" % float(raid.map.call("ground_height", at.x, at.z)))
	out.append("Zone %d, war %.2f" % [raid.world.zone_at(at), raid.war.intensity])
	return out


## Where feet go at `x, z`: on the map's ground where it has one, else `y`.
static func _feet(raid: Raid, x: float, z: float, y: float) -> Vector3:
	if raid.map != null and raid.map.has_method("ground_height"):
		return Vector3(x, float(raid.map.call("ground_height", x, z)) + 0.15, z)
	return Vector3(x, y, z)


static func _teleport(raid: Raid, body: Actor, args: Array[String]) -> Array[String]:
	if body.vehicle != null:
		return ["Get off the vehicle first."]
	var to := Vector3.INF
	if args.size() >= 2 and args[0] == "ahead" and args[1].is_valid_float():
		var ahead := body.get_aim_dir()
		ahead.y = 0.0
		ahead = ahead.normalized() * float(args[1])
		to = _feet(raid, body.global_position.x + ahead.x, body.global_position.z + ahead.z, body.global_position.y)
	elif args.size() == 2 and args[0].is_valid_float() and args[1].is_valid_float():
		to = _feet(raid, float(args[0]), float(args[1]), body.global_position.y)
	elif args.size() == 3 and args.all(func(a: String) -> bool: return a.is_valid_float()):
		to = Vector3(float(args[0]), float(args[1]), float(args[2]))
	elif args.size() >= 1:
		var spots := raid._map_nodes(args[0])
		if spots.is_empty():
			return ["No markers in group '%s'. Try markers." % args[0]]
		var index := int(args[1]) if args.size() >= 2 and args[1].is_valid_int() else 0
		var spot := spots[clampi(index, 0, spots.size() - 1)].global_position
		to = _feet(raid, spot.x, spot.z, spot.y) if absf(_feet(raid, spot.x, spot.z, spot.y).y - spot.y) < 3.0 \
				else spot + Vector3(0, 0.15, 0)
	if to == Vector3.INF:
		return ["Usage: " + COMMANDS.tp[0]]
	body.global_position = to
	body.velocity = Vector3.ZERO
	return ["Moved to %.1f, %.1f, %.1f" % [to.x, to.y, to.z]]


static func _markers(raid: Raid, args: Array[String]) -> Array[String]:
	if raid.map == null:
		return ["No map."]
	if not args.is_empty():
		var out: Array[String] = []
		var spots := raid._map_nodes(args[0])
		for i in mini(spots.size(), 20):
			var at := spots[i].global_position
			out.append("%d: %.0f, %.0f, %.0f %s" % [i, at.x, at.y, at.z, spots[i].name])
		return out if not out.is_empty() else ["None in '%s'." % args[0]]
	var counts := {}
	for node in _all_nodes(raid.map):
		for group: StringName in node.get_groups():
			if not str(group).begins_with("_"):
				counts[str(group)] = int(counts.get(str(group), 0)) + 1
	var names := counts.keys()
	names.sort()
	return ["  ".join(names.map(func(g: String) -> String: return "%s (%d)" % [g, counts[g]]))]


static func _all_nodes(root: Node) -> Array[Node]:
	var out: Array[Node] = [root]
	for child in root.get_children():
		out.append_array(_all_nodes(child))
	return out


static func _bots(raid: Raid, body: Actor, args: Array[String]) -> Array[String]:
	var count := clampi(int(args[0]) if not args.is_empty() and args[0].is_valid_int() else 3, 1, 40)
	var faction := args[1] if args.size() >= 2 else ""
	var marker := Marker3D.new()
	raid.add_child(marker)
	var made := 0
	for i in count:
		var angle := TAU * i / count + randf() * 0.5
		var spot := body.global_position + Vector3(cos(angle), 0, sin(angle)) * randf_range(15.0, 25.0)
		marker.global_position = _feet(raid, spot.x, spot.z, body.global_position.y)
		var bot := raid._add_bot(marker, false, faction)
		if bot != null:
			made += 1
	marker.queue_free()
	return ["Spawned %d bot%s%s." % [made, "" if made == 1 else "s", (" of " + faction) if faction != "" else ""]]


static func _clear(raid: Raid, body: Actor, args: Array[String]) -> Array[String]:
	var reach := float(args[0]) if not args.is_empty() and args[0].is_valid_float() else 30.0
	var gone := 0
	for bot: Variant in raid.bots.duplicate():
		if is_instance_valid(bot) and (bot as Actor).global_position.distance_to(body.global_position) <= reach:
			raid._remove_actor(bot)
			gone += 1
	return ["Removed %d bot%s." % [gone, "" if gone == 1 else "s"]]


static func _war(raid: Raid, body: Actor, args: Array[String]) -> Array[String]:
	if args.is_empty() or not args[0].is_valid_float():
		return ["War is at %.2f. Usage: %s" % [raid.war.intensity, COMMANDS.war[0]]]
	raid.war.intensity = clampf(float(args[0]), 0.0, 1.0)
	if body != null and is_instance_valid(body):
		raid.war.centre = body.global_position
		raid.war._has_centre = true
	return ["War set to %.2f (it cools on its own as usual)." % raid.war.intensity]


static func _storm(raid: Raid, body: Actor, args: Array[String]) -> Array[String]:
	if raid.world.weather_kind == "":
		return ["%s has no weather." % raid.world.display_name]
	var what := args[0] if not args.is_empty() else "start"
	match what:
		"stop":
			raid.weather.stop()
			return ["Storm over."]
		"start", "here":
			raid.weather.start()
			if what == "here" and body != null and is_instance_valid(body):
				raid.weather.centre = Vector3(body.global_position.x, 0.0, body.global_position.z)
				raid.weather.age = raid.weather.life * 0.5
				raid.weather.strength = 1.0
			return ["%s storm, %.0f s long, centre %.0f, %.0f." % [raid.weather.kind.capitalize(), raid.weather.life,
					raid.weather.centre.x, raid.weather.centre.z]]
	return ["Usage: " + COMMANDS.storm[0]]


static func _event(raid: Raid, args: Array[String]) -> Array[String]:
	var what := args[0] if not args.is_empty() else "warlord"
	if what == "end":
		raid.end_event()
		return ["Event ended."]
	if what not in ["warlord", "supply_pod", "convoy"]:
		return ["Usage: " + COMMANDS.event[0]]
	if not raid.event.is_empty():
		return ["An event is running (%s). event end first." % raid.event.get("title", "")]
	if not raid.start_event(what):
		return ["The map has nowhere to put one."]
	var at: Vector3 = raid.event.get("at", Vector3.ZERO)
	return ["%s at %.0f, %.0f, %.0f." % [raid.event.title, at.x, at.y, at.z]]


static func _shells(raid: Raid) -> Array[String]:
	if raid.world.shelling <= 0.0:
		return ["%s has no shelling." % raid.world.display_name]
	var points := raid.shelling.call_salvo(raid)
	return ["%d shells called." % points.size()] if not points.is_empty() else ["Nowhere clear to shell."]


static func _skip(raid: Raid, body: Actor, args: Array[String]) -> Array[String]:
	var what := args[0] if not args.is_empty() else "all"
	var out: Array[String] = []
	if what in ["event", "all"] and raid.event.is_empty() and raid.world.event_interval > 0.0:
		raid._event_in = 0.0
		out.append("Next event now.")
	if what in ["storm", "all"] and raid.world.weather_kind != "" and not raid.weather.active():
		raid.weather.next_in = 0.0
		out.append("Next storm now.")
	if what in ["shells", "all"] and raid.world.shelling > 0.0:
		raid.shelling._next = 0.0
		out.append("Next salvo now.")
	if what in ["signout", "all"] and body != null and is_instance_valid(body):
		var state := raid.state_for(body)
		if state != null and state.sign_out_left > 0.0:
			state.sign_out_left = 0.01
			out.append("Sign-out finishing.")
	return out if not out.is_empty() else ["Nothing to skip."]


static func _heal(body: Actor) -> Array[String]:
	body.health.health = body.health.max_health
	body.health.set_armor(body.health.max_armor)
	return ["Healed."]


static func _give(body: Actor, args: Array[String]) -> Array[String]:
	if args.is_empty() or not ItemDB.has_item(args[0]):
		return ["Usage: %s (an id from ItemDB)" % COMMANDS.give[0]]
	var count := clampi(int(args[1]) if args.size() >= 2 and args[1].is_valid_int() else 1, 1, 50)
	var added := 0
	for i in count:
		if body.inventory.add_item(args[0]):
			added += 1
	return ["Added %d %s%s." % [added, ItemDB.item_name(args[0]), "" if added == count else " (the pack is full)"]]


static func _vehicle(raid: Raid, body: Actor, args: Array[String]) -> Array[String]:
	if args.is_empty() or not ItemDB.has_item(args[0]) or not ItemDB.has_tag(args[0], "vehicle"):
		var ids := ItemDB.all_ids().filter(func(id: String) -> bool: return ItemDB.has_tag(id, "vehicle"))
		return ["Usage: %s. Vehicles: %s" % [COMMANDS.vehicle[0], ", ".join(ids)]]
	var ahead := body.get_aim_dir()
	ahead.y = 0.0
	ahead = ahead.normalized() * 6.0 if ahead.length() > 0.01 else Vector3(0, 0, -6)
	var at := _feet(raid, body.global_position.x + ahead.x, body.global_position.z + ahead.z, body.global_position.y)
	raid.spawn_vehicle(args[0], at, atan2(-ahead.x, -ahead.z))
	return ["%s at %.0f, %.0f." % [ItemDB.item_name(args[0]), at.x, at.z]]
