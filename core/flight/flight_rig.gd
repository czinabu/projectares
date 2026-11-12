class_name FlightRig
extends Node
## Flight limited by heat. One class covers every rig; the item's stats decide
## how it flies:
##   jetpack        - `thrust_accel`: hold jump in the air for sustained lift,
##                    tap jump in the air to hover and fly freely (see below).
##   thruster boots - `burst_velocity`: press jump in the air for an instant kick,
##                    and `skim_speed`: hold jump in the air to skim low.
##   glide wings    - a burst to launch, then `glide_fall_speed` and
##                    `glide_speed`: hold jump to fall slowly and fly forward,
##                    and `pulse_velocity`: press jump while gliding to climb.
##
## Every rig cruises at the same speed (`CRUISE_SPEED`) so a squad on mixed
## rigs keeps together; each stays up its own way. A jetpack cruises in
## swoops, coasting down with the jets idle to cool; wings glide for free and
## pulse to hold height; boots skim low. Flown its own way a rig stays up for
## minutes, flown against type it overheats in seconds.

## An air jump went off. Cosmetic: the model fires its nozzles for a moment.
signal burst_fired

## The level flying speed every rig shares (m/s). Bursts go faster but cost
## heat or height.
const CRUISE_SPEED := 15.0
## How far past `max_heat` a burst or pulse may land (it then overheats).
const BURST_SLACK := 0.05

var item_id := ""
var display_name := "No rig"
## False until a rig item is equipped.
var enabled := false

## The defaults are the free Mk1 jetpack; other rigs set what differs.
var thrust_accel := 36.0
var max_rise_speed := 9.0
var max_heat := 100.0
var heat_per_sec := 32.5
var cool_per_sec := 26.0
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

## Jet flight, for rigs with thrust. Tapping jump in the air lights the jets
## and keeps them lit: the rig holds you up, the move keys cruise you about at
## `fly_speed`, jump climbs and the descend key (held slide) coasts: the jets
## idle, you sink at `descend_speed` keeping your speed, and the rig cools at
## `coast_cool` a second. Sprinting forward is a boost: you fly head first at
## `boost_speed` along the view's heading, climbing or sinking only on jump
## and descend (0: no boost). The keys fly every rig; the mouse only looks.
## Holding still costs `hover_heat_mult` of the full heat rate, cruising
## `cruise_heat_mult`, climbing all of it and boosting `boost_heat_mult`.
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
var hover_heat_mult := 0.4
var cruise_heat_mult := 0.24
var boost_heat_mult := 1.4
var coast_cool := 30.0
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
## Below the stall speed a glide sinks this fast (0: just the glide sink).
var stall_sink := 0.0
## Wings: a press of a roll key while gliding snaps a sidestep this fast for
## `roll_dodge_time`, then waits `roll_cooldown` (0: no dodge).
var roll_dodge_speed := 0.0
var roll_dodge_time := 0.25
var roll_cooldown := 2.0
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
## you let go of the move keys (`skim_accel`).
var skim_speed := 0.0
var skim_accel := 40.0
var skim_hold_accel := 30.0
var skim_low := 4.0
var skim_high := 10.0
var skim_cool := 5.0
var skim_mid_heat := 8.0
var skim_high_heat := 30.0
## How far down the boots look for a surface.
var skim_probe := 30.0
## Boots: the dash key in the air dashes at `air_dash_speed` for
## `air_dash_time` for `air_dash_heat`, instead of spending stamina.
var air_dash_speed := 0.0
var air_dash_time := 0.3
var air_dash_heat := 0.0

var heat := 0.0
var overheated := false
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
## The launch of a `launch_once` rig has been used this time in the air.
var launched := false
var _since_thrust := 0.0


## Advances the rig one tick and returns the upward acceleration it provides.
## `heat_mult` scales the heat this tick costs (hovering costs less).
func tick(wants_thrust: bool, delta: float, heat_mult := 1.0) -> float:
	is_thrusting = enabled and wants_thrust and not overheated and thrust_accel > 0.0
	if is_thrusting:
		_since_thrust = 0.0
		heat += heat_per_sec * heat_mult * delta
		if heat >= max_heat:
			heat = max_heat
			overheated = true
			is_hovering = false
			is_boosting = false
		return thrust_accel
	_since_thrust += delta
	if is_gliding and glide_cool > 0.0:
		heat = maxf(0.0, heat - glide_cool * delta)
	elif _since_thrust >= cool_delay:
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
	if height < skim_low:
		heat = maxf(0.0, heat - skim_cool * delta)
		_recover()
		return
	_since_thrust = 0.0
	heat += (skim_mid_heat if height < skim_high else skim_high_heat) * delta
	if heat >= max_heat:
		heat = max_heat
		overheated = true
		is_skimming = false


## Which band a skim is in: 0 cool (low), 1 warm, 2 burning.
func skim_band() -> int:
	return 0 if skim_height < skim_low else (1 if skim_height < skim_high else 2)


func can_skim() -> bool:
	return enabled and skim_speed > 0.0


## A boot dash in the air. True if it goes off (and takes its heat).
func try_air_dash() -> bool:
	if not enabled or overheated or air_dash_speed <= 0.0:
		return false
	if not _spend(air_dash_heat):
		return false
	burst_fired.emit()
	return true


func _recover() -> void:
	if overheated and heat <= recover_heat:
		overheated = false


## An air jump. Returns the upward speed to set, or zero if the rig has no
## burst or is overheated.
func try_burst() -> float:
	if not enabled or overheated or burst_velocity <= 0.0 or (launch_once and launched):
		return 0.0
	if not _spend(burst_heat):
		return 0.0
	launched = true
	burst_fired.emit()
	return burst_velocity


## A wing pulse while gliding. Returns the upward speed to set, or zero.
func try_pulse() -> float:
	if not enabled or overheated or pulse_velocity <= 0.0 or not _spend(pulse_heat):
		return 0.0
	burst_fired.emit()
	return pulse_velocity


## Takes `cost` heat if it fits under the limit, with a little slack
## (`BURST_SLACK` of the limit) so the last burst of a set can go off and
## overheat the rig. One that would go further is refused.
func _spend(cost: float) -> bool:
	if heat + cost > max_heat * (1.0 + BURST_SLACK):
		return false
	_since_thrust = 0.0
	heat += cost
	if heat >= max_heat:
		heat = max_heat
		overheated = true
	return true


## True if the rig can hold you up and fly you about (it has thrust).
func can_hover() -> bool:
	return enabled and thrust_accel > 0.0


func can_glide() -> bool:
	return enabled and glide_fall_speed > 0.0


## What the jump key does with this rig, for the HUD.
func controls_hint() -> String:
	if not enabled:
		return "Space jump"
	var parts: Array[String] = ["Space jump"]
	if thrust_accel > 0.0:
		parts.append("hold to climb, tap in the air to hover (C coasts down to cool%s, Q/E roll)"
				% (", Shift+W boosts" if boost_speed > 0.0 else ""))
	if burst_velocity > 0.0:
		parts.append("press again in the air to boost" + (" the way you move" if burst_push > 0.0 else ""))
	if can_skim():
		parts.append("hold in the air to skim low (stay near a surface to cool, C sinks, Ctrl dashes)")
	if can_glide():
		parts.append("hold while falling to glide (steer to bank, look down to dive, up to climb, %sQ/E %s)"
				% ["press again to pulse up, " if pulse_velocity > 0.0 else "",
				"barrel roll" if roll_dodge_speed > 0.0 else "roll"])
	return ", ".join(parts)


func heat_fraction() -> float:
	return heat / max_heat
