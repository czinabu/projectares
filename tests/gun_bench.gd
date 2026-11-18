extends Node
## Measures every gun's time to kill a person, with every round landing, so
## gun roles are tuned by number like the enemies are (`duel_bench.tscn`).
## For each gun it prints, at each range, how many rounds and how long it
## takes to drop 100 health behind each armor frame: body shots, then every
## round on the head. Built from `ItemDB` through `Loadout`, so tuning a gun's
## stats moves these. Spread is not counted: this is the gun at its best.
##
##   godot --headless --path . res://tests/gun_bench.tscn
##   ... -- --ranges 5,15,30,60 --only rifle_carbine,smg_stinger
##   ... -- --recoil   (each gun's recoil pattern: how far a spray climbs and
##   drifts with no pull against it, and what is left to chance; DESIGN.md
##   "Recoil")

## Armor frames a target may wear, by name.
const ARMORS := {"none": 0.0, "scrap": 30.0, "runner": 45.0, "trooper": 85.0, "bulwark": 125.0}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var ranges: Array[float] = []
	for part in _arg(args, "--ranges", "5,15,30,60").split(","):
		ranges.append(float(part))
	var only := _arg(args, "--only", "")
	if "--recoil" in args:
		_recoil_table(only)
		get_tree().quit()
		return
	print("Gun bench: rounds / seconds to drop 100 health, every round landing (body | head)")
	var head := "%-22s %5s" % ["gun", "range"]
	for armor: String in ARMORS:
		head += "  %17s" % armor
	print(head)
	for id: String in guns():
		if only != "" and not id in only.split(","):
			continue
		var gun := make(id)
		for dist in ranges:
			if dist > gun.max_range:
				continue
			var row := "%-22s %4dm" % [id, int(dist)]
			for armor: String in ARMORS:
				var body := time_to_kill(gun, ARMORS[armor], dist, false)
				var top := time_to_kill(gun, ARMORS[armor], dist, true)
				row += "  %7s | %7s" % [_cell(body), _cell(top)]
			print(row)
		gun.free()
	get_tree().quit(0)


## Every conventional gun (firearms that are not power weapons).
static func guns() -> Array[String]:
	var out: Array[String] = []
	for id: String in ItemDB.all_ids():
		if ItemDB.has_tag(id, "firearm") and not ItemDB.has_tag(id, "power"):
			out.append(id)
	return out


## A gun built the way a loadout builds it.
static func make(id: String) -> Gun:
	var gun := Gun.new()
	gun.is_sidearm = ItemDB.has_tag(id, "sidearm")
	Loadout._setup_weapon(gun, id, ItemDB.item_stats(id))
	return gun


## [rounds, seconds] for `gun` to drop a 100-health target wearing `armor`,
## `dist` metres away, every round on the body or every one on the head.
## Every pellet of a shotgun lands. Reloads are not counted.
static func time_to_kill(gun: Gun, armor: float, dist: float, headshots: bool) -> Vector2:
	var health := HealthComponent.new()
	health.set_armor(armor)
	var shots := 0
	while not health.is_dead and shots < 200:
		shots += 1
		for i in gun.pellets:
			var info := DamageInfo.make(gun.damage * gun.range_mult(dist), null, gun.damage_kind)
			info.armor_pierce = gun.armor_pierce
			if headshots:
				info.amount *= gun.headshot_mult
			health.apply_damage(info)
	health.free()
	return Vector2(shots, (shots - 1) * gun.fire_interval)


static func _cell(result: Vector2) -> String:
	return "%d/%.2f" % [int(result.x), result.y]


func _arg(args: PackedStringArray, key: String, fallback: String) -> String:
	var at := args.find(key)
	return args[at + 1] if at >= 0 and at + 1 < args.size() else fallback


## Prints each gun's pattern from the hip: the kick of the 1st, 5th and 10th
## shot, how far a 5- and 10-round spray climbs and drifts when nobody pulls
## against it (degrees, and metres off at 20 m), and the jitter left to
## chance per shot. Aiming takes 60% of all of it.
func _recoil_table(only: String) -> void:
	print("Recoil bench: from the hip; aimed is 60% of every number")
	print("%-22s %-12s %17s  %22s  %22s  %7s" % ["gun", "pattern", "kick 1/5/10 deg",
			"5 rounds up/side deg", "10 rounds up/side deg", "jitter"])
	for id: String in guns():
		if only != "" and not id in only.split(","):
			continue
		var gun := make(id)
		var sums: Array[Vector2] = []
		var total := Vector2.ZERO
		var shots := mini(10, gun.mag_size)
		for shot in range(1, 11):
			if shot <= shots:
				total += gun.recoil_for(shot)
			sums.append(total)
		var five: Vector2 = sums[mini(5, shots) - 1]
		var ten: Vector2 = sums[shots - 1]
		print("%-22s %-12s %5.2f %5.2f %5.2f  %6.1f / %+5.1f (%4.1f m)  %6.1f / %+5.1f (%4.1f m)  %6.2f" % [
				id, gun.recoil_pattern, gun.recoil_for(1).x, gun.recoil_for(5).x, gun.recoil_for(10).x,
				five.x, five.y, tan(deg_to_rad(five.length())) * 20.0,
				ten.x, ten.y, tan(deg_to_rad(ten.length())) * 20.0,
				gun.recoil_side_deg * gun.recoil_jitter])
		gun.free()
