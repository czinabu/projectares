class_name LootContainer
extends Interactable
## A world cache, or the bag a dead actor drops (`is_bag`), or the scrip
## pile one drops where `WorldDef.death_drops_scrip` (`pile`): scrip worth
## what they lost, grabbed by running over it (`Raid._tick_piles`), with a
## bonus item from their pack in `items`.
##
## A container labelled `RACK_LABEL` is a power rack (`PowerArmory`): using
## it scans its heavy (power) weapon into your watch's heavy chamber instead
## of your pack, to be summoned from the watch.

const RACK_LABEL := "Power rack"
## A scrip pile's glow, and a bounty pile's.
const PILE_COLOR := Color(1.0, 0.72, 0.2)
const PILE_BOUNTY_COLOR := Color(1.0, 0.35, 0.15)

## The contents changed (someone looted it).
signal changed
## An actor picked up the scrip that was in here. The `Raid` scrip it.
signal scrip_taken(actor: Actor, amount: int)
## An actor took items out of here (the `Raid` counts it for contracts).
signal looted_by(actor: Actor)

var items: Array[String] = []
var is_bag := false
var label := "Cache"
## Server only: rounds left in guns put down on a rack, as
## {item id: [[mag, reserve], ...]}, last put down first.
var ammo := {}
## Scrip lying in here with the items: what a dead player was carrying.
var scrip := 0
## Server only: a share kept for one player (a keeper's vault, `Raid`), by
## their owner key, and their name for whoever else tries it. Empty for a
## cache anyone may loot. A share goes once it is emptied.
var reserved := ""
var reserved_name := ""
## Server only: why nobody may loot it yet (a hive while its keeper stands,
## `Raid._seal_hives`), or empty.
var sealed := ""
## A scrip pile (see above). `bounty` is the share of `scrip` that was the
## dead player's bounty: a pile with one burns brighter.
var pile := false
var bounty := 0

var _mesh: MeshInstance3D


func setup(p_items: Array, p_is_bag: bool, p_label: String) -> void:
	items.assign(p_items)
	is_bag = p_is_bag
	label = p_label


## Makes this a scrip pile holding `p_scrip`, `p_bounty` of it a bounty.
func make_pile(p_scrip: int, p_bounty: int) -> void:
	pile = true
	is_bag = true
	scrip = p_scrip
	bounty = p_bounty


func _ready() -> void:
	add_to_group("loot_containers")
	if pile:
		add_to_group("scrip_piles")
	var size := Vector3(0.7, 0.5, 0.7) if is_bag else Vector3(1.1, 0.8, 0.8)
	if pile:
		size = Vector3(0.8, 0.25, 0.8)
	# A cache is a crate you bump into and duck behind. A bag or a pile lies
	# where someone fell and is stepped over, never caught on.
	if not is_bag and not pile:
		collision_layer |= Actor.LAYER_WORLD
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = size.y * 0.5
	add_child(col)

	var box := BoxMesh.new()
	box.size = size
	_mesh = MeshInstance3D.new()
	_mesh.mesh = box
	_mesh.position.y = size.y * 0.5
	add_child(_mesh)
	_refresh_color()


func is_rack() -> bool:
	return label == RACK_LABEL


func get_prompt() -> String:
	if sealed != "":
		return "%s: %s" % [label, sealed]
	if is_rack():
		# Prompts are only shown to the local player.
		var raid := Raid.of(self)
		var prompt := _rack_prompt(raid.player if raid != null else null)
		if prompt != "":
			return prompt
	if pile:
		if items.is_empty():
			return "%d scrip: run over it" % scrip if scrip > 0 else label
		return "[F] Take %s%s" % [ItemDB.item_name(items[0]), ", %d scrip" % scrip if scrip > 0 else ""]
	# A bag is cleared away once it is emptied, so one that is still here
	# holds something, if only scrip.
	if items.is_empty() and is_bag:
		return "[F] Loot %s" % label
	if items.is_empty():
		return "%s (empty)" % label
	return "[F] Loot %s (%d)" % [label, items.size()]


func interact(actor: Actor) -> void:
	if sealed != "":
		actor.notice.emit(sealed)
		return
	if reserved != "":
		var raid := Raid.of(self)
		var state := raid.state_for(actor) if raid != null else null
		if state == null or state.owner != reserved:
			actor.notice.emit("This share is %s's" % reserved_name)
			return
	if is_rack() and _rack_swap(actor):
		return
	if scrip > 0:
		var got := scrip
		scrip = 0
		bounty = 0
		scrip_taken.emit(actor, got)
	var taken: Array[String] = []
	while not items.is_empty() and not actor.inventory.is_full():
		var id: String = items.pop_front()
		actor.inventory.add_item(id)
		taken.append(id)
	if not taken.is_empty():
		actor.looted.emit(taken)
		looted_by.emit(actor)
		actor.notice.emit("Looted " + ItemDB.summarize(taken))
		if actor.is_player:
			Sfx.play("loot")
	elif not items.is_empty():
		actor.notice.emit("Backpack full")
	changed.emit()
	if items.is_empty() and scrip <= 0 and (is_bag or reserved != ""):
		queue_free()
	else:
		_refresh_color()


## A body ran over the pile: the scrip is theirs (`scrip_taken`), and the
## bonus item too if their pack has room. Authority only (`Raid._tick_piles`).
func grab(actor: Actor) -> void:
	if not pile or (scrip <= 0 and items.is_empty()):
		return
	if not items.is_empty() and not actor.inventory.is_full():
		interact(actor)
		return
	if scrip > 0:
		var got := scrip
		scrip = 0
		bounty = 0
		scrip_taken.emit(actor, got)
		changed.emit()
		if items.is_empty():
			queue_free()


## The power weapon a rack would hand you, or "" if it holds none.
func rack_offer() -> String:
	for id in items:
		if ItemDB.has_tag(id, "power"):
			return id
	return ""


func _rack_prompt(actor: Actor) -> String:
	var offer := rack_offer()
	if offer == "":
		return ""
	var index := Loadout.power_index(actor) if actor != null else -1
	if index < 0:
		return "[F] Scan %s into your watch" % ItemDB.item_name(offer)
	return "[F] Scan %s into your watch, leave your %s" % [ItemDB.item_name(offer), actor.weapons[index].display_name]


## Scans the rack's power weapon into the actor's heavy chamber on the
## watch, to be summoned from there. A power weapon they already carried goes on the rack with the
## shots it had. Returns false if the rack had nothing to hand over.
func _rack_swap(actor: Actor) -> bool:
	var offer := rack_offer()
	if offer == "":
		return false
	items.erase(offer)
	var rounds: Array = [-1, -1]
	var stack: Array = ammo.get(offer, [])
	if not stack.is_empty():
		rounds = stack.pop_back()
		if stack.is_empty():
			ammo.erase(offer)
	var given := Loadout.set_power(actor, offer, rounds[0], rounds[1], false)
	if given.id != "" and not given.spent:
		items.append(given.id)
		if not ammo.has(given.id):
			ammo[given.id] = []
		ammo[given.id].append([given.mag, given.reserve])
	actor.looted.emit([offer] as Array[String])
	actor.notice.emit("Scanned %s into your watch" % ItemDB.item_name(offer))
	if actor.is_player:
		Sfx.play("loot")
	changed.emit()
	if items.is_empty() and (is_bag or reserved != ""):
		queue_free()
	else:
		_refresh_color()
	return true


## Replaces the contents, for a client showing what the server reports.
func set_items(p_items: Array, p_scrip: int = -1) -> void:
	items.assign(p_items)
	if p_scrip >= 0:
		scrip = p_scrip
		if scrip <= 0:
			bounty = 0
	_refresh_color()


## Colored by the best item inside, so rare loot is visible from a distance.
func _refresh_color() -> void:
	if _mesh == null:
		return
	# A pile's heap (dressed by `Look`) goes with its scrip.
	var heap := get_node_or_null("Crate") as Node3D
	if pile and heap != null:
		heap.visible = scrip > 0
	var mat := StandardMaterial3D.new()
	if pile and items.is_empty():
		# Scrip alone: amber, a bounty's red-gold brighter.
		var amber := PILE_BOUNTY_COLOR if bounty > 0 else PILE_COLOR
		mat.albedo_color = amber
		mat.emission_enabled = true
		mat.emission = amber
		mat.emission_energy_multiplier = 1.5 if bounty > 0 else 0.9
	elif items.is_empty():
		mat.albedo_color = Color(0.2, 0.2, 0.2)
	else:
		var best := 0
		for id in items:
			best = maxi(best, ItemDB.item_rarity(id))
		var color: Color = ItemDB.RARITY_COLORS[best]
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 0.6
	_mesh.material_override = mat
