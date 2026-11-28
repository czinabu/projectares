extends RefCounted
## Checks for the suit's styles: every outfit's top, legs and boots are a
## cut and a cloth of their own, not only a colour (`Human.SUIT_STYLES`,
## `character.gdshader` `suit_style` and `suit_weave`), the trim colour is
## its own choice, a style fits either build and stays on under armor.

const Human := preload("res://core/visual/human.gd")
const CharacterPanel := preload("res://core/ui/character_panel.gd")


static func run(t: Node) -> void:
	print("Suit styles")
	var shader: Shader = load("res://assets/shaders/character.gdshader")
	# Every outfit has a style, and within a build no two look alike.
	var every := true
	var distinct := true
	for build in Human.BUILDS:
		var seen := {}
		for outfit: String in Human.OUTFITS[build]:
			every = every and Human.SUIT_STYLES.has(outfit)
			var style: Array = Human.SUIT_STYLES.get(outfit, [])
			if style.size() == 3:
				var key := "%d" % style[0]
				distinct = distinct and not seen.has(key)
				seen[key] = true
	t.check(every, "every outfit of either build has a suit style")
	t.check(distinct, "within a build, every outfit is a cut of its own")
	var drawn := true
	for outfit: String in Human.SUIT_STYLES:
		var style: Array = Human.SUIT_STYLES[outfit]
		drawn = drawn and (style[0] == 0 or shader.code.contains("cut == %d)" % style[0]))
		drawn = drawn and (style[1] == 0 or shader.code.contains("kind == %d)" % style[1]))
	t.check(drawn and shader.code.contains("cut == %d)" % Human.BOOT_CUT),
			"the shader draws every cut and cloth a style names, and the boots")
	t.check(shader.code.contains("uniform int suit_cut") and shader.code.contains("uniform int suit_material")
			and shader.code.contains("uniform vec3 suit_second"), "the shader takes a cut, a cloth and a second colour")

	# The suit a part wears names its cut, cloth and second colour; colour
	# stays its own choice.
	var look := Human.sanitize({"build": "m", "body": "Casual_Hoodie", "legs": "Punk", "feet": "Swat", "top": 3,
			"trim": 2})
	var top := Human.suit_for(look, "body")
	var legs := Human.suit_for(look, "legs")
	var feet := Human.suit_for(look, "feet")
	t.check(top["cut"] == Human.SUIT_STYLES["Casual_Hoodie"][0] and legs["cut"] == Human.SUIT_STYLES["Punk"][0]
			and feet["cut"] == Human.BOOT_CUT, "the top, legs and boots each wear their own outfit's cut")
	t.check(top["material"] == Human.SUIT_STYLES["Casual_Hoodie"][1] and legs["material"] == Human.SUIT_STYLES["Punk"][1],
			"each part is made of its own outfit's cloth")
	t.check(top["color"] == Human.CLOTH_COLORS[3] and top["second"] != top["color"],
			"a dye colours the style, and its panels are a shade of that colour")
	t.check(top["trim"] == Human.TRIM_COLORS[2] and legs["trim"] == Human.TRIM_COLORS[2],
			"a chosen trim colour reaches every part")
	var own_trim := Human.sanitize({"build": "m", "body": "Punk"})
	t.check(Human.suit_for(own_trim, "body")["trim"] == Human.SUITS["Punk"][1], "trim \"As made\" keeps the outfit's own")
	t.check(Human.sanitize({"trim": 99})["trim"] == Human.TRIM_COLORS.size() - 1 and Human.sanitize({"trim": "red"})["trim"] == 0,
			"a trim colour from outside is clamped")
	# A second colour always differs from the suit, even at black and white.
	var shows := true
	for cloth in [Color(0.02, 0.02, 0.02), Color(0.95, 0.95, 0.95), Color(0.4, 0.2, 0.1)]:
		for contrast in [-0.5, 0.5]:
			var second := Human.second_shade(cloth, contrast)
			shows = shows and absf(second.get_luminance() - cloth.get_luminance()) > 0.01
	t.check(shows, "a style's panels show on a black, a white and a dyed suit")
	# A style sits on either build: the marks come from each build's bones.
	var marks_m := Human.body_marks("m")
	var marks_f := Human.body_marks("f")
	t.check(marks_m.has("suit_trunk") and marks_m.has("suit_arm") and marks_m.has("suit_leg")
			and marks_m["suit_trunk"] != marks_f["suit_trunk"] and marks_m["suit_arm"] != marks_f["suit_arm"],
			"each build has its own marks for a style to sit on")
	var sane := true
	for marks: Dictionary in [marks_m, marks_f]:
		var trunk: Vector4 = marks["suit_trunk"]
		var arm: Vector4 = marks["suit_arm"]
		var leg: Vector4 = marks["suit_leg"]
		sane = sane and trunk.x < trunk.y and trunk.y < trunk.z and trunk.w < arm.z and arm.z < arm.w
		sane = sane and leg.z < leg.y and leg.y < trunk.x
	t.check(sane, "the marks run feet to head and shoulder to wrist")

	# The Mirror offers the trim colour, after the suit's colours.
	var panel := CharacterPanel.new()
	t.add_child(panel)
	var keys := panel.pick_keys()
	t.check(keys.has("trim") and keys.find("trim") > keys.find("bottom") and panel.pick_title("trim") == "Trim colour"
			and panel.options_for("trim").size() == Human.TRIM_COLORS.size(), "the Mirror lists the trim colour")
	t.check(panel.pick_title("body") == "Top style" and panel.pick_title("legs") == "Legs style",
			"the Mirror calls the top and legs styles")
	panel.choose("trim", 3)
	t.check(panel.appearance["trim"] == 3, "the trim colour can be chosen")
	panel.free()

	# Built, each part's material carries its style and its build's marks.
	Look.enabled = true
	var built: Dictionary = Look.character("raider", Human.sanitize({"build": "f", "body": "Witch", "legs": "Medieval",
			"feet": "SciFi"}))
	if not built.is_empty():
		var by_slot := {}
		for mat: ShaderMaterial in built["materials"]:
			if mat.has_meta("suit_slot"):
				by_slot[mat.get_meta("suit_slot")] = mat
		t.check(by_slot.has("body") and by_slot["body"].get_shader_parameter("suit_cut") == Human.SUIT_STYLES["Witch"][0]
				and by_slot.has("legs") and by_slot["legs"].get_shader_parameter("suit_material") == Human.SUIT_STYLES["Medieval"][1]
				and by_slot.has("feet") and by_slot["feet"].get_shader_parameter("suit_cut") == Human.BOOT_CUT,
				"each part's material wears its own style")
		t.check(by_slot.has("body") and by_slot["body"].get_shader_parameter("suit_trunk") == marks_f["suit_trunk"],
				"a part's material carries its build's marks")
		(built["model"] as Node).free()
	else:
		t.check(false, "a styled look builds into a model")

	# Under armor the style stays and its panels follow the paint.
	var raid := Raid.new()
	t.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 31)
	Look.set_appearance(raid.player, Human.sanitize({"build": "m", "body": "King", "legs": "King", "feet": "King"}))
	await t.frames(4)
	var skin := raid.player.get_node("Skin")
	var suited: Array = skin._materials.filter(func(mat: ShaderMaterial) -> bool: return mat.has_meta("own_suit"))
	Loadout.wear_frame(raid.player, "frame_trooper")
	await t.frames(8)
	t.check(not suited.is_empty() and suited.all(_keeps_style),
			"under a frame the suit keeps its style, its panels a shade of the paint")
	Loadout.wear_frame(raid.player, "")
	await t.frames(8)
	t.check(suited.all(func(mat: ShaderMaterial) -> bool:
			return mat.get_shader_parameter("suit_second") == mat.get_meta("own_suit")["second"]),
			"taking the frame off gives the style its own second colour back")
	raid.queue_free()
	await t.frames(2)


static func _keeps_style(mat: ShaderMaterial) -> bool:
	var own: Dictionary = mat.get_meta("own_suit")
	return mat.get_shader_parameter("suit_cut") == own["cut"] and mat.get_shader_parameter("suit_second") \
			== Human.second_shade(mat.get_shader_parameter("suit_color"), own["contrast"])
