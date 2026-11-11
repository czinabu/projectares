class_name Raid
extends Node3D
## One run of a world: builds the map, spawns everyone, tracks the timer, and
## decides how the raid ends. It knows nothing about any specific world; it only
## uses the WorldDef contract. It also knows nothing about cameras or the HUD,
## so the same class can run on a headless server.

signal ended(result: Dictionary)

## Bots never start closer to the player than this, so a raid does not open with a fight.
const MIN_BOT_SPAWN_DISTANCE := 40.0

var world: WorldDef
var map: Node3D
var player: Actor
var bots: Array[Actor] = []
var exits: Array[ExtractionZone] = []
var time_left := 0.0
var kills := 0
var is_over := false
var rng := RandomNumberGenerator.new()
var _kit: Array[String] = []


## Call after the Raid is in the scene tree. A fixed seed makes it repeatable.
## `p_kit` is the gear the player deploys with; empty means the free scrap kit.
func start(p_world: WorldDef, p_seed: int = -1, p_kit: Array = []) -> void:
	world = p_world
	_kit.assign(p_kit if not p_kit.is_empty() else world.starter_loadout())
	Worlds.current = world
	if p_seed >= 0:
		rng.seed = p_seed
	else:
		rng.randomize()
	time_left = world.raid_duration

	map = world.create_map()
	map.name = "Map"
	add_child(map)
	if map.has_method("bake_navigation"):
		map.call("bake_navigation")

	for node in _map_nodes("exit"):
		var zone := node as ExtractionZone
		if zone:
			zone.hold_time = world.exit_hold_time
			zone.actor_extracted.connect(_on_actor_extracted)
			exits.append(zone)

	for marker in _map_nodes("spawn_cache"):
		var source: String = marker.get_meta("loot_source", "cache")
		_spawn_container(world.roll_loot(source, rng), false, "cache", marker.global_position)

	_spawn_player()
	_spawn_bots()


func _physics_process(delta: float) -> void:
	if is_over or world == null:
		return
	time_left -= delta
	if time_left <= 0.0 and player and not player.is_dead:
		player.kill("storm")


## Exit zone progress for the player, 0..1.
func extract_progress() -> float:
	var best := 0.0
	for zone in exits:
		best = maxf(best, zone.progress_for(player))
	return best


func _spawn_player() -> void:
	var spawns := _map_nodes("spawn_player")
	var at: Vector3 = spawns[rng.randi() % spawns.size()].global_position if not spawns.is_empty() else Vector3.ZERO
	player = Actor.new()
	player.name = "Player"
	player.is_player = true
	player.display_name = "You"
	add_child(player)
	player.global_position = at
	Loadout.equip(player, _kit)
	player.died.connect(_on_actor_died)
	world.on_spawn(player)


func _spawn_bots() -> void:
	var spawns := _map_nodes("spawn_bot")
	var far := spawns.filter(func(m: Node3D) -> bool:
		return m.global_position.distance_to(player.global_position) > MIN_BOT_SPAWN_DISTANCE)
	if not far.is_empty():
		spawns = far
	if spawns.is_empty():
		return
	for i in world.bot_count:
		var marker: Node3D = spawns[i % spawns.size()]
		var bot := Actor.new()
		bot.name = "Bot%d" % i
		add_child(bot)
		bot.global_position = marker.global_position + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1))
		world.equip_bot(bot, rng)
		var brain := BotBrain.new()
		brain.name = "Brain"
		brain.seed_value = rng.randi()
		bot.add_child(brain)
		bot.died.connect(_on_actor_died)
		bots.append(bot)
		world.on_spawn(bot)


func _spawn_container(items: Array, is_bag: bool, label: String, at: Vector3) -> LootContainer:
	var container := LootContainer.new()
	container.setup(items, is_bag, label)
	add_child(container)
	container.global_position = at
	return container


func _on_actor_died(actor: Actor, info: DamageInfo) -> void:
	world.on_death(actor, info)
	var drops := actor.get_drop_items()
	if not drops.is_empty():
		_spawn_container(drops, true, "%s's bag" % actor.display_name, actor.global_position)
	if actor == player:
		_finish("died", info.kind)
		return
	bots.erase(actor)
	if info.source == player:
		kills += 1
		player.notice.emit("Killed %s" % actor.display_name)
	get_tree().create_timer(4.0).timeout.connect(actor.queue_free)


func _on_actor_extracted(actor: Actor) -> void:
	if actor != player or is_over:
		return
	world.on_extract(actor)
	# Everything carried comes home: surviving gear and the backpack.
	Profile.add_to_stash(actor.get_drop_items())
	_finish("extracted", "")


func _finish(outcome: String, cause: String) -> void:
	if is_over:
		return
	is_over = true
	var loot: Array[String] = []
	if outcome == "extracted":
		loot.assign(player.inventory.items)
	var result := {
		"outcome": outcome,
		"cause": cause,
		"world_id": world.id,
		"loot": loot,
		"kept_gear": player.gear_items.filter(func(id: String) -> bool:
			return not ItemDB.has_tag(id, "starter")) if outcome == "extracted" else [],
		"loot_value": ItemDB.total_value(loot),
		"lost": player.get_drop_items() if outcome != "extracted" else [],
		"kills": kills,
		"time_in_raid": world.raid_duration - time_left,
	}
	Profile.record_raid(result)
	ended.emit(result)


func _map_nodes(group: String) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group(group):
		if node is Node3D and map.is_ancestor_of(node):
			out.append(node)
	return out


func _exit_tree() -> void:
	if Worlds.current == world:
		Worlds.current = null
