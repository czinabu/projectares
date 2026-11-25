# Updates and dev mode

Rules for the self-updater, the installer and the temporary dev mode. These are part of the rules in `CLAUDE.md` that must not be
broken: read this file before changing anything it covers, and keep it up to
date in the same PR.

- Playtest and dev builds, one codebase. The "Windows Client" and "Linux
  Server" export presets carry the feature tag "playtest": `Worlds` then
  offers only the worlds in the project setting
  `ares/release/playtest_worlds` (`Worlds.choose_offered`); a world left
  out is still loaded, so its items and old saves stay good, but it is
  never listed, offered or travelled to. The "Windows Dev" and "Linux Dev"
  presets have no tag and offer every world; CI exports them as workflow
  artifacts only (`ProjectAresDev-windows-<commit>`,
  `ProjectAresDev-linux-<commit>`).
  Both update themselves (`Updater`), each only from its own channel
  (`Updater.channel`: "release" for the playtest build, "dev" for any
  other exported build), and a manifest of the other channel is refused
  (`Updater.decide`), so the dev build is never swapped for the release,
  nor the release for the dev build. Nothing of the dev build is public
  (Caleb's call): it is never put on a release. Builds of main leave its
  manifest and pack as workflow artifacts with fixed names
  (`dev-update-manifest-<system>`, `dev-update-pack-<system>`,
  `Updater.dev_artifact`), and a dev game fetches the newest one built
  from main through the GitHub API with a read-only token its owner pastes
  into the phone's Servers app (`Updater.set_dev_token`). The token stays
  in `Updater.TOKEN_FILE` on that computer, never in the pack, the
  settings or a bug snapshot, and is sent only to api.github.com: the
  archive's redirect to GitHub's storage is followed without it. Its
  downloads sit apart from the playtest build's (`Updater.DEV_DIR`). `--playtest` on the command line tries
  the playtest build from the editor. A world joins the list once it runs
  smoothly (the frame bench, `--world <id>`) and its core loop works;
  changing the list is Caleb's call. Never branch the code for a build:
  gate on the tag or the list. The release build also applies the launch
  scope (`docs/systems/launch-scope.md`), which offers the launch's worlds
  instead of this list; the dev builds never apply it.
- The game updates itself (`core/update/updater.gd`, the `Updater`
  autoload, second after `Boot` and, like it, free of project classes). The
  Windows and Linux clients keep their pack beside the exe (`embed_pck`
  off); the release workflow stamps each build's number into
  `ares/build/number` and publishes each system's pack and manifest (build,
  engine, platform, size, SHA-256) on the rolling "latest" release:
  `ProjectAres.pck` and `update.json` for Windows, `ProjectAres-linux.pck`
  and `update-linux.json` for Linux (`Updater.manifest_name`). A manifest
  for another system is ignored, so a pack never crosses systems. Only the
  pack is replaced, never the exe, so a renamed exe (its pack renamed to
  match, found as the engine finds it, `Updater.pack_candidates`) and the
  Linux executable bit survive an update. An exported, stamped game reads it at launch,
  downloads a newer pack to `user://updates`, checks it and swaps it in
  beside the exe (on Windows a batch script does it once the game has
  closed, since an open pack cannot be replaced; release builds refuse
  `--main-pack`), then restarts. It never runs in the editor, a test, a
  server or headless, and anything that changes the engine or a native
  library needs a fresh install. Release builds also refuse `--path`, so a
  game starts its own server with `Main.server_process_args`, which leaves
  it out of an exported game. Its state shows on the start screen's
  corner and the phone's Servers app (online too, with a restart that
  leaves the server first, `Main._restart_for_update`). An update waiting
  on the player (`Phone.update_waiting`: downloaded, or needing a fresh
  install) is told (Caleb's feedback): the phone buzzes with a pop-up and
  the Servers app wears a badge, held back out in a world, the arena or a
  race (`Phone.update_hold`) until the player is home or in the plaza,
  and told again each time they get home (`Phone.remind_update`). The installer
  (`.github/installer/ProjectAres.nsi`, NSIS, built by the same workflow as
  `ProjectAres-Setup.exe`) installs per user into
  `%LOCALAPPDATA%\Programs\Project Ares`, never Program Files, so the game
  can write its own pack, and adds desktop and Start menu shortcuts. The
  logo is a placeholder in `assets/branding` (the window, exe and installer
  icon and the boot splash), made by its `make_logo.py`.
- Dev mode is TEMPORARY (Caleb's call, to come out once the game is further
  along): `core/dev/dev_mode.gd`, switched in the phone's Settings app and
  only in a debug or editor run (`DevMode.available`), never in an exported
  game. Solo, it puts `Profile` on a separate save
  (`Profile.DEV_SAVE_PATH`) kept topped up with all gear and max scrip, and
  hands a solo `Raid` its cheats (`Raid.dev_cheats`: god mode, endless heat
  and ammo, no cooldowns); a server or client raid ignores them. Online, only
  a server hosted from the editor in dev mode (`main.gd host_and_join`
  passes `--dev-host`) tops up one account: the one that claims the handed
  profile with the host's secret (`StashService.dev_host`, `dev_accounts`),
  never anyone just using the host's name. Such a server keeps its accounts
  in `Main.DEV_ACCOUNTS`, apart from real ones, and its snapshots only go
  back into the save it was hosted from (`Main._hosted_save`), so dev gear
  never leaks into the real profile; the save never swaps while online.
  Free test gear is never handed to every player (`Profile.GEAR_CRATES`
  stays empty): new gear to try comes from dev mode. `Profile.FRESH_START`
  sets an older real save back to a fresh player once, keeping who you
  are. No cheats online. Every line
  it touches is marked "DEV MODE". Never build a feature on it; to remove it,
  delete `core/dev/` and every "DEV MODE" line or block, plus
  `tests/dev_mode_tests.gd`, `tests/dev_tools_tests.gd` and
  `tests/visual/console.gd`. Dev mode also knows every blueprint
  (`DevMode.top_up_blueprints`).
- Dev tools (DEV MODE, `core/dev/dev_tools.gd`, added by `Main`): two raw
  keys read only in an editor or debug run with a window
  (`DevTools.enabled`), never exported, headless or on a server. F9 records
  `CAPTURE_SECONDS` of frame timings (frame, process, physics, render CPU
  and GPU), draw calls, objects and primitives into one JSON under
  `user://dev` with its summary first, the machine and the graphics
  settings, so Caleb can send back numbers from his own card; F10 saves a
  bug snapshot zip there (the screenshot, `Main.report_context`, the
  settings and the recent logs). The snapshot also keeps the last
  `SHOOTERS_KEPT` hits on the player's body by someone ("shooters") and
  everyone within `NEAR_REACH` of the camera ("near"), each with its
  `DevTools.draw_state` at that moment: framed by the camera, a clear line
  to it, and how many of its meshes are shown, shown to this camera and
  inside the view as the renderer culls them, so an enemy firing with no
  body on screen can be caught on Caleb's card. They are not input actions, so the
  Controls app and the key checks leave them out; a new dev key stays off
  the game's keys (no B, N, M, Y, U, K or middle mouse).
- The dev console (DEV MODE, Caleb's call: a phone app, never a flat
  overlay): the phone's Console app (`Phone.console_command`, shown only
  while `DevMode.active()`) hands `Main` a typed line, and
  `core/dev/dev_console.gd` runs it on a solo `Raid` (teleport, bots, war
  heat, storms, events, shells, timers, heal, items, vehicles; `help`
  lists them). It refuses online, where the server decides, and changes the
  world only through what the `Raid` itself calls (its spawns, events and
  weather). A new command is a `COMMANDS` row and its function there. Check
  by eye with `visual_check.tscn -- <dir> --console-only`.
