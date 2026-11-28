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
	_by_weight(t)


## The heavier the frame, the broader its pads stand (the shoulders carry
## the silhouette).
static func _by_weight(t: Node) -> void:
	var light := _size(ArmorModel.pauldron("light", STYLE, 1.0, "m"))
	var medium := _size(ArmorModel.pauldron("medium", STYLE, 1.0, "m"))
	var heavy := _size(ArmorModel.pauldron("heavy", STYLE, 1.0, "m"))
	t.check(light.x < medium.x and medium.x < heavy.x and light.z < medium.z and medium.z < heavy.z,
			"pads stand broader and deeper the heavier the frame (%.3f, %.3f, %.3f across)" % [light.x, medium.x, heavy.x])


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
