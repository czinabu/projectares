extends RefCounted
## The racing league (DESIGN.md section 9, "League and rivals"): static
## rules on a small dictionary kept on the account (`Profile.racing` solo,
## `StashService.Account.racing` online, in the snapshot), like `Contracts`.
## Only live races move it: the `Race` sends each racer's finish as a result
## and `apply` works out the new state, the same everywhere.
##
## A rating climbs by beating people and AI racers and slips a little by
## losing to them (`points_for`), never below the floor of the league you
## are in: no relegation. Each league has its cast of named rivals
## (`RIVALS`), AI racers who fill a grid of that league, and the last of
## them is the league's top rival: to move up, your rating must reach the
## next league and you must have beaten the top rival in a race. Until then
## the rating waits at the gate.
##
## A race pays a little scrip by place (`scrip_for`), at most `DAILY_CAP` a
## day, so racing never out-earns the warzone.
##
## The rivals talk on the race radio (`line`): what they say depends on the
## moment (`EVENTS`), their manner, and how you have done against them, so
## one you keep beating changes their tune.
##
## Load with `const RaceLeague := preload("res://core/race/race_league.gd")`.

## The leagues, lowest first: the rating that reaches each and how good its
## AI racers are (`RaceDriver` skill).
const LEAGUES: Array[Dictionary] = [
	{"id": "rookie", "name": "Rookie", "from": 0, "ai": 0.12},
	{"id": "club", "name": "Club", "from": 60, "ai": 0.32},
	{"id": "pro", "name": "Pro", "from": 160, "ai": 0.52},
	{"id": "elite", "name": "Elite", "from": 300, "ai": 0.72},
	{"id": "champion", "name": "Champion", "from": 480, "ai": 0.9},
]
## Rating for each racer finished ahead of, and lost for each one behind.
const BEAT_POINTS := 3
const LOSE_POINTS := 1
## The most racers a result may name (a grid's size, `Race.GRID_SIZE`).
const MAX_FIELD := 8
## Scrip for first, second and third, and for any other finish.
const PLACE_SCRIP: Array[int] = [30, 20, 12]
const FINISH_SCRIP := 5
## The most racing pays in a day.
const DAILY_CAP := 120
## Results kept for the phone's Racing app.
const RECENT := 5
## A rival you are this many wins up on is humbled and says so.
const HUMBLED_AFTER := 3

## The named rivals: league, skill above the league's own, manner and the
## machine they favour ("wheels" or "hover"). The last of each league is
## its top rival.
const RIVALS := {
	"pip": {"name": "Pip Lacey", "league": 0, "edge": 0.04, "style": "joker", "machine": "hover"},
	"haro": {"name": "Haro Venn", "league": 0, "edge": 0.08, "style": "clean", "machine": "wheels"},
	"moss": {"name": "Moss Teller", "league": 0, "edge": 0.14, "style": "cocky", "machine": "wheels"},
	"kit": {"name": "Kit Sarno", "league": 1, "edge": 0.04, "style": "blocker", "machine": "wheels"},
	"edda": {"name": "Edda Pike", "league": 1, "edge": 0.08, "style": "veteran", "machine": "hover"},
	"rafe": {"name": "Rafe Dorran", "league": 1, "edge": 0.14, "style": "cocky", "machine": "hover"},
	"lune": {"name": "Lune Achebe", "league": 2, "edge": 0.04, "style": "clean", "machine": "hover"},
	"gus": {"name": "Gus Marlowe", "league": 2, "edge": 0.08, "style": "joker", "machine": "wheels"},
	"nadia": {"name": "Nadia Strell", "league": 2, "edge": 0.14, "style": "veteran", "machine": "wheels"},
	"corvin": {"name": "Corvin Sault", "league": 3, "edge": 0.04, "style": "blocker", "machine": "hover"},
	"yara": {"name": "Yara Quill", "league": 3, "edge": 0.08, "style": "cocky", "machine": "wheels"},
	"ashe": {"name": "Ashe Tamura", "league": 3, "edge": 0.12, "style": "clean", "machine": "hover"},
	"brandt": {"name": "Brandt Okoye", "league": 4, "edge": 0.03, "style": "veteran", "machine": "wheels"},
	"zeph": {"name": "Zeph Calloway", "league": 4, "edge": 0.06, "style": "cocky", "machine": "hover"},
	"iris": {"name": "Iris Kestrel", "league": 4, "edge": 0.1, "style": "clean", "machine": "wheels"},
}
## The moments a rival speaks: at the lights, when you pass them, when they
## pass you, when you leave the track, when they win, and when you beat them
## to the line.
const EVENTS := ["lights", "pass", "passed", "off", "win", "beaten"]
## What each manner says at each moment. "{you}" is the racer's name.
## A humbled rival (`HUMBLED_AFTER`) says the "humbled" lines instead at
## the lights and when passed.
const LINES := {
	"cocky": {
		"lights": ["Hope you like the view of my tail lights, {you}.", "Wake me when you catch up.",
				"Another grid, another win. Try to keep up."],
		"pass": ["Lucky line. Won't happen twice.", "Enjoy it while it lasts."],
		"passed": ["Excuse me, coming through.", "That's where you belong, behind me."],
		"off": ["The track's the grey bit, {you}.", "Sightseeing again?"],
		"win": ["Was there ever any doubt?", "Same result as always."],
		"beaten": ["Fluke. Rematch, now.", "My machine was off. Next time."],
		"humbled": ["Fine. You're quick. Don't tell anyone I said so.", "I've been watching your lines, {you}."],
	},
	"clean": {
		"lights": ["Clean race, everyone. Good luck, {you}.", "Hold your lines into the first turn."],
		"pass": ["Nicely done. I'll be back.", "Good move, fair and square."],
		"passed": ["Coming by on the outside.", "Sorry, had the run on you."],
		"off": ["Careful out there, {you}.", "Keep it on the road, it's a long race."],
		"win": ["Good racing, everyone.", "Close one. Thanks for the fight."],
		"beaten": ["Well driven, {you}. Deserved.", "You had the pace today."],
		"humbled": ["You've been teaching me lines, {you}.", "I'm studying your braking points now."],
	},
	"blocker": {
		"lights": ["My line, my corner. Remember that.", "You'll have to find a way round me, {you}."],
		"pass": ["Hey, I had that line!", "Watch it, {you}."],
		"passed": ["Door's shut, {you}.", "Find another way round."],
		"off": ["That's what happens when you push.", "Told you there was no room."],
		"win": ["Nobody gets by me.", "Wide enough, wasn't I?"],
		"beaten": ["You squeezed through. Barely.", "Next time I close that gap."],
		"humbled": ["Fine, I'll leave you a lane.", "You keep finding the gap, {you}."],
	},
	"veteran": {
		"lights": ["Easy off the line, it's three laps.", "Patience wins races, {you}."],
		"pass": ["Saw that coming. Good move.", "Hm. You've been practising."],
		"passed": ["Experience, {you}. Watch and learn.", "Lifted too early there."],
		"off": ["Brake before the bend, not in it.", "Every racer does that once. Or twice."],
		"win": ["Old tricks still work.", "Done this a long time, {you}."],
		"beaten": ["The young ones get faster every year.", "Well raced. You earned that."],
		"humbled": ["Not much left I can teach you, {you}.", "I'll be chasing you today."],
	},
	"joker": {
		"lights": ["Last one home buys the coolant!", "Ready, steady, wobble!"],
		"pass": ["Hey! I was sightseeing!", "Rude, {you}. Very rude."],
		"passed": ["Beep beep!", "Toot toot, coming through!"],
		"off": ["Ooh, scenic route!", "The salt flats are lovely this time of year."],
		"win": ["I won? I won! Somebody write that down!", "Drinks are on you, {you}."],
		"beaten": ["I let you win. Obviously.", "Rematch! Best of seventeen!"],
		"humbled": ["Okay you're good, it's not funny any more.", "Can I just follow you round?"],
	},
}


## A fresh racer: rookie, no rating, no races.
static func fresh() -> Dictionary:
	return {"rating": 0, "league": 0, "top_beaten": false, "races": 0, "wins": 0, "podiums": 0,
			"rivals": {}, "recent": [], "day": 0, "paid": 0}


## A saved state, made safe: anything missing or out of range is fixed.
static func clean(raw: Variant) -> Dictionary:
	var out := fresh()
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	var d: Dictionary = raw
	out.league = clampi(int(d.get("league", 0)), 0, LEAGUES.size() - 1)
	out.rating = clampi(int(d.get("rating", 0)), floor_of(out.league), 1_000_000)
	out.top_beaten = bool(d.get("top_beaten", false))
	for key: String in ["races", "wins", "podiums", "day", "paid"]:
		out[key] = maxi(0, int(d.get(key, 0)))
	var rivals: Variant = d.get("rivals", {})
	if typeof(rivals) == TYPE_DICTIONARY:
		for id: Variant in rivals:
			var pair: Variant = rivals[id]
			if RIVALS.has(str(id)) and typeof(pair) == TYPE_ARRAY and (pair as Array).size() == 2:
				out.rivals[str(id)] = [maxi(0, int(pair[0])), maxi(0, int(pair[1]))]
	var recent: Variant = d.get("recent", [])
	if typeof(recent) == TYPE_ARRAY:
		for row: Variant in recent:
			if typeof(row) == TYPE_DICTIONARY and out.recent.size() < RECENT:
				out.recent.append({"track": str(row.get("track", "")).left(32),
						"place": clampi(int(row.get("place", 0)), 0, MAX_FIELD),
						"field": clampi(int(row.get("field", 0)), 0, MAX_FIELD),
						"points": clampi(int(row.get("points", 0)), -MAX_FIELD * LOSE_POINTS, MAX_FIELD * BEAT_POINTS),
						"day": maxi(0, int(row.get("day", 0)))})
	return out


## A race's result for one racer, made safe: {"track", "place", "field",
## "finished", "ahead", "behind"} where "ahead" and "behind" are the rival
## ids who finished ahead of and behind them. Empty if it makes no sense.
static func clean_result(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = raw
	var field := clampi(int(d.get("field", 0)), 0, MAX_FIELD)
	var place := int(d.get("place", 0))
	if field < 2 or place < 1 or place > field:
		return {}
	var out := {"track": str(d.get("track", "")).left(32), "place": place, "field": field,
			"finished": bool(d.get("finished", true)), "ahead": [], "behind": []}
	for side: String in ["ahead", "behind"]:
		var ids: Variant = d.get(side, [])
		if typeof(ids) != TYPE_ARRAY:
			continue
		for id: Variant in ids:
			var rid := str(id)
			if RIVALS.has(rid) and rid not in out.ahead and rid not in out.behind:
				out[side].append(rid)
	return out


static func league_name(league: int) -> String:
	return str(LEAGUES[clampi(league, 0, LEAGUES.size() - 1)].name)


## The rating a league starts at.
static func floor_of(league: int) -> int:
	return int(LEAGUES[clampi(league, 0, LEAGUES.size() - 1)].from)


## The rating that reaches the next league, or -1 at the top.
static func next_from(league: int) -> int:
	return int(LEAGUES[league + 1].from) if league + 1 < LEAGUES.size() else -1


## How good a league's AI racers are, before each rival's own edge.
static func ai_skill(league: int) -> float:
	return float(LEAGUES[clampi(league, 0, LEAGUES.size() - 1)].ai)


## A league's rivals, its top rival last.
static func rivals_in(league: int) -> Array[String]:
	var out: Array[String] = []
	for id: String in RIVALS:
		if int(RIVALS[id].league) == league:
			out.append(id)
	return out


## The rival you must beat to leave `league`.
static func top_rival(league: int) -> String:
	var all := rivals_in(league)
	return all[all.size() - 1] if not all.is_empty() else ""


static func rival_name(id: String) -> String:
	return str(RIVALS[id].name) if RIVALS.has(id) else id


## A rival's skill (0 to 1): their league's and their own edge.
static func rival_skill(id: String) -> float:
	if not RIVALS.has(id):
		return 0.5
	return clampf(ai_skill(int(RIVALS[id].league)) + float(RIVALS[id].edge), 0.0, 1.0)


## Rating for finishing `place` of `field`: points for everyone behind,
## a little lost for everyone ahead. A racer who did not finish counts last.
static func points_for(place: int, field: int, finished := true) -> int:
	var at := place if finished else field
	return (field - at) * BEAT_POINTS - (at - 1) * LOSE_POINTS


## Scrip for finishing `place`; nothing for not finishing.
static func scrip_for(place: int, finished := true) -> int:
	if not finished:
		return 0
	return PLACE_SCRIP[place - 1] if place <= PLACE_SCRIP.size() else FINISH_SCRIP


## Your wins and losses against a rival.
static func record_against(state: Dictionary, id: String) -> Array:
	var rivals: Dictionary = state.get("rivals", {})
	return rivals.get(id, [0, 0])


## True once you are `HUMBLED_AFTER` wins up on a rival.
static func humbled(state: Dictionary, id: String) -> bool:
	var rec := record_against(state, id)
	return int(rec[0]) - int(rec[1]) >= HUMBLED_AFTER


## True while your rating waits at the next league for the top rival.
static func at_gate(state: Dictionary) -> bool:
	var next := next_from(int(state.get("league", 0)))
	return next >= 0 and int(state.get("rating", 0)) >= next and not bool(state.get("top_beaten", false))


## A race's result applied to `state` on day `day` (`Contracts.today`):
## {"state" (the new state), "points", "scrip", "promoted"}. The state
## passed in is not changed.
static func apply(state: Dictionary, result: Dictionary, day: int) -> Dictionary:
	var s := clean(state)
	var r := clean_result(result)
	if r.is_empty():
		return {"state": s, "points": 0, "scrip": 0, "promoted": false}
	var league: int = s.league
	var finished: bool = r.finished
	var points := points_for(r.place, r.field, finished)
	s.races += 1
	if finished and r.place == 1:
		s.wins += 1
	if finished and r.place <= 3:
		s.podiums += 1
	for id: String in r.behind:
		var rec: Array = s.rivals.get(id, [0, 0])
		s.rivals[id] = [int(rec[0]) + 1, int(rec[1])]
		if id == top_rival(league):
			s.top_beaten = true
	for id: String in r.ahead:
		var rec: Array = s.rivals.get(id, [0, 0])
		s.rivals[id] = [int(rec[0]), int(rec[1]) + 1]
	var rating: int = maxi(s.rating + points, floor_of(league))
	var next := next_from(league)
	var promoted := false
	if next >= 0 and rating >= next:
		if s.top_beaten:
			league += 1
			promoted = true
			s.top_beaten = false
			# One league at a time: the next gate waits at the next league's top.
			var after := next_from(league)
			if after >= 0:
				rating = mini(rating, after)
		else:
			rating = next
	s.league = league
	s.rating = rating
	if int(s.day) != day:
		s.day = day
		s.paid = 0
	var scrip := mini(scrip_for(r.place, finished), maxi(DAILY_CAP - int(s.paid), 0))
	s.paid = int(s.paid) + scrip
	s.recent.push_front({"track": r.track, "place": r.place if finished else 0, "field": r.field,
			"points": points, "day": day})
	if s.recent.size() > RECENT:
		s.recent.resize(RECENT)
	return {"state": s, "points": points, "scrip": scrip, "promoted": promoted}


## What rival `id` says over the radio at `event`, to a racer called `you`
## with league state `state`; `pick` chooses among the lines. Empty if the
## rival has nothing to say then.
static func line(id: String, event: String, you: String, state: Dictionary, pick: int) -> String:
	if not RIVALS.has(id):
		return ""
	var said: Dictionary = LINES.get(str(RIVALS[id].style), {})
	var key := event
	if event in ["lights", "pass"] and humbled(state, id) and said.has("humbled"):
		key = "humbled"
	var options: Array = said.get(key, [])
	if options.is_empty():
		return ""
	return str(options[posmod(pick, options.size())]).replace("{you}", you)


## One line for the Racing app and the notices: "Club · 84 rating".
static func standing_line(state: Dictionary) -> String:
	var s := clean(state)
	var text := "%s · %d rating" % [league_name(s.league), s.rating]
	if at_gate(s):
		text += " · beat %s to move up" % rival_name(top_rival(s.league))
	return text
