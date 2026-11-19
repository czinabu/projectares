extends RefCounted
## The `rig_models` checks. The test runner finds this file by itself and calls
## `run(t)`.

const RigLookTests := preload("res://tests/rig_look_tests.gd")


static func run(t: Node) -> void:
	print("Flight rig models")
	await RigLookTests.run(t)
