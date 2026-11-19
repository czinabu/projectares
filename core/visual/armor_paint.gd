class_name ArmorPaint
extends RefCounted
## Paints for armor frames (Caleb's call): cosmetic colour schemes bought
## with scrip at the Tailor, owned for good, and picked per frame look at the
## base's armor stands. A paint is another row of a frame look's colours
## (`ActorSkin.FRAME_STYLES`): plate, second plate, carrier fabric, straps,
## the undersuit and the lit accent. It never changes a frame's stats, its
## shape, its metal, its details or how brightly its accent glows.
##
## The chosen paints ride in the appearance as "paints" (frame look to paint
## id, `Human.sanitize`), so they travel and are checked wherever a look is:
## the spawn data, `NetSession._request_look`, the mirror. A player may only
## wear paints they own (`owned`, from `Economy.unlocked_outfits`, which lists
## "paint:<id>" for each paint item in the stash). Static and safe headless.

## The frame looks a paint can go on (the keys of `ActorSkin.FRAME_STYLES`;
## a test keeps them in step).
const LOOKS: Array[String] = ["scrap", "runner", "trooper", "thermal", "bulwark"]

## Each paint's colours, name and the item that unlocks it. Every colour is
## also held in `SAFE` by `colours`, so a row can never make a body vanish
## into the dark or burn neon.
const PAINTS := {
	"ashen": {"name": "Ashen", "item": "paint_ashen",
		"plate": Color(0.44, 0.44, 0.42), "plate2": Color(0.3, 0.3, 0.29), "fabric": Color(0.36, 0.35, 0.33),
		"strap": Color(0.15, 0.15, 0.15), "suit": Color(0.1, 0.1, 0.1), "accent": Color(0.95, 0.75, 0.45)},
	"desert": {"name": "Desert", "item": "paint_desert",
		"plate": Color(0.56, 0.48, 0.35), "plate2": Color(0.42, 0.35, 0.25), "fabric": Color(0.5, 0.42, 0.3),
		"strap": Color(0.24, 0.2, 0.15), "suit": Color(0.16, 0.14, 0.11), "accent": Color(1.0, 0.72, 0.3)},
	"woodland": {"name": "Woodland", "item": "paint_woodland",
		"plate": Color(0.3, 0.36, 0.24), "plate2": Color(0.2, 0.24, 0.17), "fabric": Color(0.33, 0.35, 0.26),
		"strap": Color(0.14, 0.15, 0.11), "suit": Color(0.08, 0.09, 0.07), "accent": Color(0.75, 1.0, 0.45)},
	"arctic": {"name": "Arctic", "item": "paint_arctic",
		"plate": Color(0.68, 0.7, 0.72), "plate2": Color(0.5, 0.53, 0.56), "fabric": Color(0.56, 0.58, 0.6),
		"strap": Color(0.26, 0.27, 0.29), "suit": Color(0.18, 0.19, 0.21), "accent": Color(0.55, 0.9, 1.0)},
	"night": {"name": "Night Ops", "item": "paint_night",
		"plate": Color(0.16, 0.18, 0.23), "plate2": Color(0.12, 0.13, 0.17), "fabric": Color(0.14, 0.15, 0.18),
		"strap": Color(0.06, 0.06, 0.08), "suit": Color(0.05, 0.05, 0.06), "accent": Color(0.4, 0.7, 1.0)},
	"cobalt": {"name": "Cobalt", "item": "paint_cobalt",
		"plate": Color(0.2, 0.3, 0.48), "plate2": Color(0.14, 0.2, 0.32), "fabric": Color(0.22, 0.26, 0.33),
		"strap": Color(0.1, 0.11, 0.14), "suit": Color(0.07, 0.08, 0.1), "accent": Color(0.8, 0.9, 1.0)},
	"crimson": {"name": "Crimson", "item": "paint_crimson",
		"plate": Color(0.46, 0.19, 0.18), "plate2": Color(0.3, 0.125, 0.115), "fabric": Color(0.24, 0.2, 0.19),
		"strap": Color(0.1, 0.08, 0.08), "suit": Color(0.07, 0.06, 0.06), "accent": Color(1.0, 0.45, 0.3)},
	"hazard": {"name": "Hazard", "item": "paint_hazard",
		"plate": Color(0.62, 0.52, 0.24), "plate2": Color(0.18, 0.18, 0.19), "fabric": Color(0.28, 0.27, 0.25),
		"strap": Color(0.1, 0.1, 0.1), "suit": Color(0.07, 0.07, 0.07), "accent": Color(1.0, 0.55, 0.15)},
	# Earned, never sold (Caleb's call: a few only the hardest content
	# hands out): Relic items, so no shop stocks them and the market never
	# lists them. Ashfront's warlords carry the first, the Heart Warden's
	# vault in Frostline's Engine holds the second, and the Spore Marsh's Grey
	# Matriarch the third.
	"warlord": {"name": "Warlord", "item": "paint_warlord", "earned": true,
		"plate": Color(0.17, 0.16, 0.14), "plate2": Color(0.56, 0.445, 0.215), "fabric": Color(0.14, 0.13, 0.12),
		"strap": Color(0.07, 0.065, 0.06), "suit": Color(0.05, 0.05, 0.045), "accent": Color(1.0, 0.8, 0.38)},
	"warden": {"name": "Heart Warden", "item": "paint_warden", "earned": true,
		"plate": Color(0.62, 0.67, 0.72), "plate2": Color(0.3, 0.38, 0.48), "fabric": Color(0.36, 0.41, 0.47),
		"strap": Color(0.14, 0.16, 0.19), "suit": Color(0.085, 0.1, 0.13), "accent": Color(0.45, 0.95, 1.0)},
	"spore": {"name": "Spore", "item": "paint_spore", "earned": true,
		"plate": Color(0.3, 0.38, 0.26), "plate2": Color(0.2, 0.25, 0.2), "fabric": Color(0.24, 0.27, 0.22),
		"strap": Color(0.1, 0.12, 0.1), "suit": Color(0.07, 0.085, 0.07), "accent": Color(0.5, 1.0, 0.7)},
}

## The colour keys a paint sets, and the range each is held in: [lowest
## value, highest value, most saturation] in HSV. Plates and fabric are never
## near black or white, straps and the suit stay dark but not void, and the
## accent is always a clearly lit colour, never a white-hot or a dead one.
const SAFE := {
	"plate": [0.14, 0.72, 0.62], "plate2": [0.1, 0.6, 0.62], "fabric": [0.12, 0.62, 0.5],
	"strap": [0.05, 0.3, 0.4], "suit": [0.04, 0.24, 0.35], "accent": [0.6, 1.0, 0.85],
}
## The least saturation an accent keeps, so it reads as a colour.
const ACCENT_MIN_SAT := 0.2


static func ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in PAINTS:
		out.append(id)
	return out


## True for a paint only hard content hands out.
static func earned(id: String) -> bool:
	return bool(PAINTS.get(id, {}).get("earned", false))


static func paint_name(id: String) -> String:
	return str(PAINTS[id]["name"]) if PAINTS.has(id) else "Factory"


## The owned-list entry a paint is unlocked under ("paint:<id>").
static func owned_key(id: String) -> String:
	return "paint:" + id


## The paint a paint item unlocks, or "".
static func of_item(item_id: String) -> String:
	for id: String in PAINTS:
		if PAINTS[id]["item"] == item_id:
			return id
	return ""


## The paints `owned` (an owned list from `Economy.unlocked_outfits`) holds,
## in `PAINTS` order.
static func owned_paints(owned: Array) -> Array[String]:
	var out: Array[String] = []
	for id: String in PAINTS:
		if owned_key(id) in owned:
			out.append(id)
	return out


## A valid paint choice from anything: look to paint id, unknown looks and
## paints dropped. With `owned` (not null) only the paints owned are kept.
static func clean(raw: Variant, owned: Variant = null) -> Dictionary:
	var out := {}
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	for look: Variant in raw:
		var paint: Variant = raw[look]
		if typeof(look) != TYPE_STRING or typeof(paint) != TYPE_STRING:
			continue
		if look not in LOOKS or not PAINTS.has(paint):
			continue
		if owned != null and owned_key(paint) not in owned:
			continue
		out[look] = paint
	return out


## A paint's colours, each held in its `SAFE` range.
static func colours(id: String) -> Dictionary:
	var out := {}
	if not PAINTS.has(id):
		return out
	for key: String in SAFE:
		out[key] = safe(key, PAINTS[id][key])
	return out


## `color` held in the range `SAFE` gives `key`.
static func safe(key: String, color: Color) -> Color:
	var limits: Array = SAFE[key]
	var sat := minf(color.s, limits[2])
	if key == "accent":
		sat = maxf(sat, ACCENT_MIN_SAT)
	return Color.from_hsv(color.h, sat, clampf(color.v, limits[0], limits[1]))


## A frame look's style (`ActorSkin.FRAME_STYLES` row) worn in `paint`:
## the paint's colours over it, everything else (metal, finish, glow, the
## details) kept. "" or an unknown paint gives the style back as it is.
static func paint_style(style: Dictionary, paint: String) -> Dictionary:
	if not PAINTS.has(paint):
		return style
	var out := style.duplicate()
	out.merge(colours(paint), true)
	return out
