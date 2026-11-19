class_name PlanetTypes
extends RefCounted
## The planet types (DESIGN.md "Planet kit"). Each is a recipe, never a map:
## a world picks one by id and lays its own places on it. A new type is a
## new function here and an entry in `ids()`.


static func ids() -> Array[String]:
	return ["ashland", "glacier", "saltflat", "basalt", "dunes", "marsh"]


static func get_type(id: String) -> PlanetType:
	match id:
		"ashland": return ashland()
		"glacier": return glacier()
		"saltflat": return saltflat()
		"basalt": return basalt()
		"dunes": return dunes()
		"marsh": return marsh()
	return null


## Burnt plains under smoke: rolling ground, craters, ash drifts, embers in
## the air and ash storms. The war planet.
static func ashland() -> PlanetType:
	var t := PlanetType.new()
	t.id = "ashland"
	t.display_name = "Ashland"
	t.blurb = "Burnt plains under a smoke ceiling, lit by fires and a dull sun."
	t.sky = {
		"zenith_color": Color(0.32, 0.17, 0.13), "horizon_color": Color(0.78, 0.42, 0.28),
		"horizon_fall": 2.5, "sun_disc": 0.035, "sun_glow": 0.55, "sun_glow_width": 4.0,
		"cloud_cover": 0.62, "cloud_scale": 0.3, "cloud_color": Color(0.55, 0.32, 0.24),
		"cloud_shade": Color(0.17, 0.1, 0.08),
		"body2_dir": Vector3(-0.6, 0.32, -0.7), "body2_size": 0.035, "body2_color": Color(0.85, 0.55, 0.4),
		"body_daylight": 0.35,
	}
	# Ash-grey air and a neutral light, so the red lives in the sky's glow,
	# the fires and the cracks and they stand out (Caleb's look pass, after
	# his references: grey smoke with hot lights burning through it).
	t.calm = {
		"sky_tint": Color(0.75, 0.6, 0.55), "sky_energy": 0.95, "sky_saturation": 0.85,
		"fog_color": Color(0.3, 0.28, 0.27), "fog_density": 0.7,
		"fog_depth_begin": 70.0, "fog_depth_end": 900.0, "fog_depth_curve": 1.3,
		"fog_height": 2.0, "fog_height_density": 0.04, "haze_height": 0.18,
		"sun_color": Color(0.95, 0.75, 0.62), "sun_energy": 1.7, "sun_angles": Vector3(-20, 38, 0),
		"ambient_color": Color(0.5, 0.5, 0.52), "ambient_energy": 1.4,
		"exposure": 1.25, "saturation": 0.65, "contrast": 1.15, "glow": 0.9,
	}
	t.storm = {
		"sky_tint": Color(0.6, 0.5, 0.45), "sky_energy": 0.45, "fog_color": Color(0.32, 0.3, 0.28),
		"fog_density": 0.985, "fog_depth_begin": 4.0, "fog_depth_end": 55.0, "fog_depth_curve": 0.8,
		"haze_height": 0.9, "sun_color": Color(0.95, 0.7, 0.55), "sun_energy": 0.5,
		"ambient_color": Color(0.52, 0.5, 0.5), "ambient_energy": 1.6,
		"exposure": 1.3, "saturation": 0.6, "contrast": 1.05, "glow": 0.9,
	}
	t.smoke = {"density": 0.012, "colour": Color(0.45, 0.44, 0.44), "depth": 18.0, "war": 0.6, "storm": 1.5}
	t.terrain = {
		"base_amp": 9.0, "base_freq": 0.006, "octaves": 4, "warp": 25.0,
		"ridge_amp": 26.0, "ridge_freq": 0.005, "ridge_cover": 0.18,
		"field": 280.0, "field_calm": 0.8, "rim": 34.0, "rim_ramp": 140.0,
		"craters": 70, "crater_radius": Vector2(4.0, 16.0), "crater_depth": 2.5,
	}
	t.surfaces = {"base": "Ground031", "rock": "Rock051", "cap": "Ground110", "patch": "Ground110"}
	t.ground = {
		"base_a": Color(0.3, 0.25, 0.22), "base_b": Color(0.2, 0.17, 0.15), "base_rough": 0.95,
		"rock_a": Color(0.3, 0.26, 0.24), "rock_b": Color(0.16, 0.13, 0.12), "rock_rough": 0.85,
		"slope_range": Vector2(0.86, 0.7), "strata_every": 1.6, "strata": 0.4,
		"patch_a": Color(0.4, 0.37, 0.35), "patch_b": Color(0.34, 0.31, 0.3), "patch_amount": 0.42,
		"patch_edge": 0.3, "cracks": 0.6, "crack_glow": Color(1.0, 0.35, 0.08), "crack_energy": 0.9,
		"detail_scale": 0.3, "saturation": 0.95,
	}
	t.horizon = {"reach": 2600.0, "peaks": 140.0}
	t.weather = {"air": "embers", "storm": "ash"}
	t.props = [
		{"kind": "boulder", "per_ha": 6.0, "size": Vector2(0.6, 2.4), "max_slope": 0.6},
		{"kind": "slab", "per_ha": 1.5, "size": Vector2(2.5, 6.0), "max_slope": 0.4},
		{"kind": "spire", "per_ha": 0.25, "size": Vector2(7.0, 16.0), "max_slope": 0.3, "out": 0.6},
	]
	t.rules = {"cold": 0.0, "surface_grip": 1.0, "shot_carry": 1.0}
	return t


## A glacier valley: snow on the floor, blue ice in the hollows, dark rock
## banded on the walls, a low bright sun, and whiteouts.
static func glacier() -> PlanetType:
	var t := PlanetType.new()
	t.id = "glacier"
	t.display_name = "Glacier"
	t.blurb = "Snowfields and blue ice between dark ridges, under a low sun that never warms."
	t.sky = {
		"zenith_color": Color(0.16, 0.3, 0.62), "horizon_color": Color(0.78, 0.86, 0.96),
		"horizon_fall": 3.5, "sun_disc": 0.028, "sun_glow": 0.7, "sun_glow_width": 5.0,
		"cloud_cover": 0.32, "cloud_scale": 0.45, "cloud_color": Color(1.0, 0.98, 0.96),
		"cloud_shade": Color(0.62, 0.68, 0.8),
		"body2_dir": Vector3(0.55, 0.42, -0.72), "body2_size": 0.05, "body2_color": Color(0.82, 0.85, 0.92),
		"body_daylight": 0.55,
	}
	t.calm = {
		"sky_tint": Color(1.0, 1.0, 1.0), "sky_energy": 1.0, "sky_saturation": 0.9,
		"fog_color": Color(0.66, 0.75, 0.88), "fog_density": 0.55,
		"fog_depth_begin": 120.0, "fog_depth_end": 1800.0, "fog_depth_curve": 1.5,
		"haze_height": 0.14,
		"sun_color": Color(1.0, 0.88, 0.72), "sun_energy": 1.9, "sun_angles": Vector3(-12, -35, 0),
		"ambient_color": Color(0.45, 0.56, 0.78), "ambient_energy": 0.8,
		"exposure": 1.0, "saturation": 0.92, "contrast": 1.12, "glow": 0.6,
	}
	t.storm = {
		"sky_tint": Color(0.9, 0.93, 0.98), "sky_energy": 0.9, "sky_saturation": 0.2,
		"fog_color": Color(0.8, 0.85, 0.92), "fog_density": 0.985,
		"fog_depth_begin": 4.0, "fog_depth_end": 55.0, "fog_depth_curve": 0.8, "haze_height": 1.0,
		"sun_color": Color(0.9, 0.93, 1.0), "sun_energy": 0.45,
		"ambient_color": Color(0.7, 0.76, 0.86), "ambient_energy": 1.3,
		"saturation": 0.6, "contrast": 0.95,
	}
	t.terrain = {
		"base_amp": 10.0, "base_freq": 0.006, "octaves": 5, "warp": 40.0,
		"ridge_amp": 70.0, "ridge_freq": 0.0045, "ridge_cover": 0.4,
		"field": 220.0, "field_calm": 0.6, "rim": 30.0, "rim_ramp": 140.0,
		"floor": -4.0, "floor_soft": 3.0,
	}
	t.surfaces = {"base": "Snow008A", "rock": "Rock060", "cap": "Snow008C", "patch": "Ice001"}
	t.ground = {
		"base_a": Color(0.88, 0.91, 0.96), "base_b": Color(0.78, 0.83, 0.92), "base_rough": 0.75,
		"rock_a": Color(0.22, 0.24, 0.29), "rock_b": Color(0.12, 0.13, 0.16), "rock_rough": 0.7,
		"slope_range": Vector2(0.8, 0.66), "strata_every": 4.0, "strata": 0.55,
		"cap_color": Color(0.94, 0.96, 1.0), "cap_range": Vector2(30.0, 45.0), "cap_on_slopes": 0.12,
		"patch_a": Color(0.36, 0.56, 0.74), "patch_b": Color(0.5, 0.7, 0.84), "patch_amount": 0.7,
		"patch_edge": 0.04, "patch_low": 1.0, "patch_low_at": -3.0, "patch_wet": 0.75,
		"sparkle": 0.9, "detail_scale": 0.3, "saturation": 1.0,
	}
	t.horizon = {"reach": 3000.0, "peaks": 320.0}
	t.weather = {"air": "snow", "storm": "snow"}
	t.props = [
		{"kind": "boulder", "per_ha": 3.0, "size": Vector2(0.8, 3.0), "max_slope": 0.6},
		{"kind": "shard", "per_ha": 1.2, "size": Vector2(1.5, 5.0), "max_slope": 0.35, "low": -1.0},
	]
	t.rules = {"cold": 1.2, "surface_grip": 0.55, "shot_carry": 1.3}
	return t


## A dry lake bed of salt crust to the horizon, red mesas, a sun stuck on
## the horizon and a ringed giant in the sky. The race planet.
static func saltflat() -> PlanetType:
	var t := PlanetType.new()
	t.id = "saltflat"
	t.display_name = "Salt Flat"
	t.blurb = "A cracked white pan to the horizon, red mesas, and a ringed giant over an endless dusk."
	t.sky = {
		"zenith_color": Color(0.18, 0.16, 0.36), "horizon_color": Color(1.0, 0.58, 0.38),
		"horizon_fall": 2.2, "sun_disc": 0.04, "sun_glow": 0.9, "sun_glow_width": 3.0,
		"cloud_cover": 0.22, "cloud_scale": 0.25, "cloud_color": Color(1.0, 0.68, 0.5),
		"cloud_shade": Color(0.42, 0.3, 0.42),
		"body1_dir": Vector3(0.75, 0.3, 0.55), "body1_size": 0.2,
		"body1_color": Color(0.85, 0.72, 0.6), "body1_band": Color(0.62, 0.42, 0.34), "body1_bands": 7.0,
		"body1_ring_axis": Vector3(0.25, 1.0, -0.18), "body1_ring": Vector2(1.35, 2.3),
		"body1_ring_color": Color(0.92, 0.84, 0.74), "body1_glow": Color(1.0, 0.7, 0.5),
		"body_daylight": 0.85, "stars": 0.4,
	}
	t.calm = {
		"sky_tint": Color(1.0, 1.0, 1.0), "sky_energy": 1.0, "sky_saturation": 1.0,
		"fog_color": Color(0.7, 0.48, 0.42), "fog_density": 0.55,
		"fog_depth_begin": 150.0, "fog_depth_end": 2400.0, "fog_depth_curve": 1.4, "haze_height": 0.12,
		"sun_scatter": 0.5, "sun_color": Color(1.0, 0.6, 0.38), "sun_energy": 2.2, "sun_angles": Vector3(-7, -58, 0),
		"ambient_color": Color(0.62, 0.52, 0.52), "ambient_energy": 1.1,
		"exposure": 1.0, "saturation": 0.98, "contrast": 1.1, "glow": 0.9,
	}
	t.storm = {
		"sky_tint": Color(0.95, 0.75, 0.62), "sky_energy": 0.7, "sky_saturation": 0.5,
		"fog_color": Color(0.74, 0.55, 0.45), "fog_density": 0.9,
		"fog_depth_begin": 10.0, "fog_depth_end": 140.0, "fog_depth_curve": 0.9, "haze_height": 0.7,
		"sun_color": Color(1.0, 0.65, 0.45), "sun_energy": 1.0,
		"ambient_color": Color(0.62, 0.5, 0.5), "ambient_energy": 1.6, "saturation": 0.75, "contrast": 1.0,
	}
	t.terrain = {
		"base_amp": 1.2, "base_freq": 0.004, "octaves": 3,
		"ridge_amp": 70.0, "ridge_freq": 0.003, "ridge_cover": 0.05,
		"terrace": 9.0, "terrace_sharp": 0.85,
		"field": 380.0, "field_calm": 0.25, "rim": 10.0, "rim_ramp": 400.0,
		"floor": 0.0, "floor_soft": 1.5,
	}
	t.surfaces = {"base": "Ground031", "rock": "Rock051", "cap": "Ground079L", "patch": "Ground079L"}
	t.ground = {
		"base_a": Color(0.95, 0.92, 0.86), "base_b": Color(0.88, 0.84, 0.78), "base_rough": 0.6,
		"rock_a": Color(0.62, 0.3, 0.2), "rock_b": Color(0.42, 0.2, 0.14), "rock_rough": 0.85,
		"slope_range": Vector2(0.9, 0.75), "strata_every": 1.3, "strata": 0.7,
		"cap_color": Color(0.7, 0.42, 0.3), "cap_range": Vector2(6.0, 8.0), "cap_on_slopes": 0.0,
		"patch_a": Color(0.8, 0.72, 0.62), "patch_b": Color(0.74, 0.66, 0.58), "patch_amount": 0.25,
		"patch_wet": 0.55, "cracks": 1.0, "sparkle": 0.5, "detail_scale": 0.25, "saturation": 1.0,
	}
	t.horizon = {"reach": 3200.0, "peaks": 110.0}
	t.weather = {"air": "", "storm": "sand"}
	t.props = [
		{"kind": "spire", "per_ha": 0.14, "size": Vector2(14.0, 40.0), "max_slope": 0.3, "out": 0.45},
		{"kind": "slab", "per_ha": 0.6, "size": Vector2(2.0, 4.0), "max_slope": 0.4},
	]
	t.rules = {"cold": 0.0, "surface_grip": 0.9, "shot_carry": 1.15}
	return t


## A volcanic rift: black basalt, rivers and cracks of lava in the low
## ground, a night sky of smoke and two moons, and falling ash.
static func basalt() -> PlanetType:
	var t := PlanetType.new()
	t.id = "basalt"
	t.display_name = "Basalt Rift"
	t.blurb = "Black basalt split by lava, lit from below, under smoke and two moons."
	t.sky = {
		"zenith_color": Color(0.03, 0.025, 0.05), "horizon_color": Color(0.38, 0.12, 0.08),
		"horizon_fall": 4.0, "sun_disc": 0.02, "sun_glow": 0.25, "sun_glow_width": 6.0,
		"cloud_cover": 0.55, "cloud_scale": 0.3, "cloud_color": Color(0.32, 0.12, 0.08),
		"cloud_shade": Color(0.05, 0.03, 0.03),
		"body1_dir": Vector3(-0.4, 0.45, -0.8), "body1_size": 0.09,
		"body1_color": Color(0.55, 0.62, 0.72), "body1_band": Color(0.4, 0.45, 0.55), "body1_bands": 3.0,
		"body1_glow": Color(0.5, 0.6, 0.9),
		"body2_dir": Vector3(0.3, 0.6, -0.75), "body2_size": 0.03, "body2_color": Color(0.85, 0.75, 0.65),
		"body_daylight": 1.0, "stars": 1.0,
	}
	t.calm = {
		"sky_tint": Color(1.0, 1.0, 1.0), "sky_energy": 1.0, "sky_saturation": 1.0,
		"fog_color": Color(0.16, 0.06, 0.05), "fog_density": 0.75,
		"fog_depth_begin": 60.0, "fog_depth_end": 1100.0, "fog_depth_curve": 1.2,
		"fog_height": 1.5, "fog_height_density": 0.06, "haze_height": 0.12,
		"sun_color": Color(0.6, 0.66, 0.85), "sun_energy": 0.9, "sun_angles": Vector3(-30, 170, 0),
		"ambient_color": Color(0.62, 0.36, 0.3), "ambient_energy": 1.5,
		"exposure": 1.8, "saturation": 1.0, "contrast": 1.15, "glow": 1.2,
	}
	t.storm = {
		"sky_tint": Color(0.8, 0.5, 0.4), "sky_energy": 0.6, "fog_color": Color(0.2, 0.08, 0.06),
		"fog_density": 0.95, "fog_depth_begin": 6.0, "fog_depth_end": 70.0, "fog_depth_curve": 0.9,
		"haze_height": 0.9, "sun_energy": 0.2, "ambient_color": Color(0.5, 0.26, 0.2), "ambient_energy": 1.1,
		"saturation": 0.85, "contrast": 1.05, "glow": 1.3,
	}
	t.terrain = {
		"base_amp": 9.0, "base_freq": 0.007, "octaves": 5, "warp": 35.0,
		"ridge_amp": 34.0, "ridge_freq": 0.006, "ridge_cover": 0.35,
		"terrace": 2.2, "terrace_sharp": 0.45,
		"field": 260.0, "field_calm": 0.7, "rim": 40.0, "rim_ramp": 120.0,
		"floor": -5.0, "floor_soft": 1.0,
	}
	t.surfaces = {"base": "Ground110", "rock": "Rock051", "cap": "Ground110", "patch": ""}
	t.ground = {
		"base_a": Color(0.16, 0.15, 0.16), "base_b": Color(0.09, 0.085, 0.09), "base_rough": 0.75,
		"rock_a": Color(0.12, 0.11, 0.115), "rock_b": Color(0.06, 0.055, 0.06), "rock_rough": 0.6,
		"slope_range": Vector2(0.85, 0.7), "strata_every": 0.9, "strata": 0.5,
		"cap_color": Color(0.32, 0.3, 0.3), "cap_range": Vector2(22.0, 34.0), "cap_on_slopes": 0.3,
		"patch_a": Color(0.25, 0.06, 0.02), "patch_b": Color(0.6, 0.18, 0.04), "patch_amount": 0.75,
		"patch_edge": 0.03, "patch_low": 1.0, "patch_low_at": -4.2, "patch_rough": 0.4,
		"cracks": 1.0, "crack_glow": Color(1.0, 0.33, 0.06), "crack_energy": 5.0,
		"detail_scale": 0.35, "saturation": 1.0,
	}
	t.horizon = {"reach": 2600.0, "peaks": 260.0}
	t.weather = {"air": "ash", "storm": "ash"}
	t.props = [
		{"kind": "spire", "per_ha": 0.5, "size": Vector2(4.0, 12.0), "max_slope": 0.4},
		{"kind": "boulder", "per_ha": 4.0, "size": Vector2(0.6, 2.2), "max_slope": 0.6},
	]
	t.rules = {"cold": 0.0, "surface_grip": 1.0, "shot_carry": 0.9}
	return t


## A sea of dunes and wind-cut sandstone under a white-hot sky and a ringed
## giant. Sandstorms.
static func dunes() -> PlanetType:
	var t := PlanetType.new()
	t.id = "dunes"
	t.display_name = "Dune Sea"
	t.blurb = "Wind-built dunes round sandstone buttes, a white-hot sky and a giant hanging over it."
	t.sky = {
		"zenith_color": Color(0.3, 0.48, 0.72), "horizon_color": Color(0.95, 0.88, 0.76),
		"horizon_fall": 2.6, "sun_disc": 0.03, "sun_glow": 0.8, "sun_glow_width": 3.5,
		"cloud_cover": 0.12, "cloud_scale": 0.5, "cloud_color": Color(1.0, 0.97, 0.92),
		"cloud_shade": Color(0.8, 0.75, 0.7),
		"body1_dir": Vector3(-0.5, 0.42, -0.75), "body1_size": 0.26,
		"body1_color": Color(0.7, 0.78, 0.86), "body1_band": Color(0.55, 0.6, 0.75), "body1_bands": 9.0,
		"body1_ring_axis": Vector3(-0.35, 1.0, 0.2), "body1_ring": Vector2(1.3, 2.1),
		"body1_ring_color": Color(0.95, 0.92, 0.88), "body1_glow": Color(0.6, 0.75, 1.0),
		"body_daylight": 0.5,
	}
	t.calm = {
		"sky_tint": Color(1.0, 1.0, 1.0), "sky_energy": 1.0, "sky_saturation": 1.0,
		"fog_color": Color(0.88, 0.78, 0.64), "fog_density": 0.6,
		"fog_depth_begin": 140.0, "fog_depth_end": 2200.0, "fog_depth_curve": 1.4, "haze_height": 0.15,
		"sun_scatter": 0.3, "sun_color": Color(1.0, 0.93, 0.8), "sun_energy": 2.6, "sun_angles": Vector3(-38, 120, 0),
		"ambient_color": Color(0.62, 0.62, 0.7), "ambient_energy": 1.1,
		"exposure": 0.95, "saturation": 1.0, "contrast": 1.1, "glow": 0.6,
	}
	t.storm = {
		"sky_tint": Color(1.0, 0.8, 0.6), "sky_energy": 0.7, "sky_saturation": 0.6,
		"fog_color": Color(0.72, 0.5, 0.3), "fog_density": 0.985,
		"fog_depth_begin": 4.0, "fog_depth_end": 55.0, "fog_depth_curve": 0.8, "haze_height": 0.9,
		"sun_color": Color(1.0, 0.75, 0.5), "sun_energy": 0.8,
		"ambient_color": Color(0.75, 0.55, 0.38), "ambient_energy": 1.4, "saturation": 0.8, "contrast": 1.0,
	}
	t.terrain = {
		"base_amp": 3.0, "base_freq": 0.004, "octaves": 3, "warp": 30.0,
		"dune_amp": 11.0, "dune_len": 70.0, "dune_dir": 25.0, "dune_cover": 0.8,
		"ridge_amp": 50.0, "ridge_freq": 0.004, "ridge_cover": 0.1,
		"terrace": 7.0, "terrace_sharp": 0.3,
		"field": 300.0, "field_calm": 0.9, "rim": 20.0, "rim_ramp": 200.0,
	}
	t.surfaces = {"base": "Ground098", "rock": "Rock051", "cap": "Ground079L", "patch": "Ground079L"}
	t.ground = {
		"base_a": Color(0.86, 0.66, 0.44), "base_b": Color(0.78, 0.56, 0.36), "base_rough": 0.95,
		"rock_a": Color(0.7, 0.42, 0.26), "rock_b": Color(0.52, 0.3, 0.2), "rock_rough": 0.9,
		"slope_range": Vector2(0.6, 0.45), "strata_every": 1.1, "strata": 0.6,
		"patch_a": Color(0.68, 0.48, 0.32), "patch_b": Color(0.74, 0.54, 0.36), "patch_amount": 0.2,
		"ripple_dir": Vector2(0.9, 0.42), "ripple_every": 0.5, "ripples": 1.0,
		"detail_scale": 0.4, "detail_strength": 0.5, "saturation": 1.0,
	}
	t.horizon = {"reach": 3000.0, "peaks": 90.0}
	t.weather = {"air": "", "storm": "sand"}
	t.props = [
		{"kind": "spire", "per_ha": 0.12, "size": Vector2(8.0, 22.0), "max_slope": 0.3, "out": 0.5},
		{"kind": "boulder", "per_ha": 0.8, "size": Vector2(0.8, 2.5), "max_slope": 0.5},
	]
	t.rules = {"cold": 0.0, "surface_grip": 0.75, "shot_carry": 1.0}
	return t


## A warm, drowned lowland: moss and black water, giant fungal stalks that
## glow under their caps, two moons through the mist, rain.
static func marsh() -> PlanetType:
	var t := PlanetType.new()
	t.id = "marsh"
	t.display_name = "Spore Marsh"
	t.blurb = "Moss and black water under fungal giants that glow at dusk; rain and drifting spores."
	t.sky = {
		"zenith_color": Color(0.03, 0.08, 0.09), "horizon_color": Color(0.26, 0.38, 0.32),
		"horizon_fall": 2.4, "sun_disc": 0.03, "sun_glow": 0.65, "sun_glow_width": 5.0,
		"cloud_cover": 0.62, "cloud_scale": 0.35, "cloud_color": Color(0.42, 0.52, 0.46),
		"cloud_shade": Color(0.1, 0.15, 0.15),
		"body1_dir": Vector3(0.6, 0.38, -0.7), "body1_size": 0.08, "body1_color": Color(0.85, 0.82, 0.7),
		"body1_band": Color(0.7, 0.66, 0.55), "body1_bands": 0.0, "body1_glow": Color(0.6, 0.9, 0.8),
		"body2_dir": Vector3(0.35, 0.55, -0.76), "body2_size": 0.035, "body2_color": Color(0.7, 0.85, 0.82),
		"body_daylight": 0.75, "stars": 0.3,
	}
	t.calm = {
		"sky_tint": Color(0.85, 0.95, 0.9), "sky_energy": 0.75, "sky_saturation": 1.0,
		"fog_color": Color(0.16, 0.25, 0.22), "fog_density": 0.86,
		"fog_depth_begin": 12.0, "fog_depth_end": 300.0, "fog_depth_curve": 0.9,
		"fog_height": 1.5, "fog_height_density": 0.3, "haze_height": 0.35,
		"sun_color": Color(1.0, 0.72, 0.5), "sun_energy": 1.0, "sun_angles": Vector3(-10, -60, 0),
		"ambient_color": Color(0.26, 0.4, 0.36), "ambient_energy": 1.15,
		"exposure": 1.15, "saturation": 0.95, "contrast": 1.15, "glow": 1.35,
	}
	t.storm = {
		"sky_tint": Color(0.6, 0.68, 0.68), "sky_energy": 0.6, "sky_saturation": 0.5,
		"fog_color": Color(0.32, 0.4, 0.4), "fog_density": 0.93,
		"fog_depth_begin": 8.0, "fog_depth_end": 90.0, "fog_depth_curve": 0.9, "haze_height": 0.8,
		"sun_energy": 0.35, "ambient_color": Color(0.4, 0.5, 0.5), "ambient_energy": 1.1,
		"saturation": 0.8, "contrast": 1.0, "glow": 1.1,
	}
	t.terrain = {
		"base_amp": 5.0, "base_freq": 0.008, "octaves": 4, "warp": 30.0,
		"ridge_amp": 30.0, "ridge_freq": 0.005, "ridge_cover": 0.2,
		"field": 260.0, "field_calm": 0.7, "rim": 25.0, "rim_ramp": 150.0,
		"floor": -1.5, "floor_soft": 0.8,
	}
	t.surfaces = {"base": "Grass007", "rock": "Rock060", "cap": "Ground037", "patch": ""}
	t.ground = {
		"base_a": Color(0.2, 0.26, 0.15), "base_b": Color(0.12, 0.16, 0.12), "base_rough": 0.9,
		"rock_a": Color(0.2, 0.2, 0.19), "rock_b": Color(0.1, 0.11, 0.1), "rock_rough": 0.55,
		"slope_range": Vector2(0.8, 0.62), "strata_every": 2.0, "strata": 0.3,
		"cap_color": Color(0.32, 0.42, 0.24), "cap_range": Vector2(20.0, 30.0), "cap_on_slopes": 0.6,
		"patch_a": Color(0.03, 0.05, 0.05), "patch_b": Color(0.05, 0.08, 0.07), "patch_amount": 0.75,
		"patch_edge": 0.03, "patch_low": 1.0, "patch_low_at": -0.6, "patch_wet": 1.0,
		"bank": 0.8, "bank_width": 0.14, "bank_color": Color(0.28, 0.4, 0.13), "photo_chroma": 0.75,
		"detail_scale": 0.4, "saturation": 1.0,
	}
	t.horizon = {"reach": 2400.0, "peaks": 150.0}
	t.weather = {"air": "spores", "storm": "rain"}
	t.props = [
		{"kind": "stalk", "per_ha": 3.5, "size": Vector2(8.0, 30.0), "max_slope": 0.35, "high": -0.5},
		{"kind": "boulder", "per_ha": 2.5, "size": Vector2(0.6, 2.0), "max_slope": 0.6},
		{"kind": "crystal", "per_ha": 0.8, "size": Vector2(0.6, 1.6), "max_slope": 0.5, "high": -0.8},
	]
	# Mist lying low over the black water, thicker in the rain.
	t.smoke = {"density": 0.05, "colour": Color(0.5, 0.62, 0.56), "depth": 7.0, "war": 0.0, "storm": 1.2}
	t.rules = {"cold": 0.0, "surface_grip": 0.8, "shot_carry": 0.85}
	return t
