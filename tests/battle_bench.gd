extends Node
## Measures what a big battle costs the server: starts a headless server raid
## with many bots and some players standing in for clients, lets the armies
## fight, and prints the processor time each physics tick takes (all threads,
## Linux only).
##
##   godot --headless --path . res://tests/battle_bench.tscn -- --bots 150 --players 32 --seconds 30

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
	while ticks < seconds * rate:
		await get_tree().physics_frame
		ticks += 1
		if ticks % (5 * rate) == 0:
			var cpu := _cpu_seconds()
			print("  %3d s: %5.2f ms a tick, %d bots, war %.2f" % [ticks / rate,
					(cpu - window_cpu) * 1000.0 / (5 * rate), raid.bots.size(), raid.war.intensity])
			window_cpu = cpu
	var budget := 1000.0 / rate
	var each := (_cpu_seconds() - cpu_began) * 1000.0 / ticks
	print("Processor time: %.2f ms a tick, %.0f%% of the %.1f ms budget" % [each, each / budget * 100.0, budget])
	print("Real time: %.1f s for %.0f s of game" % [(Time.get_ticks_msec() - began) / 1000.0, seconds])
	world.bot_count = usual
	get_tree().quit()


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
