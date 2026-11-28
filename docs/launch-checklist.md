# Early Access launch checklist

What has to be done before Verge goes on sale in Early Access on Steam
(Caleb's call, 28 November 2026). The scope itself (which worlds, features
and items ship) is in `docs/systems/launch-scope.md` and DESIGN.md "More
worlds". This file is the to-do list: tick a line in the PR that finishes
it.

It is called Early Access, not 1.0: the held-back worlds, the Pit and the
market come in later updates, and "1.0" waits until they are in.

## Must be done before launch

- [ ] **An official server.** Launch worlds only, the game pointed at it,
  its certificate built in, one sign-in per account across worlds, a
  crashed world's unsent results kept, off-machine backups. Hosting starts
  on Caleb's own machine (the paid server waits, Caleb's call); a rented one
  later. Owned by the "Plan what's left before release polish" thread;
  see `docs/hosting.md`.
- [ ] **Account recovery code.** A one-time code on the phone that moves an
  account to a new PC. Same thread as above. (design-gaps: "Official
  servers before Steam")
- [ ] **Steam.**
  - [ ] Steamworks app (the $100 fee), store page, capsule art and
    screenshots. Caleb's to do.
  - [ ] Steam export presets (feature tag "steam") and an upload step for
    the builds (depots).
  - [x] The self-updater stays off in a copy Steam installed
    (`Updater.on_steam`), since Steam updates it.
  - [ ] Steam login, or a decision to add it a few weeks after launch
    (design-gaps: "Steam login"). Caleb's call.
  - [ ] A privacy policy and terms, since accounts live on our server.
- [ ] **A friends playtest** on the official server, to set the prices,
  drop rates and balance that are placeholders today.
- [ ] **Progression.** The mastery gate on Mk2, Mk2 helmets, bounties paying
  upgrade data, what weapons gain per Mk level. Needs Caleb's numbers.
- [ ] **The new player tour.** The last step's guide from the base and the
  plaza (in flight).
- [x] **Crash-safe solo saves.** The profile and settings are written whole
  (`SafeFile`), and the last good profile save is kept and loaded if the
  save is torn (`Profile.BACKUP`).
- [ ] **Audio basics.** Footsteps, vehicles, world ambience and a menu
  track. Only the guns have real sounds today.
- [ ] **Laptop performance.** 60 fps on Low, checked with Caleb's F9
  recording from the laptop.

## After launch

The Ashfront battlefield polish, animation and vehicle polish, the deploy
gates showing their worlds, the enemy rework, a heavy weapon dropping into
the bag instead of on a rack, the insured seal on the watch and displays,
and Linux self-updates (Steam handles updates there). Then the Spore Marsh
and the Pit, the Dune Sea, the Basalt Rift and Meridian.
