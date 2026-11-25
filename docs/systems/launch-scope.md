# The launch scope

Rules for the first release's scope: what the Early Access launch ships and
how the rest is held back without leaving the code. These are part of the
rules in `CLAUDE.md` that must not be broken: read this file before changing
anything it covers, and keep it up to date in the same PR.

- The launch is the home base, the Concourse, Ashfront and Frostline (Caleb's
  call, 25 November 2026, DESIGN.md "More worlds"). Everything else that is
  built stays in the code for later updates, held back by one switch:
  `LaunchScope` (`core/release/launch_scope.gd`), the project setting
  `ares/release/launch_scope`.
- The switch applies only to the release build: the export presets with the
  feature tag "playtest" ("Windows Client", "Linux Client", "Linux Server"),
  or `--playtest` on the command line to try it from the editor.
  `Worlds.choose_offered` sets `LaunchScope.on` at startup. The dev build
  ("Windows Dev", "Linux Dev", the editor) and the test runner never apply
  it, so they keep every world and everything held back. Never add a second
  switch or a feature tag for it, and never branch the code for a build: ask
  `LaunchScope`.
- Worlds: with the switch on, `Worlds` offers `ares/release/launch_worlds`
  (plaza, ashfront, frostline) instead of `ares/release/playtest_worlds`.
  Everything that lists worlds asks `Worlds` (`raid_worlds`, `offered`), so
  the gate terrace, `Portal.destinations`, the War Room's console and race
  feed (`WarRoom.segments`), contracts and the server's sessions all follow.
  A held world is still loaded, so its items and old saves stay good.
- Features (`LaunchScope.HELD`, asked with `holds`): "arena" (the Pit: no
  arena session on a server, `Portal.destinations` and `Main.open_arena`
  refuse it, the hub's arena gate has its shutter down and Sola talks about
  it opening), "races" (the phone's Racing app), "market" (the Exchange on
  Market Row is a shuttered front, `NetSession._request_market` and
  `Main.open_market` refuse), "trophies" (`BaseLayout.spots` gives the
  trophy shelf and the artifact case none, and the stores build no shelf
  for them), "lounge" (`BasePlan.held`: its doorway is sealed with no room
  behind it, the plan table leaves it out, its upgrades are not ready) and
  "base_visits" (no "Invite to base" on the phone, `SocialService.invite`
  refuses one, Wren drops her line about visitors).
- Items (`LaunchScope.holds_item`): anything tagged "rover", "walker",
  "aircraft" or "artifact", and a blueprint whose recipe makes one. Never
  sold (`Economy.is_shop_item`, the back room), rolled as loot
  (`ItemDB.roll` gives the rest of a table its weight; `roll_artifact`,
  `roll_crafting_loot`), paid by a job (`Contracts.reward_for`), crafted
  (`Crafting.ids`, `blocked`) or offered on the watch (`Raid.add_player`'s
  toys, `HomeBase.watch_vehicles`, the artifact icon left off by
  `Hud.Wrist.row`). The bikes and the hoverbike stay.
- A new way to reach something held back asks `LaunchScope` too, and gets a
  check in `tests/launch_scope_tests.gd`. Shipping something later is a
  change to this list (or the setting), not to each place that offers it.
