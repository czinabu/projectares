# Phone, watch and menus

Rules for the phone and its settings, emotes and shortcut keys, bug reports, the new player's tour, opening in the world, menus in the world and the watch. These are part of the rules in `CLAUDE.md` that must not be
broken: read this file before changing anything it covers, and keep it up to
date in the same PR.

- The phone (`core/phone/phone.gd`) is the game's menu and only a view. Online,
  presence, contacts, messages, invites and news live on the server in
  `SocialService` (`core/social/social_service.gd`), keyed by the account id
  the peer signed in with, never by anything the client claims. `NetSession`
  turns phone requests into service calls and pushes each affected player a
  fresh `social_state` snapshot. A feature that adds a new place a player can be
  (base, social hub) reports it with `NetSession._set_presence(peer, where)` and
  a name in `SocialService.PLACE_NAMES`. The phone's Controls app lists
  every key from `Phone.CONTROLS`, whose `{action}` names are filled in from
  the live `InputMap`; a new input action needs a row there (a test fails
  otherwise), and a changed control needs its row's wording updated. The phone
  is a thing in the hand, never an overlay, and every view shows the same
  one: a rugged handheld with a pistol grip (`core/phone/handheld.gd`, its
  origin at the grip) that the character's own right hand closes round with
  the gun-grip fist (`ActorSkin._update_phone`, `Locomotion.phone_pose`,
  driven by `ActorCommand.phone`, a held flag, so everyone sees it). Your own
  phone puts its screen, a `SubViewport` drawn with the device's frame and
  chin keys, on that handheld's face (`Phone.set_holder`,
  `ActorSkin.set_phone_screen`) and clicks are cast onto it; other players'
  show lit glass. It is held at the chest, a forearm out and right of the
  middle, below the face (`Locomotion.phone_wrist`), so others and a mirror
  see a person reading a phone, the same hold in both views. First person
  reads and clicks the handheld's own face: the eyes drop to it and the view
  zooms in until it stands `PlayerController.phone_zoom` of the view's
  height (`phone_zoomed`, `phone_fit_fov`). Third person never moves the
  camera for the phone (Caleb's call, replacing the old reading view and
  zoom): the screen is thrown up off the handheld as a hologram, like the
  watch's card off the wrist (`Phone.HoloScreen`, view only, your own
  phone only). It stands just past the character from the camera
  (`behind`), right of the crosshair, drawn over the world so a wall or
  the ground beside you never hides it (Caleb's "fix the projected phone":
  it used to be depth tested, and a wall to your right swallowed it),
  `tall` of the view's height and square to the camera so its text reads
  (scaled along its own axes, `scaled_local`: `Basis.scaled` stretches
  along the world's and skewed it whenever the view turned),
  on dark glass the world shows through a little (`backing`, `TINT`,
  Caleb's feedback). Where it stands follows Caleb's sketch: just right of
  the crosshair, its middle a little over the view's (`across`, `lift`), and
  the light runs from the device into its near edge like a projector's cone
  (`beam_reach`); clicks are cast onto it (`HoloScreen.card_point`)
  instead of the device. Its text stays sharp drawn smaller than its
  texture because the hologram shader takes four taps across each
  pixel's footprint (`Hud.Wrist.HOLO_SHADER`, a viewport texture has no
  mipmaps), and its scan lines are faint (`HoloScreen.line_depth`) so they
  never dim a line of text. The Mirror app (Caleb's pick): in first person a
  mirror stands square in front of the body, never along the camera, close
  enough that you stand large in it (`Mirror.distance`), and wide enough
  to fill the view behind both you and the phone's screen
  (`Mirror.width`, `side_offset`), so no edge of it runs down the middle.
  Its reflection is drawn at about the screen's own sharpness
  (`Mirror._fit_resolution`, with the main view's smoothing and model
  detail) and the dressing light puts no glint on its frame. Caleb's "make the
  mirror easy to use and clear": the phone in the hand was too small to
  read with the mirror in view and you too small in the glass, so in first
  person the view frames your reflection, you left of the middle the whole
  body tall (`PlayerController.mirror_frame`, `mirror_left`, `mirror_fill`,
  view only: `yaw`, `pitch` and the aim stay put), and the phone throws its
  screen up beside you as the same hologram third person reads
  (`Phone._hold`); the phone in your hand is left out of the eyes' camera
  meanwhile, as your head is, so it never stands in front of your
  reflection (`Phone._keep_device_from_eyes`), and the hologram is kept out
  of the mirror's camera. In third person there is no mirror
  but a dressing room: the camera swings round in front of the character
  (`PlayerController.dressing_room`, `_dress_view`) from over the phone
  held at the chest (`dressing_height`, so it never hides the face), with
  the body framed left of the middle, the phone stays up with its hologram
  on the right. Choosing a face row (hairstyle, facial hair, hair colour,
  eyes: `Phone.FACE_PICKS`, `mirror_on_face`) brings either view in close
  on the face (`PlayerController.mirror_focus`, `dressing_close`), and the
  page says how to use it at the top,
  and a drag beside the hologram turns the view round you
  (`Phone.dressing`, `dressing_dragged`, `dressing_turn`). Switching view
  with the app up swaps one for the other (`Main._keep_mirror_view`), and
  either way a soft light stands in front of you so the outfit shows
  whatever the sun does (`Main._make_dressing_light`, view only). The Mirror app's wheel works like a watch icon:
  it moves between rows, a click opens one for the wheel to turn, a right
  click closes it (`Phone._mirror_mouse`), and the page scrolls to keep
  the chosen row in view (`Phone._keep_in_view`, once the redrawn rows are
  laid out). The device and its text are sized to be read at that hold
  (`Handheld.HEIGHT`, `Phone.text_scale`, the first-person zoom and the
  hologram's size, Caleb's feedback); make it readable by size and zoom,
  never by bringing it to the face.
  The other hand hangs at the side while the phone is out
  (`Locomotion.phone_rest`). A new app is an entry in `Phone.APPS` with a line glyph in
  `Phone.AppIcon`. Going online is the Servers app (Caleb's call: no Uplink
  console in the base): it asks `Main` to host, join by address or leave
  (`host_requested`, `join_requested`, `leave_server_requested`) and shows
  `Hub.set_online_status`'s line (`Phone.set_link_status`). Settings are grouped in `Phone.SETTINGS_TABS`, and the dev
  switches live only on the Dev tab.
  Quitting the game is two taps from any page (Caleb's call): the status
  bar's power button (`Phone.PowerButton`) and Settings' System tab both
  go through `Phone.ask_quit`. The first tap arms it for
  `quit_confirm_time` and says what quitting does to the gear carried
  there (`Phone.quit_note`, read from `Main.quit_note`), the second asks
  `Main.quit_game`. Closing the window goes through the same call
  (`auto_accept_quit` is off in a game), so it never skips a solo
  countdown. Solo out in a world `quit_game` leaves the body standing
  as a server would (`Raid.remove_player`, hands off it) and closes once
  the life is settled; asked again meanwhile, it quits at once.
  Settings live in
  `core/settings/game_settings.gd` (its own save file); a server never reads them.
  Each one is a row in `GameSettings.SCHEMA` (its tab, section, kind,
  label, default and range or choices) plus its typed var, and the phone
  draws every tab's settings from that table (`Phone._draw_setting_rows`),
  so a new setting never touches the phone.
- Emotes (DESIGN.md "Emotes", `core/visual/emotes.gd`): picked on the
  emote key's quick wheel (below; they left the watch, Caleb's call), played by the
  controller as the held `ActorCommand.emote` (in the stance's byte,
  `EMOTE_SHIFT`), so they predict and replicate with no message of their
  own, and posed on the one body (`ActionPose.emote`, timed by each view;
  `Locomotion._emote_body` and `emote_pose`), the same in both views. View
  only: nothing in the simulation reads one. Moving, firing, drawing, the
  phone or watch, a vehicle or the air ends one, and starting one puts the
  weapon away (`PlayerController._tick_emote`). A new emote is an
  `Emotes.IDS` entry and a pose; check by eye with `visual_check.tscn --
  <dir> --emotes-only`. The emote key's quick wheel comes up without the
  watch (`PlayerController.open_emote_wheel`, `emote_wheel_open`; the
  mouse picks a slice, `wheel_slice`, and never turns the view while it is
  up), drawn on the visor (`VisorHud._draw_emote_wheel`) or, with no
  working visor, as a hologram from the wrist (`Hud.EmoteHolo`,
  `emote_wheel_holo`), the same in both views. Shortcut keys (DESIGN.md "Shortcut keys") only
  raise the same watch or take out the same phone at an icon or app
  (`PlayerController.watch_shortcut`, `quick_emote`, `Phone.shortcut`),
  never a menu of their own; a new one is an `InputSetup` action and a
  `Phone.CONTROLS` row, and no two actions share a key (a test checks it).
- The phone's pop-ups (`Phone.show_notice`) come one at a time in the order
  sent, never over each other (Caleb's "they stack in random order"): one
  sent while another is up waits (`notices_kept`, the oldest plain one
  dropped past it), the same words are never queued twice, and a `key`
  names news that a newer one replaces, up or waiting, so a stale step or
  update notice is never shown (`drop_notice` takes one down). `first`
  puts one ahead of plain news (the tour's step). While the screen is
  covered between places (`notices_paused`, set by `main.gd`) the one up
  keeps its time. A new kind of news that can go stale sends a key.
- Bug reports (the must-work checklist's "Bug reporting with logs"): the
  phone's Report app (`Phone.report_requested`) hands `Main` a line of
  text, and `core/report/bug_report.gd` (`Main.bug_report`, view and
  client only) bundles it with the build, the machine, where the player is
  (`Main.report_context`, plain values, never a secret) and the game's
  log from this run and the run before (a crashed run's log is found on
  the next launch). It posts that to a Discord webhook as a message with
  the logs attached, at most one every `report_every`, and always keeps a
  copy under `BugReport.SAVE_DIR`. The webhook is never in the code: the
  Windows build of main stamps it into `ares/report/webhook` from the
  repository secret `BUG_REPORT_WEBHOOK` (`windows-client.yml`), and any
  other build only keeps the copy. A new fact worth having in a report is
  a key in `report_context`.
- The new player's tour (`core/progression/onboarding.gd`, static rules on
  a small dictionary in `Profile.onboarding`, run by `main.gd`'s "new
  player's tour" section): a handler contact messages a new player on the
  phone (`Phone.add_local_message`, kept on the phone only, so it works
  offline), one step at a time, and the step's objective is a small line on
  the watch card (`Hud.Wrist.objective`) and the visor glass (`Hud.objective`,
  drawn by `VisorHud._draw_objectives`), never an overlay. A new player
  has no helmet, so the tour also leads through the world (Caleb's "it
  doesn't follow the player"): each step names what it points at
  (`STEPS[i].mark`, `Onboarding.mark`: a weapon on show, the test lane, the
  base's way out, a safe zone's portal by destination, the nearest depot),
  and `main.gd` stands the guide's light on it (`Main.TourGuide`, view only,
  only you see it, through walls), the objective and the distance written
  over it, its column fading as you get close (`_tour_guide_tick`,
  `_tour_mark_at`, looked for again every `TourGuide.LOOK_EVERY`). A step
  done out in a world, seen from where that world is not, leads the way
  there (`_tour_route`): from the base to its way out, from a safe zone to
  the gentle world's gate, that leg written under the step. A step
  with nothing to walk to (raising the watch) says what to press instead,
  on the line under the crosshair while nothing else is offered there
  (`Onboarding.hint`, `Hud.tour_hint`, `BaseHud.tour_hint`). The handler's
  pop-up says the current step only (`_tour_remind`, key `TOUR_NOTICE`), on
  each step and again on arriving in a new place or a new life. Places are
  found through the map contract (`WorldDef`'s "portal", "depot" and
  "outpost" groups), never by world. Steps finish on the
  action itself, reported by `main.gd` as events (`_tour_event`) and as what
  is already true (`_tour_check`), never on a button. It is a view of the
  player's own progress, with one rule (Caleb's call): while it runs a
  full-loot world (gear at risk, not kept on death) is closed
  (`Onboarding.locks`), until the tour is finished or skipped. `main.gd`
  turns every way in back with the handler saying why
  (`_tour_refuses`: the plaza's gates, whose prompt says it is closed
  (`PlazaView.tour_closed`), a squad portal, the watch's portal, joining a
  friend, a solo start). It hands out nothing, and a server never reads
  it, so the lock is the client's (the tour lives in the local profile). It names worlds by what they are (`Onboarding.names`),
  never by id, picking the launch's worlds first (`LaunchScope.worlds`:
  Frostline to learn in, Ashfront for full loot, Caleb's call) in every
  build that has them. A save from before it starts it only if nothing was played or
  equipped. Settings' System tab skips or replays it, and dev mode never
  runs it. A new step is an entry in `Onboarding.STEPS` and an event reported
  where the action happens.
- The game opens in the world, never on a menu screen. Solo it boots into the
  home base; online, joining a server puts you in its plaza, and a world's
  lobby is the home base again on the server's stash. The base's door goes
  straight out to the plaza with no screen (`main.gd head_out`): it joins the
  server it remembers (`Profile.home_server`, set by a join from the phone's
  Servers app) or
  starts one here that runs every world, since worlds are chosen at the
  plaza's gates, never before going online. Travel never strands you on
  the travel screen: a server of your own moves to free ports when an old
  one still holds them (`Main.free_host_port`), stops itself once the game
  that started it stops touching its heartbeat file (`--heartbeat`,
  `HEARTBEAT_STALE`), and is given `HOST_JOIN_DEADLINE` to let you in
  (watched every second, a stopped server noticed at once) before it is
  started once more and then given up on; a deploy that never arrives
  fails after `DEPLOY_TIMEOUT`. Every failed trip ends in `go_home` with
  the reason. `Hub` (`core/ui/hub.gd`)
  is never a main screen: it holds the screens that the base's stations
  (`HomeBase.STATIONS`, sections in `Hub.STATIONS`) show, and the travel
  screen shown while connecting. A new menu feature gets a station (or a
  phone app), not a button on a front screen. `main.gd go_home` is where
  every "back to the menu" path ends.
- Menus live in the world (Caleb's rule: as few flat menus as possible). A
  screen you use goes on a `WorldScreen` (`core/ui/world_screen.gd`): a panel
  in the room that shows a `SubViewport` and forwards the mouse and keys to
  it, with the view moving in to face it while in use. `Main` keeps the hub
  in `hub_screen` and mounts it on the used station's `Station.screen`. Do not
  add full-screen panels or overlays; information about a thing goes on or
  next to the thing (a `Label3D` tag, a sign) or into the phone. The HUD is
  for the crosshair, prompts, hit feedback and brief notices.
  A screen that lists items (the trader and the Concourse's storefronts,
  the locker, the fabricator, insurance, the market kiosk, the records
  board's stash) puts an `ItemCard` (`core/ui/item_card.gd`, view only)
  beside its list: the item pointed at, its model in a small lit window
  that stays still until dragged (`ItemCard.Preview`), its kind, what it
  is for in plain words (`about_text`), its numbers read off its stats
  (`facts`) and the screen's own notes (price, what you are short of).
  A new list hands each row over with `card.track(row, id)`; a new kind
  of item gets a line in `ItemCard.KINDS` and its facts. Check by eye with
  `visual_check.tscn -- <dir> --panels-only`. Those screens wear the
  terminal style (`core/ui/terminal_style.gd`, view only): the station
  screens (`Hub`) and the Concourse's terminals (`Main.ShopView`) set its
  `theme()` on their root, stand on its `Backdrop` (a lit terminal's
  glass: grid, scanlines, a slow sweep, amber corner brackets) and call
  `dress(root)` once built, which lights every title as a heading. Plates
  have cut corners (`TerminalStyle.plate`), amber where you can act, cyan
  where something is shown; a new screen of this kind uses them, never
  plain boxes.
- The watch and the phone split the job (Caleb's rule, revised: the watch no
  longer carries vitals, heat and ammo; see DESIGN.md section 3). Vitals,
  flight heat and ammo are always in view on the visor and the gear (health
  arc, gun display, pack screen), so no key is needed to see them. The
  holographic watch (`Hud.Wrist`, raised with X) is for the things you choose
  to do in action: vehicles, the heavy weapon, artifacts, sign-out, banking,
  the map and pings, landing choices and the pack. The phone is for
  settings, talking to friends and players, and information (news, the war
  feed). A new in-raid action goes on the watch; a new social or info
  feature is a phone app. The watch is a card-sized hologram of icons in
  three tabs (`Hud.Wrist.TABS`, `TAB_SLOTS`, `SLOTS`; DESIGN.md section 3):
  Summon (weapons, vehicles, artifacts, the pack, with the pack's line
  under it; the helmet left the watch once it had its own key, K),
  Status (map, standing) and Mission (portal, contract, sign-out,
  abandon). The Abandon icon (`Hud.abandon_slot`) gives the life up where
  you stand (`Raid.abandon`, online `NetSession.abandon`): fire held on it
  for `PlayerController.abandon_hold` (3 s), from a click that began on
  it (`tick_abandon`), so a stray click never costs a life. Its line says
  what it would cost and what is already banked; it is an empty socket
  wherever `Raid.can_abandon` is false. Emotes
  (the emote key's wheel) and the squad ping (its own key) left the watch
  (Caleb's call): a watch icon must do something no key already does.
  The contract icon is the mission log (Caleb's ask): opened, the wheel
  turns through the tour's step and each contract held
  (`Hud.mission_entries`, `mission_slot`) and a click turns the picked one
  from on the visor's objective block to the main one (first and lit) to
  off it and back (`GameSettings.cycle_mission`, `untracked`,
  `main_mission`: view only, read by `VisorHud.objective_lines`).
  The map icon, while read, draws a small holographic map beside it
  (`Hud.map_marks`, `Card._draw_map`): only what the player is told, never
  other people. The Status icons open with a click like a carousel (Caleb's
  call): the map rises over the card as a tabletop hologram with the
  ground's relief (`Wrist.show_table`, `Hud.map_relief`), the wheel turns
  through the nearest depot, gate outpost and strongpoint, the hot zone,
  the event and the pings (`Hud.map_targets`), and a click sets the picked
  one as a waypoint only you see (`Hud.waypoint`: a column of light, a mark
  on the visor's strip and scope, cleared on arrival); Standing turns
  through three pages (`Hud.STANDING_PAGES`: at stake, safe, this life).
  The pack is an icon on the Summon tab (`Hud.pack_slot`) that opens as a
  list of what is carried with each item's worth; a click on gear in it
  puts it on through the same summon (`PlayerController.take_picked_from_pack`,
  `Loadout.wearable_from_pack`: weapons, helmets, frames, flight rigs and
  ability chips, never an artifact or attachment). `Raid.swap_worn` puts
  on a rig (`Loadout.wear_rig`, on the ground only, keeping the old rig's
  heat, the frame's scaling put back round it) or a chip
  (`Loadout.wear_ability`, starting on its cooldown) as it does a helmet,
  and clients follow through `NetSession._worn_changed`. An opened icon's list or
  page takes the card's right side (`Card._draw_panel`). A click on Sign out starts or cancels it like L
  (`PlayerController.is_on_sign_out`), and its icon carries what this life
  has banked (`Actor.banked_*`, sent to the owner only, `NetSession._banked`).
  Down, the death report's landing choices are picked with the wheel and a
  click (`drop_pick`, `click_landing`); the number keys and Enter still work. The open
  icon shows one short line, and controls are glyphs (wheel, click, key
  cap), never words. Three levels (Caleb's call): raised with X the watch
  is on its tab row (`PlayerController.watch_tabs`), where the wheel turns
  the tabs, the open one's name framed with arrows and the line under the
  row saying what it holds (`Wrist.TAB_LINES`, `Card.tabs`), and a click
  goes into the tab. In a tab the wheel moves across that tab's icons only
  and stops at its ends (`watch_focus`, `step_watch`); turning back to a
  tab lands on the icon last looked at there (`_tab_focus`). A click on an
  icon that holds several things (weapons, toys, artifacts, portal places:
  `watch_entries`) opens it (`PlayerController.watch_open`), the wheel then
  turns through them and stops at the list's ends, and a click acts. A
  right click backs out one level (`back_watch`): a list to its tab
  (`close_watch_icon`), a tab to the tab row, the tab row lowers the
  watch; it never aims. A shortcut key (the map) raises the watch straight
  into its tab. A closed icon shows the click glyph instead of
  the wheel (`Hud.mark_open`). The mouse only looks. While the watch is up the
  wheel never switches weapons. A new watch feature is a new slot on a
  tab, not a new line of text; something that only matters now and then is
  a pop-up line (`Wrist.show_card`'s `popup`), not a slot. The summon
  carousel (Caleb's call) shows only what is carried, never the stash:
  `Hud.weapon_entries` is only the weapons worn (Caleb's call), and gear in
  the pack comes out through the pack's list (`Hud.pack_slot`, which shows
  the watch's rest as a ring): picking a weapon there asks the authority's
  `Raid.summon` (`NetSession.summon`
  online), which swaps it with the one worn in its slot through
  `Loadout.swap_weapon` (the old one goes in the pack with its rounds,
  `Actor.stowed_rounds`; clients copy it from `Actor.weapon_swapped`). It
  takes `Loadout.summon_time` by weight, during which the weapon cannot be
  used (`Actor.materialize_left`) and is drawn digitizing in on the one
  body (`ActorSkin._update_materialize`), then the watch rests
  (`Loadout.summon_cooldown`). A materialize is heard (`Sfx` "summon" and
  "store", played by `ActorSkin._update_materialize`); while the watch
  rests its face breathes amber (`Wrist.resting`), a refused pick buzzes
  and a chime says it is ready. Storing is the summon in reverse: a click
  on the weapon in hand asks `Raid.store` (`NetSession.store` online),
  which puts it in the pack with its rounds at once and starts
  `Loadout.store_weapon` (clients copy it from `Actor.weapon_stored`): the
  weapon fades out of the hand over `Loadout.store_time`
  (`Actor.dematerialize_left`, the same `_update_materialize` light run
  backwards), unusable and with no switching, then `Actor._tick_store`
  takes it off and leaves the hands empty. It needs room in the pack,
  never stores a heavy weapon, and does not rest the watch. At home it
  unequips the slot. Dropping (Caleb's call: a way to be rid of what you
  do not want): on the opened pack list the interact key (its cap is drawn
  beside the wheel, `Hud.key_cap`) drops the picked item instead of
  interacting (`PlayerController.drop_picked_from_pack`), and the watch
  stays on the list. The authority's `Raid.drop_item` (`NetSession.drop`
  online) takes it out of the pack it keeps and lays it at the player's
  feet in a bag anyone may loot, like a dead player's, cleared after
  `WorldDef.bag_lifetime`; drops within `Raid.drop_bag_reach` of the last
  share its bag, and a gun keeps its rounds in the bag
  (`LootContainer.ammo`), so dropping and taking it back never refills it.
  A safe zone, or a world where nothing is at stake (`gear_at_risk` off),
  refuses it (`Hud.can_drop_here`), so dropping is never a way to trade.
  The squad ping (`Raid.ping`, `pinged`) goes
  only to the pinger's side, like a visor tag. In third person the
  card rises off the worn watch with a glow on the arm (Caleb's feedback):
  it stands just past the character (`Wrist.tp_depth`, `tp_behind`), so the
  body passes in front of it and it reads as coming from the watch, beside
  the head clear of the crosshair, a third of the view tall, backed but still see-through (a hologram, Caleb's call)
  (`_tp_spot`, `_tp_size`, `tp_backing`); the arm and its
  pose stay the same, only where the light lands differs. It stays close to the body
  (Caleb's feedback): its lower edge sits just over the watch as the camera
  sees it (`_over_wrist`, `tp_over_wrist`), level with the shoulder, and
  only its bare right margin may tuck behind the head (`tp_tuck`), never
  its text, so the light rises from the wrist up into the card,
  with bands running out along it (`Wrist.BEAM_SHADER`, `_draw_beam`),
  never slanting down into it (Caleb's feedback). The weapon and toy
  holograms over the card are drawn at `tp_rows` of their first-person size
  and lifted by as little, smaller still where the top of the view is near
  (`_tp_row_scale`), so they stay in frame while the card keeps its size
  (Caleb's feedback). Vitals go on the card only where there is no visor
  to show them (no helmet). The watch works in the home base
  too (`BaseHud.wrist`), its card saying what each icon holds for the next
  deploy (`Hud.base_watch_slots`), and there its Summon tab is the whole
  collection (Caleb's call): every weapon and vehicle owned
  (`HomeBase.watch_weapons`, `watch_vehicles`). A vehicle thrown at home
  unpacks to be ridden in the base (`HomeBase.throw_toy`, `pack_vehicle`;
  `Vehicle.local_only`, since no server runs it) and a weapon picked is
  equipped through `equip_requested`. Out in a world summons work
  everywhere, the plaza included. Raised, the wrist comes up in front of
  the model's eyes as the camera has them (`WeaponArm.watch_point`, from
  `ActorSkin.eye_point`, so it stays put on the run and in view crouched),
  close enough to stay in the arm's reach, so it is in view in
  first person wherever you look, and the forearm rolls so the face, worn
  on the back of the wrist (`Hud.Wrist.FACE_AXIS`, out on the skin by
  `wrist_skin` and depth tested like anything worn, so a gun or hand in
  front of it hides it), looks at the eyes
  (`WeaponArm._face_watch`). From the eyes the card opens just over the
  face, sized to read like a card at arm's length (`fp_card_reads_at`). Check it by eye with
  `visual_check.tscn -- <dir> --watch-only` (`--base-watch-only` for just
  the base).
- The launch scope (`docs/systems/launch-scope.md`) hides the phone's
  Racing app and the "Invite to base" button, and leaves the artifact icon
  off the watch: ask `Hud.Wrist.row(tab)` and `tab_line`, never `TAB_SLOTS`
  directly, for the icons a tab shows.
