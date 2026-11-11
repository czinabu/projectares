extends WorldDef
## The arena: a round sand pit ringed by a wall, with tiered stands for the
## crowd. It is a venue, not a raid world, so it lives in core and is never
## listed with the deploy targets. It never names a specific world.
##
## Rules: nobody loses gear here (`gear_at_risk` is off), nobody can hurt
## anyone except the two fighters in the current bout, and the bout is run by
## `Arena` (core/arena/arena.gd), which this venue creates as its raid.
##
## Map contract, beyond WorldDef's: Marker3D nodes in group "arena_gate" with
## meta "side" (0 = red, 1 = blue) where fighters enter the pit.
##
## Load with `const ArenaVenue := preload("res://core/arena/arena_venue.gd")`.

const ID := "arena"
const ArenaScript := preload("res://core/arena/arena.gd")

## Inside this radius from the center is the pit. The stands start past the wall.
const PIT_RADIUS := 16.0
const WALL_RADIUS := 16.6
const WALL_HEIGHT := 3.6
const STAND_TIERS := 4
const TIER_DEPTH := 3.0
const TIER_RISE := 0.9
const OUTER_RADIUS := WALL_RADIUS + 0.6 + STAND_TIERS * TIER_DEPTH
const SEGMENTS := 28
const GATE_DISTANCE := 12.5

## Gladiator names for bots, picked by seed so a client builds the same one.
const GLADIATOR_NAMES := ["Varro", "Priscus", "Spiculus", "Flamma", "Crixus", "Tetraites", "Carpophorus",
		"Verus", "Marcus Attilius", "Hermes", "Triumphus", "Celadus"]

## The arena that is using this venue. Set by `Arena` when it starts.
var arena: Node = null


func _init() -> void:
	id = ID
	display_name = "The Pit"
	description = "Duels, tournaments and wagers. Nobody loses gear in the arena."
	# Bouts keep their own clock. The raid timer never runs out here.
	raid_duration = 1.0e9
	bot_count = 0
	gear_at_risk = false


func new_raid() -> Raid:
	return ArenaScript.new()


func create_map() -> Node3D:
	return Pit.new()


## The free scrap kit from the core item list, for empty loadout slots.
func starter_loadout() -> Array[String]:
	return ["rifle_scrap", "blade_scrap", "jetpack_mk1", "plate_light"]


## Only the two fighters in a running bout can hurt each other. `info` is
## null when a bot is only asking whether someone is a target.
func can_damage(attacker: Node, target: Node, _info: DamageInfo) -> bool:
	if attacker == target or arena == null or not is_instance_valid(arena):
		return false
	return arena.call("may_hurt", attacker, target)


## A bot gladiator, the same from the same seed on every machine.
func equip_bot(bot: Actor, rng: RandomNumberGenerator) -> void:
	bot.faction = "gladiator_%d" % rng.randi()
	bot.display_name = GLADIATOR_NAMES[rng.randi() % GLADIATOR_NAMES.size()]
	bot.set_meta("look", "scavenger")
	bot.body_color = Color(0.75, 0.6, 0.3)
	var kit: Array[String] = ["plate_light"]
	# Most gladiators fight with a blade, the rest with a rifle.
	if rng.randf() < 0.65:
		kit.append("blade_scrap")
	else:
		kit.append("rifle_scrap")
	Loadout.equip(bot, kit)
	bot.health.max_health = rng.randf_range(90.0, 110.0)
	bot.health.health = bot.health.max_health


## True if `at` is inside the pit wall (fighters belong there, nobody else).
static func in_pit(at: Vector3) -> bool:
	return Vector2(at.x, at.z).length() < WALL_RADIUS + 0.2


## The colosseum, built from plain boxes that `Look` dresses.
class Pit:
	extends Node3D

	var _sand: Material
	var _stone: Material
	var _dark: Material

	func _ready() -> void:
		_sand = Look.surface("ground", {"tint": Color(0.86, 0.72, 0.5), "grime": 0.2, "scale": 0.15})
		_stone = Look.surface("concrete", {"tint": Color(0.78, 0.7, 0.6), "grime": 0.35, "scale": 0.25})
		_dark = Look.surface("concrete", {"tint": Color(0.45, 0.4, 0.36), "grime": 0.6, "scale": 0.25})
		Look.atmosphere(self, {"sun_angles": Vector3(-55, 40, 0), "sun_color": Color(1.0, 0.92, 0.8),
				"sun_energy": 1.2, "fog_color": Color(0.7, 0.62, 0.52)})
		var size := OUTER_RADIUS * 2.0 + 6.0
		_box(Vector3(size, 0.5, size), Vector3(0, -0.25, 0), 0.0, _sand)
		_ring(WALL_RADIUS, 0.6, 0.0, WALL_HEIGHT, _stone)
		for tier in STAND_TIERS:
			var inner := WALL_RADIUS + 0.3 + tier * TIER_DEPTH
			var top := WALL_HEIGHT - 0.6 + tier * TIER_RISE
			_ring(inner + TIER_DEPTH * 0.5, TIER_DEPTH, 0.0, top, _dark if tier % 2 == 0 else _stone)
		_ring(OUTER_RADIUS + 0.5, 1.0, 0.0, WALL_HEIGHT + STAND_TIERS * TIER_RISE + 4.0, _stone)
		_gates()
		_spectator_spots()
		var title := Label3D.new()
		title.text = "THE PIT"
		title.font_size = 128
		title.pixel_size = 0.02
		title.modulate = Color(1.0, 0.62, 0.22)
		title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		title.position = Vector3(0, 7.5, 0)
		add_child(title)

	## A ring of boxes around the center: `radius` to its middle, `depth` thick.
	func _ring(radius: float, depth: float, bottom: float, top: float, material: Material) -> void:
		var width := 2.0 * (radius + depth * 0.5) * tan(PI / SEGMENTS) + 0.1
		for i in SEGMENTS:
			var angle := TAU * i / SEGMENTS
			var at := Vector3(sin(angle), 0, cos(angle)) * radius
			at.y = (bottom + top) * 0.5
			_box(Vector3(width, top - bottom, depth), at, angle, material)

	func _box(size: Vector3, at: Vector3, yaw: float, material: Material) -> void:
		var body := StaticBody3D.new()
		body.collision_layer = Actor.LAYER_WORLD
		body.collision_mask = 0
		body.position = at
		body.rotation.y = yaw
		var shape := BoxShape3D.new()
		shape.size = size
		var col := CollisionShape3D.new()
		col.shape = shape
		body.add_child(col)
		var mesh := BoxMesh.new()
		mesh.size = size
		mesh.material = material
		var mesh_node := MeshInstance3D.new()
		mesh_node.mesh = mesh
		body.add_child(mesh_node)
		add_child(body)

	## Where each side's fighter enters, with a colored portcullis on the wall.
	func _gates() -> void:
		for side in 2:
			var dir := -1.0 if side == 0 else 1.0
			var marker := Marker3D.new()
			marker.name = "Gate%d" % side
			marker.position = Vector3(dir * GATE_DISTANCE, 0.1, 0)
			marker.set_meta("side", side)
			marker.add_to_group("arena_gate")
			add_child(marker)
			var color := Color(0.9, 0.25, 0.2) if side == 0 else Color(0.25, 0.45, 0.95)
			var mat := StandardMaterial3D.new()
			mat.albedo_color = color
			mat.emission_enabled = true
			mat.emission = color * 0.4
			var mesh := BoxMesh.new()
			mesh.size = Vector3(0.3, 3.0, 3.2)
			mesh.material = mat
			var gate := MeshInstance3D.new()
			gate.mesh = mesh
			gate.position = Vector3(dir * (WALL_RADIUS - 0.35), 1.5, 0)
			add_child(gate)

	## Spectators arrive on the lower tiers, spread around the ring.
	func _spectator_spots() -> void:
		for tier in 2:
			var radius := WALL_RADIUS + 0.3 + (tier + 0.5) * TIER_DEPTH
			var height := WALL_HEIGHT - 0.6 + tier * TIER_RISE + 0.1
			for i in 8:
				var angle := TAU * (i + 0.5 * tier) / 8.0 + PI / 16.0
				var marker := Marker3D.new()
				marker.position = Vector3(sin(angle) * radius, height, cos(angle) * radius)
				# Facing the pit.
				marker.rotation.y = angle
				marker.add_to_group("spawn_player")
				add_child(marker)
