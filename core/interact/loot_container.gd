class_name LootContainer
extends Interactable
## A world cache, or the bag a dead actor drops (`is_bag`).
##
## A container labelled `RACK_LABEL` is a power rack (`PowerArmory`): using
## it puts its power weapon in your power slot instead of your pack.

const RACK_LABEL := "Power rack"

## The contents changed (someone looted it).
signal changed
## An actor picked up the scrip that was in here. The `Raid` scrip it.
signal scrip_taken(actor: Actor, amount: int)

var items: Array[String] = []
var is_bag := false
var label := "Cache"
## Server only: rounds left in guns put down on a rack, as
## {item id: [[mag, reserve], ...]}, last put down first.
var ammo := {}
## Scrip lying in here with the items: what a dead player was carrying.
var scrip := 0

var _mesh: MeshInstance3D


func setup(p_items: Array, p_is_bag: bool, p_label: String) -> void:
	items.assign(p_items)
	is_bag = p_is_bag
	label = p_label


func _ready() -> void:
	add_to_group("loot_containers")
	var size := Vector3(0.7, 0.5, 0.7) if is_bag else Vector3(1.1, 0.8, 0.8)
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
	if is_rack():
		# Prompts are only shown to the local player.
		var raid := Raid.of(self)
		var prompt := _rack_prompt(raid.player if raid != null else null)
		if prompt != "":
			return prompt
	# A bag is cleared away once it is emptied, so one that is still here
	# holds something, if only scrip.
	if items.is_empty() and is_bag:
		return "[F] Loot %s" % label
	if items.is_empty():
		return "%s (empty)" % label
	return "[F] Loot %s (%d)" % [label, items.size()]


func interact(actor: Actor) -> void:
	if is_rack() and _rack_swap(actor):
		return
	if scrip > 0:
		var got := scrip
		scrip = 0
		scrip_taken.emit(actor, got)
	var taken: Array[String] = []
	while not items.is_empty() and not actor.inventory.is_full():
		var id: String = items.pop_front()
		actor.inventory.add_item(id)
		taken.append(id)
	if not taken.is_empty():
		actor.notice.emit("Looted " + ItemDB.summarize(taken))
		if actor.is_player:
			Sfx.play("loot")
	elif not items.is_empty():
		actor.notice.emit("Backpack full")
	changed.emit()
	if items.is_empty() and is_bag:
		queue_free()
	else:
		_refresh_color()


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
		return "[F] Take %s" % ItemDB.item_name(offer)
	return "[F] Take %s, leave your %s" % [ItemDB.item_name(offer), actor.weapons[index].display_name]


## Puts the rack's power weapon in the actor's power slot (key 4) and in
## hand. A power weapon they already carried goes on the rack with the
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
	var given := Loadout.set_power(actor, offer, rounds[0], rounds[1])
	if given.id != "" and not given.spent:
		items.append(given.id)
		if not ammo.has(given.id):
			ammo[given.id] = []
		ammo[given.id].append([given.mag, given.reserve])
	actor.notice.emit("Took %s" % ItemDB.item_name(offer))
	if actor.is_player:
		Sfx.play("loot")
	changed.emit()
	if items.is_empty() and is_bag:
		queue_free()
	else:
		_refresh_color()
	return true


## Replaces the contents, for a client showing what the server reports.
func set_items(p_items: Array) -> void:
	items.assign(p_items)
	_refresh_color()


## Colored by the best item inside, so rare loot is visible from a distance.
func _refresh_color() -> void:
	if _mesh == null:
		return
	var mat := StandardMaterial3D.new()
	if items.is_empty():
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
