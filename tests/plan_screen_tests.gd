extends RefCounted
## Checks that the plan table's lectern screen goes back to its idle face
## when the player steps away, before and after a change that rebuilds the
## table: a live screen left behind shows a freed viewport, which draws solid
## white. Called from the test runner (`-- --only plan_screen`).

const BasePlan := preload("res://core/base/base_plan.gd")


static func run(t: Node) -> void:
	print("Plan table screen")
	await _leave_plain(t)
	await _leave_after_change(t)


## Opens the plan table on a fresh base, as `Main.open_bench("plan")` does.
static func _open(t: Node) -> Array:
	var base := HomeBase.new()
	base.show_gear([], {})
	t.add_child(base)
	await t.frames(5)
	base.use_plan()
	var view: Node3D = load("res://core/ui/bench_view.gd").new()
	view.base = base
	view.target = "plan"
	base.add_child(view)
	view.focus()
	await t.frames(3)
	return [base, view]


## Every customizer screen standing on the lectern, in or out of the tree.
static func _live_screens(base: HomeBase) -> int:
	var face: Node3D = base.plan_screen()
	if face == null:
		return 0
	var count := 0
	for child in face.get_children():
		if child is WorldScreen and not child.is_queued_for_deletion():
			count += 1
	return count


## Esc from an Input event: the view leaves, and the frame's own process
## step that follows must not put the screen back up.
static func _leave_by_key(view: Node3D) -> void:
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	view._unhandled_input(esc)
	# The rest of the frame: the view is only queued for freeing yet.
	view._process(1.0 / 60.0)


static func _leave_plain(t: Node) -> void:
	var opened: Array = await _open(t)
	var base: HomeBase = opened[0]
	var view: Node3D = opened[1]
	t.check(_live_screens(base) == 1, "using the plan table puts one live screen on the lectern")
	_leave_by_key(view)
	await t.frames(3)
	var face: Node3D = base.plan_screen()
	t.check(_live_screens(base) == 0, "stepping away leaves no live screen on the lectern (a freed one draws white)")
	t.check(face.get_node_or_null("Idle") != null and face.get_node_or_null("IdleText") != null,
			"the lectern shows its idle face again")
	base.queue_free()
	await t.frames(2)


static func _leave_after_change(t: Node) -> void:
	var opened: Array = await _open(t)
	var base: HomeBase = opened[0]
	var view: Node3D = opened[1]
	# A change that rebuilds the table while it is in use (a room moved).
	var plan := BasePlan.clean({})
	var rooms: Array = []
	for socket: String in BasePlan.SOCKETS:
		rooms.append(plan[socket])
	plan[BasePlan.SOCKETS[0]] = rooms[1]
	plan[BasePlan.SOCKETS[1]] = rooms[0]
	base.show_gear([], {}, null, plan)
	await t.frames(3)
	t.check(_live_screens(base) == 1, "after a change rebuilds the table, one live screen is back on it")
	_leave_by_key(view)
	await t.frames(3)
	t.check(_live_screens(base) == 0, "stepping away after a change leaves no live screen behind")
	# Using it again after stepping away still works, with one screen.
	opened = []
	base.use_plan()
	var again: Node3D = load("res://core/ui/bench_view.gd").new()
	again.base = base
	again.target = "plan"
	base.add_child(again)
	again.focus()
	await t.frames(3)
	t.check(_live_screens(base) == 1, "using the table again puts exactly one screen up")
	again.leave()
	await t.frames(3)
	t.check(_live_screens(base) == 0, "and stepping away takes it down")
	base.queue_free()
	await t.frames(2)
