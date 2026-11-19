extends RefCounted
## Checks for armor paints (`ArmorPaint`): cosmetic colour schemes for armor
## frames, bought at the Tailor or earned, owned for good, picked at the
## base's armor stands and worn in the appearance. Called from the test
## runner (`-- --only armor_paint` runs just these).

const SkinScript := preload("res://core/visual/actor_skin.gd")
const Human := preload("res://core/visual/human.gd")
const Economy := preload("res://core/economy/economy.gd")
const Market := preload("res://core/economy/market.gd")

const COLOUR_KEYS: Array[String] = ["plate", "plate2", "fabric", "strap", "suit", "accent"]


static func run(t: Node) -> void:
	print("Armor paints")
	_data(t)
	_items(t)
	_appearance(t)
	_built(t)
	await _stands(t)
	await _worn(t)
	_earned(t)


## Every paint is a row of a frame look's colours, held in its safe range,
## and goes on every frame look there is.
static func _data(t: Node) -> void:
	var looks: Array[String] = []
	for look: String in SkinScript.FRAME_STYLES:
		looks.append(look)
	looks.sort()
	var listed := ArmorPaint.LOOKS.duplicate()
	listed.sort()
	t.check(listed == looks, "a paint can go on every frame look, and only those")
	var whole := true
	var in_range := true
	for id in ArmorPaint.ids():
		for key in COLOUR_KEYS:
			whole = whole and ArmorPaint.PAINTS[id].has(key)
			var raw: Color = ArmorPaint.PAINTS[id][key]
			# Written inside its range already: the clamp is a backstop, not a
			# second colour nobody chose.
			in_range = in_range and ArmorPaint.safe(key, raw).is_equal_approx(Color.from_hsv(raw.h, raw.s, raw.v))
	t.check(whole, "every paint names its plates, carrier, straps, undersuit and accent")
	t.check(in_range, "every paint is written inside the safe colour range")
	var black := ArmorPaint.safe("plate", Color.BLACK)
	var neon := ArmorPaint.safe("accent", Color(0.0, 1.0, 0.0))
	var dead := ArmorPaint.safe("accent", Color(0.05, 0.05, 0.05))
	t.check(black.v >= 0.14 and neon.s <= 0.85 + 0.001 and dead.v >= 0.6 and dead.s >= ArmorPaint.ACCENT_MIN_SAT - 0.001,
			"no paint can make plates vanish into black, or an accent go neon or dead")
	var style: Dictionary = SkinScript.FRAME_STYLES["bulwark"]
	var painted := ArmorPaint.paint_style(style, "desert")
	var kept := true
	for key: String in style:
		if key not in COLOUR_KEYS:
			kept = kept and painted[key] == style[key]
	t.check(kept and painted["plate"] == ArmorPaint.colours("desert")["plate"] and painted.get("glow") == style.get("glow"),
			"a paint changes only the colours: metal, finish, glow and details stay the frame's")
	t.check(ArmorPaint.paint_style(style, "") == style and ArmorPaint.paint_style(style, "nope") == style,
			"no paint, or an unknown one, leaves the frame's own colours")


## A paint is an item like clothing: the Tailor sells the plain ones, the
## earned ones are Relic loot no shop or trader board touches.
static func _items(t: Node) -> void:
	var matched := true
	var shop_ok := true
	var earned_ok := true
	var earned := 0
	for id in ArmorPaint.ids():
		var item: String = ArmorPaint.PAINTS[id]["item"]
		matched = matched and ItemDB.has_tag(item, "paint") and ItemDB.has_tag(item, "cosmetic") \
				and ItemDB.item_stats(item).get("paint") == id and ArmorPaint.of_item(item) == id
		matched = matched and Loadout.slot_of(item) == ""
		if ArmorPaint.earned(id):
			earned += 1
			earned_ok = earned_ok and not Economy.is_shop_item(item) and not Market.tradeable(item) \
					and ItemDB.item_rarity(item) == ItemDB.Rarity.RELIC and not ItemDB.has_tag(item, "vendor")
		else:
			shop_ok = shop_ok and Economy.for_sale("tailor", item) and Economy.buy_price(item) > 0
	t.check(matched, "every paint has its item, a cosmetic that fits no loadout slot, so it never goes on a raid")
	t.check(shop_ok, "the Tailor sells every plain paint")
	t.check(earned >= 2 and earned_ok, "a few paints are earned only: never sold, never traded")
	var owned := Economy.unlocked_outfits(["paint_desert", "outfit_punk", "rifle_carbine"])
	t.check(ArmorPaint.owned_key("desert") in owned and "m_Punk" in owned and ArmorPaint.owned_paints(owned) == ["desert"],
			"a paint in the stash unlocks it beside the clothing")


## The chosen paints ride in the appearance, checked like clothing.
static func _appearance(t: Node) -> void:
	var raw := {"build": "m", "paints": {"trooper": "desert", "runner": "night", "bogus": "desert", "bulwark": "nope"}}
	var clean := Human.sanitize(raw)
	t.check(clean.get("paints") == {"trooper": "desert", "runner": "night"},
			"a look keeps valid paints and drops unknown looks and paints")
	t.check(not Human.sanitize({"build": "m"}).has("paints"), "a look with no paints carries none")
	var owned := Economy.unlocked_outfits(["paint_desert"])
	var worn := Human.player_look(raw, owned)
	t.check(worn.get("paints") == {"trooper": "desert"}, "a player wears only the paints they own")
	t.check(not Human.player_look(raw, []).has("paints"), "with none owned, no paint goes on")
	t.check(Look.clean_appearance(raw, owned) == worn, "the server's check (`clean_appearance`) holds paints to the stash")


## Built in a paint, a frame wears the paint's colours; plain, its own.
static func _built(t: Node) -> void:
	var plain := SkinScript.build_frame("frame_trooper")
	var painted := SkinScript.build_frame("frame_trooper", "desert")
	var desert: Color = ArmorPaint.colours("desert")["plate"]
	var own: Color = SkinScript.FRAME_STYLES["trooper"]["plate"]
	t.check(_wears(painted, desert) and not _wears(painted, own) and _wears(plain, own),
			"a frame built in a paint wears its plate colour, and plain its own")
	t.check(_wears(SkinScript.build_pad("frame_bulwark", 1.0, "crimson"), ArmorPaint.colours("crimson")["plate"]),
			"the limb pieces take the paint too")
	for node in [plain, painted]:
		node.free()


## True if `root` has a surface in `color`.
static func _wears(root: Node, color: Color) -> bool:
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	for node in meshes:
		var mesh := (node as MeshInstance3D).mesh
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i) as StandardMaterial3D
			if mat == null:
				mat = (node as MeshInstance3D).get_surface_override_material(i) as StandardMaterial3D
			if mat != null and mat.albedo_color.is_equal_approx(color):
				return true
	return false


## The armor stands show the paint each frame look wears, and a swatch on
## each turns through the paints owned.
static func _stands(t: Node) -> void:
	var base := HomeBase.new()
	base.paints = {"trooper": "night"}
	base.show_gear(["frame_trooper", "paint_desert", "paint_night"], {"frame": "frame_trooper"})
	t.add_child(base)
	await t.frames(2)
	var stand: HomeBase.Display = null
	for display in base.displays:
		if display.kind == "armor_stand" and display.item_id == "frame_trooper":
			stand = display
	var swatch := stand.get_node_or_null("PaintSwatch") as HomeBase.PaintSwatch if stand else null
	t.check(swatch != null and _wears(stand.get_node("Model"), ArmorPaint.colours("night")["plate"]),
			"an armor stand wears its frame in the paint chosen, with a paint swatch beside it")
	if swatch == null:
		base.queue_free()
		return
	t.check(base.owned_paints() == ["desert", "night"] and base.next_paint("trooper") == ""
			and base.next_paint("runner") == "desert", "the swatch turns through the paints owned, round to the frame's own")
	t.check(swatch.get_prompt().begins_with("[F] Paint: Night Ops"), "the swatch names the paint worn and the next")
	var asked := []
	base.paint_requested.connect(func(look: String, paint: String) -> void: asked.append([look, paint]))
	t._face_display(base.player, swatch)
	await t.frames(2)
	t.check(base.player.find_interactable() == swatch, "the swatch can be walked up to and looked at")
	await t._use(base.player)
	t.check(asked == [["trooper", ""]], "using it asks for the next paint")
	base.show_paints({"trooper": "desert"})
	await t.frames(1)
	var again: HomeBase.Display = null
	for display in base.displays:
		if display.kind == "armor_stand" and display.item_id == "frame_trooper":
			again = display
	t.check(again != null and _wears(again.get_node("Model"), ArmorPaint.colours("desert")["plate"])
			and (again.get_node("PaintSwatch/PaintName") as Label3D).text == "Desert",
			"a new paint repaints the stand and its swatch")
	base.queue_free()
	await t.frames(1)
	var poor := HomeBase.new()
	poor.show_gear(["frame_trooper"], {"frame": "frame_trooper"})
	t.add_child(poor)
	await t.frames(2)
	var poor_swatch: HomeBase.PaintSwatch = null
	for display in poor.displays:
		if display.kind == "armor_stand":
			poor_swatch = display.get_node_or_null("PaintSwatch")
	var heard := [0]
	poor.paint_requested.connect(func(_l: String, _p: String) -> void: heard[0] += 1)
	if poor_swatch:
		poor_swatch.interact(poor.player)
	t.check(poor_swatch != null and heard[0] == 0 and poor_swatch.get_prompt().contains("Tailor"),
			"with no paints owned the swatch points to the Tailor and does nothing")
	poor.queue_free()
	await t.frames(1)


## Worn, the frame and the undersuit take the paint, the same body in both
## views (nothing first-person only).
static func _worn(t: Node) -> void:
	Look.enabled = true
	var raid := Raid.new()
	t.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 319, ["frame_trooper"] as Array[String])
	await t.frames(4)
	var p := raid.player
	Look.set_appearance(p, {"build": "m", "head": "Casual_2", "body": "Casual_2", "legs": "Casual_2", "feet": "Casual_2",
			"paints": {"trooper": "cobalt"}})
	await t.frames(6)
	var skin := p.get_node_or_null("Skin")
	var skeleton: Skeleton3D = skin.get("_skeleton") if skin else null
	var frame: Node = null
	if skeleton:
		for node in skeleton.get_children():
			if node is BoneAttachment3D and node.name == "Frame":
				frame = node
	var cobalt := ArmorPaint.colours("cobalt")
	t.check(frame != null and _wears(frame, cobalt["plate"]), "a worn frame wears the paint its look was given")
	var mats: Array = skin.get("_materials") if skin else []
	t.check(mats.any(func(m: ShaderMaterial) -> bool: return m.get_shader_parameter("suit_color") == cobalt["suit"]),
			"the undersuit takes the paint's suit colour")
	Loadout.wear_frame(p, "frame_runner")
	await t.frames(3)
	frame = null
	for node in skeleton.get_children():
		# Its name may have gone to the old carrier on its way out: the
		# carrier is the piece on the chest.
		if node is BoneAttachment3D and (node as BoneAttachment3D).bone_name == "Chest" and not node.is_queued_for_deletion():
			frame = node
	t.check(frame != null and _wears(frame, SkinScript.FRAME_STYLES["runner"]["plate"]),
			"another frame's look keeps its own colours until it is painted")
	Look.enabled = false
	raid.queue_free()
	await t.frames(1)


## The earned paints come from the hardest fights: Ashfront's warlords and
## the Heart Warden's vault.
static func _earned(t: Node) -> void:
	var ashfront := Worlds.get_world("ashfront")
	t.check(ashfront.warlord_paint == "paint_warlord" and ashfront.warlord_paint_chance > 0.0
			and ArmorPaint.earned(ArmorPaint.of_item(ashfront.warlord_paint)),
			"Ashfront's warlords may carry the Warlord paint")
	var frostline := Worlds.get_world("frostline")
	var found := false
	var rng := RandomNumberGenerator.new()
	for i in 200:
		rng.seed = i
		if "paint_warden" in frostline.roll_vault("warden", rng):
			found = true
			break
	t.check(found, "the Heart Warden's vault may hold the Heart Warden paint")
	var plain_worlds := true
	for id: String in ["frostline", "plaza"]:
		var world: WorldDef = Worlds.get_world(id)
		if world != null:
			plain_worlds = plain_worlds and world.warlord_paint == ""
	t.check(plain_worlds, "no other world's warlords carry an earned paint")
