class_name Hud
extends CanvasLayer
## In-raid HUD. Almost nothing is drawn over the screen: the crosshair, hit
## markers, the melee side marks, the red flash when you are hurt, and the
## prompt for what you are looking at. Everything else is on your gear in
## the world:
##   - the helmet's visor (`visor`, a `VisorHud`): what the glass you look
##     through shows, in first person only, and only what that helmet shows;
##   - the helmet's glass also carries your vitals at its edges: health,
##     armor and stamina on the left, flight heat and the rig's cue on the
##     right, and the ability's state, so they are always in view;
##   - the holographic watch on your left wrist (`wrist`), brought up with
##     the `check_wrist` key (X) and on its own while you are down: a small
##     card of icons in three tabs. Summon is the carousel of what you carry
##     (weapons worn and in the pack, toy vehicles, artifacts) with the
##     pack's fill and worth under it; Status is the map and your standing;
##     Mission is the portal, the contract, and sign-out and banking.
##     Down, it shows what your death cost and where you can land. With no
##     helmet, or in third person, it also carries the vitals as a thin strip;
##   - an ammo counter on every gun (`AMMO_COUNTER` on the gun's model);
##   - a heat gauge in the screen bay on the back of a jetpack
##     (`HEAT_READOUT`), seen in third person and by everyone around you.
## War news goes to the phone as a notification (`notice_sink`) when the game
## gives the HUD one.

const RenownLedger := preload("res://core/progression/renown_ledger.gd")
const Contracts := preload("res://core/economy/contracts.gd")
const SafetyNets := preload("res://core/economy/safety_nets.gd")
const SkinScript := preload("res://core/visual/actor_skin.gd")
const PhoneScript := preload("res://core/phone/phone.gd")
const GameSettings := preload("res://core/settings/game_settings.gd")
## The watch map's risk-zone grid is this many cells a side, how much room
## it leaves round what it shows, and the least half width it shows (metres).
const MAP_GRID := 16
const MAP_MARGIN := 1.2
const MAP_MIN_HALF := 40.0
## The tabletop map's relief is sampled on this many points a side.
const TABLE_GRID := 24
## The pages of the Standing icon, opened with a click: what you would lose
## now, what is already safe, and how this life is going.
## The mag share at or under which the reload prompt shows.
const RELOAD_PROMPT_SHARE := 0.25
const STANDING_PAGES := ["At stake", "Safe", "This life"]
## How close (metres) to a waypoint set on the watch map counts as there.
const WAYPOINT_REACHED := 8.0
## Marks the place to land picked out on the death report.
const DEATH_PICK := "> "
## The name of the counter added to each gun's model.
const AMMO_COUNTER := "AmmoCounter"
## The jetpack's screen bay, as the rig model names it.
const HEAT_DISPLAY := "HeatDisplay"
## The gauge added to it.
const HEAT_READOUT := "HeatReadout"

var raid: Raid
var controller: PlayerController
## Where war news goes (the phone's `show_notice`). Unset, it goes on the wrist.
var notice_sink: Callable
## The contracts held (`Contracts.held` of the account), for the watch's
## contract icon. Set by `main.gd`; counted against `Actor.tally`.
var contracts: Array[Dictionary] = []
## The new player's tour objective (`Onboarding.objective`), set by
## `main.gd`: a small line on the watch card and the visor glass, "" for none.
var objective := ""
## What to press for a tour step with nothing to walk to (`Onboarding.hint`),
## on the line under the crosshair while nothing else is offered there.
var tour_hint := ""
## On a race track, the run in one line (`Race.run_line`): the watch card
## and the visor's objective block show it in the tour's place.
var race_line := ""
## The race radio: what rivals said to you lately, oldest first
## ({"from", "text", "left"}). The visor draws it under its objectives;
## with no helmet each line goes on the wrist like a notice.
var comms: Array[Dictionary] = []
## The wrist display.
var wrist: Wrist
## What the helmet draws on its glass in first person, and what its visor
## shows out in the world (scan snapshots, tags).
var visor: VisorHud

var _hit_marker: HitMarker
## Fills round the crosshair while you bank at a depot or sign out, so the
## progress is in view without raising the watch (playtest feedback).
var progress_ring: ProgressRing
var _hurt_flash: ColorRect
var _stance: StanceIndicator
## The aiming cross in the middle of the screen.
var crosshair: Label
var _prompt: Label
var _messages: Array[Dictionary] = []
## The local player's last life, shown while they are down (see `show_death`).
var _death_result := {}
## Squad pings standing in the world: { node, left }.
var _pings: Array[Dictionary] = []
var _redeploy_wait := 0.0
## Whether the watch was resting last frame, to chime once it is ready.
var _was_resting := false
## Where the watch map's waypoint is ({"at", "title", "kind"}), set by a
## click on one of its targets, or {} for none. Only you see it: a column of
## light in the world (`_waypoint_mark`) and a mark on the visor's heading
## strip and scope. Cleared once you get there.
var waypoint := {}
var _waypoint_mark: Node3D
## Seconds this life has lasted, for the Standing icon's "This life" page.
var life_time := 0.0


func setup(p_raid: Raid, p_controller: PlayerController) -> void:
	raid = p_raid
	controller = p_controller


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_hurt_flash = ColorRect.new()
	_hurt_flash.color = Color(0.8, 0.05, 0.02, 0.0)
	_hurt_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hurt_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hurt_flash)

	visor = VisorHud.new()
	visor.name = "Visor"
	visor.setup(raid, controller)
	visor.hud = self
	root.add_child(visor)

	_hit_marker = HitMarker.new()
	_hit_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hit_marker)
	_place(_hit_marker, 0.5, 0.5, Vector2(-20, -20), Vector2(40, 40))
	progress_ring = ProgressRing.new()
	progress_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(progress_ring)
	_place(progress_ring, 0.5, 0.5, Vector2(-32, -32), Vector2(64, 64))

	_stance = StanceIndicator.new()
	_stance.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_stance)
	_place(_stance, 0.5, 0.5, Vector2(-70, -70), Vector2(140, 140))

	crosshair = _label(root, "+", 22)
	_place(crosshair, 0.5, 0.5, Vector2(-7, -17), Vector2(14, 30))

	_prompt = _label(root, "", 18)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(_prompt, 0.5, 0.5, Vector2(-300, 40), Vector2(600, 30))

	wrist = Wrist.new()
	wrist.name = "Wrist"
	add_child(wrist)

	if controller != null:
		controller.map_target_clicked.connect(_on_map_target_clicked)
	raid.player.notice.connect(_on_notice)
	if not raid.pinged.is_connected(_on_pinged):
		raid.pinged.connect(_on_pinged)
	raid.war_feed.connect(_on_war_feed)
	raid.player.hit_confirmed.connect(_on_hit_confirmed)
	raid.player.health.damaged.connect(_on_player_damaged)
	if raid is Race:
		(raid as Race).radio.connect(_on_radio)


func _exit_tree() -> void:
	if wrist != null and is_instance_valid(wrist):
		wrist.take_off()
		wrist.queue_free()


func _process(delta: float) -> void:
	if raid == null or raid.player == null or not is_instance_valid(raid.player):
		return
	var p := raid.player
	_redeploy_wait = maxf(0.0, _redeploy_wait - delta)
	_hurt_flash.color.a = maxf(0.0, _hurt_flash.color.a - delta * 0.9)

	var weapon := p.get_active_weapon()
	var blade := weapon as MeleeWeapon
	_stance.threat = incoming_side(p) if blade else -1
	_update_ammo_counters(p)
	if crosshair:
		# Looking down an optic, its own reticle marks the middle.
		crosshair.modulate.a = 0.0 if controller != null and is_instance_valid(controller) and controller.sighted else 1.0
	_update_heat_display(p)

	var banking := raid.bank_progress()
	var leaving := raid.sign_out_progress(p)
	if p.is_dead:
		var places := drop_choices(raid, p).size()
		var landing := "Wheel or 1-%d: pick where to land      " % places if places > 1 else ""
		_prompt.text = landing + "Click or Enter: drop back in      L: go home" if _redeploy_wait <= 0.0 \
				else "Dropping back in in %d..." % ceili(_redeploy_wait)
		if _death_result.is_empty():
			_prompt.text = ""
	elif leaving >= 0.0:
		var state := raid.state_for(p)
		var left := ceili(state.sign_out_left) if state != null and state.sign_out_left >= 0.0 else 0
		_prompt.text = ("Signing out  %d s   L to cancel" % left) if left > 0 else "Signing out...   L to cancel"
	elif banking > 0.0:
		_prompt.text = "Banking your backpack  %d%%" % roundi(banking * 100.0)
	elif p.heal_time_left > 0.0:
		_prompt.text = "Healing %.1f" % p.heal_time_left
	else:
		# On a vehicle, F gets you off, so nothing else is offered.
		var target := p.find_interactable() if p.vehicle == null else null
		_prompt.text = target.get_prompt() if target else reload_prompt(p)
		if _prompt.text == "" and not (controller != null and controller.wrist_raised):
			_prompt.text = tour_hint

	if progress_ring:
		progress_ring.show_progress(-1.0 if p.is_dead else (leaving if leaving >= 0.0 else (banking if banking > 0.0 else -1.0)),
				ProgressRing.LEAVING if leaving >= 0.0 else ProgressRing.BANKING)
	for m in _messages:
		m.time -= delta
	_messages = _messages.filter(func(m: Dictionary) -> bool: return m.time > 0.0)
	for line in comms:
		line.left -= delta
	comms = comms.filter(func(line: Dictionary) -> bool: return line.left > 0.0)
	var log_lines: Array[String] = []
	for m in _messages:
		log_lines.append(m.text)

	wrist.raised = p.is_dead or (controller != null and controller.wrist_raised)
	wrist.mount(p, controller, visible, delta)
	var picked := controller.watch_index if controller != null else 0
	var to_pack: Node3D = controller.pack_target() if controller != null else null
	var pack_name: String = to_pack.get("display_name") if to_pack != null else ""
	if to_pack != null:
		_prompt.text = "Click: pack %s onto your watch" % pack_name
	elif _prompt.text.contains("Ride ") and not p.is_dead:
		_prompt.text += "      Watch up, then click: pack it"
	if not p.is_dead:
		life_time += delta
	var picks := {"weapon": controller.weapon_pick, "artifact": controller.artifact_pick, "portal": controller.portal_pick,
			"map": controller.map_pick, "standing": controller.standing_pick, "pack": controller.pack_pick,
			"race": controller.race_pick, "race_open": controller.watch_open == "contract",
			"ghost": controller.ghost_pick, "life_time": life_time,
			"mission": controller.mission_pick, "mission_open": controller.watch_open == "contract",
			"abandon": controller.abandon_progress()} \
			if controller != null else {"life_time": life_time}
	picks["objective"] = objective
	if controller != null:
		controller.missions = mission_entries(contracts, objective)
	race_line = Race.run_line((raid as Race).view_run()) if raid is Race else ""
	if raid is Race:
		_guide_to_pits((raid as Race).view_run())
	var targets := map_targets(raid, p, ping_spots()) if wrist.raised and not p.is_dead else ([] as Array[Dictionary])
	if controller != null:
		controller.map_targets = targets
	picks["targets"] = targets
	picks["waypoint"] = waypoint
	var slots := watch_slots(raid, p, picked, pack_name, leaving, banking, picks, contracts)
	var opened := controller.watch_open if controller != null else ""
	mark_open(slots, opened)
	var focus := default_focus(slots)
	if controller != null:
		if controller.watch_focus_moved:
			focus = clampi(controller.watch_focus, 0, slots.size() - 1)
		else:
			controller.watch_focus = focus
	var death := death_text(_death_result, _redeploy_wait, drop_choices(raid, p),
			controller.drop_pick if controller != null else 0) \
			if p.is_dead and not _death_result.is_empty() else ""
	# Your vitals are on the visor's edges in either view (drawn flat in
	# third person); with no helmet the card carries them in a thin strip.
	var on_glass := visor != null and (visor.glass_shown() or visor.flat_shown())
	wrist.objective = race_line if race_line != "" else (objective if GameSettings.is_tracked(GameSettings.TOUR_KEY) else "")
	# The map is only worked out while it is the icon being read; opened, it
	# also rises off the wrist as a tabletop hologram with the ground's relief.
	var map_open: bool = wrist.raised and focus < slots.size() and slots[focus].id == "map"
	wrist.map = map_marks(raid, p, ping_spots()) if map_open and not p.is_dead else {}
	wrist.opened = opened if wrist.raised and focus < slots.size() and slots[focus].id == opened else ""
	wrist.tabs = wrist.raised and not p.is_dead and controller != null and controller.watch_tabs
	if wrist.opened == "map" and not wrist.map.is_empty():
		var at := clampi(controller.map_pick if controller != null else 0, 0, maxi(targets.size() - 1, 0))
		wrist.show_table(wrist.map, map_relief(raid, wrist.map),
				targets[at] if not targets.is_empty() else {}, waypoint)
	else:
		wrist.show_table({}, PackedFloat32Array(), {}, {})
	_update_waypoint(p)
	var resting := not p.is_dead and raid.summon_wait(p) > 0.0
	if _was_resting and not resting and not p.is_dead:
		Sfx.play("watch_ready", null, -8.0)
	_was_resting = resting
	wrist.resting = resting
	wrist.show_card(slots, focus, death, p.health.health / maxf(p.health.max_health, 1.0),
			wrist_bars(p) if not on_glass else ([] as Array[float]),
			log_lines.slice(maxi(0, log_lines.size() - 1)), {"summon": pack_text(p)},
			flight_popup(p) if not on_glass else "")
	wrist.show_toys(raid.stowed_for(p) if not p.is_dead else ([] as Array[String]), picked,
			raid.toy_wait(p) <= 0.0, delta)
	var carried: Array[String] = []
	if not p.is_dead:
		for entry in weapon_entries(p):
			carried.append(entry.id)
	wrist.show_weapons(carried, int(picks.get("weapon", 0)), raid.summon_wait(p) <= 0.0, delta)
	_update_pings(delta)


## Two-level watch (Caleb's call): an icon that holds several things shows
## the wheel glyph only once opened; on the main row it shows a click, which
## opens it, and the wheel moves between icons.
## The line under the crosshair when the gun in hand needs a reload (Caleb's
## call: a gun never reloads on its own, it asks): empty or low with rounds in
## the pack, "R  Reload"; empty with nothing left, "Out of ammo". Shown with
## or without a helmet and in both views; empty otherwise.
static func reload_prompt(p: Actor) -> String:
	var gun := p.get_active_weapon() as Gun if p != null else null
	if gun == null or gun.is_reloading() or gun.is_power() or p.weapons_locked:
		return ""
	if gun.jammed:
		return "%s  Clear the jam" % PhoneScript.key_name("reload")
	if gun.ammo_in_mag <= 0 and gun.reserve_ammo <= 0:
		return "Out of ammo"
	if gun.reserve_ammo > 0 and gun.ammo_in_mag <= floori(gun.mag_size * RELOAD_PROMPT_SHARE):
		return "%s  Reload" % PhoneScript.key_name("reload")
	return ""


static func mark_open(slots: Array[Dictionary], opened: String) -> void:
	for slot in slots:
		if int(slot.get("count", 0)) > 1 and slot.id != opened:
			# Closed, an icon with pages or a list says what it is about.
			if slot.has("where"):
				slot.detail = slot.where
			var hints: Array = slot.hints.filter(func(h: String) -> bool: return h != "wheel")
			if not hints.has("click"):
				hints.append("click")
			slot.hints = hints


## The weapons on the watch's carousel, in the order the wheel turns through
## them: the ones worn (primary, sidearm, melee, heavy), drawn or stored
## with a click. Each is {"id", "index" (in `Actor.weapons`)}. What is in the
## pack is put on from the pack's own list (Caleb's call: one place to swap
## gear in), never from here; at home the carousel goes on through the
## collection (`PlayerController.watch_weapons`).
static func weapon_entries(p: Actor) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var storing := p.storing_weapon()
	for index in p.slot_order():
		# One dematerializing back into the pack is already listed there.
		if p.weapons[index] != storing:
			entries.append({"id": p.weapons[index].item_id, "index": index})
	# The heavy chamber's weapon: drawn only from here, never by a key.
	var heavy := Loadout.power_index(p)
	if heavy >= 0:
		entries.append({"id": p.weapons[heavy].item_id, "index": heavy})
	return entries


## The artifact on the watch (item ids): only the one attuned for this
## outing, used with one click (Caleb's call). Any others carried are loot,
## read in the pack's list.
static func artifact_entries(p: Actor) -> Array[String]:
	var entries: Array[String] = []
	if p.artifact.enabled:
		entries.append(p.artifact.item_id)
	return entries


## The pack's line under the Summon tab: how full, what everything carried
## weighs and its tier (`CarryLoad`), what the pack is worth, heals and scrip.
static func pack_text(p: Actor) -> String:
	var pack := "Pack %d/%d · %s" % [p.inventory.items.size(), p.inventory.capacity, CarryLoad.label(p.carry_kg())]
	if not p.inventory.items.is_empty():
		pack += " · worth %d" % p.inventory.total_value()
	var heals := p.inventory.count_with_tag("heal")
	if heals > 0:
		pack += " · %d heal%s" % [heals, "" if heals == 1 else "s"]
	if p.scrip > 0:
		pack += " · %d scrip" % p.scrip
	return pack


## The flight rig's cue as a pop-up on the card, only while flying and only
## where the visor is not showing it.
static func flight_popup(p: Actor) -> String:
	if p.is_dead or not p.flight.enabled or p.airborne_time <= 0.3:
		return ""
	var cue := rig_text(p)
	return cue if cue != "" else "%s · heat %d%%" % [p.flight.display_name, roundi(p.flight.heat_fraction() * 100.0)]


## The icons on the watch card, left to right, tab after tab
## (`Wrist.SLOTS`, `Wrist.TABS`), each a Dictionary:
##   "id": which slot, drawn as its icon;
##   "tab": the tab it is on;
##   "value": a short number or word on the icon ("" for none);
##   "detail": the one line shown when the icon is open (looked at);
##   "hints": controls drawn as glyphs beside it ("wheel", "click", or
##     "key:L" for a key cap), never written out;
##   "progress": a ring around the icon from 0 to 1, or below 0 for none;
##   "empty": nothing in it (drawn as a dim socket);
##   "alert": something wants the eye (drawn warm and pulsing);
##   "count", "index": on a carousel, how many things it holds and which
##     one is picked out (0 and 0 for a plain icon).
## `picked_toy` is the toy picked out, `pack_name` the vehicle a click would
## pack, `leaving` the sign-out progress (below 0 for none), `banking` the
## depot progress, and `picks` the weapon and artifact picked out
## ({"weapon": n, "artifact": n}).
static func watch_slots(p_raid: Raid, p: Actor, picked_toy := 0, pack_name := "", leaving := -1.0,
		banking := 0.0, picks := {}, jobs: Array[Dictionary] = []) -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	# Summon: what you carry, materialized through the watch.
	slots.append(weapon_slot(p_raid, p, int(picks.get("weapon", 0))))
	# The vehicle: toys on the watch, or the one a click would pack.
	var toys := p_raid.stowed_for(p)
	var recharge := p_raid.toy_wait(p)
	if p.vehicle != null:
		slots.append(_slot("vehicle", "%d" % roundi(absf(float(p.vehicle.get("speed"))) * 3.6),
				"%s · km/h" % p.vehicle.get("display_name"), [], -1.0, false, false))
	elif pack_name != "":
		slots.append(_slot("vehicle", "+", "Pack %s" % pack_name, ["click"], -1.0, false, true))
	elif toys.is_empty():
		slots.append(_slot("vehicle", "", "No vehicle", [], -1.0, true, false))
	else:
		var at := clampi(picked_toy, 0, toys.size() - 1)
		var name := ItemDB.item_name(toys[at])
		var wait := 1.0 - recharge / maxf(p_raid.toy_cooldown, 0.01) if recharge > 0.0 else -1.0
		slots.append(_slot("vehicle", "%d" % toys.size(), name if recharge <= 0.0 else "%s · %d s" % [name, ceili(recharge)],
				["wheel", "click"] if recharge <= 0.0 else [], wait, false, false, toys.size(), at))
	# The artifact attuned for this outing: one click uses it.
	slots.append(artifact_slot(p.artifact))
	slots.append(pack_slot(p, int(picks.get("pack", 0)), p_raid))
	# Status: where you are and how you stand.
	var where := p_raid.world.display_name
	# The risk zone you stand in (DESIGN.md section 2), or the outpost sheltering you.
	if p_raid.zone_label(p) != "":
		where += " · " + p_raid.zone_label(p)
	if p_raid.war.intensity >= 0.2:
		where += " · " + p_raid.war.level_name()
	var held := sites_text(p_raid, p)
	if held != "":
		where += " · " + held
	slots.append(map_slot(where, picks.get("targets", []), int(picks.get("map", 0)), picks.get("waypoint", {}), p))
	slots.append(standing_slot(p_raid, p, int(picks.get("standing", 0)), jobs, float(picks.get("life_time", 0.0))))
	# Mission: the squad portal, the contract, and sign-out and banking.
	slots.append(portal_slot(Portal.choices_for(p_raid, p), int(picks.get("portal", 0)),
			not p_raid.world.safe_zone))
	# On a race track the contract's place is the time trial's (no job
	# counts there): the run's line, and restart, ghost and stop to pick.
	if p_raid is Race:
		var view := (p_raid as Race).view_run()
		var pick := str(picks.get("ghost", "mine"))
		slots.append(race_slot(view, int(picks.get("race", 0)), bool(picks.get("race_open", false)), pick,
				(p_raid as Race).ghost_shown(pick, str(view.get("track", "")), str(view.get("machine", "")))))
	else:
		slots.append(mission_slot(mission_entries(jobs, str(picks.get("objective", ""))), p.tally,
				int(picks.get("mission", 0)), bool(picks.get("mission_open", false))))
	# A click (or L) starts or cancels the sign-out.
	if leaving >= 0.0:
		slots.append(_slot("leave", "", "Signing out · cancel", ["click", "key:L"], leaving, false, true))
	elif banking > 0.0:
		slots.append(_slot("leave", "", "Banking", [], banking, false, true))
	else:
		slots.append(_slot("leave", banked_value(p), "Sign out" + banked_line(p), ["click", "key:L"], -1.0, false, false))
	slots.append(abandon_slot(p_raid, p, float(picks.get("abandon", -1.0))))
	return slots


## The Abandon icon: hold fire on it to give this life up where you stand
## (`Raid.abandon`), a quick way out that costs what you carry. It says
## what that is, and what is already home and safe. `held` is the hold's
## progress (below 0 for none). Empty where nothing is at stake.
static func abandon_slot(p_raid: Raid, p: Actor, held := -1.0) -> Dictionary:
	if p_raid == null or not p_raid.can_abandon(p):
		return _slot("abandon", "", "Nothing to abandon here", [], -1.0, true, false)
	if held >= 0.0:
		return _slot("abandon", "", "Keep holding to abandon this life", ["click"], held, false, true)
	return _slot("abandon", "", "Hold to abandon · " + abandon_cost(p_raid, p) + banked_line(p),
			["click"], -1.0, false, false)


## What abandoning would cost, in words: what you carry falls in your bag
## or as the world's death rule says (only the loot you found where a world
## keeps your gear on death).
static func abandon_cost(p_raid: Raid, p: Actor) -> String:
	var keeps := p_raid.world.keep_gear_on_death
	var at_stake: Array[String] = []
	at_stake.assign(p.inventory.items if keeps else p.get_drop_items())
	var worth := ItemDB.total_value(at_stake) + maxi(p.scrip, 0)
	if at_stake.is_empty() and p.scrip <= 0:
		return "nothing on you to lose"
	return ("lose the loot you found, worth %d" if keeps else "lose what you carry, worth %d") % worth


## The small holographic map on the watch's Map icon (Status tab), as plain
## data for the card to draw: a square of the world around everything that
## matters, north up, with every point in it from -1 to 1. Only what the
## player is already told: where they are and face, the strongpoints (and
## whether their side holds each), the depots, the gate outposts, where the
## war is hot, their side's pings, and the risk zones as a coarse grid.
## Never other people. Empty where there is no world (at home).
##   "you": Vector2, "facing": Vector2 (a unit direction on the map),
##   "sites": [{"at", "held", "contested"}], "depots", "outposts", "pings":
##   [Vector2], "war": Vector2 or null, "zones": PackedByteArray of
##   `MAP_GRID` x `MAP_GRID` tiers (row by row, north first) or empty when
##   the world has one zone, "half": the half width shown, in metres,
##   "pushes": [{"from", "to"}], an army on its way to a site (`Raid.pushes`).
static func map_marks(p_raid: Raid, p: Actor, pings: Array[Vector3] = []) -> Dictionary:
	if p_raid == null or p == null or not is_instance_valid(p) or p_raid.world == null:
		return {}
	var points: Array[Vector3] = [p.global_position]
	for point in p_raid.strongpoints:
		points.append(point.global_position)
	for depot in p_raid.depots:
		points.append(depot.global_position)
	for outpost in p_raid.outposts:
		if is_instance_valid(outpost):
			points.append(outpost.global_position)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for at in points:
		lo = Vector2(minf(lo.x, at.x), minf(lo.y, at.z))
		hi = Vector2(maxf(hi.x, at.x), maxf(hi.y, at.z))
	var middle := (lo + hi) * 0.5
	var half := maxf(maxf(hi.x - lo.x, hi.y - lo.y) * 0.5 * MAP_MARGIN, MAP_MIN_HALF)
	var to_map := func(at: Vector3) -> Vector2:
		return (Vector2(at.x, at.z) - middle) / half
	var aim := p.cmd.aim_dir if p.cmd != null and p.cmd.aim_dir.length_squared() > 0.001 else -p.global_basis.z
	var facing := Vector2(aim.x, aim.z)
	var marks := {
		"you": to_map.call(p.global_position),
		"facing": facing.normalized() if facing.length_squared() > 0.0001 else Vector2.UP,
		"half": half,
		"middle": middle,
		"sites": [], "depots": [], "outposts": [], "pings": [], "war": null, "storm": null,
		"zones": PackedByteArray(), "pushes": [],
	}
	for push in p_raid.live_pushes():
		var site := int(push.site)
		if site >= 0 and site < p_raid.strongpoints.size():
			marks.pushes.append({"from": to_map.call(push.from),
					"to": to_map.call(p_raid.strongpoints[site].global_position)})
	for point in p_raid.strongpoints:
		marks.sites.append({"at": to_map.call(point.global_position), "held": p_raid.holds(p, point),
				"contested": point.contested})
	for depot in p_raid.depots:
		marks.depots.append(to_map.call(depot.global_position))
	for outpost in p_raid.outposts:
		if is_instance_valid(outpost):
			marks.outposts.append(to_map.call(outpost.global_position))
	for at in pings:
		marks.pings.append(to_map.call(at))
	if p_raid.war.intensity >= 0.2:
		marks.war = to_map.call(p_raid.war.centre)
	if p_raid.weather.active():
		marks.storm = {"at": to_map.call(p_raid.weather.centre), "radius": p_raid.weather.radius / half}
	var zones := PackedByteArray()
	var varied := false
	for row in MAP_GRID:
		for col in MAP_GRID:
			var spot := middle + (Vector2(col, row) + Vector2(0.5, 0.5)) / MAP_GRID * 2.0 * half - Vector2(half, half)
			var tier := clampi(p_raid.world.zone_at(Vector3(spot.x, 0.0, spot.y)), 0, 2)
			varied = varied or tier != 0
			zones.append(tier)
	if varied:
		marks.zones = zones
	return marks


## What the opened watch map can point you to, in the wheel's order: the
## nearest depot, gate outpost and strongpoint, the war's hot zone, the
## world event, and your side's pings. Each is {"kind", "title", "at"
## (Vector3)}. Only places the player is already told about, never people.
static func map_targets(p_raid: Raid, p: Actor, pings: Array[Vector3] = []) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if p_raid == null or p == null or not is_instance_valid(p) or p_raid.world == null:
		return out
	var from := p.global_position
	var nearest := func(nodes: Array) -> Node3D:
		var best: Node3D = null
		for node: Node3D in nodes:
			if is_instance_valid(node) and (best == null
					or node.global_position.distance_to(from) < best.global_position.distance_to(from)):
				best = node
		return best
	var depot: Node3D = nearest.call(p_raid.depots)
	if depot != null:
		out.append({"kind": "depot", "title": "Depot", "at": depot.global_position})
	var outpost: Node3D = nearest.call(p_raid.outposts)
	if outpost != null:
		out.append({"kind": "outpost", "title": "Gate outpost", "at": outpost.global_position})
	var site: Node3D = nearest.call(p_raid.strongpoints)
	if site != null:
		out.append({"kind": "site", "title": str(site.get("title")), "at": site.global_position})
	if p_raid.war.intensity >= 0.2:
		out.append({"kind": "hot", "title": "The fighting", "at": p_raid.war.centre})
	if p_raid.event.get("at") is Vector3:
		out.append({"kind": "event", "title": str(p_raid.event.get("title", "Event")), "at": p_raid.event.at})
	for at in pings:
		out.append({"kind": "ping", "title": "Ping", "at": at})
	return out


## How far and which way: "120 m NE".
static func bearing_text(from: Vector3, to: Vector3) -> String:
	var flat := Vector2(to.x - from.x, to.z - from.z)
	var away := roundi(flat.length())
	if away < 2:
		return "here"
	var names := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	var angle := fposmod(rad_to_deg(atan2(flat.x, -flat.y)) + 22.5, 360.0)
	return "%d m %s" % [away, names[int(angle / 45.0) % 8]]


## The Map icon: where you are on its line, and once opened (a click), the
## wheel turns through `targets` (`map_targets`), the picked one on the line
## with how far and which way, and a click sets it as your waypoint.
static func map_slot(where: String, targets: Array, picked: int, way: Dictionary, p: Actor) -> Dictionary:
	if targets.is_empty():
		return _slot("map", "", where, [], -1.0, false, false)
	var at := clampi(picked, 0, targets.size() - 1)
	var target: Dictionary = targets[at]
	var marked := not way.is_empty() and (way.at as Vector3).is_equal_approx(target.at)
	var detail := "%s · %s%s" % [target.title, bearing_text(p.global_position, target.at), " · waypoint" if marked else ""]
	var slot := _slot("map", "", detail, ["wheel", "click"], -1.0, false, false, targets.size(), at)
	# Closed, the line still says where you are (see `mark_open`, and the
	# card shows `where` until it is opened).
	slot["where"] = where
	var lines: Array[String] = []
	for target_at: Dictionary in targets:
		lines.append("%s  %s" % [target_at.title, bearing_text(p.global_position, target_at.at)])
	slot["panel"] = lines
	slot["panel_at"] = at
	return slot


## The Standing icon: rank and renown on its line, and once opened, three
## pages the wheel turns through (`STANDING_PAGES`): what you would lose
## now, what is already safe, and how this life is going.
static func standing_slot(p_raid: Raid, p: Actor, page: int, jobs: Array[Dictionary] = [], alive := 0.0) -> Dictionary:
	var hunted := p.bounty > 0 or p.exposed or p.marked
	var at := clampi(page, 0, STANDING_PAGES.size() - 1)
	var slot := _slot("standing", str(p.renown) if p.renown > 0 else "", standing_text(p).replace("   ", " · "),
			[], -1.0, false, hunted, STANDING_PAGES.size(), at)
	slot["where"] = slot.detail
	slot["page"] = STANDING_PAGES[at]
	slot["panel"] = standing_page(p_raid, p, at, jobs, alive)
	slot["panel_at"] = -1
	return slot


## The lines of Standing page `page` (`STANDING_PAGES`).
static func standing_page(p_raid: Raid, p: Actor, page: int, jobs: Array[Dictionary] = [], alive := 0.0) -> Array[String]:
	var lines: Array[String] = []
	match page:
		0:
			lines.append("Pack: %d item%s, worth %d" % [p.inventory.items.size(),
					"" if p.inventory.items.size() == 1 else "s", p.inventory.total_value()])
			lines.append("Scrip carried: %d" % p.scrip)
			lines.append("Renown at stake: %d" % p.renown)
			if p.bounty > 0:
				lines.append("Bounty on you: %d" % p.bounty)
			if p.exposed or p.marked:
				lines.append("THE MARKED" if p.marked else "EXPOSED")
		1:
			lines.append("Sent home: %d item%s, worth %d" % [p.banked_count, "" if p.banked_count == 1 else "s",
					p.banked_value])
			lines.append("Scrip banked: %d" % p.banked_scrip)
			lines.append("Rank: %s" % RenownLedger.rank_name(p.rank))
		_:
			var seconds := int(alive)
			lines.append("Alive %d:%02d" % [seconds / 60, seconds % 60])
			var state := p_raid.state_for(p) if p_raid != null else null
			lines.append("Kills: %d" % (state.kills if state != null else 0))
			if p.streak > 1:
				lines.append("Streak: %d" % p.streak)
			var job := contract_slot(jobs, p.tally)
			if not job.empty:
				lines.append(job.detail)
	return lines


## The Pack icon on the Summon tab: how full it is, and once opened, the
## wheel turns through what is in it, the picked item's worth on the line.
static func pack_slot(p: Actor, picked := 0, p_raid: Raid = null) -> Dictionary:
	var items := p.inventory.items
	var fill := "%d/%d" % [items.size(), p.inventory.capacity]
	if items.is_empty():
		return _slot("pack", fill, "Pack empty", [], -1.0, true, false)
	var at := clampi(picked, 0, items.size() - 1)
	var id: String = items[at]
	# Gear the watch can put on takes a click (`Loadout.wearable_from_pack`);
	# its line says the slot it goes in.
	var slot := _slot("pack", fill, "%s · worth %d" % [ItemDB.item_name(id), ItemDB.total_value([id])],
			["wheel", "click"] if Loadout.wearable_from_pack(id) else ["wheel"], -1.0, false, false,
			items.size(), at)
	# Resting after a summon or a swap, nothing in the pack goes on: the ring
	# fills back up as the rest runs out.
	var wait := p_raid.summon_wait(p) if p_raid != null else 0.0
	if wait > 0.0 and Loadout.wearable_from_pack(id):
		slot.detail = "%s · resting %d s" % [ItemDB.item_name(id), ceili(wait)]
		slot.hints = ["wheel"]
		slot.progress = p_raid.summon_charge(p)
	elif Loadout.summonable(id):
		slot.detail += " · %.1f s" % Loadout.summon_time(id)
	if can_drop_here(p_raid):
		# The interact key drops the picked item (`PlayerController.drop_picked_from_pack`).
		slot.hints = slot.hints + [key_cap("interact")]
	slot["where"] = pack_text(p)
	var lines: Array[String] = []
	for item: String in items:
		lines.append(pack_line(item))
	slot["panel"] = lines
	slot["panel_at"] = at
	return slot


## True if `p_raid`'s world lets a player drop things out of their pack
## (`Raid.drop_item`): out in a world, never a safe zone or anywhere nothing
## is at stake.
static func can_drop_here(p_raid: Raid) -> bool:
	return p_raid != null and p_raid.world != null and not p_raid.world.safe_zone and p_raid.world.gear_at_risk


## The key cap hint ("key:F") for input action `action`, read from the keys
## as bound, so a rebound key shows its own letter.
static func key_cap(action: String) -> String:
	if InputMap.has_action(action):
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				var key := ev as InputEventKey
				var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
				return "key:" + OS.get_keycode_string(code)
	return "key:F"


## One line of the opened pack list: the item and its worth, and for gear
## the watch can put on, the slot it goes in.
static func pack_line(item: String) -> String:
	var line := "%s  %d" % [ItemDB.item_name(item), ItemDB.total_value([item])]
	if Loadout.wearable_from_pack(item):
		var slot := Loadout.weapon_slot(item) if Loadout.summonable(item) else Loadout.slot_of(item)
		line += "  · %s" % Loadout.SLOT_NAMES.get(slot, slot)
	return line


## The relief under the watch's tabletop map: the ground's height on a
## `TABLE_GRID` square grid over what `marks` shows (`map_marks`), from 0
## (lowest) to 1 (highest), row by row, north first. Flat with no ground.
static func map_relief(p_raid: Raid, marks: Dictionary) -> PackedFloat32Array:
	var heights := PackedFloat32Array()
	var n := TABLE_GRID
	heights.resize(n * n)
	var map := p_raid.map if p_raid != null else null
	if marks.is_empty() or map == null or not is_instance_valid(map) or not map.has_method("ground_height"):
		return heights
	var middle: Vector2 = marks.middle
	var half: float = marks.half
	var low := INF
	var high := -INF
	for row in n:
		for col in n:
			var spot := middle + (Vector2(col, row) / float(n - 1) * 2.0 - Vector2.ONE) * half
			var h := float(map.call("ground_height", spot.x, spot.y))
			heights[row * n + col] = h
			low = minf(low, h)
			high = maxf(high, h)
	var span := maxf(high - low, 1.0)
	for i in heights.size():
		heights[i] = (heights[i] - low) / span
	return heights


## A click on the opened map's target: it becomes your waypoint, or stops
## being one if it already was.
func _on_map_target_clicked(index: int) -> void:
	var targets := controller.map_targets if controller != null else ([] as Array[Dictionary])
	if index < 0 or index >= targets.size():
		return
	var target := targets[index]
	if not waypoint.is_empty() and (waypoint.at as Vector3).is_equal_approx(target.at):
		set_waypoint({})
	else:
		set_waypoint(target)
		Sfx.play("ping", null, -8.0)


## Sets the watch map's waypoint ({} clears it): a column of light only you
## see, and a mark on the visor's heading strip and scope.
func set_waypoint(target: Dictionary) -> void:
	waypoint = {"at": target.at, "title": target.title, "kind": target.get("kind", "")} if not target.is_empty() else {}
	if _waypoint_mark != null and is_instance_valid(_waypoint_mark):
		_waypoint_mark.queue_free()
	_waypoint_mark = null
	if waypoint.is_empty() or raid == null:
		return
	_waypoint_mark = ping_mark(String(waypoint.title))
	_waypoint_mark.name = "Waypoint"
	raid.add_child(_waypoint_mark)
	_waypoint_mark.global_position = waypoint.at


## A finished racer is shown the way into the pits (`Race.set_down`): the
## track's pit row is the waypoint until the run is over.
func _guide_to_pits(view: Dictionary) -> void:
	var done := str(view.get("phase", "")) == "done"
	if done and str(waypoint.get("kind", "")) != "pits":
		var rt := (raid as Race).track_by_id(str(view.get("track", "")))
		if rt != null:
			set_waypoint({"at": rt.pit_spot(), "title": "Pits", "kind": "pits"})
	elif not done and str(waypoint.get("kind", "")) == "pits":
		set_waypoint({})


## Clears the waypoint once you reach it.
func _update_waypoint(p: Actor) -> void:
	# The way into the pits ends when the race sets you down, not here.
	if waypoint.is_empty() or str(waypoint.get("kind", "")) == "pits":
		return
	var at: Vector3 = waypoint.at
	if Vector2(at.x - p.global_position.x, at.z - p.global_position.z).length() <= WAYPOINT_REACHED:
		notify("Reached %s" % waypoint.title)
		set_waypoint({})


## The number on the sign-out icon once this life has banked at a depot:
## the worth sent home ("" before anything was).
static func banked_value(p: Actor) -> String:
	return str(p.banked_value) if p.banked_value > 0 else ""


## The banking readout after "Sign out": what this life has already sent
## home through depots, safe whatever happens next ("" before anything was).
static func banked_line(p: Actor) -> String:
	var parts: Array[String] = []
	if p.banked_count > 0:
		parts.append("%d item%s, worth %d" % [p.banked_count, "" if p.banked_count == 1 else "s", p.banked_value])
	if p.banked_scrip > 0:
		parts.append("%d scrip" % p.banked_scrip)
	return " · home: " + ", ".join(parts) if not parts.is_empty() else ""


## The weapon carousel's icon: the weapon picked out of what is carried.
## One worn is drawn with a click (a heavy weapon shows its shots), and the
## one in hand is stored back into the pack with a click; one in
## the pack is materialized into the hand in place of the one worn in its
## slot, which takes `Loadout.summon_time` and then rests the watch.
static func weapon_slot(p_raid: Raid, p: Actor, picked := 0) -> Dictionary:
	var entries := weapon_entries(p)
	if entries.is_empty():
		return _slot("weapon", "", "No weapon", [], -1.0, true, false)
	var at := clampi(picked, 0, entries.size() - 1)
	var entry := entries[at]
	var name := ItemDB.item_name(entry.id)
	var hints: Array = ["wheel"] if entries.size() > 1 else []
	var value := "%d/%d" % [at + 1, entries.size()]
	if int(entry.index) >= 0:
		var worn := p.weapons[entry.index]
		var gun := worn as Gun
		var detail := name
		if gun and gun.is_power():
			detail = "%s · %d" % [name, gun.ammo_in_mag + gun.reserve_ammo] if not gun.is_spent() else "%s · spent" % name
		if int(entry.index) == p.active_weapon_index:
			# The one in hand is stored back into the pack with a click (the
			# summon in reverse); a heavy weapon never goes in a pack.
			if Loadout.summonable(entry.id) and not p.inventory.is_full() and p.materialize_left <= 0.0:
				return _slot("weapon", value, "%s · store" % detail, hints + ["click"], -1.0, false, false, entries.size(), at)
			return _slot("weapon", value, "%s · in hand" % detail, hints, -1.0, false, false, entries.size(), at)
		return _slot("weapon", value, detail, hints + ["click"], -1.0, false, false, entries.size(), at)
	return _slot("weapon", value, name, hints, -1.0, false, false, entries.size(), at)


## The weapon icon at home: the weapons worn, then every other one owned,
## which a click equips (`HomeBase.watch_weapons`).
static func base_weapon_slot(p: Actor, entries: Array[Dictionary], picked := 0) -> Dictionary:
	if entries.is_empty():
		return _slot("weapon", "", "No weapon", [], -1.0, true, false)
	var at := clampi(picked, 0, entries.size() - 1)
	var entry := entries[at]
	var hints: Array = ["wheel"] if entries.size() > 1 else []
	var value := "%d/%d" % [at + 1, entries.size()]
	var name := ItemDB.item_name(entry.id)
	if int(entry.index) >= 0 and int(entry.index) == p.active_weapon_index:
		# At home, storing the one in hand takes it off the loadout.
		return _slot("weapon", value, "%s · store" % name, hints + ["click"], -1.0, false, false, entries.size(), at)
	if int(entry.index) >= 0:
		return _slot("weapon", value, name, hints + ["click"], -1.0, false, false, entries.size(), at)
	return _slot("weapon", value, "%s · equip" % name, hints + ["click"], -1.0, false, false, entries.size(), at)


## The vehicle icon at home: every vehicle owned, one to throw, or packing
## the one looked at.
static func base_vehicle_slot(toys: Array[String], picked := 0, packing := false) -> Dictionary:
	if packing:
		return _slot("vehicle", "+", "Pack it onto your watch", ["click"], -1.0, false, true)
	if toys.is_empty():
		return _slot("vehicle", "", "No vehicle", [], -1.0, true, false)
	var at := clampi(picked, 0, toys.size() - 1)
	return _slot("vehicle", "%d" % toys.size(), ItemDB.item_name(toys[at]),
			(["wheel"] if toys.size() > 1 else []) + ["click"], -1.0, false, false, toys.size(), at)


## The watch card at home (`HomeBase`), where there is no raid: the same
## icons, each saying what it holds for the next deploy. `loadout` is the
## base's loadout (slot -> item id). The squad portal (`portal_slot`, on
## `portal_pick`) is the one icon used from here: it is how you leave for a
## world. The rest is the base's stations' job.
static func base_watch_slots(base_name: String, loadout: Dictionary, held: Array[Dictionary] = [],
		portal_pick := 0, objective := "",
		mission_pick := 0, mission_open := false) -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	var worn: Array[String] = []
	for slot: String in ["primary", "sidearm", "melee"]:
		var id: String = loadout.get(slot, "")
		if id != "" and ItemDB.has_item(id):
			worn.append(ItemDB.item_name(id))
	slots.append(_slot("weapon", str(worn.size()) if not worn.is_empty() else "",
			" · ".join(worn) if not worn.is_empty() else "No weapon", [], -1.0, worn.is_empty(), false))
	var vehicle: String = loadout.get("vehicle", "")
	if vehicle != "" and ItemDB.has_item(vehicle):
		slots.append(_slot("vehicle", "1", ItemDB.item_name(vehicle), [], -1.0, false, false))
	else:
		slots.append(_slot("vehicle", "", "No vehicle", [], -1.0, true, false))
	var relic: String = loadout.get("artifact", "")
	if relic != "" and ItemDB.has_item(relic):
		slots.append(_slot("artifact", "", ItemDB.item_name(relic), [], -1.0, false, false))
	else:
		slots.append(_slot("artifact", "", "No artifact", [], -1.0, true, false))
	slots.append(_slot("pack", "", "Your pack fills out in a world", [], -1.0, true, false))
	slots.append(_slot("map", "", base_name, [], -1.0, false, false))
	slots.append(_slot("standing", "", "At home", [], -1.0, true, false))
	slots.append(portal_slot(Portal.from_base(), portal_pick))
	slots.append(mission_slot(mission_entries(held, objective), {}, mission_pick, mission_open))
	slots.append(_slot("leave", "", "Home", [], -1.0, true, false))
	slots.append(_slot("abandon", "", "Nothing to abandon at home", [], -1.0, true, false))
	return slots


## The squad portal icon: a carousel of where a portal can lead from here
## (`choices`, `Portal.choices_for`), the one `picked` out on its line.
## A click opens it in front of you for your squad to walk through.
## `signs_out`: out in a world where gear is at stake, where every portal is
## a sign-out (home first, then on from there), which the line says.
static func portal_slot(choices: Array[String], picked := 0, signs_out := false) -> Dictionary:
	if choices.is_empty():
		return _slot("portal", "", "No portal opens here", [], -1.0, true, false)
	var at := clampi(picked, 0, choices.size() - 1)
	var line := "Portal home" if choices[at] == Portal.HOME else "Portal to %s" % Portal.title_of(choices[at])
	if signs_out:
		line += " · signs you out"
	var hints: Array = ["click"] if choices.size() == 1 else ["wheel", "click"]
	return _slot("portal", "", line, hints, -1.0, false, false, choices.size(), at)


## The contract icon: how many jobs are held, and the one nearest done as its
## line, counting this life's `tally` on top (it only counts once you sign out
## alive, which the "+" says). The ring is that job's progress.
static func contract_slot(held: Array[Dictionary], tally: Dictionary) -> Dictionary:
	if held.is_empty():
		return _slot("contract", "", "No contracts", [], -1.0, true, false)
	var best := {}
	var best_share := -1.0
	var best_now := 0
	for entry in held:
		var now := Contracts.live(entry.stat, tally)
		var share := minf(float(entry.have + now) / maxf(float(entry.goal), 1.0), 1.0)
		if share > best_share:
			best = entry
			best_share = share
			best_now = now
	var line := "%s · %d/%d" % [best.title, best.have, best.goal]
	if best_now > 0:
		line += " +%d" % best_now
	if held.size() > 1:
		line += " · %d held" % held.size()
	return _slot("contract", str(held.size()), line, [], best_share, false, best_share >= 1.0)


## The mission log (Caleb's ask): everything you are working on, for the
## watch's contract icon to turn through. The new player's tour step first
## (`objective`, key `GameSettings.TOUR_KEY`), then each contract held (its
## id as the key). Each: {"key", "title", "have", "goal", "stat", "tour"}.
static func mission_entries(held: Array[Dictionary], objective := "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if objective != "":
		out.append({"key": GameSettings.TOUR_KEY, "title": objective, "have": 0, "goal": 0, "stat": "", "tour": true})
	for entry in held:
		out.append({"key": str(entry.get("id", "")), "title": str(entry.get("title", "")),
				"have": int(entry.get("have", 0)), "goal": int(entry.get("goal", 1)),
				"stat": str(entry.get("stat", "")), "tour": false})
	return out


## The contract icon as the mission log: closed, the job nearest done
## (`contract_slot`) or the tour's step; opened with a click, the wheel turns
## through every mission (`mission_entries`) and a click turns the picked one
## from on the visor's objective block to the main one (first and lit) to
## off it and back (`GameSettings.cycle_mission`). With only one mission a
## click turns it straight away.
static func mission_slot(entries: Array[Dictionary], tally: Dictionary, picked := 0, opened := false) -> Dictionary:
	if entries.is_empty():
		return _slot("contract", "", "No missions", [], -1.0, true, false)
	var held: Array[Dictionary] = []
	for entry in entries:
		if not entry.tour:
			held.append(entry)
	var slot := contract_slot(held, tally) if not held.is_empty() \
			else _slot("contract", "", str(entries[0].title), [], -1.0, false, false)
	slot["value"] = str(entries.size())
	slot["count"] = entries.size()
	var at := clampi(picked, 0, entries.size() - 1)
	slot["index"] = at
	if opened or entries.size() == 1:
		var entry: Dictionary = entries[at if opened else 0]
		var line := str(entry.title)
		if not entry.tour:
			line += " · %d/%d" % [int(entry.have), int(entry.goal)]
			var now := Contracts.live(str(entry.stat), tally)
			if now > 0:
				line += " +%d" % now
		line += {"main": " · main", "on": " · on visor", "off": " · off visor"}[GameSettings.mission_state(str(entry.key))]
		slot["detail"] = line
	elif not opened:
		# Closed, the main mission is the line, if one is pinned.
		for entry in entries:
			if GameSettings.mission_state(str(entry.key)) == "main":
				slot["detail"] = "Main · " + str(entry.title)
	slot["hints"] = ["wheel", "click"] if opened else ["click"]
	return slot


## What the race icon offers, in order: a live race (join the next start),
## back to the grid for a time trial, which ghost to chase (each click
## turns to the next of `Race.GHOST_PICKS`), and stopping the run. `PlayerController.race_actions` turns a pick into one of these.
const RACE_ACTIONS := ["race", "restart", "ghost", "retire"]


## The race icon, in the contract's place on a race track (drawn as a flag,
## its "glyph"): the run's line and how far round it is, or what each pick
## does once opened.
static func race_slot(view: Dictionary, picked: int, opened: bool, ghost_pick: String,
		ghost := {}) -> Dictionary:
	var at := clampi(picked, 0, RACE_ACTIONS.size() - 1)
	var line := Race.run_line(view)
	if opened:
		match RACE_ACTIONS[at]:
			"race":
				match str(view.get("heat", "")):
					"forming":
						line = "In the next race · " + Race.run_line(view)
					"racing":
						line = "Racing · " + Race.place_tag(view)
					_:
						line = "Race · join the next start, AI fill the grid"
			"restart":
				line = "Time trial · back to the grid" if not view.is_empty() else "Time trial on this machine"
			"ghost":
				line = ghost_line(ghost_pick, ghost, view.is_empty())
			"retire":
				line = "Stop the run and get off"
	elif line == "":
		line = "Race or time trial · take a machine from the pit bays"
	var value := ""
	if not view.is_empty():
		value = "%d/%d" % [int(view.get("lap", 1)), int(view.get("laps", 1))] if str(view.get("phase")) != "done" else "✓"
		if Race.place_tag(view) != "":
			value = "P%d" % int(view.place)
		elif str(view.get("phase")) == "waiting":
			value = Race.format_countdown(Race.run_starts_in(view))
	var slot := _slot("contract", value, line, ["wheel", "click"] if opened else ["click"], Race.run_progress(view),
			false, str(view.get("phase", "")) in ["grid", "waiting"], RACE_ACTIONS.size(), at)
	slot["glyph"] = "race"
	return slot


## The race icon's ghost pick in one line: whose lap runs beside you, and
## its time once it is here.
static func ghost_line(pick: String, ghost: Dictionary, no_run: bool) -> String:
	var whose := {"mine": "your best", "friend": "a friend's best", "leader": "the board leader's"}
	if pick == "off" or not whose.has(pick):
		return "Ghost off"
	var line := "Ghost · " + str(whose[pick])
	if not ghost.is_empty():
		line = "Ghost · %s %s" % ["your best" if pick == "mine" else str(ghost.name), Race.format_time(float(ghost.lap))]
	elif not no_run:
		line += " · none yet"
	return line


## The artifact icon: uses left (or a countdown), a ring while it runs or
## recharges, and a click to use it when it is ready.
static func artifact_slot(relic: Artifact) -> Dictionary:
	if relic == null or not relic.enabled:
		return _slot("artifact", "", "No artifact", [], -1.0, true, false)
	var value := ""
	var progress := -1.0
	if relic.is_active():
		value = str(ceili(relic.active_left))
		progress = relic.active_left / maxf(relic.duration, 0.01)
	elif relic.cooldown_left > 0.0:
		value = str(ceili(relic.cooldown_left))
		progress = 1.0 - relic.cooldown_left / maxf(relic.cooldown, 0.01)
	elif relic.charges > 0:
		value = str(relic.uses_left)
	return _slot("artifact", value, relic.status_text(), ["click"] if relic.is_ready() else [], progress,
			relic.is_spent(), relic.is_active())


static func _slot(id: String, value: String, detail: String, hints: Array, progress: float, empty: bool,
		alert: bool, count := 0, index := 0) -> Dictionary:
	return {"id": id, "tab": Wrist.tab_of(id), "value": value, "detail": detail, "hints": hints,
			"progress": progress, "empty": empty, "alert": alert, "count": count, "index": index}


## The icon the card opens on before you look anywhere: what is happening
## (a sign-out or banking, a vehicle to pack), else the vehicles.
static func default_focus(slots: Array[Dictionary]) -> int:
	var vehicle := -1
	for i in slots.size():
		var slot := slots[i]
		if slot.id == "leave" and float(slot.progress) >= 0.0:
			return i
		if slot.id == "vehicle":
			vehicle = i
	return maxi(vehicle, 0)


## The card's words, for reading it back (tests, and a screen reader one
## day): the death report while down, else each icon's open line.
static func wrist_text(p_raid: Raid, p: Actor, death: Dictionary, wait: float, picked_toy := 0,
		pack_name := "") -> String:
	if not death.is_empty():
		return death_text(death, wait, drop_choices(p_raid, p))
	var lines: Array[String] = []
	for slot in watch_slots(p_raid, p, picked_toy, pack_name):
		lines.append(slot.detail)
	lines.append(pack_text(p))
	return "\n".join(lines)


## The landing warning (DESIGN.md "Flight HUD"): heat this far up the bar
## starts it, and a skim with this many seconds left.
const LANDING_HEAT := 0.75
const LANDING_SKIM := 0.6
## How far down the warning looks for ground (m).
const LANDING_REACH := 200.0


## How close the rig is to cutting out, 0 to 1: shut off (a jam) or
## overheated is 1; heat climbing past `LANDING_HEAT` and a boot skim
## running out build toward it. Overclocked, heat never counts.
static func landing_risk(rig: FlightRig) -> float:
	if not rig.enabled:
		return 0.0
	if rig.jam_left > 0.0 or rig.overheated:
		return 1.0
	var risk := 0.0
	if not rig.heat_free and rig.max_heat > 0.0:
		risk = clampf((rig.heat_fraction() - LANDING_HEAT) / (1.0 - LANDING_HEAT), 0.0, 1.0)
	if rig.is_skimming and rig.skim_time > 0.0:
		risk = maxf(risk, clampf(1.0 - rig.skim_left / LANDING_SKIM, 0.0, 1.0))
	return risk


## True if dropping from `height` meters, already falling at `fall_speed`,
## would land hard enough to hurt (`Actor.fall_safe_speed`, scaled by the
## rig: boots take none, so they never warn).
static func fall_would_hurt(p: Actor, height: float, fall_speed: float) -> bool:
	var mult := p.flight.fall_damage_mult if p.flight.enabled else 1.0
	if mult <= 0.0 or height <= 0.0:
		return false
	var impact := sqrt(fall_speed * fall_speed + 2.0 * p.gravity * height)
	return impact > p.fall_safe_speed


## The landing warning for `p`, 0 to 1: ground below that a fall would hurt
## on, while the rig is about to cut out, so you land or pulse before you
## drop. View only, read each frame for the player's own visor and pack
## screen; the ray is only cast once the rig is at risk.
static func landing_warning(p: Actor) -> float:
	if p == null or p.is_dead or p.vehicle != null or not p.flight.enabled or p.is_on_floor():
		return 0.0
	var risk := landing_risk(p.flight)
	if risk <= 0.0:
		return 0.0
	var height := p.height_above_ground(LANDING_REACH)
	return risk if fall_would_hurt(p, height, maxf(0.0, -p.velocity.y)) else 0.0


## What the landing warning says is wrong, in the visor's capitals.
static func landing_reason(rig: FlightRig) -> String:
	if rig.jam_left > 0.0:
		return "RIG JAMMED"
	if rig.overheated:
		return "RIG OVERHEATED"
	if rig.is_skimming and rig.skim_time > 0.0 and rig.skim_left < LANDING_SKIM:
		return "SKIM ENDING"
	return "RIG HOT"


## The flight rig's cue, at the visor's edge under the heat gauge (or on the
## card's vitals strip without the glass): overheating, then what the rig
## needs you to know in the air. A jetpack warns when a heat seeker could lock on
## (`Gun.heat_target`'s rule); wings show airspeed against the stall and
## the boosts left this flight; boots show their dash charges and the skim
## time left.
static func rig_text(p: Actor) -> String:
	var rig := p.flight
	if not rig.enabled:
		return ""
	if rig.overheated:
		return "%s OVERHEATED" % rig.display_name.to_upper()
	if rig.can_glide() and (rig.is_gliding or p.airborne_time > 0.3):
		var air := Vector2(p.velocity.x, p.velocity.z).length()
		var stall := rig.glide_speed * rig.glide_stall
		var pulse := ""
		if rig.pulse_velocity > 0.0:
			pulse = "   pulse ready" if rig.heat + rig.pulse_heat <= rig.max_heat else "   pulse cooling"
		if rig.max_charges > 0:
			pulse += "   boosts %d" % rig.charges
		return "Air %d m/s%s%s" % [roundi(air), "  STALL" if air < stall - 0.5 else "", pulse]
	if rig.can_skim() and rig.max_charges > 0:
		var skim := "skim %.1fs" % rig.skim_left if rig.is_skimming else ("" if rig.skim_left > 0.0 else "skim spent")
		return ("dashes %d/%d   %s" % [rig.charges, rig.max_charges, skim]).strip_edges()
	if rig.can_skim() and (rig.is_skimming or p.airborne_time > 0.3):
		var dashes := floori((rig.max_heat * (1.0 + FlightRig.BURST_SLACK) - rig.heat) / maxf(rig.air_dash_heat, 1.0))
		var band: String = ["low, cooling", "warm", "BURNING"][rig.skim_band()] if rig.is_skimming else "falling"
		return "Skim %s   dashes %d" % [band, clampi(dashes, 0, 3)]
	if rig.can_hover() and rig.is_hovering:
		var state := "coasting" if rig.is_coasting else ("boost" if rig.is_boosting else "jets lit")
		var lockable := rig.is_thrusting or rig.heat >= rig.max_heat * 0.3
		return "%s  %s%s" % [rig.display_name, state, "   LOCKABLE" if lockable else ""]
	return ""


## The vitals: health, armor and stamina from 0 to 1, flight heat (-1 with
## no flight rig) and body heat (-1 where there is no cold). On the visor's
## edges, or the card's strip without one.
static func wrist_bars(p: Actor) -> Array[float]:
	return [p.health.health / p.health.max_health,
			p.health.armor / p.health.max_armor if p.health.max_armor > 0.0 else 0.0,
			p.stamina / p.max_stamina,
			p.flight.heat_fraction() if p.flight.enabled else -1.0,
			p.body_heat / maxf(p.max_body_heat, 1.0) if feels_cold(p) else -1.0]


## Whether someone is out in a world with cold (`WorldDef.cold`), where body
## heat is a vital worth showing.
static func feels_cold(p: Actor) -> bool:
	if p == null or not p.is_inside_tree():
		return false
	var raid := Raid.of(p)
	return raid != null and raid.world != null and raid.world.cold > 0.0 and not raid.world.safe_zone


## Keeps a counter on each carried gun's model: rounds in the magazine over
## what is in reserve.
func _update_ammo_counters(p: Actor) -> void:
	for w in p.weapons:
		var gun := w as Gun
		if gun == null or gun.visual == null or not is_instance_valid(gun.visual):
			continue
		var counter := gun.visual.get_node_or_null(AMMO_COUNTER) as Label3D
		if counter == null:
			counter = Label3D.new()
			counter.name = AMMO_COUNTER
			counter.font_size = 48
			counter.pixel_size = 0.0007
			counter.outline_size = 8
			counter.no_depth_test = true
			counter.render_priority = 2
			counter.position = Vector3(0.0, 0.085, 0.06)
			counter.rotation.x = -0.35
			gun.visual.add_child(counter)
		counter.text = ammo_text(gun)
		counter.modulate = Color(1.0, 0.4, 0.3) if gun.ammo_in_mag <= gun.mag_size / 5 else Color(0.55, 1.0, 0.75)


## Lights the screen bay on the back of a worn jetpack (the rig model's
## `HEAT_DISPLAY` marker) with a heat gauge: a bar that fills and turns from
## green to red, and a word over it. Others see it on your back; you see it
## in third person. The skin builds the model, so headless there is none.
func _update_heat_display(p: Actor) -> void:
	var bay := p.find_child(HEAT_DISPLAY, true, false) as Node3D
	if bay == null:
		return
	var readout := bay.get_node_or_null(HEAT_READOUT) as Node3D
	if readout == null:
		readout = _build_heat_readout(bay.get_meta("size", Vector2(0.13, 0.15)))
		bay.add_child(readout)
	var heat := p.flight.heat_fraction() if p.flight.enabled else 0.0
	var fill := readout.get_node("Fill") as MeshInstance3D
	var room: float = readout.get_meta("bar_height")
	fill.scale.y = maxf(0.001, heat)
	fill.position.y = readout.get_meta("bar_bottom") + room * heat * 0.5
	var color := heat_color(heat, p.flight.overheated)
	var word := readout.get_node("Word") as Label3D
	word.text = heat_text(p.flight)
	# The landing warning pulses the screen: the word flashes LAND and the
	# bar beats (DESIGN.md "Flight HUD", third person).
	var landing := landing_warning(p)
	if landing > 0.0:
		var beat := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * lerpf(6.0, 14.0, landing))
		word.text = "LAND"
		color = color.lerp(Color(1.0, 0.2, 0.1), 0.6).lerp(Color(0.25, 0.04, 0.02), 1.0 - beat)
		(fill.material_override as StandardMaterial3D).emission_energy_multiplier = lerpf(1.6, 4.0, beat)
	else:
		(fill.material_override as StandardMaterial3D).emission_energy_multiplier = 1.6
	(fill.material_override as StandardMaterial3D).albedo_color = color
	(fill.material_override as StandardMaterial3D).emission = color
	word.modulate = color


func _build_heat_readout(room: Vector2) -> Node3D:
	var readout := Node3D.new()
	readout.name = HEAT_READOUT
	var bar := Vector2(room.x * 0.6, room.y * 0.6)
	var bottom := -room.y * 0.5 + room.y * 0.08
	readout.set_meta("bar_height", bar.y)
	readout.set_meta("bar_bottom", bottom)
	var back := _flat_quad(bar + Vector2(0.008, 0.008), Color(0.02, 0.025, 0.03), 0.0)
	back.position = Vector3(0, bottom + bar.y * 0.5, 0.001)
	readout.add_child(back)
	var fill := _flat_quad(Vector2(bar.x, bar.y), Color(0.4, 1.0, 0.6), 1.6)
	fill.name = "Fill"
	fill.position = Vector3(0, bottom, 0.002)
	readout.add_child(fill)
	var word := Label3D.new()
	word.name = "Word"
	word.font_size = 40
	word.pixel_size = 0.0011
	word.outline_size = 6
	word.position = Vector3(0, room.y * 0.5 - room.y * 0.14, 0.003)
	readout.add_child(word)
	return readout


static func _flat_quad(size: Vector2, color: Color, energy: float) -> MeshInstance3D:
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = size
	quad.mesh = mesh
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	if energy > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = energy
	quad.material_override = mat
	return quad


## The word on the jetpack's screen: the heat in percent, or that it is
## locked out cooling down.
static func heat_text(flight: FlightRig) -> String:
	if flight.overheated:
		return "HOT"
	return "%d%%" % roundi(flight.heat_fraction() * 100.0)


## Green when cool, through amber, to red when hot or locked out.
static func heat_color(heat: float, overheated: bool) -> Color:
	if overheated:
		return Color(1.0, 0.25, 0.15)
	var cool := Color(0.4, 1.0, 0.6)
	var warm := Color(1.0, 0.75, 0.2)
	var hot := Color(1.0, 0.3, 0.15)
	return cool.lerp(warm, heat / 0.6) if heat < 0.6 else warm.lerp(hot, (heat - 0.6) / 0.4)


## The counter on a gun: "24 | 90", or that it is reloading.
static func ammo_text(gun: Gun) -> String:
	if gun.is_reloading():
		return "RELOAD"
	return "%d | %d" % [gun.ammo_in_mag, gun.reserve_ammo]


## The side a nearby enemy swing is coming at the player, as the player sees
## it (the side to guard), or -1 when nothing is winding up in front of them.
static func incoming_side(p: Actor) -> int:
	if p.is_dead or not p.is_inside_tree():
		return -1
	var forward := p.get_aim_dir()
	forward.y = 0.0
	var best := -1
	var best_dist := INF
	for node in p.get_tree().get_nodes_in_group("actors"):
		var other := node as Actor
		if other == null or other == p or other.is_dead:
			continue
		var blade := other.get_active_weapon() as MeleeWeapon
		# A windup, or a heavy being held back: both show their side.
		if blade == null or blade.threat_dir() < 0:
			continue
		var to := other.global_position - p.global_position
		to.y = 0.0
		var dist := to.length()
		if dist > blade.reach * 2.5 or dist >= best_dist:
			continue
		if dist > 0.5 and forward.length() > 0.01 and forward.normalized().dot(to.normalized()) < 0.2:
			continue
		best = MeleeWeapon.mirror(blade.threat_dir())
		best_dist = dist
	return best


func _on_hit_confirmed(_target: Actor, info: DamageInfo, lethal: bool) -> void:
	var kind := HitMarker.kind_of(info, lethal)
	_hit_marker.flash(kind)


func _on_player_damaged(info: DamageInfo) -> void:
	_hurt_flash.color.a = clampf(_hurt_flash.color.a + 0.12 + info.amount * 0.012, 0.0, 0.45)


## Shows what the local player's death cost them and how to carry on.
## `wait` is how many seconds until they may drop back in.
func show_death(result: Dictionary, wait: float) -> void:
	_death_result = result
	_redeploy_wait = wait


## The words on the death screen.
## Where the player may land next (`Raid.drop_choices`). Only the authority
## knows a player's owner key; a client is offered the world's own places.
static func drop_choices(p_raid: Raid, p: Actor) -> Array:
	var state := p_raid.state_for(p)
	return p_raid.drop_choices(state.owner if state != null and p_raid.mode != Raid.Mode.CLIENT else "")


## `drops` is where they may land next (`Raid.drop_choices`), and `picked`
## the one picked out with the wheel, marked with a pointer: a click drops
## in there.
static func death_text(result: Dictionary, wait: float, drops: Array = [], picked := 0) -> String:
	var by: String = result.get("killed_by", "")
	var lost: Array = result.get("lost", [])
	var lines: Array[String] = ["Killed by %s" % by if by != "" else "You died"]
	lines.append("Lost: %s" % ItemDB.summarize(lost) if not lost.is_empty() else "Nothing lost")
	if int(result.get("renown_lost", 0)) > 0:
		lines.append("Renown lost: %d" % int(result.renown_lost))
	if int(result.get("scrip_lost", 0)) > 0:
		lines.append("Scrip dropped: %d" % int(result.scrip_lost))
	var kept: Array = result.get("kept_gear", [])
	if not kept.is_empty():
		lines.append("Kept: %s" % ItemDB.summarize(kept))
	if str(result.get("recalled", "")) != "":
		lines.append("Insured, recalled home: %s" % ItemDB.item_name(result.recalled))
	var salvage: Array = result.get("salvage", [])
	if not salvage.is_empty():
		lines.append("Salvaged: %s" % SafetyNets.describe(salvage))
	var banked: Array = result.get("banked", [])
	if not banked.is_empty():
		lines.append("Banked before you fell: worth %d" % int(result.get("banked_value", 0)))
	lines.append("")
	if wait > 0.0:
		lines.append("Drop back in in %d..." % ceili(wait))
	else:
		# One place to land is no choice: Enter is enough.
		if drops.size() > 1:
			var at := clampi(picked, 0, drops.size() - 1)
			for i in drops.size():
				lines.append("%s%d: %s, %s" % [DEATH_PICK if i == at else "    ", i + 1, drops[i].title, drops[i].note])
			lines.append("")
		lines.append("Click or Enter: drop back in      L: return to the hub")
	return "\n".join(lines)


## The local player's standing: rank, session renown, streak, and whether
## they are being hunted. Scrip is on the pack's icon instead.
static func standing_text(p: Actor) -> String:
	var text := "%s   Renown %d" % [RenownLedger.rank_name(p.rank), p.renown]
	if p.streak > 1:
		text += "   Streak %d" % p.streak
	if p.bounty > 0:
		text += "   BOUNTY %d" % p.bounty
	if p.exposed:
		text += "   EXPOSED"
	if p.marked:
		text += "   THE MARKED"
	return text


## Strongpoints: the one the player is standing in, in full, or else how
## many of the world's they hold ("Held 1/3").
static func sites_text(p_raid: Raid, p: Actor) -> String:
	if p_raid.strongpoints.is_empty():
		return ""
	var here := p_raid.strongpoint_at(p) if not p.is_dead else null
	if here != null:
		return here.status(p_raid.holds(p, here))
	var mine := 0
	for point in p_raid.strongpoints:
		if p_raid.holds(p, point):
			mine += 1
	return "Held %d/%d" % [mine, p_raid.strongpoints.size()]


## News for everyone in the world: a phone notification when there is a
## phone, else a line on the wrist that stays up a little longer.
func _on_war_feed(text: String) -> void:
	if notice_sink.is_valid():
		notice_sink.call(text)
		return
	_log(text, 7.0)


## Puts a line on the wrist display.
func notify(text: String) -> void:
	_on_notice(text)


## Someone pinged a spot (`Raid.ping`). Yours and your side's stand in the
## world as a column of light for `Raid.ping_time`; a client only ever
## hears of those.
func _on_pinged(pinger: Actor, at: Vector3) -> void:
	var p := raid.player if raid != null else null
	if p == null or not is_instance_valid(p) or not is_instance_valid(pinger):
		return
	if pinger != p and raid.mode != Raid.Mode.CLIENT and not Visor.allied(p, pinger):
		return
	var mark := ping_mark(pinger.display_name if pinger != p else "")
	raid.add_child(mark)
	mark.global_position = at
	_pings.append({"node": mark, "left": raid.ping_time})
	Sfx.play("dash", null, -14.0)


## A ping's marker: a thin column of light with a ring at its foot and the
## pinger's name over it.
static func ping_mark(by := "") -> Node3D:
	var mark := Node3D.new()
	mark.name = "Ping"
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(0.35, 0.95, 1.0, 0.55)
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var column := MeshInstance3D.new()
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.03
	shaft.bottom_radius = 0.08
	shaft.height = 6.0
	shaft.material = mat
	column.mesh = shaft
	column.position = Vector3(0.0, 3.0, 0.0)
	column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mark.add_child(column)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.5
	torus.outer_radius = 0.58
	torus.material = mat
	ring.mesh = torus
	ring.position = Vector3(0.0, 0.1, 0.0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mark.add_child(ring)
	if by != "":
		var tag := Label3D.new()
		tag.text = by
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.fixed_size = true
		tag.pixel_size = 0.0012
		tag.modulate = Color(0.6, 1.0, 1.0)
		tag.position = Vector3(0.0, 6.3, 0.0)
		mark.add_child(tag)
	return mark


## Fades and clears the pings standing in the world.
func _update_pings(delta: float) -> void:
	for ping in _pings.duplicate():
		ping.left -= delta
		var mark: Node3D = ping.node
		if ping.left <= 0.0 or not is_instance_valid(mark):
			_pings.erase(ping)
			if is_instance_valid(mark):
				mark.queue_free()
			continue
		# The ring breathes; the whole mark thins out over its last second.
		mark.scale = Vector3.ONE * (1.0 + 0.08 * sin(ping.left * 6.0))
		mark.visible = ping.left > 1.0 or fmod(ping.left, 0.2) > 0.08


## The pings standing in the world now (for checks).
## Where the squad pings standing now are, for the watch map.
func ping_spots() -> Array[Vector3]:
	var spots: Array[Vector3] = []
	for ping in _pings:
		var node: Node3D = ping.node
		if is_instance_valid(node):
			spots.append(node.global_position)
	return spots


func pings_shown() -> int:
	return _pings.size()


## How long a line on the race radio stays up, and how many at once.
const COMMS_TIME := 6.0
const COMMS_KEPT := 3


## A rival said something to you on the race radio (`Race.radio`).
func _on_radio(actor: Actor, from: String, text: String) -> void:
	if raid == null or actor != raid.player:
		return
	comms.append({"from": from, "text": text, "left": COMMS_TIME})
	while comms.size() > COMMS_KEPT:
		comms.pop_front()
	Sfx.play("radio")
	if visor == null or not (visor.glass_shown() or visor.flat_shown()):
		_log("%s: %s" % [from, text], COMMS_TIME)


func _on_notice(text: String) -> void:
	_log(text, 4.0)


func _log(text: String, seconds: float) -> void:
	_messages.append({"text": text, "time": seconds})
	if _messages.size() > 6:
		_messages.pop_front()


func _label(parent: Control, text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


## Anchors a control to a point of the screen (0..1) with a pixel offset and size.
func _place(control: Control, ax: float, ay: float, offset: Vector2, size: Vector2) -> void:
	control.anchor_left = ax
	control.anchor_right = ax
	control.anchor_top = ay
	control.anchor_bottom = ay
	control.offset_left = offset.x
	control.offset_top = offset.y
	control.offset_right = offset.x + size.x
	control.offset_bottom = offset.y + size.y


## A thin ring round the crosshair that fills clockwise from the top as a
## bank or sign-out goes on, over a faint full ring. Hidden below 0.
class ProgressRing:
	extends Control

	const BANKING := Color(0.45, 0.9, 1.0)
	const LEAVING := Color(0.55, 1.0, 0.55)
	var value := -1.0
	var color := BANKING

	func show_progress(p_value: float, p_color: Color) -> void:
		if is_equal_approx(p_value, value) and p_color == color:
			return
		value = p_value
		color = p_color
		queue_redraw()

	func _draw() -> void:
		if value < 0.0:
			return
		var c := size * 0.5
		var radius := minf(size.x, size.y) * 0.5 - 3.0
		var faint := color
		faint.a = 0.18
		draw_arc(c, radius, 0.0, TAU, 64, faint, 2.0, true)
		if value > 0.0:
			draw_arc(c, radius, -PI / 2.0, -PI / 2.0 + TAU * clampf(value, 0.0, 1.0), 64, color, 3.0, true)


## Four diagonal ticks around the crosshair that flash when your attack lands.
class HitMarker:
	extends Control

	## Each kind of hit has its own look, so a glance says what a hit did:
	## [color, how long it shows, how big]. A head is gold and larger, a hit
	## the plates soaked is steel blue, the hit that broke them a wide
	## cyan, and a kill red and longest.
	const KINDS := {
		"hit": [Color.WHITE, 0.15, 1.0],
		"armor": [Color(0.62, 0.78, 1.0), 0.15, 0.85],
		"armor_break": [Color(0.35, 0.95, 1.0), 0.3, 1.35],
		"head": [Color(1.0, 0.82, 0.25), 0.22, 1.3],
		"guarded": [Color(0.6, 0.75, 1.0), 0.15, 0.75],
		"kill": [Color(1.0, 0.25, 0.2), 0.35, 1.45],
	}

	var kind := ""
	var _left := 0.0
	var _duration := 0.15
	var _color := Color.WHITE
	var _size := 1.0

	## Which `KINDS` entry a confirmed hit shows. A kill outranks a head, a
	## head outranks plates breaking, and that outranks plates soaking.
	static func kind_of(info: DamageInfo, lethal: bool) -> String:
		if lethal:
			return "kill"
		if info.parried or info.blocked:
			return "guarded"
		if info.headshot:
			return "head"
		if info.armor_broke:
			return "armor_break"
		if info.armored:
			return "armor"
		return "hit"

	func flash(p_kind: String) -> void:
		var look: Array = KINDS.get(p_kind, KINDS["hit"])
		kind = p_kind
		_color = look[0]
		_duration = look[1]
		_size = look[2]
		_left = _duration
		queue_redraw()

	func _process(delta: float) -> void:
		if _left > 0.0:
			_left -= delta
			queue_redraw()

	func _draw() -> void:
		if _left <= 0.0:
			return
		var c := size * 0.5
		var color := _color
		color.a = clampf(_left / _duration, 0.0, 1.0)
		# The marks spring out a little as they fade.
		var grow := _size * (1.0 + 0.25 * (1.0 - color.a))
		for dir: Vector2 in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
			draw_line(c + dir * 7.0 * grow, c + dir * 15.0 * grow, color, 2.5 * _size)

## A mark beside the crosshair on the side an enemy swing is coming from, so
## a blade out in first person reads a swing at the edge of the view. Guards
## turn to meet a swing by themselves; the mark is only for timing.
## Kept as an inner class so the HUD never depends on the editor's class cache.
class StanceIndicator:
	extends Control

	const OFFSETS := [Vector2(0, -1), Vector2(-1, 0), Vector2(1, 0)]

	## The side of the screen an enemy swing is coming at, or -1 for none.
	var threat := -1

	var threat_radius := 48.0
	var mark_length := 22.0


	func _process(_delta: float) -> void:
		queue_redraw()


	func _draw() -> void:
		var center := size * 0.5
		for dir in OFFSETS.size():
			var out: Vector2 = OFFSETS[dir]
			var along := Vector2(-out.y, out.x) * mark_length * 0.5
			if dir == threat:
				var at := center + out * threat_radius
				# Yellow on a dark outline, so it shows against red enemies and sky.
				draw_line(at - along * 1.6, at + along * 1.6, Color(0, 0, 0, 0.85), 12.0)
				draw_line(at - along * 1.5, at + along * 1.5, Color(1.0, 0.9, 0.15), 7.0)


## Shows or hides the aiming marks in the middle of the screen, which would
## sit on your face in the phone's mirror.
func show_aim(on: bool) -> void:
	if crosshair:
		crosshair.visible = on
	if _stance:
		_stance.visible = on


## A holographic watch on your left wrist. Lowered, it is only a watch: a
## band and a small lit face, nothing in the view. Raised (`raised`, the
## `check_wrist` key, and on its own while you are down), it projects a
## small card of light just above the face, about the size of a playing
## card, in three tabs (`TABS`) named along its top. Summon is the carousel
## of what you carry: weapons (worn and in the pack), toy vehicles and
## artifacts, with the pack's fill and worth under it. Status is the map
## and your standing. Mission is the portal, the contract, and sign-out
## and banking. The open tab's icons stand in a row; the open icon grows and
## its one line shows under the row, with its controls as glyphs (a mouse
## wheel, a click, a key cap), never written out. Which icon is open is
## `PlayerController.watch_focus`: the mouse wheel steps across the card,
## tab after tab (and through the weapons, toys and artifacts on their
## icons), and the mouse only looks. The things picked from stand over the
## card as small holograms. Some things only pop up when they matter: what
## the death cost and where you can land while you are down, the flight
## rig's cue while flying, and a brief notice.
## Your vitals are not on the card while the visor shows them (`VisorHud`);
## with no helmet, or in third person, the card carries them as a thin strip.
##   - First person, where your own body is not drawn: a forearm comes up
##     into the bottom of the view with the watch on it, and the card opens
##     over the watch.
##   - Third person: the watch rides on the character's left wrist bone, and
##     the card opens just above it at its real size, turned to the camera,
##     with a soft glow on the arm. It is never pulled out towards the camera
##     as a floating panel.
## Sizes in first person follow the camera's field of view, so a wide view
## does not shrink it.
class Wrist:
	extends Node3D

	const VehicleScript := preload("res://core/vehicle/vehicle.gd")

	## The card's tabs, left to right, and the icons on each.
	const TABS := ["summon", "status", "mission"]
	const TAB_SLOTS := {
		"summon": ["weapon", "vehicle", "artifact", "pack"],
		"status": ["map", "standing"],
		"mission": ["portal", "contract", "leave", "abandon"],
	}
	## What each tab holds, the line shown on the tab row.
	const TAB_LINES := {
		"summon": "Weapons · vehicles · artifacts · pack",
		"status": "Map · standing",
		"mission": "Portal · missions · sign out · abandon",
	}
	## Every icon, left to right, tab after tab (see `Hud.watch_slots`).
	const SLOTS := ["weapon", "vehicle", "artifact", "pack", "map", "standing", "portal", "contract", "leave", "abandon"]
	const HOLO_TINT := Color(0.75, 1.0, 1.0, 0.95)
	const GLOW_COLOR := Color(0.35, 0.95, 1.0)
	## The card as projected light: faint scanlines that crawl up it, a
	## brighter band sweeping through now and then, a slight flicker, edges
	## that thin out, and a shimmer across it while it is still opening.
	const HOLO_SHADER := """
shader_type spatial;
render_mode unshaded, DEPTH, cull_disabled, blend_mix, shadows_disabled;
uniform sampler2D card : source_color, filter_linear;
uniform vec4 tint : source_color = vec4(0.75, 1.0, 1.0, 0.95);
uniform float open = 1.0;
// A dark glass behind the card's lines (0 none, 1 solid), so the world
// does not show through where it has to be read.
uniform float backing = 0.0;
// How deep the scan lines run (0 none): a card full of small text, like the
// phone's, keeps them faint so they never dim a line of it.
uniform float line_depth = 0.14;
void fragment() {
	vec2 uv = UV;
	float settle = 1.0 - open;
	uv.x += settle * 0.03 * sin(uv.y * 90.0 + TIME * 40.0);
	// Four taps across the pixel's footprint on the card: drawn smaller than
	// its texture (a viewport texture has no mipmaps) one tap would skip
	// whole strokes of the text and crawl as the card moves.
	vec2 dx = dFdx(uv) * 0.25;
	vec2 dy = dFdy(uv) * 0.25;
	vec4 c = (texture(card, uv + dx + dy) + texture(card, uv + dx - dy)
			+ texture(card, uv - dx + dy) + texture(card, uv - dx - dy)) * 0.25;
	float lines = 1.0 - line_depth + line_depth * sin(uv.y * 420.0 - TIME * 8.0);
	float sweep = smoothstep(0.08, 0.0, abs(fract(TIME * 0.3) * 1.4 - 0.2 - uv.y));
	float flick = 0.93 + 0.07 * sin(TIME * 53.0) * sin(TIME * 7.3);
	float edge = smoothstep(0.0, 0.012, uv.x) * smoothstep(0.0, 0.012, 1.0 - uv.x)
			* smoothstep(0.0, 0.02, uv.y) * smoothstep(0.0, 0.02, 1.0 - uv.y);
	vec3 glow = c.rgb * tint.rgb * (lines + sweep * 0.6) * flick * 1.2;
	float a = clamp(c.a * tint.a * lines * flick * edge + sweep * 0.08 * edge, 0.0, 1.0);
	float back = backing * edge;
	ALBEDO = mix(vec3(0.015, 0.03, 0.04), glow, a / max(a + back * (1.0 - a), 0.001));
	ALPHA = clamp(a + back * (1.0 - a), 0.0, 1.0) * mix(1.0, 0.6, settle);
}
"""
	## The light thrown from the watch face up to the card: bright where it
	## leaves the face (UV.y 0) and thinning towards the card (UV.y 1), with
	## faint bands of light running out along it from the watch to the card,
	## so it reads as projected outwards, never drawn in (Caleb's feedback).
	## `open` fades it while the card unfolds.
	const BEAM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec3 color : source_color = vec3(0.35, 0.95, 1.0);
uniform float open = 1.0;
void fragment() {
	float out_along = UV.y;
	float bands = 0.5 + 0.5 * sin((out_along * 6.0 - TIME * 2.8) * 6.2832);
	bands = pow(bands, 3.0);
	ALBEDO = color;
	ALPHA = clamp((mix(0.22, 0.04, out_along) + 0.08 * bands) * open, 0.0, 1.0);
}
"""
	## The bone the watch is worn on in third person.
	const WRIST_BONE := "Wrist.L"
	## The back of the wrist in that bone's space, where the watch face looks
	## out (the bone's own +Y runs along the arm to the hand).
	const FACE_AXIS := Vector3.RIGHT
	## The holographic map drawn on the card while its Map icon is read
	## (`Hud.map_marks`, set before `show_card`); empty for none.
	var map := {}
	## The icon opened with a click and being read ("" for none): its panel
	## (a list or a page) takes the card's right side (set before `show_card`).
	var opened := ""
	## On the tab row (`PlayerController.watch_tabs`): the wheel turns the
	## tabs, so the tab name is what is lit, not an icon (set before
	## `show_card`).
	var tabs := false
	## The tabletop map over the card while the Map icon is opened: how wide
	## it is (metres, from the eyes), how high its relief stands as a share
	## of that, and how far it tips back towards the eyes.
	var table_width := 0.16
	var table_relief := 0.12
	var table_tilt := 0.6
	var _table: MeshInstance3D
	## True while the watch rests after a summon or a swap (set before
	## `show_card`): the face breathes amber, so it shows even with the card
	## down, and a soft chime sounds once it is ready again (`Hud`).
	var resting := false
	var _rest_time := 0.0
	## The new player's tour objective, drawn as a small line on the card
	## (set before `show_card`). "" for none.
	var objective := ""
	## How far the back of the wrist is out from the wrist bone, in metres.
	var wrist_skin := 0.03
	## The card's face in metres, and its picture in pixels.
	var face_size := Vector2(0.18, 0.104)
	var pixels := Vector2i(520, 300)
	## Where the card opens when the camera looks out of the eyes, in the
	## camera's space, at `reference_fov`: just over the raised wrist.
	var first_person_at := Vector3(-0.1, -0.1, -0.38)
	## From the eyes, how far above the watch face the card's centre stands.
	var fp_card_lift := 0.09
	var fp_card_reads_at := 0.42
	## The field of view the sizes above are for. A wider view grows them.
	var reference_fov := 80.0
	## Third person: how big the card looks next to its first-person size
	## (it grows with the camera's distance, so it reads the same from behind
	## the shoulder), and where it hangs: in front of the character, beyond
	## them from the camera, up and to the left of the head (metres ahead
	## along the view, up from the eyes, and to the side, negative is left).
	## The light reaches out to it from the wrist.
	var third_person_view := 0.84
	var projection_at := Vector3(-0.85, 0.35, 0.9)
	## Third person (Caleb's feedback): the card stands just past the
	## character, `tp_behind` metres beyond the head from the camera, so the
	## body and the raised arm pass in front of it and it reads as thrown out
	## of the watch. It is as tall as `tp_screen` of the view however far
	## that is, beside the head off the crosshair, and backed with dark glass
	## the world still shows through (`tp_backing`; it is a hologram, Caleb's
	## call). The device, the arm and its pose are the same as in first
	## person; only where the light lands differs.
	var tp_behind := 0.25
	var tp_screen := 0.34
	var tp_lift := 0.06
	var tp_backing := 0.6
	## How far, in metres at the head, the card keeps clear of the head and
	## helmet from the camera's view.
	var head_clearance := 0.05
	## Third person: the share of the card's width, at its right edge (only
	## frame and margin there, never text), that may sit behind the head, so
	## the card stays close to the body (Caleb's feedback).
	var tp_tuck := 0.08
	## Third person: how far over the watch, as the camera sees it (a share
	## of the view's height), the card's lower edge stays, so the light
	## opens upwards from the wrist into the card rather than slanting down
	## to it (Caleb's feedback).
	var tp_over_wrist := 0.05
	## The glow on the arm while the card is up: how bright, and how far it
	## reaches.
	var glow_energy := 0.7
	var glow_range := 0.6
	## Seconds the card takes to open or close.
	var raise_time := 0.18

	## True while the card should be up.
	var raised := false
	## 0 lowered, 1 fully open.
	var raise_amount := 0.0
	## The colour the watch face glows now (see `face_tint`).
	var face_color := Color.WHITE

	## Toy vehicles over the card: how far above its top edge they stand,
	## how far apart, and how big next to a thrown toy.
	var toy_lift := 0.016
	var toy_spacing := 0.05
	var toy_size := 0.16
	## Weapons over the card: how far apart, and how long the picked one is
	## drawn, in metres (the others are two thirds of it).
	var weapon_spacing := 0.034
	var weapon_length := 0.05
	## Third person: the toy and weapon rows over the card are drawn this much
	## smaller than from the eyes (the card keeps its size), and smaller still
	## if that is what it takes to keep them in the view under its top edge
	## (`rows_tall` is how much room, in card units, a row needs over the card).
	var tp_rows := 0.5
	var rows_tall := 0.06

	var viewport: SubViewport
	var card: Card
	var _toys: Node3D
	var _toy_ids: Array[String] = []
	var _weapons: Node3D
	var _weapon_ids: Array[String] = []
	var _spin := 0.0
	var _holo: MeshInstance3D
	var _glow: OmniLight3D
	## The card's look over everything (first person) and in the world
	## (third person, hidden behind whatever is in front of it).
	var _holo_over: ShaderMaterial
	## Third person: the same card, depth tested, so the body in front of
	## it hides what it covers.
	var _holo_behind: ShaderMaterial
	var _third := false
	## How big the rows over the card are drawn now (see `tp_rows`).
	var _row_scale := 1.0
	## The light thrown up from the watch face to the card.
	var _beam: MeshInstance3D
	## The watch worn on the character's wrist bone, third person.
	var _worn: Node3D

	func _ready() -> void:
		viewport = SubViewport.new()
		viewport.size = pixels
		viewport.disable_3d = true
		viewport.transparent_bg = true
		add_child(viewport)
		card = Card.new()
		card.name = "Card"
		card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		viewport.add_child(card)

		_holo = MeshInstance3D.new()
		_holo.name = "Hologram"
		var quad := QuadMesh.new()
		quad.size = face_size
		_holo.mesh = quad
		# The card is light, drawn over everything in both views: from the
		# eyes it hangs just in front of them, and from behind it is set
		# beside the character, clear of the head (`_clear_of_head`).
		_holo_over = _holo_material(true)
		_holo_behind = _holo_material(false)
		_holo.material_override = _holo_over
		_holo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_holo)
		_beam = MeshInstance3D.new()
		_beam.name = "Beam"
		_beam.top_level = true
		_beam.mesh = ImmediateMesh.new()
		_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var beam_mat := ShaderMaterial.new()
		var beam_shader := Shader.new()
		beam_shader.code = BEAM_SHADER
		beam_mat.shader = beam_shader
		beam_mat.set_shader_parameter("color", GLOW_COLOR)
		beam_mat.render_priority = 9
		_beam.material_override = beam_mat
		add_child(_beam)
		_glow = OmniLight3D.new()
		_glow.name = "Glow"
		_glow.light_color = GLOW_COLOR
		_glow.omni_range = glow_range
		_glow.light_energy = 0.0
		_glow.shadow_enabled = false
		add_child(_glow)

	## The tab an icon is on ("" if it is not on the card).
	static func tab_of(id: String) -> String:
		for tab: String in TABS:
			if id in row(tab):
				return tab
		return ""

	## The icons on a tab, left to right: `TAB_SLOTS` without what the launch
	## holds back (`LaunchScope`: the artifact icon while artifacts are).
	static func row(tab: String) -> Array:
		var out: Array = TAB_SLOTS.get(tab, []).duplicate()
		if LaunchScope.holds_tag("artifact"):
			out.erase("artifact")
		return out

	## What a tab holds, the line shown on the tab row.
	static func tab_line(tab: String) -> String:
		var line: String = TAB_LINES.get(tab, "")
		if "artifact" in TAB_SLOTS.get(tab, []) and "artifact" not in row(tab):
			line = line.replace(" · artifacts", "")
		return line

	## Takes the watch off the character (the HUD going away).
	func take_off() -> void:
		if _worn != null and is_instance_valid(_worn):
			_worn.queue_free()
		_worn = null

	## The watch itself: a band and a small glowing face, face up (+Y).
	static func _watch() -> Node3D:
		var watch := Node3D.new()
		watch.name = "Watch"
		watch.add_child(_box(Vector3(0.03, 0.012, 0.086), Color(0.08, 0.08, 0.09)))
		var face := _box(Vector3(0.036, 0.008, 0.036), Color(0.3, 0.95, 1.0), 2.0)
		face.name = "Face"
		face.position = Vector3(0, 0.008, 0)
		watch.add_child(face)
		return watch

	static func _box(size: Vector3, color: Color, glow := 0.0) -> MeshInstance3D:
		var mesh := BoxMesh.new()
		mesh.size = size
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		if glow > 0.0:
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.emission_enabled = true
			mat.emission = color
			mat.emission_energy_multiplier = glow
		mesh.material = mat
		var box := MeshInstance3D.new()
		box.mesh = mesh
		box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return box

	## Straps the watch to the character's wrist bone, once there is a skin
	## with one. Headless there is none, and nothing is worn.
	func _wear(p: Actor) -> void:
		if _worn != null and is_instance_valid(_worn) and _worn.is_inside_tree():
			return
		var skeleton := p.find_child("*Skeleton*", true, false) as Skeleton3D
		if skeleton == null or skeleton.find_bone(WRIST_BONE) < 0:
			return
		var attach := BoneAttachment3D.new()
		attach.name = "WornWatch"
		attach.bone_name = WRIST_BONE
		skeleton.add_child(attach)
		var watch := _watch()
		# Face out of the back of the wrist, and undo the model's import
		# scale so the watch keeps its size.
		var s := skeleton.global_basis.get_scale()
		watch.basis = Basis(Quaternion(Vector3.UP, FACE_AXIS)) \
				* Basis.from_scale(Vector3(1.0 / maxf(s.x, 0.001), 1.0 / maxf(s.y, 0.001), 1.0 / maxf(s.z, 0.001)))
		# On the skin of the wrist, not inside it: the watch is depth tested
		# like anything worn, so a gun or a hand in front of it hides it.
		watch.position = FACE_AXIS * (wrist_skin / maxf(s.x, 0.001))
		attach.add_child(watch)
		_worn = attach

	var _emote_holo: EmoteHolo

	## The quick emote wheel thrown over the wrist where there is no visor
	## to draw it on (no helmet, or one taken off; `Hud.emote_wheel_holo`).
	func _mount_emote_holo(p: Actor, controller: PlayerController, shown: bool) -> void:
		var wanted: bool = shown and controller != null and Hud.emote_wheel_holo(p, controller)
		if not wanted:
			if _emote_holo != null and is_instance_valid(_emote_holo):
				_emote_holo.visible = false
			return
		if _emote_holo == null or not is_instance_valid(_emote_holo):
			_emote_holo = EmoteHolo.new()
			add_child(_emote_holo)
		_emote_holo.visible = true
		_emote_holo.show_wheel(p, controller, watch_position(p))

	## Where the watch is in the world, third person: on the wrist bone, or
	## where a left wrist would be when there is no skin.
	func watch_position(p: Actor) -> Vector3:
		if _worn != null and is_instance_valid(_worn) and _worn.is_inside_tree():
			return _worn.global_position
		return p.global_transform * Vector3(-0.3, 1.05, -0.1)

	## Puts the watch and its card where the view can see them, and opens or
	## closes the card towards `raised`. Hidden with the HUD.
	func mount(p: Actor, controller: PlayerController, shown: bool, delta := 0.0) -> void:
		_mount_emote_holo(p, controller, shown)
		# The card rises off the watch on your own wrist in both views: first
		# and third person differ only in where the camera is (Caleb's rule).
		var third := true
		var cam := controller.camera if controller else null
		var holder: Node3D = p
		if get_parent() != holder:
			if get_parent():
				get_parent().remove_child(self)
			holder.add_child(self)
		_wear(p)
		var goal := 1.0 if raised else 0.0
		raise_amount = move_toward(raise_amount, goal, delta / maxf(raise_time, 0.001)) if delta > 0.0 else goal
		visible = shown
		# The card unfolds upwards once the wrist is up.
		var open := clampf((raise_amount - 0.35) / 0.65, 0.0, 1.0)
		_holo.visible = open > 0.0
		# In third person the skin lights the arm for everyone
		# (`ActorSkin._update_watch_glow`); first person lights the forearm.
		_glow.light_energy = glow_energy * open
		_glow.visible = open > 0.0 and not third
		# A wider view shrinks everything in it; the watch grows to match.
		var k := 1.0
		if cam:
			k = tan(deg_to_rad(cam.fov) * 0.5) / tan(deg_to_rad(reference_fov) * 0.5)
		transform = Transform3D.IDENTITY
		if third:
			if is_inside_tree():
				var wrist := watch_position(p)
				# Out in front of the character, turned to face the camera, so
				# it is never behind the body. It is sized by the camera's
				# distance to look as big as in first person, and opens out
				# from the wrist.
				var facing := cam.global_basis.orthonormalized() if cam else p.global_basis.orthonormalized()
				var ahead := Vector3(-facing.z.x, 0.0, -facing.z.z).normalized()
				var side := Vector3(facing.x.x, 0.0, facing.x.z).normalized()
				var spot := p.get_eye_position() + ahead * projection_at.z + Vector3.UP * projection_at.y \
						+ side * projection_at.x
				var far := cam.global_position.distance_to(spot) if cam else 3.0
				var size := far / first_person_at.length() * third_person_view
				var from_eyes := cam != null and cam.global_position.distance_to(p.get_eye_position()) < 0.7
				if from_eyes:
					# Looking out of the eyes, the card stands just over the
					# raised wrist (`WeaponArm.watch_point` brings it up into
					# view), at its real size, turned to the eye.
					# Held close to the face it is smaller, so it always looks as
					# big as a card at `fp_card_reads_at` metres.
					spot = wrist + facing.y * fp_card_lift + facing.z * 0.02
					size = clampf(cam.global_position.distance_to(spot) / fp_card_reads_at, 0.35, 1.0) * k
				elif cam:
					var depth := tp_depth(p, cam)
					size = _tp_size(cam, depth)
					spot = _clear_of_head(p, cam, _tp_spot(p, cam, depth), face_size.x * size * 0.5)
					spot = _keep_on_screen(cam, spot, face_size.x * size * 0.5)
					spot = _over_wrist(cam, spot, wrist, face_size.y * size * 0.5)
				var at := wrist.lerp(spot, ease(open, -2.0))
				_row_scale = 1.0
				if cam and not from_eyes:
					_row_scale = _tp_row_scale(cam, spot, size)
				_holo.global_transform = Transform3D(facing.scaled_local(Vector3(size, size * maxf(open, 0.001), size)), at)
				_glow.global_position = wrist
		_third = third
		# From the eyes nothing comes between you and the card, so it is drawn
		# over the world like the light it is; seen from behind, it stands
		# past the character and the body passes in front of it.
		var from_behind := third and cam != null and cam.global_position.distance_to(p.get_eye_position()) >= 0.7
		_holo.material_override = _holo_behind if from_behind else _holo_over
		(_holo.material_override as ShaderMaterial).set_shader_parameter("open", open)
		(_holo.material_override as ShaderMaterial).set_shader_parameter("backing", tp_backing if from_behind else 0.0)
		_draw_beam(third, open)

	## One card material: drawn over everything (`over`, from the eyes) or
	## depth tested (from behind, where the body stands in front of it).
	func _holo_material(over: bool) -> ShaderMaterial:
		var mat := ShaderMaterial.new()
		var shader := Shader.new()
		shader.code = HOLO_SHADER.replace("DEPTH", "depth_test_disabled" if over else "depth_draw_never")
		mat.shader = shader
		mat.set_shader_parameter("card", viewport.get_texture())
		mat.set_shader_parameter("tint", HOLO_TINT)
		mat.render_priority = 10
		return mat

	## Third person: how big the rows over the card centred at `spot` (drawn
	## at `size`) can be: `tp_rows`, or less where the top of the view is
	## nearer than `rows_tall` over the card.
	func _tp_row_scale(cam: Camera3D, spot: Vector3, size: float) -> float:
		var card := cam.global_transform.affine_inverse() * spot
		if card.z >= -0.01:
			return tp_rows
		var top := -card.z * tan(deg_to_rad(cam.fov) * 0.5) * 0.97
		var room := (top - card.y) / maxf(size, 0.0001) - face_size.y * 0.5
		return clampf(room / rows_tall, 0.2, tp_rows)

	## Third person: how far out along the view the card stands, `tp_behind`
	## past the character's head.
	func tp_depth(p: Actor, cam: Camera3D) -> float:
		var head := cam.global_transform.affine_inverse() * p.get_eye_position()
		return maxf(-head.z, 0.5) + tp_behind

	## Third person: the card's scale so it stands `tp_screen` of the view tall
	## at `depth` from the camera.
	func _tp_size(cam: Camera3D, depth: float) -> float:
		var tall := 2.0 * depth * tan(deg_to_rad(cam.fov) * 0.5)
		return tall * tp_screen / face_size.y

	## Third person: where the card starts, `depth` out from the camera,
	## level with the head (a little over it), before it slides clear of it.
	func _tp_spot(p: Actor, cam: Camera3D, depth: float) -> Vector3:
		var to_cam := cam.global_transform.affine_inverse()
		var head := to_cam * (p.get_eye_position() + Vector3.UP * 0.1)
		var y := tp_lift * depth
		if head.z < -0.01:
			y += head.y * depth / -head.z
		return cam.global_transform * Vector3(0.0, y, -depth)

	## Third person: lifts the card's centre `spot` until its lower edge
	## (`half_height` below it) stands `tp_over_wrist` over the watch as the
	## camera sees it, so the projected light runs up into the card.
	func _over_wrist(cam: Camera3D, spot: Vector3, wrist: Vector3, half_height: float) -> Vector3:
		var to_cam := cam.global_transform.affine_inverse()
		var card := to_cam * spot
		var watch := to_cam * wrist
		if card.z >= -0.01 or watch.z >= -0.01:
			return spot
		var watch_y := watch.y * card.z / watch.z
		var view_tall := -2.0 * card.z * tan(deg_to_rad(cam.fov) * 0.5)
		var short := watch_y + tp_over_wrist * view_tall - (card.y - half_height)
		return cam.global_transform * (card + Vector3(0.0, short, 0.0))

	## Keeps a card `half_width` wide whole on screen: slid back right if its
	## left edge would leave the view.
	func _keep_on_screen(cam: Camera3D, spot: Vector3, half_width: float) -> Vector3:
		var to_cam := cam.global_transform.affine_inverse()
		var card := to_cam * spot
		if card.z >= -0.01:
			return spot
		var vp := cam.get_viewport()
		var aspect := 16.0 / 9.0
		if vp != null and vp.get_visible_rect().size.y > 0.0:
			aspect = vp.get_visible_rect().size.x / vp.get_visible_rect().size.y
		var half_view := -card.z * tan(deg_to_rad(cam.fov) * 0.5) * aspect
		var left := card.x - half_width
		if left < -half_view * 0.97:
			card.x += -half_view * 0.97 - left
		return cam.global_transform * card

	## Third person: slides the card's centre `spot` left, as the camera sees
	## it, until the card (half as wide as `half_width`) clears the head and
	## helmet with room to spare, so the character is never hidden behind it.
	func _clear_of_head(p: Actor, cam: Camera3D, spot: Vector3, half_width: float) -> Vector3:
		var to_cam := cam.global_transform.affine_inverse()
		var card := to_cam * spot
		var head := to_cam * (p.get_eye_position() + Vector3.UP * 0.1)
		if card.z >= -0.01 or head.z >= -0.01:
			return spot
		# The head's side and its edge, brought to the card's depth.
		var at_depth := card.z / head.z
		var head_left := head.x * at_depth - head_clearance * at_depth
		var overlap := card.x + half_width * (1.0 - tp_tuck) - head_left
		if overlap <= 0.0:
			return spot
		return cam.global_transform * (card - Vector3(overlap, 0.0, 0.0))

	## The watch face, where the light comes from: the forearm's watch in
	## first person, the one worn on the wrist bone in third.
	func _face_position(third: bool) -> Vector3:
		var watch: Node = _worn.get_child(0) if _worn != null and is_instance_valid(_worn) and _worn.get_child_count() > 0 else null
		var face := watch.get_node_or_null("Face") as Node3D if watch != null else null
		if face != null and face.is_inside_tree():
			return face.global_position
		return _holo.global_position - _holo.global_basis.y.normalized() * 0.1

	## Light thrown out from the watch face up to the card's lower edge,
	## bright at the face and thinning out towards the card, with bands of
	## light running out along it, so the card reads as projected rather
	## than floating. Nothing crosses the card's face, so it stays readable.
	func _draw_beam(third: bool, open: float) -> void:
		var mesh := _beam.mesh as ImmediateMesh
		mesh.clear_surfaces()
		_beam.visible = _holo.visible and is_inside_tree()
		if not _beam.visible:
			return
		_beam.global_transform = Transform3D.IDENTITY
		(_beam.material_override as ShaderMaterial).set_shader_parameter("open", open)
		var apex := _face_position(third)
		var half := face_size * 0.5
		var left := _holo.global_transform * Vector3(-half.x, -half.y, 0.0)
		var right := _holo.global_transform * Vector3(half.x, -half.y, 0.0)
		# A fan of light up to the card's lower edge (UV.y runs out from the
		# face, 0, to the card, 1) and two fine rays at its sides.
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		mesh.surface_set_uv(Vector2(0.5, 0.0))
		mesh.surface_add_vertex(apex)
		mesh.surface_set_uv(Vector2(0.0, 1.0))
		mesh.surface_add_vertex(left)
		mesh.surface_set_uv(Vector2(1.0, 1.0))
		mesh.surface_add_vertex(right)
		mesh.surface_end()
		mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		for corner in [left, right]:
			mesh.surface_set_uv(Vector2(0.0, 0.0))
			mesh.surface_add_vertex(apex)
			mesh.surface_set_uv(Vector2(0.0, 1.0))
			mesh.surface_add_vertex(corner)
		mesh.surface_end()

	## Fills the card: `slots` from `Hud.watch_slots`, `focus` the icon being
	## looked at, `death` the death report while down (else ""), `health`
	## your share of health (for the face's colour), `bars` the vitals strip
	## (empty while the visor shows them), `notes` a last notice, `summaries`
	## a line under a tab's name (tab -> text: the pack under Summon) and
	## `popup` a line that is only there while it matters (the flight rig's
	## cue while flying).
	func show_card(slots: Array[Dictionary], focus: int, death: String, health: float, bars: Array[float],
			notes: Array[String] = [], summaries := {}, popup := "") -> void:
		card.slots = slots
		card.summaries = summaries
		card.popup = popup
		card.objective = objective
		card.focus = clampi(focus, 0, maxi(slots.size() - 1, 0))
		card.death = death
		card.map = map
		card.opened = opened
		card.tabs = tabs
		card.bars = bars
		card.note = notes[-1] if not notes.is_empty() else ""
		card.queue_redraw()
		# The watch face shows health even with the card down: cyan when
		# well, red when low.
		face_color = face_tint(clampf(health, 0.0, 1.0))
		if resting:
			# Resting after a summon: the face breathes amber until it is ready.
			_rest_time += get_process_delta_time()
			face_color = face_color.lerp(Card.WARM, 0.45 + 0.25 * sin(_rest_time * 5.0))
		else:
			_rest_time = 0.0
		for watch: Node in [_worn.get_child(0) if _worn != null and is_instance_valid(_worn) and _worn.get_child_count() > 0 else null]:
			var face := watch.get_node_or_null("Face") as MeshInstance3D if watch != null else null
			if face:
				var mat := (face.mesh as BoxMesh).material as StandardMaterial3D
				mat.albedo_color = face_color
				mat.emission = face_color
		var glow := face_color.lerp(GLOW_COLOR, 0.5)
		_glow.light_color = glow

	## Stands the toy vehicles in a row over the card, as small holograms of
	## their own. The picked one is bigger and turns; `ready` is false while
	## the watch recharges, which dims them all.
	func show_toys(ids: Array[String], picked: int, ready: bool, delta := 0.0) -> void:
		if _toys == null:
			_toys = Node3D.new()
			_toys.name = "Toys"
			_holo.add_child(_toys)
		if ids != _toy_ids:
			_toy_ids = ids.duplicate()
			for old in _toys.get_children():
				_toys.remove_child(old)
				old.queue_free()
			for id in ids:
				var toy: Node3D = VehicleScript.toy_model(id)
				# A hologram of the toy, not the toy: `Look` leaves it alone.
				toy.remove_meta("display_item")
				for mesh in toy.find_children("*", "MeshInstance3D", true, false):
					(mesh as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				_toys.add_child(toy)
		_toys.position = Vector3(0.0, face_size.y * 0.5 + toy_lift * _row_scale, 0.0)
		_toys.scale = Vector3.ONE * _row_scale
		# They stand up only while the card is on the vehicles.
		_toys.visible = card != null and card.focused_id() == "vehicle" and card.death == ""
		picked = clampi(picked, 0, maxi(ids.size() - 1, 0))
		_spin = fmod(_spin + delta * 1.6, TAU)
		for i in _toys.get_child_count():
			var toy := _toys.get_child(i) as Node3D
			var chosen := i == picked
			toy.position = Vector3((i - (ids.size() - 1) * 0.5) * toy_spacing, 0.0, 0.0)
			toy.scale = Vector3.ONE * VehicleScript.TOY_SCALE * toy_size * (1.5 if chosen else 1.0)
			toy.rotation = Vector3(0.0, _spin if chosen else 0.9, 0.0)
			var tint := toy_tint(chosen, ready)
			for mesh in toy.find_children("*", "MeshInstance3D", true, false):
				var mat := (mesh as MeshInstance3D).material_override as StandardMaterial3D
				if mat == null:
					mat = StandardMaterial3D.new()
					mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					mat.render_priority = 11
					(mesh as MeshInstance3D).material_override = mat
				# Like the card: over everything in first person only.
				mat.no_depth_test = not _third
				mat.albedo_color = tint

	## Stands the carried weapons in a row over the card while it is on the
	## weapon icon, as small holograms of their real models (`ids` in the
	## carousel's order, `Hud.weapon_entries`). The picked one is bigger and
	## turns; `ready` is false while the watch rests after a summon.
	func show_weapons(ids: Array[String], picked: int, ready: bool, delta := 0.0) -> void:
		if _weapons == null:
			_weapons = Node3D.new()
			_weapons.name = "Weapons"
			_holo.add_child(_weapons)
		if ids != _weapon_ids:
			_weapon_ids = ids.duplicate()
			for old in _weapons.get_children():
				_weapons.remove_child(old)
				old.queue_free()
			for id in ids:
				_weapons.add_child(_weapon_holo(id))
		_weapons.position = Vector3(0.0, face_size.y * 0.5 + (toy_lift + 0.012) * _row_scale, 0.0)
		_weapons.scale = Vector3.ONE * _row_scale
		_weapons.visible = card != null and card.focused_id() == "weapon" and card.death == ""
		if not _weapons.visible:
			return
		picked = clampi(picked, 0, maxi(ids.size() - 1, 0))
		for i in _weapons.get_child_count():
			var holo := _weapons.get_child(i) as Node3D
			var chosen := i == picked
			# The row slides so the picked weapon is always over the middle.
			holo.position = Vector3((i - picked) * weapon_spacing, 0.006 if chosen else 0.0, 0.0)
			holo.visible = absi(i - picked) <= 3
			var length: float = holo.get_meta("length", 1.0)
			holo.scale = Vector3.ONE * weapon_length / maxf(length, 0.05) * (1.0 if chosen else 0.66)
			holo.rotation = Vector3(0.0, _spin if chosen else 0.0, 0.0)
			var tint := toy_tint(chosen, ready)
			_tint(holo, Color(tint, tint.a * 0.8))

	## A weapon's real model as a hologram, with how long it is in its
	## "length" meta. Headless there is no model, and it is an empty node.
	func _weapon_holo(id: String) -> Node3D:
		var holo := Node3D.new()
		holo.name = "Weapon"
		holo.set_meta("item", id)
		var model: Node3D = null
		if ItemDB.has_tag(id, "helmet"):
			# A helmet shows the model it is worn as.
			var stats := ItemDB.item_stats(id)
			model = SkinScript.build_helmet(str(stats.get("mode", "")), stats.get("glass_color", Color.WHITE),
					Vector3(0.27, 0.31, 0.31), Color(0.22, 0.23, 0.25), int(stats.get("tier", 1)))
		elif ItemDB.has_tag(id, "armor"):
			# A frame shows the plates it is worn as.
			model = SkinScript.build_frame(id)
		else:
			var weapon: Weapon = MeleeWeapon.new() if ItemDB.has_tag(id, "melee") else Gun.new()
			weapon.item_id = id
			model = Look.weapon_model(weapon) if DisplayServer.get_name() != "headless" else null
			weapon.free()
		if model == null:
			return holo
		holo.add_child(model)
		var box := AABB()
		var first := true
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			var part := mesh as MeshInstance3D
			part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var placed := _to_holo(part, holo) * part.get_aabb()
			box = placed if first else box.merge(placed)
			first = false
		# Centred, so it turns about its middle, and laid along the row: a
		# gun's barrel runs along Z and a blade stands along Y.
		model.position -= box.get_center()
		holo.remove_child(model)
		var lay := Node3D.new()
		lay.name = "Lay"
		match box.get_longest_axis_index():
			Vector3.AXIS_Y:
				lay.rotation = Vector3(0.0, 0.0, -PI * 0.5)
			Vector3.AXIS_Z:
				lay.rotation = Vector3(0.0, PI * 0.5, 0.0)
		lay.add_child(model)
		holo.add_child(lay)
		holo.set_meta("length", box.get_longest_axis_size())
		return holo

	## A node's transform up to (not including) `top`, before either is in
	## the tree.
	static func _to_holo(node: Node3D, top: Node3D) -> Transform3D:
		var out := Transform3D.IDENTITY
		var at: Node = node
		while at != null and at != top:
			if at is Node3D:
				out = (at as Node3D).transform * out
			at = at.get_parent()
		return out

	## Draws every mesh under `holo` as flat light in `tint`.
	func _tint(holo: Node3D, tint: Color) -> void:
		for mesh in holo.find_children("*", "MeshInstance3D", true, false):
			var mat := (mesh as MeshInstance3D).material_override as StandardMaterial3D
			if mat == null:
				mat = StandardMaterial3D.new()
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mat.render_priority = 11
				(mesh as MeshInstance3D).material_override = mat
			# Like the card: over everything in first person only.
			mat.no_depth_test = not _third
			mat.albedo_color = tint

	## The tabletop map over the card while the Map icon is opened (Caleb's
	## call): the ground around you in lines of light with its relief, north
	## away from you, the strongpoints, depots, gate outposts, the war's hot
	## zone and your side's pings standing on it as small pillars, you as a
	## bright one with your facing, and a line out to the target picked on the
	## wheel (`target`), the waypoint (`way`) standing taller. Built from
	## `marks` (`Hud.map_marks`) and `relief` (`Hud.map_relief`); empty
	## `marks` puts it away. It is part of the one card, so it is the same in
	## both views.
	func show_table(marks: Dictionary, relief: PackedFloat32Array, target: Dictionary, way: Dictionary) -> void:
		if marks.is_empty() or (card != null and card.death != ""):
			if _table != null:
				_table.visible = false
			return
		if _table == null:
			_table = MeshInstance3D.new()
			_table.name = "Table"
			_table.mesh = ImmediateMesh.new()
			_table.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.vertex_color_use_as_albedo = true
			mat.render_priority = 11
			_table.material_override = mat
			_holo.add_child(_table)
		(_table.material_override as StandardMaterial3D).no_depth_test = not _third
		_table.visible = true
		var w := table_width
		_table.rotation = Vector3(table_tilt, 0.0, 0.0)
		_table.position = Vector3(0.0, face_size.y * 0.5 + (0.012 + w * 0.5 * sin(table_tilt)) * _row_scale, 0.0)
		_table.scale = Vector3.ONE * _row_scale
		var mesh := _table.mesh as ImmediateMesh
		mesh.clear_surfaces()
		mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		var n := Hud.TABLE_GRID
		var ground := func(m: Vector2) -> Vector3:
			var c := m.clamp(Vector2(-1, -1), Vector2(1, 1))
			var h := 0.0
			if relief.size() == n * n:
				var fx := (c.x + 1.0) * 0.5 * (n - 1)
				var fy := (c.y + 1.0) * 0.5 * (n - 1)
				var x0 := clampi(floori(fx), 0, n - 2)
				var y0 := clampi(floori(fy), 0, n - 2)
				var tx := fx - x0
				var ty := fy - y0
				h = lerpf(lerpf(relief[y0 * n + x0], relief[y0 * n + x0 + 1], tx),
						lerpf(relief[(y0 + 1) * n + x0], relief[(y0 + 1) * n + x0 + 1], tx), ty)
			return Vector3(c.x * w * 0.5, h * w * table_relief, c.y * w * 0.5)
		var line := func(a: Vector3, b: Vector3, color: Color) -> void:
			mesh.surface_set_color(color)
			mesh.surface_add_vertex(a)
			mesh.surface_set_color(color)
			mesh.surface_add_vertex(b)
		var ink := Color(0.6, 1.0, 1.0)
		var warm := Card.WARM
		# The ground: lines along the rows and columns, brighter up high.
		for k in n:
			for j in n - 1:
				var u := float(k) / (n - 1) * 2.0 - 1.0
				var v0 := float(j) / (n - 1) * 2.0 - 1.0
				var v1 := float(j + 1) / (n - 1) * 2.0 - 1.0
				for across in [true, false]:
					var a: Vector3 = ground.call(Vector2(v0, u) if across else Vector2(u, v0))
					var b: Vector3 = ground.call(Vector2(v1, u) if across else Vector2(u, v1))
					var lift := (a.y + b.y) * 0.5 / maxf(w * table_relief, 0.001)
					line.call(a, b, Color(ink, 0.2 + 0.3 * lift))
		var pillar := func(m: Vector2, tall: float, color: Color) -> void:
			var foot: Vector3 = ground.call(m)
			line.call(foot, foot + Vector3(0, tall * w, 0), color)
			var r := 0.012 * w
			for d: Vector3 in [Vector3(r, 0, 0), Vector3(0, 0, r)]:
				line.call(foot - d, foot + d, color)
		for site: Dictionary in marks.get("sites", []):
			pillar.call(site.at, 0.16 if site.held else 0.1, Color(warm if site.contested else ink, 0.95))
		for at: Vector2 in marks.get("depots", []):
			pillar.call(at, 0.08, Color(ink, 0.9))
		for at: Vector2 in marks.get("outposts", []):
			pillar.call(at, 0.06, Color(0.45, 1.0, 0.6, 0.9))
		for at: Vector2 in marks.get("pings", []):
			pillar.call(at, 0.12, Color(warm, 0.9))
		var storm: Variant = marks.get("storm")
		if storm is Dictionary:
			var middle3: Vector3 = ground.call(storm.at)
			var r := float(storm.radius)
			for i in 24:
				if i % 2 == 1:
					continue
				var a := TAU * i / 24.0
				var b := TAU * (i + 1) / 24.0
				line.call(middle3 + Vector3(cos(a), 0.03, sin(a)) * r * w * 0.5,
						middle3 + Vector3(cos(b), 0.03, sin(b)) * r * w * 0.5, Color(0.95, 0.72, 0.55, 0.8))
		for push: Dictionary in marks.get("pushes", []):
			var tail: Vector3 = ground.call(push.from) + Vector3(0, 0.03 * w, 0)
			var head: Vector3 = ground.call(push.to) + Vector3(0, 0.03 * w, 0)
			line.call(tail, head, Color(warm, 0.9))
			var back := (tail - head).normalized() * 0.05 * w
			var side := back.cross(Vector3.UP).normalized() * 0.03 * w
			line.call(head, head + back + side, Color(warm, 0.9))
			line.call(head, head + back - side, Color(warm, 0.9))
		var war: Variant = marks.get("war")
		if war is Vector2:
			var centre: Vector3 = ground.call(war)
			for i in 16:
				var a := TAU * i / 16.0
				var b := TAU * (i + 1) / 16.0
				line.call(centre + Vector3(cos(a), 0.02, sin(a)) * 0.08 * w,
						centre + Vector3(cos(b), 0.02, sin(b)) * 0.08 * w, Color(warm, 0.85))
		# You: a bright pillar with your facing laid out on the ground.
		var you: Vector2 = marks.get("you", Vector2.ZERO)
		var feet: Vector3 = ground.call(you)
		var face: Vector2 = marks.get("facing", Vector2.UP)
		line.call(feet, feet + Vector3(0, 0.22 * w, 0), Color(1, 1, 1, 0.95))
		line.call(feet, feet + Vector3(face.x, 0, face.y) * 0.07 * w, Color(1, 1, 1, 0.95))
		var to_map := func(at: Vector3) -> Vector2:
			return (Vector2(at.x, at.z) - (marks.middle as Vector2)) / float(marks.half)
		if not way.is_empty():
			pillar.call(to_map.call(way.at), 0.3, Color(1.0, 0.9, 0.4, 0.95))
		if not target.is_empty():
			# The picked target: a line out to it along the ground.
			var goal: Vector2 = to_map.call(target.at)
			var steps := 12
			for i in steps:
				var a: Vector3 = ground.call(you.lerp(goal, float(i) / steps)) + Vector3(0, 0.01 * w, 0)
				var b: Vector3 = ground.call(you.lerp(goal, float(i + 1) / steps)) + Vector3(0, 0.01 * w, 0)
				if i % 2 == 0:
					line.call(a, b, Color(1.0, 0.9, 0.4, 0.95))
			pillar.call(goal, 0.2, Color(1.0, 0.9, 0.4, 0.95))
		mesh.surface_end()

	## True while the tabletop map stands over the card.
	func table_shown() -> bool:
		return _table != null and _table.visible

	## The ids of the weapons standing over the card, in the carousel's order.
	func weapons_shown() -> Array[String]:
		return _weapon_ids

	## A toy hologram's colour: bright when picked, faint while recharging.
	static func toy_tint(chosen: bool, ready: bool) -> Color:
		var tint := Color(0.75, 1.0, 1.0, 0.95) if chosen else Color(0.3, 0.85, 1.0, 0.45)
		if not ready:
			tint = Color(1.0, 0.6, 0.25, tint.a * 0.6)
		return tint

	## The ids of the toys standing over the card, left to right.
	func toys_shown() -> Array[String]:
		return _toy_ids

	## True once the card is fully open.
	func is_open() -> bool:
		return raise_amount >= 1.0

	## The watch face's colour at a share of health.
	static func face_tint(health: float) -> Color:
		return Color(1.0, 0.2, 0.15).lerp(Color(0.3, 0.95, 1.0), clampf((health - 0.2) / 0.5, 0.0, 1.0))

	## The card's words: the death report while down, else the open icon's
	## line first and then the others'.
	func text() -> String:
		if card == null:
			return ""
		if card.death != "":
			return card.death
		var lines: Array[String] = []
		if not card.slots.is_empty():
			lines.append(card.slots[card.focus].detail)
		for i in card.slots.size():
			if i != card.focus:
				lines.append(card.slots[i].detail)
		for tab: String in TABS:
			if card.summaries.get(tab, "") != "":
				lines.append(card.summaries[tab])
		if card.popup != "":
			lines.append(card.popup)
		if card.objective != "":
			lines.append(card.objective)
		return "\n".join(lines)

	## The id of the icon being looked at ("" with none).
	func focused_id() -> String:
		return card.focused_id() if card != null else ""

	## The controls the open icon shows as glyphs ("wheel", "click", "key:L").
	func focused_hints() -> Array:
		if card == null or card.slots.is_empty():
			return []
		if card.tabs:
			return ["wheel", "click"]
		return card.slots[card.focus].hints


	## The card's picture, drawn into the watch's viewport: thin lines of light
	## on next to nothing, like the visor. Icons are drawn from lines here,
	## so the card needs no textures.
	class Card:
		extends Control

		const INK := Color(0.6, 1.0, 1.0)
		const WARM := Color(1.0, 0.62, 0.3)
		const BAR_COLORS := [Color(1.0, 0.35, 0.3), Color(0.45, 0.7, 1.0), Color(0.95, 0.9, 0.4), Color(1.0, 0.6, 0.2),
				Color(0.6, 0.85, 1.0)]

		var slots: Array[Dictionary] = []
		var focus := 0
		var death := ""
		var bars: Array[float] = []
		var note := ""
		## A line under a tab's name: tab -> text.
		var summaries := {}
		## A line that is only there while it matters (the rig's cue in flight).
		var popup := ""
		## The new player's tour objective, a marked line under the tabs.
		var objective := ""
		## The small map shown beside the Map icon (`Hud.map_marks`).
		var map := {}
		## The icon opened with a click ("" for none); its panel replaces the
		## small map on the right.
		var opened := ""
		## On the tab row: the open tab's name is framed and its icons wait,
		## none grown, the line under them naming what the tab holds.
		var tabs := false
		var _time := 0.0

		func _process(delta: float) -> void:
			_time += delta
			queue_redraw()

		func focused_id() -> String:
			return slots[focus].id if focus < slots.size() else ""

		## The tab the open icon is on.
		func focused_tab() -> String:
			return slots[focus].get("tab", "") if focus < slots.size() else ""

		func _draw() -> void:
			var w := size.x
			var h := size.y
			var font := ThemeDB.fallback_font
			# A faint plate with lit corners: light, not a box.
			draw_rect(Rect2(Vector2(4, 4), size - Vector2(8, 8)), Color(0.0, 0.14, 0.18, 0.5))
			for corner in [Vector2(6, 6), Vector2(w - 6, 6), Vector2(6, h - 6), Vector2(w - 6, h - 6)]:
				var sx := 1.0 if corner.x < w * 0.5 else -1.0
				var sy := 1.0 if corner.y < h * 0.5 else -1.0
				draw_line(corner, corner + Vector2(26 * sx, 0), Color(INK, 0.8), 2.0)
				draw_line(corner, corner + Vector2(0, 26 * sy), Color(INK, 0.8), 2.0)
			if death != "":
				var y := 36.0
				for line in death.split("\n"):
					draw_string(font, Vector2(22, y), line, HORIZONTAL_ALIGNMENT_LEFT, w - 44, 20, Color(INK, 0.95))
					y += 24.0
				return
			var top := 14.0
			if not bars.is_empty():
				top = _draw_bars(w)
			if slots.is_empty():
				return
			var tab := focused_tab()
			top = _draw_tabs(w, top, tab)
			# The open tab's icons, in a row.
			var shown: Array[int] = []
			for i in slots.size():
				if slots[i].get("tab", "") == tab:
					shown.append(i)
			var count := shown.size()
			var row_y := top + 54.0
			# The map stands to the right of the Status icons while it is read.
			var open_slot: Dictionary = slots[focus] if focus < slots.size() else {}
			var panel: Array = open_slot.get("panel", []) if opened != "" and opened == focused_id() else []
			var map_side := minf(h - top - 80.0, w * 0.42) if (not map.is_empty() and focused_id() == "map") \
					or not panel.is_empty() else 0.0
			var row_w := w - (map_side + 20.0 if map_side > 0.0 else 0.0)
			var step := minf((row_w - 40.0) / count, 170.0)
			var left := (row_w - step * count) * 0.5
			if not panel.is_empty():
				_draw_panel(Rect2(Vector2(w * 0.45, top + 8.0), Vector2(w * 0.55 - 24.0, h - top - 80.0)), open_slot)
				row_w = w * 0.45
				step = minf((row_w - 40.0) / count, 170.0)
				left = (row_w - step * count) * 0.5
			elif map_side > 0.0:
				_draw_map(Rect2(Vector2(w - map_side - 24.0, top + 8.0), Vector2(map_side, map_side)))
			for n in count:
				var i := shown[n]
				var slot := slots[i]
				var centre := Vector2(left + step * (n + 0.5), row_y)
				var looked := i == focus and not tabs
				var color := _color_of(slot, looked)
				var radius := 30.0 if looked else 21.0
				if looked:
					draw_arc(centre, radius + 11.0, 0.0, TAU, 40, Color(color, 0.25), 1.5, true)
				var progress: float = slot.progress
				if progress >= 0.0:
					draw_arc(centre, radius + 11.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(progress, 0.0, 1.0), 40,
							Color(WARM if slot.alert else INK, 0.95), 4.0, true)
				_draw_icon(str(slot.get("glyph", slot.id)), centre, radius, color, 3.0 if looked else 2.0)
				if slot.value != "":
					draw_string(font, centre + Vector2(-step * 0.5, radius + 30.0), slot.value,
							HORIZONTAL_ALIGNMENT_CENTER, step, 20 if looked else 17, color)
				# A carousel shows a pip for each thing it holds.
				var held := int(slot.get("count", 0))
				if looked and held > 1:
					var pip := minf(12.0, (step - 20.0) / held)
					for k in held:
						var at := centre + Vector2((k - (held - 1) * 0.5) * pip, radius + 40.0)
						draw_circle(at, 3.0 if k == int(slot.get("index", 0)) else 1.6,
								Color(INK, 1.0 if k == int(slot.get("index", 0)) else 0.5))
			# The open icon's one line, with its controls as glyphs after it;
			# on the tab row, what the tab holds, with the wheel and a click.
			var open := slots[focus]
			if tabs:
				open = {"detail": Wrist.tab_line(tab), "hints": ["wheel", "click"], "alert": false, "empty": false}
			var line_y := h - 40.0 if note == "" else h - 56.0
			var hints: Array = open.hints
			var room := w - 40.0 - hints.size() * 34.0
			var text_w := minf(font.get_string_size(open.detail, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x, room)
			var x := (w - text_w - hints.size() * 34.0) * 0.5
			draw_string(font, Vector2(x, line_y), open.detail, HORIZONTAL_ALIGNMENT_LEFT, room, 26,
					_color_of(open, true))
			x += text_w + 14.0
			for hint: String in hints:
				_draw_hint(hint, Vector2(x + 10.0, line_y - 9.0), Color(INK, 0.9))
				x += 34.0
			if note != "":
				draw_string(font, Vector2(22, h - 20.0), note, HORIZONTAL_ALIGNMENT_CENTER, w - 44, 16,
						Color(INK, 0.6))

		## An opened icon's panel in `box`: a page's title and lines (Standing),
		## or a list the wheel moves through with the picked row lit (the map's
		## targets, the pack), scrolled to keep it in view.
		func _draw_panel(box: Rect2, slot: Dictionary) -> void:
			var font := ThemeDB.fallback_font
			draw_rect(box, Color(0.0, 0.2, 0.25, 0.3))
			draw_rect(box, Color(INK, 0.3), false, 1.5)
			var lines: Array = slot.get("panel", [])
			var at := int(slot.get("panel_at", -1))
			var y := box.position.y + 20.0
			if slot.has("page"):
				draw_string(font, Vector2(box.position.x + 10.0, y), String(slot.page).to_upper(),
						HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 20.0, 17, Color(INK, 1.0))
				y += 22.0
			var row_h := 19.0
			var fits := maxi(1, int((box.end.y - y) / row_h))
			var first := clampi(at - fits / 2, 0, maxi(lines.size() - fits, 0)) if at >= 0 else 0
			for i in range(first, mini(lines.size(), first + fits)):
				var lit := i == at
				if lit:
					draw_rect(Rect2(Vector2(box.position.x + 4.0, y - 14.0), Vector2(box.size.x - 8.0, row_h)),
							Color(INK, 0.14))
				draw_string(font, Vector2(box.position.x + 10.0, y), str(lines[i]), HORIZONTAL_ALIGNMENT_LEFT,
						box.size.x - 20.0, 15, Color(INK, 1.0 if lit or at < 0 else 0.6))
				y += row_h

		## The small holographic map in `box`: the risk zones as faint cells,
		## the strongpoints as diamonds (filled where your side holds one), the
		## depots as squares, the gate outposts as small arches, your side's
		## pings, a warm pulse where the war is hot, and you as an arrow the
		## way you face. Lines of light, north up, like the rest of the card.
		## An army's push on the card's map: a dashed warm line from the army
		## to the site with a head at the site.
		func _draw_push_arrow(from: Vector2, to: Vector2) -> void:
			var along := to - from
			if along.length() < 4.0:
				return
			draw_dashed_line(from, to, Color(WARM, 0.85), 1.5, 4.0)
			var back := -along.normalized() * 7.0
			var side := Vector2(-back.y, back.x) * 0.6
			draw_colored_polygon(PackedVector2Array([to, to + back + side, to + back - side]), Color(WARM, 0.9))


		func _draw_map(box: Rect2) -> void:
			var centre := box.get_center()
			var half := box.size.x * 0.5
			var at := func(point: Vector2) -> Vector2:
				return centre + point.clamp(Vector2(-1, -1), Vector2(1, 1)) * half
			draw_rect(box, Color(0.0, 0.2, 0.25, 0.35))
			var zones: PackedByteArray = map.get("zones", PackedByteArray())
			var grid := Hud.MAP_GRID
			if zones.size() == grid * grid:
				var cell := box.size / grid
				for i in zones.size():
					if zones[i] > 0:
						draw_rect(Rect2(box.position + Vector2(i % grid, floori(i / float(grid))) * cell, cell),
								Color(WARM, 0.11 * zones[i]))
			# A faint grid and a frame with lit corners.
			for k in range(1, 4):
				var x := box.position.x + box.size.x * k / 4.0
				var y := box.position.y + box.size.y * k / 4.0
				draw_line(Vector2(x, box.position.y), Vector2(x, box.end.y), Color(INK, 0.08), 1.0)
				draw_line(Vector2(box.position.x, y), Vector2(box.end.x, y), Color(INK, 0.08), 1.0)
			draw_rect(box, Color(INK, 0.35), false, 1.5)
			draw_string(ThemeDB.fallback_font, box.position + Vector2(box.size.x * 0.5 - 6.0, -3.0), "N",
					HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(INK, 0.6))
			var storm: Variant = map.get("storm")
			if storm is Dictionary:
				# A storm crossing the map: a slowly turning broken ring its size.
				var spin := _time * 0.6
				var r := float(storm.radius) * half
				for k in 6:
					var a := spin + TAU * k / 6.0
					draw_arc(at.call(storm.at), r, a, a + TAU / 10.0, 8, Color(0.95, 0.72, 0.55, 0.7), 1.5, true)
			var war: Variant = map.get("war")
			if war is Vector2:
				var pulse := 0.5 + 0.5 * sin(_time * 3.0)
				draw_arc(at.call(war), 10.0 + 6.0 * pulse, 0.0, TAU, 24, Color(WARM, 0.35 + 0.3 * pulse), 2.0, true)
			for spot: Vector2 in map.get("outposts", []):
				var c: Vector2 = at.call(spot)
				draw_arc(c + Vector2(0, 3), 5.0, PI, TAU, 10, Color(INK, 0.7), 1.5, true)
			for spot: Vector2 in map.get("depots", []):
				var c: Vector2 = at.call(spot)
				draw_rect(Rect2(c - Vector2(4, 4), Vector2(8, 8)), Color(INK, 0.85), false, 1.5)
			for push: Dictionary in map.get("pushes", []):
				_draw_push_arrow(at.call(push.from), at.call(push.to))
			for site: Dictionary in map.get("sites", []):
				var c: Vector2 = at.call(site.at)
				var color := Color(WARM, 0.95) if site.contested else Color(INK, 0.95)
				var diamond := PackedVector2Array([c + Vector2(0, -6), c + Vector2(6, 0), c + Vector2(0, 6),
						c + Vector2(-6, 0)])
				if site.held:
					draw_colored_polygon(diamond, Color(color, 0.6))
				diamond.append(c + Vector2(0, -6))
				draw_polyline(diamond, color, 1.5, true)
			for spot: Vector2 in map.get("pings", []):
				var c: Vector2 = at.call(spot)
				draw_circle(c, 2.5, Color(WARM, 0.9))
				draw_arc(c, 6.0, 0.0, TAU, 12, Color(WARM, 0.6), 1.0, true)
			if map.has("you"):
				var c: Vector2 = at.call(map.you)
				var f: Vector2 = map.get("facing", Vector2.UP)
				var side := Vector2(-f.y, f.x)
				draw_colored_polygon(PackedVector2Array([c + f * 9.0, c - f * 5.0 + side * 5.0, c - f * 2.0,
						c - f * 5.0 - side * 5.0]), Color(INK, 0.95 + 0.05 * sin(_time * 6.0)))

		## The tab names along the top, the open one lit and underlined, then
		## the open tab's line (the pack under Summon) and the pop-up line
		## when there is one. Returns where the icons can start.
		func _draw_tabs(w: float, top: float, open_tab: String) -> float:
			var font := ThemeDB.fallback_font
			var each := (w - 40.0) / TABS.size()
			var y := top + 18.0
			for i in TABS.size():
				var lit: bool = TABS[i] == open_tab
				var color := Color(INK, 1.0 if lit else 0.6)
				draw_string(font, Vector2(20.0 + each * i, y), String(TABS[i]).to_upper(),
						HORIZONTAL_ALIGNMENT_CENTER, each, 20 if lit else 17, color)
				if lit:
					draw_line(Vector2(20.0 + each * i + each * 0.25, y + 6.0),
							Vector2(20.0 + each * (i + 1) - each * 0.25, y + 6.0), color, 2.0)
				if lit and tabs:
					# On the tab row the open tab is what the wheel moves:
					# a pulsing frame around its name, arrows to its sides.
					var box := Rect2(Vector2(20.0 + each * i + each * 0.12, y - 22.0), Vector2(each * 0.76, 34.0))
					draw_rect(box, Color(INK, 0.55 + 0.3 * sin(_time * 4.0)), false, 2.0)
					if i > 0:
						draw_string(font, Vector2(box.position.x - 16.0, y), "<", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(INK, 0.8))
					if i < TABS.size() - 1:
						draw_string(font, Vector2(box.end.x + 6.0, y), ">", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(INK, 0.8))
			y += 12.0
			var line: String = summaries.get(open_tab, "")
			if line != "":
				y += 18.0
				draw_string(font, Vector2(20, y), line, HORIZONTAL_ALIGNMENT_CENTER, w - 40, 17, Color(INK, 0.85))
			if popup != "":
				y += 18.0
				draw_string(font, Vector2(20, y), popup, HORIZONTAL_ALIGNMENT_CENTER, w - 40, 17,
						Color(WARM, 0.95))
			if objective != "":
				y += 18.0
				# A small diamond marks it as the thing to do next.
				var text_w := minf(font.get_string_size(objective, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x, w - 70.0)
				var x := (w - text_w) * 0.5
				var c := Vector2(x - 12.0, y - 6.0)
				var mark := Color(WARM, 0.75 + 0.25 * sin(_time * 3.0))
				draw_polyline(PackedVector2Array([c + Vector2(0, -5), c + Vector2(5, 0), c + Vector2(0, 5),
						c + Vector2(-5, 0), c + Vector2(0, -5)]), mark, 1.5, true)
				draw_string(font, Vector2(x, y), objective, HORIZONTAL_ALIGNMENT_LEFT, w - 70.0, 17, Color(WARM, 0.9))
			return y

		## The vitals strip along the top, when the visor is not showing them:
		## health, armor and stamina, and heat with a flight rig. Returns where
		## the icons can start.
		func _draw_bars(w: float) -> float:
			var y := 18.0
			for i in bars.size():
				var value := bars[i]
				if value < 0.0:
					continue
				var thick := 6.0 if i == 0 else 3.0
				draw_rect(Rect2(Vector2(24, y), Vector2(w - 48, thick)), Color(BAR_COLORS[i], 0.15))
				draw_rect(Rect2(Vector2(24, y), Vector2((w - 48) * clampf(value, 0.0, 1.0), thick)), Color(BAR_COLORS[i], 0.9))
				y += thick + 4.0
			return y

		func _color_of(slot: Dictionary, looked: bool) -> Color:
			if slot.alert:
				return Color(WARM, 0.75 + 0.25 * sin(_time * 6.0))
			if slot.empty:
				return Color(INK, 0.45 if looked else 0.28)
			return Color(INK, 1.0 if looked else 0.7)

		## One icon, drawn in lines around `c` at radius `r`.
		func _draw_icon(id: String, c: Vector2, r: float, color: Color, width: float) -> void:
			match id:
				"map":
					var pts := PackedVector2Array([Vector2(-1, -0.7), Vector2(-0.33, -1), Vector2(0.33, -0.7),
							Vector2(1, -1), Vector2(1, 0.7), Vector2(0.33, 1), Vector2(-0.33, 0.7), Vector2(-1, 1),
							Vector2(-1, -0.7)])
					_lines(pts, c, r, color, width)
					_lines(PackedVector2Array([Vector2(-0.33, -1), Vector2(-0.33, 0.7)]), c, r, color, width * 0.6)
					_lines(PackedVector2Array([Vector2(0.33, -0.7), Vector2(0.33, 1)]), c, r, color, width * 0.6)
				"pack":
					# A backpack: the bag, its flap and a pocket.
					_lines(PackedVector2Array([Vector2(-0.65, -0.45), Vector2(0.65, -0.45), Vector2(0.75, 1.0),
							Vector2(-0.75, 1.0), Vector2(-0.65, -0.45)]), c, r, color, width)
					_lines(PackedVector2Array([Vector2(-0.3, -0.45), Vector2(-0.3, -0.85), Vector2(0.3, -0.85),
							Vector2(0.3, -0.45)]), c, r, color, width * 0.8)
					_lines(PackedVector2Array([Vector2(-0.65, -0.1), Vector2(0.65, -0.1)]), c, r, color, width * 0.7)
					_lines(PackedVector2Array([Vector2(-0.35, 0.35), Vector2(0.35, 0.35), Vector2(0.35, 0.75),
							Vector2(-0.35, 0.75), Vector2(-0.35, 0.35)]), c, r, color, width * 0.6)
				"standing":
					# A rank chevron over a bar.
					_lines(PackedVector2Array([Vector2(-0.8, 0.0), Vector2(0, -0.8), Vector2(0.8, 0.0)]),
							c, r, color, width)
					_lines(PackedVector2Array([Vector2(-0.8, 0.5), Vector2(0, -0.3), Vector2(0.8, 0.5)]),
							c, r, color, width)
					_lines(PackedVector2Array([Vector2(-0.8, 0.95), Vector2(0.8, 0.95)]), c, r, color, width * 0.7)
				"vehicle":
					draw_arc(c + Vector2(-0.6, 0.45) * r, 0.38 * r, 0.0, TAU, 16, color, width, true)
					draw_arc(c + Vector2(0.6, 0.45) * r, 0.38 * r, 0.0, TAU, 16, color, width, true)
					_lines(PackedVector2Array([Vector2(-0.6, 0.45), Vector2(-0.1, -0.15), Vector2(0.6, 0.45)]),
							c, r, color, width)
					_lines(PackedVector2Array([Vector2(-0.1, -0.15), Vector2(0.4, -0.65), Vector2(0.7, -0.65)]),
							c, r, color, width)
					_lines(PackedVector2Array([Vector2(-0.6, -0.25), Vector2(0.05, -0.25)]), c, r, color, width)
				"weapon":
					# A rifle in outline: receiver and barrel, stock, grip, magazine.
					_lines(PackedVector2Array([Vector2(-0.45, -0.3), Vector2(1.0, -0.3), Vector2(1.0, -0.12),
							Vector2(0.35, -0.12), Vector2(0.35, 0.05), Vector2(-0.45, 0.05), Vector2(-0.45, -0.3)]),
							c, r, color, width)
					_lines(PackedVector2Array([Vector2(-0.45, -0.3), Vector2(-1.0, -0.2), Vector2(-1.0, 0.3),
							Vector2(-0.45, 0.05)]), c, r, color, width * 0.8)
					_lines(PackedVector2Array([Vector2(-0.2, 0.05), Vector2(-0.35, 0.6)]), c, r, color, width)
					_lines(PackedVector2Array([Vector2(0.1, 0.05), Vector2(0.18, 0.55)]), c, r, color, width * 0.8)
				"artifact":
					var hex := PackedVector2Array()
					for i in 7:
						var a := PI / 6.0 + TAU * i / 6.0
						hex.append(Vector2(cos(a), sin(a)) * 0.95)
					_lines(hex, c, r, color, width)
					_lines(PackedVector2Array([Vector2(0, -0.5), Vector2(0.38, 0), Vector2(0, 0.5),
							Vector2(-0.38, 0), Vector2(0, -0.5)]), c, r, color, width * 0.7)
				"contract":
					# A clipboard with a tick on it.
					_lines(PackedVector2Array([Vector2(-0.7, -0.8), Vector2(0.7, -0.8), Vector2(0.7, 1),
							Vector2(-0.7, 1), Vector2(-0.7, -0.8)]), c, r, color, width)
					_lines(PackedVector2Array([Vector2(-0.3, -1), Vector2(0.3, -1), Vector2(0.3, -0.6),
							Vector2(-0.3, -0.6), Vector2(-0.3, -1)]), c, r, color, width * 0.7)
					_lines(PackedVector2Array([Vector2(-0.4, 0.15), Vector2(-0.1, 0.5), Vector2(0.45, -0.25)]),
							c, r, color, width)
				"race":
					# A chequered flag on its pole.
					_lines(PackedVector2Array([Vector2(-0.75, 1.0), Vector2(-0.75, -1.0)]), c, r, color, width)
					_lines(PackedVector2Array([Vector2(-0.75, -0.95), Vector2(0.85, -0.95), Vector2(0.85, 0.15),
							Vector2(-0.75, 0.15)]), c, r, color, width * 0.8)
					for row in 2:
						for col in 4:
							if (row + col) % 2 == 0:
								var cell := Rect2(c + Vector2(-0.75 + col * 0.4, -0.95 + row * 0.55) * r,
										Vector2(0.4, 0.55) * r)
								draw_rect(cell, Color(color, color.a * 0.7))
				"portal":
					# An upright ring with a swirl inside it.
					var ring := PackedVector2Array()
					for i in 25:
						var a := TAU * i / 24.0
						ring.append(Vector2(cos(a) * 0.62, sin(a) * 0.95))
					_lines(ring, c, r, color, width)
					draw_arc(c, 0.3 * r, 0.0, PI * 1.4, 12, color, width * 0.7, true)
					_lines(PackedVector2Array([Vector2(-0.9, 1.0), Vector2(0.9, 1.0)]), c, r, color, width * 0.7)
				"abandon":
					# A flag on a broken pole: giving up.
					_lines(PackedVector2Array([Vector2(-0.55, 1.0), Vector2(-0.55, 0.2)]), c, r, color, width)
					_lines(PackedVector2Array([Vector2(-0.45, 0.05), Vector2(-0.55, -1.0)]), c, r, color, width)
					_lines(PackedVector2Array([Vector2(-0.53, -0.95), Vector2(0.8, -0.7), Vector2(-0.48, -0.35)]),
							c, r, color, width * 0.8)
					_lines(PackedVector2Array([Vector2(-0.9, 1.0), Vector2(0.3, 1.0)]), c, r, color, width * 0.7)
				"leave":
					_lines(PackedVector2Array([Vector2(-0.75, -0.1), Vector2(-0.75, 1), Vector2(0.75, 1),
							Vector2(0.75, -0.1)]), c, r, color, width)
					_lines(PackedVector2Array([Vector2(0, 0.65), Vector2(0, -1)]), c, r, color, width)
					_lines(PackedVector2Array([Vector2(-0.4, -0.6), Vector2(0, -1), Vector2(0.4, -0.6)]),
							c, r, color, width)

		func _lines(points: PackedVector2Array, c: Vector2, r: float, color: Color, width: float) -> void:
			var placed := PackedVector2Array()
			for point in points:
				placed.append(c + point * r)
			draw_polyline(placed, color, width, true)

		## A control as a glyph: a mouse with its wheel or left button lit, or
		## a key cap with its letter.
		func _draw_hint(hint: String, c: Vector2, color: Color) -> void:
			if hint.begins_with("key:"):
				var box := Rect2(c - Vector2(12, 12), Vector2(24, 24))
				draw_rect(box, color, false, 2.0)
				draw_string(ThemeDB.fallback_font, c + Vector2(-12, 7), hint.substr(4), HORIZONTAL_ALIGNMENT_CENTER,
						24, 18, color)
				return
			var body := Rect2(c - Vector2(9, 14), Vector2(18, 28))
			draw_rect(body, color, false, 2.0)
			draw_line(c + Vector2(-9, -3), c + Vector2(9, -3), color, 1.5)
			draw_line(c + Vector2(0, -14), c + Vector2(0, -3), color, 1.5)
			match hint:
				"wheel":
					draw_rect(Rect2(c + Vector2(-2, -12), Vector2(4, 8)), color)
				"click":
					draw_rect(Rect2(c + Vector2(-8, -13), Vector2(8, 10)), color)


## True while the quick emote wheel is up with no working visor to draw it
## on (no helmet, or one taken off onto the hip): the wrist throws it as a
## small hologram instead (`EmoteHolo`). With a visor it is on the glass
## (`VisorHud._draw_emote_wheel`).
static func emote_wheel_holo(p: Actor, controller: PlayerController) -> bool:
	return controller != null and controller.emote_wheel_open and p != null and is_instance_valid(p) \
			and not p.is_dead and not p.visor.working()


## The quick emote wheel as projected light, for a player with no visor to
## draw it on: a ring of the emotes standing in front of the chest, below
## the eyes and a little left, thrown up from the watch by a thin beam. It
## stands in the world, from the body's own eyes and aim, so it is the same
## in both views; a camera further off sees it grown to read the same.
## View only.
class EmoteHolo:
	extends Node3D

	## Where the ring stands from the eyes: ahead, down and to the left
	## (metres), and its radius.
	var ahead := 0.55
	var down := 0.2
	var left := 0.3
	var radius := 0.1
	## Seen from further than this, the ring grows to read as big.
	var read_at := 0.6
	const INK := Color(0.45, 0.95, 1.0)

	var _labels: Array[Label3D] = []
	var _lines: MeshInstance3D
	var _mesh: ImmediateMesh

	func _ready() -> void:
		top_level = true
		for id: String in Emotes.IDS:
			var label := Label3D.new()
			label.text = Emotes.name_of(id).to_upper()
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.no_depth_test = true
			label.shaded = false
			label.double_sided = true
			label.font_size = 32
			label.outline_size = 6
			label.outline_modulate = Color(0.0, 0.03, 0.05, 0.6)
			label.pixel_size = 0.0006
			label.render_priority = 2
			label.outline_render_priority = 1
			label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(label)
			_labels.append(label)
		_mesh = ImmediateMesh.new()
		_lines = MeshInstance3D.new()
		_lines.mesh = _mesh
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.no_depth_test = true
		mat.vertex_color_use_as_albedo = true
		mat.render_priority = 1
		_lines.material_override = mat
		_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_lines.top_level = true
		add_child(_lines)

	## Where the ring's middle stands for `p`: from the eyes along the aim's
	## heading, never with the view's pitch, so it stays put as you look.
	func spot_for(p: Actor) -> Vector3:
		var aim := p.get_aim_dir()
		var heading := Vector3(aim.x, 0.0, aim.z)
		heading = heading.normalized() if heading.length() > 0.01 else -p.global_basis.z
		var side := heading.cross(Vector3.UP).normalized()
		return p.get_eye_position() + heading * ahead + Vector3.DOWN * down - side * left

	func show_wheel(p: Actor, controller: PlayerController, wrist: Vector3) -> void:
		var middle := spot_for(p)
		var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
		var grow := 1.0
		var up := Vector3.UP
		var right := Vector3.RIGHT
		if cam != null:
			grow = clampf(cam.global_position.distance_to(middle) / read_at, 1.0, 5.0)
			var basis := cam.global_basis.orthonormalized()
			up = basis.y
			right = basis.x
		global_position = middle
		var r := radius * grow
		var picked := controller.emote_wheel_pick
		for i in _labels.size():
			var label := _labels[i]
			var dir := Emotes.slice_dir(i)
			label.global_position = middle + (right * dir.x - up * dir.y) * r
			var on := i == picked
			label.pixel_size = 0.0006 * grow * (1.25 if on else 1.0)
			label.modulate = Color(INK.r, INK.g, INK.b, 1.0 if on else 0.55)
		# The ring, the picked slice's mark and the beam up from the watch.
		_mesh.clear_surfaces()
		_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		var steps := 48
		for k in steps:
			for e in 2:
				var a := TAU * float(k + e) / float(steps)
				_mesh.surface_set_color(Color(INK.r, INK.g, INK.b, 0.25))
				_mesh.surface_add_vertex(middle + (right * sin(a) + up * cos(a)) * r * 0.72)
		var dir := Emotes.slice_dir(picked)
		_mesh.surface_set_color(Color(INK.r, INK.g, INK.b, 0.9))
		_mesh.surface_add_vertex(middle + (right * dir.x - up * dir.y) * r * 0.2)
		_mesh.surface_set_color(Color(INK.r, INK.g, INK.b, 0.9))
		_mesh.surface_add_vertex(middle + (right * dir.x - up * dir.y) * r * 0.72)
		_mesh.surface_set_color(Color(INK.r, INK.g, INK.b, 0.5))
		_mesh.surface_add_vertex(wrist)
		_mesh.surface_set_color(Color(INK.r, INK.g, INK.b, 0.05))
		_mesh.surface_add_vertex(middle - up * r * 0.72)
		_mesh.surface_end()
