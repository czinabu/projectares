class_name LifeLog
extends RefCounted
## Where lives end (DESIGN.md "Challenge and balance data"): the authority's
## `Raid` writes one line for every life a player finishes, died or left,
## so a world's challenge is tuned from what happened in play rather than
## guessed. A line says where (the spot and the risk zone), how (the cause,
## what killed them, how many bots were after them), how long the life ran,
## what it carried and banked, and the world's state at the time (war, storm).
##
## Nothing here is shown to anyone and nothing reads it back in play: the
## report (`tests/life_report.tscn`) turns the files into rates and a map.
## Lines are JSON, one a life, appended to one file a world a day under
## `directory` (left empty, nothing is written: the tests, and any raid that
## `main.gd` did not set up). An append is not a save: a crash loses at most
## the line being written, never the ones before it.

## Where the files go. `main.gd` sets it for a solo game and every server.
static var directory := ""

## The last lines recorded, newest last, kept whether or not anything is
## written, so a test can read what a life left behind.
var recent: Array[Dictionary] = []
const RECENT_KEPT := 64


## Records one finished life and writes it out where `directory` is set.
func record(entry: Dictionary) -> void:
	recent.append(entry)
	if recent.size() > RECENT_KEPT:
		recent.pop_front()
	if directory == "":
		return
	var world_id := str(entry.get("world", "world"))
	var day := Time.get_date_string_from_unix_time(int(entry.get("time", Time.get_unix_time_from_system())))
	var path := directory.path_join("%s-%s.jsonl" % [world_id, day])
	if not DirAccess.dir_exists_absolute(directory):
		DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(path, FileAccess.READ_WRITE) if FileAccess.file_exists(path) \
			else FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.seek_end()
	file.store_line(JSON.stringify(entry))
	file.close()


## What killed someone, as a short kind the report can group by: "player",
## "raider", "warlord", "boss", "<faction>:<kind>" for an army bot (its
## "kind" meta, "soldier" by default), "self" or the damage kind ("hazard",
## "cold", "fall") when nobody did it.
static func killer_kind(raid: Raid, victim: Actor, info: DamageInfo) -> String:
	var source := info.source as Actor if info != null and info.source is Actor else null
	if source == null or not is_instance_valid(source):
		return info.kind if info != null and info.kind != "" else "unknown"
	if source == victim:
		return "self"
	if raid.state_for(source) != null:
		return "player"
	if raid.is_raider(source):
		return "raider"
	if raid.warlords.has(source):
		return "warlord"
	for boss: Dictionary in raid._bosses:
		if boss.bot == source:
			return "boss"
	var faction := source.faction if source.faction != "" else "bot"
	return "%s:%s" % [faction, str(source.get_meta("kind", "soldier"))]


## How many bots had `victim` as their target: the measure of being
## converged on (`BotBrain.target`). Once a life, so a scan is fine.
static func hunters_of(victim: Actor) -> int:
	if victim == null or not victim.is_inside_tree():
		return 0
	var count := 0
	for node: Variant in victim.get_tree().get_nodes_in_group("actors"):
		if not is_instance_valid(node) or not node is Actor:
			continue
		var other := node as Actor
		if other == victim or other.is_dead or not Raid.together(victim, other):
			continue
		var brain := other.get_node_or_null("Brain") as BotBrain
		if brain != null and brain.target == victim:
			count += 1
	return count


## Reads every line of the files under `dir` whose name starts with
## `world_id` ("" for every world). For the report and the tests.
static func read_all(dir: String, world_id := "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var listing := DirAccess.open(dir)
	if listing == null:
		return out
	for name in listing.get_files():
		if not name.ends_with(".jsonl") or (world_id != "" and not name.begins_with(world_id + "-")):
			continue
		var file := FileAccess.open(dir.path_join(name), FileAccess.READ)
		if file == null:
			continue
		while not file.eof_reached():
			var line := file.get_line().strip_edges()
			if line == "":
				continue
			var parsed: Variant = JSON.parse_string(line)
			if parsed is Dictionary:
				out.append(parsed)
	return out
