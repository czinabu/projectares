extends Node3D
## The people of a safe zone: locals who live their day in it, and a few you
## can talk to (DESIGN.md section 2, "Locals"). A view only, like the rest of
## `PlazaView`: every client makes the same crowd from the map's
## `locals_layout()` and a fixed seed, and walks each local along a routine
## timed by the wall clock, so everyone sees much the same people in much the
## same places and the server sends nothing and runs nothing for them.
##
## Locals are ordinary `Actor`s, dressed by `Look` and driven only through
## their `ActorCommand` (legs follow velocity as for anyone), but they are not
## part of the world: not in the "actors" group, no collision with people,
## never a child of the `Raid`, so nothing in the simulation, the roster or
## the network sees them. They look at people who come near and step out of
## their way. Far ones are thinned like far bots (`Actor.thin`).
##
## The people you talk to stand at the map's "talker" markers (meta "id",
## "yaw", "name", "role", and where they have them "lines", "reads",
## "color" and "dress", the outfits they wear for their work). `talk` makes them answer in a speech panel over their head: a
## lit card in the world, never on the screen. A keeper works a counter (a
## shop, the clan hall) and has no spot of their own: `greet` has them say
## their piece when someone uses the counter.
##
## Load with `preload("res://core/social/plaza_locals.gd")`.

const Human := preload("res://core/visual/human.gd")
const Contracts := preload("res://core/economy/contracts.gd")
const RaidRoster := preload("res://core/ui/raid_roster.gd")
const Economy := preload("res://core/economy/economy.gd")
## The loadout slots each shop's keeper looks you over for.
const SHOP_SLOTS := {
	"armory": ["primary", "sidearm", "melee"],
	"outfitter": ["frame", "helmet", "rig"],
	"garage": ["vehicle"],
}

## The crowd's seed: the same everywhere, so every client agrees.
const CROWD_SEED := 52_731
## A local further than this from where their routine says is put back there.
const SNAP := 6.0
## Close enough to where they should be to stand still.
const ARRIVED := 0.3
## People nearer than this are looked at, and nearer than `GIVE_WAY` in their
## path are stepped round.
const NOTICE := 7.0
const GIVE_WAY := 1.9
## A talker turns to face anyone this close.
const FACE_RANGE := 4.5
## Past this from the camera a local takes a step every few ticks.
const THIN_RANGE := 45.0
## How long a line stays up, and how far you can walk off before it closes.
const SPEECH_TIME := 9.0
const SPEECH_RANGE := 8.0
## A cart's customers keep to one beat: each step of their round (joining
## the queue, moving up, ordering, eating, walking off) takes whole beats, and
## no two are on the same step, so two never stand in the same place in the
## queue. SNACK_STEPS is the round in beats: arriving, two in the queue,
## eating, leaving.
const SNACK_BEAT := 9.0
const SNACK_ARRIVE := 4
const SNACK_EAT := 6
const SNACK_LEAVE := 4
const SNACK_STEPS := SNACK_ARRIVE + 2 + SNACK_EAT + SNACK_LEAVE

## How many of each kind make up the crowd. Not one to a spot: the counts and
## who goes together are rolled from the seed.
var strollers := 8
var shoppers := 8
var watchers := 8
var chats := 5
var wanderers := 10
## Customers at each boulevard cart (and its cook).
var diners := 7

var raid: Raid
## The map's layout (see `worlds/plaza/map.gd locals_layout`).
var layout := {}
## Each local: {actor, routine, offset, speed, side, talker}.
var locals: Array[Dictionary] = []
## Talker id -> its entry in `locals`.
var talkers := {}
## Talker id -> SpeechPanel.
var panels := {}
## The talker whose line is up, and how long it has left.
var speaking := ""
var _speech_left := 0.0
## Each talker's next line, so talking again moves on.
var _line_index := {}
## What Rook offered in the line now up: a job id to take, or "".
var offered_job := ""
## Seconds since the crowd last checked who is far from the camera.
var _thin_wait := 0.0
## For tests: a clock to use instead of the wall clock (< 0 for the wall).
var clock_override := -1.0


func setup(p_raid: Raid) -> void:
	raid = p_raid


func _ready() -> void:
	if raid == null or raid.map == null or not raid.map.has_method("locals_layout"):
		return
	layout = raid.map.call("locals_layout")
	var rng := RandomNumberGenerator.new()
	rng.seed = CROWD_SEED
	for plan in plan_crowd(layout, rng, {"strollers": strollers, "shoppers": shoppers, "watchers": watchers,
			"chats": chats, "wanderers": wanderers, "diners": diners}):
		_spawn(plan, rng)
	for node in raid.get_tree().get_nodes_in_group("talker"):
		var marker := node as Node3D
		if marker == null or not raid.map.is_ancestor_of(marker):
			continue
		var id := str(marker.get_meta("id", ""))
		var routine := Routine.new()
		routine.dwell(marker.global_position, float(marker.get_meta("yaw", 0.0)), 60.0)
		var look_rng := RandomNumberGenerator.new()
		look_rng.seed = hash(["talker", id])
		var entry := _spawn({"routine": routine, "offset": 0.0, "speed": 1.2, "side": 0.0,
				"dress": marker.get_meta("dress", {})}, look_rng)
		entry["talker"] = id
		entry["name"] = str(marker.get_meta("name", id.capitalize()))
		entry["role"] = str(marker.get_meta("role", ""))
		entry["lines"] = marker.get_meta("lines", [])
		entry["reads"] = str(marker.get_meta("reads", ""))
		entry["color"] = marker.get_meta("color", talker_color(id))
		entry["shop"] = str(marker.get_meta("shop", ""))
		entry.actor.display_name = entry.name
		talkers[id] = entry
		_add_name_tag(entry)
		var panel := SpeechPanel.new()
		panel.name = "Speech_%s" % id
		add_child(panel)
		panel.global_position = marker.global_position + Vector3(0, 2.15, 0)
		panels[id] = panel


func _spawn(plan: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var actor := Actor.new()
	actor.name = "Local%d" % locals.size()
	actor.display_name = "Local"
	actor.set_meta("appearance", Human.random(rng, plan.get("dress", {})))
	var routine: Routine = plan.routine
	var start := routine.sample(_now() + float(plan.offset))
	actor.position = start.pos + Vector3(0, 0.05, 0)
	add_child(actor)
	# Not part of the world: nothing scans for them and nobody bumps them.
	actor.remove_from_group("actors")
	actor.collision_layer = 0
	actor.collision_mask = Actor.LAYER_WORLD
	Loadout.equip(actor, [])
	actor.weapons_locked = true
	actor.cmd.yaw = float(start.yaw)
	var entry := {"actor": actor, "routine": routine, "offset": float(plan.offset),
			"speed": float(plan.speed), "side": float(plan.get("side", 0.0)), "talker": ""}
	locals.append(entry)
	return entry


func _add_name_tag(entry: Dictionary) -> void:
	var tag := Label3D.new()
	tag.name = "NameTag"
	tag.text = "%s\n%s" % [entry.name, entry.role] if entry.role != "" else entry.name
	tag.font_size = 40
	tag.pixel_size = 0.0035
	tag.outline_size = 0
	tag.modulate = Color(0.92, 0.97, 1.0, 0.92)
	tag.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	tag.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	tag.visibility_range_end = 14.0
	tag.position = Vector3(0, 2.05, 0)
	(entry.actor as Actor).add_child(tag)


func _now() -> float:
	return clock_override if clock_override >= 0.0 else Time.get_unix_time_from_system()


func _physics_process(delta: float) -> void:
	if locals.is_empty():
		return
	var people := RaidRoster.players_in(raid) if raid != null and is_instance_valid(raid) else [] as Array[Actor]
	var now := _now()
	for entry in locals:
		var actor: Actor = entry.actor
		if not is_instance_valid(actor) or not actor.ticks_now():
			continue
		_steer(entry, now, people, delta * actor.tick_every)
	_thin_wait -= delta
	if _thin_wait <= 0.0:
		_thin_wait = 0.5
		_thin_far()


func _process(delta: float) -> void:
	if speaking == "":
		return
	_speech_left -= delta
	var me := raid.player if raid != null and is_instance_valid(raid) else null
	var entry: Dictionary = talkers.get(speaking, {})
	var walked_off := me != null and is_instance_valid(me) and not entry.is_empty() \
			and me.global_position.distance_to((entry.actor as Actor).global_position) > SPEECH_RANGE
	if _speech_left <= 0.0 or walked_off:
		hush()


## Steers one local toward where its routine has it now, looking at people
## nearby and stepping out of their way.
func _steer(entry: Dictionary, now: float, people: Array[Actor], delta: float) -> void:
	var actor: Actor = entry.actor
	var routine: Routine = entry.routine
	var want := routine.sample(now + float(entry.offset))
	var target: Vector3 = want.pos
	if float(entry.side) != 0.0 and want.walking:
		var dir: Vector3 = want.dir
		target += Vector3(-dir.z, 0.0, dir.x) * float(entry.side)
	var here := actor.global_position
	var to := Vector3(target.x - here.x, 0.0, target.z - here.z)
	if to.length() > SNAP:
		actor.global_position = Vector3(target.x, target.y + 0.05, target.z)
		actor.velocity = Vector3.ZERO
		to = Vector3.ZERO
	var walk := Vector3.ZERO
	var face := float(want.yaw)
	if to.length() > ARRIVED:
		walk = to.normalized()
		face = yaw_of(walk)
		# Catch up a little when behind, so the crowd keeps to the clock.
		actor.walk_speed = float(entry.speed) * clampf(0.85 + to.length() * 0.25, 0.85, 1.5)
	var near := nearest_person(here, people)
	var look_yaw := face
	var pitch := 0.0
	if near != null:
		var head := near.get_eye_position()
		var off := head - actor.get_eye_position()
		var flat := Vector3(off.x, 0.0, off.z)
		var gap := flat.length()
		if walk != Vector3.ZERO and gap < GIVE_WAY and walk.angle_to(flat) < deg_to_rad(60.0):
			# Someone in the way: step round them, on the side away from them.
			var side := Vector3(-walk.z, 0.0, walk.x)
			if side.dot(flat) > 0.0:
				side = -side
			walk = (walk + side * 0.9).normalized()
		if entry.talker != "" and walk == Vector3.ZERO and gap < FACE_RANGE:
			face = yaw_of(flat)
			look_yaw = face
			pitch = atan2(off.y, maxf(gap, 0.01))
		elif gap < NOTICE:
			var turn := wrapf(yaw_of(flat) - face, -PI, PI)
			if absf(turn) < deg_to_rad(110.0):
				look_yaw = face + clampf(turn, -1.2, 1.2)
				pitch = clampf(atan2(off.y, maxf(gap, 0.01)), -0.5, 0.5)
	var rate := minf(1.0, delta * 5.0)
	actor.cmd.yaw = lerp_angle(actor.cmd.yaw, look_yaw, rate)
	actor.cmd.pitch = lerpf(actor.cmd.pitch, pitch, rate)
	var local := Basis(Vector3.UP, -actor.cmd.yaw) * walk
	actor.cmd.move = Vector2(local.x, -local.z)


func _thin_far() -> void:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		return
	var eye := camera.global_position
	for i in locals.size():
		var actor: Actor = locals[i].actor
		if is_instance_valid(actor):
			actor.thin(3 if actor.global_position.distance_to(eye) > THIN_RANGE else 1, i % 3)


## The person nearest `at`, or null.
static func nearest_person(at: Vector3, people: Array[Actor]) -> Actor:
	var best: Actor = null
	var best_gap := NOTICE
	for person in people:
		if not is_instance_valid(person) or person.is_dead:
			continue
		var gap := person.global_position.distance_to(at)
		if gap < best_gap:
			best = person
			best_gap = gap
	return best


## The yaw that faces along `dir` (yaw 0 faces -Z, as `Actor` has it).
static func yaw_of(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


# --- Talking -----------------------------------------------------------------

## Someone used a talker's spot. Puts their next line up over their head.
## `world_status` is the server's news of the worlds and `account` the
## player's snapshot (for Rook's favour). Returns the job id to take when the
## player answers Rook's offer by talking to him again, else "".
func talk(id: String, world_status: Dictionary, account: Dictionary) -> String:
	if not talkers.has(id):
		return ""
	if id == "rook" and speaking == "rook" and offered_job != "":
		var job := offered_job
		offered_job = ""
		_say(id, "Good. It's on your board now. Get it done and get out breathing.")
		return job
	var line := ""
	var job_offered := ""
	match id:
		"kade":
			var lines := kade_lines(world_status)
			line = lines[_next_line(id, lines.size())]
		"dusk":
			var lines := rumours(world_status)
			line = lines[_next_line(id, lines.size())]
		"rook":
			var said := rook_line(account, Contracts.today())
			line = said.text
			job_offered = said.job
		_:
			var lines := own_lines(talkers[id], world_status)
			line = lines[_next_line(id, lines.size())]
	_say(id, line)
	offered_job = job_offered
	return ""


## A keeper's hello when someone uses their counter: their next line, unless
## they are already talking.
func greet(id: String, world_status := {}, account := {}) -> void:
	if not talkers.has(id) or speaking == id:
		return
	var entry: Dictionary = talkers[id]
	var lines := stock_lines(str(entry.get("shop", "")), account, Contracts.today())
	lines.append_array(own_lines(entry, world_status))
	_say(id, lines[_next_line(id, lines.size())])


## What a keeper says about the shop's real stock and the player's own
## account (the snapshot the client already holds): today's featured piece
## (picked by the date, the same for everyone all day), something they could
## use and afford, and what they could sell. Never a price the shop does not
## charge.
static func stock_lines(shop_id: String, account: Dictionary, day: int) -> Array[String]:
	var out: Array[String] = []
	if shop_id == "":
		return out
	var stock := Economy.stock(shop_id)
	var stash: Array = account.get("stash", [])
	if not stock.is_empty():
		var featured: String = stock[absi(hash([shop_id, day])) % stock.size()]
		out.append("%s came in today. %d scrip." % [ItemDB.item_name(featured), Economy.buy_price(featured)])
	var advice := _advice(shop_id, stock, account)
	if advice != "":
		out.append(advice)
	if shop_id in SHOP_SLOTS:
		var worth := Economy.loot_value(stash)
		if worth > 0:
			out.append("You're sitting on salvage. I'll give you %d scrip for the lot." % worth)
	return out


## Something on the shelf that beats what the player wears (or fills an
## empty slot), that they do not own yet and can pay for. "" if nothing fits.
static func _advice(shop_id: String, stock: Array[String], account: Dictionary) -> String:
	if not account.has("scrip"):
		return ""
	var scrip := int(account.get("scrip", 0))
	var stash: Array = account.get("stash", [])
	var loadout: Dictionary = account.get("loadout", {})
	if shop_id in SHOP_SLOTS:
		for slot: String in SHOP_SLOTS[shop_id]:
			var worn := str(loadout.get(slot, ""))
			var worn_value := ItemDB.item_value(worn) if worn != "" else 0
			for id: String in stock:
				if not Loadout.fits(slot, id) or id in stash or Economy.buy_price(id) > scrip \
						or ItemDB.item_value(id) <= worn_value:
					continue
				if worn == "" or ItemDB.has_tag(worn, "starter"):
					return "Nothing worth the name in your %s slot. A %s is %d, and you can cover it." % \
							[str(Loadout.SLOT_NAMES.get(slot, slot)).to_lower(), ItemDB.item_name(id), Economy.buy_price(id)]
				return "That %s has done its time. A %s is %d, and you can cover it." % \
						[ItemDB.item_name(worn), ItemDB.item_name(id), Economy.buy_price(id)]
		return ""
	for id: String in stock:
		if id not in stash and Economy.buy_price(id) <= scrip:
			return "You haven't got the %s yet. %d, and it's yours for good." % [ItemDB.item_name(id), Economy.buy_price(id)]
	return ""


## What a talker without lines of their own in code says: the dispatcher reads
## the worlds out, anyone else their marker's lines.
static func own_lines(entry: Dictionary, world_status: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if str(entry.get("reads", "")) == "worlds":
		out = dispatch_lines(world_status)
	for line: Variant in entry.get("lines", []):
		out.append(str(line))
	if out.is_empty():
		out.append("...")
	return out


## The dispatcher's board read aloud: how each world is doing, from
## `world_status` only (players, war level, the event), never who is where.
static func dispatch_lines(world_status: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var ids: Array = world_status.keys()
	ids.sort()
	for id: Variant in ids:
		var status: Variant = world_status[id]
		if typeof(status) != TYPE_DICTIONARY:
			continue
		var players := int(status.get("players", 0))
		var line := "%s: %s in, war %s." % [world_name(str(id)), "nobody" if players == 0 else str(players),
				str(status.get("level", "quiet")).to_lower()]
		var event := str(status.get("event", ""))
		if event != "":
			line += " There's a %s on." % event.to_lower()
		out.append(line)
	out.append("Pick an arch and walk through it. It lights when you're in it. Your kit goes with you.")
	return out


## Takes the line down.
func hush() -> void:
	if panels.has(speaking):
		(panels[speaking] as SpeechPanel).close()
		_show_name(speaking, true)
	speaking = ""
	offered_job = ""


func _say(id: String, text: String) -> void:
	if speaking != "" and speaking != id:
		hush()
	speaking = id
	_speech_left = SPEECH_TIME
	var entry: Dictionary = talkers[id]
	(panels[id] as SpeechPanel).say(entry.name, entry.get("color", talker_color(id)), text)
	# The card carries their name while it is up.
	_show_name(id, false)


func _show_name(id: String, shown: bool) -> void:
	var entry: Dictionary = talkers.get(id, {})
	if entry.is_empty() or not is_instance_valid(entry.actor):
		return
	var tag := (entry.actor as Node).get_node_or_null("NameTag") as Node3D
	if tag != null:
		tag.visible = shown


func _next_line(id: String, count: int) -> int:
	var at := int(_line_index.get(id, 0)) % maxi(count, 1)
	_line_index[id] = at + 1
	return at


static func talker_color(id: String) -> Color:
	match id:
		"kade":
			return Color(1.0, 0.42, 0.35)
		"dusk":
			return Color(0.45, 0.85, 1.0)
		"rook":
			return Color(0.55, 1.0, 0.65)
	return Color(0.9, 0.9, 0.9)


## Kade, by the most-wanted board: how bounties work, and who is up there.
static func kade_lines(world_status: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var top := top_wanted(world_status)
	if not top.is_empty():
		out.append("%s is worth %d right now, out in %s. Take them down and it's in your pocket." %
				[top.name, top.bounty, world_name(top.world)])
	out.append("Every name on that board pays what's on their head, in scrip. You carry it, so you can lose it. Get it home and it's yours.")
	out.append("Rack up kills against other players and your own name goes up there. Then everyone's hunting you.")
	if top.is_empty():
		out.append("Board's empty. Nobody's hot enough yet. Give it time.")
	return out


## The biggest bounty across the worlds, with its world: {name, bounty,
## world}, or {}.
static func top_wanted(world_status: Dictionary) -> Dictionary:
	var best := {}
	for world: Variant in world_status:
		var entry: Variant = world_status[world]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		for wanted: Variant in entry.get("wanted", []):
			if typeof(wanted) != TYPE_DICTIONARY:
				continue
			if best.is_empty() or int(wanted.get("bounty", 0)) > int(best.bounty):
				best = {"name": str(wanted.get("name", "")), "bounty": int(wanted.get("bounty", 0)), "world": str(world)}
	return best


## What Dusk has heard: lines made from what the server says of each world
## (war level, players, the event, the top bounty), then a few that are
## always true. Never more than the plaza's own signs already know.
static func rumours(world_status: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var ids: Array = world_status.keys()
	ids.sort()
	for id: Variant in ids:
		var status: Variant = world_status[id]
		if typeof(status) != TYPE_DICTIONARY:
			continue
		var name := world_name(str(id))
		var event := str(status.get("event", ""))
		var war := float(status.get("war", 0.0))
		var players := int(status.get("players", 0))
		if event != "":
			out.append("Word is there's a %s going on in %s. If you hurry, you might see it end." % [event.to_lower(), name])
		if war >= 0.6:
			out.append("%s is burning. %s in there and the war's at %s. Don't take in what you can't stand to lose." %
					[name, "One poor soul" if players == 1 else "%d people" % players, str(status.get("level", "")).to_lower()])
		elif players == 0:
			out.append("Nobody's in %s right now. Quiet is when the careful ones go in." % name)
		if int(status.get("bounty", 0)) > 0:
			out.append("Someone in %s is carrying a %d bounty. Kade's got the name." % [name, int(status.bounty)])
	out.append_array(["The Pit runs bouts all day. Nobody loses their gear in there, only their pride.",
			"Bank at a depot before you get greedy. I've watched a lot of people get greedy.",
			"You hear the guns before you see them. If it's gone quiet out there, something big is walking."])
	return out


## Rook's line: today's favour and whether you hold it already. {text, job}
## where `job` is the favour on offer (empty once taken or done).
static func rook_line(account: Dictionary, day: int) -> Dictionary:
	var job := Contracts.favor_for(day)
	if job == "":
		return {"text": "Nothing today. Check back tomorrow.", "job": ""}
	var state: Variant = account.get("contracts", null)
	if typeof(state) != TYPE_DICTIONARY:
		return {"text": "Come back when you're signed in properly. I don't deal with strangers.", "job": ""}
	if job in state.get("done", []):
		return {"text": "That's all I had today. You did good. Come back tomorrow.", "job": ""}
	for entry: Variant in state.get("active", []):
		if typeof(entry) == TYPE_DICTIONARY and str(entry.get("id", "")) == job:
			return {"text": "You're on it: %s. Sign out alive and I'll know." % Contracts.title_of(job), "job": ""}
	var info := Contracts.job(job)
	return {"text": "%s\n%d scrip in it for you. Talk to me again to take it." %
			[str(info.get("ask", Contracts.title_of(job))), int(info.get("scrip", 0))], "job": job}


static func world_name(id: String) -> String:
	var world := Worlds.get_world(id)
	return world.display_name if world != null else id.capitalize()


# --- The crowd ---------------------------------------------------------------

## Plans the crowd from a map's layout: one entry per local, each {routine,
## offset, speed, side}. `counts` names how many of each kind. Everything
## comes from `rng`, so a seed makes the same crowd anywhere, and nothing is
## spaced evenly: groups, gaps and timings are all rolled.
static func plan_crowd(p_layout: Dictionary, rng: RandomNumberGenerator, counts: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var centre: Vector3 = p_layout.get("centre", Vector3.ZERO)
	var rings: Array = p_layout.get("rings", [])
	for i in int(counts.get("strollers", 0)):
		if rings.is_empty():
			break
		var band: Array = rings[rng.randi() % rings.size()]
		var r := rng.randf_range(float(band[0]), float(band[1]))
		var routine := stroll(centre, r, rng)
		var speed := rng.randf_range(1.1, 1.55)
		var offset := rng.randf() * routine.length
		out.append({"routine": routine, "offset": offset, "speed": speed, "side": 0.0})
		# Now and then they walk as a pair.
		if rng.randf() < 0.4:
			out.append({"routine": routine, "offset": offset + rng.randf_range(-0.4, 0.4), "speed": speed,
					"side": rng.randf_range(0.75, 1.05) * (1.0 if rng.randf() < 0.5 else -1.0)})
	var browse: Array = p_layout.get("browse", [])
	for i in int(counts.get("shoppers", 0)):
		if browse.is_empty():
			break
		var routine := shop(centre, float(p_layout.get("promenade", 50.0)), browse, rng, p_layout.get("street", {}))
		out.append({"routine": routine, "offset": rng.randf() * routine.length, "speed": rng.randf_range(1.0, 1.4)})
	var watch: Array = p_layout.get("watch", [])
	var taken: Array[Vector3] = []
	for i in int(counts.get("watchers", 0)):
		if watch.is_empty():
			break
		var spot := _watch_spot(watch, taken, rng)
		taken.append(spot.pos)
		out.append({"routine": stand_about(spot.pos, float(spot.yaw), 0.35, rng), "offset": 0.0, "speed": 1.0})
		# Some came with a friend, close but not lined up.
		if rng.randf() < 0.35:
			var beside: Vector3 = spot.pos + Vector3(rng.randf_range(0.7, 1.0) * (1.0 if rng.randf() < 0.5 else -1.0),
					0.0, rng.randf_range(-0.25, 0.25))
			taken.append(beside)
			out.append({"routine": stand_about(beside, float(spot.yaw), 0.4, rng), "offset": 0.0, "speed": 1.0})
	var gather: Array = p_layout.get("gather", []).duplicate()
	for i in int(counts.get("chats", 0)):
		if gather.is_empty():
			break
		var at: Vector3 = gather.pop_at(rng.randi() % gather.size())
		var size := rng.randi_range(2, 3)
		var angle := rng.randf() * TAU
		for k in size:
			angle += rng.randf_range(1.6, 2.6)
			var spot := at + Vector3(cos(angle), 0.0, sin(angle)) * rng.randf_range(0.65, 1.05)
			var inward := at - spot
			out.append({"routine": stand_about(spot, yaw_of(inward), 0.6, rng), "offset": 0.0, "speed": 1.0})
	for stop: Dictionary in p_layout.get("stops", []):
		var cook: Array = stop.cook
		out.append({"routine": stand_about(cook[0], float(cook[1]), 0.5, rng), "offset": 0.0, "speed": 1.0})
		# The queue: a step back from the counter each, not quite in line.
		var queue: Vector3 = stop.queue
		var aside := queue.cross(Vector3.UP)
		var slots: Array = [stop.counter]
		for k in 2:
			slots.append(Vector3(slots[-1]) + queue * rng.randf_range(0.9, 1.15) + aside * rng.randf_range(-0.2, 0.2))
		var places: Array = stop.places.duplicate()
		var steps: Array = range(SNACK_STEPS)
		for k in range(steps.size() - 1, 0, -1):
			var j := rng.randi() % (k + 1)
			var swap: int = steps[k]
			steps[k] = steps[j]
			steps[j] = swap
		for k in mini(int(counts.get("diners", 0)), places.size()):
			var place: Array = places.pop_at(rng.randi() % places.size())
			# Each waits out on the lane in a spot of their own.
			var wait := Vector3(stop.far) + Vector3(cos(TAU * k / 7.0), 0.0, sin(TAU * k / 7.0)) * 2.4
			out.append({"routine": snack(stop, slots, place, wait, rng), "offset": float(steps[k]) * SNACK_BEAT,
					"speed": 1.4, "stop": stop.counter})
	var routes: Array = p_layout.get("routes", [])
	for i in int(counts.get("wanderers", 0)):
		if routes.is_empty():
			break
		var routine := wander(routes[i % routes.size()], rng)
		out.append({"routine": routine, "offset": rng.randf() * routine.length, "speed": rng.randf_range(1.15, 1.5)})
	return out


## A free spot on one of the watching tiers, not too near anyone already
## there: {pos, yaw}.
static func _watch_spot(watch: Array, taken: Array[Vector3], rng: RandomNumberGenerator) -> Dictionary:
	var spot := {}
	for attempt in 12:
		var tier: Dictionary = watch[rng.randi() % watch.size()]
		var half := float(tier.width) * 0.5 - 1.0
		var depth := float(tier.depth) * 0.5 - 0.5
		var centre: Vector3 = tier.centre
		var pos := centre + Vector3(rng.randf_range(-half, half), 0.0, rng.randf_range(-depth, depth))
		spot = {"pos": pos, "yaw": float(tier.yaw) + rng.randf_range(-0.2, 0.2)}
		if taken.all(func(other: Vector3) -> bool: return other.distance_to(pos) > 1.3):
			break
	return spot


## Strolling part way round a ring and back, stopping at each end (and
## sometimes on the way) to look about.
static func stroll(centre: Vector3, radius: float, rng: RandomNumberGenerator) -> Routine:
	var routine := Routine.new()
	var start := rng.randf() * TAU
	var sweep := rng.randf_range(0.9, 3.2) * (1.0 if rng.randf() < 0.5 else -1.0)
	var out_points := arc(centre, radius, start, start + sweep)
	var speed := 1.3
	routine.walk(out_points, speed)
	routine.dwell(out_points[-1], rng.randf() * TAU, rng.randf_range(4.0, 22.0))
	var back := out_points.duplicate()
	back.reverse()
	if rng.randf() < 0.5 and back.size() > 4:
		var mid := back.size() / 2
		routine.walk(back.slice(0, mid + 1), speed)
		routine.dwell(back[mid], yaw_of(centre - back[mid]), rng.randf_range(3.0, 12.0))
		routine.walk(back.slice(mid), speed)
	else:
		routine.walk(back, speed)
	routine.dwell(back[-1], rng.randf() * TAU, rng.randf_range(5.0, 25.0))
	return routine


## Window shopping: two or three shops next to each other, a while at each
## door, walking between them, then back. With a `street` ({from, to, lane})
## the shops face each other down it: they walk its lane on their own side
## and cross only at the next door. Otherwise round the `promenade` ring.
static func shop(centre: Vector3, promenade: float, browse: Array, rng: RandomNumberGenerator,
		street := {}) -> Routine:
	var sorted := browse.duplicate()
	if not street.is_empty():
		var from: Vector3 = street.from
		var axis: Vector3 = (Vector3(street.to) - from).normalized()
		sorted.sort_custom(func(a: Array, b: Array) -> bool:
			return (Vector3(a[0]) - from).dot(axis) < (Vector3(b[0]) - from).dot(axis))
	var count := mini(rng.randi_range(2, 3), sorted.size())
	var first := rng.randi() % sorted.size()
	var stops: Array = []
	for k in count:
		var stop: Array = sorted[(first + k) % sorted.size()]
		# Not all on the one spot: a step either way along the front.
		var along := Basis(Vector3.UP, float(stop[1])) * Vector3.RIGHT
		stops.append([Vector3(stop[0]) + along * rng.randf_range(-1.2, 1.2), stop[1]])
	var routine := Routine.new()
	var speed := 1.2
	var order := stops.duplicate()
	var back := stops.duplicate()
	back.reverse()
	order.append_array(back.slice(1, back.size() - 1))
	for k in order.size():
		var here: Array = order[k]
		var next: Array = order[(k + 1) % order.size()]
		routine.dwell(here[0], float(here[1]) + rng.randf_range(-0.3, 0.3), rng.randf_range(8.0, 30.0))
		if not street.is_empty():
			routine.walk(street_path(street, here[0], next[0]), speed)
			continue
		var from_angle := _angle(centre, here[0])
		var to_angle := _angle(centre, next[0])
		var turn := wrapf(to_angle - from_angle, -PI, PI)
		var path: Array = [here[0]]
		path.append_array(arc(centre, promenade, from_angle, from_angle + turn))
		path.append(next[0])
		routine.walk(path, speed)
	return routine


## From one door to the next down a street: out to the lane on this side,
## along it to level with the next door, then across to it.
static func street_path(street: Dictionary, here: Vector3, next: Vector3) -> Array:
	var from: Vector3 = street.from
	var axis: Vector3 = (Vector3(street.to) - from).normalized()
	var across := axis.cross(Vector3.UP)
	var side := signf((here - from).dot(across))
	if side == 0.0:
		side = 1.0
	var lane := float(street.get("lane", 3.0)) * side
	var at_here := from + axis * (here - from).dot(axis) + across * lane
	var at_next := from + axis * (next - from).dot(axis) + across * lane
	return [here, at_here, at_next, next]


## Standing in one place: a few dwells facing about `yaw`, glancing up to
## `spread` radians either way, shifting their weight now and then.
static func stand_about(at: Vector3, yaw: float, spread: float, rng: RandomNumberGenerator) -> Routine:
	var routine := Routine.new()
	for k in rng.randi_range(3, 5):
		routine.dwell(at, yaw + rng.randf_range(-spread, spread), rng.randf_range(5.0, 18.0))
	return routine


## A customer's round at a cart, SNACK_STEPS beats long: in from the lane to
## the back of the queue, up a place, ordering at the counter, eating at
## their `place` ([pos, yaw]) at a table, then off the way they came and a
## while out on the lane at `far`. Every step ends on its beat (see
## SNACK_BEAT).
static func snack(stop: Dictionary, slots: Array, place: Array, far: Vector3, rng: RandomNumberGenerator) -> Routine:
	var routine := Routine.new()
	var beat := SNACK_BEAT
	var yaw := float(stop.yaw)
	# They set off in time to reach the back of the queue as its last beat
	# starts, never sooner, or they would share it with the one before.
	var walk := far.distance_to(stop.enter) + Vector3(stop.enter).distance_to(slots[2])
	var budget := beat * (SNACK_ARRIVE - 1)
	var speed := maxf(1.25, walk / (budget * 0.9))
	routine.dwell(far, yaw_of(Vector3(stop.enter) - far), budget - walk / speed)
	routine.walk([far, stop.enter, slots[2]], speed)
	routine.dwell(slots[2], yaw, beat)
	_step(routine, [slots[2], slots[1]], yaw, beat)
	_step(routine, [slots[1], slots[0]], yaw, beat)
	# Out of the queue's way before turning for the table.
	_step(routine, [slots[0], stop.served, place[0]],
			float(place[1]) + rng.randf_range(-0.2, 0.2), beat * SNACK_EAT)
	_step(routine, [place[0], stop.enter, far], rng.randf() * TAU, beat * SNACK_LEAVE)
	return routine


## Walks `points` and waits at the last, facing `yaw`, `time` seconds in all;
## a walk too long for it is taken faster.
static func _step(routine: Routine, points: Array, yaw: float, time: float) -> void:
	var walk := 0.0
	for k in points.size() - 1:
		walk += Vector3(points[k]).distance_to(points[k + 1])
	var speed := maxf(1.25, walk / (time * 0.8))
	var before := routine.length
	routine.walk(points, speed)
	routine.dwell(points[-1], yaw, maxf(time - (routine.length - before), 0.01))


## Out along a route and back, a while at the far end.
static func wander(route: Array, rng: RandomNumberGenerator) -> Routine:
	var routine := Routine.new()
	var points: Array = route.duplicate()
	routine.walk(points, 1.3)
	var end: Vector3 = points[-1]
	routine.dwell(end, yaw_of(end - points[-2]) + rng.randf_range(-0.5, 0.5), rng.randf_range(12.0, 40.0))
	var back := points.duplicate()
	back.reverse()
	routine.walk(back, 1.3)
	routine.dwell(back[-1], rng.randf() * TAU, rng.randf_range(6.0, 20.0))
	return routine


## Points round a circle from one angle to another, a step of about 3 m.
## Angles here are plain math angles round `centre` (x = cos, z = sin).
static func arc(centre: Vector3, radius: float, from_angle: float, to_angle: float) -> Array:
	var steps := maxi(1, int(ceil(absf(to_angle - from_angle) * radius / 3.0)))
	var out: Array = []
	for k in steps + 1:
		var a := lerpf(from_angle, to_angle, float(k) / steps)
		out.append(centre + Vector3(cos(a), 0.0, sin(a)) * radius)
	return out


static func _angle(centre: Vector3, at: Vector3) -> float:
	return atan2(at.z - centre.z, at.x - centre.x)


## A loop of walks and waits, timed so it can be read at any moment: where
## the local is, which way they face, and whether they are walking.
class Routine:
	extends RefCounted
	## Each leg: {a, b, time, yaw, walking}.
	var legs: Array[Dictionary] = []
	## Seconds round the loop.
	var length := 0.0

	func walk(points: Array, speed: float) -> void:
		for k in points.size() - 1:
			var a: Vector3 = points[k]
			var b: Vector3 = points[k + 1]
			var gap := Vector3(b.x - a.x, 0.0, b.z - a.z)
			if gap.length() < 0.01:
				continue
			var time := gap.length() / maxf(speed, 0.1)
			legs.append({"a": a, "b": b, "time": time, "yaw": atan2(-gap.x, -gap.z), "walking": true})
			length += time

	func dwell(at: Vector3, yaw: float, time: float) -> void:
		legs.append({"a": at, "b": at, "time": time, "yaw": yaw, "walking": false})
		length += time

	## Where the routine has them at `t` seconds (any number: it loops):
	## {pos, yaw, walking, dir}.
	func sample(t: float) -> Dictionary:
		if legs.is_empty():
			return {"pos": Vector3.ZERO, "yaw": 0.0, "walking": false, "dir": Vector3.FORWARD}
		var left := fposmod(t, maxf(length, 0.001))
		for leg in legs:
			if left <= float(leg.time):
				var a: Vector3 = leg.a
				var b: Vector3 = leg.b
				var share := left / maxf(float(leg.time), 0.001)
				var dir := Vector3(b.x - a.x, 0.0, b.z - a.z)
				return {"pos": a.lerp(b, share), "yaw": float(leg.yaw), "walking": bool(leg.walking),
						"dir": dir.normalized() if dir.length() > 0.001 else Vector3.FORWARD}
			left -= float(leg.time)
		var last: Dictionary = legs[-1]
		return {"pos": last.b, "yaw": float(last.yaw), "walking": false, "dir": Vector3.FORWARD}


## A line said over someone's head: a dark card with a lit edge in the
## speaker's colour, their name small on top and the line under it in clean
## text, turned to the viewer and faded in and out. Lives in the world.
class SpeechPanel:
	extends Node3D
	## The card's width, and the text's size on it.
	const WIDTH := 2.8
	const PAD := 0.13
	const PIXEL := 0.0028
	const BODY_SIZE := 48
	const NAME_SIZE := 40
	var _back: MeshInstance3D
	var _edge: MeshInstance3D
	var _name: Label3D
	var _body: Label3D
	var _back_mat: StandardMaterial3D
	var _edge_mat: StandardMaterial3D
	var _alpha := 0.0
	var _target := 0.0

	func _ready() -> void:
		_back_mat = _flat(Color(0.03, 0.05, 0.08, 0.94), false)
		_edge_mat = _flat(Color(1, 1, 1), true)
		_back = _quad(_back_mat)
		_edge = _quad(_edge_mat)
		_name = _label(NAME_SIZE)
		_body = _label(BODY_SIZE)
		visible = false

	func say(who: String, color: Color, text: String) -> void:
		_name.text = who.to_upper()
		_name.modulate = color
		_body.text = text
		_edge_mat.albedo_color = color
		var font: Font = _body.font if _body.font != null else ThemeDB.fallback_font
		var inner := WIDTH - PAD * 2.0
		var body_px := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, inner / PIXEL, BODY_SIZE)
		var name_h := font.get_height(NAME_SIZE) * PIXEL
		var body_h := body_px.y * PIXEL
		var height := PAD * 2.0 + name_h + 0.04 + body_h
		(_back.mesh as QuadMesh).size = Vector2(WIDTH, height)
		_back.position = Vector3(0, height * 0.5, 0)
		(_edge.mesh as QuadMesh).size = Vector2(WIDTH, 0.025)
		_edge.position = Vector3(0, height, 0.002)
		_name.position = Vector3(0, height - PAD, 0.004)
		_body.position = Vector3(0, height - PAD - name_h - 0.04, 0.004)
		_body.width = inner / PIXEL
		_target = 1.0
		visible = true

	func close() -> void:
		_target = 0.0

	func _process(delta: float) -> void:
		_alpha = move_toward(_alpha, _target, delta * 5.0)
		visible = _alpha > 0.0
		if not visible:
			return
		var camera := get_viewport().get_camera_3d()
		if camera != null:
			var to := camera.global_position - global_position
			rotation.y = atan2(to.x, to.z)
		_back_mat.albedo_color.a = 0.94 * _alpha
		_edge_mat.albedo_color.a = _alpha
		_name.modulate.a = _alpha
		_body.modulate.a = _alpha

	func _flat(color: Color, glow: bool) -> StandardMaterial3D:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		if glow:
			mat.emission_enabled = true
			mat.emission = color
		return mat

	func _quad(mat: Material) -> MeshInstance3D:
		var mesh := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.material = mat
		mesh.mesh = quad
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mesh)
		return mesh

	func _label(size: int) -> Label3D:
		var label := Label3D.new()
		label.font_size = size
		label.pixel_size = PIXEL
		label.outline_size = 0
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		label.render_priority = 2
		add_child(label)
		return label
