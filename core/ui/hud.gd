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
##     Mission is the contract, the squad ping, and sign-out and banking.
##     Down, it shows what your death cost and where you can land. With no
##     helmet, or in third person, it also carries the vitals as a thin strip;
##   - an ammo counter on every gun (`AMMO_COUNTER` on the gun's model);
##   - a heat gauge in the screen bay on the back of a jetpack
##     (`HEAT_READOUT`), seen in third person and by everyone around you.
## War news goes to the phone as a notification (`notice_sink`) when the game
## gives the HUD one.

const RenownLedger := preload("res://core/progression/renown_ledger.gd")
const Contracts := preload("res://core/economy/contracts.gd")
const SkinScript := preload("res://core/visual/actor_skin.gd")
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
## The wrist display.
var wrist: Wrist
## What the helmet draws on its glass in first person, and what its visor
## shows out in the world (scan snapshots, tags).
var visor: VisorHud

var _hit_marker: HitMarker
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

	raid.player.notice.connect(_on_notice)
	if not raid.pinged.is_connected(_on_pinged):
		raid.pinged.connect(_on_pinged)
	raid.war_feed.connect(_on_war_feed)
	raid.player.hit_confirmed.connect(_on_hit_confirmed)
	raid.player.health.damaged.connect(_on_player_damaged)


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
	_stance.stance = blade.stance if blade else -1
	_stance.guarding = blade != null and blade.is_blocking()
	_stance.threat = incoming_side(p)
	_update_ammo_counters(p)
	if crosshair:
		# Looking down an optic, its own reticle marks the middle.
		crosshair.modulate.a = 0.0 if controller != null and is_instance_valid(controller) and controller.sighted else 1.0
	_update_heat_display(p)

	var banking := raid.bank_progress()
	var leaving := raid.sign_out_progress(p)
	if p.is_dead:
		var places := drop_choices(raid, p).size()
		var landing := "1-%d: pick where to land      " % places if places > 1 else ""
		_prompt.text = landing + "Enter: drop back in      L: go home" if _redeploy_wait <= 0.0 \
				else "Dropping back in in %d..." % ceili(_redeploy_wait)
		if _death_result.is_empty():
			_prompt.text = ""
	elif leaving >= 0.0:
		_prompt.text = "Signing out...   L to cancel"
	elif banking > 0.0:
		_prompt.text = "Banking your backpack..."
	elif p.heal_time_left > 0.0:
		_prompt.text = "Healing %.1f" % p.heal_time_left
	else:
		# On a vehicle, F gets you off, so nothing else is offered.
		var target := p.find_interactable() if p.vehicle == null else null
		_prompt.text = target.get_prompt() if target else ""

	for m in _messages:
		m.time -= delta
	_messages = _messages.filter(func(m: Dictionary) -> bool: return m.time > 0.0)
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
	var picks := {"weapon": controller.weapon_pick, "artifact": controller.artifact_pick, "portal": controller.portal_pick} \
			if controller != null else {}
	var slots := watch_slots(raid, p, picked, pack_name, leaving, banking, picks, contracts)
	mark_open(slots, controller.watch_open if controller != null else "")
	var focus := default_focus(slots)
	if controller != null:
		if controller.watch_focus_moved:
			focus = clampi(controller.watch_focus, 0, slots.size() - 1)
		else:
			controller.watch_focus = focus
	var death := death_text(_death_result, _redeploy_wait, drop_choices(raid, p)) \
			if p.is_dead and not _death_result.is_empty() else ""
	# Your vitals are on the visor's edges while you look through it; with
	# no helmet, or in third person, the card carries them in a thin strip.
	var on_glass := visor != null and visor.glass_shown()
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
static func mark_open(slots: Array[Dictionary], opened: String) -> void:
	for slot in slots:
		if int(slot.get("count", 0)) > 1 and slot.id != opened:
			var hints: Array = slot.hints.filter(func(h: String) -> bool: return h != "wheel")
			if not hints.has("click"):
				hints.append("click")
			slot.hints = hints


## The weapons on the watch's carousel, in the order the wheel turns through
## them: the ones worn (primary, sidearm, melee, heavy) and then the ones in
## the pack, then any helmets and armor in the pack (a click puts one on). Each is
## {"id", "index" (in `Actor.weapons`, or -1 in the pack)}.
## Only what is carried is ever here, never the stash.
static func weapon_entries(p: Actor) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for index in p.slot_order():
		entries.append({"id": p.weapons[index].item_id, "index": index})
	# The heavy chamber's weapon: drawn only from here, never by a key.
	var heavy := Loadout.power_index(p)
	if heavy >= 0:
		entries.append({"id": p.weapons[heavy].item_id, "index": heavy})
	for id in p.inventory.items:
		if Loadout.summonable(id):
			entries.append({"id": id, "index": -1})
	# Helmets and armor frames carried are put on with a click, swapping for
	# the one worn.
	for id in p.inventory.items:
		if ItemDB.has_tag(id, "helmet") or ItemDB.has_tag(id, "armor"):
			entries.append({"id": id, "index": -1})
	return entries


## The artifacts on the watch's carousel (item ids): the one attuned for
## this outing first, then any carried in the pack as loot.
static func artifact_entries(p: Actor) -> Array[String]:
	var entries: Array[String] = []
	if p.artifact.enabled:
		entries.append(p.artifact.item_id)
	for id in p.inventory.items:
		if ItemDB.has_tag(id, "artifact"):
			entries.append(id)
	return entries


## The pack's line under the Summon tab: how full, what it is worth, heals
## and scrip.
static func pack_text(p: Actor) -> String:
	var pack := "Pack %d/%d" % [p.inventory.items.size(), p.inventory.capacity]
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
	# The artifacts carried: the one attuned for this outing, and any found.
	var relics := artifact_entries(p)
	var relic_at := clampi(int(picks.get("artifact", 0)), 0, maxi(relics.size() - 1, 0))
	if relic_at > 0 or (not relics.is_empty() and not p.artifact.enabled):
		slots.append(_slot("artifact", "", "%s · in pack, not attuned" % ItemDB.item_name(relics[relic_at]),
				["wheel"] if relics.size() > 1 else [], -1.0, false, false, relics.size(), relic_at))
	else:
		var relic := artifact_slot(p.artifact)
		relic["count"] = relics.size()
		if relics.size() > 1:
			relic["hints"] = ["wheel"] + relic["hints"]
		slots.append(relic)
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
	slots.append(_slot("map", "", where, [], -1.0, false, false))
	var hunted := p.bounty > 0 or p.exposed or p.marked
	slots.append(_slot("standing", str(p.renown) if p.renown > 0 else "", standing_text(p).replace("   ", " · "),
			[], -1.0, false, hunted))
	# Mission: the squad portal, the contract, the squad ping, and sign-out
	# and banking.
	slots.append(portal_slot(Portal.choices_for(p_raid, p), int(picks.get("portal", 0))))
	slots.append(contract_slot(jobs, p.tally))
	slots.append(_slot("ping", "", "Ping where you look", ["click"], -1.0, false, false))
	if leaving >= 0.0:
		slots.append(_slot("leave", "", "Signing out", ["key:L"], leaving, false, true))
	elif banking > 0.0:
		slots.append(_slot("leave", "", "Banking", [], banking, false, true))
	else:
		slots.append(_slot("leave", "", "Sign out", ["key:L"], -1.0, false, false))
	return slots


## The weapon carousel's icon: the weapon picked out of what is carried.
## One worn is drawn with a click (a heavy weapon shows its shots); one in
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
			return _slot("weapon", value, "%s · in hand" % detail, hints, -1.0, false, false, entries.size(), at)
		return _slot("weapon", value, detail, hints + ["click"], -1.0, false, false, entries.size(), at)
	if ItemDB.has_tag(entry.id, "helmet"):
		return _slot("weapon", value, "%s · wear" % name, hints + ["click"], -1.0, false, false, entries.size(), at)
	var wait := p_raid.summon_wait(p) if p_raid != null else 0.0
	if wait > 0.0:
		return _slot("weapon", value, "%s · %d s" % [name, ceili(wait)], hints, p_raid.summon_charge(p), false, false,
				entries.size(), at)
	return _slot("weapon", value, "%s · pack · %.1f s" % [name, Loadout.summon_time(entry.id)], hints + ["click"],
			-1.0, false, false, entries.size(), at)


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
		return _slot("weapon", value, "%s · in hand" % name, hints, -1.0, false, false, entries.size(), at)
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
		portal_pick := 0) -> Array[Dictionary]:
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
	slots.append(_slot("map", "", base_name, [], -1.0, false, false))
	slots.append(_slot("standing", "", "At home", [], -1.0, true, false))
	slots.append(portal_slot(Portal.destinations(), portal_pick))
	slots.append(contract_slot(held, {}))
	slots.append(_slot("ping", "", "No squad here", [], -1.0, true, false))
	slots.append(_slot("leave", "", "Home", [], -1.0, true, false))
	return slots


## The squad portal icon: a carousel of where a portal can lead from here
## (`choices`, none outside a safe space), the one `picked` out on its line.
## A click opens it in front of you for your squad to walk through.
static func portal_slot(choices: Array[String], picked := 0) -> Dictionary:
	if choices.is_empty():
		return _slot("portal", "", "Portals open in safe zones and gate outposts", [], -1.0, true, false)
	if choices == [Portal.HOME]:
		# A gate outpost's portal: a sign-out with a door.
		return _slot("portal", "", "Portal home · signs you out", ["click"], -1.0, false, false, 1, 0)
	var at := clampi(picked, 0, choices.size() - 1)
	return _slot("portal", "", "Portal to %s" % Portal.title_of(choices[at]), ["wheel", "click"], -1.0, false, false,
			choices.size(), at)


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


## The vitals: health, armor and stamina from 0 to 1, and flight heat (-1
## with no flight rig). On the visor's edges, or the card's strip without one.
static func wrist_bars(p: Actor) -> Array[float]:
	return [p.health.health / p.health.max_health,
			p.health.armor / p.health.max_armor if p.health.max_armor > 0.0 else 0.0,
			p.stamina / p.max_stamina,
			p.flight.heat_fraction() if p.flight.enabled else -1.0]


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
	(fill.material_override as StandardMaterial3D).albedo_color = color
	(fill.material_override as StandardMaterial3D).emission = color
	var word := readout.get_node("Word") as Label3D
	word.text = heat_text(p.flight)
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
	if lethal:
		_hit_marker.flash(Color(1.0, 0.25, 0.2), 0.35)
	elif info.parried or info.blocked:
		_hit_marker.flash(Color(0.6, 0.75, 1.0), 0.15)
	else:
		_hit_marker.flash(Color.WHITE, 0.15)


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


## `drops` is where they may land next (`Raid.drop_choices`).
static func death_text(result: Dictionary, wait: float, drops: Array = []) -> String:
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
	var banked: Array = result.get("banked", [])
	if not banked.is_empty():
		lines.append("Banked before you fell: worth %d" % int(result.get("banked_value", 0)))
	lines.append("")
	if wait > 0.0:
		lines.append("Drop back in in %d..." % ceili(wait))
	else:
		# One place to land is no choice: Enter is enough.
		if drops.size() > 1:
			for i in drops.size():
				lines.append("%d: %s, %s" % [i + 1, drops[i].title, drops[i].note])
			lines.append("")
		lines.append("Enter: drop back in      L: return to the hub")
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
func pings_shown() -> int:
	return _pings.size()


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


## Four diagonal ticks around the crosshair that flash when your attack lands.
class HitMarker:
	extends Control

	var _left := 0.0
	var _duration := 0.15
	var _color := Color.WHITE

	func flash(color: Color, duration: float) -> void:
		_color = color
		_duration = duration
		_left = duration
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
		for dir: Vector2 in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
			draw_line(c + dir * 7.0, c + dir * 15.0, color, 2.5)

## Three marks around the crosshair for directional melee: which side you are
## set to attack or guard, and which side an enemy swing is coming at.
## Kept as an inner class so the HUD never depends on the editor's class cache.
class StanceIndicator:
	extends Control

	const OFFSETS := [Vector2(0, -1), Vector2(-1, 0), Vector2(1, 0)]

	## The player's `MeleeWeapon.Dir`, or -1 to hide the stance marks.
	var stance := -1
	var guarding := false
	## The side of the screen an enemy swing is coming at, or -1 for none.
	var threat := -1

	var radius := 34.0
	var threat_radius := 48.0
	var mark_length := 22.0


	func _process(_delta: float) -> void:
		queue_redraw()


	func _draw() -> void:
		var center := size * 0.5
		for dir in OFFSETS.size():
			var out: Vector2 = OFFSETS[dir]
			var along := Vector2(-out.y, out.x) * mark_length * 0.5
			if stance >= 0:
				var active := dir == stance
				var color := Color(1, 1, 1, 0.22)
				if active:
					color = Color(0.45, 0.75, 1.0) if guarding else Color.WHITE
				var at := center + out * radius
				draw_line(at - along, at + along, color, 4.0 if active else 2.0)
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
## and your standing. Mission is the contract, the squad ping, and sign-out
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
		"summon": ["weapon", "vehicle", "artifact"],
		"status": ["map", "standing"],
		"mission": ["portal", "contract", "ping", "leave"],
	}
	## Every icon, left to right, tab after tab (see `Hud.watch_slots`). The
	## wheel steps along this.
	const SLOTS := ["weapon", "vehicle", "artifact", "map", "standing", "portal", "contract", "ping", "leave"]
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
void fragment() {
	vec2 uv = UV;
	float settle = 1.0 - open;
	uv.x += settle * 0.03 * sin(uv.y * 90.0 + TIME * 40.0);
	vec4 c = texture(card, uv);
	float lines = 0.86 + 0.14 * sin(uv.y * 420.0 - TIME * 8.0);
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
	## The bone the watch is worn on in third person.
	const WRIST_BONE := "Wrist.L"
	## The back of the wrist in that bone's space, where the watch face looks
	## out (the bone's own +Y runs along the arm to the hand).
	const FACE_AXIS := Vector3.RIGHT
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
	var tp_behind := 0.5
	var tp_screen := 0.34
	var tp_lift := 0.06
	var tp_backing := 0.6
	## How far, in metres at the head, the card keeps clear of the head and
	## helmet from the camera's view.
	var head_clearance := 0.05
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
		var beam_mat := StandardMaterial3D.new()
		beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		beam_mat.vertex_color_use_as_albedo = true
		beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		# Depth tested: in third person the body hides the light where it
		# would pass behind it.
		beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
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
			if id in TAB_SLOTS[tab]:
				return tab
		return ""

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

	## Where the watch is in the world, third person: on the wrist bone, or
	## where a left wrist would be when there is no skin.
	func watch_position(p: Actor) -> Vector3:
		if _worn != null and is_instance_valid(_worn) and _worn.is_inside_tree():
			return _worn.global_position
		return p.global_transform * Vector3(-0.3, 1.05, -0.1)

	## Puts the watch and its card where the view can see them, and opens or
	## closes the card towards `raised`. Hidden with the HUD.
	func mount(p: Actor, controller: PlayerController, shown: bool, delta := 0.0) -> void:
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
				var at := wrist.lerp(spot, ease(open, -2.0))
				_holo.global_transform = Transform3D(facing.scaled(Vector3(size, size * maxf(open, 0.001), size)), at)
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
		var overlap := card.x + half_width - head_left
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

	## Light thrown out from the watch face to the card's lower edge, bright
	## at the face and thinning out towards the card, so the card reads as
	## projected rather than floating.
	func _draw_beam(third: bool, open: float) -> void:
		var mesh := _beam.mesh as ImmediateMesh
		mesh.clear_surfaces()
		_beam.visible = _holo.visible and is_inside_tree()
		if not _beam.visible:
			return
		_beam.global_transform = Transform3D.IDENTITY
		var apex := _face_position(third)
		var half := face_size * 0.5
		var corners: Array[Vector3] = []
		for c: Vector2 in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]:
			corners.append(_holo.global_transform * Vector3(c.x, c.y, 0.0))
		var bright := Color(GLOW_COLOR, 0.22 * open)
		# A fan of light up to the card's lower edge, and two fine rays at
		# its sides. Nothing crosses the card's face, so it stays readable.
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		mesh.surface_set_color(bright)
		mesh.surface_add_vertex(apex)
		mesh.surface_set_color(Color(GLOW_COLOR, 0.04 * open))
		mesh.surface_add_vertex(corners[0])
		mesh.surface_set_color(Color(GLOW_COLOR, 0.04 * open))
		mesh.surface_add_vertex(corners[1])
		mesh.surface_end()
		mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		for corner in [corners[0], corners[1]]:
			mesh.surface_set_color(Color(GLOW_COLOR, 0.55 * open))
			mesh.surface_add_vertex(apex)
			mesh.surface_set_color(Color(GLOW_COLOR, 0.15 * open))
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
		card.focus = clampi(focus, 0, maxi(slots.size() - 1, 0))
		card.death = death
		card.bars = bars
		card.note = notes[-1] if not notes.is_empty() else ""
		card.queue_redraw()
		# The watch face shows health even with the card down: cyan when
		# well, red when low.
		face_color = face_tint(clampf(health, 0.0, 1.0))
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
		_toys.position = Vector3(0.0, face_size.y * 0.5 + toy_lift, 0.0)
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
		_weapons.position = Vector3(0.0, face_size.y * 0.5 + toy_lift + 0.012, 0.0)
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
					Vector3(0.27, 0.31, 0.31), Color(0.22, 0.23, 0.25))
		elif ItemDB.has_tag(id, "armor"):
			# A frame shows the plates it is worn as.
			model = SkinScript.build_frame(SkinScript.frame_weight(id), SkinScript.FRAME_COLOR)
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
		return "\n".join(lines)

	## The id of the icon being looked at ("" with none).
	func focused_id() -> String:
		return card.focused_id() if card != null else ""

	## The controls the open icon shows as glyphs ("wheel", "click", "key:L").
	func focused_hints() -> Array:
		if card == null or card.slots.is_empty():
			return []
		return card.slots[card.focus].hints


	## The card's picture, drawn into the watch's viewport: thin lines of light
	## on next to nothing, like the visor. Icons are drawn from lines here,
	## so the card needs no textures.
	class Card:
		extends Control

		const INK := Color(0.6, 1.0, 1.0)
		const WARM := Color(1.0, 0.62, 0.3)
		const BAR_COLORS := [Color(1.0, 0.35, 0.3), Color(0.45, 0.7, 1.0), Color(0.95, 0.9, 0.4), Color(1.0, 0.6, 0.2)]

		var slots: Array[Dictionary] = []
		var focus := 0
		var death := ""
		var bars: Array[float] = []
		var note := ""
		## A line under a tab's name: tab -> text.
		var summaries := {}
		## A line that is only there while it matters (the rig's cue in flight).
		var popup := ""
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
			var step := minf((w - 40.0) / count, 170.0)
			var left := (w - step * count) * 0.5
			for n in count:
				var i := shown[n]
				var slot := slots[i]
				var centre := Vector2(left + step * (n + 0.5), row_y)
				var looked := i == focus
				var color := _color_of(slot, looked)
				var radius := 30.0 if looked else 21.0
				if looked:
					draw_arc(centre, radius + 11.0, 0.0, TAU, 40, Color(color, 0.25), 1.5, true)
				var progress: float = slot.progress
				if progress >= 0.0:
					draw_arc(centre, radius + 11.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(progress, 0.0, 1.0), 40,
							Color(WARM if slot.alert else INK, 0.95), 4.0, true)
				_draw_icon(slot.id, centre, radius, color, 3.0 if looked else 2.0)
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
			# The open icon's one line, with its controls as glyphs after it.
			var open := slots[focus]
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
			y += 12.0
			var line: String = summaries.get(open_tab, "")
			if line != "":
				y += 18.0
				draw_string(font, Vector2(20, y), line, HORIZONTAL_ALIGNMENT_CENTER, w - 40, 17, Color(INK, 0.85))
			if popup != "":
				y += 18.0
				draw_string(font, Vector2(20, y), popup, HORIZONTAL_ALIGNMENT_CENTER, w - 40, 17,
						Color(WARM, 0.95))
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
				"standing":
					# A rank chevron over a bar.
					_lines(PackedVector2Array([Vector2(-0.8, 0.0), Vector2(0, -0.8), Vector2(0.8, 0.0)]),
							c, r, color, width)
					_lines(PackedVector2Array([Vector2(-0.8, 0.5), Vector2(0, -0.3), Vector2(0.8, 0.5)]),
							c, r, color, width)
					_lines(PackedVector2Array([Vector2(-0.8, 0.95), Vector2(0.8, 0.95)]), c, r, color, width * 0.7)
				"ping":
					# A point with rings going out.
					draw_circle(c, 0.16 * r, color)
					draw_arc(c, 0.5 * r, 0.0, TAU, 20, color, width * 0.8, true)
					draw_arc(c, 0.92 * r, -PI * 0.3, PI * 0.3, 12, color, width * 0.7, true)
					draw_arc(c, 0.92 * r, PI * 0.7, PI * 1.3, 12, color, width * 0.7, true)
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
				"portal":
					# An upright ring with a swirl inside it.
					var ring := PackedVector2Array()
					for i in 25:
						var a := TAU * i / 24.0
						ring.append(Vector2(cos(a) * 0.62, sin(a) * 0.95))
					_lines(ring, c, r, color, width)
					draw_arc(c, 0.3 * r, 0.0, PI * 1.4, 12, color, width * 0.7, true)
					_lines(PackedVector2Array([Vector2(-0.9, 1.0), Vector2(0.9, 1.0)]), c, r, color, width * 0.7)
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
