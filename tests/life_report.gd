extends Node
## Reads the life log (`LifeLog`, DESIGN.md "Challenge and balance data")
## and prints how a world is going: by risk zone, how many lives end there,
## how many die and how many get out, how long they last and what they
## carry; what does the killing; how often someone dies with several bots
## after them (being converged on); and deaths by how much gear was brought.
## With `--png` it also draws the deaths (red) and sign-outs (green) over
## the map, brighter where more of them pile up.
##
##   godot --headless --path . res://tests/life_report.tscn
##   ... -- --dir <folder> --world ashfront --png <file.png>
##
## The folder defaults to the game's own (`user://life_log`). Copy a
## server's folder here to read it.

const ZONES := ["outer ring", "middle", "core"]
## Gear brought, by stash value: the bands the report splits deaths by.
const GEAR_BANDS := [0, 500, 1500, 4000]
const HEAT_SIZE := 512


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var dir := _arg(args, "--dir", "user://life_log")
	var world := _arg(args, "--world", "")
	var lines := LifeLog.read_all(dir, world)
	print("Life report: %d lives from %s%s" % [lines.size(), ProjectSettings.globalize_path(dir),
			"" if world == "" else " (%s)" % world])
	if lines.is_empty():
		get_tree().quit()
		return
	print_report(summarize(lines))
	var png := _arg(args, "--png", "")
	if png != "":
		heatmap(lines).save_png(png)
		print("Map of where lives ended: %s" % png)
	get_tree().quit()


## Counts the lines up. Static so the tests can check it.
static func summarize(lines: Array[Dictionary]) -> Dictionary:
	var out := {"lives": lines.size(), "died": 0, "left": 0, "zones": {}, "killers": {},
			"converged": 0, "gear": {}}
	for line in lines:
		var died: bool = line.get("outcome") == "died"
		out.died += 1 if died else 0
		out.left += 0 if died else 1
		var zone := int(line.get("zone", 0))
		var row: Dictionary = out.zones.get(zone, {"lives": 0, "died": 0, "alive": [], "carried": 0, "banked": 0})
		row.lives += 1
		row.died += 1 if died else 0
		row.alive.append(float(line.get("alive", 0.0)))
		row.carried += int(line.get("carried_value", 0))
		row.banked += int(line.get("banked_value", 0))
		out.zones[zone] = row
		var band := 0
		for i in GEAR_BANDS.size():
			if int(line.get("gear_value", 0)) >= GEAR_BANDS[i]:
				band = i
		var gear: Dictionary = out.gear.get(band, {"lives": 0, "died": 0, "to_players": 0})
		gear.lives += 1
		if died:
			gear.died += 1
			var killer := str(line.get("killer", "unknown"))
			out.killers[killer] = int(out.killers.get(killer, 0)) + 1
			if killer == "player":
				gear.to_players += 1
			if int(line.get("hunters", 0)) >= 3:
				out.converged += 1
		out.gear[band] = gear
	return out


static func print_report(s: Dictionary) -> void:
	print("  %d lives: %d died (%d%%), %d signed out" % [s.lives, s.died, _pct(s.died, s.lives), s.left])
	print("\n  %-11s %6s %6s %10s %12s %12s" % ["zone", "lives", "died", "median s", "avg carried", "avg banked"])
	var zones: Array = s.zones.keys()
	zones.sort()
	for zone: int in zones:
		var row: Dictionary = s.zones[zone]
		var alive: Array = row.alive
		alive.sort()
		print("  %-11s %6d %5d%% %10.0f %12d %12d" % [ZONES[clampi(zone, 0, 2)] if zone >= 0 else "none",
				row.lives, _pct(row.died, row.lives), alive[alive.size() / 2],
				row.carried / maxi(row.lives, 1), row.banked / maxi(row.lives, 1)])
	print("\n  What killed them:")
	var killers: Array = s.killers.keys()
	killers.sort_custom(func(a: String, b: String) -> bool: return s.killers[a] > s.killers[b])
	for killer: String in killers:
		print("    %-22s %4d (%d%%)" % [killer, s.killers[killer], _pct(s.killers[killer], s.died)])
	print("\n  Died with 3 or more bots after them: %d of %d deaths (%d%%)" % [s.converged, s.died,
			_pct(s.converged, s.died)])
	print("\n  %-14s %6s %6s %14s" % ["gear brought", "lives", "died", "killed by people"])
	var bands: Array = s.gear.keys()
	bands.sort()
	for band: int in bands:
		var row: Dictionary = s.gear[band]
		var label := "%d+" % GEAR_BANDS[band]
		print("  %-14s %6d %5d%% %14d" % [label, row.lives, _pct(row.died, row.lives), row.to_players])


## Deaths in red, sign-outs in green, over the square that holds them all.
static func heatmap(lines: Array[Dictionary]) -> Image:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for line in lines:
		var at := Vector2(float(line.get("x", 0.0)), float(line.get("z", 0.0)))
		lo = lo.min(at)
		hi = hi.max(at)
	var span := maxf(maxf(hi.x - lo.x, hi.y - lo.y), 1.0) * 1.1
	var middle := (lo + hi) * 0.5
	var counts := {"died": PackedFloat32Array(), "left": PackedFloat32Array()}
	for key: String in counts:
		counts[key].resize(HEAT_SIZE * HEAT_SIZE)
	var radius := 6
	for line in lines:
		var at := (Vector2(float(line.get("x", 0.0)), float(line.get("z", 0.0))) - middle) / span + Vector2(0.5, 0.5)
		var px := Vector2i(at * HEAT_SIZE)
		var grid: PackedFloat32Array = counts["died" if line.get("outcome") == "died" else "left"]
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var x := px.x + dx
				var y := px.y + dy
				if x < 0 or y < 0 or x >= HEAT_SIZE or y >= HEAT_SIZE or dx * dx + dy * dy > radius * radius:
					continue
				grid[y * HEAT_SIZE + x] += 1.0 - sqrt(float(dx * dx + dy * dy)) / (radius + 1)
		counts["died" if line.get("outcome") == "died" else "left"] = grid
	var top := 1.0
	for key: String in counts:
		for v in counts[key]:
			top = maxf(top, v)
	var image := Image.create(HEAT_SIZE, HEAT_SIZE, false, Image.FORMAT_RGB8)
	image.fill(Color(0.08, 0.08, 0.1))
	for i in HEAT_SIZE * HEAT_SIZE:
		var red: float = sqrt(counts.died[i] / top)
		var green: float = sqrt(counts.left[i] / top)
		if red > 0.0 or green > 0.0:
			image.set_pixel(i % HEAT_SIZE, i / HEAT_SIZE, Color(0.08 + red * 0.92, 0.08 + green * 0.8, 0.1))
	return image


static func _pct(part: int, whole: int) -> int:
	return roundi(100.0 * part / maxf(whole, 1.0))


func _arg(args: PackedStringArray, flag: String, fallback: String) -> String:
	var at := args.find(flag)
	return args[at + 1] if at >= 0 and at + 1 < args.size() else fallback
