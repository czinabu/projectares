extends RefCounted
## The `army_pushes` checks. The test runner finds this file by itself and calls
## `run(t)`.

const LifeLogTests := preload("res://tests/life_log_tests.gd")


static func run(t: Node) -> void:
	await LifeLogTests.pushes(t)
