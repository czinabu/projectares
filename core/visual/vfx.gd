extends RefCounted
## One-shot effects: muzzle flashes, impact sparks, thruster flame. Only `Look`
## and the skins call these, and only when there is a screen to draw on.


static func muzzle_flash(parent: Node, at: Vector3, dir: Vector3) -> void:
	var root := Node3D.new()
	parent.add_child(root)
	var up := Vector3.RIGHT if absf(dir.y) > 0.99 else Vector3.UP
	root.look_at_from_position(at, at + dir, up)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(3.0, 1.9, 0.7)
	var roll := randf() * TAU
	for i in 3:
		var quad := QuadMesh.new()
		quad.size = Vector2(0.09, 0.36) if i < 2 else Vector2(0.22, 0.22)
		quad.material = mat
		var node := MeshInstance3D.new()
		node.mesh = quad
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if i < 2:
			# Two crossed blades of flame along the barrel.
			node.rotation = Vector3(-PI / 2.0, 0, roll + i * PI / 2.0)
			node.rotation_order = EULER_ORDER_ZXY
			node.position.z = -0.16
		else:
			node.rotation.z = roll
		root.add_child(node)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.75, 0.4)
	light.light_energy = 3.0
	light.omni_range = 7.0
	light.shadow_enabled = false
	root.add_child(light)
	parent.get_tree().create_timer(0.045).timeout.connect(root.queue_free)


static func impact(parent: Node, at: Vector3, normal: Vector3, bright := true) -> void:
	var sparks := CPUParticles3D.new()
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.amount = 10 if bright else 5
	sparks.lifetime = 0.35
	sparks.direction = normal
	sparks.spread = 50.0
	sparks.initial_velocity_min = 2.5
	sparks.initial_velocity_max = 8.0
	sparks.gravity = Vector3(0, -14, 0)
	sparks.scale_amount_min = 0.5
	sparks.scale_amount_max = 1.0
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.015, 0.015, 0.11)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(3.5, 2.0, 0.6)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	mesh.material = mat
	sparks.mesh = mesh
	sparks.particle_flag_align_y = true
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(sparks)
	sparks.global_position = at
	sparks.emitting = true

	var dust := CPUParticles3D.new()
	dust.one_shot = true
	dust.explosiveness = 0.9
	dust.amount = 5
	dust.lifetime = 0.7
	dust.direction = normal
	dust.spread = 35.0
	dust.initial_velocity_min = 0.4
	dust.initial_velocity_max = 1.6
	dust.gravity = Vector3(0, 0.4, 0)
	dust.damping_min = 2.0
	dust.damping_max = 3.0
	dust.scale_amount_min = 0.6
	dust.scale_amount_max = 1.5
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.3))
	grow.add_point(Vector2(1, 1.0))
	dust.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(0.5, 0.47, 0.44, 0.5))
	fade.set_color(1, Color(0.5, 0.47, 0.44, 0.0))
	dust.color_ramp = fade
	var puff := QuadMesh.new()
	puff.size = Vector2(0.35, 0.35)
	var puff_mat := StandardMaterial3D.new()
	puff_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	puff_mat.vertex_color_use_as_albedo = true
	puff_mat.albedo_texture = _soft_dot()
	puff.material = puff_mat
	dust.mesh = puff
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(dust)
	dust.global_position = at
	dust.emitting = true
	var timer := parent.get_tree().create_timer(1.0)
	timer.timeout.connect(sparks.queue_free)
	timer.timeout.connect(dust.queue_free)


## A flame and a glow for a flight rig. The caller shows and hides it.
static func thruster() -> Node3D:
	var root := Node3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.09
	cone.bottom_radius = 0.0
	cone.height = 0.7
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.6, 2.2, 3.5, 0.8)
	cone.material = mat
	for x: float in [-0.14, 0.14]:
		var flame := MeshInstance3D.new()
		flame.mesh = cone
		flame.position = Vector3(x, -0.35, 0)
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(flame)
	var light := OmniLight3D.new()
	light.light_color = Color(0.5, 0.7, 1.0)
	light.light_energy = 2.0
	light.omni_range = 5.0
	light.shadow_enabled = false
	light.position.y = -0.4
	root.add_child(light)
	return root


static var _dot: GradientTexture2D

static func _soft_dot() -> GradientTexture2D:
	if _dot == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1, 1, 1, 1))
		gradient.set_color(1, Color(1, 1, 1, 0))
		_dot = GradientTexture2D.new()
		_dot.gradient = gradient
		_dot.fill = GradientTexture2D.FILL_RADIAL
		_dot.fill_from = Vector2(0.5, 0.5)
		_dot.fill_to = Vector2(1.0, 0.5)
		_dot.width = 32
		_dot.height = 32
	return _dot
