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
| `assets/characters` `Character` `Enemy_*` | Cyberpunk Game Kit | Quaternius | CC0 1.0 | https://quaternius.com/packs/cyberpunkgamekit.html |
| `assets/weapons` `AR_*` `SMG_*` `Sniper_*` `Pistol_1` | Sci-Fi Modular Gun Pack | Quaternius | CC0 1.0 | https://quaternius.com/packs/scifimodularguns.html |
| `assets/weapons` `Shotgun_1` `Knife` `Axe` | Survival Pack | Quaternius | CC0 1.0 | https://quaternius.com/packs/survival.html |
| `assets/props` (most files) | Cyberpunk Game Kit | Quaternius | CC0 1.0 | https://quaternius.com/packs/cyberpunkgamekit.html |
| `assets/props` `Backpack` `GasCan` `PropaneTank` `Trashcan` `Tent` `Bonfire` | Survival Pack | Quaternius | CC0 1.0 | https://quaternius.com/packs/survival.html |
| `assets/props` `Streetlight_*` `TrafficLight` `Sign_Stop` | Modular Streets Pack | Quaternius | CC0 1.0 | https://quaternius.com/packs/modularstreets.html |
| `assets/props` `Wreck_Tank` | Animated Tanks Pack (`Tank.glb`, renamed) | Quaternius | CC0 1.0 | https://quaternius.com/packs/animatedtanks.html |
| `assets/textures` | Asphalt021, Bricks066, Concrete012, Ground037, Metal063, Road001 (resized from 2K to 1K) | ambientCG | CC0 1.0 | https://ambientcg.com |
| `assets/sky` | kloppenheim_06_puresky (2K HDRI) | Poly Haven | CC0 1.0 | https://polyhaven.com/a/kloppenheim_06_puresky |
| `assets/fonts` | Rajdhani SemiBold | Indian Type Foundry | SIL OFL 1.1, see `assets/fonts/OFL.txt` | https://github.com/google/fonts/tree/main/ofl/rajdhani |

Shaders in `assets/shaders` were written for this project.

## Where the files were fetched from

The build machine could not reach the authors' sites, so the files were taken
from public GitHub mirrors that redistribute them unchanged under the same
license. The license terms are the authors' own, linked above.

- Quaternius models: https://github.com/trebeljahr/quaternius-showcase
  (commit c06a6fa), which lists each pack's license in its `LICENSES.md`.
- ambientCG textures and the Poly Haven sky:
  https://github.com/petroulacl/fps-buildings-env-kit (commit 1dd8e93).
- Rajdhani: https://github.com/google/fonts

CC0 1.0: https://creativecommons.org/publicdomain/zero/1.0/
