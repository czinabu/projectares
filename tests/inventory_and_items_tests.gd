extends RefCounted
## The `inventory_and_items` checks. The test runner finds this file by itself and calls
## `run(t)`.


static func run(t: Node) -> void:
	print("Inventory and items")
	var inv := Inventory.new()
	inv.capacity = 2
	t.check(inv.add_item("scrap_metal") and inv.add_item("power_cell"), "items fit up to capacity")
	t.check(not inv.add_item("medkit"), "a full backpack refuses more")
	t.check(inv.total_value() == 135, "backpack value adds up")
	t.check(inv.remove_item("scrap_metal") and not inv.has_item("scrap_metal"), "items can be removed")
	inv.free()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var loot := Worlds.get_world("ashfront").roll_loot("rooftop", rng)
	t.check(loot.size() >= 2 and loot.all(func(id: String) -> bool: return ItemDB.has_item(id)),
			"world loot rolls are valid items")
