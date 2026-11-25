extends VBoxContainer
## How your character looks: the choices the phone's Mirror app scrolls
## through (the base's Wardrobe is a mirror that opens it), each a row of
## options, and a line summing the look up. There is no flat customizer: you
## see the look on your own body, in the mirror or the dressing room. The
## choice is cosmetic only. It is kept in the local profile, and online it is
## sent to the server so others see it.

const Human := preload("res://core/visual/human.gd")

## The look changed. The hub's owner saves it and passes it on.
signal changed(appearance: Dictionary)

## The look being edited. Always a valid appearance.
var appearance := {}
## Outfit ids (`Human.outfit_id`) this player owns on top of the starter
## clothes. Only starter and owned outfits are offered.
var owned: Array = []

var _summary: Label

## Every choice, in the order the Mirror app lists them: the body, then the
## head (hairstyle, facial hair, hair colour, eyes, skin, face shape), then
## the suit.
const PICKS: Array[String] = ["build", "style", "facial", "hair", "eyes", "skin", "face", "body", "legs", "feet",
		"top", "bottom", "pattern"]
const TITLES := {"build": "Body", "face": "Face", "style": "Hairstyle", "facial": "Facial hair", "body": "Suit top",
		"legs": "Suit legs", "feet": "Boots"}


func _ready() -> void:
	appearance = Human.player_look(appearance, owned)
	add_theme_constant_override("separation", 4)
	add_child(_label("CHARACTER", 20, Color(1.0, 0.55, 0.25)))
	_summary = _label("", 15, Color(0.85, 0.85, 0.85))
	add_child(_summary)
	_refresh_summary()


## Shows a look without announcing a change, e.g. the one loaded from disk.
func set_appearance(p_appearance: Variant) -> void:
	appearance = Human.player_look(p_appearance, owned)
	_refresh_summary()


## What each picker offers, in order: [[value, label], ...]. "build" and the
## part slots hold names; colour keys hold indexes.
func options_for(key: String) -> Array:
	var out := []
	if key == "build":
		for build in Human.BUILDS:
			out.append([build, Human.BUILD_NAMES[build]])
	elif key in ["style", "facial", "face"]:
		var table: Dictionary = {"style": Human.STYLES, "facial": Human.FACIAL, "face": Human.FACES}[key]
		for id: String in table:
			out.append([id, table[id][0]])
	elif key in Human.SLOTS:
		var outfits: Dictionary = Human.OUTFITS[appearance["build"]]
		for outfit in Human.wearable(appearance["build"], owned):
			out.append([outfit, outfits[outfit]])
	else:
		var names: Array = Human.COLOR_KEYS[key][1]
		for i in names.size():
			out.append([i, names[i]])
	return out


## Every choice, in the order the customizer and the phone's mirror list them.
func pick_keys() -> Array[String]:
	return PICKS.duplicate()


## The name a choice is listed under.
func pick_title(key: String) -> String:
	if TITLES.has(key):
		return TITLES[key]
	return Human.COLOR_KEYS[key][0]


## Where the option worn now sits among those offered: [index, count].
func pick_position(key: String) -> Array:
	var options := options_for(key)
	for i in options.size():
		if options[i][0] == appearance[key]:
			return [i, options.size()]
	return [0, options.size()]


## The label of the option worn now.
func pick_label(key: String) -> String:
	var options := options_for(key)
	return String(options[pick_position(key)[0]][1]) if not options.is_empty() else ""


## Moves one choice `steps` along what is offered, wrapping round, as the
## mirror's arrows and scroll wheel do.
func step(key: String, steps: int) -> void:
	var options := options_for(key)
	if options.is_empty() or steps == 0:
		return
	var at: int = pick_position(key)[0]
	choose(key, options[posmod(at + steps, options.size())][0])


## Where the part worn in a slot comes from: starter clothes, or the stash
## item that unlocked it. "" for choices that are not clothing.
func pick_source(key: String) -> String:
	if key not in Human.SLOTS:
		return ""
	var build: String = appearance["build"]
	var outfit: String = appearance[key]
	if outfit in Human.STARTER[build]:
		return "Starter clothes"
	var wanted := Human.outfit_id(build, outfit)
	for id: Variant in ItemDB.all_ids():
		if ItemDB.has_tag(id, "cosmetic") and wanted in ItemDB.item_stats(id).get("outfits", []):
			return "From your stash: %s" % ItemDB.item_name(id)
	return "Owned"


## Changes one choice, if it is one the pickers offer. Switching build keeps the colours and resets the parts,
## since each build has its own outfits.
func choose(key: String, value: Variant) -> void:
	if not options_for(key).any(func(option: Array) -> bool: return option[0] == value):
		return
	var next := appearance.duplicate()
	next[key] = value
	_apply(Human.player_look(next, owned))


func randomize_look() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var pool := {}
	for build in Human.BUILDS:
		pool[build] = Human.wearable(build, owned)
	var next := Human.random(rng, pool)
	next["style"] = Human.STYLES.keys()[rng.randi() % Human.STYLES.size()]
	var facial: Array = Human.FACIAL.keys()
	next["facial"] = facial[1 + rng.randi() % (facial.size() - 1)] if rng.randf() < 0.3 else "none"
	next["pattern"] = 1 + rng.randi() % (Human.PATTERNS.size() - 1) if rng.randf() < 0.4 else 0
	next["top"] = rng.randi() % Human.CLOTH_COLORS.size()
	next["bottom"] = rng.randi() % Human.CLOTH_COLORS.size()
	_apply(Human.player_look(next, owned))


func _apply(next: Dictionary) -> void:
	if next == appearance:
		return
	appearance = next
	_refresh_summary()
	changed.emit(appearance.duplicate())


func _refresh_summary() -> void:
	var outfits: Dictionary = Human.OUTFITS[appearance["build"]]
	var hair: String = Human.STYLES[appearance["style"]][0].to_lower()
	if appearance["facial"] != "none":
		hair += " and " + String(Human.FACIAL[appearance["facial"]][0]).to_lower()
	_summary.text = "%s: %s, %s suit." % [Human.BUILD_NAMES[appearance["build"]], hair, outfits[appearance["body"]]]


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
