extends RefCounted
## The `death` checks. The test runner finds this file by itself and calls
## `run(t)`.

const StashService := preload("res://core/account/stash_service.gd")


static func run(t: Node) -> void:
	print("Death and dropping back in")
	Profile.reset()
	var raid: Raid = await t._new_raid(45, false)
	var results: Array[Dictionary] = []
	raid.player_finished.connect(func(_a: Actor, r: Dictionary) -> void: results.append(r))
	var p := raid.player
	var bot := raid.bots[0]
	p.inventory.add_item("lattice_shard")
	Combat.deal(p, DamageInfo.make(9999.0, bot, "bullet"))
	await t.frames(2)
	t.check(p.is_dead, "player can die")
	t.check(results.size() == 1 and results[0].outcome == "died" and results[0].killed_by == bot.display_name,
			"the life ends as died and names the killer")
	t.check(Profile.stash.is_empty(), "nothing reaches the stash on death")
	# Ashfront drops a scrip pile, not the gear (DESIGN.md "Scrip piles"):
	# the shard is either the pile's bonus item or sold into its scrip.
	var bags := raid.get_children().filter(func(n: Node) -> bool:
		return n is LootContainer and (n as LootContainer).is_bag)
	var pile: LootContainer = bags[0] if bags.size() == 1 else null
	t.check(pile != null and pile.pile and "rifle_scrap" not in pile.items
			and (pile.items == ["lattice_shard"] and pile.scrip == 0
				or pile.items.is_empty() and pile.scrip == StashService.Economy.sell_price("lattice_shard")),
			"the player's gear is gone and a scrip pile lies where they fell (%s, %d scrip)"
			% [pile.items if pile else [], pile.scrip if pile else -1])
	t.check(Hud.death_text(results[0], 0.0).contains(bot.display_name) and Hud.death_text(results[0], 0.0).contains("Enter")
			and not Hud.death_text(results[0], 2.0).contains("Enter"),
			"the death screen names the killer and offers to drop back in once the wait is over")

	# The world carries on, and the same player drops back into it.
	var again := raid.add_player([], {}, "You")
	await t.frames(2)
	t.check(raid.player == again and not again.is_dead and raid.players.size() == 1,
			"dropping back in starts a new life in the same world")
	t.check(not is_instance_valid(p) or p.is_queued_for_deletion(), "the old body is cleared away")
	t.check(is_instance_valid(bags[0]) and (bags[0] as LootContainer).pile,
			"the pile is still where you fell")
	t.check(again.protected_left > 0.0 and not Combat.deal(again, DamageInfo.make(10.0, bot, "bullet"))
			and is_equal_approx(again.health.health, again.health.max_health),
			"a player who just dropped in cannot be hurt")
	Combat.deal(bot, DamageInfo.make(1.0, again, "bullet"))
	t.check(is_zero_approx(again.protected_left) and Combat.deal(again, DamageInfo.make(10.0, bot, "bullet")),
			"attacking gives the protection up")
	again.kill("test")
	await t.frames(2)
	t.check(results.size() == 2 and Profile.raids_played == 2, "every life is recorded")
	await t._end_raid(raid)
