extends RefCounted
## Checks for the Graphics quality pick (`GameSettings.GRAPHICS`): one
## choice on the phone that sets every performance setting, reads "Custom"
## once one of them is changed by hand, spots a laptop's built-in graphics,
## and fits a window bigger than a small screen.

const GameSettings := preload("res://core/settings/game_settings.gd")
const PhoneScript := preload("res://core/phone/phone.gd")


static func run(t: Node) -> void:
	GameSettings.persist = false
	GameSettings.reset()
	t.check(GameSettings.graphics == GameSettings.GRAPHICS_HIGH
			and GameSettings.graphics_matching() == GameSettings.GRAPHICS_HIGH,
			"the defaults are the High graphics pick, the world as made")
	for pick: int in GameSettings.GRAPHICS_CUSTOM:
		var row: Array = GameSettings.GRAPHICS[pick]
		t.check(row.size() == GameSettings.GRAPHICS_KEYS.size() + 1,
				"graphics pick %s has a value for every setting it sets" % row[0])
		for i: int in GameSettings.GRAPHICS_KEYS.size():
			var key: String = GameSettings.GRAPHICS_KEYS[i]
			var schema := GameSettings.row_of(key)
			t.check(not schema.is_empty() and typeof(row[i + 1]) == typeof(schema["default"]),
					"graphics pick %s sets %s to a value of its kind" % [row[0], key])
			if schema.get("kind", "") == "choice":
				t.check(int(row[i + 1]) < (schema["choices"] as Array).size(),
						"graphics pick %s sets %s to a choice there is" % [row[0], key])

	GameSettings.set_value("graphics", GameSettings.GRAPHICS_LOW)
	var low := GameSettings.shadows == 2 and GameSettings.render_scale == GameSettings.RENDER_SCALE_AUTO \
			and GameSettings.view_distance == 2 and not GameSettings.ambient_occlusion \
			and not GameSettings.ground_smoke and not GameSettings.bloom
	t.check(low and GameSettings.graphics == GameSettings.GRAPHICS_LOW and GameSettings.to_dict().has("graphics"),
			"picking Low sets the shadows, render scale, view distance and effects at once, and is saved")
	GameSettings.set_value("shadows", 0)
	t.check(GameSettings.graphics == GameSettings.GRAPHICS_CUSTOM
			and GameSettings.render_scale == GameSettings.RENDER_SCALE_AUTO,
			"changing one of them by hand reads Custom and keeps the rest")
	GameSettings.set_value("graphics", GameSettings.GRAPHICS_CUSTOM)
	t.check(GameSettings.shadows == 0 and GameSettings.render_scale == GameSettings.RENDER_SCALE_AUTO,
			"picking Custom changes nothing")
	GameSettings.set_value("shadows", 2)
	t.check(GameSettings.graphics == GameSettings.GRAPHICS_LOW,
			"settings that match a pick again read as that pick")
	GameSettings.set_value("graphics", GameSettings.GRAPHICS_LOWEST)
	t.check(GameSettings.shadows == GameSettings.SHADOWS.size() - 1
			and is_equal_approx(GameSettings.RENDER_SCALE[GameSettings.render_scale][1], 0.5),
			"Lowest has no shadows and the smallest render scale")
	GameSettings.set_value("graphics", GameSettings.GRAPHICS_HIGH)
	var root := t.get_tree().root
	GameSettings.apply_graphics()
	t.check(is_equal_approx(root.scaling_3d_scale, 1.0) and GameSettings.shadows == 0,
			"back to High, the world as made at full size")

	# Spotting the graphics card on the first launch.
	t.check(GameSettings.graphics_for(RenderingDevice.DEVICE_TYPE_DISCRETE_GPU, "NVIDIA GeForce RTX 5070")
			== GameSettings.GRAPHICS_HIGH, "a separate graphics card starts on High")
	t.check(GameSettings.graphics_for(RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU,
			"Intel(R) UHD Graphics 620 (KBL GT2)") == GameSettings.GRAPHICS_LOW,
			"a laptop's built-in graphics starts on Low")
	t.check(GameSettings.graphics_for(RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU,
			"AMD Radeon 780M Graphics (RADV PHOENIX)") == GameSettings.GRAPHICS_MEDIUM,
			"the strongest built-in graphics start on Medium")
	t.check(GameSettings.graphics_for(RenderingDevice.DEVICE_TYPE_CPU, "llvmpipe (LLVM 20.1.2, 256 bits)")
			== GameSettings.GRAPHICS_LOWEST, "a software renderer starts on Lowest")
	t.check(GameSettings.graphics_for(RenderingDevice.DEVICE_TYPE_DISCRETE_GPU, "Mesa Intel(R) HD Graphics", false)
			== GameSettings.GRAPHICS_LOW, "the OpenGL fallback (no Vulkan) starts on Low")
	GameSettings.reset()
	GameSettings.detect_graphics()
	t.check(GameSettings.graphics_card == "" and GameSettings.graphics == GameSettings.GRAPHICS_HIGH,
			"with no window the graphics card is not looked at")

	# A window bigger than a small laptop screen.
	t.check(GameSettings.window_fit(Vector2i(1600, 900), Vector2i(1920, 1040)) == Vector2i(1600, 900),
			"a window that fits is left as it is")
	var fitted := GameSettings.window_fit(Vector2i(1600, 900), Vector2i(1366, 728))
	t.check(fitted.x <= 1366 and fitted.y <= 728 and absf(float(fitted.x) / fitted.y - 16.0 / 9.0) < 0.02,
			"a window bigger than the screen is shrunk to fit, keeping its shape")

	# The phone shows a pick's settings at once.
	var schema_graphics := GameSettings.row_of("graphics")
	t.check(schema_graphics.get("tab", "") == "view" and schema_graphics.get("section", "") == "PERFORMANCE",
			"Graphics quality is on the phone's View tab, over the performance settings")
	GameSettings.reset()
	var phone: CanvasLayer = PhoneScript.new()
	t.add_child(phone)
	await t.frames(1)
	phone.toggle()
	phone.open_app("settings")
	phone.open_settings_tab("view")
	await t.frames(1)
	var lists: Dictionary = phone._setting_controls
	var drawn: bool = lists.get("graphics") is OptionButton and lists.get("shadows") is OptionButton
	if drawn:
		(lists["graphics"] as OptionButton).select(GameSettings.GRAPHICS_LOWEST)
		(lists["graphics"] as OptionButton).item_selected.emit(GameSettings.GRAPHICS_LOWEST)
	t.check(drawn and (lists["shadows"] as OptionButton).selected == GameSettings.SHADOWS.size() - 1
			and not (lists["ambient_occlusion"] as CheckButton).button_pressed,
			"picking a graphics quality on the phone shows the rows it set at once")
	if drawn:
		(lists["shadows"] as OptionButton).item_selected.emit(0)
	t.check(drawn and (lists["graphics"] as OptionButton).selected == GameSettings.GRAPHICS_CUSTOM,
			"and changing one row by hand shows Custom")
	phone.queue_free()
	await t.frames(1)
	GameSettings.reset()
