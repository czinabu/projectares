# Putting Verge on Steam

Everything that can be ready before the Steamworks fee is paid is in the
repo: the Steam export presets, the upload workflow and draft legal pages.
This is the list of what is left once Caleb pays the fee, in order.

## What is already built

- **Two export presets**, "Windows Steam" and "Linux Steam" (`export_presets.cfg`).
  - They are the release build: they carry the feature tag "playtest", so
    the launch scope applies (`docs/systems/launch-scope.md`).
  - They also carry the tag "steam".
  - They export to `build/steam/windows/Verge.exe` and
    `build/steam/linux/Verge.x86_64`, each with its pack beside it.
- **No self-update in a Steam copy.** `Updater.on_steam` sees the "steam" tag,
  or the `SteamAppId` that Steam sets when it launches a game, and keeps the
  updater off. Steam updates the game itself, and a pack swapped in under it
  would fail Steam's file check.
- **The upload workflow**, `.github/workflows/steam.yml`.
  - It runs by hand only: Actions > Steam build > Run workflow.
  - It exports both presets and keeps them as a workflow artifact.
  - Once the settings below exist, it also uploads both depots with SteamCMD
    (`.github/steam/*.vdf`).
  - To set the build live, type a Steam branch name, such as `beta` or
    `default`, in the "live" box.
- **Draft privacy policy and terms**, `docs/legal/`. These are drafts that
  someone should read over before they are published.

## What is left, once the fee is paid

1. **Join Steamworks** at partner.steamgames.com. This is the $100 app fee,
   plus Valve's tax and bank forms. Valve holds a new app for about 30 days
   before it can be released, so pay at least a month before launch day.
2. **Set up the app.** In the Steamworks app settings:
   - Make it Windows and Linux, 64-bit.
   - Add two depots, one for Windows and one for Linux.
   - Launch options: `Verge.exe` for Windows and `Verge.x86_64` for Linux.
3. **Make a build account.** Create a second Steam account just for uploads,
   with only "Edit App Metadata" and "Publish App Changes To Steam" rights.
   On any computer, run `steamcmd +login <that account> +quit` once and type
   the Steam Guard code. Then base64 the `config/config.vdf` it wrote.
4. **Add the settings to GitHub.** In the repository settings:
   - **Variables:** `STEAM_APP_ID`, `STEAM_DEPOT_WINDOWS` and
     `STEAM_DEPOT_LINUX`.
   - **Secrets:** `STEAM_USERNAME`, and `STEAM_CONFIG_VDF` (the base64 text).
5. **Do a test upload.** Run the workflow with "live" set to `beta`, and
   check that it installs and runs from Steam's beta branch.
6. **Make the store page.** It needs:
   - capsule art in Steam's sizes
   - at least five screenshots
   - a trailer
   - the description, from the pitch doc
   - the Early Access questions ("Why Early Access?" and so on), answered
     from `docs/launch-checklist.md`
   - the content survey and age rating
7. **Link the legal pages.** Publish the privacy policy and terms somewhere
   public, such as GitHub Pages, and link them on the store page.
8. **Release.** Valve reviews both the store page and the build first, which
   takes a few days each.

## Not done yet

- **Steam login.** Accounts are still a name plus a secret the game makes. A
  Steam sign-in is the "Steam login" row in `docs/design-gaps.md`. It's
  Caleb's call whether it comes at launch or a few weeks after.
- **The Steam overlay and achievements.** Both need GodotSteam (MIT), which
  can be added when Steam login is.
- **Bug reports from Steam builds.** The Steam workflow does not stamp the
  bug report webhook yet, so reports from a Steam copy stay on the player's
  computer.
