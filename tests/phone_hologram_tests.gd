extends RefCounted
## Checks for the phone's hologram in third person (Caleb's call, replacing
## the zoom in on the hand): the screen is thrown up off the handheld beside
## the character, square to the camera and big enough to read, the camera
## stays put, and clicks land on the hologram. First person still reads the
## handheld itself. `-- --groups phone_hologram` runs just these.

const PhoneScript := preload("res://core/phone/phone.gd")
const Handheld := preload("res://core/phone/handheld.gd")


## A stand-in for the dressed character's skin: a hand holding the device.
class HandSkin extends Node:
	var held: Node3D
	var phone_screen: Material
	var locomotion: Object = self

	func handheld() -> Node3D:
		return held

	func set_phone_screen(screen: Material) -> void:
		phone_screen = screen
		var face := Handheld.face_of(held)
		if face != null:
			face.set_surface_override_material(0, screen)


static func run(t: Node) -> void:
	print("Phone: the hologram in third person")
	var phone: CanvasLayer = PhoneScript.new()
	t.add_child(phone)
	var raid: Raid = await t._new_raid(93, false)
	var controller := PlayerController.new()
	controller.setup(raid.player)
	raid.add_child(controller)
	await t.frames(2)
	if raid.player.has_node("Skin"):
		# A dressed character holds the real handheld; these checks use a
		# plain hand so they run the same headless.
		await t._end_raid(raid)
		phone.queue_free()
		return
	var skin := HandSkin.new()
	skin.name = "Skin"
	skin.held = Handheld.build()
	raid.player.add_child(skin)
	raid.player.add_child(skin.held)
	skin.held.position = Vector3(0.15, 1.4, -0.4)
	phone.set_holder(raid.player)
	var projection: Node3D = phone.projection
	t.check(projection != null and not projection.showing(), "the phone has a hologram, down while it is away")

	controller.view_mode = PlayerController.ViewMode.THIRD
	controller.input_blocked = true
	controller.phone_out = true
	phone.open()
	for i in 40:
		await t.frames(1)
	var cam := controller.camera
	t.check(controller.is_third_person() and projection.showing(), "third person throws the screen up as a hologram")
	var shown: Vector2 = cam.get_viewport().get_visible_rect().size
	var rect: Rect2 = projection.on_screen(cam)
	t.check(rect.size.y / shown.y > 0.39, "it stands a big share of the view tall, so its text reads (%.2f)" % (rect.size.y / shown.y))
	var hand := cam.unproject_position(Handheld.face_of(skin.held).global_position)
	t.check(rect.end.y < hand.y, "its lower edge stands over the phone, so the light rises up into it (Caleb's feedback)")
	t.check(rect.position.x > shown.x * 0.5 and rect.end.x <= shown.x + 1.0 and rect.position.y >= -1.0
			and rect.end.y <= shown.y + 1.0, "right of the crosshair and all of it in frame")
	var card: MeshInstance3D = projection.get_node("Card")
	t.check(card.global_basis.z.normalized().dot(cam.global_basis.z.normalized()) > 0.99,
			"square to the camera")
	var to_card := cam.global_transform.affine_inverse() * card.global_position
	var to_head := cam.global_transform.affine_inverse() * raid.player.get_eye_position()
	t.check(-to_card.z > -to_head.z, "standing just past the character, so the body passes in front of it")
	t.check(projection.get_node("Beam").visible, "with light running up to it from the device")
	var middle: Vector2 = phone.screen_point(rect.get_center())
	t.check(middle.distance_to(Vector2(phone.screen_size) * 0.5) < 6.0, "a click on it lands on the phone's screen")
	t.check(phone.screen_point(Vector2(4.0, shown.y * 0.5)).x < 0.0, "and a click off it misses")

	phone.close()
	controller.phone_out = false
	for i in 20:
		await t.frames(1)
	t.check(not projection.showing() and not card.visible, "putting the phone away takes the hologram down")

	controller.view_mode = PlayerController.ViewMode.FIRST
	controller.phone_out = true
	phone.open()
	for i in 40:
		await t.frames(1)
	t.check(not controller.is_third_person() and not projection.showing(),
			"first person reads the handheld itself, with no hologram")
	phone.close()
	controller.phone_out = false
	controller.input_blocked = false
	await t._end_raid(raid)
	phone.queue_free()
	await t.frames(1)
