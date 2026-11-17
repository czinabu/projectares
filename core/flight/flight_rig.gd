class_name FlightRig
extends Node
## One class covers every rig; the item's stats decide how it flies. Each rig
## has one job and one weakness (DESIGN.md section 5, Caleb's balance pass):
##   jetpack        - height and hover. `thrust_accel`: hold jump in the air
##                    to climb, hold aim to hover and cruise, Shift boosts.
##                    Heat-limited, steady aim, but loud and slow across the
##                    map, and clumsy under a roof (`indoor_mult`).
##   thruster boots - ground agility and stealth. Faster on foot
##                    (`ground_speed_mult`), kicks (`burst_velocity`) and air
##                    dashes paid from charges (`max_charges`), not heat, a
##                    graze window on every dash (`graze_window`), a short
##                    skim (`skim_time`), quiet on scans, low ceiling.
##   glide wings    - distance and speed. A launch, then `glide_speed` with
##                    dives; gliding spends glide stamina (`glide_heat`) that
##                    refills only on the ground, and a couple of boosts a
##                    flight (`max_charges`). No hover, poor aim, no use
##                    indoors.
## Each Mk tier adds about 15% to the rig's strength only.

## An air jump went off. Cosmetic: the model fires its nozzles for a moment.
signal burst_fired

## The jetpack's level flying speed (m/s), the default `fly_speed`.
const CRUISE_SPEED := 14.0
## How far past `max_heat` a burst or pulse may land (it then overheats).
const BURST_SLACK := 0.05
## Below its ceiling a rig's climb eases off over this many meters, so the
## climb comes to rest on the ceiling instead of hitting it.
const CEILING_EASE := 4.0
## A kick, pulse or launch that could lift you less than this (m/s) under the
## ceiling is refused rather than spent.
const MIN_LIFT := 3.0

var item_id := ""
var display_name := "No rig"
## False until a rig item is equipped.
var enabled := false

## The rig's tier (Mk1, Mk2, ...). Each tier adds about 15% to the rig's
## own strength only (`ItemDB._rig_tier`).
var tier := 1
## The highest the rig can lift you, in meters over the world's ground (a
## roof under you does not count, so roof-hopping never stacks it): jets
## stop climbing there and a kick, pulse or launch tops out on it. It only
## limits lift; dropping off something higher is fine, and the rig still
## holds or glides you there. 0: no ceiling.
var ceiling := 0.0
## Set by the `Actor` every tick in the air: how high you are over the
## world's ground, and whether the world says where that is
## (`Actor.ground_level`). Where it does not, there is no ceiling.
var altitude := 0.0
var altitude_known := false

## The defaults are the free Mk1 jetpack; other rigs set what differs.
var thrust_accel := 36.0
var max_rise_speed := 8.0
var max_heat := 100.0
## Heat a second of hovering costs; climbing and boosting cost multiples of
## it (`climb_heat_mult`, `boost_heat_mult`).
var heat_per_sec := 12.5
var cool_per_sec := 25.0
var cool_delay := 0.5
## After overheating, thrust stays locked until heat falls below this.
var recover_heat := 35.0
## Upward speed from pressing jump in the air, and the heat each press costs.
## A press that would take heat past `max_heat` is refused, not fired.
var burst_velocity := 0.0
var burst_heat := 0.0
## Only one burst until you touch the ground again (wings: the launch).
var launch_once := false
## Wings: pressing jump while gliding gives this much upward speed, keeping
## your airspeed, for `pulse_heat`. Gliding cools at `glide_cool` a second
## with no delay, so one pulse every `pulse_heat / glide_cool` seconds holds
## a level flight and pulsing faster overheats.
var pulse_velocity := 0.0
var pulse_heat := 0.0
var glide_cool := 0.0
## While holding jump and falling: the fastest you sink, and how fast you fly.
## Zero means the rig cannot glide.
var glide_fall_speed := 0.0
var glide_speed := 0.0
var glide_accel := 22.0

## Jet flight, for rigs with thrust. Holding aim in the air lights the jets
## and they stay lit only while it is held (Caleb's call: no hover that stays
## on by itself): the rig holds you up, the move keys cruise you about at
## `fly_speed`, jump climbs and the descend key (held slide) coasts: the jets
## idle, you sink at `descend_speed` keeping your speed, and the rig cools at
## `coast_cool` a second. A sprint press in the air is a boost, no hover
## needed, and holding sprint keeps it going: you speed up head first toward
## `boost_speed` along the view's heading, laid out prone, climbing or
## sinking only on jump and descend (0: no boost). The keys fly every rig; the mouse only looks.
## Holding still costs `hover_heat_mult` of `heat_per_sec`, cruising
## `cruise_heat_mult`, climbing `climb_heat_mult` and boosting
## `boost_heat_mult` (Caleb's call: 1x, 1x, 1.5x, 2.5x).
## At cruise speed the heading turns at most `cruise_turn_rate` rad/s: a
## jetpack makes wide turns but stops dead. Landing or overheating puts the
## jets out.
var fly_speed := CRUISE_SPEED
var fly_accel := 24.0
var boost_speed := 0.0
var boost_accel := 16.0
var descend_speed := 6.0
## How fast the jets bring your climb or sink to what you ask for, in m/s².
var hover_accel := 30.0
var hover_heat_mult := 1.0
var cruise_heat_mult := 1.0
var climb_heat_mult := 1.5
var boost_heat_mult := 2.5
var coast_cool := 25.0
var cruise_turn_rate := 1.2
## A jetpack carries heavy armor: a frame's extra heat (`heat_mult` above 1)
## does not apply to it (`Loadout.equip`).
var heavy_lift := false
## Gliding is flown like a wing. The heading turns toward where you steer at
## up to `glide_turn_rate` (radians a second) instead of sliding sideways.
## Speed is energy: looking down dives (up to `glide_dive_gain` faster,
## sinking up to `glide_dive_fall`, gaining `glide_dive_accel` m/s²), and
## looking up trades speed for height until you are down to the stall speed
## (`glide_stall` of `glide_speed`); each meter climbed costs speed
## (`glide_climb_cost`, a little more than the dive gave).
## Below glide speed you only pick speed back up slowly (`glide_recover`).
var glide_turn_rate := 1.6
var glide_dive_gain := 0.6
var glide_dive_fall := 10.0
var glide_dive_accel := 5.0
var glide_drag := 2.0
var glide_stall := 0.6
var glide_climb_cost := 14.0
var glide_recover := 6.0
var glide_lift_accel := 60.0
## How hard the wings catch a fall or a dive back to the glide's own sink, in
## m/s². It is never instant: a snap in one tick reads as a hitch.
var glide_catch_accel := 45.0
## How fast the bank rolls in and out on the strafe keys, per second: full
## bank after 1 / `glide_bank_rate` seconds. A tap only nudges the heading.
var glide_bank_rate := 8.0
## Forward held with no strafe key turns the glide onto the view's heading:
## full bank while it is off by this many radians or more, easing to level
## as it comes round, so it settles on the view without swinging past.
var glide_align_angle := 0.5
## Flying like a wing (see `Actor._glide_velocity`): speed lost a second in
## a full bank, how much more a pull tightens a banked turn, how much faster
## a full bank sinks (1: twice as fast), how much of a pull's climb a full
## bank turns into turning instead, and how well stalled wings still turn.
var glide_turn_drag := 3.0
var glide_pull_turn := 0.6
var glide_bank_sink := 1.0
var glide_bank_lift_loss := 0.7
var stall_authority := 0.3
## Stalled, the nose drops and the fall gives back this much speed a second.
var stall_recover := 8.0
## Below the stall speed a glide sinks this fast (0: just the glide sink).
var stall_sink := 0.0
## Wings: only a sidearm fires while they are spread, and a main gun only
## `glide_stow_time` after they fold.
var glide_sidearm_only := false
var glide_stow_time := 0.35
## Wings: touching down at least this fast turns into a slide that keeps the
## speed (0: off).
var slide_landing_speed := 0.0
## Sideways speed an air jump adds along the move keys (thruster boots).
var burst_push := 0.0
## Boots: holding jump in the air skims at this speed (0: no skim), holding
## your height (a kick still carries you up first; descend sinks). The heat
## depends on the height over the ground or roof below: under `skim_low`
## meters the boots cool at `skim_cool` a second, up to `skim_high` they
## cost `skim_mid_heat`, and above it `skim_high_heat`. You stop dead when
## you let go of the move keys (`skim_accel`). Boots only ever cool near a
## surface (`aloft`): a set of kicks tops a rooftop, and the roof under your
## feet is where they cool again.
var skim_speed := 0.0
var skim_accel := 40.0
var skim_hold_accel := 30.0
var skim_low := 6.0
var skim_high := 12.0
var skim_cool := 5.0
var skim_mid_heat := 8.0
var skim_high_heat := 20.0
## How far down the boots look for a surface.
var skim_probe := 30.0
## Every rig: pressing sprint in the air dashes the way the move keys point
## (forward with none held). The dash adds `air_dash_speed` that way on top
## of how the rig is flying for `air_dash_time`, then takes it back off, so
## a glide or a cruise carries on as before. It costs `air_dash_heat` and
## waits `air_dash_cooldown` before the next (0 speed: no dash). The
## defaults are the jetpacks'; boots dash furthest (their edge), wings
## shortest but cheapest. Holding sprint on after a jetpack's forward dash
## keeps boosting (`boost_speed`).
var air_dash_speed := 16.0
var air_dash_time := 0.25
var air_dash_heat := 15.0
var air_dash_cooldown := 0.7
## Wings: Shift (or Shift + W) in a glide is a boost instead of a dash. It
## thrusts you the way you face, adding `glide_boost` m/s of airspeed that
## the glide keeps and bleeds off at `glide_drag`, and Shift + S climbs at
## `glide_boost_climb` m/s, keeping the airspeed. Either costs
## `glide_boost_heat` (0 boost: the ordinary dash).
var glide_boost := 0.0
var glide_boost_climb := 0.0
var glide_boost_heat := 0.0

## Rigs that run on charges instead of heat (the boots' kicks and dashes,
## the wings' boosts): each spends one charge, and one comes back every
## `charge_time` seconds, only on the ground with `charge_on_ground`. A
## launch-once launch is free. 0: everything costs heat.
var max_charges := 0
var charge_time := 1.5
var charge_on_ground := false
## Boots: how long a skim holds you up per time in the air, refilled on
## landing (0: no limit, only heat).
var skim_time := 0.0
## Wings: glide stamina, as heat a second of gliding builds. With
## `ground_cool_only` it comes back only on the ground.
var glide_heat := 0.0
var ground_cool_only := false
## On foot with the rig worn: walk, sprint and slide speed scale.
var ground_speed_mult := 1.0
## How much the air spoils aim while the rig flies its own way (jets lit
## and not boosting, a boots dash, a glide), against 1 for a plain fall.
## See `Actor.air_aim`.
var flight_aim := 1.0
## The share of fall damage taken on landing (`Actor.fall_safe_speed`).
## Landing out of a glide takes none whatever the rig.
var fall_damage_mult := 1.0
## Boots: every dash opens a window this long where rounds only graze,
## doing `graze_mult` of their damage (0: no window).
var graze_window := 0.0
var graze_mult := 0.25
## How far a thermal visor or a Seeker scan picks up whoever wears the rig,
## in meters (0: the visor's own reach). Loud, bright rigs carry further.
var scan_range := 0.0
## Under a roof (`indoors`): the share of flying speed and climb left. 1
## works fully, 0 cannot fly at all (wings cannot open).
var indoor_mult := 1.0

var heat := 0.0
var overheated := false
## Charges left (see `max_charges`), and the skim time left this flight.
var charges := 0
var skim_left := 0.0
## A roof is close overhead (the `Actor` sets it every tick in the air).
var indoors := false
var _charge_wait := 0.0
## An artifact's Overclock Core is running: flying makes no heat.
var heat_free := false
## Seconds left with the rig shut off by an artifact's Static Bloom. While
## jammed it does nothing at all: no thrust, no glide, no skim, no dash.
var jam_left := 0.0
var is_thrusting := false
var is_gliding := false
## The jets are lit and holding you up (see `fly_speed`).
var is_hovering := false
## Flying head first at boost speed.
var is_boosting := false
## Jets idle, sinking and cooling (see `coast_cool`).
var is_coasting := false
## Boots skimming (holding jump in the air).
var is_skimming := false
## Boots: the height over the surface below while skimming, in meters.
var skim_height := 0.0
## Boots in the air at `skim_low` or more over the surface below: they do not
## cool there (the `Actor` sets it every tick).
var aloft := false
## The launch of a `launch_once` rig has been used this time in the air.
var launched := false
var _since_thrust := 0.0


## Advances the rig one tick and returns the upward acceleration it provides.
## `heat_mult` scales the heat this tick costs (hovering costs less).
func tick(wants_thrust: bool, delta: float, heat_mult := 1.0) -> float:
	is_thrusting = working() and wants_thrust and not overheated and thrust_accel > 0.0
	if is_thrusting:
		_since_thrust = 0.0
		heat += _heat(heat_per_sec * heat_mult * delta)
		if heat >= max_heat:
			heat = max_heat
			overheated = true
			is_hovering = false
			is_boosting = false
		return thrust_accel
	_since_thrust += delta
	if is_gliding and (glide_cool > 0.0 or glide_heat > 0.0):
		heat = maxf(0.0, heat + (_heat(glide_heat) - glide_cool) * delta)
		if heat >= max_heat:
			heat = max_heat
			overheated = true
			is_gliding = false
	elif _since_thrust >= cool_delay and not aloft:
		heat = maxf(0.0, heat - cool_per_sec * delta)
	_recover()
	return 0.0


## Jets idle while lit: no thrust, and the rig cools at `coast_cool`.
func coast(delta: float) -> void:
	is_thrusting = false
	heat = maxf(0.0, heat - coast_cool * delta)
	_recover()


## Boots skimming at `height` over the surface below: cools low down,
## heats up higher (see `skim_speed`).
func skim(delta: float, height: float) -> void:
	is_thrusting = false
	skim_height = height
	skim_left = maxf(0.0, skim_left - delta)
	if height < skim_low:
		heat = maxf(0.0, heat - skim_cool * delta)
		_recover()
		return
	_since_thrust = 0.0
	heat += _heat((skim_mid_heat if height < skim_high else skim_high_heat) * delta)
	if heat >= max_heat:
		heat = max_heat
		overheated = true
		is_skimming = false


## Which band a skim is in: 0 cool (low), 1 warm, 2 burning.
func skim_band() -> int:
	return 0 if skim_height < skim_low else (1 if skim_height < skim_high else 2)


func can_skim() -> bool:
	return working() and skim_speed > 0.0


## True if a skim may start or go on: boots with skim time left.
func skim_ready() -> bool:
	return can_skim() and not overheated and (skim_time <= 0.0 or skim_left > 0.0)


## Every tick: a rig on charges refills them (only on the ground with
## `charge_on_ground`), and landing refills the skim.
func refill(delta: float, on_floor: bool) -> void:
	if on_floor:
		skim_left = skim_time
	if max_charges <= 0 or charges >= max_charges:
		_charge_wait = 0.0
		return
	if charge_on_ground and not on_floor:
		return
	_charge_wait += delta
	while _charge_wait >= charge_time and charges < max_charges:
		_charge_wait -= charge_time
		charges += 1


## Full charges and skim, as a rig is put on.
func fill() -> void:
	charges = max_charges
	skim_left = skim_time
	_charge_wait = 0.0


## The share of flying speed and climb left here (see `indoor_mult`).
func indoor_factor() -> float:
	return indoor_mult if indoors else 1.0


## Pays for a kick, dash or boost: a charge on a rig that runs on them,
## else `cost` heat (see `_spend`).
func _pay(cost: float) -> bool:
	if max_charges <= 0:
		return _spend(cost)
	if charges <= 0:
		return false
	charges -= 1
	return true


## A dash in the air. True if it goes off (and takes its heat).
## `cost` overrides the dash's heat (a wing boost); below zero it is
## `air_dash_heat`.
func try_air_dash(cost := -1.0) -> bool:
	if not working() or overheated or air_dash_speed <= 0.0 or indoor_factor() <= 0.0:
		return false
	if not _pay(air_dash_heat if cost < 0.0 else cost):
		return false
	burst_fired.emit()
	return true


func _recover() -> void:
	if overheated and heat <= recover_heat:
		overheated = false


## An air jump. Returns the upward speed to set, or zero if the rig has no
## burst, is overheated or is too close under its ceiling (`cap`, from
## `lift_cap`: the speed is cut so the jump tops out on the ceiling).
func try_burst(cap := INF) -> float:
	if not working() or overheated or burst_velocity <= 0.0 or (launch_once and launched) or indoor_factor() <= 0.0:
		return 0.0
	if minf(cap, burst_velocity) < MIN_LIFT or not (_spend(burst_heat) if launch_once else _pay(burst_heat)):
		return 0.0
	launched = true
	burst_fired.emit()
	return minf(burst_velocity, cap)


## A wing pulse while gliding. Returns the upward speed to set, or zero;
## `cap` limits it under the ceiling like a burst.
func try_pulse(cap := INF) -> float:
	if not working() or overheated or pulse_velocity <= 0.0 or minf(cap, pulse_velocity) < MIN_LIFT:
		return 0.0
	if not _spend(pulse_heat):
		return 0.0
	burst_fired.emit()
	return minf(pulse_velocity, cap)


## Takes `cost` heat if it fits under the limit, with a little slack
## (`BURST_SLACK` of the limit) so the last burst of a set can go off and
## overheat the rig. One that would go further is refused.
func _spend(cost: float) -> bool:
	if heat + cost > max_heat * (1.0 + BURST_SLACK):
		return false
	_since_thrust = 0.0
	heat += _heat(cost)
	if heat >= max_heat:
		heat = max_heat
		overheated = true
	return true


## True if a rig is worn and not shut off (`jam`).
func working() -> bool:
	return enabled and jam_left <= 0.0


## Shuts the rig off for `seconds` (an artifact's Static Bloom): whatever it
## was doing stops, and you drop.
func jam(seconds: float) -> void:
	if not enabled:
		return
	jam_left = maxf(jam_left, seconds)
	is_thrusting = false
	is_hovering = false
	is_boosting = false
	is_gliding = false
	is_skimming = false


## Overheats the rig at once (an Overclock Core burning out).
func lock_up() -> void:
	if not enabled:
		return
	heat = max_heat
	overheated = true
	is_hovering = false
	is_boosting = false
	is_skimming = false


## Heat that `amount` really adds: none while overclocked.
func _heat(amount: float) -> float:
	return 0.0 if heat_free else amount


## True if the rig can hold you up and fly you about (it has thrust).
func can_hover() -> bool:
	return working() and thrust_accel > 0.0


## True if the wings can spread: worn, working, with glide stamina left
## and no roof overhead that stops them.
func can_glide() -> bool:
	return working() and glide_fall_speed > 0.0 and not overheated and indoor_factor() > 0.0


## What the jump key does with this rig, for the HUD.
func controls_hint() -> String:
	if not enabled:
		return "Space jump"
	var parts: Array[String] = ["Space jump"]
	if thrust_accel > 0.0:
		parts.append("hold to climb, hold right mouse in the air to hover (C coasts down to cool%s)"
				% (", Shift in the air to boost" if boost_speed > 0.0 else ""))
	if burst_velocity > 0.0:
		parts.append(("press again in the air to launch" if launch_once else "press again in the air to kick")
				+ (" the way you move" if burst_push > 0.0 else ""))
	if can_skim():
		parts.append("hold in the air to skim a moment (C sinks)")
	if can_glide():
		parts.append("hold while falling to glide (look to steer, W dives, S climbs, Shift boosts%s)"
				% (", press again to pulse up" if pulse_velocity > 0.0 else ""))
	if air_dash_speed > 0.0:
		parts.append("Shift + a move key dashes that way in the air%s" % (" (gliding, Shift boosts ahead and Shift + S climbs)" if can_glide() else ""))
	return ", ".join(parts)


## How much of a full climb the ceiling still allows, 0 to 1: 1 well under
## it, easing to 0 over the last `CEILING_EASE` meters.
func climb_room() -> float:
	if ceiling <= 0.0 or not altitude_known:
		return 1.0
	return clampf((ceiling - altitude) / CEILING_EASE, 0.0, 1.0)


## The most upward speed a kick, pulse or launch may give so that, under
## `gravity`, it tops out on the ceiling (INF with no ceiling).
func lift_cap(gravity: float) -> float:
	if ceiling <= 0.0 or not altitude_known:
		return INF
	return sqrt(2.0 * gravity * maxf(0.0, ceiling - altitude))


## True once the rig can lift you no higher.
func at_ceiling() -> bool:
	return climb_room() <= 0.0


func heat_fraction() -> float:
	return heat / max_heat
