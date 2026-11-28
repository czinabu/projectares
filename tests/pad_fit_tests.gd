extends RefCounted
## Shoulder pads are as broad on every build (Caleb: Build B's read a third
## smaller): a pad on an arm slimmer than Build A's stands off it by the
## difference (`ArmorModel.arm_shortfall`).

const ArmorModel := preload("res://core/visual/armor_model.gd")
const STYLE := {"plate": Color.GRAY, "plate2": Color.GRAY, "fabric": Color.GRAY, "strap": Color.GRAY,
		"metal": Color.GRAY, "accent": Color.GRAY}


static func run(t: Node) -> void:
	print("Shoulder pads on every build")
	t.check(is_zero_approx(ArmorModel.arm_shortfall("m")) and ArmorModel.arm_shortfall("f") > 0.01,
			"Build B's upper arm is slimmer than Build A's, so its pads stand off it (%.3f m)" % ArmorModel.arm_shortfall("f"))
	for weight: String in ["light", "medium", "heavy"]:
		var a := _size(ArmorModel.pauldron(weight, STYLE, 1.0, "m"))
		var b := _size(ArmorModel.pauldron(weight, STYLE, 1.0, "f"))
		t.check(b.x > a.x * 0.85 and b.z > a.z * 0.9,
				"a %s pad is nearly as broad on Build B as on Build A (%.3f x %.3f against %.3f x %.3f)" % [weight, b.x, b.z, a.x, a.z])


static func _size(pad: Node3D) -> Vector3:
	var box := AABB()
	var first := true
	for part in pad.find_children("*", "MeshInstance3D", true, false):
		var mesh_part := part as MeshInstance3D
		var bb: AABB = mesh_part.transform * mesh_part.mesh.get_aabb()
		box = bb if first else box.merge(bb)
		first = false
	pad.free()
	return box.size
