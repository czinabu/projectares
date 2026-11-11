class_name FlightRig
extends Node
## Thruster flight limited by heat. This base class is a jetpack; glide wings
## and thruster boots will subclass it and override `tick`.

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

var heat := 0.0
var overheated := false
var is_thrusting := false
var _since_thrust := 0.0


## Advances the rig one tick and returns the upward acceleration it provides.
func tick(wants_thrust: bool, delta: float) -> float:
	is_thrusting = enabled and wants_thrust and not overheated
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


func heat_fraction() -> float:
	return heat / max_heat
