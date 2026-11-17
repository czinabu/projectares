extends Node3D
## A site worth holding. Maps mark where they are (Marker3D nodes in the
## group "strongpoint") and the `Raid` puts one of these on each marker and
## runs it. Whoever stands inside alone for long enough takes it; while two
## sides are inside it is contested and nothing moves.
##
## A side is a plain string key: one per bot faction, and one per player (or
## one for all players in a world where they are allied). This node only
## does the arithmetic and shows a greybox beacon. Who is standing where, what
## a capture pays and who hears about it are the `Raid`'s business.

## Colours of the beacon by who holds the site.
const NOBODY := Color(0.8, 0.8, 0.8)
const BOTS := Color(1.0, 0.45, 0.15)
const PLAYERS := Color(0.3, 0.7, 1.0)
const FOUGHT_OVER := Color(1.0, 0.15, 0.1)

## Seconds one actor alone needs to take the site.
var capture_time := 20.0
## Each extra actor of the same side speeds it up by this much, up to the cap.
var crowd_bonus := 0.25
var crowd_cap := 2.0
## A half-finished capture drains this many times faster than it built up.
var drain := 2.0

var index := 0
var title := "Strongpoint"
var radius := 14.0
## The side holding the site, "" for nobody, and the name to show for it.
var holder := ""
var holder_name := ""
## Whether the holder is a player side, for the beacon and the feed.
var holder_is_player := false
## The side part of the way to taking it, and how far (0 to 1).
var taker := ""
var taker_name := ""
var progress := 0.0
var contested := false
## Client only: the server's word on whether the local player's side holds it.
var viewer_holds := false
var _beam: MeshInstance3D
var _shown := Color.BLACK


func _ready() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.35
	mesh.bottom_radius = 0.35
	mesh.height = 60.0
	mesh.radial_segments = 8
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material = mat
	_beam = MeshInstance3D.new()
	_beam.name = "Beacon"
	_beam.mesh = mesh
	_beam.position.y = mesh.height * 0.5
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam)
	refresh_look()


## Whether a point is inside the site. Height does not matter much: a
## rooftop over the site counts, someone flying far above does not.
func covers(point: Vector3) -> bool:
	var flat := Vector2(point.x - global_position.x, point.z - global_position.z)
	return flat.length() <= radius and absf(point.y - global_position.y) <= radius


## Advances the site. `present` maps each side with a living actor inside to
## { "count": int, "name": String, "player": bool }. Returns true when the
## site changed hands on this tick.
func tick(delta: float, present: Dictionary) -> bool:
	contested = present.size() > 1
	if contested:
		return false
	if present.is_empty() or present.has(holder):
		# Nobody is pushing: a half-finished capture drains away.
		progress = maxf(0.0, progress - delta * drain / maxf(capture_time, 0.001))
		if progress <= 0.0:
			taker = ""
			taker_name = ""
		return false
	var side: String = present.keys()[0]
	var who: Dictionary = present[side]
	if taker != side:
		taker = side
		taker_name = who.get("name", "")
		progress = 0.0
	var speed := minf(1.0 + crowd_bonus * (int(who.get("count", 1)) - 1), crowd_cap)
	progress += delta * speed / maxf(capture_time, 0.001)
	if progress < 1.0:
		return false
	hold(side, taker_name, who.get("player", false))
	return true


## Hands the site to a side outright.
func hold(side: String, side_name: String, is_player: bool) -> void:
	holder = side
	holder_name = side_name
	holder_is_player = is_player
	taker = ""
	taker_name = ""
	progress = 0.0
	refresh_look()


## One line on the state of the site, for a HUD. `mine` is whether the
## reader's side holds it.
func status(mine: bool) -> String:
	var text := title + ": "
	if mine:
		text += "yours"
	elif holder == "":
		text += "unclaimed"
	else:
		text += "held by %s" % holder_name
	if contested:
		text += ", contested"
	elif taker != "":
		text += ", %s taking it %d%%" % [taker_name, floori(progress * 100.0)]
	return text


func refresh_look() -> void:
	if _beam == null:
		return
	var colour := NOBODY if holder == "" else (PLAYERS if holder_is_player else BOTS)
	if contested:
		colour = FOUGHT_OVER
	if colour == _shown:
		return
	_shown = colour
	var mat: StandardMaterial3D = (_beam.mesh as CylinderMesh).material
	mat.albedo_color = Color(colour.r, colour.g, colour.b, 0.55)
