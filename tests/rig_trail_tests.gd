extends RefCounted
## Checks for thruster trails (`RigTrail`): the colour every flight rig's
## flames burn in, bought at the Tailor or earned, owned for good, picked at
## the base's rig stands and worn in the appearance. Called from the test
## runner (`-- --only rig_trail` runs just these).

const Human := preload("res://core/visual/human.gd")
const Economy := preload("res://core/economy/economy.gd")
const Market := preload("res://core/economy/market.gd")
const Vfx := preload("res://core/visual/vfx.gd")


static func run(t: Node) -> void:
	print("Thruster trails")
	_data(t)
	_items(t)
	_appearance(t)
	_flame(t)
	await _stands(t)
	await _worn(t)


## Every trail's colours are held in their safe range, and the factory
## flame is the blue one rigs always had.
static func _data(t: Node) -> void:
	var whole := true
	var in_range := true
	for id in RigTrail.ids():
		for key: String in ["glow", "core"]:
			whole = whole and RigTrail.TRAILS[id].has(key)
			var raw: Color = RigTrail.TRAILS[id][key]
			in_range = in_range and RigTrail.safe(key, raw).is_equal_approx(Color.from_hsv(raw.h, raw.s, raw.v))
		whole = whole and RigTrail.TRAILS[id].has("name") and RigTrail.TRAILS[id].has("item")
	t.check(whole and in_range, "every trail has a glow and a core, and both sit in their safe range")
	var black := RigTrail.safe("glow", Color.BLACK)
	var grey := RigTrail.safe("glow", Color(0.6, 0.6, 0.6))
	var neon := RigTrail.safe("core", Color(0.0, 1.0, 0.0))
	t.check(black.v >= 0.7 - 0.001 and grey.s >= 0.35 - 0.001 and neon.s <= 0.62 + 0.001,
			"a trail can never burn black, grey or a neon core")
	var factory := RigTrail.flame_colours("")
	var outer: Color = factory["outer"]
	t.check(outer.b > outer.g and outer.g > outer.r and is_equal_approx(maxf(outer.b, 0.0), RigTrail.GLOW_ENERGY)
			and RigTrail.flame_colours("nope") == factory, "no trail (or an unknown one) burns the factory blue")
	var ember: Color = RigTrail.flame_colours("ember")["outer"]
	t.check(ember.r > ember.b and is_equal_approx(ember.r, RigTrail.GLOW_ENERGY * RigTrail.TRAIL_DIM),
			"a trail's flame burns its colour, a little less bright so the colour reads")


## A trail is an item like a paint: the Tailor sells the plain ones, the
## earned ones are Relic loot no shop or trader board touches.
static func _items(t: Node) -> void:
	var matched := true
	var shop_ok := true
	var earned_ok := true
	var earned := 0
	for id in RigTrail.ids():
		var item: String = RigTrail.TRAILS[id]["item"]
		matched = matched and ItemDB.has_tag(item, "trail") and ItemDB.has_tag(item, "cosmetic") \
				and ItemDB.item_stats(item).get("trail") == id and RigTrail.of_item(item) == id
		matched = matched and Loadout.slot_of(item) == ""
		if RigTrail.earned(id):
			earned += 1
			earned_ok = earned_ok and not Economy.is_shop_item(item) and not Market.tradeable(item) \
					and ItemDB.item_rarity(item) == ItemDB.Rarity.RELIC and not ItemDB.has_tag(item, "vendor")
		else:
			shop_ok = shop_ok and Economy.for_sale("tailor", item) and Economy.buy_price(item) > 0
	t.check(matched, "every trail has its item, a cosmetic that fits no loadout slot, so it never goes on a raid")
	t.check(shop_ok, "the Tailor sells every plain trail")
	t.check(earned >= 2 and earned_ok, "the earned trails are never sold, never traded")
	var owned := Economy.unlocked_outfits(["trail_ember", "paint_desert", "rifle_carbine"])
	t.check(RigTrail.owned_key("ember") in owned and ArmorPaint.owned_key("desert") in owned
			and RigTrail.owned_trails(owned) == ["ember"], "a trail in the stash unlocks it beside the paints")


## The chosen trail rides in the appearance, checked like a paint.
static func _appearance(t: Node) -> void:
	var raw := {"build": "m", "trail": "ember"}
	t.check(Human.sanitize(raw).get("trail") == "ember", "a look keeps a valid trail")
	t.check(not Human.sanitize({"build": "m", "trail": "nope"}).has("trail")
			and not Human.sanitize({"build": "m", "trail": 3}).has("trail")
			and not Human.sanitize({"build": "m"}).has("trail"), "an unknown trail, or none, carries none")
	var owned := Economy.unlocked_outfits(["trail_ember"])
	t.check(Human.player_look(raw, owned).get("trail") == "ember", "a player wears a trail they own")
	t.check(not Human.player_look({"build": "m", "trail": "magma"}, owned).has("trail"),
			"and not one they do not own")
	t.check(Look.clean_appearance(raw, []) == Human.player_look(raw, []) and not Look.clean_appearance(raw, []).has("trail"),
			"the server's check (`clean_appearance`) holds the trail to the stash")


## A nozzle flame is built in the trail's colours, its light too.
static func _flame(t: Node) -> void:
	var flame := Vfx.nozzle_flame(0.05, 0.5, true, "toxic")
	var colours := RigTrail.flame_colours("toxic")
	var got: Array[Color] = []
	var light: OmniLight3D = null
	for child in flame.get_children():
		if child is MeshInstance3D:
			got.append(((child as MeshInstance3D).mesh.surface_get_material(0) as StandardMaterial3D).albedo_color)
		elif child is OmniLight3D:
			light = child
	t.check(got.size() == 2 and got[0].is_equal_approx(colours["outer"]) and got[1].is_equal_approx(colours["core"])
			and light != null and light.light_color.is_equal_approx(colours["light"]),
			"a nozzle flame burns in the trail's glow and core, and lights the ground in its glow")
	flame.free()


## The rig stands burn in the trail worn, and a swatch on each turns through
## the trails owned.
static func _stands(t: Node) -> void:
	var base := HomeBase.new()
	base.trail = "ember"
	base.show_gear(["jetpack_mk1", "trail_ember", "trail_toxic"], {"rig": "jetpack_mk1"})
	t.add_child(base)
	await t.frames(2)
	var stand := _rig_stand(base)
	var swatch := stand.get_node_or_null("TrailSwatch") as HomeBase.TrailSwatch if stand else null
	var ember: Color = RigTrail.colours("ember")["glow"]
	t.check(swatch != null and _glows(stand.get_node("Model"), ember),
			"a rig stand's nozzles glow in the trail worn, with a trail swatch beside it")
	if swatch == null:
		base.queue_free()
		await t.frames(1)
		return
	t.check(base.owned_trails() == ["ember", "toxic"] and base.next_trail() == "toxic",
			"the swatch turns through the trails owned")
	t.check(swatch.get_prompt().begins_with("[F] Trail: Ember (next Toxic)"), "the swatch names the trail worn and the next")
	var asked := []
	base.trail_requested.connect(func(trail: String) -> void: asked.append(trail))
	t._face_display(base.player, swatch)
	await t.frames(2)
	t.check(base.player.find_interactable() == swatch, "the swatch can be walked up to and looked at")
	await t._use(base.player)
	t.check(asked == ["toxic"], "using it asks for the next trail")
	base.show_trail("toxic")
	await t.frames(1)
	var again := _rig_stand(base)
	t.check(again != null and _glows(again.get_node("Model"), RigTrail.colours("toxic")["glow"])
			and (again.get_node("TrailSwatch/TrailName") as Label3D).text == "Toxic",
			"a new trail relights the stand and its swatch")
	base.show_trail("toxic")
	t.check(base.next_trail() == "", "after the last trail owned comes the factory flame")
	base.queue_free()
	await t.frames(1)
	var poor := HomeBase.new()
	poor.show_gear(["jetpack_mk1"], {"rig": "jetpack_mk1"})
	t.add_child(poor)
	await t.frames(2)
	var poor_stand := _rig_stand(poor)
	var poor_swatch: HomeBase.TrailSwatch = poor_stand.get_node_or_null("TrailSwatch") if poor_stand else null
	var heard := [0]
	poor.trail_requested.connect(func(_t: String) -> void: heard[0] += 1)
	if poor_swatch:
		poor_swatch.interact(poor.player)
	t.check(poor_swatch != null and heard[0] == 0 and poor_swatch.get_prompt().contains("Tailor"),
			"with no trails owned the swatch points to the Tailor and does nothing")
	poor.queue_free()
	await t.frames(1)


static func _rig_stand(base: HomeBase) -> HomeBase.Display:
	for display in base.displays:
		if display.kind == "rig_stand" and is_instance_valid(display) and not display.is_queued_for_deletion():
			return display
	return null


## True if `root` has a lit surface in `color`.
static func _glows(root: Node, color: Color) -> bool:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i) as StandardMaterial3D
			if mat == null:
				mat = (node as MeshInstance3D).get_surface_override_material(i) as StandardMaterial3D
			if mat != null and mat.albedo_color.is_equal_approx(color):
				return true
	return false


## Worn, every rig's nozzles burn in the trail chosen; a body with none burns
## the factory blue.
static func _worn(t: Node) -> void:
	Look.enabled = true
	var raid := Raid.new()
	t.add_child(raid)
	raid.start(Worlds.get_world("rift"), 321)
	await t.frames(4)
	var p := raid.player
	Look.set_appearance(p, {"build": "m", "head": "Casual_2", "body": "Casual_2", "legs": "Casual_2", "feet": "Casual_2",
			"trail": "magma"})
	await t.frames(6)
	var skin := p.get_node_or_null("Skin")
	var flames: Array = skin.get("_flames") if skin else []
	var outer: Color = RigTrail.flame_colours("magma")["outer"]
	t.check(not flames.is_empty() and flames.all(func(f: Node3D) -> bool: return _burns(f, outer)),
			"a worn rig's nozzles burn in the trail the look names")
	t.check(skin != null and skin.call("rig_trail") == "magma", "the body knows its trail")
	var bot: Actor = null
	for b in raid.bots:
		if is_instance_valid(b) and b.flight.enabled and b.has_node("Skin"):
			bot = b
	if bot != null:
		var theirs: Array = bot.get_node("Skin").get("_flames")
		var factory: Color = RigTrail.flame_colours("")["outer"]
		t.check(theirs.all(func(f: Node3D) -> bool: return _burns(f, factory)), "a body with no trail burns the factory blue")
	Look.enabled = false
	raid.queue_free()
	await t.frames(1)


static func _burns(flame: Node3D, color: Color) -> bool:
	for child in flame.get_children():
		if child is MeshInstance3D:
			var mat := (child as MeshInstance3D).mesh.surface_get_material(0) as StandardMaterial3D
			return mat != null and mat.albedo_color.is_equal_approx(color)
	return false
