extends RefCounted
## Where power weapons turn up. One lives in each `Raid` and runs on the
## authority only; the racks it puts down are ordinary `LootContainer`s
## labelled `LootContainer.RACK_LABEL`, so they reach clients like any
## cache.
##
## Power weapons are items tagged "power": a few shots, no reloads from the
## stash, never stored. Taking one off a rack swaps it into your primary
## slot and leaves your own gun on the rack, so you choose. They turn up:
##   - on a rack at every strongpoint, restocked on a timer the war speeds up,
##   - on a rack beside every supply pod,
##   - now and then on a rack beside a cache that refills, likelier in a hot war,
##   - where someone carrying one died, with the shots they had left.
## `WorldDef.power_weapon_rate` scales all of it; 0 turns it off.
##
## Load with `preload("res://core/war/power_armory.gd")`.

## Seconds before an emptied strongpoint rack is stocked again while the
## world is quiet. An all-out war makes it three times faster.
var restock_time := 150.0
var war_restock_speedup := 2.0
## Chance a refilling cache gets a rack beside it: at a quiet world, and
## added on top in an all-out war.
var cache_chance := 0.04
var cache_war_chance := 0.22
## How far from the strongpoint's centre, cache or pod the rack stands.
var rack_offset := Vector3(2.4, 0.0, 1.2)

var raid: Raid
## One entry per strongpoint: {"point", "rack", "restock_in"}.
var _sites: Array[Dictionary] = []


## Every power weapon there is, in registration order.
static func all_power_ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in ItemDB.all_ids():
		if ItemDB.has_tag(id, "power"):
			out.append(id)
	return out


func enabled() -> bool:
	return raid != null and raid.world != null and raid.world.power_weapon_rate > 0.0 \
			and not raid.world.safe_zone


## Puts an empty rack at every strongpoint. The first stock comes after
## half a restock.
func setup(p_raid: Raid) -> void:
	raid = p_raid
	_sites.clear()
	if not enabled():
		return
	for point in raid.strongpoints:
		var rack := _spawn_rack([], point.global_position + rack_offset, false)
		_sites.append({"point": point, "rack": rack, "restock_in": restock_time * 0.5})


func tick(delta: float) -> void:
	if not enabled():
		return
	var speed := raid.world.power_weapon_rate * (1.0 + war_restock_speedup * raid.war.intensity)
	for site in _sites:
		var rack: LootContainer = site.rack
		if not is_instance_valid(rack) or _has_power(rack):
			continue
		site.restock_in -= delta * speed
		if site.restock_in > 0.0:
			continue
		site.restock_in = restock_time
		var id := roll()
		var stocked := rack.items.duplicate()
		stocked.append(id)
		rack.set_items(stocked)
		rack.changed.emit()
		raid.war_feed.emit("A %s is racked at %s" % [ItemDB.item_name(id), site.point.title])


## A supply pod came down at `at`: it always brings a power weapon.
func on_supply_pod(at: Vector3) -> LootContainer:
	if not enabled():
		return null
	return _spawn_rack([roll()], at + rack_offset, true)


## A cache at `at` refilled. Sometimes a rack comes with it.
func on_cache_refilled(at: Vector3) -> LootContainer:
	if not enabled():
		return null
	var chance := (cache_chance + cache_war_chance * raid.war.intensity) * raid.world.power_weapon_rate
	if raid.rng.randf() >= chance:
		return null
	return _spawn_rack([roll()], at + rack_offset, true)


## Takes the power weapons out of a dead actor's `drops` (they never go in a
## bag or a backpack) and leaves any with shots left on a rack where they
## fell. Safe to call on a client: it only filters there.
func on_death(actor: Actor, drops: Array[String]) -> void:
	var power: Array[String] = []
	for id in drops:
		if ItemDB.has_tag(id, "power"):
			power.append(id)
	if power.is_empty():
		return
	for id in power:
		drops.erase(id)
	if raid == null or raid.mode == Raid.Mode.CLIENT:
		return
	var rack_items: Array[String] = []
	var ammo := {}
	for weapon in actor.weapons:
		var gun := weapon as Gun
		if gun == null or not gun.item_id in power or gun.is_spent():
			continue
		rack_items.append(gun.item_id)
		if not ammo.has(gun.item_id):
			ammo[gun.item_id] = []
		ammo[gun.item_id].append([gun.ammo_in_mag, gun.reserve_ammo])
	if rack_items.is_empty():
		return
	var rack := _spawn_rack(rack_items, actor.global_position + Vector3(0.8, 0.0, 0.0), true)
	rack.ammo = ammo


## A power weapon id, weighted equally for now.
func roll() -> String:
	var ids := all_power_ids()
	if ids.is_empty():
		return ""
	return ids[raid.rng.randi() % ids.size()]


func _has_power(rack: LootContainer) -> bool:
	for id in rack.items:
		if ItemDB.has_tag(id, "power"):
			return true
	return false


## A rack at `at`. A temporary one (`temporary`) goes when it is emptied or
## after the world's bag lifetime, like a dead player's bag.
func _spawn_rack(items: Array, at: Vector3, temporary: bool) -> LootContainer:
	var rack := raid.spawn_container(items, temporary, LootContainer.RACK_LABEL, raid._stand(at))
	if temporary and raid.is_inside_tree():
		raid.get_tree().create_timer(raid.world.bag_lifetime, false, true).timeout.connect(func() -> void:
			if is_instance_valid(rack):
				rack.queue_free())
	return rack
