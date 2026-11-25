class_name RigTrail
extends RefCounted
## Thruster trails for flight rigs (DESIGN.md "Cosmetics": "thruster trail
## colours"): the colour a rig's nozzles burn in, one choice for every rig
## worn. A trail is owned for good once its item reaches the stash, bought at
## the Tailor or earned, and picked at the base's rig stands. It never
## changes a rig's stats, how long or wide its flame is or when it burns.
##
## The chosen trail rides in the appearance as "trail" (`Human.sanitize`),
## so it travels and is checked wherever a look is: the spawn data,
## `NetSession._request_look`, the mirror. A player may only wear a trail
## they own (`owned`, from `Economy.unlocked_outfits`, which lists
## "trail:<id>" for each trail item in the stash). Static and safe headless.

## Each trail's colours, name and the item that unlocks it: "glow" the outer
## flame and the light it throws, "core" the hot middle. Both are held in
## `SAFE` by `colours`, so a row can never burn black or blind white.
const TRAILS := {
	"ember": {"name": "Ember", "item": "trail_ember",
		"glow": Color(1.0, 0.5, 0.16), "core": Color(1.0, 0.86, 0.62)},
	"toxic": {"name": "Toxic", "item": "trail_toxic",
		"glow": Color(0.42, 1.0, 0.3), "core": Color(0.9, 1.0, 0.74)},
	"violet": {"name": "Violet", "item": "trail_violet",
		"glow": Color(0.66, 0.36, 1.0), "core": Color(0.95, 0.84, 1.0)},
	"redline": {"name": "Redline", "item": "trail_redline",
		"glow": Color(1.0, 0.2, 0.22), "core": Color(1.0, 0.78, 0.7)},
	# Earned, never sold: Relic items, so no shop stocks them and the market
	# never lists them. The worlds that hand them out name them in their
	# own settings.
	"magma": {"name": "Magma", "item": "trail_magma", "earned": true,
		"glow": Color(1.0, 0.24, 0.06), "core": Color(1.0, 0.9, 0.42)},
	"leviathan": {"name": "Leviathan", "item": "trail_leviathan", "earned": true,
		"glow": Color(1.0, 0.76, 0.3), "core": Color(0.96, 0.98, 1.0)},
}

## The range each colour is held in: [lowest value, least saturation, most
## saturation] in HSV. The glow is always a clear colour; the core is a pale,
## hot one.
const SAFE := {"glow": [0.7, 0.35, 0.95], "core": [0.85, 0.0, 0.62]}

## How the flame is drawn: the factory trail (no choice) and how bright each
## layer burns. The flame is additive and unshaded, so the brightest
## channel of each layer sits at its energy.
const FACTORY := {"glow": Color(0.35, 0.53, 1.0), "core": Color(1.0, 0.87, 0.67)}
const GLOW_ENERGY := 3.4
const CORE_ENERGY := 3.0
const GLOW_ALPHA := 0.55
const CORE_ALPHA := 0.9
## How much less bright a chosen trail burns than the factory flame.
const TRAIL_DIM := 0.7


static func ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in TRAILS:
		out.append(id)
	return out


## True for a trail only hard content hands out.
static func earned(id: String) -> bool:
	return bool(TRAILS.get(id, {}).get("earned", false))


static func trail_name(id: String) -> String:
	return str(TRAILS[id]["name"]) if TRAILS.has(id) else "Factory"


## The owned-list entry a trail is unlocked under ("trail:<id>").
static func owned_key(id: String) -> String:
	return "trail:" + id


## The trail a trail item unlocks, or "".
static func of_item(item_id: String) -> String:
	for id: String in TRAILS:
		if TRAILS[id]["item"] == item_id:
			return id
	return ""


## The trails `owned` (an owned list from `Economy.unlocked_outfits`) holds,
## in `TRAILS` order.
static func owned_trails(owned: Array) -> Array[String]:
	var out: Array[String] = []
	for id: String in TRAILS:
		if owned_key(id) in owned:
			out.append(id)
	return out


## A valid trail choice from anything, or "" (the factory flame). With
## `owned` (not null) only a trail owned is kept.
static func clean(raw: Variant, owned: Variant = null) -> String:
	if typeof(raw) != TYPE_STRING or not TRAILS.has(raw):
		return ""
	if owned != null and owned_key(raw) not in owned:
		return ""
	return raw


## A trail's colours, each held in its `SAFE` range; the factory ones for ""
## or an unknown trail.
static func colours(id: String) -> Dictionary:
	if not TRAILS.has(id):
		return FACTORY.duplicate()
	return {"glow": safe("glow", TRAILS[id]["glow"]), "core": safe("core", TRAILS[id]["core"])}


## `color` held in the range `SAFE` gives `key`.
static func safe(key: String, color: Color) -> Color:
	var limits: Array = SAFE[key]
	return Color.from_hsv(color.h, clampf(color.s, limits[1], limits[2]), clampf(color.v, limits[0], 1.0))


## What a nozzle's flame is drawn in for trail `id` (`Vfx.nozzle_flame`):
## "outer" and "core" the two cones (over-bright, for the glow), "light" the
## light it throws.
static func flame_colours(id: String) -> Dictionary:
	var c := colours(id)
	var glow: Color = c["glow"]
	var core: Color = c["core"]
	# A trail burns a little less bright than the factory flame, so its
	# colour reads through the glow instead of blooming white.
	var dim := 1.0 if not TRAILS.has(id) else TRAIL_DIM
	return {"outer": _lit(glow, GLOW_ENERGY * dim, GLOW_ALPHA), "core": _lit(core, CORE_ENERGY * dim * dim, CORE_ALPHA),
			"light": glow.lightened(0.25)}


## `color` scaled so its brightest channel is `energy`.
static func _lit(color: Color, energy: float, alpha: float) -> Color:
	var top := maxf(maxf(color.r, color.g), maxf(color.b, 0.001))
	var k := energy / top
	return Color(color.r * k, color.g * k, color.b * k, alpha)
