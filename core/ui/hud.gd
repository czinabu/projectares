class_name Hud
extends CanvasLayer
## In-raid HUD. Almost nothing is drawn over the screen: the crosshair, hit
## markers, the melee side marks, the red flash when you are hurt, and the
## prompt for what you are looking at. Everything else is on your gear in
## the world:
##   - the helmet's visor (`visor`, a `VisorHud`): what the glass you look
##     through shows, in first person only, and only what that helmet shows;
##   - the holographic watch on your left wrist (`wrist`), brought up with
##     the `check_wrist` key (X) and on its own while you are down:
##     health, armor, stamina, jetpack heat, what you carry, your standing,
##     strongpoints, sign-out and banking progress, the last few notices, and
##     what your death cost;
##   - an ammo counter on every gun (`AMMO_COUNTER` on the gun's model);
##   - a heat gauge in the screen bay on the back of a jetpack
##     (`HEAT_READOUT`), seen in third person and by everyone around you.
## War news goes to the phone as a notification (`notice_sink`) when the game
## gives the HUD one.

const RenownLedger := preload("res://core/progression/renown_ledger.gd")
## The name of the counter added to each gun's model.
const AMMO_COUNTER := "AmmoCounter"
## The jetpack's screen bay, as the rig model names it.
const HEAT_DISPLAY := "HeatDisplay"
## The gauge added to it.
const HEAT_READOUT := "HeatReadout"

var raid: Raid
var controller: PlayerController
## Where war news goes (the phone's `show_notice`). Unset, it goes on the wrist.
var notice_sink: Callable
## The wrist display.
var wrist: Wrist
## What the helmet draws on its glass in first person, and what its visor
## shows out in the world (scan snapshots, tags).
var visor: VisorHud

var _hit_marker: HitMarker
var _hurt_flash: ColorRect
var _stance: StanceIndicator
## The aiming cross in the middle of the screen.
var crosshair: Label
var _prompt: Label
var _messages: Array[Dictionary] = []
## The local player's last life, shown while they are down (see `show_death`).
var _death_result := {}
var _redeploy_wait := 0.0


func setup(p_raid: Raid, p_controller: PlayerController) -> void:
	raid = p_raid
	controller = p_controller


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_hurt_flash = ColorRect.new()
	_hurt_flash.color = Color(0.8, 0.05, 0.02, 0.0)
	_hurt_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hurt_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hurt_flash)

	visor = VisorHud.new()
	visor.name = "Visor"
	visor.setup(raid, controller)
	root.add_child(visor)

	_hit_marker = HitMarker.new()
	_hit_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hit_marker)
	_place(_hit_marker, 0.5, 0.5, Vector2(-20, -20), Vector2(40, 40))

	_stance = StanceIndicator.new()
	_stance.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_stance)
	_place(_stance, 0.5, 0.5, Vector2(-70, -70), Vector2(140, 140))

	crosshair = _label(root, "+", 22)
	_place(crosshair, 0.5, 0.5, Vector2(-7, -17), Vector2(14, 30))

	_prompt = _label(root, "", 18)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(_prompt, 0.5, 0.5, Vector2(-300, 40), Vector2(600, 30))

	wrist = Wrist.new()
	wrist.name = "Wrist"
	add_child(wrist)

	raid.player.notice.connect(_on_notice)
	raid.war_feed.connect(_on_war_feed)
	raid.player.hit_confirmed.connect(_on_hit_confirmed)
	raid.player.health.damaged.connect(_on_player_damaged)


func _exit_tree() -> void:
	if wrist != null and is_instance_valid(wrist):
		wrist.take_off()
		wrist.queue_free()


func _process(delta: float) -> void:
	if raid == null or raid.player == null or not is_instance_valid(raid.player):
		return
	var p := raid.player
	_redeploy_wait = maxf(0.0, _redeploy_wait - delta)
	_hurt_flash.color.a = maxf(0.0, _hurt_flash.color.a - delta * 0.9)

	var weapon := p.get_active_weapon()
	var blade := weapon as MeleeWeapon
	_stance.stance = blade.stance if blade else -1
	_stance.guarding = blade != null and blade.is_blocking()
	_stance.threat = incoming_side(p)
	_update_ammo_counters(p)
	_update_heat_display(p)

	var banking := raid.bank_progress()
	var leaving := raid.sign_out_progress(p)
	if p.is_dead:
		var places := drop_choices(raid, p).size()
		var landing := "1-%d: pick where to land      " % places if places > 1 else ""
		_prompt.text = landing + "Enter: drop back in      L: go home" if _redeploy_wait <= 0.0 \
				else "Dropping back in in %d..." % ceili(_redeploy_wait)
		if _death_result.is_empty():
			_prompt.text = ""
	elif leaving >= 0.0:
		_prompt.text = "Signing out...   L to cancel"
	elif banking > 0.0:
		_prompt.text = "Banking your backpack..."
	elif p.heal_time_left > 0.0:
		_prompt.text = "Healing %.1f" % p.heal_time_left
	else:
		# On a vehicle, F gets you off, so nothing else is offered.
		var target := p.find_interactable() if p.vehicle == null else null
		_prompt.text = target.get_prompt() if target else ""

	for m in _messages:
		m.time -= delta
	_messages = _messages.filter(func(m: Dictionary) -> bool: return m.time > 0.0)
	var log_lines: Array[String] = []
	for m in _messages:
		log_lines.append(m.text)

	wrist.raised = p.is_dead or (controller != null and controller.wrist_raised)
	wrist.mount(p, controller, visible, delta)
	wrist.show_text(wrist_text(raid, p, _death_result if p.is_dead else {}, _redeploy_wait, log_lines),
			wrist_bars(p), leaving if leaving >= 0.0 else banking)


## What the wrist display says, line by line. `death` is the last life's
## result while down (else empty), and `log_lines` the recent notices.
static func wrist_text(p_raid: Raid, p: Actor, death: Dictionary, wait: float, log_lines: Array[String]) -> String:
	if not death.is_empty():
		return death_text(death, wait, drop_choices(p_raid, p))
	var lines: Array[String] = []
	var where := p_raid.world.display_name
	if p_raid.war.intensity >= 0.2:
		where += "   " + p_raid.war.level_name()
	lines.append(where)
	lines.append(standing_text(p))
	var sites := sites_text(p_raid, p)
	if sites != "":
		lines.append(sites)
	var weapon := p.get_active_weapon()
	lines.append(weapon.status_text() if weapon else "Unarmed")
	if p.ability.enabled:
		lines.append("[G] %s" % p.ability.status_text())
	if p.visor.enabled and p.visor.mode != "":
		lines.append("[T] %s" % p.visor.status_text())
	if p.vehicle != null:
		lines.append("%s   %d km/h" % [p.vehicle.get("display_name"), roundi(absf(float(p.vehicle.get("speed"))) * 3.6)])
	lines.append("Pack %d/%d   worth %d   heals %d" % [p.inventory.items.size(), p.inventory.capacity,
			p.inventory.total_value(), p.inventory.count_with_tag("heal")])
	if p.flight.enabled and p.flight.overheated:
		lines.append("JETPACK OVERHEATED")
	for line in log_lines.slice(maxi(0, log_lines.size() - 2)):
		lines.append(line)
	return "\n".join(lines)


## The wrist's bars: health, armor and stamina from 0 to 1, and jetpack heat
## (-1 with no flight rig).
static func wrist_bars(p: Actor) -> Array[float]:
	return [p.health.health / p.health.max_health,
			p.health.armor / p.health.max_armor if p.health.max_armor > 0.0 else 0.0,
			p.stamina / p.max_stamina,
			p.flight.heat_fraction() if p.flight.enabled else -1.0]


## Keeps a counter on each carried gun's model: rounds in the magazine over
## what is in reserve.
func _update_ammo_counters(p: Actor) -> void:
	for w in p.weapons:
		var gun := w as Gun
		if gun == null or gun.visual == null or not is_instance_valid(gun.visual):
			continue
		var counter := gun.visual.get_node_or_null(AMMO_COUNTER) as Label3D
		if counter == null:
			counter = Label3D.new()
			counter.name = AMMO_COUNTER
			counter.font_size = 48
			counter.pixel_size = 0.0007
			counter.outline_size = 8
			counter.no_depth_test = true
			counter.render_priority = 2
			counter.position = Vector3(0.0, 0.085, 0.06)
			counter.rotation.x = -0.35
			gun.visual.add_child(counter)
		counter.text = ammo_text(gun)
		counter.modulate = Color(1.0, 0.4, 0.3) if gun.ammo_in_mag <= gun.mag_size / 5 else Color(0.55, 1.0, 0.75)


## Lights the screen bay on the back of a worn jetpack (the rig model's
## `HEAT_DISPLAY` marker) with a heat gauge: a bar that fills and turns from
## green to red, and a word over it. Others see it on your back; you see it
## in third person. The skin builds the model, so headless there is none.
func _update_heat_display(p: Actor) -> void:
	var bay := p.find_child(HEAT_DISPLAY, true, false) as Node3D
	if bay == null:
		return
	var readout := bay.get_node_or_null(HEAT_READOUT) as Node3D
	if readout == null:
		readout = _build_heat_readout(bay.get_meta("size", Vector2(0.13, 0.15)))
		bay.add_child(readout)
	var heat := p.flight.heat_fraction() if p.flight.enabled else 0.0
	var fill := readout.get_node("Fill") as MeshInstance3D
	var room: float = readout.get_meta("bar_height")
	fill.scale.y = maxf(0.001, heat)
	fill.position.y = readout.get_meta("bar_bottom") + room * heat * 0.5
	var color := heat_color(heat, p.flight.overheated)
	(fill.material_override as StandardMaterial3D).albedo_color = color
	(fill.material_override as StandardMaterial3D).emission = color
	var word := readout.get_node("Word") as Label3D
	word.text = heat_text(p.flight)
	word.modulate = color


func _build_heat_readout(room: Vector2) -> Node3D:
	var readout := Node3D.new()
	readout.name = HEAT_READOUT
	var bar := Vector2(room.x * 0.6, room.y * 0.6)
	var bottom := -room.y * 0.5 + room.y * 0.08
	readout.set_meta("bar_height", bar.y)
	readout.set_meta("bar_bottom", bottom)
	var back := _flat_quad(bar + Vector2(0.008, 0.008), Color(0.02, 0.025, 0.03), 0.0)
	back.position = Vector3(0, bottom + bar.y * 0.5, 0.001)
	readout.add_child(back)
	var fill := _flat_quad(Vector2(bar.x, bar.y), Color(0.4, 1.0, 0.6), 1.6)
	fill.name = "Fill"
	fill.position = Vector3(0, bottom, 0.002)
	readout.add_child(fill)
	var word := Label3D.new()
	word.name = "Word"
	word.font_size = 40
	word.pixel_size = 0.0011
	word.outline_size = 6
	word.position = Vector3(0, room.y * 0.5 - room.y * 0.14, 0.003)
	readout.add_child(word)
	return readout


static func _flat_quad(size: Vector2, color: Color, energy: float) -> MeshInstance3D:
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = size
	quad.mesh = mesh
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	if energy > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = energy
	quad.material_override = mat
	return quad


## The word on the jetpack's screen: the heat in percent, or that it is
## locked out cooling down.
static func heat_text(flight: FlightRig) -> String:
	if flight.overheated:
		return "HOT"
	return "%d%%" % roundi(flight.heat_fraction() * 100.0)


## Green when cool, through amber, to red when hot or locked out.
static func heat_color(heat: float, overheated: bool) -> Color:
	if overheated:
		return Color(1.0, 0.25, 0.15)
	var cool := Color(0.4, 1.0, 0.6)
	var warm := Color(1.0, 0.75, 0.2)
	var hot := Color(1.0, 0.3, 0.15)
	return cool.lerp(warm, heat / 0.6) if heat < 0.6 else warm.lerp(hot, (heat - 0.6) / 0.4)


## The counter on a gun: "24 | 90", or that it is reloading.
static func ammo_text(gun: Gun) -> String:
	if gun.is_reloading():
		return "RELOAD"
	return "%d | %d" % [gun.ammo_in_mag, gun.reserve_ammo]


## The side a nearby enemy swing is coming at the player, as the player sees
## it (the side to guard), or -1 when nothing is winding up in front of them.
static func incoming_side(p: Actor) -> int:
	if p.is_dead or not p.is_inside_tree():
		return -1
	var forward := p.get_aim_dir()
	forward.y = 0.0
	var best := -1
	var best_dist := INF
	for node in p.get_tree().get_nodes_in_group("actors"):
		var other := node as Actor
		if other == null or other == p or other.is_dead:
			continue
		var blade := other.get_active_weapon() as MeleeWeapon
		if blade == null or not blade.is_winding_up():
			continue
		var to := other.global_position - p.global_position
		to.y = 0.0
		var dist := to.length()
		if dist > blade.reach * 2.5 or dist >= best_dist:
			continue
		if dist > 0.5 and forward.length() > 0.01 and forward.normalized().dot(to.normalized()) < 0.2:
			continue
		best = MeleeWeapon.mirror(blade.attack_dir)
		best_dist = dist
	return best


func _on_hit_confirmed(_target: Actor, info: DamageInfo, lethal: bool) -> void:
	if lethal:
		_hit_marker.flash(Color(1.0, 0.25, 0.2), 0.35)
	elif info.parried or info.blocked:
		_hit_marker.flash(Color(0.6, 0.75, 1.0), 0.15)
	else:
		_hit_marker.flash(Color.WHITE, 0.15)


func _on_player_damaged(info: DamageInfo) -> void:
	_hurt_flash.color.a = clampf(_hurt_flash.color.a + 0.12 + info.amount * 0.012, 0.0, 0.45)


## Shows what the local player's death cost them and how to carry on.
## `wait` is how many seconds until they may drop back in.
func show_death(result: Dictionary, wait: float) -> void:
	_death_result = result
	_redeploy_wait = wait


## The words on the death screen.
## Where the player may land next (`Raid.drop_choices`). Only the authority
## knows a player's owner key; a client is offered the world's own places.
static func drop_choices(p_raid: Raid, p: Actor) -> Array:
	var state := p_raid.state_for(p)
	return p_raid.drop_choices(state.owner if state != null and p_raid.mode != Raid.Mode.CLIENT else "")


## `drops` is where they may land next (`Raid.drop_choices`).
static func death_text(result: Dictionary, wait: float, drops: Array = []) -> String:
	var by: String = result.get("killed_by", "")
	var lost: Array = result.get("lost", [])
	var lines: Array[String] = ["Killed by %s" % by if by != "" else "You died"]
	lines.append("Lost: %s" % ItemDB.summarize(lost) if not lost.is_empty() else "Nothing lost")
	if int(result.get("renown_lost", 0)) > 0:
		lines.append("Renown lost: %d" % int(result.renown_lost))
	if int(result.get("scrip_lost", 0)) > 0:
		lines.append("Scrip dropped: %d" % int(result.scrip_lost))
	var kept: Array = result.get("kept_gear", [])
	if not kept.is_empty():
		lines.append("Kept: %s" % ItemDB.summarize(kept))
	var banked: Array = result.get("banked", [])
	if not banked.is_empty():
		lines.append("Banked before you fell: worth %d" % int(result.get("banked_value", 0)))
	lines.append("")
	if wait > 0.0:
		lines.append("Drop back in in %d..." % ceili(wait))
	else:
		# One place to land is no choice: Enter is enough.
		if drops.size() > 1:
			for i in drops.size():
				lines.append("%d: %s, %s" % [i + 1, drops[i].title, drops[i].note])
			lines.append("")
		lines.append("Enter: drop back in      L: return to the hub")
	return "\n".join(lines)


## The local player's standing: rank, session renown, streak, and whether
## they are being hunted.
static func standing_text(p: Actor) -> String:
	var text := "%s   Renown %d" % [RenownLedger.rank_name(p.rank), p.renown]
	if p.scrip > 0:
		text += "   Scrip %d" % p.scrip
	if p.streak > 1:
		text += "   Streak %d" % p.streak
	if p.bounty > 0:
		text += "   BOUNTY %d" % p.bounty
	if p.exposed:
		text += "   EXPOSED"
	if p.marked:
		text += "   THE MARKED"
	return text


## Strongpoints: the one the player is standing in, in full, or else how
## many of the world's they hold.
static func sites_text(p_raid: Raid, p: Actor) -> String:
	if p_raid.strongpoints.is_empty():
		return ""
	var here := p_raid.strongpoint_at(p) if not p.is_dead else null
	if here != null:
		return here.status(p_raid.holds(p, here))
	var mine := 0
	for point in p_raid.strongpoints:
		if p_raid.holds(p, point):
			mine += 1
	return "Strongpoints held: %d of %d" % [mine, p_raid.strongpoints.size()]


## News for everyone in the world: a phone notification when there is a
## phone, else a line on the wrist that stays up a little longer.
func _on_war_feed(text: String) -> void:
	if notice_sink.is_valid():
		notice_sink.call(text)
		return
	_log(text, 7.0)


## Puts a line on the wrist display.
func notify(text: String) -> void:
	_on_notice(text)


func _on_notice(text: String) -> void:
	_log(text, 4.0)


func _log(text: String, seconds: float) -> void:
	_messages.append({"text": text, "time": seconds})
	if _messages.size() > 6:
		_messages.pop_front()


func _label(parent: Control, text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


## Anchors a control to a point of the screen (0..1) with a pixel offset and size.
func _place(control: Control, ax: float, ay: float, offset: Vector2, size: Vector2) -> void:
	control.anchor_left = ax
	control.anchor_right = ax
	control.anchor_top = ay
	control.anchor_bottom = ay
	control.offset_left = offset.x
	control.offset_top = offset.y
	control.offset_right = offset.x + size.x
	control.offset_bottom = offset.y + size.y


## Four diagonal ticks around the crosshair that flash when your attack lands.
class HitMarker:
	extends Control

	var _left := 0.0
	var _duration := 0.15
	var _color := Color.WHITE

	func flash(color: Color, duration: float) -> void:
		_color = color
		_duration = duration
		_left = duration
		queue_redraw()

	func _process(delta: float) -> void:
		if _left > 0.0:
			_left -= delta
			queue_redraw()

	func _draw() -> void:
		if _left <= 0.0:
			return
		var c := size * 0.5
		var color := _color
		color.a = clampf(_left / _duration, 0.0, 1.0)
		for dir: Vector2 in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
			draw_line(c + dir * 7.0, c + dir * 15.0, color, 2.5)

## Three marks around the crosshair for directional melee: which side you are
## set to attack or guard, and which side an enemy swing is coming at.
## Kept as an inner class so the HUD never depends on the editor's class cache.
class StanceIndicator:
	extends Control

	const OFFSETS := [Vector2(0, -1), Vector2(-1, 0), Vector2(1, 0)]

	## The player's `MeleeWeapon.Dir`, or -1 to hide the stance marks.
	var stance := -1
	var guarding := false
	## The side of the screen an enemy swing is coming at, or -1 for none.
	var threat := -1

	var radius := 34.0
	var threat_radius := 48.0
	var mark_length := 22.0


	func _process(_delta: float) -> void:
		queue_redraw()


	func _draw() -> void:
		var center := size * 0.5
		for dir in OFFSETS.size():
			var out: Vector2 = OFFSETS[dir]
			var along := Vector2(-out.y, out.x) * mark_length * 0.5
			if stance >= 0:
				var active := dir == stance
				var color := Color(1, 1, 1, 0.22)
				if active:
					color = Color(0.45, 0.75, 1.0) if guarding else Color.WHITE
				var at := center + out * radius
				draw_line(at - along, at + along, color, 4.0 if active else 2.0)
			if dir == threat:
				var at := center + out * threat_radius
				# Yellow on a dark outline, so it shows against red enemies and sky.
				draw_line(at - along * 1.6, at + along * 1.6, Color(0, 0, 0, 0.85), 12.0)
				draw_line(at - along * 1.5, at + along * 1.5, Color(1.0, 0.9, 0.15), 7.0)


## Shows or hides the aiming marks in the middle of the screen, which would
## sit on your face in the phone's mirror.
func show_aim(on: bool) -> void:
	if crosshair:
		crosshair.visible = on
	if _stance:
		_stance.visible = on


## A holographic watch on your left wrist. Lowered, it is only a watch: a
## band and a small lit face, nothing in the view. Raised (`raised`, the
## `check_wrist` key, and on its own while you are down), it throws a
## hologram up off the face: bars and a few lines of text, drawn into its
## own viewport.
##   - First person, where your own body is not drawn: a forearm comes up
##     into the bottom of the view with the watch on it, and the hologram
##     opens above it.
##   - Third person: the watch rides on the character's left wrist bone, and
##     the hologram opens over the wrist, turned to the camera and pulled
##     towards it far enough to read.
## Sizes follow the camera's field of view, so a wide view does not shrink it.
class Wrist:
	extends Node3D

	const BAR_COLORS := [Color(0.85, 0.25, 0.25), Color(0.35, 0.6, 1.0), Color(0.95, 0.85, 0.3), Color(1.0, 0.6, 0.15)]
	const HOLO_TINT := Color(0.7, 1.0, 1.0, 0.9)
	## The bone the watch is worn on in third person.
	const WRIST_BONE := "Wrist.L"
	## The hologram's face in metres, and its picture in pixels.
	var face_size := Vector2(0.24, 0.15)
	var pixels := Vector2i(480, 300)
	## Where the hologram opens in first person, in the camera's space, at
	## `reference_fov`: low and a little left of the middle of the view.
	var first_person_at := Vector3(-0.1, -0.09, -0.36)
	## Where the forearm sits under it when raised, and how far below the
	## view it waits when lowered.
	var arm_at := Vector3(-0.1, -0.215, -0.4)
	var arm_lowered_drop := 0.32
	## The field of view the sizes above are for. A wider view grows them.
	var reference_fov := 80.0
	## Third person: how far in front of the camera the hologram hangs, how
	## big it is there, and how far above the wrist it opens.
	var projection_distance := 1.4
	var projection_scale := 3.0
	var projection_lift := 0.45
	## How far it is nudged across the view (camera right, up) from there.
	var projection_nudge := Vector2(-0.3, -0.12)
	## Seconds the hologram takes to open or close.
	var raise_time := 0.18

	## True while the hologram should be up.
	var raised := false
	## 0 lowered, 1 fully open.
	var raise_amount := 0.0
	## The colour the watch face glows now (see `face_tint`).
	var face_color := Color.WHITE

	var viewport: SubViewport
	var _text: Label
	var _bars: Array[ProgressBar] = []
	var _hold: ProgressBar
	var _holo: MeshInstance3D
	var _arm: Node3D
	## The watch worn on the character's wrist bone, third person.
	var _worn: Node3D
	var _body_mesh: MeshInstance3D

	func _ready() -> void:
		viewport = SubViewport.new()
		viewport.size = pixels
		viewport.disable_3d = true
		viewport.transparent_bg = true
		add_child(viewport)
		var glass := ColorRect.new()
		glass.color = Color(0.0, 0.22, 0.26, 0.5)
		glass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		viewport.add_child(glass)
		var box := VBoxContainer.new()
		box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		box.offset_left = 14
		box.offset_top = 10
		box.offset_right = -14
		box.offset_bottom = -10
		box.add_theme_constant_override("separation", 4)
		viewport.add_child(box)
		for i in BAR_COLORS.size():
			var bar := ProgressBar.new()
			bar.show_percentage = false
			bar.max_value = 1.0
			bar.custom_minimum_size = Vector2(0, 16 if i == 0 else 9)
			var fill := StyleBoxFlat.new()
			fill.bg_color = BAR_COLORS[i]
			var back := StyleBoxFlat.new()
			back.bg_color = Color(1, 1, 1, 0.1)
			bar.add_theme_stylebox_override("fill", fill)
			bar.add_theme_stylebox_override("background", back)
			box.add_child(bar)
			_bars.append(bar)
		_text = Label.new()
		_text.add_theme_font_size_override("font_size", 21)
		_text.add_theme_color_override("font_color", Color(0.75, 1.0, 0.95))
		_text.add_theme_constant_override("line_spacing", -3)
		_text.clip_text = true
		_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.add_child(_text)
		_hold = ProgressBar.new()
		_hold.show_percentage = false
		_hold.max_value = 1.0
		_hold.custom_minimum_size = Vector2(0, 10)
		var hold_fill := StyleBoxFlat.new()
		hold_fill.bg_color = Color(0.25, 1.0, 0.55)
		_hold.add_theme_stylebox_override("fill", hold_fill)
		box.add_child(_hold)

		_holo = MeshInstance3D.new()
		_holo.name = "Hologram"
		var quad := QuadMesh.new()
		quad.size = face_size
		_holo.mesh = quad
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_texture = viewport.get_texture()
		mat.albedo_color = HOLO_TINT
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.no_depth_test = true
		mat.render_priority = 3
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_holo.material_override = mat
		_holo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_holo)
		_arm = _build_arm()
		add_child(_arm)

	## Takes the watch off the character (the HUD going away).
	func take_off() -> void:
		if _worn != null and is_instance_valid(_worn):
			_worn.queue_free()
		_worn = null

	## A greybox forearm in a sleeve, with the watch on top, for first person.
	func _build_arm() -> Node3D:
		var arm := Node3D.new()
		arm.name = "Forearm"
		# The forearm runs from the bottom left in towards the middle.
		arm.rotation = Vector3(0.25, 0.0, 0.35)
		var sleeve := _box(Vector3(0.36, 0.075, 0.08), Color(0.2, 0.22, 0.2))
		sleeve.position = Vector3(-0.17, 0, 0)
		arm.add_child(sleeve)
		var hand := _box(Vector3(0.08, 0.035, 0.07), Color(0.62, 0.48, 0.38))
		hand.position = Vector3(0.05, -0.005, 0)
		arm.add_child(hand)
		var watch := _watch()
		watch.position = Vector3(-0.03, 0.04, 0)
		arm.add_child(watch)
		return arm

	## The watch itself: a band and a small glowing face, face up (+Y).
	static func _watch() -> Node3D:
		var watch := Node3D.new()
		watch.name = "Watch"
		watch.add_child(_box(Vector3(0.03, 0.012, 0.086), Color(0.08, 0.08, 0.09)))
		var face := _box(Vector3(0.036, 0.008, 0.036), Color(0.3, 0.95, 1.0), 2.0)
		face.name = "Face"
		face.position = Vector3(0, 0.008, 0)
		watch.add_child(face)
		return watch

	static func _box(size: Vector3, color: Color, glow := 0.0) -> MeshInstance3D:
		var mesh := BoxMesh.new()
		mesh.size = size
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		if glow > 0.0:
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.emission_enabled = true
			mat.emission = color
			mat.emission_energy_multiplier = glow
		mat.no_depth_test = true
		mat.render_priority = 2
		mesh.material = mat
		var box := MeshInstance3D.new()
		box.mesh = mesh
		box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return box

	## Straps the watch to the character's wrist bone, once there is a skin
	## with one. Headless there is none, and nothing is worn.
	func _wear(p: Actor) -> void:
		if _worn != null and is_instance_valid(_worn) and _worn.is_inside_tree():
			return
		var skeleton := p.find_child("*Skeleton*", true, false) as Skeleton3D
		if skeleton == null or skeleton.find_bone(WRIST_BONE) < 0:
			return
		var attach := BoneAttachment3D.new()
		attach.name = "WornWatch"
		attach.bone_name = WRIST_BONE
		skeleton.add_child(attach)
		var watch := _watch()
		# Undo the model's import scale so the watch keeps its size.
		var s := skeleton.global_basis.get_scale()
		watch.scale = Vector3(1.0 / maxf(s.x, 0.001), 1.0 / maxf(s.y, 0.001), 1.0 / maxf(s.z, 0.001))
		attach.add_child(watch)
		_worn = attach
		_body_mesh = null
		for child in skeleton.find_children("*", "MeshInstance3D", true, false):
			_body_mesh = child
			break

	## The watch is drawn on the same layers as the body, so in first person,
	## where your own camera leaves the body out, it goes with it.
	func _match_body_layers() -> void:
		if _worn == null or not is_instance_valid(_worn) or _body_mesh == null or not is_instance_valid(_body_mesh):
			return
		for child in _worn.find_children("*", "MeshInstance3D", true, false):
			(child as MeshInstance3D).layers = _body_mesh.layers

	## Where the watch is in the world, third person: on the wrist bone, or
	## where a left wrist would be when there is no skin.
	func _watch_position(p: Actor) -> Vector3:
		if _worn != null and is_instance_valid(_worn) and _worn.is_inside_tree():
			return _worn.global_position
		return p.global_transform * Vector3(-0.3, 1.05, -0.1)

	## Puts the watch and its hologram where the view can see them, and opens
	## or closes the hologram towards `raised`. Hidden with the HUD.
	func mount(p: Actor, controller: PlayerController, shown: bool, delta := 0.0) -> void:
		var third := controller != null and controller.is_third_person()
		var cam := controller.camera if controller else null
		var holder: Node3D = p if third or cam == null else cam
		if get_parent() != holder:
			if get_parent():
				get_parent().remove_child(self)
			holder.add_child(self)
		_wear(p)
		_match_body_layers()
		var goal := 1.0 if raised else 0.0
		raise_amount = move_toward(raise_amount, goal, delta / maxf(raise_time, 0.001)) if delta > 0.0 else goal
		var t := ease(raise_amount, -2.0)
		visible = shown
		# The hologram unfolds upwards once the wrist is up.
		var open := clampf((raise_amount - 0.35) / 0.65, 0.0, 1.0)
		_holo.visible = open > 0.0
		# A wider view shrinks everything in it; the watch grows to match.
		var k := 1.0
		if cam:
			k = tan(deg_to_rad(cam.fov) * 0.5) / tan(deg_to_rad(reference_fov) * 0.5)
		var spread := Vector3(k, k, 1.0)
		_arm.visible = not third and raise_amount > 0.0
		if third:
			transform = Transform3D.IDENTITY
			if cam and is_inside_tree():
				var above := _watch_position(p) + Vector3.UP * projection_lift
				var to_cam := cam.global_position - above
				var at := above
				if to_cam.length() > projection_distance + 0.01:
					at = cam.global_position - to_cam.normalized() * projection_distance
				# Nudged left and down of the wrist's line, clear of the crosshair.
				at += (cam.global_basis.x * projection_nudge.x + cam.global_basis.y * projection_nudge.y) * k
				var size := projection_scale * k
				_holo.global_transform = Transform3D(cam.global_basis.orthonormalized().scaled(
						Vector3(size, size * maxf(open, 0.001), size)), at)
		else:
			transform = Transform3D.IDENTITY
			_arm.position = arm_at * spread + Vector3(0, -arm_lowered_drop * (1.0 - t), 0)
			_arm.scale = Vector3.ONE * k
			_holo.transform = Transform3D(Basis.IDENTITY.scaled(Vector3(k, k * maxf(open, 0.001), k)),
					first_person_at * spread + Vector3(0, -arm_lowered_drop * (1.0 - t), 0))

	## True once the hologram is fully open.
	func is_open() -> bool:
		return raise_amount >= 1.0

	func show_text(text: String, bars: Array[float], hold: float) -> void:
		_text.text = text
		for i in _bars.size():
			var value: float = bars[i] if i < bars.size() else -1.0
			_bars[i].visible = value >= 0.0
			_bars[i].value = clampf(value, 0.0, 1.0)
		_hold.modulate.a = 1.0 if hold > 0.0 else 0.0
		_hold.value = clampf(hold, 0.0, 1.0)
		# The watch face shows health even with the hologram down: cyan when
		# well, red when low.
		var health: float = clampf(bars[0], 0.0, 1.0) if not bars.is_empty() else 1.0
		face_color = face_tint(health)
		for watch: Node in [_arm.get_node_or_null("Watch"), _worn.get_child(0) if _worn != null and is_instance_valid(_worn) and _worn.get_child_count() > 0 else null]:
			var face := watch.get_node_or_null("Face") as MeshInstance3D if watch != null else null
			if face:
				var mat := (face.mesh as BoxMesh).material as StandardMaterial3D
				mat.albedo_color = face_color
				mat.emission = face_color

	## The watch face's colour at a share of health.
	static func face_tint(health: float) -> Color:
		return Color(1.0, 0.2, 0.15).lerp(Color(0.3, 0.95, 1.0), clampf((health - 0.2) / 0.5, 0.0, 1.0))

	func text() -> String:
		return _text.text if _text else ""
