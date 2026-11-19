extends RefCounted
## The `fresh_drops` checks. The test runner finds this file by itself and calls
## `run(t)`.

const LifeLogTests := preload("res://tests/life_log_tests.gd")


static func run(t: Node) -> void:
	await LifeLogTests.fresh_drops(t)
