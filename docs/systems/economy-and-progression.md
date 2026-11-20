# Economy and progression

Rules for bounties, mastery, the scrap kit, safety nets, crafting, money, scrip, contracts, the market and cosmetics. These are part of the rules in `CLAUDE.md` that must not be
broken: read this file before changing anything it covers, and keep it up to
date in the same PR.

- A player's bounty pays its killer in scrip (`Economy.bounty_scrip`, one
  for one, Caleb's call) into the life's carried scrip, so it is at stake
  until banked or carried out, like the kill's own pay. Where deaths drop
  scrip piles it goes into the dead player's pile instead (a bounty pile,
  `LootContainer.bounty`), for whoever grabs it.
- Mastery (`core/progression/`) is keyed by gear type tags ("rifle", "blink",
  "frame_heavy"), never by item id. Variants are sidegrades: every one trades a
  strength for a weakness, and death never takes mastery away. Variant picks go
  into `Raid.start` alongside the kit; `Raid` never reads them from `Profile`.
- `starter`-tagged items are the free scrap kit. They never enter the stash:
  every player owns one of each piece that goes in a slot
  (`StashRules.free_items`, `equippable`), equipped like any other gear and
  shown in their own base. An empty loadout slot is bare (Caleb's call:
  you can go fully bare, clothes aside): nothing fills it on a deploy, in
  the base or in the arena, and a kit of nothing is `[Loadout.BARE]`,
  because an empty kit still means the world's scrap kit to
  `Raid.add_player`. Only lost gear falls back to its scrap piece
  (`StashRules.validate_loadout`). A new player starts with nothing
  equipped (`StashRules.new_player_loadout`, Caleb's call): no weapons,
  armor or helmet, and puts everything on by hand the first time (the
  welcome crate and the scrap pieces wait in the base). A save without
  `StashRules.BARE_KEY` is from before the bare rule and gets its empty
  slots filled once with the scrap kit (`StashRules.starter_loadout`).
- Safety nets (`core/economy/safety_nets.gd`, static rules like `Economy`,
  DESIGN.md "Safety nets"): salvage and one insured item, decided by the
  authority's `Raid` at a death and nowhere else. `add_player`'s
  `p_insured` (from `StashService.deploy`'s "insured", or
  `Profile.insured_in` solo, and only if the kit carries it) is recalled
  from the body before the bag drops (`Raid._recall_insured`), never
  copied: the killer simply does not get it. Salvage is paid only for
  crafted gear from the stash lost with the body. Both travel in the
  result ("recalled", in `brought_home` too, "salvaged", "salvage") and are
  settled by `StashService.settle` online and `Raid.apply_result` solo; a
  policy is kept on the account (`Account.insurance`, in the snapshot and
  `StashRules.CARRIED`) and changed only by `StashService.insure`.
- Blueprints and crafting (`core/progression/crafting.gd`, static rules like
  `Economy`, DESIGN.md section 10). A blueprint is an item tagged
  "blueprint": loot while carried, learned when it reaches a stash
  (`Crafting.learn` moves it to the account's known list:
  `Profile.blueprints` solo, the account's online, in the snapshot), and
  never lost after that; a spare copy stays in the stash as a trade good.
  Anything that hands an account items must go through
  `Profile.add_to_stash` or `StashService.Account.add_items`, never append
  to a stash, or a blueprint is stored instead of learned. A recipe
  (`Crafting.RECIPES`) makes one item from a known blueprint for scrip,
  parts and, for a higher Mk, the item `upgrade_data`; what it makes is
  ordinary gear. Crafting is done at the fabricator on the gunsmith bench
  (`HomeBase.CraftConsole`, the hub's "craft" section, `craft_panel.gd`):
  `Profile.craft` solo, `NetSession.craft` online, where only
  `StashService.craft` decides. Each world has its own job (DESIGN.md
  "Frostline"): the war's blueprints and most upgrade data come from the PvP
  world (`WorldDef.roll_crafting_loot` and its chances, 0 by default; a
  world's own loot tables), while the expedition world pays the parts every
  Mk2 and Mk3 needs (`Crafting.MK2_PARTS`, `MK3_PARTS`: Cryo Core, Glacial
  Alloy, Engine Coil), a trickle of upgrade data and its own blueprints,
  tagged "expedition", which make new options only, never a higher Mk, and
  which `roll_crafting_loot` never hands out. Its slow route to the war's
  blueprints (Caleb's call) is rare: the relay's `roll_crafting_loot` at a
  low chance, its warlords' `warlord_blueprint_chance` and the expedition
  weeklies' blueprint. Cold-weather gear is data: a
  frame's "insulation" stat keeps out that share of the cold
  (`Raid.insulation_of`). A new craftable is a recipe row and, if it needs
  one, a `_blueprint` item. Costs are placeholders.
- Money (`core/economy/`): the rules live once, in `economy.gd` (static, like
  `StashRules`), shared by `Profile` and `StashService`. Online, `scrip`
  lives on the server's account and only changes there: through
  `StashService.buy` / `sell`, the payout in `settle`, or `change_scrip`
  for other server systems. A client never sends a price or an amount.
  Shops are tag-driven: an item is stocked if it has the `vendor` tag and one
  of the shop's tags (`shop_db.gd`), and `Economy.is_shop_item` refuses
  anything above Uncommon, so rare gear stays loot-only. The one exception
  is the plaza's back room (`Economy.BLACK_MARKET`, a shop with "stall" in
  `ShopDB`, built down an alley by the plaza map's `_build_stall`): two
  Rare pieces a day by the date (`black_market_stock`) at
  `BLACK_MARKET_MARKUP` times their value; every price a shop charges is
  `Economy.price_in(shop_id, id)`. Keep every sell
  price below its buy price, and keep run payouts small next to loot: scrip
  must come from getting loot home, so full loot stays the stake.
- Scrip is what a life pays, and it is at stake. The `Raid` pays it
  (`_pay_scrip`, amounts in `Economy`) into `PlayerState.scrip`, copied to
  `Actor.scrip` for views. A death moves it into the bag
  (`LootContainer.scrip`); a depot moves it to `scrip_banked`. It reaches an
  account only through the result (`scrip`, `scrip_banked`) and
  `Economy.payout`, never directly, and nothing is paid for kills alone.
- Contracts (`core/economy/contracts.gd`, static rules like `Economy`): the
  board's jobs are data in `Contracts.JOBS`, offered by the date so every
  machine agrees, and held on the online account (`Account.contracts`, in the
  snapshot); only the server takes, drops, rerolls (`StashService.contract`,
  asked with `NetSession.contract_ask`) and pays them, in `settle`. A life's
  counters are the `Raid`'s (`_count`, authority only, never in a safe zone
  or where gear is not at stake) and travel in the result's `tally`; the
  owner's copy for the watch is `Actor.tally`. Only a sign-out counts, and no
  job may count player kills or reward signing straight out. A new job is a
  `JOBS` entry; a new stat is a `_count` call where the event happens.
  A world adds jobs of its own with `WorldDef.contract_jobs` under its
  `WorldDef.contract_tag` (Frostline's "expedition"): every lookup goes
  through `Contracts.jobs()`, never `JOBS` alone, the board offers one daily
  and one weekly per tag beside the general ones, and a tagged job counts
  only a result whose "contract_tag" matches (`Contracts.counts_in`). Stats
  include `item:<id>` (brought home), `kills:<faction>`, `bosses` (and
  `boss:<kind>`, by its "boss" meta, for a job that names one boss),
  `cache:<source>` (once per fill, `LootContainer.looted_by`), `banks` and
  `hold_seconds` (stood in a site your side holds, `Raid._count_holding`;
  Ashfront's "warzone" jobs).
- The player market (DESIGN.md section 10, "Two worlds, one loop"): rules
  once in `core/economy/market.gd` (static, like `Economy`: what trades, the
  price band, fees, the daily cap; Mk3, heavy weapons, artifacts and relics
  never trade), the board in `core/economy/market_service.gd`, shared by
  every session of a server like the `ClanService` (`NetSession.market`).
  It moves goods only through six ledger calls on the `StashService`
  (`count_of`, `scrip_of`, `take_items`, `give_items`, `change_scrip`, and
  `transaction`, which every listing charge and every sale goes through so
  no trade is half done); it never writes an account itself. On official
  servers the board runs inside the account service, beside those accounts
  (`AccountService.market`), and a session only passes the request on. Listed items are held by the
  board, its file is written before the accounts' transaction so a crash
  can lose a listing but never copy one, and
  a client only asks (`NetSession.market_ask`) from the Exchange kiosk in
  the plaza and shows `market_state`. Trading needs a safe zone and no
  deploy; there is no solo market.
- Furniture (`furniture`, small pieces also `decor`) and clothing
  (`cosmetic`, with an `outfits` stat of customizer outfit ids) are ordinary
  stash items that fit no loadout slot, so they never go on a raid.
  `Economy.unlocked_outfits(stash)` lists the outfits a stash unlocks.
