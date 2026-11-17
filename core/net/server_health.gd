class_name ServerHealth
extends Node
## The server's health line: once an interval (a minute by default) it prints
## how long a physics tick takes and how many players and bots each session
## (plaza, worlds, arena) holds. Tick time is processor time per tick across
## all threads (Linux only, -1 elsewhere), against the budget of one tick, and
## the worst single tick of the interval. Reads only; it changes nothing.
##
## A server prints one with `--health-log <seconds>` (0 turns it off).

## The processor time a tick may take: one tick of the physics rate.
static func budget_ms() -> float:
	return 1000.0 / Engine.physics_ticks_per_second

var interval := 60.0
var sessions: Array[NetSession] = []
## Where lines go; the bench swaps it to collect them.
var sink: Callable = func(line: String) -> void: print(line)

var _ticks := 0
var _since := 0.0
var _cpu_then := -1.0
var _worst_ms := 0.0
var _began := Time.get_ticks_msec()


func _ready() -> void:
	name = "ServerHealth"
	_cpu_then = cpu_seconds()


func _physics_process(delta: float) -> void:
	_ticks += 1
	_since += delta
	_worst_ms = maxf(_worst_ms, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	if interval > 0.0 and _since >= interval:
		sink.call(report())


## One line for the interval so far, then starts the next interval.
func report() -> String:
	var cpu := cpu_seconds()
	var each := -1.0
	if cpu >= 0.0 and _cpu_then >= 0.0 and _ticks > 0:
		each = (cpu - _cpu_then) * 1000.0 / _ticks
	var parts: PackedStringArray = []
	var total := 0
	for session in sessions:
		if not is_instance_valid(session) or session.raid == null:
			continue
		var players := session.raid.active_players().size()
		total += players
		parts.append("%s %d players %d bots" % [session.world_id, players, session.raid.bots.size()])
	var budget := budget_ms()
	var line := "Health: up %ds, tick %s ms of %.1f (worst %.1f), %d players | %s" % [
			(Time.get_ticks_msec() - _began) / 1000,
			("%.2f" % each) if each >= 0.0 else "?", budget, _worst_ms, total, " | ".join(parts)]
	_ticks = 0
	_since = 0.0
	_worst_ms = 0.0
	_cpu_then = cpu
	return line


## Processor time this process has used so far, in seconds, or -1 where the
## system does not say (anything but Linux).
static func cpu_seconds() -> float:
	var stat := FileAccess.open("/proc/self/stat", FileAccess.READ)
	if stat == null:
		return -1.0
	var fields := stat.get_buffer(1024).get_string_from_ascii().get_slice(") ", 1).split(" ")
	if fields.size() < 13:
		return -1.0
	return (float(fields[11]) + float(fields[12])) / 100.0
