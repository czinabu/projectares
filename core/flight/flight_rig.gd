class_name FlightRig
extends Node
## Flight limited by heat. One class covers every rig; the item's stats decide
## how it flies:
##   jetpack        - `thrust_accel`: hold jump in the air for sustained lift,
##                    tap jump in the air to hover and fly freely (see below).
##   thruster boots - `burst_velocity`: press jump in the air for an instant kick.
##   glide wings    - a burst to launch, then `glide_fall_speed` and
##                    `glide_speed`: hold jump to fall slowly and fly forward.

## An air jump went off. Cosmetic: the model fires its nozzles for a moment.
signal burst_fired

var item_id := ""
var display_name := "No rig"
## False until a rig item is equipped.
var enabled := false

var thrust_accel := 36.0
var max_rise_speed := 9.0
var max_heat := 100.0
var heat_per_sec := 34.0
var cool_per_sec := 26.0
var cool_delay := 0.5
## After overheating, thrust stays locked until heat falls below this.
var recover_heat := 35.0
## Upward speed from pressing jump in the air, and the heat each press costs.
var burst_velocity := 0.0
var burst_heat := 0.0
## While holding jump and falling: the fastest you sink, and how fast you fly.
## Zero means the rig cannot glide.
var glide_fall_speed := 0.0
var glide_speed := 0.0
var glide_accel := 22.0

## Jet flight, for rigs with thrust. Tapping jump in the air lights the jets
## and keeps them lit: the rig holds you up, the move keys fly you about at
## `fly_speed`, jump climbs and the descend key (held slide) sinks you at
## `descend_speed`. Sprinting forward is a boost: you fly head first at
## `boost_speed` wherever you look, up and down included. Hovering costs a
## share of the full heat rate; climbing and boosting cost all of it. Landing or
## overheating puts the jets out.
var fly_speed := 10.0
var fly_accel := 20.0
var boost_speed := 22.0
var boost_accel := 16.0
var descend_speed := 7.0
## How fast the jets bring your climb or sink to what you ask for, in m/s².
var hover_accel := 30.0
var hover_heat_mult := 0.25
var boost_heat_mult := 1.0
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
## Sideways speed an air jump adds along the move keys (thruster boots).
var burst_push := 0.0

var heat := 0.0
var overheated := false
var is_thrusting := false
var is_gliding := false
## The jets are lit and holding you up (see `fly_speed`).
var is_hovering := false
## Flying head first at boost speed.
var is_boosting := false
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
	if _since_thrust >= cool_delay:
		heat = maxf(0.0, heat - cool_per_sec * delta)
	if overheated and heat <= recover_heat:
		overheated = false
	return 0.0


## An air jump. Returns the upward speed to set, or zero if the rig has no
## burst or is overheated.
func try_burst() -> float:
	if not enabled or overheated or burst_velocity <= 0.0:
		return 0.0
	_since_thrust = 0.0
	heat += burst_heat
	if heat >= max_heat:
		heat = max_heat
		overheated = true
	burst_fired.emit()
	return burst_velocity


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
		parts.append("hold to climb, tap in the air to hover (C sinks, Shift+W boosts, Z/X roll)")
	if burst_velocity > 0.0:
		parts.append("press again in the air to boost" + (" the way you move" if burst_push > 0.0 else ""))
	if can_glide():
		parts.append("hold while falling to glide (steer to bank, look down to dive, up to climb, Z/X roll)")
	return ", ".join(parts)


func heat_fraction() -> float:
	return heat / max_heat
