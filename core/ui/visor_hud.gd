class_name VisorHud
extends Control
## What a helmet shows its wearer. Two halves:
##
## The glass. Drawn over the view in first person only, and only while a
## helmet is worn: the visor projects its readouts into your view. It is a
## display of thin lines of light, never a frame: nothing is blacked out or
## tinted, and nothing sits over the middle of the view but the reticle.
## Everything hugs the rim of the glass and the middle stays clear (Caleb's
## redesign, after a reference he liked, made our own): every helmet has its
## vitals as a short row of hex cells along the lower left curve (health,
## armor, stamina, a flight rig's heat and cue, the ability), each filling
## like a gauge with its number over it (`vital_cells`). A working helmet
## also has a heading tape across the top, bowed with the glass, numbered
## every 15 degrees with the heading in a notch under it, marking the squad,
## pings and the nearest depot (`compass_marks`); a contact scope top left
## plotting those same marks round you, never a map (`scope_points`), with
## the squad's size on its rim; the helmet's name, role and system beside the
## scope; an objective block top right under a thin bracket, a hex bullet,
## progress bar and count per contract held, then the tour's step
## (`objective_lines`); faint pitch ticks up both edges; and a ring round the
## crosshair. Each helmet has a role (`role_name`), shown as it comes on, its own reticle,
## and the rest depends on its `mode` (see `Visor`): range finder, lock-on
## brackets, binocular scale and tagged targets on the strip for "zoom"
## (recon); a sweep, contact count and the scan's contacts on the strip for
## "scan" (intel); for "threat" (tactical) the health of whoever is under
## the crosshair, what nearby loot holds, the war's hot zone on the strip
## and where a hit came from; for "thermal" a heat picture of the whole view
## and how warm you look yourself. A scrap visor only manages a bearing and
## the vitals. Every helmet, scrap included, also reads loot: the container
## you look at is tagged with everything inside it (`_draw_crate`), and what
## you pick up runs up a short feed over the weapon readout (`_draw_pickups`).
## The display is alive: it sweeps in when it comes on (`boot`),
## trails the view a little as you turn (`sway`), sits dim until something
## happens (`alert`) and closes on what you aim at (`lock`). With no helmet,
## or in third person, nothing is drawn. It works wherever a helmet is worn:
## a world, the plaza and the arena (`setup`, a `Raid`) and the home base
## (`setup_base`).
##
## The world. Things a visor puts out there, seen in either view: the frozen
## snapshots of a scan, markers over tagged targets, the ring of a scan pulse
## (anyone's), the outlines of Threat Sense, the glint off a lens that is
## looking your way, and the ember of a thermal visor seen up close.
##
## A view only: it reads `Visor` state and never decides what is revealed.

const Contracts := preload("res://core/economy/contracts.gd")
const GameSettings := preload("res://core/settings/game_settings.gd")

## How long the mark for a scan that caught you stays on the glass.
var felt_time := 2.5
## How long a pulse's ring takes to cross its radius.
var ring_time := 0.7
## How squarely a lens must face you to glint, as the cosine of the angle.
var glint_facing := 0.94
## Seconds between range finder readings.
var range_interval := 0.1
var range_max := 600.0
## How long the mark for a hit stays on a tactical visor.
var hit_mark_time := 1.6
## How close a thermal visor's ember can be seen from.
var ember_range := 18.0
## Seconds the display takes to sweep in when it comes on.
var boot_time := 0.9
## How far the display trails the view, in pixels per radian turned per
## second, how far it may drift at most, and how fast it settles.
var sway_gain := 26.0
var sway_max := 22.0
var sway_settle := 7.0
## How bright the standing lines are while nothing is happening (0 to 1),
## and how fast an alert fades.
var idle_dim := 0.55
var alert_fade := 0.7
## How far the brackets lock on to someone, and how fast they close.
var lock_range := 220.0
var lock_rate := 6.0
## The body heat cell's colours: icy out in the cold, a heater's orange
## while warming up.
const BODY_HEAT_INK := Color(0.6, 0.85, 1.0)
const WARMING_INK := Color(1.0, 0.6, 0.25)
## How far frost has crept in over the glass (0 to 1), from body heat.
var frost := 0.0
## How much ash has settled on the glass (0 to 1), from an ash storm.
var ash := 0.0
## Most specks of ash the glass holds, and how far in from the rim they
## settle (a share of the way to the middle, which stays clear).
const ASH_SPECKS := 220
const ASH_CLEAR := 0.55
## Streaks of the weather whipping across the glass as you fly fast through
## it (Caleb's first person flight pass): how many there are at most, how
## strong they are now (0 to 1), and in what colour (the storm's own streak
## colour, frost white in the cold). The speeds (m/s) they start and are
## full at, and how strong the cold alone makes them with no storm.
const STREAKS := 48
var streaks := 0.0
var streak_ink := Color(1, 1, 1, 0.6)
var streak_from := 12.0
var streak_full := 38.0
var streak_cold := 0.45
## How fast the streaks run across the glass now, a share of full speed.
var _streak_run := 0.0
var _streak_clock := 0.0
## The armor arc's colour (stamina takes the glass's own).
const ARMOR_INK := Color(0.5, 0.75, 1.0)
## Colours of the heading strip's marks that are not the glass's own.
const SQUAD_INK := Color(0.45, 1.0, 0.6)
const PING_INK := Color(0.35, 0.95, 1.0)
const HOT_INK := Color(1.0, 0.55, 0.15)
## A storm crossing the map (DESIGN.md "Weather: ash storms").
const STORM_INK := Color(0.95, 0.72, 0.55)
## Scrip piles near you (`Raid.piles`), and a pile holding a bounty.
const PILE_INK := Color(1.0, 0.78, 0.3)
const BOUNTY_INK := Color(1.0, 0.42, 0.25)
## The most piles marked at once, nearest first.
const PILES_SHOWN := 4
const TAG_INK := Color(1.0, 0.3, 0.2)
## The waypoint set on the watch map.
const WAYPOINT_INK := Color(1.0, 0.9, 0.4)
## How many degrees either side of straight ahead the heading strip shows.
var strip_reach := 45.0
## How far the heading strip bows down at its ends, as a share of the
## screen's height: the glass is curved.
var strip_bow := 0.018
## How far out the contact scope reaches, in metres, before a mark sits on
## its rim.
var scope_range := 80.0
## Where the vitals cells sit along the glass's lower left curve: how far in
## the first is and how low the row runs (shares of the view's height), and
## how much the row lifts toward the left edge, as the glass curves up there.
var vitals_left := 0.075
var vitals_low := 0.9
var vitals_lift := 0.07
## Where the landing warning sits, as a share of the view's height.
var landing_low := 0.86
## Pitch ticks: pixels per degree, as a share of the view's height.
var pitch_scale := 0.009
## The weapon readout, bottom right: how long it stays lit after a switch,
## below what share of a mag it counts as low, how bright it rests, and how
## fast it wakes and settles.
var weapon_show_time := 2.5
var weapon_low_share := 0.25
var weapon_rest := 0.55
var weapon_fade := 2.5
## The war must be at least this hot before a tactical visor marks its centre.
var hot_from := 0.25
## How long the helmet's name stays up after the display comes on.
var ident_time := 2.4
## Seconds the glass's scan line takes to run down the view.
var scanline_time := 5.5
## The pickup feed (`pickups`): how long a line stays, how long it takes to
## fade at the end, how long it slides in, and how many lines at most.
var pickup_time := 4.5
var pickup_fade := 1.2
var pickup_slide := 0.18
var pickup_lines := 6
## The container tag (`_draw_crate`): rows a column before a second column
## starts, and seconds it takes to come up once you look at one.
var crate_rows := 12
var crate_rise := 0.15

## Where the wearer is: a `Raid` (a world, the plaza, the arena) or, with
## `setup_base`, a `HomeBase`. The glass works the same in both, so a helmet
## shows its display wherever it is worn.
var raid: Raid
var base: HomeBase
var controller: PlayerController
## The range finder's last reading in metres, below zero for nothing in reach.
var range_reading := -1.0
## Scans that caught the wearer: {"origin": Vector3, "left": float}.
var felt: Array[Dictionary] = []
## Hits a tactical visor is pointing out: {"origin": Vector3, "left": float}.
var hit_marks: Array[Dictionary] = []
## Who a tactical visor is reading under the crosshair, or null.
var read_target: Actor
## True while the view is the thermal picture.
var thermal_shown := false
## How far the display has swept in, 0 off to 1 fully on.
var boot := 0.0
## How far the display is trailing the view right now, in pixels.
var sway := Vector2.ZERO
## How awake the display is, 0 calm to 1: a hit, a scan or a threat raises it.
var alert := 0.0
## Whoever is under the crosshair within `lock_range`, and how far the
## brackets have closed on them (0 to 1).
var aim_target: Actor
var lock := 0.0
## How lit the weapon readout is, 0 resting to 1 (`weapon_awake`).
var weapon_lit := 0.0
## How far the binocular scale has opened, 0 to 1.
var zoom_shown := 0.0
## Height above the ground while off it, below zero when standing on it.
var altitude := -1.0
## The landing warning, 0 to 1 (`Hud.landing_warning`): drawn low in the
## middle of the glass's lower rim, and flat in third person.
var landing := 0.0
## Everyone on the wearer's squad in this world, alive (see `squadmate`).
var squad: Array[Actor] = []
## Spots the wearer's side pinged: {"at": Vector3, "left": float}.
var pings: Array[Dictionary] = []
## The HUD this glass belongs to (`Hud`, or the home base's), for the
## contracts held and the tour's objective. May be null.
var hud: Node
## The pickup feed: what you just picked up, newest last, one line an item
## kind ({"id", "count", "left", "age"}), fed by `Actor.looted`.
var pickups: Array[Dictionary] = []
## The container you are looking at (the one F would loot), or null, and
## how far its tag has come up (0 to 1).
var looked: LootContainer
var crate_shown := 0.0

var _world: Node3D
var _ghosts: Array[MeshInstance3D] = []
var _tag_marks := {}
## Everyone tagged for the wearer's side right now, for the heading strip.
var _tagged: Array[Actor] = []
## Seconds since the display last came on, for the helmet's name.
var _since_boot := 0.0
var _glints := {}
var _embers := {}
var _threat_marks := {}
var _heat := {}
var _thermal: ColorRect
var _rings: Array[Dictionary] = []
var _heard := {}
var _range_wait := 0.0
var _time := 0.0
var _last_look := Vector2.ZERO
var _look_known := false
## The actor whose signals the glass listens to. The home base swaps its
## actor out when it has to, so this is followed rather than set once.
var _wired: Actor
## The weapon in hand last frame, and seconds since it changed.
var _last_weapon: Weapon
var _since_switch := 99.0


func setup(p_raid: Raid, p_controller: PlayerController) -> void:
	raid = p_raid
	controller = p_controller


## The glass in a home base: the same display, with nothing a world adds
## (pings, depots, the war).
func setup_base(p_base: HomeBase, p_controller: PlayerController) -> void:
	base = p_base
	controller = p_controller


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world = Node3D.new()
	_world.name = "VisorWorld"
	var host: Node = raid if raid != null else base
	if host != null:
		host.add_child.call_deferred(_world)
	_thermal = ColorRect.new()
	_thermal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_thermal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_thermal.show_behind_parent = true
	_thermal.visible = false
	var shader := Shader.new()
	shader.code = THERMAL_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	_thermal.material = material
	add_child(_thermal)
	_wire(_player())
	if raid != null:
		raid.pinged.connect(_on_pinged)


## Listens to the wearer's scans, hits and damage, moving over when the
## wearer is a new actor.
func _wire(p: Actor) -> void:
	if p == _wired:
		return
	if _wired != null and is_instance_valid(_wired):
		_wired.visor.felt_scan.disconnect(_on_felt_scan)
		_wired.visor.threatened.disconnect(_on_threatened)
		_wired.health.damaged.disconnect(_on_damaged)
		_wired.looted.disconnect(_on_looted)
	_wired = p
	if p != null:
		p.visor.felt_scan.connect(_on_felt_scan)
		p.visor.threatened.connect(_on_threatened)
		p.health.damaged.connect(_on_damaged)
		p.looted.connect(_on_looted)


func _on_damaged(_info: DamageInfo) -> void:
	alert = 1.0


## Something was picked up: a line on the feed for each kind of item. One
## already on the feed counts up and stays longer instead.
func _on_looted(ids: Array[String]) -> void:
	for id in ids:
		var line := {}
		for entry in pickups:
			if entry.id == id:
				line = entry
		if line.is_empty():
			pickups.append({"id": id, "count": 1, "left": pickup_time, "age": 0.0})
		else:
			line.count += 1
			line.left = pickup_time
	while pickups.size() > pickup_lines:
		pickups.pop_front()


func _exit_tree() -> void:
	if _world != null and is_instance_valid(_world):
		_world.queue_free()


## True while the wearer is looking through the glass: a helmet on, alive,
## and the camera in their head.
func glass_shown() -> bool:
	var p := _player()
	if p == null or p.is_dead or not p.visor.working():
		return false
	return controller == null or not controller.is_third_person()


## True while a helmet's readouts are drawn flat in third person: the same
## information as the glass, so neither view is better informed (Caleb's
## call); only the glass itself (its rim, a scrap visor's cracks, the trail
## behind your turns) belongs to first person.
func flat_shown() -> bool:
	var p := _player()
	return p != null and not p.is_dead and p.visor.working() 			and controller != null and controller.is_third_person()


## The thermal picture: the view's brightness run through a heat ramp, cold
## blue to hot white. The world is dimmed so it stays cold; warm bodies are
## drawn bright (see `_sync_heat`) and so come out hot.
const THERMAL_SHADER := """
shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_linear;

void fragment() {
	vec3 seen = texture(screen, SCREEN_UV).rgb;
	float heat = dot(seen, vec3(0.299, 0.587, 0.114));
	// Bodies are drawn far brighter than anything the world has.
	float warm = smoothstep(0.82, 1.0, heat);
	float cold = clamp(heat * 0.6, 0.0, 0.5);
	vec3 ramp = mix(vec3(0.01, 0.02, 0.09), vec3(0.16, 0.2, 0.42), cold * 2.0);
	vec3 hot = mix(vec3(1.0, 0.45, 0.05), vec3(1.0, 0.98, 0.85), smoothstep(0.9, 1.0, heat));
	float line = 0.94 + 0.06 * sin(FRAGCOORD.y * 2.4);
	COLOR = vec4(mix(ramp, hot, warm) * line, 1.0);
}
"""


## Compass bearing in degrees for a yaw: 0 north (-Z), 90 east (+X).
static func bearing(yaw: float) -> float:
	return fposmod(-rad_to_deg(yaw), 360.0)


## Where `origin` lies for someone at `at` facing `yaw`, as an angle from
## straight ahead: positive to the right, PI behind.
static func angle_to(origin: Vector3, at: Vector3, yaw: float) -> float:
	var local := Basis(Vector3.UP, yaw).inverse() * (origin - at)
	return atan2(local.x, -local.z)


## The short name of a compass bearing: N, NE, E and so on.
static func compass_name(degrees: float) -> String:
	var names := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	return names[posmod(roundi(degrees / 45.0), 8)]


func _player() -> Actor:
	var p: Actor = null
	if raid != null:
		p = raid.player
	elif base != null and is_instance_valid(base):
		p = base.player
	if p == null or not is_instance_valid(p) or p.is_queued_for_deletion():
		return null
	return p


func _process(delta: float) -> void:
	_time += delta
	var p := _player()
	_wire(p)
	for mark in felt:
		mark.left -= delta
	felt = felt.filter(func(m: Dictionary) -> bool: return m.left > 0.0)
	for mark in hit_marks:
		mark.left -= delta
	hit_marks = hit_marks.filter(func(m: Dictionary) -> bool: return m.left > 0.0)
	for mark in pings:
		mark.left -= delta
	pings = pings.filter(func(m: Dictionary) -> bool: return m.left > 0.0)
	for line in pickups:
		line.left -= delta
		line.age += delta
	pickups = pickups.filter(func(m: Dictionary) -> bool: return m.left > 0.0)
	var seen := looked_container(p)
	if seen != looked:
		crate_shown = 0.0
	looked = seen
	crate_shown = minf(1.0, crate_shown + delta / maxf(crate_rise, 0.01)) if looked != null else 0.0
	thermal_shown = p != null and (glass_shown() or flat_shown()) and p.visor.thermal_on
	_thermal.visible = thermal_shown
	# Frost creeps in once body heat is half gone, and melts off when warm.
	var frosted := 0.0
	if p != null and Hud.feels_cold(p):
		frosted = clampf(1.0 - p.body_heat / maxf(p.max_body_heat * 0.5, 1.0), 0.0, 1.0)
	frost = move_toward(frost, frosted, delta * (0.15 if frosted > frost else 0.5))
	# Ash settles on the glass in an ash storm and blows off slowly after.
	var ashing := 0.0
	if p != null and raid != null and raid.weather != null and raid.world != null:
		ashing = ash_settling(raid.world.weather_kind, raid.weather.strength_at(p.global_position))
	ash = move_toward(ash, ashing, delta * (0.06 if ashing > ash else 0.04))
	_update_streaks(p, delta)
	landing = Hud.landing_warning(p) if p != null and (glass_shown() or flat_shown()) else 0.0
	_animate(p, delta)
	if p == null or _world == null or not _world.is_inside_tree():
		queue_redraw()
		return
	_read_range(p, delta)
	_sync_ghosts(p)
	# One pass over everyone in the wearer's world, shared by what follows.
	var around: Array[Actor] = []
	for node in get_tree().get_nodes_in_group("actors"):
		var other := node as Actor
		if other != null and Raid.together(other, p):
			around.append(other)
	squad.clear()
	for other in around:
		if squadmate(raid, p, other):
			squad.append(other)
	_sync_actors(p, around)
	_sync_heat(p, around)
	_tick_rings(delta)
	queue_redraw()


## Moves the display's own motion along: the sweep in, the trail behind
## the view, the alert level, the lock and the binocular scale.
func _animate(p: Actor, delta: float) -> void:
	if p == null or not (glass_shown() or flat_shown()):
		boot = 0.0
		sway = Vector2.ZERO
		lock = 0.0
		zoom_shown = 0.0
		_look_known = false
		return
	if boot <= 0.0:
		_since_boot = 0.0
	_since_boot += delta
	boot = minf(1.0, boot + delta / maxf(boot_time, 0.01))
	if not glass_shown():
		# Flat in third person: no glass to trail behind the view.
		sway = Vector2.ZERO
		_look_known = false
		var held := aim_target != null and is_instance_valid(aim_target) and not aim_target.is_dead
		lock = move_toward(lock, 1.0 if held else 0.0, lock_rate * delta)
		return
	var look := Vector2(p.cmd.yaw, p.cmd.pitch)
	if _look_known and delta > 0.0:
		# Turning right (yaw falls) leaves the display behind, to the left.
		var turned := Vector2(wrapf(look.x - _last_look.x, -PI, PI), look.y - _last_look.y) / delta
		sway += Vector2(turned.x, turned.y) * sway_gain * delta
	_last_look = look
	_look_known = true
	sway = sway.limit_length(sway_max) * exp(-sway_settle * delta)
	var busy := p.visor.is_sensing() or not p.visor.threats.is_empty() or p.visor.is_zoomed() \
			or p.visor.thermal_on or not felt.is_empty() or not hit_marks.is_empty() \
			or p.health.health < p.health.max_health * 0.35 or landing > 0.0
	alert = 1.0 if busy else maxf(0.0, alert - alert_fade * delta)
	var locked := aim_target != null and is_instance_valid(aim_target) and not aim_target.is_dead
	lock = move_toward(lock, 1.0 if locked else 0.0, lock_rate * delta)
	zoom_shown = move_toward(zoom_shown, 1.0 if p.visor.is_zoomed() else 0.0, 5.0 * delta)
	var held := p.get_active_weapon()
	if held != _last_weapon:
		_last_weapon = held
		_since_switch = 0.0
	_since_switch += delta
	weapon_lit = move_toward(weapon_lit, 1.0 if weapon_awake(held) else 0.0, weapon_fade * delta)


func _on_felt_scan(origin: Vector3) -> void:
	felt.append({"origin": origin, "left": felt_time})
	Sfx.play("ability", null, -9.0)


## A ping from the wearer or their side (others never reach a client; solo
## they are filtered here like the HUD's own marker).
func _on_pinged(pinger: Actor, at: Vector3) -> void:
	var p := _player()
	if p == null or not is_instance_valid(pinger):
		return
	if pinger != p and raid.mode != Raid.Mode.CLIENT and not Visor.allied(p, pinger):
		return
	pings.append({"at": at, "left": raid.ping_time})


## True if `other` is on the wearer's squad: another living player in the
## same world who shares a clan with them, or anyone in a world where all
## players fight together. Never a bot, never an enemy (DESIGN.md section 5).
## Clans are what a client is told about, so this works the same online.
static func squadmate(p_raid: Raid, p: Actor, other: Actor) -> bool:
	if p_raid == null or other == null or other == p or other.is_dead or p_raid.state_for(other) == null:
		return false
	if p_raid.world != null and p_raid.world.players_allied:
		return true
	return p.clan != "" and p.clan == other.clan


## What each helmet is for, shown as it comes on.
static func role_name(mode: String) -> String:
	match mode:
		"zoom":
			return "RECON"
		"scan":
			return "INTEL"
		"threat":
			return "TACTICAL"
		"thermal":
			return "THERMAL"
	return "SCRAP"


## How warm the wearer looks to a thermal visor (`Visor.heat_of`), for an
## Ember's own readout.
static func signature_text(heat: float) -> String:
	if heat >= 1.2:
		return "SIG HIGH"
	if heat >= 0.7:
		return "SIG MED"
	return "SIG LOW"


## The visor's contract tracker: the job nearest done (`Hud.contract_slot`),
## or "" with none held.
static func tracker_text(held: Array[Dictionary], tally: Dictionary) -> String:
	if held.is_empty():
		return ""
	return str(Hud.contract_slot(held, tally).detail).to_upper()


## What the heading strip marks, nearest the middle last so it draws on top:
## {"kind", "at" (Vector3), "label"}. Kinds: "squad", "ping" and "depot" on
## every working visor, with the watch map's "waypoint" and "storm" (the
## middle of a storm crossing the map) and "pile" or "bounty" (a scrip pile
## within `WorldDef.pile_seen_range`, which everyone near can see glowing
## anyway); "tag" (Spotter), "contact" (Seeker's snapshots) and "hot" (the
## war's centre, Warden). A scrap visor marks nothing.
func compass_marks(p: Actor) -> Array[Dictionary]:
	var marks: Array[Dictionary] = []
	var v := p.visor
	if v.mode == "":
		return marks
	var nearest: Node3D = null
	for depot in raid.depots if raid != null else []:
		if is_instance_valid(depot) and Raid.together(depot, p) and (nearest == null
				or depot.global_position.distance_to(p.global_position)
				< nearest.global_position.distance_to(p.global_position)):
			nearest = depot
	if nearest != null:
		marks.append({"kind": "depot", "at": nearest.global_position, "label": "DEPOT"})
	if raid != null and raid.weather.active():
		marks.append({"kind": "storm", "at": raid.weather.centre + Vector3(0.0, p.global_position.y, 0.0),
				"label": raid.world.weather_name.to_upper().left(10)})
	for pile in nearby_piles(p):
		marks.append({"kind": "bounty" if pile.bounty > 0 else "pile", "at": pile.global_position,
				"label": "BOUNTY" if pile.bounty > 0 else "SCRIP"})
	if v.mode == "threat" and raid != null and raid.war.intensity >= hot_from:
		marks.append({"kind": "hot", "at": raid.war.centre, "label": "HOT"})
	for ghost in v.ghosts if v.mode == "scan" else []:
		marks.append({"kind": "contact", "at": ghost.at, "label": ""})
	for target in _tagged if v.mode == "zoom" else []:
		if is_instance_valid(target):
			marks.append({"kind": "tag", "at": target.global_position, "label": ""})
	for ping in pings:
		marks.append({"kind": "ping", "at": ping.at, "label": "PING"})
	# The waypoint set on the watch map: only yours.
	var way: Variant = hud.get("waypoint") if hud != null and is_instance_valid(hud) else null
	if way is Dictionary and not (way as Dictionary).is_empty():
		marks.append({"kind": "waypoint", "at": way.at, "label": String(way.title).left(10).to_upper()})
	for mate in squad:
		if is_instance_valid(mate):
			marks.append({"kind": "squad", "at": mate.global_position, "label": mate.display_name.left(8).to_upper()})
	return marks


## The scrip piles within the world's `pile_seen_range` of `p`, nearest
## first, at most `PILES_SHOWN`.
func nearby_piles(p: Actor) -> Array[LootContainer]:
	var out: Array[LootContainer] = []
	if raid == null or not raid.world.death_drops_scrip:
		return out
	var reach := raid.world.pile_seen_range
	for pile: Variant in raid.piles:
		if is_instance_valid(pile) and (pile as LootContainer).scrip > 0 \
				and (pile as Node3D).global_position.distance_to(p.global_position) <= reach:
			out.append(pile)
	out.sort_custom(func(a: LootContainer, b: LootContainer) -> bool:
		return a.global_position.distance_squared_to(p.global_position) \
				< b.global_position.distance_squared_to(p.global_position))
	return out.slice(0, PILES_SHOWN)


func _on_threatened(origin: Vector3) -> void:
	hit_marks.append({"origin": origin, "left": hit_mark_time})


## What the wearer's eyes see along their aim: how far it is (the range
## finder), who it is (the lock, and a tactical visor's readout), and how
## high the wearer is.
func _read_range(p: Actor, delta: float) -> void:
	_range_wait -= delta
	if _range_wait > 0.0 or p.visor.mode == "" or not p.visor.working() or not p.is_inside_tree():
		return
	_range_wait = range_interval
	var from := p.get_eye_position()
	var query := PhysicsRayQueryParameters3D.create(from, from + p.get_aim_dir() * range_max,
			Actor.LAYER_WORLD | Actor.LAYER_ACTORS)
	query.exclude = [p.get_rid()]
	var hit := p.get_world_3d().direct_space_state.intersect_ray(query)
	range_reading = -1.0 if hit.is_empty() else from.distance_to(hit.position)
	var seen := hit.get("collider") as Actor
	var found := seen if seen != null and not seen.is_dead and range_reading <= lock_range else null
	if found != aim_target:
		aim_target = found
		lock = 0.0
	read_target = found if found != null and p.visor.mode == "threat" \
			and range_reading <= p.visor.read_range else null
	# How high the wearer is, for the readout that shows in the air.
	altitude = -1.0
	if p.airborne_time > 0.35 and p.vehicle == null:
		var feet := p.global_position + Vector3(0.0, 0.5, 0.0)
		var down := PhysicsRayQueryParameters3D.create(feet, feet + Vector3.DOWN * 400.0, Actor.LAYER_WORLD)
		var ground := p.get_world_3d().direct_space_state.intersect_ray(down)
		altitude = 400.0 if ground.is_empty() else maxf(0.0, feet.y - 0.5 - ground.position.y)


# --- The world -----------------------------------------------------------------

## One frozen figure per snapshot of the wearer's last scan, seen through walls.
func _sync_ghosts(p: Actor) -> void:
	var wanted := p.visor.ghosts
	while _ghosts.size() > wanted.size():
		_ghosts.pop_back().queue_free()
	while _ghosts.size() < wanted.size():
		var mesh := CapsuleMesh.new()
		mesh.radius = Actor.BODY_RADIUS
		mesh.height = Actor.BODY_HEIGHT
		mesh.material = _see_through(p.visor.glass_color)
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_world.add_child(node)
		_ghosts.append(node)
	for i in wanted.size():
		var ghost: Dictionary = wanted[i]
		_ghosts[i].global_position = ghost.at + Vector3(0.0, Actor.BODY_HEIGHT * 0.5, 0.0)
		var mat: StandardMaterial3D = _ghosts[i].mesh.material
		mat.albedo_color.a = 0.5 * clampf(ghost.left / maxf(p.visor.ghost_time, 0.01), 0.0, 1.0)


## Everything that follows another actor: pulse rings, tag marks and glints.
func _sync_actors(p: Actor, around: Array[Actor]) -> void:
	var camera := get_viewport().get_camera_3d()
	var tagged := {}
	var glinting := {}
	for other in around:
		if not _heard.has(other):
			_heard[other] = true
			other.visor.pulsed.connect(_on_pulsed.bind(other.visor.scan_radius, other.visor.glass_color))
			other.tree_exiting.connect(func() -> void: _heard.erase(other))
		# Tags held by the wearer's side. Online the server only sends those.
		# Most visors hold no tags: ask that before the dearer question of sides.
		if not other.visor.tags.is_empty() and (other == p or not Combat.authoritative or Visor.allied(p, other)):
			for target: Variant in other.visor.tags:
				if is_instance_valid(target):
					tagged[target] = true
		if other != p and not other.is_dead and other.visor.is_zoomed() and camera != null:
			var eye := other.get_eye_position()
			var to_me := camera.global_position - eye
			if to_me.length() > 1.0 and other.get_aim_dir().dot(to_me.normalized()) >= glint_facing:
				glinting[other] = eye + to_me.normalized() * 0.4
	var embers := {}
	if camera != null:
		for other in around:
			if other != p and not other.is_dead and other.visor.thermal_on \
					and camera.global_position.distance_to(other.global_position) <= ember_range:
				embers[other] = true
	var sensed := {}
	for other in p.visor.threats:
		if is_instance_valid(other) and not other.is_dead:
			sensed[other] = true
	_tagged.clear()
	for target: Variant in tagged:
		if target is Actor and not (target as Actor).is_dead:
			_tagged.append(target)
	_sync_marks(_tag_marks, tagged, _new_tag_mark)
	_sync_marks(_glints, glinting, _new_glint)
	_sync_marks(_embers, embers, _new_ember)
	_sync_marks(_threat_marks, sensed, _new_threat_mark)
	for other: Actor in _embers:
		_embers[other].global_position = other.get_eye_position() + other.get_aim_dir() * 0.3
	for other: Actor in _threat_marks:
		_threat_marks[other].global_position = other.global_position + Vector3(0.0, Actor.BODY_HEIGHT * 0.5, 0.0)
	for target: Actor in _tag_marks:
		_tag_marks[target].global_position = target.global_position + Vector3(0.0, 2.5, 0.0)
	for other: Actor in _glints:
		var glint: MeshInstance3D = _glints[other]
		glint.global_position = glinting[other]
		# Far away a glint would be a single pixel: it grows with distance.
		var away: float = camera.global_position.distance_to(glint.global_position)
		glint.scale = Vector3.ONE * clampf(away * 0.03, 1.0, 9.0) * (0.8 + 0.2 * sin(_time * 23.0))


## Keeps one node in `marks` for every key of `wanted`, built by `make`.
func _sync_marks(marks: Dictionary, wanted: Dictionary, make: Callable) -> void:
	for key: Variant in marks.keys():
		if not wanted.has(key) or not is_instance_valid(key):
			marks[key].queue_free()
			marks.erase(key)
	for key: Variant in wanted:
		if not marks.has(key):
			var node: Node3D = make.call()
			_world.add_child(node)
			marks[key] = node


func _new_tag_mark() -> Node3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.28
	mesh.bottom_radius = 0.0
	mesh.height = 0.45
	mesh.radial_segments = 4
	mesh.material = _see_through(Color(1.0, 0.25, 0.15, 0.9))
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


func _new_glint() -> Node3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.07
	mesh.height = 0.14
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 1.0, 0.92)
	mesh.material = mat
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## The dull red point of a thermal visor that is switched on.
func _new_ember() -> Node3D:
	var node := _new_glint() as MeshInstance3D
	var mat: StandardMaterial3D = node.mesh.material
	mat.albedo_color = Color(1.0, 0.2, 0.08)
	return node


## The outline Threat Sense puts on someone aiming at the wearer.
func _new_threat_mark() -> Node3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = Actor.BODY_RADIUS
	mesh.height = Actor.BODY_HEIGHT
	mesh.material = _see_through(Color(1.0, 0.2, 0.12, 0.5))
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## Thermal: every living body in view gets a bright shell the heat picture
## turns hot. It is hidden by walls like the body it covers, and fog does
## not touch it. The hotter the body, the brighter the shell.
func _sync_heat(p: Actor, around: Array[Actor]) -> void:
	var warm := {}
	if thermal_shown:
		for other in around:
			if other != p and not other.is_dead \
					and other.global_position.distance_to(p.global_position) <= Visor.reach_to(other, INF):
				warm[other] = true
	_sync_marks(_heat, warm, _new_heat_shell)
	for other: Actor in _heat:
		var shell: MeshInstance3D = _heat[other]
		shell.global_position = other.global_position + Vector3(0.0, Actor.BODY_HEIGHT * 0.5, 0.0)
		var mat: StandardMaterial3D = shell.mesh.material
		mat.albedo_color.a = clampf(0.35 + 0.45 * Visor.heat_of(other), 0.0, 1.0)


func _new_heat_shell() -> Node3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = Actor.BODY_RADIUS * 0.95
	mesh.height = Actor.BODY_HEIGHT
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.disable_fog = true
	mat.albedo_color = Color(4.0, 4.0, 4.0, 1.0)
	mat.render_priority = 10
	mesh.material = mat
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


func _on_pulsed(origin: Vector3, radius: float, color: Color) -> void:
	if _world == null or not _world.is_inside_tree():
		return
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(color.r, color.g, color.b, 0.22)
	mesh.material = mat
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.add_child(node)
	node.global_position = origin
	_rings.append({"node": node, "age": 0.0, "radius": radius})


func _tick_rings(delta: float) -> void:
	for ring in _rings:
		ring.age += delta
		var done := clampf(ring.age / ring_time, 0.0, 1.0)
		var node: MeshInstance3D = ring.node
		node.scale = Vector3.ONE * maxf(0.5, ring.radius * done)
		var mat: StandardMaterial3D = node.mesh.material
		mat.albedo_color.a = 0.22 * (1.0 - done)
		if done >= 1.0:
			node.queue_free()
	_rings = _rings.filter(func(r: Dictionary) -> bool: return r.age < ring_time)


## A flat colour that shows through walls.
func _see_through(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.albedo_color = color
	return mat


# --- The glass -----------------------------------------------------------------
# A projected display, not a window frame: thin lines of light that hang in
# the view, drift a little behind it when you turn, sweep in when the visor
# comes on, sit dim while nothing is happening and brighten when something is.

func _draw() -> void:
	var flat := flat_shown()
	if not (glass_shown() or flat) or boot <= 0.0:
		return
	var p := _player()
	var v := p.visor
	var ink := v.glass_color
	var centre := size * 0.5 + sway
	# Even a failing scrap visor holds the emote wheel steady while it is up.
	_draw_emote_wheel(ink, centre)
	if v.mode == "":
		# A scrap visor's projector is failing: the picture drops out now and then.
		if sin(_time * 1.7) * sin(_time * 4.3) > 0.82:
			return
		if not flat:
			_draw_cracks(ink)
	if not flat:
		_draw_glass(ink)
		_draw_frost()
		_draw_ash()
		_draw_streaks()
	_draw_vitals(p, ink)
	_draw_landing(p)
	_draw_hunted(p)
	_draw_weapon(p, ink)
	_draw_ident(v, ink)
	if v.mode == "":
		_draw_heading(p, ink)
	else:
		_draw_reticle(ink, centre, v.mode)
		_draw_pitch(p, ink)
		_draw_compass(p, ink)
		_draw_scope(p, ink)
		_draw_objectives(p, ink)
	match v.mode:
		"zoom":
			_draw_lock(p, ink, "%d m" % roundi(range_reading) if range_reading >= 0.0 else "")
			_draw_range(ink, centre)
			_draw_system(ink, float(v.zoom_level) / maxf(v.zoom_levels.size(), 1.0),
					"OPTIC %dx" % roundi(v.zoom_factor()) if v.is_zoomed() else "OPTIC READY", v.is_zoomed())
			if zoom_shown > 0.01:
				_draw_binoculars(v, ink, centre)
		"scan":
			_draw_system(ink, 1.0 - clampf(v.cooldown_left / maxf(v.cooldown, 0.01), 0.0, 1.0),
					"SCAN READY" if v.cooldown_left <= 0.0 else "SCAN IN %d" % ceili(v.cooldown_left),
					v.cooldown_left <= 0.0)
			_draw_sweep(v, ink, centre)
		"threat":
			_draw_lock(p, ink, "")
			_draw_target(ink)
			_draw_loot(p, ink)
			if v.is_sensing():
				_draw_system(Color(1.0, 0.3, 0.2), v.active_left / maxf(v.threat_time, 0.01),
						"THREATS %d" % v.threats.size(), true)
			else:
				_draw_system(ink, 1.0 - clampf(v.cooldown_left / maxf(v.cooldown, 0.01), 0.0, 1.0),
						"SENSE READY" if v.cooldown_left <= 0.0 else "SENSE IN %d" % ceili(v.cooldown_left),
						v.cooldown_left <= 0.0)
		"thermal":
			_draw_system(ink, v.charge_fraction(), "THERMAL ON" if v.thermal_on else "CELL %d%%" %
					roundi(v.charge_fraction() * 100.0), v.thermal_on)
			_draw_signature(p, ink)
	_draw_comms(ink)
	_draw_crate(p, ink)
	_draw_pickups(p, ink)
	_draw_slivers(p, centre, felt, felt_time, Color(1.0, 0.2, 0.12), 0.4)
	_draw_slivers(p, centre, hit_marks, hit_mark_time, Color(1.0, 0.6, 0.1), 0.34)


## True while the quick emote wheel is drawn here, on the glass (or flat in
## third person, `flat_shown`): it is up and a helmet is working. Without
## one the wrist throws it as a hologram instead (`Hud.EmoteHolo`).
func emote_wheel_shown() -> bool:
	return controller != null and controller.emote_wheel_open and (glass_shown() or flat_shown())


## The quick emote wheel (`PlayerController.emote_wheel_open`): every emote
## round a ring about the middle of the view, the one pointed at lit with
## its slice of the ring and a line out to it from the middle.
func _draw_emote_wheel(ink: Color, centre: Vector2) -> void:
	if not emote_wheel_shown():
		return
	var radius := size.y * 0.17
	var count := Emotes.IDS.size()
	var picked := controller.emote_wheel_pick
	var slice := TAU / float(count)
	# A faint dark glass behind it, so the names read against a bright sky.
	draw_circle(centre, radius * 1.4, Color(0.0, 0.02, 0.04, 0.28 * boot))
	draw_arc(centre, radius * 0.32, 0.0, TAU, 48, _lit(ink, 0.35, false), 1.0, true)
	draw_arc(centre, radius * 1.18, 0.0, TAU, 96, _lit(ink, 0.18, false), 1.0, true)
	# The picked slice of the ring: drawn round from the top, clockwise.
	var mid := -PI * 0.5 + slice * float(picked)
	draw_arc(centre, radius * 1.18, mid - slice * 0.42, mid + slice * 0.42, 16, _lit(ink, 0.95, false), 3.0, true)
	var pull := controller.emote_wheel_aim
	if pull.length() >= controller.emote_wheel_dead:
		draw_line(centre + pull.normalized() * radius * 0.32, centre + pull.normalized() * radius * 0.9,
				_lit(ink, 0.6, false), 1.5, true)
	for i in count:
		var id: String = Emotes.IDS[i]
		var at := centre + Emotes.slice_dir(i) * radius
		var on := i == picked
		var label := Emotes.name_of(id).to_upper()
		if id == controller.emote_playing:
			label += " ·"
		_text(at + Vector2(0.0, 5.0), label, _lit(ink if on else ink.darkened(0.1), 1.0 if on else 0.8, false),
				HORIZONTAL_ALIGNMENT_CENTER, 140.0, 16 if on else 13)
	_text(centre + Vector2(0.0, radius * 1.18 + 24.0), "EMOTE", _lit(ink, 0.5, false), HORIZONTAL_ALIGNMENT_CENTER, 120.0, 11)


## True in third person while a working helmet's reticle is drawn (it is, as
## part of the flat readouts, `flat_shown`). The helmet's health and system
## light are also worn on the back of the head, for others (`ActorSkin`).
func reticle_shown() -> bool:
	var p := _player()
	return flat_shown() and p.visor.mode != ""


## The visor's colour at `alpha`, dimmed while the display is still coming
## on and while nothing needs the wearer's eye, the same in both views.
func _lit(ink: Color, alpha: float, ambient := true) -> Color:
	var level := boot * (lerpf(idle_dim, 1.0, alert) if ambient else 1.0)
	return Color(ink.r, ink.g, ink.b, clampf(alpha * level, 0.0, 1.0))


## How much of something to show while the display sweeps in.
func _swept() -> float:
	return ease(boot, 0.4)


## Small capitals, the way every readout is lettered. They type themselves in,
## with a faint dark halo so they read against a bright sky.
func _text(at: Vector2, text: String, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := 220.0,
		font_size := 13) -> void:
	var shown := text.substr(0, ceili(text.length() * _swept()))
	var from := at if align == HORIZONTAL_ALIGNMENT_LEFT else at - Vector2(width * (0.5 if align
			== HORIZONTAL_ALIGNMENT_CENTER else 1.0), 0.0)
	var font := ThemeDB.fallback_font
	draw_string_outline(font, from, shown, align, width, font_size, 3, Color(0.0, 0.02, 0.04, color.a * 0.45))
	draw_string(font, from, shown, align, width, font_size, color)


## A band of short ticks along an arc, turned by `turn` radians.
func _ticks(centre: Vector2, radius: float, from: float, to: float, step: float, length: float,
		color: Color, turn := 0.0) -> void:
	var angle := from + fposmod(turn, step)
	while angle <= to:
		var dir := Vector2(cos(angle), sin(angle))
		draw_line(centre + dir * radius, centre + dir * (radius + length), color, 1.0, true)
		angle += step


## The ability's state under the vitals: its name when ready, the seconds
## left while it runs or recharges, "" with none.
static func ability_text(ability: Ability) -> String:
	if not ability.enabled:
		return ""
	var name := ability.display_name.to_upper()
	if ability.is_active():
		return "%s %.1f" % [name, ability.active_left]
	if ability.cooldown_left > 0.0:
		return "%s %d" % [name, ceili(ability.cooldown_left)]
	return name


## A broken ring around the crosshair that turns slowly, and closes in when
## something is under it. Each helmet breaks it its own way: three arcs for
## recon, four for intel, two heavy brackets for tactical, six short ticks
## for thermal.
func _draw_reticle(ink: Color, centre: Vector2, mode := "") -> void:
	var locked := aim_target != null and is_instance_valid(aim_target)
	var radius := lerpf(30.0, 20.0, lock) * lerpf(2.2, 1.0, _swept())
	var turn := _time * (1.4 if locked else 0.35)
	var parts := {"scan": 4, "threat": 2, "thermal": 6}.get(mode, 3) as int
	var gap := {"threat": 1.3, "thermal": 0.75}.get(mode, 0.5) as float
	var width := 2.0 if mode == "threat" else 1.0
	for i in parts:
		var from := turn + TAU * i / parts
		draw_arc(centre, radius, from, from + TAU / parts - gap, 12, _lit(ink, 0.55 + 0.35 * lock), width, true)


## A plain visor has seen better days.
func _draw_cracks(ink: Color) -> void:
	var color := _lit(ink, 0.3)
	var from := Vector2(size.x * 0.13, size.y * 0.1)
	var unit := size.y * 0.05
	draw_polyline(PackedVector2Array([from, from + Vector2(1.4, 0.9) * unit, from + Vector2(1.7, 2.2) * unit,
			from + Vector2(3.0, 2.9) * unit]), color, 1.5, true)
	draw_polyline(PackedVector2Array([from + Vector2(1.4, 0.9) * unit, from + Vector2(2.8, 0.7) * unit,
			from + Vector2(3.6, 1.5) * unit]), color, 1.2, true)
	draw_polyline(PackedVector2Array([from + Vector2(1.7, 2.2) * unit, from + Vector2(0.9, 3.3) * unit]),
			color, 1.2, true)


## Frost on the glass as body heat runs low: fern-like ice creeping in from
## the corners, the middle always clear. The glass itself, so first person
## only; the body heat cell says the same in both views.
func _draw_frost() -> void:
	if frost <= 0.01:
		return
	var color := Color(0.85, 0.95, 1.0, 0.28 * frost)
	var unit := size.y * 0.24 * frost
	for corner: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		var at := Vector2(corner.x * size.x, corner.y * size.y)
		var inward := Vector2(1.0 - corner.x * 2.0, 1.0 - corner.y * 2.0)
		for k in 5:
			# Each frond grows from the corner's edge, branching as it goes.
			var start := at + Vector2(inward.x * size.y * 0.03 * k, inward.y * size.y * 0.06 * (4 - k))
			var dir := (inward.normalized()).rotated(0.5 - k * 0.25)
			var length := unit * (0.65 + 0.35 * sin(k * 2.3 + corner.x * 3.0 + corner.y * 5.0))
			var tip := start + dir * length
			draw_line(start, tip, color, 1.4, true)
			for b in 3:
				var on := start + dir * length * (0.3 + b * 0.22)
				var twig := length * (0.28 - b * 0.06)
				draw_line(on, on + dir.rotated(0.7) * twig, color, 1.0, true)
				draw_line(on, on + dir.rotated(-0.7) * twig, color, 1.0, true)


## How much ash a storm of `kind` this `strength` (0 to 1) settles on the
## glass: only an ash storm's (DESIGN.md "Weather: ash storms").
static func ash_settling(kind: String, strength: float) -> float:
	return clampf(strength, 0.0, 1.0) if kind == "ash" else 0.0


## Speck `i` of the ash on the glass: where it sits, in the glass's own
## frame (-1 to 1 each way, the middle 0), and its size (0 to 1). The same
## every frame, so ash builds up rather than shimmering, and never inside
## `ASH_CLEAR` of the middle.
static func ash_speck(i: int) -> Vector3:
	# Grains land in clumps of eight, each clump somewhere round the rim.
	var clump := RandomNumberGenerator.new()
	clump.seed = hash(int(i / 8) * 7919 + 31)
	var angle := clump.randf() * TAU
	# Thickest at the rim, thinning in toward the clear middle.
	var reach := lerpf(ASH_CLEAR + 0.08, 1.05, pow(clump.randf(), 0.4))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(i * 104729 + 7)
	var at := Vector2(cos(angle), sin(angle)) * reach + Vector2(rng.randf_range(-0.07, 0.07), rng.randf_range(-0.09, 0.09))
	# Kept off the middle, whatever the scatter did.
	if at.length() < ASH_CLEAR:
		at = at.normalized() * ASH_CLEAR
	return Vector3(at.x, at.y, rng.randf())


## Ash on the glass in an ash storm: dark grains and a few smears settling
## in from the rim, thickest there, the middle always clear. The glass
## itself, so first person only, like frost.
func _draw_ash() -> void:
	if ash <= 0.01:
		return
	var half := size * 0.5
	# A fine dusting first, darkest in the corners.
	for corner: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		var at := Vector2(corner.x * size.x, corner.y * size.y)
		for ring in 3:
			draw_circle(at, size.y * (0.16 + ring * 0.1), Color(0.18, 0.14, 0.12, 0.07 * ash))
	var shown := ash * ASH_SPECKS
	for i in ASH_SPECKS:
		if float(i) >= shown:
			break
		var speck := ash_speck(i)
		var at := half + Vector2(speck.x * half.x, speck.y * half.y)
		# Each grain darkens in as it lands rather than popping on.
		var landed := clampf(shown - i, 0.0, 1.0)
		var grain := size.y * (0.0018 + speck.z * speck.z * 0.0045)
		var dark := Color(0.2, 0.16, 0.14, 0.55 * landed)
		if i % 23 == 0:
			# A smear, dragged along by the wind across the glass.
			var drag := Vector2(grain * 7.0, grain * (speck.z - 0.5) * 2.0)
			draw_line(at - drag, at + drag, Color(dark, dark.a * 0.6), grain * 1.6, true)
		draw_circle(at, grain, dark)
		# Lit grit catches the light on its upper edge.
		draw_circle(at - Vector2(0, grain * 0.4), grain * 0.45, Color(0.85, 0.6, 0.45, 0.25 * landed))


## How strong the streaks across the glass are for a wearer moving at
## `speed` (m/s) off the ground through weather this `strength` (0 to 1) in
## air this `cold` (body heat a second): nothing on the ground or slow, and
## nothing in clear, warm air.
func streaks_wanted(speed: float, airborne: bool, strength: float, cold: float) -> float:
	if not airborne:
		return 0.0
	var fast := clampf((speed - streak_from) / maxf(streak_full - streak_from, 1.0), 0.0, 1.0)
	var weather := maxf(clampf(strength, 0.0, 1.0), streak_cold if cold > 0.0 else 0.0)
	return fast * weather


func _update_streaks(p: Actor, delta: float) -> void:
	var wanted := 0.0
	var speed := 0.0
	if p != null and raid != null and raid.world != null and controller != null and not controller.is_third_person():
		speed = p.velocity.length()
		var storm := raid.weather.strength_at(p.global_position) if raid.weather != null else 0.0
		var chill := raid.world.cold_at(p.global_position) if storm <= 0.0 else 0.0
		wanted = streaks_wanted(speed, FlightHolo.flying(p), storm, chill)
		if wanted > 0.0:
			var look := get_node_or_null("/root/Look")
			var kind := raid.world.weather_kind if storm > 0.0 and raid.world.weather_kind != "" else "snow"
			if look != null and look.has_method("weather_kit"):
				streak_ink = (look.call("weather_kit", kind) as Dictionary).get("streak", streak_ink)
	streaks = move_toward(streaks, wanted, delta * 2.0)
	_streak_run = clampf((speed - streak_from) / maxf(streak_full - streak_from, 1.0), 0.0, 1.0)
	_streak_clock += delta * (0.4 + 1.6 * _streak_run)


## The weather whipping across the glass at speed: thin streaks born near
## the clear middle and dragged out toward the rim, longer the faster you
## go. The glass itself, so first person only, like frost and ash.
func _draw_streaks() -> void:
	if streaks <= 0.01:
		return
	var half := size * 0.5
	var count := int(ceil(STREAKS * streaks))
	for i in count:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(i * 7907 + 13)
		var angle := rng.randf() * TAU
		var pace := rng.randf_range(0.7, 1.3)
		# Each one runs from the edge of the clear middle out past the rim, then again.
		var life := fposmod(_streak_clock * pace + rng.randf(), 1.0)
		var dir := Vector2(cos(angle), sin(angle))
		var reach := lerpf(ASH_CLEAR * 0.8, 1.15, life)
		var length := (0.04 + 0.16 * _streak_run) * rng.randf_range(0.6, 1.2)
		var a := half + Vector2(dir.x * half.x, dir.y * half.y) * reach
		var b := half + Vector2(dir.x * half.x, dir.y * half.y) * (reach + length)
		# Faint where it is born, strongest midway, gone at the rim.
		var fade := sin(life * PI) * streaks
		draw_line(a, b, Color(streak_ink, streak_ink.a * 0.8 * fade), 1.0 + rng.randf() * 1.2, true)


## Where the curved heading strip is at `off` degrees from straight ahead:
## it bows down toward its ends, the way the glass curves.
func _strip_point(off: float) -> Vector2:
	var share := clampf(off / strip_reach, -1.0, 1.0)
	return Vector2(size.x * 0.5 + sway.x + off * size.x * 0.0045,
			size.y * 0.075 + sway.y + share * share * size.y * strip_bow)


func _draw_strip_mark(p: Actor, ink: Color, mark: Dictionary, off: float, waiting: int) -> void:
	var off_strip := absf(off) > strip_reach
	var at := _strip_point(clampf(off, -strip_reach, strip_reach)) + Vector2(0.0, 34.0)
	at.x -= signf(off) * waiting * 70.0
	var away := roundi((mark.at as Vector3).distance_to(p.global_position))
	var tint: Color = {"squad": SQUAD_INK, "ping": PING_INK, "hot": HOT_INK, "tag": TAG_INK, "waypoint": WAYPOINT_INK, "storm": STORM_INK, "pile": PILE_INK, "bounty": BOUNTY_INK}.get(mark.kind, ink)
	var urgent: bool = mark.kind in ["tag", "contact", "ping"]
	var color := _lit(tint, 0.95 if not off_strip else 0.7, not urgent)
	match mark.kind:
		"squad":
			draw_colored_polygon(PackedVector2Array([at + Vector2(-6, 4), at + Vector2(6, 4), at + Vector2(0, -6)]), color)
		"depot":
			draw_rect(Rect2(at - Vector2(5, 5), Vector2(10, 10)), color, false, 1.5)
		"hot":
			var flicker := 0.7 + 0.3 * sin(_time * 4.0)
			draw_arc(at, 6.0, 0.0, TAU, 16, Color(color, color.a * flicker), 2.0, true)
			draw_circle(at, 2.0, color)
		"storm":
			# A slow swirl: two broken arcs turning.
			var turn := _time * 1.5
			draw_arc(at, 7.0, turn, turn + 2.2, 12, color, 1.5, true)
			draw_arc(at, 7.0, turn + PI, turn + PI + 2.2, 12, color, 1.5, true)
			draw_arc(at, 3.0, -turn, -turn + 2.6, 8, color, 1.5, true)
		"contact":
			draw_arc(at, 5.0, 0.0, TAU, 12, color, 1.5, true)
		"pile", "bounty":
			# A coin: a ring round a lit middle, a bounty's bigger.
			var big := 7.0 if mark.kind == "bounty" else 5.0
			draw_arc(at, big, 0.0, TAU, 14, color, 1.5, true)
			draw_circle(at, big * 0.45, color)
		_:
			# Pings and tags are diamonds.
			draw_colored_polygon(PackedVector2Array([at + Vector2(0, -6), at + Vector2(6, 0), at + Vector2(0, 6),
					at + Vector2(-6, 0)]), color)
	if off_strip:
		# Waiting at the end of the strip: a chevron says which way to turn.
		var side := signf(off)
		draw_polyline(PackedVector2Array([at + Vector2(side * 9.0, -5.0), at + Vector2(side * 14.0, 0.0),
				at + Vector2(side * 9.0, 5.0)]), color, 1.5, true)
	var label: String = mark.label
	label = "%d m" % away if label == "" else "%s %d m" % [label, away]
	_text(at + Vector2(0.0, 20.0), label, color, HORIZONTAL_ALIGNMENT_CENTER, 140.0, 11)


## A scrap visor's failing projector manages a bearing and nothing more.
func _draw_heading(p: Actor, ink: Color) -> void:
	var heading := bearing(p.cmd.yaw)
	_text(Vector2(size.x * 0.5, size.y * 0.08), "%03d %s" % [roundi(heading), compass_name(heading)],
			_lit(ink, 0.7), HORIZONTAL_ALIGNMENT_CENTER, 120.0)


## The helmet's name and role, typed in as it comes on and gone again
## once it has settled, under the heading strip.
func _draw_ident(v: Visor, ink: Color) -> void:
	if _since_boot > ident_time:
		return
	var fade := clampf((ident_time - _since_boot) / 0.6, 0.0, 1.0)
	var text := "%s · %s" % [v.display_name.to_upper(), role_name(v.mode)]
	_text(Vector2(size.x * 0.5 + sway.x, size.y * 0.2 + sway.y), text, _lit(ink, 0.9 * fade, false),
			HORIZONTAL_ALIGNMENT_CENTER, 400.0, 14)


## The look of the glass itself, never a frame or a tint: a faint scan line
## that rolls down the view, kept to the outer edges so the middle stays
## clear, and two thin glints where the curved glass catches the light.
func _draw_glass(ink: Color) -> void:
	var y := fposmod(_time / maxf(scanline_time, 0.1), 1.0) * size.y
	var line := _lit(ink, 0.06)
	draw_line(Vector2(0.0, y), Vector2(size.x * 0.2, y), line, 2.0)
	draw_line(Vector2(size.x * 0.8, y), Vector2(size.x, y), line, 2.0)
	var glint := _lit(Color(1.0, 1.0, 1.0), 0.05)
	var radius := size.y * 0.9
	draw_arc(Vector2(size.x * 0.5, size.y * 0.95) + sway * 0.5, radius, PI * 1.12, PI * 1.2, 24, glint, 2.0, true)
	draw_arc(Vector2(size.x * 0.5, size.y * 0.95) + sway * 0.5, radius, PI * 1.8, PI * 1.88, 24, glint, 2.0, true)


func _draw_range(ink: Color, centre: Vector2) -> void:
	_text(centre + Vector2(0.0, 58.0), "--- m" if range_reading < 0.0 else "%d m" % roundi(range_reading),
			_lit(ink, 0.9, false), HORIZONTAL_ALIGNMENT_CENTER, 120.0, 13)


## Where `target` stands on the screen, as a box around the body. Empty when
## it is behind the camera.
func _box_of(target: Actor) -> Rect2:
	var camera := get_viewport().get_camera_3d()
	var feet := target.global_position
	var head := feet + Vector3(0.0, Actor.BODY_HEIGHT + 0.1, 0.0)
	if camera == null or camera.is_position_behind(feet) or camera.is_position_behind(head):
		return Rect2()
	var top := camera.unproject_position(head)
	var bottom := camera.unproject_position(feet)
	var tall := maxf(bottom.y - top.y, 14.0)
	var wide := tall * 0.5
	return Rect2(Vector2((top.x + bottom.x) * 0.5 - wide * 0.5, top.y), Vector2(wide, tall))


## Four corner brackets that snap onto whoever is under the crosshair.
func _draw_lock(_p: Actor, ink: Color, note: String) -> void:
	if aim_target == null or not is_instance_valid(aim_target) or aim_target.is_dead:
		return
	var box := _box_of(aim_target)
	if box.size == Vector2.ZERO:
		return
	box = box.grow(lerpf(box.size.y * 0.6, 6.0, ease(lock, 0.3)))
	var arm := clampf(box.size.x * 0.3, 5.0, 26.0)
	var color := _lit(ink, 0.5 + 0.5 * lock, false)
	for corner: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		var at := box.position + box.size * corner
		var inward := Vector2(1.0 - 2.0 * corner.x, 1.0 - 2.0 * corner.y)
		draw_line(at, at + Vector2(arm * inward.x, 0.0), color, 1.5, true)
		draw_line(at, at + Vector2(0.0, arm * inward.y), color, 1.5, true)
	if note != "" and lock > 0.8:
		_text(Vector2(box.end.x + 8.0, box.position.y + 10.0), note, color)


## Looking through the binoculars: a wide ring opens around the view with a
## turning scale on it and marks for judging drop and lead. Nothing is
## blacked out.
func _draw_binoculars(v: Visor, ink: Color, centre: Vector2) -> void:
	var radius := size.y * 0.36 * lerpf(0.35, 1.0, ease(zoom_shown, 0.35))
	var color := _lit(ink, 0.7 * zoom_shown, false)
	draw_arc(centre, radius, 0.0, TAU, 96, _lit(ink, 0.35 * zoom_shown, false), 1.0, true)
	_ticks(centre, radius + 4.0, 0.0, TAU, TAU / 72.0, 5.0, _lit(ink, 0.45 * zoom_shown, false), _time * 0.12)
	_ticks(centre, radius + 4.0, 0.0, TAU, TAU / 12.0, 11.0, color, _time * 0.12)
	# Short hairlines at the ring only: the middle stays clear.
	for dir: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		draw_line(centre + dir * radius * 0.72, centre + dir * radius, color, 1.0, true)
	for step in range(1, 5):
		var down := radius * 0.14 * step
		draw_line(centre + Vector2(-6.0 + step, down), centre + Vector2(6.0 - step, down), color, 1.0, true)
	_text(centre + Vector2(radius * 0.74, radius * 0.74), "%.1fx" % v.zoom_factor(), color)


## A scan going out: a ring that races from the crosshair to the edge of the
## display, and a count of what came back.
func _draw_sweep(v: Visor, ink: Color, centre: Vector2) -> void:
	var since := v.cooldown - v.cooldown_left
	if v.cooldown_left > 0.0 and since < 0.6:
		var done := since / 0.6
		draw_arc(centre, size.y * 0.5 * ease(done, 0.5), 0.0, TAU, 96, _lit(ink, 0.8 * (1.0 - done), false),
				2.0, true)
	if not v.ghosts.is_empty():
		_text(centre + Vector2(0.0, 58.0), "%d CONTACT%s" % [v.ghosts.size(), "" if v.ghosts.size() == 1 else "S"],
				_lit(ink, 0.6 + 0.4 * sin(_time * 10.0), false), HORIZONTAL_ALIGNMENT_CENTER, 200.0, 13)


## Chevrons on the side something came from: a scan that caught the wearer,
## or a hit on a tactical visor.
func _draw_slivers(p: Actor, centre: Vector2, marks: Array[Dictionary], life: float, color: Color,
		radius_share: float) -> void:
	for mark in marks:
		var angle := angle_to(mark.origin, p.global_position, p.cmd.yaw) - PI * 0.5
		var alpha := clampf(mark.left / life, 0.0, 1.0)
		var tint := Color(color.r, color.g, color.b, alpha)
		var radius := size.y * radius_share * (1.0 + 0.06 * (1.0 - alpha))
		draw_arc(centre, radius, angle - 0.16, angle + 0.16, 16, tint, 2.5, true)
		draw_arc(centre, radius + 9.0, angle - 0.09, angle + 0.09, 12, Color(tint.r, tint.g, tint.b, alpha * 0.6),
				1.5, true)


## Tactical: the name, health and armor of whoever is under the crosshair,
## on a leader line beside their brackets.
func _draw_target(ink: Color) -> void:
	if read_target == null or not is_instance_valid(read_target) or read_target.is_dead:
		return
	var box := _box_of(read_target)
	if box.size == Vector2.ZERO:
		return
	var at := Vector2(box.end.x + 22.0, box.position.y + 4.0)
	var width := 110.0 * ease(lock, 0.4)
	var health := read_target.health
	draw_line(Vector2(box.end.x + 6.0, box.position.y + 10.0), at + Vector2(-4.0, 6.0), _lit(ink, 0.6, false), 1.0, true)
	_text(at + Vector2(0.0, -4.0), read_target.display_name.to_upper(), _lit(ink, 0.95, false))
	draw_rect(Rect2(at, Vector2(width, 3.0)), _lit(ink, 0.18, false))
	draw_rect(Rect2(at, Vector2(width * clampf(health.health / maxf(health.max_health, 1.0), 0.0, 1.0), 3.0)),
			Color(1.0, 0.3, 0.22, 0.95 * boot))
	if health.max_armor > 0.0:
		draw_rect(Rect2(at + Vector2(0.0, 6.0), Vector2(width, 2.0)), _lit(ink, 0.18, false))
		draw_rect(Rect2(at + Vector2(0.0, 6.0), Vector2(width * clampf(health.armor / health.max_armor, 0.0, 1.0),
				2.0)), Color(0.45, 0.7, 1.0, 0.95 * boot))


## What a tactical visor says about a container: its best item, and how
## many more there are. Empty for an empty one.
static func loot_text(items: Array) -> String:
	if items.is_empty():
		return ""
	var best: String = items[0]
	for id: String in items:
		if ItemDB.item_value(id) > ItemDB.item_value(best):
			best = id
	return ItemDB.item_name(best) if items.size() == 1 else "%s +%d" % [ItemDB.item_name(best), items.size() - 1]


## Tactical: a callout on every container close by, naming what is inside.
func _draw_loot(p: Actor, ink: Color) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	for node in get_tree().get_nodes_in_group("loot_containers"):
		var container := node as LootContainer
		# The one you are looking at has its full tag (`_draw_crate`).
		if container == null or container == looked or not Raid.together(container, p):
			continue
		var spot := container.global_position + Vector3(0.0, 0.9, 0.0)
		if spot.distance_to(p.global_position) > p.visor.loot_range or camera.is_position_behind(spot):
			continue
		var text := loot_text(container.items)
		if text == "":
			continue
		var at := camera.unproject_position(spot)
		var elbow := at + Vector2(26.0, -30.0)
		draw_circle(at, 2.5, _lit(ink, 0.9, false))
		draw_line(at, elbow, _lit(ink, 0.6, false), 1.0, true)
		draw_line(elbow, elbow + Vector2(120.0, 0.0), _lit(ink, 0.6, false), 1.0, true)
		_text(elbow + Vector2(4.0, -5.0), text.to_upper(), _lit(ink, 0.95, false), HORIZONTAL_ALIGNMENT_LEFT, 300.0)


# --- Loot: the container you look at and what you pick up -------------------------
# Every working helmet shows these, scrap visor included, in both views (Caleb's
# call: what you are about to pick up and what you just did, without the watch).
# The watch's pack is still where the pack is managed.

## The container the wearer is looking at, the one F would loot, or null.
## On a vehicle F gets you off, so nothing is looked at.
func looked_container(p: Actor) -> LootContainer:
	if p == null or p.is_dead or p.vehicle != null or not (glass_shown() or flat_shown()):
		return null
	var container := p.find_interactable() as LootContainer
	if container == null or not is_instance_valid(container) or container.is_queued_for_deletion():
		return null
	return container


## How item `id` compares with what is worn in the slot it would go in
## (`worn`, the wearer's `Actor.gear_items`): "up" if it is better or the
## slot is empty, "down" if worse, "same" for the same item or an equal one,
## and "" for anything that is not gear (materials, heals). Better is rarer,
## then worth more.
static func versus_worn(id: String, worn: Array) -> String:
	var slot := Loadout.slot_of(id)
	if slot == "":
		return ""
	var current := ""
	for other: String in worn:
		if Loadout.fits(slot, other):
			current = other
			break
	if current == "":
		return "up"
	if current == id:
		return "same"
	var ours := Vector2i(ItemDB.item_rarity(id), ItemDB.item_value(id))
	var theirs := Vector2i(ItemDB.item_rarity(current), ItemDB.item_value(current))
	if ours == theirs:
		return "same"
	return "up" if ours > theirs else "down"


## What a container holds, every item, stacked by kind: rarest first, then
## the most valuable. Each row is {"id", "name", "count", "rarity",
## "verdict"} (see `versus_worn`).
static func loot_rows(items: Array, worn: Array) -> Array[Dictionary]:
	var counts := {}
	var order: Array[String] = []
	for id: String in items:
		if not counts.has(id):
			order.append(id)
		counts[id] = counts.get(id, 0) + 1
	order.sort_custom(func(a: String, b: String) -> bool:
		var ra := ItemDB.item_rarity(a)
		var rb := ItemDB.item_rarity(b)
		if ra != rb:
			return ra > rb
		return ItemDB.item_value(a) > ItemDB.item_value(b))
	var rows: Array[Dictionary] = []
	for id in order:
		rows.append({"id": id, "name": ItemDB.item_name(id), "count": counts[id], "rarity": ItemDB.item_rarity(id),
				"verdict": versus_worn(id, worn)})
	return rows


## A row's text: its name in capitals, and how many when more than one.
static func row_text(name: String, count: int) -> String:
	return name.to_upper() if count <= 1 else "%s  x%d" % [name.to_upper(), count]


## The colour a rarity is drawn in on the glass.
static func rarity_ink(rarity: int) -> Color:
	return ItemDB.RARITY_COLORS[clampi(rarity, 0, ItemDB.RARITY_COLORS.size() - 1)]


## A small mark for how an item compares with what is worn: a green chevron
## up, a dim one down, a short bar for the same. Nothing for non-gear.
func _draw_verdict(verdict: String, at: Vector2, alpha: float) -> void:
	match verdict:
		"up":
			draw_colored_polygon(PackedVector2Array([at + Vector2(-5.0, 3.0), at + Vector2(0.0, -4.0),
					at + Vector2(5.0, 3.0)]), Color(SQUAD_INK, alpha))
		"down":
			draw_colored_polygon(PackedVector2Array([at + Vector2(-4.0, -3.0), at + Vector2(4.0, -3.0),
					at + Vector2(0.0, 3.0)]), Color(1.0, 0.45, 0.35, alpha * 0.8))
		"same":
			draw_line(at + Vector2(-4.0, 0.0), at + Vector2(4.0, 0.0), Color(1.0, 1.0, 1.0, alpha * 0.6), 2.0)


## The tag on the container you are looking at: a dot on it and a thin
## leader out to the side, clear of the crosshair, then its name, how many
## things and their worth, and every item inside on a row of its own (Caleb's
## call: all of them), each with a hex bullet in its rarity's colour, its
## name (the Mk is in the name), its rarity and whether it beats what you
## wear. A long list runs on into a second column rather than being cut.
func _draw_crate(p: Actor, ink: Color) -> void:
	if looked == null or not is_instance_valid(looked) or crate_shown <= 0.0:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var spot := looked.global_position + Vector3(0.0, 0.85, 0.0)
	if camera.is_position_behind(spot):
		return
	var rows := loot_rows(looked.items, p.gear_items)
	var shown := ease(crate_shown, 0.5) * _swept()
	var row_h := 19.0
	var col_w := 250.0
	var columns := 1 if rows.size() <= crate_rows else 2
	var per_column := ceili(rows.size() / float(columns))
	var listed := mini(rows.size(), maxi(per_column, 1))
	var tall := 30.0 + row_h * maxi(listed, 1) + (row_h if looked.scrip > 0 else 0.0)
	var wide := col_w * columns
	var anchor := camera.unproject_position(spot)
	var middle := size * 0.5
	# Out to whichever side the container is on, never over the middle.
	var right_side := anchor.x >= middle.x - 30.0
	# Far enough out to clear the loot prompt under the crosshair too.
	var x := maxf(anchor.x + 60.0, middle.x + 170.0) if right_side else minf(anchor.x - 60.0, middle.x - 170.0) - wide
	x = clampf(x, size.y * 0.06, size.x - size.y * 0.06 - wide)
	var top := clampf(anchor.y - 40.0, size.y * 0.16, size.y * 0.8 - tall)
	var near := Vector2(x if right_side else x + wide, top + 8.0)
	var line := _lit(ink, 0.6 * shown, false)
	draw_circle(anchor, 2.5, _lit(ink, 0.9 * shown, false))
	draw_line(anchor, near, line, 1.0, true)
	draw_line(Vector2(x, top + 8.0), Vector2(x + wide * shown, top + 8.0), line, 1.0, true)
	var title := looked.label.to_upper()
	var count := looked.items.size()
	var note := "EMPTY" if count == 0 and looked.scrip <= 0 else "%d ITEM%s  ·  WORTH %d" % [count,
			"" if count == 1 else "S", ItemDB.total_value(looked.items)]
	_text(Vector2(x + 2.0, top + 3.0), title, _lit(ink, 0.95 * shown, false), HORIZONTAL_ALIGNMENT_LEFT, col_w, 14)
	_text(Vector2(x + wide - 2.0, top + 3.0), note, _lit(ink, 0.6 * shown, false), HORIZONTAL_ALIGNMENT_RIGHT,
			col_w, 12)
	var y0 := top + 28.0
	for i in rows.size():
		var row: Dictionary = rows[i]
		var column := floori(i / float(per_column))
		var cx := x + column * col_w
		var y := y0 + (i % per_column) * row_h
		# Each row comes up a moment after the one above it.
		var rise := clampf(crate_shown * 3.0 - float(i % per_column) / maxf(listed, 1.0), 0.0, 1.0) * _swept()
		if rise <= 0.0:
			continue
		var tint := rarity_ink(int(row.rarity))
		draw_colored_polygon(hex_points(Vector2(cx + 7.0, y - 4.0), 5.0), Color(tint, 0.9 * rise * boot))
		_text(Vector2(cx + 18.0, y), row_text(str(row.name), int(row.count)), Color(Color.WHITE.lerp(tint, 0.35),
				0.95 * rise * boot), HORIZONTAL_ALIGNMENT_LEFT, col_w - 92.0, 13)
		_text(Vector2(cx + col_w - 22.0, y), ItemDB.RARITY_NAMES[int(row.rarity)].to_upper(),
				Color(tint, 0.75 * rise * boot), HORIZONTAL_ALIGNMENT_RIGHT, 70.0, 10)
		_draw_verdict(str(row.verdict), Vector2(cx + col_w - 10.0, y - 4.0), rise * boot)
	if looked.scrip > 0:
		var y := y0 + listed * row_h
		draw_circle(Vector2(x + 7.0, y - 4.0), 3.0, Color(HOT_INK, 0.9 * shown * boot))
		_text(Vector2(x + 18.0, y), "%d SCRIP" % looked.scrip, Color(HOT_INK, 0.95 * shown * boot),
				HORIZONTAL_ALIGNMENT_LEFT, col_w - 30.0, 13)


## The pickup feed, bottom right over the weapon readout: a line for each
## kind of thing just picked up ("+ ARC BLADE MK3  x2") in its rarity's
## colour, a chevron where it beats what you wear, newest at the bottom,
## sliding in and fading after a few seconds.
func _draw_pickups(p: Actor, ink: Color) -> void:
	if pickups.is_empty():
		return
	var radius := cell_radius()
	var right := size.x - size.y * vitals_left + sway.x
	var bottom := size.y * vitals_low + sway.y + radius * 0.3 - radius * 2.2 - 30.0
	var row_h := 21.0
	var font := ThemeDB.fallback_font
	for i in pickups.size():
		var line: Dictionary = pickups[pickups.size() - 1 - i]
		var alpha := clampf(float(line.left) / maxf(pickup_fade, 0.01), 0.0, 1.0) * _swept()
		var slide := 1.0 - ease(clampf(float(line.age) / maxf(pickup_slide, 0.01), 0.0, 1.0), 0.4)
		var y := bottom - i * row_h
		var x := right + slide * 40.0
		var rarity := ItemDB.item_rarity(line.id)
		var tint := rarity_ink(rarity)
		var text := "+ " + row_text(ItemDB.item_name(line.id), int(line.count))
		var verdict := versus_worn(line.id, p.gear_items)
		var mark_room := 16.0 if verdict == "up" else 0.0
		_text(Vector2(x - mark_room, y), text, Color(Color.WHITE.lerp(tint, 0.45), 0.95 * alpha),
				HORIZONTAL_ALIGNMENT_RIGHT, 320.0, 15)
		if verdict == "up":
			_draw_verdict("up", Vector2(x - 5.0, y - 5.0), alpha)
		var text_w := minf(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x, 320.0)
		draw_line(Vector2(x - mark_room - text_w, y + 5.0), Vector2(x, y + 5.0), Color(tint, 0.35 * alpha), 1.0)
		draw_colored_polygon(hex_points(Vector2(x - mark_room - text_w - 10.0, y - 5.0), 4.0), Color(tint, 0.9 * alpha))


# --- The layout around the edges --------------------------------------------------
# Everything hugs the rim of the glass and the middle stays clear. Each
# helmet keeps its own glass colour; nothing here is a box laid over the view.

## Where the vitals cell at `slot` (0 the leftmost, fractions between)
## sits: along the lower left curve of the glass, lifting toward the left
## edge the way the visor curves, so they follow its rim, not a straight row.
func cell_point(slot: float) -> Vector2:
	var radius := cell_radius()
	var x := size.y * vitals_left + slot * radius * 2.3
	var from_middle := clampf((size.x * 0.5 - x) / maxf(size.x * 0.5, 1.0), 0.0, 1.0)
	return Vector2(x, size.y * vitals_low - from_middle * from_middle * size.y * vitals_lift) + sway


func cell_radius() -> float:
	return clampf(size.y * 0.028, 18.0, 40.0)


## A flat-topped hexagon's corners.
static func hex_points(at: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 6:
		var angle := TAU * i / 6.0
		points.append(at + Vector2(cos(angle), sin(angle)) * radius)
	return points


## A hex cell, outlined, filled from the bottom by `share` (0 to 1).
func _hex_cell(at: Vector2, radius: float, share: float, color: Color, fill_alpha: float) -> void:
	var hex := hex_points(at, radius)
	var closed := hex.duplicate()
	closed.append(hex[0])
	draw_colored_polygon(hex, Color(color.r, color.g, color.b, color.a * 0.08))
	if share > 0.0:
		var top := at.y + radius - 2.0 * radius * clampf(share, 0.0, 1.0)
		var cut := PackedVector2Array([Vector2(at.x - radius * 2.0, top), Vector2(at.x + radius * 2.0, top),
				Vector2(at.x + radius * 2.0, at.y + radius * 2.0), Vector2(at.x - radius * 2.0, at.y + radius * 2.0)])
		for part in Geometry2D.intersect_polygons(hex_points(at, radius - 3.0), cut):
			draw_colored_polygon(part, Color(color.r, color.g, color.b, color.a * fill_alpha))
	draw_polyline(closed, color, 1.5, true)


## A line glyph for a vitals cell, drawn in `color` around `at`.
func _glyph(kind: String, at: Vector2, unit: float, color: Color) -> void:
	var pts := func(list: Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		for point: Vector2 in list:
			out.append(at + point * unit)
		return out
	match kind:
		"health":
			draw_polyline(pts.call([Vector2(-1, 0), Vector2(-0.35, 0), Vector2(-0.1, -0.7), Vector2(0.25, 0.7),
					Vector2(0.45, 0), Vector2(1, 0)]), color, 2.0, true)
		"armor":
			var shield: PackedVector2Array = pts.call([Vector2(0, -0.95), Vector2(0.8, -0.6), Vector2(0.65, 0.35),
					Vector2(0, 0.95), Vector2(-0.65, 0.35), Vector2(-0.8, -0.6), Vector2(0, -0.95)])
			draw_polyline(shield, color, 2.0, true)
		"stamina":
			draw_polyline(pts.call([Vector2(0.35, -1), Vector2(-0.4, 0.1), Vector2(0.4, 0.1), Vector2(-0.35, 1)]),
					color, 2.0, true)
		"heat":
			draw_polyline(pts.call([Vector2(-0.6, 0.8), Vector2(-0.7, 0.1), Vector2(-0.25, -0.35), Vector2(-0.1, 0.1),
					Vector2(0.15, -0.95), Vector2(0.65, -0.1), Vector2(0.6, 0.8), Vector2(-0.6, 0.8)]), color, 2.0, true)
		"body_heat":
			# A snowflake: three crossed strokes with a tick at each end.
			for k in 3:
				var dir := Vector2.from_angle(PI / 2.0 + k * PI / 3.0)
				draw_line(at - dir * unit * 0.9, at + dir * unit * 0.9, color, 2.0, true)
				for end: float in [-1.0, 1.0]:
					var tip := at + dir * unit * 0.6 * end
					draw_line(tip, tip + dir.rotated(PI * 0.75 * end) * unit * 0.3 * end, color, 1.5, true)
					draw_line(tip, tip + dir.rotated(-PI * 0.75 * end) * unit * 0.3 * end, color, 1.5, true)
		"ability":
			draw_arc(at, unit * 0.8, 0.0, TAU, 20, color, 2.0, true)
			draw_polyline(pts.call([Vector2(-0.4, 0), Vector2(0.45, 0)]), color, 2.0, true)
			draw_polyline(pts.call([Vector2(0.15, -0.3), Vector2(0.45, 0), Vector2(0.15, 0.3)]), color, 2.0, true)


## What the vitals cells show, left to right: {"kind", "share" (0 to 1),
## "value" (the number beside it), "label", "ink", "warn"}. Health always;
## armor with an armor frame; stamina always; body heat in a cold world;
## flight heat with a rig on; the ability with one fitted. These are your always-in-view readings: the
## watch no longer carries them.
func vital_cells(p: Actor, ink: Color) -> Array[Dictionary]:
	var cells: Array[Dictionary] = []
	var health := clampf(p.health.health / maxf(p.health.max_health, 1.0), 0.0, 1.0)
	var low := health < 0.35
	cells.append({"kind": "health", "share": health, "value": "%d%%" % roundi(health * 100.0),
			"label": "CRITICAL" if low else "HEALTH", "ink": Color(1.0, 0.25, 0.15) if low else ink, "warn": low})
	if p.health.max_armor > 0.0:
		var armor := clampf(p.health.armor / p.health.max_armor, 0.0, 1.0)
		cells.append({"kind": "armor", "share": armor, "value": "%d%%" % roundi(armor * 100.0),
				"label": "ARMOR", "ink": ARMOR_INK, "warn": false})
	var stamina := clampf(p.stamina / maxf(p.max_stamina, 1.0), 0.0, 1.0)
	cells.append({"kind": "stamina", "share": stamina, "value": "%d%%" % roundi(stamina * 100.0),
			"label": "STAMINA", "ink": ink, "warn": false})
	if Hud.feels_cold(p):
		var warmth := clampf(p.body_heat / maxf(p.max_body_heat, 1.0), 0.0, 1.0)
		var label := "BODY HEAT"
		var tint := BODY_HEAT_INK
		if p.warming:
			label = "WARMING"
			tint = WARMING_INK
		elif raid != null and raid.indoors_at(p.global_position) != null:
			# Out of the wind: still chilling, never hurting.
			label = "SHELTER"
		elif warmth <= 0.0:
			label = "FREEZING"
			tint = Color(1.0, 0.25, 0.15)
		elif p.shivering:
			label = "COLD"
		cells.append({"kind": "body_heat", "share": warmth, "value": "%d%%" % roundi(warmth * 100.0),
				"label": label, "ink": tint, "warn": label == "COLD" or label == "FREEZING"})
	var rig := p.flight
	if rig.enabled:
		var heat := rig.heat_fraction()
		var cue := Hud.rig_text(p).to_upper()
		cells.append({"kind": "heat", "share": heat, "value": Hud.heat_text(rig),
				"label": cue if cue != "" else "RIG HEAT", "ink": Hud.heat_color(heat, rig.overheated),
				"warn": rig.overheated or heat > 0.6})
	var ability := p.ability
	if ability.enabled:
		var share := 1.0
		var value := "RDY"
		if ability.is_active():
			share = ability.active_left / maxf(ability.duration, 0.01)
			value = "%.1f" % ability.active_left
		elif ability.cooldown_left > 0.0:
			share = 1.0 - ability.cooldown_left / maxf(ability.cooldown, 0.01)
			value = str(ceili(ability.cooldown_left))
		cells.append({"kind": "ability", "share": clampf(share, 0.0, 1.0), "value": value,
				"label": ability.display_name.to_upper(), "ink": ink, "warn": false})
	return cells


## The vitals: a short row of hex cells along the lower left curve of the
## glass, each filling like a gauge, its number beside it. Hurt, the health
## cell goes red and beats.
func _draw_vitals(p: Actor, ink: Color) -> void:
	var cells := vital_cells(p, ink)
	var radius := cell_radius()
	var swept := _swept()
	for i in cells.size():
		var cell: Dictionary = cells[i]
		# Health sits highest, by the left edge; the rest run down the rim
		# toward the bottom. Booting, they slide out along it from the edge.
		var at := cell_point(lerpf(-1.5, float(i), swept))
		var warn: bool = cell.warn
		var beat := 0.6 + 0.4 * sin(_time * 9.0) if warn and cell.kind == "health" else 1.0
		var color := _lit(cell.ink, 0.85 * beat, not warn)
		_hex_cell(at, radius, float(cell.share) * swept, color, 0.4)
		_glyph(cell.kind, at, radius * 0.42, _lit(Color.WHITE.lerp(cell.ink, 0.35), 0.9 * beat, not warn))
		# The number over the cell, and its name under it.
		_text(at + Vector2(0.0, -radius - 6.0), str(cell.value), color, HORIZONTAL_ALIGNMENT_CENTER, 100.0,
				roundi(radius * 0.6))
		_text(at + Vector2(0.0, radius + 14.0), str(cell.label), _lit(cell.ink, 0.65, not warn),
				HORIZONTAL_ALIGNMENT_CENTER, 110.0, 11)
	if altitude >= 0.0:
		var top := cell_point(0.0) + Vector2(-radius, -radius * 2.6)
		_text(top, "ALT %d m" % roundi(altitude), _lit(ink, 0.9, false), HORIZONTAL_ALIGNMENT_LEFT, 140.0, 13)
		var climb := clampf(p.velocity.y / 12.0, -1.0, 1.0)
		draw_line(top + Vector2(-8.0, -4.0), top + Vector2(-8.0, -4.0 - 14.0 * climb), _lit(ink, 0.9, false), 2.0, true)


## The landing warning (DESIGN.md "Flight HUD"): chevrons pointing down
## at the bottom of the glass, beating faster the closer the rig is to
## cutting out, with what is wrong and how far the ground is over them.
## Kept to the lower rim so the middle of the view stays clear; a scrap
## visor shows it too, since it only needs the ground under you.
func _draw_landing(p: Actor) -> void:
	if landing <= 0.0:
		return
	var beat := 0.55 + 0.45 * sin(_time * lerpf(6.0, 14.0, landing))
	var color := Color(TAG_INK.r, TAG_INK.g, TAG_INK.b, boot * lerpf(0.5, 1.0, beat))
	var at := Vector2(size.x * 0.5, size.y * landing_low) + sway
	var wide := clampf(size.y * 0.022, 12.0, 30.0)
	for i in 3:
		var tip := at + Vector2(0.0, (i - 1) * wide * 0.6)
		var shade := Color(color, color.a * (0.45 + 0.275 * i))
		draw_polyline(PackedVector2Array([tip + Vector2(-wide, -wide * 0.45), tip,
				tip + Vector2(wide, -wide * 0.45)]), shade, 3.0, true)
	var words := Hud.landing_reason(p.flight) + "   LAND"
	if altitude >= 0.0:
		words += "   GROUND %d m" % roundi(altitude)
	_text(at + Vector2(0.0, -wide * 1.6), words, color, HORIZONTAL_ALIGNMENT_CENTER, 420.0, 14)


## What the tag says while an army hunts the wearer for a grudge
## (`Actor.hunted_by`), or "" for none.
static func hunted_text(p: Actor) -> String:
	if p == null or p.hunted_by == "":
		return ""
	var world := Worlds.of(p)
	var army := world.faction_title(p.hunted_by) if world else p.hunted_by
	return "%s IS HUNTING YOU" % army.to_upper()


## A small tag under the heading tape while an army hunts the wearer, beating
## slowly: told, never where they are.
func _draw_hunted(p: Actor) -> void:
	var words := hunted_text(p)
	if words == "":
		return
	var beat := 0.7 + 0.3 * sin(_time * 3.0)
	var color := Color(TAG_INK.r, TAG_INK.g, TAG_INK.b, boot * beat)
	_text(Vector2(size.x * 0.5, size.y * 0.15) + sway, words, color, HORIZONTAL_ALIGNMENT_CENTER, 420.0, 13)


## Faint pitch ticks up both edges of the glass, sliding as the head tips,
## with where the view points marked at the middle.
func _draw_pitch(p: Actor, ink: Color) -> void:
	var degrees := rad_to_deg(p.cmd.pitch)
	var per := size.y * pitch_scale
	var mid := size.y * 0.5 + sway.y
	var band := size.y * 0.23 * _swept()
	for side: float in [-1.0, 1.0]:
		var edge := size.y * 0.035 + sway.x if side < 0.0 else size.x - size.y * 0.035 + sway.x
		var first := int(floor((degrees - band / per) / 5.0)) * 5
		var mark := first
		while mark <= degrees + band / per + 5.0:
			var y := mid - (mark - degrees) * per
			var off := absf(y - mid)
			if off <= band:
				var fade := 1.0 - off / maxf(band, 1.0)
				var major := posmod(mark, 15) == 0
				var length := 16.0 if major else 7.0
				var from := Vector2(edge, y)
				var to := from + Vector2(-side * length, 0.0)
				draw_line(from, to, _lit(ink, (0.5 if major else 0.3) * fade), 1.5 if major else 1.0, true)
				if major and mark != 0:
					_text(to + Vector2(-side * 6.0, 4.0), "%+d" % mark,
							_lit(ink, 0.45 * fade), HORIZONTAL_ALIGNMENT_RIGHT if side > 0.0 else HORIZONTAL_ALIGNMENT_LEFT,
							60.0, 11)
			mark += 5
		var caret := Vector2(edge - side * 22.0, mid)
		draw_colored_polygon(PackedVector2Array([caret, caret + Vector2(-side * 9.0, -5.0),
				caret + Vector2(-side * 9.0, 5.0)]), _lit(SQUAD_INK, 0.85))
		_text(caret + Vector2(-side * 14.0, 5.0), "%+d" % roundi(degrees),
				_lit(SQUAD_INK, 0.85), HORIZONTAL_ALIGNMENT_RIGHT if side > 0.0 else HORIZONTAL_ALIGNMENT_LEFT, 60.0, 13)


## A strip of bearings across the top that slides as the wearer turns, bowed
## with the glass, with what the helmet knows marked under it
## (`compass_marks`): squad, pings and the nearest depot on every working
## visor, and the helmet's own finds. Bearings are numbered every 15 degrees,
## the eight winds named, and the heading is read out in a notch under the
## middle. Something off the strip waits at its end, pointing.
func _draw_compass(p: Actor, ink: Color) -> void:
	var heading := bearing(p.cmd.yaw)
	var reach := strip_reach * _swept()
	var first := int(floor((heading - strip_reach) / 5.0)) * 5
	for mark in range(first, first + int(strip_reach * 2.0) + 5, 5):
		var off := mark - heading
		if absf(off) > reach:
			continue
		# Marks fade toward the ends of the strip.
		var color := _lit(ink, 0.85 * (1.0 - absf(off) / (strip_reach + 5.0)))
		var at := _strip_point(off)
		var major := posmod(mark, 15) == 0
		draw_line(at, at + Vector2(0.0, 9.0 if major else 4.0), color, 1.5 if major else 1.0, true)
		if major:
			var name := compass_name(posmod(mark, 360)) if posmod(mark, 45) == 0 else "%03d" % posmod(mark, 360)
			_text(at + Vector2(0.0, -5.0), name, color, HORIZONTAL_ALIGNMENT_CENTER, 60.0,
					14 if posmod(mark, 45) == 0 else 11)
	# The heading in a notch under the middle, a thin bracket open at the top.
	var mid := _strip_point(0.0) + Vector2(0.0, 13.0)
	draw_colored_polygon(PackedVector2Array([mid, mid + Vector2(-5.0, 6.0), mid + Vector2(5.0, 6.0)]), _lit(ink, 0.9))
	var notch := PackedVector2Array([mid + Vector2(-26.0, 8.0), mid + Vector2(-26.0, 26.0), mid + Vector2(26.0, 26.0),
			mid + Vector2(26.0, 8.0)])
	draw_polyline(notch, _lit(ink, 0.55), 1.0, true)
	_text(mid + Vector2(0.0, 22.0), "%03d" % roundi(heading), _lit(ink, 0.95), HORIZONTAL_ALIGNMENT_CENTER, 52.0, 15)
	# Marks off the strip queue at its ends, inward, so they never sit on each other.
	var queued := {-1.0: 0, 1.0: 0}
	for mark in compass_marks(p):
		var off := rad_to_deg(angle_to(mark.at, p.global_position, p.cmd.yaw))
		var waiting := 0
		if absf(off) > strip_reach:
			waiting = queued[signf(off)]
			queued[signf(off)] += 1
		_draw_strip_mark(p, ink, mark, off, waiting)


## Where the contact scope sits, and its radius: top left, in the corner of
## the glass.
func scope_rect() -> Rect2:
	var radius := clampf(size.y * 0.075, 48.0, 110.0)
	var at := Vector2(size.y * 0.05 + radius, size.y * 0.06 + radius) + sway
	return Rect2(at - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)


## Where each of the heading strip's marks lands on the contact scope: the
## wearer at the middle facing up, `scope_range` metres to the rim; further
## off it sits on the rim. {"mark", "at" (Vector2), "inside" (bool)}.
func scope_points(p: Actor) -> Array[Dictionary]:
	var rect := scope_rect()
	var centre := rect.get_center()
	var radius := rect.size.x * 0.5
	var out: Array[Dictionary] = []
	for mark in compass_marks(p):
		var flat := Vector2(mark.at.x - p.global_position.x, mark.at.z - p.global_position.z)
		var away := flat.length()
		var angle := angle_to(mark.at, p.global_position, p.cmd.yaw)
		var reach := minf(away / maxf(scope_range, 1.0), 1.0) * (radius - 6.0)
		out.append({"mark": mark, "at": centre + Vector2(sin(angle), -cos(angle)) * reach,
				"inside": away <= scope_range})
	return out


## The contact scope: a small round plot of what the heading strip already
## marks (squad, pings, the depot and the helmet's finds) around the wearer,
## turned so ahead is up. It is not a map: no ground, walls or roads, which
## stay on the watch. The squad's size rides on its rim.
func _draw_scope(p: Actor, ink: Color) -> void:
	var rect := scope_rect()
	var centre := rect.get_center()
	var radius := rect.size.x * 0.5 * lerpf(0.4, 1.0, _swept())
	draw_arc(centre, radius, 0.0, TAU, 64, _lit(ink, 0.5), 1.5, true)
	draw_arc(centre, radius * 0.6, 0.0, TAU, 48, _lit(ink, 0.16), 1.0, true)
	draw_arc(centre, radius * 0.25, 0.0, TAU, 32, _lit(ink, 0.14), 1.0, true)
	# Rim ticks turn with the heading; north gets its letter.
	var turn := -deg_to_rad(bearing(p.cmd.yaw))
	_ticks(centre, radius - 5.0, -PI, PI, TAU / 24.0, 5.0, _lit(ink, 0.35), turn - PI * 0.5)
	var north := centre + Vector2(sin(turn), -cos(turn)) * (radius + 9.0)
	_text(north + Vector2(-20.0, 4.0), "N", _lit(ink, 0.8), HORIZONTAL_ALIGNMENT_CENTER, 40.0, 11)
	# The view's cone and a slow sweep.
	for edge: float in [-0.6, 0.6]:
		draw_line(centre, centre + Vector2(sin(edge), -cos(edge)) * radius, _lit(ink, 0.18), 1.0, true)
	var sweep := fposmod(_time * 1.3, TAU)
	draw_arc(centre, radius * 0.55, sweep, sweep + 0.5, 12, _lit(ink, 0.1), radius * 0.9, false)
	draw_colored_polygon(PackedVector2Array([centre + Vector2(0, -6), centre + Vector2(4.5, 5),
			centre + Vector2(-4.5, 5)]), _lit(ink, 0.95))
	for point in scope_points(p):
		var mark: Dictionary = point.mark
		var tint: Color = {"squad": SQUAD_INK, "ping": PING_INK, "hot": HOT_INK, "tag": TAG_INK, "waypoint": WAYPOINT_INK, "storm": STORM_INK, "pile": PILE_INK, "bounty": BOUNTY_INK}.get(mark.kind, ink)
		var color := _lit(tint, 0.95 if point.inside else 0.55, mark.kind not in ["tag", "contact", "ping"])
		var at: Vector2 = point.at
		if not point.inside:
			var dir := (at - centre).normalized()
			draw_line(centre + dir * (radius - 2.0), centre + dir * (radius + 5.0), color, 2.0, true)
			continue
		match mark.kind:
			"squad":
				draw_polyline(PackedVector2Array([at + Vector2(-5, 4), at + Vector2(5, 4), at + Vector2(0, -5),
						at + Vector2(-5, 4)]), color, 1.5, true)
			"depot":
				draw_rect(Rect2(at - Vector2(4, 4), Vector2(8, 8)), color, false, 1.5)
			"contact":
				draw_arc(at, 4.0, 0.0, TAU, 10, color, 1.5, true)
			"pile", "bounty":
				draw_arc(at, 4.0, 0.0, TAU, 10, color, 1.5, true)
				draw_circle(at, 1.8, color)
			_:
				draw_colored_polygon(PackedVector2Array([at + Vector2(0, -5), at + Vector2(5, 0), at + Vector2(0, 5),
						at + Vector2(-5, 0)]), color)
	# The rim's readouts: the squad on the lower left of it, the range on the right.
	var lower := centre + Vector2(0.0, radius + 18.0)
	if not squad.is_empty():
		_text(lower + Vector2(-radius - 10.0, 0.0), "SQUAD %d" % (squad.size() + 1), _lit(SQUAD_INK, 0.85),
				HORIZONTAL_ALIGNMENT_LEFT, 120.0, 12)
	_text(lower + Vector2(radius + 10.0, 0.0), "%d M" % roundi(scope_range), _lit(ink, 0.5),
			HORIZONTAL_ALIGNMENT_RIGHT, 90.0, 11)


## Beside the scope: the helmet's name and role, and its system. How full the
## bar is shows a recharge, a battery or time left; `lit` means it is ready
## or running.
func _draw_system(ink: Color, share: float, text: String, lit: bool) -> void:
	var p := _player()
	var rect := scope_rect()
	var at := Vector2(rect.end.x + 22.0, rect.position.y + rect.size.y * 0.3)
	var width := 190.0 * _swept()
	var glow := 0.75 + 0.25 * sin(_time * 5.0) if lit else 0.6
	_text(at, p.visor.display_name.to_upper() if p != null else "", _lit(ink, 0.95), HORIZONTAL_ALIGNMENT_LEFT, 190.0, 16)
	_text(at + Vector2(0.0, 15.0), role_name(p.visor.mode) if p != null else "", _lit(ink, 0.5),
			HORIZONTAL_ALIGNMENT_LEFT, 190.0, 11)
	var bar := at + Vector2(0.0, 26.0)
	draw_line(bar, bar + Vector2(width, 0.0), _lit(ink, 0.2), 3.0)
	if share > 0.0:
		draw_line(bar, bar + Vector2(width * clampf(share, 0.0, 1.0), 0.0), _lit(ink, 0.9 * glow, not lit), 3.0)
	# Hash marks every tenth, so the bar reads as a gauge, not a loading bar.
	for i in range(1, 10):
		var x := bar.x + width * i / 10.0
		draw_line(Vector2(x, bar.y + 3.0), Vector2(x, bar.y + 6.0), _lit(ink, 0.25), 1.0)
	_text(bar + Vector2(0.0, 22.0), text, _lit(ink, 0.9, not lit), HORIZONTAL_ALIGNMENT_LEFT, 190.0, 13)


## Thermal: how warm the wearer looks to another thermal visor, under the
## helmet's system, so an Ember wearer knows when their own rig gives them away.
func _draw_signature(p: Actor, ink: Color) -> void:
	var heat := Visor.heat_of(p)
	var hot := heat >= 1.2
	var rect := scope_rect()
	var at := Vector2(rect.end.x + 22.0, rect.position.y + rect.size.y * 0.3 + 66.0)
	_text(at, signature_text(heat), _lit(HOT_INK if hot else ink, 0.85, not hot), HORIZONTAL_ALIGNMENT_LEFT, 220.0, 12)


## What the objective block lists, in order: {"title", "have", "goal",
## "share", "done", "tour", "main"}. The main mission first, then the
## contracts held, nearest done first, with this life's counts on top, then
## the new player's tour objective. Only what is
## tracked (the watch's mission log, `GameSettings.is_tracked`).
func objective_lines(held: Array[Dictionary], tally: Dictionary, objective: String,
		tour_key := GameSettings.TOUR_KEY) -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	for entry in held:
		if not GameSettings.is_tracked(str(entry.get("id", ""))):
			continue
		var have: int = int(entry.get("have", 0)) + Contracts.live(str(entry.get("stat", "")), tally)
		var goal: int = maxi(int(entry.get("goal", 1)), 1)
		lines.append({"title": str(entry.get("title", "")), "have": mini(have, goal), "goal": goal,
				"share": clampf(float(have) / goal, 0.0, 1.0), "done": have >= goal, "tour": false,
				"main": str(entry.get("id", "")) == GameSettings.main_mission})
	lines.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.share > b.share)
	if objective != "" and (tour_key == "" or GameSettings.is_tracked(tour_key)):
		lines.append({"title": objective, "have": 0, "goal": 0, "share": -1.0, "done": false, "tour": true,
				"main": tour_key != "" and tour_key == GameSettings.main_mission})
	# The main mission (the watch's mission log) leads.
	for i in lines.size():
		if lines[i].main:
			lines.push_front(lines.pop_at(i))
			break
	return lines


## The objective block, top right: a thin bracket that draws itself along the
## top and down the right edge as the visor comes on, and under it one line per
## objective with a hex bullet, its progress as a thin bar and the count in
## colour. A finished one goes green; the tour's step is marked in the ping
## colour. Nothing is boxed in.
func _draw_objectives(p: Actor, ink: Color) -> void:
	if hud == null:
		return
	var held: Array[Dictionary] = []
	held.assign(hud.get("contracts") if hud.get("contracts") is Array else [])
	var objective := str(hud.get("objective")) if hud.get("objective") != null else ""
	var tour_key := GameSettings.TOUR_KEY
	if str(hud.get("race_line")) not in ["", "<null>"]:
		objective = str(hud.get("race_line"))
		tour_key = ""
	var lines := objective_lines(held, p.tally, objective, tour_key)
	if lines.is_empty():
		return
	var right := size.x - size.y * 0.06 + sway.x
	var width := clampf(size.x * 0.2, 260.0, 420.0)
	var top := size.y * 0.075 + sway.y
	var row := 36.0
	var drawn := _swept()
	var tall := 34.0 + row * lines.size()
	# The bracket: a rule along the top that runs out from the right, a tick
	# down at its far end, and a line down the right edge.
	draw_line(Vector2(right, top), Vector2(right - width * drawn, top), _lit(ink, 0.6), 1.5, true)
	draw_line(Vector2(right - width * drawn, top), Vector2(right - width * drawn, top + 7.0), _lit(ink, 0.6), 1.5, true)
	draw_line(Vector2(right, top), Vector2(right, top + tall * drawn), _lit(ink, 0.35), 1.0, true)
	draw_line(Vector2(right - 6.0, top + tall * drawn), Vector2(right, top + tall * drawn), _lit(ink, 0.35), 1.0, true)
	var contracts := held.size()
	_text(Vector2(right - width, top - 7.0), "OBJECTIVES" if contracts == 0 else "CONTRACTS", _lit(ink, 0.55),
			HORIZONTAL_ALIGNMENT_LEFT, 200.0, 12)
	if contracts > 0:
		_text(Vector2(right - 8.0, top - 7.0), "%d HELD" % contracts, _lit(ink, 0.55), HORIZONTAL_ALIGNMENT_RIGHT,
				150.0, 12)
	var y := top + 28.0
	for line in lines:
		var x := right - width
		var done: bool = line.done
		var tour: bool = line.tour
		var tint := SQUAD_INK if done else (PING_INK if tour else HOT_INK)
		var bullet := hex_points(Vector2(x + 6.0, y - 5.0), 6.0)
		if done:
			draw_colored_polygon(bullet, _lit(tint, 0.9, false))
		else:
			var closed := bullet.duplicate()
			closed.append(bullet[0])
			draw_polyline(closed, _lit(tint, 0.95, false), 1.5, true)
			if tour:
				draw_circle(Vector2(x + 6.0, y - 5.0), 2.0, _lit(tint, 0.95, false))
		var title: String = line.title
		var main: bool = line.get("main", false)
		if main:
			# The main mission: a lit tick beside its bullet, its title brighter.
			draw_line(Vector2(x - 6.0, y - 15.0), Vector2(x - 6.0, y + 9.0), _lit(tint, 0.95, false), 2.5)
		_text(Vector2(x + 20.0, y), title, _lit(SQUAD_INK if done else Color.WHITE.lerp(ink, 0.15 if main else 0.4),
				1.0 if main else 0.92), HORIZONTAL_ALIGNMENT_LEFT, width - 80.0, 17 if main else 16)
		if not tour:
			_text(Vector2(right - 14.0, y), "%d/%d" % [line.have, line.goal],
					_lit(SQUAD_INK if float(line.share) > 0.0 else ink, 0.95), HORIZONTAL_ALIGNMENT_RIGHT, 60.0, 15)
			var bar := Vector2(x + 20.0, y + 8.0)
			var long := (width - 34.0) * drawn
			draw_line(bar, bar + Vector2(long, 0.0), _lit(ink, 0.18), 2.0)
			if float(line.share) > 0.0:
				draw_line(bar, bar + Vector2(long * float(line.share), 0.0), _lit(SQUAD_INK if done else ink, 0.85), 2.0)
		y += row


## The race radio (`Hud.comms`): each line a rival's name over what they
## said, right under the objective block, fading as it goes.
func _draw_comms(ink: Color) -> void:
	if hud == null or not hud.get("comms") is Array:
		return
	var lines: Array = hud.get("comms")
	if lines.is_empty():
		return
	var right := size.x - size.y * 0.06 + sway.x
	var width := clampf(size.x * 0.24, 300.0, 480.0)
	var y := size.y * 0.34 + sway.y
	for line: Dictionary in lines:
		# Gone over its last second.
		var alpha := clampf(float(line.left), 0.0, 1.0)
		_text(Vector2(right, y), "RADIO · " + str(line.from).to_upper(), _lit(ink, 0.7 * alpha, false),
				HORIZONTAL_ALIGNMENT_RIGHT, width, 12)
		_text(Vector2(right, y + 20.0), str(line.text), _lit(Color.WHITE.lerp(ink, 0.25), 0.95 * alpha, false),
				HORIZONTAL_ALIGNMENT_RIGHT, width, 15)
		draw_line(Vector2(right + 6.0, y - 10.0), Vector2(right + 6.0, y + 24.0), _lit(ink, 0.5 * alpha, false), 1.5)
		y += 50.0


## True while the weapon readout should be lit: reloading, the mag low or
## empty, or just after a switch. Otherwise it rests dim: the gun's own
## counter is where ammo is read.
func weapon_awake(held: Weapon) -> bool:
	if held == null:
		return false
	if _since_switch < weapon_show_time:
		return true
	var gun := held as Gun
	if gun == null:
		return false
	return gun.is_reloading() or gun.ammo_in_mag <= floori(gun.mag_size * weapon_low_share)


## The weapon readout, bottom right, mirroring the vitals: the weapon in hand,
## and for a gun the rounds in the mag over a row of ticks, the rounds in the
## pack beside it and a bar while reloading. It rests dim and lights up when
## it matters (`weapon_awake`). Ammo still lives on the gun's own counter.
func _draw_weapon(p: Actor, ink: Color) -> void:
	var held := p.get_active_weapon()
	if held == null:
		return
	var level := lerpf(weapon_rest, 1.0, weapon_lit) * _swept()
	var radius := cell_radius()
	var right := size.x - size.y * vitals_left + sway.x
	var base := size.y * vitals_low + sway.y + radius * 0.3
	var gun := held as Gun
	var low := gun != null and not gun.is_reloading() and gun.ammo_in_mag <= floori(gun.mag_size * weapon_low_share)
	var tint := Color(1.0, 0.3, 0.2) if low else ink
	_text(Vector2(right, base - radius * 2.4), held.display_name.to_upper(), _lit(ink, 0.9 * level, false),
			HORIZONTAL_ALIGNMENT_RIGHT, 300.0, 16)
	draw_line(Vector2(right - 150.0 * _swept(), base - radius * 1.9), Vector2(right, base - radius * 1.9),
			_lit(ink, 0.4 * level, false), 1.0, true)
	draw_line(Vector2(right, base - radius * 1.9), Vector2(right, base - radius * 1.5),
			_lit(ink, 0.4 * level, false), 1.0, true)
	if gun == null:
		return
	if gun.is_reloading():
		var done := 1.0 - gun.reload_left() / maxf(gun.reload_time, 0.01)
		_text(Vector2(right, base - 4.0), "RELOADING", _lit(ink, 0.95 * level, false), HORIZONTAL_ALIGNMENT_RIGHT, 220.0, 22)
		draw_line(Vector2(right - 150.0, base + 8.0), Vector2(right, base + 8.0), _lit(ink, 0.2 * level, false), 3.0)
		draw_line(Vector2(right - 150.0, base + 8.0), Vector2(right - 150.0 + 150.0 * done, base + 8.0),
				_lit(ink, 0.9 * level, false), 3.0)
		return
	# The mag count large, the pack's rounds small beside it.
	var reserve := "/ %d" % gun.reserve_ammo
	_text(Vector2(right, base - 4.0), reserve, _lit(ink, 0.8 * level, false), HORIZONTAL_ALIGNMENT_RIGHT, 110.0, 20)
	var font := ThemeDB.fallback_font
	var reserve_w := font.get_string_size(reserve, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	_text(Vector2(right - reserve_w - 10.0, base - 4.0), str(gun.ammo_in_mag), _lit(tint, level, false),
			HORIZONTAL_ALIGNMENT_RIGHT, 110.0, roundi(radius * 1.25))
	# Empty: the readout itself asks for the reload (`Hud.reload_prompt`).
	var ask := Hud.reload_prompt(p)
	if ask != "":
		var pulse := 0.65 + 0.35 * sin(Time.get_ticks_msec() * 0.008)
		_text(Vector2(right, base - radius * 3.3), ask.to_upper(), _lit(Color(1.0, 0.3, 0.2), pulse * level, false),
				HORIZONTAL_ALIGNMENT_RIGHT, 300.0, 18)
	# A tick a round, up to a mag of 40; beyond that, one bar.
	var row := Vector2(right, base + 8.0)
	if gun.mag_size <= 40:
		var step := minf(6.0, 180.0 / maxf(gun.mag_size, 1.0))
		for i in gun.mag_size:
			var x := row.x - i * step
			var full := i < gun.ammo_in_mag
			draw_line(Vector2(x, row.y), Vector2(x, row.y + 9.0), _lit(tint if full else ink, (0.95 if full else 0.2) * level,
					false), 2.5)
	else:
		var share := clampf(float(gun.ammo_in_mag) / maxf(gun.mag_size, 1.0), 0.0, 1.0)
		draw_line(row, row + Vector2(-150.0, 0.0), _lit(ink, 0.2 * level, false), 3.0)
		draw_line(row, row + Vector2(-150.0 * share, 0.0), _lit(tint, 0.9 * level, false), 3.0)
