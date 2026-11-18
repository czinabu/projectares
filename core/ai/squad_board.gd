class_name SquadBoard
extends RefCounted
## What a group of bots shares (DESIGN.md "Enemy senses and squads"): who
## is hunting each person, who went to look at a noise, who is working round
## a person's flank and which cover is taken. Static claims with an expiry,
## like the attack slots (`BotBrain.take_slot`), so every rule here is cheap,
## has no per-tick cost of its own and can be checked on its own.
##
## Claims are keyed by an instance id (the person, the noise's source) and
## held by a brain's instance id until a physics frame. A claim that runs
## out is simply forgotten the next time anyone asks.

## Hunters: bots allowed to leave their ground to close on, chase or search
## for one person, by the person's instance id: {brain id: frame it ends}.
static var _hunters := {}
## Bots sent to look at one source's noise: {source id: {brain id: frame}}.
static var _looking := {}
## The one bot working round each person's flank: {person id: [brain id, frame]}.
static var _flankers := {}
## Cover spots in use: {cell key: [brain id, frame]}.
static var _cover := {}

## How close two bots may take cover to one another.
const COVER_CELL := 2.5


static func _tps() -> int:
	return Engine.physics_ticks_per_second


## Asks for one of `cap` hunter places on the person `key` for `me` until
## `now + hold` seconds; true while it holds one (and refreshes it).
static func hunt(key: int, me: int, cap: int, now: int, hold: float) -> bool:
	return _claim(_hunters, key, me, cap, now, hold)


## Lets go of the hunter place `me` holds on `key`.
static func stop_hunt(key: int, me: int) -> void:
	var held: Dictionary = _hunters.get(key, {})
	held.erase(me)


## How many hunt the person `key` at frame `now`.
static func hunters(key: int, now: int) -> int:
	return _count(_hunters, key, now)


## Asks to be one of `cap` bots that go to look at a noise made by `source`.
static func look(source: int, me: int, cap: int, now: int, hold: float) -> bool:
	return _claim(_looking, source, me, cap, now, hold)


## Asks to be the one bot working round the flank of the person `key`.
static func flank(key: int, me: int, now: int, hold: float) -> bool:
	var held: Array = _flankers.get(key, [])
	if held.is_empty() or held[0] == me or held[1] <= now:
		_flankers[key] = [me, now + int(hold * _tps())]
		return true
	return false


static func stop_flank(key: int, me: int) -> void:
	var held: Array = _flankers.get(key, [])
	if not held.is_empty() and held[0] == me:
		_flankers.erase(key)


## True when no other bot holds cover within `COVER_CELL` of `spot`.
static func cover_free(spot: Vector3, me: int, now: int) -> bool:
	var key := _cell(spot)
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var held: Array = _cover.get(key + Vector2i(dx, dz), [])
			if not held.is_empty() and held[0] != me and held[1] > now:
				return false
	return true


## Takes the cover at `spot` for `hold` seconds.
static func take_cover(spot: Vector3, me: int, now: int, hold: float) -> void:
	if _cover.size() > 2048:
		for key: Vector2i in _cover.keys():
			if _cover[key][1] <= now:
				_cover.erase(key)
	_cover[_cell(spot)] = [me, now + int(hold * _tps())]


static func clear() -> void:
	_hunters.clear()
	_looking.clear()
	_flankers.clear()
	_cover.clear()


static func _cell(spot: Vector3) -> Vector2i:
	return Vector2i(floori(spot.x / COVER_CELL), floori(spot.z / COVER_CELL))


static func _claim(table: Dictionary, key: int, me: int, cap: int, now: int, hold: float) -> bool:
	var held: Dictionary = table.get(key, {})
	if held.is_empty():
		held = {}
		table[key] = held
		if table.size() > 512:
			_prune(table, now)
	for id: int in held.keys():
		if held[id] <= now:
			held.erase(id)
	if not held.has(me) and held.size() >= cap:
		return false
	held[me] = now + int(hold * _tps())
	return true


static func _count(table: Dictionary, key: int, now: int) -> int:
	var count := 0
	var held: Dictionary = table.get(key, {})
	for id: int in held:
		if held[id] > now:
			count += 1
	return count


static func _prune(table: Dictionary, now: int) -> void:
	for key: int in table.keys():
		if (table[key] as Dictionary).values().all(func(until: int) -> bool: return until <= now):
			table.erase(key)
