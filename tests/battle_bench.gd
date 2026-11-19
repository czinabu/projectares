extends Node
## Measures what a big battle costs the server: starts a headless server raid
## with many bots and some players standing in for clients, lets the armies
## fight, and prints the processor time each physics tick takes (all threads,
## Linux only).
##
##   godot --headless --path . res://tests/battle_bench.tscn -- --bots 150 --players 32 --seconds 30
##
## It ends with a pass line and exits 1 when a tick takes more processor
## time on average than the tick's budget (16.7 ms at 60 ticks a second;
## `--budget <ms>` to hold it to another).
##
## It also counts stuck bots (the enemy AI pass): a bot that pressed to move
## at every one-second look through a five-second window and got less than
## `STUCK_MOVE` metres from where it started. The places they get stuck are
## printed at the end, rounded to `STUCK_CELL` metres, so pathing fixes go
## where bots really pile up.

const STUCK_MOVE := 1.5
const STUCK_CELL := 10.0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var bots := int(_arg(args, "--bots", "150"))
	var players := int(_arg(args, "--players", "32"))
	var seconds := float(_arg(args, "--seconds", "30"))
	var world := Worlds.get_world(_arg(args, "--world", "ashfront"))
	var usual := world.bot_count
	world.bot_count = bots
	var raid := world.new_raid()
	add_child(raid)
	raid.start_server(world, 7)
	for i in players:
		raid.add_player([], {}, "Bench%d" % i, "bench%d" % i)
	print("Battle bench: %s, %d bots, %d players, %.0f s" % [world.id, raid.bots.size(), players, seconds])
	var ticks := 0
	var began := Time.get_ticks_msec()
	var cpu_began := _cpu_seconds()
	var window_cpu := cpu_began
	var rate := Engine.physics_ticks_per_second
	# Each bot's place at the window's start and how many looks found it
	# pressing to move.
	var starts := {}
	var pressing := {}
	var stuck_spots := {}
	var stuck_total := 0
	while ticks < seconds * rate:
		await get_tree().physics_frame
		ticks += 1
		if ticks % rate == 0:
			_look_for_stuck(raid, starts, pressing)
		if ticks % (5 * rate) == 0:
			var cpu := _cpu_seconds()
			var stuck := _count_stuck(raid, starts, pressing, stuck_spots)
			stuck_total += stuck
			print("  %3d s: %5.2f ms a tick, %d bots, war %.2f, %d stuck" % [ticks / rate,
					(cpu - window_cpu) * 1000.0 / (5 * rate), raid.bots.size(), raid.war.intensity, stuck])
			window_cpu = cpu
	var budget := float(_arg(args, "--budget", str(1000.0 / rate)))
	var each := (_cpu_seconds() - cpu_began) * 1000.0 / ticks
	print("Processor time: %.2f ms a tick, %.0f%% of the %.1f ms budget" % [each, each / budget * 100.0, budget])
	print("Real time: %.1f s for %.0f s of game" % [(Time.get_ticks_msec() - began) / 1000.0, seconds])
	print("Stuck: %d bot-windows in all" % stuck_total)
	var spots := stuck_spots.keys()
	spots.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return stuck_spots[a] > stuck_spots[b])
	for spot: Vector2i in spots.slice(0, 10):
		print("  stuck x%d near (%d, %d), zone %d" % [stuck_spots[spot], spot.x, spot.y,
				world.zone_at(Vector3(spot.x, 0.0, spot.y))])
	world.bot_count = usual
	var passed := each <= budget
	print("%s: %.2f ms a tick against the %.1f ms budget" % ["PASS" if passed else "FAIL", each, budget])
	get_tree().quit(0 if passed else 1)


## One look a second: which bots are pressing to move.
func _look_for_stuck(raid: Raid, starts: Dictionary, pressing: Dictionary) -> void:
	for node: Variant in raid.bots:
		if not is_instance_valid(node):
			continue
		var bot := node as Actor
		if bot == null or bot.is_dead:
			continue
		var key := bot.get_instance_id()
		if not starts.has(key):
			starts[key] = bot.global_position
			pressing[key] = 0
		# A bot fighting strafes back and forth on purpose: only travel counts.
		var brain := bot.get_node_or_null("Brain") as BotBrain
		if brain != null and brain.state == BotBrain.State.ATTACK:
			continue
		if bot.cmd.move.length() > 0.5:
			pressing[key] = int(pressing[key]) + 1


## At the end of a window: the bots that pressed at every look and barely
## moved. Starts a new window.
func _count_stuck(raid: Raid, starts: Dictionary, pressing: Dictionary, spots: Dictionary) -> int:
	var stuck := 0
	for node: Variant in raid.bots:
		if not is_instance_valid(node):
			continue
		var bot := node as Actor
		if bot == null or bot.is_dead:
			continue
		var key := bot.get_instance_id()
		if not starts.has(key) or int(pressing[key]) < 5:
			continue
		var from: Vector3 = starts[key]
		if Vector2(from.x - bot.global_position.x, from.z - bot.global_position.z).length() < STUCK_MOVE:
			stuck += 1
			var cell := Vector2i(roundi(from.x / STUCK_CELL) * int(STUCK_CELL), roundi(from.z / STUCK_CELL) * int(STUCK_CELL))
			spots[cell] = int(spots.get(cell, 0)) + 1
	starts.clear()
	pressing.clear()
	return stuck


func _arg(args: PackedStringArray, key: String, fallback: String) -> String:
	var at := args.find(key)
	return args[at + 1] if at >= 0 and at + 1 < args.size() else fallback


## Processor time this process has used so far, in seconds, or -1 where the
## system does not say (anything but Linux).
func _cpu_seconds() -> float:
	var stat := FileAccess.open("/proc/self/stat", FileAccess.READ)
	if stat == null:
		return -1.0
	var fields := stat.get_buffer(1024).get_string_from_ascii().get_slice(") ", 1).split(" ")
	if fields.size() < 13:
		return -1.0
	return (float(fields[11]) + float(fields[12])) / 100.0
