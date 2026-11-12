class_name FlightRig
extends Node
## Flight limited by heat. One class covers every rig; the item's stats decide
## how it flies:
##   jetpack        - `thrust_accel`: hold jump in the air for sustained lift.
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

var heat := 0.0
var overheated := false
var is_thrusting := false
var is_gliding := false
var _since_thrust := 0.0


## Advances the rig one tick and returns the upward acceleration it provides.
func tick(wants_thrust: bool, delta: float) -> float:
	is_thrusting = enabled and wants_thrust and not overheated and thrust_accel > 0.0
	if is_thrusting:
		_since_thrust = 0.0
		heat += heat_per_sec * delta
		if heat >= max_heat:
			heat = max_heat
			overheated = true
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


func can_glide() -> bool:
	return enabled and glide_fall_speed > 0.0


## What the jump key does with this rig, for the HUD.
func controls_hint() -> String:
	if not enabled:
		return "Space jump"
	var parts: Array[String] = ["Space jump"]
	if thrust_accel > 0.0:
		parts.append("hold to fly")
	if burst_velocity > 0.0:
		parts.append("press again in the air to boost")
	if can_glide():
		parts.append("hold while falling to glide")
	return ", ".join(parts)


func heat_fraction() -> float:
	return heat / max_heat
