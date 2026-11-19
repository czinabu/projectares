extends RefCounted
## The `phone` checks. The test runner finds this file by itself and calls
## `run(t)`.


static func run(t: Node) -> void:
	t._test_social_service()
	t._test_game_settings()
	await t._test_phone_view()
	await t._test_phone_escape()
	await t._test_online_phone()
