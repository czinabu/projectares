extends Node
## Lives in a Raid and watches one actor. It applies the mastery variants the
## actor deployed with and counts the mastery XP they earn, by gear type.
## No input, camera or Profile access: the Raid hands the result to whoever
## owns the profile, so this works the same on a headless server.

const MasteryDB := preload("res://core/progression/mastery_db.gd")

## XP per point of damage dealt with a weapon or ability.
var xp_per_damage := 0.5
## Extra XP when that hit was a kill.
var xp_per_kill := 40
## XP for each ability use.
var xp_per_ability_use := 20
## XP per point of damage taken while wearing a frame.
var xp_per_damage_taken := 0.4
## Given to the track of every piece of gear you extract with.
var xp_extract_bonus := 60

var actor: Actor
## Track id -> XP earned this raid, as a float until it is reported.
var earned := {}


## Applies `picks` (track -> variant id) to the actor's gear and starts tracking.
## Call after `Loadout.equip`.
func setup(p_actor: Actor, picks: Dictionary) -> void:
	actor = p_actor
	apply_variants(actor, picks)
	actor.hit_confirmed.connect(_on_hit_confirmed)
	actor.health.damaged.connect(_on_damaged)
	actor.ability.activated.connect(_on_ability_used)


static func apply_variants(target: Actor, picks: Dictionary) -> void:
	for weapon in target.weapons:
		var mods := _mods_for(weapon.item_id, picks)
		if not mods.is_empty():
			MasteryDB.apply_mods(weapon, mods)
	if target.ability.enabled:
		var mods := _mods_for(target.ability.item_id, picks)
		if not mods.is_empty():
			MasteryDB.apply_mods(target.ability, mods)
	var frame := _frame_item(target)
	var mods := _mods_for(frame, picks)
	if mods.has("armor"):
		target.health.set_armor(MasteryDB.modded(target.health.max_armor, mods.armor))
	if mods.has("speed"):
		target.walk_speed = MasteryDB.modded(target.walk_speed, mods.speed)
		target.sprint_speed = MasteryDB.modded(target.sprint_speed, mods.speed)
	if mods.has("heat"):
		target.flight.heat_per_sec = MasteryDB.modded(target.flight.heat_per_sec, mods.heat)
		target.flight.burst_heat = MasteryDB.modded(target.flight.burst_heat, mods.heat)


static func _mods_for(item_id: String, picks: Dictionary) -> Dictionary:
	var track := MasteryDB.track_for_item(item_id)
	if track == "" or not picks.has(track):
		return {}
	return MasteryDB.variant(track, picks[track]).get("mods", {})


static func _frame_item(target: Actor) -> String:
	for id in target.gear_items:
		if ItemDB.has_tag(id, "armor"):
			return id
	return ""


func add(track: String, amount: float) -> void:
	if track != "" and amount > 0.0:
		earned[track] = earned.get(track, 0.0) + amount


## The XP to bank, by track, as whole numbers. Extracting adds a bonus to
## every piece of gear you bring home. Dying keeps everything earned so far.
func report(extracted: bool) -> Dictionary:
	if extracted and actor:
		for id in actor.gear_items:
			add(MasteryDB.track_for_item(id), xp_extract_bonus)
	var out := {}
	for track: String in earned:
		var whole := roundi(earned[track])
		if whole > 0:
			out[track] = whole
	return out


func _on_hit_confirmed(_target: Actor, info: DamageInfo, lethal: bool) -> void:
	var track := ""
	if info.kind == "pulse":
		track = MasteryDB.track_for_item(actor.ability.item_id)
	elif info.kind in ["bullet", "melee", "slam"]:
		var weapon := actor.get_active_weapon()
		if weapon:
			track = MasteryDB.track_for_item(weapon.item_id)
	add(track, info.amount * xp_per_damage + (xp_per_kill if lethal else 0))


func _on_damaged(info: DamageInfo) -> void:
	add(MasteryDB.track_for_item(_frame_item(actor)), info.amount * xp_per_damage_taken)


func _on_ability_used(_effect: String) -> void:
	add(MasteryDB.track_for_item(actor.ability.item_id), xp_per_ability_use)
