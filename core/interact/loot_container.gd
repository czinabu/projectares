class_name LootContainer
extends Interactable
## A world cache, or the bag a dead actor drops (`is_bag`).

## The contents changed (someone looted it).
signal changed
## An actor picked up the scrip that was in here. The `Raid` credits it.
signal scrip_taken(actor: Actor, amount: int)

var items: Array[String] = []
var is_bag := false
var label := "Cache"
## Scrip lying in here with the items: what a dead player was carrying.
var scrip := 0

var _mesh: MeshInstance3D


func setup(p_items: Array, p_is_bag: bool, p_label: String) -> void:
	items.assign(p_items)
	is_bag = p_is_bag
	label = p_label


func _ready() -> void:
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


func get_prompt() -> String:
	# A bag is cleared away once it is emptied, so one that is still here
	# holds something, if only scrip.
	if items.is_empty() and is_bag:
		return "[F] Loot %s" % label
	if items.is_empty():
		return "%s (empty)" % label
	return "[F] Loot %s (%d)" % [label, items.size()]


func interact(actor: Actor) -> void:
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
