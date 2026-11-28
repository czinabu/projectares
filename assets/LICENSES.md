# Asset licenses

Everything in `assets/` comes from free packs under permissive licenses. All
3D models, textures and skies are CC0 1.0 (public domain): no attribution is
required, and they can ship in a commercial game. The font is under the SIL
Open Font License. Credit is given here anyway.

Only add assets whose license allows redistribution in a public repository,
and add a row for each new source.

| Folder | What | Author | License | Source |
| --- | --- | --- | --- | --- |
| `assets/characters` `George` `Leela` `Mike` `Stan` | Animated Mech Pack | Quaternius | CC0 1.0 | https://quaternius.com/packs/animatedmech.html |
| `assets/characters` `Enemy_*` | Cyberpunk Game Kit | Quaternius | CC0 1.0 | https://quaternius.com/packs/cyberpunkgamekit.html |
| `assets/characters/humans` `rig_m` | Ultimate Modular Men (`Swat` repacked as GLB with its animations; kept only as the source `tools/human_rig` carries the game's own clips from) | Quaternius | CC0 1.0 | https://quaternius.com/packs/ultimatemodularcharacters.html |
| `assets/characters/humans` `rig_f` | Ultimate Modular Women (`Soldier`, repacked and kept the same way) | Quaternius | CC0 1.0 | https://quaternius.com/packs/ultimatemodularwomen.html |
| `assets/characters/humans` `body_m` `body_f` and their textures | Universal Base Characters, Standard (`Superhero_Male` and `Superhero_Female` with the pack's hairstyles and eyebrows, rebuilt by `tools/human_rig` with textures shrunk to 2048 and 1024) | Quaternius | CC0 1.0 | https://quaternius.itch.io/universal-base-characters |
| `assets/characters/humans` `body_m` `body_f` (animations) | Universal Animation Library, Source tier (bought; the Unreal-Godot `UAL1.glb`), and Universal Animation Library 2, Source tier (bought; `Unreal-Godot/UAL2.glb`) (clips carried onto the bodies by `tools/human_rig`) | Quaternius | CC0 1.0 | https://quaternius.itch.io/universal-animation-library |
| `assets/characters/humans/ubc_source` (Regular male and female, heads, hairstyles, beards, textures; unedited glTF exports, hashes match the source copy) | Universal Base Characters, Source tier (bought by Quaternius's customers, re-shared with its own `License_Source.txt`, CC0 1.0 Universal) | Quaternius | CC0 1.0 | https://quaternius.itch.io/universal-base-characters |
| `assets/weapons` `AR_*` `SMG_*` `Sniper_*` `Pistol_1` | Sci-Fi Modular Gun Pack | Quaternius | CC0 1.0 | https://quaternius.com/packs/scifimodularguns.html |
| `assets/weapons` `Shotgun_1` `Knife` `Axe` | Survival Pack | Quaternius | CC0 1.0 | https://quaternius.com/packs/survival.html |
| `assets/weapons` `Sword` `Hammer` | Modular Weapons Pack (`Sword.glb`, and `Hammer_Double.glb` renamed) | Quaternius | CC0 1.0 | https://quaternius.com/packs/medievalweapons.html |
| `assets/weapons` `Katana` | Animated Knight Pack | Quaternius | CC0 1.0 | https://quaternius.com/packs/knightcharacter.html |
| `assets/props` (most files) | Cyberpunk Game Kit | Quaternius | CC0 1.0 | https://quaternius.com/packs/cyberpunkgamekit.html |
| `assets/props` `Backpack` `GasCan` `PropaneTank` `Trashcan` `Tent` `Bonfire` | Survival Pack | Quaternius | CC0 1.0 | https://quaternius.com/packs/survival.html |
| `assets/props` `Streetlight_*` `TrafficLight` `Sign_Stop` | Modular Streets Pack | Quaternius | CC0 1.0 | https://quaternius.com/packs/modularstreets.html |
| `assets/props` `Wreck_Tank` | Animated Tanks Pack (`Tank.glb`, renamed) | Quaternius | CC0 1.0 | https://quaternius.com/packs/animatedtanks.html |
| `assets/textures` | Asphalt021, Bricks066, Concrete012, Grass007, Ground031, Ground037, Ground079L, Ground098, Ground110, Ice001, Metal063, Road001, MetalPlates015A, Rock051, Rock060, Snow008A, Snow008C (Color and NormalGL only, resized to 1K) | ambientCG | CC0 1.0 | https://ambientcg.com |
| `assets/sky` | kloppenheim_06_puresky (2K HDRI) | Poly Haven | CC0 1.0 | https://polyhaven.com/a/kloppenheim_06_puresky |
| `assets/sky` | qwantani_dusk_1_puresky (2K HDRI, the Concourse's dusk) | Poly Haven | CC0 1.0 | https://polyhaven.com/a/qwantani_dusk_1_puresky |
| `assets/fonts` | Oxanium (variable, the title screen and splash), license in `assets/fonts/OFL-Oxanium.txt` | Severin Meyer | SIL OFL 1.1 | https://github.com/google/fonts/tree/main/ofl/oxanium |
| `assets/fonts` | Rajdhani SemiBold | Indian Type Foundry | SIL OFL 1.1, see `assets/fonts/OFL.txt` | https://github.com/google/fonts/tree/main/ofl/rajdhani |

`assets/branding` (the placeholder logo: `icon.png`, `icon.ico`, `splash.png`) was made for this project by `assets/branding/make_logo.py` and is CC0; the splash sets its name in Oxanium.

## Sounds

| Folder | What | Author | License | Source |
| --- | --- | --- | --- | --- |
| `assets/sounds` (not in this repository, see its `README.md`) | Clips from Extreme Winds Vol. 1 (344 Audio), Sci-Fi Drones (Cinematic Sound Design) and Effective Trailer Booms Vol. 2 (Federico Soler), cut, filtered and looped | Sonniss #GameAudioGDC 2026 bundle | Sonniss GDC bundle license: royalty-free, commercial use, no attribution; may ship inside the game but not be sold or handed out as they come | https://gdc.sonniss.com |

| `assets/sounds/world` (`step_*`: footsteps on hard ground, dirt, snow, grass and wood; `engine_*`: the ground, hover and air engine loops) | Impact Sounds (`footstep_*`) and Sci-Fi Sounds (`spaceEngineLow_004`, `spaceEngineSmall_002`, `spaceEngineLarge_002`), cut, mixed (the dirt steps are the concrete taps dulled with a little of the grass under them), made mono and crossfaded into loops by `assets/sounds/world/make_world_sounds.py` | Kenney (www.kenney.nl) | CC0 1.0 | https://kenney.nl/assets/impact-sounds, https://kenney.nl/assets/sci-fi-sounds (fetched from the GitHub mirror `series-ai/jam-ready-assets`, which carries each pack's CC0 `License.txt`) |

`assets/sounds/world/wind_cold.ogg` (Frostline's wind) and `music_plaza.ogg` (the start screen, home and the Concourse's music) were made for this project from code by `assets/sounds/world/make_world_sounds.py` and are CC0: no samples, nothing to credit.

`assets/sounds/weapons` (every gun's shots, the hit and kill confirms, draws, the rail's charge and the rotary cannon's spin) was made for this project from code by `assets/sounds/weapons/make_weapon_sounds.py` and is CC0: no samples, nothing to credit.

Shaders in `assets/shaders` were written for this project.

## Code libraries

| Folder | What | Author | License | Source |
| --- | --- | --- | --- | --- |
| `addons/godot-sqlite` | godot-sqlite 4.7 (GDExtension, release builds for Windows, macOS and Linux x86_64 only), used by the server's account store | Piet Bronders & Jeroen De Geeter | MIT, see `addons/godot-sqlite/LICENSE.md` | https://github.com/2shady4u/godot-sqlite (tag `v4.7-assetlib`) |

## Where the files were fetched from

The build machine could not reach the authors' sites, so the files were taken
from public GitHub mirrors that redistribute them unchanged under the same
license. The license terms are the authors' own, linked above.

- Quaternius models: https://github.com/trebeljahr/quaternius-showcase
  (commit c06a6fa), which lists each pack's license in its `LICENSES.md`.
- Quaternius human packs (with their animations and the pack's CC0 `License.txt`): https://github.com/osman-1002/3D-3rd-Person-Godot-Game-With-GenAI-Integration at commit `108740b`, under `addons/`
- ambientCG textures and the Poly Haven sky:
  https://github.com/petroulacl/fps-buildings-env-kit (commit 1dd8e93).
- Universal Base Characters Source glTF exports: https://github.com/slopwarefactory/terra (`art/characters/quaternius/universal-base-characters`, files fetched through Git LFS and checked against its `SHA256SUMS`; `License_Source.txt` kept beside them).
- Rajdhani: https://github.com/google/fonts
- MetalPlates015A (Color, NormalGL, Roughness) and the qwantani_dusk_1_puresky sky were downloaded straight from ambientCG and Poly Haven.

CC0 1.0: https://creativecommons.org/publicdomain/zero/1.0/
