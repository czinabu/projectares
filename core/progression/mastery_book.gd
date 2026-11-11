extends RefCounted
## One player's mastery: XP per track and the variant picked for each track.
## Lives on `Profile`. It is never touched by death, which is the point:
## gear is lost, mastery is kept.

const MasteryDB := preload("res://core/progression/mastery_db.gd")

## Track id -> total XP.
var xp := {}
## Track id -> picked variant id. A missing track uses the stock item.
var picks := {}


func clear() -> void:
	xp.clear()
	picks.clear()


func xp_for(track: String) -> int:
	return xp.get(track, 0)


func level(track: String) -> int:
	return MasteryDB.level_for_xp(xp_for(track))


## Adds XP and returns how many levels it gained.
func add_xp(track: String, amount: int) -> int:
	if not MasteryDB.has_track(track) or amount <= 0:
		return 0
	var before := level(track)
	xp[track] = xp_for(track) + amount
	return level(track) - before


func is_unlocked(track: String, variant_id: String) -> bool:
	var v := MasteryDB.variant(track, variant_id)
	return not v.is_empty() and level(track) >= int(v.level)


## Picks a variant, or "" for stock. Returns false if it is not unlocked.
func pick(track: String, variant_id: String) -> bool:
	if variant_id == "":
		picks.erase(track)
		return true
	if not is_unlocked(track, variant_id):
		return false
	picks[track] = variant_id
	return true


func picked(track: String) -> String:
	var id: String = picks.get(track, "")
	return id if is_unlocked(track, id) else ""


## Every picked, unlocked variant: what `Raid.start` takes.
func active_picks() -> Dictionary:
	var out := {}
	for track: String in picks:
		var id := picked(track)
		if id != "":
			out[track] = id
	return out


func to_dict() -> Dictionary:
	return {"xp": xp.duplicate(), "picks": picks.duplicate()}


func load_dict(data: Variant) -> void:
	clear()
	if typeof(data) != TYPE_DICTIONARY:
		return
	var saved_xp: Variant = data.get("xp", {})
	if typeof(saved_xp) == TYPE_DICTIONARY:
		for track: Variant in saved_xp:
			if typeof(track) == TYPE_STRING and MasteryDB.has_track(track):
				xp[track] = maxi(0, int(saved_xp[track]))
	var saved_picks: Variant = data.get("picks", {})
	if typeof(saved_picks) == TYPE_DICTIONARY:
		for track: Variant in saved_picks:
			if typeof(track) == TYPE_STRING and typeof(saved_picks[track]) == TYPE_STRING:
				pick(track, saved_picks[track])
