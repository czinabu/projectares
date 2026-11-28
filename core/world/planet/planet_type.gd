class_name PlanetType
extends RefCounted
## A kind of planet a world is built on (DESIGN.md "Planet kit"): its sky,
## its light in calm and in a storm, the shape and surface of its ground,
## its far horizon, its weather and the rocks and growth scattered over it,
## all as data. A world names one (`WorldDef.planet`) and builds only its own
## layout and rules on it; two worlds on one type look like one planet.
##
## Nothing here names a world, and nothing here changes the simulation
## except `rules`, the defaults a world on this planet starts from (it may
## still set its own). The look is applied by `Planet` and stays a no-op on a
## headless server, like everything in `Look`.

var id := ""
var display_name := ""
## One line on what the place is like, for the design doc and dev tools.
var blurb := ""
## `PlanetSky`'s uniforms (see `assets/shaders/planet_sky.gdshader`).
var sky := {}
## `Look.atmosphere` moods: the calm and the thick of a storm. The sky keys
## (tint, energy, saturation, haze) grade the planet's own sky.
var calm := {}
var storm := {}
## Close air, a mood for where a map says the air shuts in (the marsh's
## forests), blended by the map's "close_here" meta, or empty for none.
var close := {}
## `PlanetTerrain`'s recipe.
var terrain := {}
## `planet_ground.gdshader`'s uniforms.
var ground := {}
## The scanned surface each ground layer wears ("base", "rock", "cap",
## "patch"): a folder under `assets/textures` holding `Color.jpg` and
## `NormalGL.jpg`, or "" for the layer's procedural look alone (lava, water).
## The scan only adds detail: the layer's colour still comes from `ground`.
var surfaces := {"base": "", "rock": "", "cap": "", "patch": ""}
## The far ring of land round a map (`Planet.horizon`): how far it reaches
## and how high its mountains stand at the far edge.
var horizon := {"reach": 2600.0, "peaks": 120.0}
## The weather: "air" is what always drifts (`Planet.weather` kinds:
## "embers", "ash", "snow", "rain", "sand", "spores", ""), "storm" the
## storm kind a world on this planet uses (`WorldDef.weather_kind`).
var weather := {"air": "", "storm": ""}
## Low smoke lying over the ground (`Planet.GroundSmoke`, view only, behind
## `GameSettings.ground_smoke`), or empty for clear air: "density" in calm,
## "colour", "depth" (metres it stands over the ground), "war" and "storm"
## (how much thicker it is at full war and in the thick of a storm, as
## shares of the calm density). With "banks" it also drifts in banks
## (`Planet.GroundSmoke`): "count" round the camera, "cell" metres apart,
## "size" (an ellipsoid), "density", "drift" (metres a second) and "wind"
## (its heading, radians).
var smoke := {}
## What is scattered on the ground (`PlanetProps`): kind, how many per
## hectare, size range, and where (slope, height).
var props: Array[Dictionary] = []
## The colour a world on this planet glows in on its deploy gate
## (`GateLook.world_color`), or clear to take it from the weather. Set it
## where two planets' weather would give their gates the same colour.
var accent := Color(0, 0, 0, 0)
## Simulation defaults for a world on this planet: `cold`, `surface_grip`,
## `shot_carry`. Read by `WorldDef` when it takes the planet.
var rules := {}
