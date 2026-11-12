extends RefCounted
## The war director: the server's read on how much fighting is going on in a
## world. One lives in each `Raid`. For now it owns a single number, war
## intensity from 0 (quiet) to 1 (all-out battle), and where the heaviest
## fighting is. Strongpoints, reinforcements and world events will hang off
## the same object later.
##
## Plain arithmetic with no nodes, so it runs on a headless server. Clients
## never tick it: `NetSession` copies the server's values in.

## Names for stretches of the meter, lowest first: [starts at, name].
const LEVELS := [[0.0, "Quiet"], [0.2, "Skirmish"], [0.5, "Battle"], [0.8, "All-out war"]]

## How much a kill adds. Fights between players count for the most.
var bot_kill_heat := 0.03
var player_kill_heat := 0.14
## How much a strongpoint changing hands adds.
var capture_heat := 0.1
## Hostile players this close to each other are a fight brewing. Each such
## pair adds this much every second. Headcount alone adds nothing.
var clash_distance := 80.0
var clash_heat := 0.012
## Bots killing each other keep a war simmering: each such kill adds this
## much, but never lifts the meter past the ceiling. Only players take a
## world from a skirmish to a battle.
var battle_heat := 0.008
var battle_ceiling := 0.3
## Seconds after the last kill or clash before the meter starts to fall,
## and how fast it then falls per second.
var calm_delay := 12.0
var cooling := 0.012
## How quickly the centre of the fighting moves to a new kill (0 to 1).
var centre_pull := 0.35

## 0 to 1.
var intensity := 0.0
## Where the heaviest fighting is. Only meaningful while `intensity` is above 0.
var centre := Vector3.ZERO
## A world's multiplier on everything that raises the meter. 0 keeps it quiet.
var scale := 1.0
var _calm_for := 0.0
var _has_centre := false


## A kill happened at `at`.
func report_kill(at: Vector3, victim_is_player: bool) -> void:
	_heat(player_kill_heat if victim_is_player else bot_kill_heat, at)


## One bot killed another at `at`.
func report_battle(at: Vector3) -> void:
	_heat(minf(battle_heat, (battle_ceiling - intensity) / maxf(scale, 0.001)), at)


## A strongpoint changed hands at `at`.
func report_capture(at: Vector3) -> void:
	_heat(capture_heat, at)


## Hostile sides are fighting over a place, for `delta` seconds.
func report_clash(at: Vector3, delta: float) -> void:
	_heat(clash_heat * delta, at, delta)


## Advances the meter. `clashes` holds the midpoint of every pair of hostile
## players within `clash_distance` of each other.
func tick(delta: float, clashes: Array[Vector3] = []) -> void:
	if not clashes.is_empty():
		var middle := Vector3.ZERO
		for at in clashes:
			middle += at
		_heat(clash_heat * clashes.size() * delta, middle / clashes.size(), delta)
		return
	_calm_for += delta
	if _calm_for >= calm_delay:
		intensity = maxf(0.0, intensity - cooling * delta)
		if intensity <= 0.0:
			_has_centre = false


## The name of the current stretch of the meter.
func level_name() -> String:
	return level_for(intensity)


static func level_for(value: float) -> String:
	var name: String = LEVELS[0][1]
	for level: Array in LEVELS:
		if value >= float(level[0]):
			name = level[1]
	return name


## How much more renown a kill pays right now: up to half again in a full battle.
func renown_bonus() -> float:
	return 1.0 + 0.5 * intensity


func _heat(amount: float, at: Vector3, pull_time := 1.0) -> void:
	if scale <= 0.0 or amount <= 0.0:
		return
	intensity = minf(1.0, intensity + amount * scale)
	_calm_for = 0.0
	if not _has_centre:
		centre = at
		_has_centre = true
	else:
		centre = centre.lerp(at, clampf(centre_pull * pull_time, 0.0, 1.0))
