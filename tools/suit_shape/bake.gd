extends Node
## Bakes the suit's shape (`core/visual/suit_shape.gd`) for every build into
## `suit_<build>_<part>.res` beside the bodies. Run again whenever the bodies
## or `suit_shape.gd` change, then re-measure with `tools/body_fit`. Needs a
## display or xvfb (a headless run keeps no mesh data):
##
##   godot --path . res://tools/suit_shape/bake.tscn

const Human := preload("res://core/visual/human.gd")
const SuitShape := preload("res://core/visual/suit_shape.gd")


func _ready() -> void:
	for build: String in Human.BUILDS:
		var rig: Node3D = (load(Human.rig_path(build)) as PackedScene).instantiate()
		var skeleton := rig.find_child("Skeleton3D", true, false) as Skeleton3D
		var meshes := SuitShape.make(skeleton)
		for part: String in meshes:
			var mesh: ArrayMesh = meshes[part]
			# The body's material stays in the body file; it is given back on load.
			mesh.surface_set_material(0, null)
			var err := ResourceSaver.save(mesh, SuitShape.baked_path(build, part))
			print("baked ", SuitShape.baked_path(build, part), " ", error_string(err))
		rig.free()
	get_tree().quit()
