# Starling Visuals 3.1

Starling Visuals is Starling's own shader pack for Minecraft on a phone, written in the Iris /
OptiFine `shaders/` format. Version 3.1 finishes the job 3.0 started: no ordinary block is left
pale or white, the edge pass costs half the fetches, and a `POTATO` profile gives a weak phone
the most frames it can make. The cinematic lens, sky, water and lighting stack stay.

The pack ships inside the Starling APK as `assets/StarlingVisuals.zip`; this repository is the
standalone source and the release download.

## What is new in 3.1

- **Obsidian and pumpkin are their own colours again.** The white was not the film curve this
  time: it was the emissive id. Some clients (Horizon, Starling's own) give a shader an id per
  *sprite layer*, not per block, and two glowing blocks reuse a plain block's sprite — the
  beacon's base is `block/obsidian`, and the jack o'lantern's side and top are
  `block/pumpkin_side` and `block/pumpkin_top`. Those sprites carried the cold-light id, so
  every obsidian block and every pumpkin emitted light and washed out. Neither block carries
  an emissive id any more, and `lit.glsl` now gates emission on the texture's own brightness:
  a dark texel emits nothing, so a black block can never be lifted to grey by an id again.
- **Half the edge-pass fetches.** The edge-aware smooth and the unsharp mask both read the same
  four neighbours; they are one pass now, four fetches instead of eight on `HIGH` and `ULTRA`,
  with the same picture.
- **The sun is looked up once per pixel.** The highlight, the light through a leaf and the
  water's path all reused `sunDir()`, `sunlight()` and `moonlight()`; they now share one lookup.
- **`POTATO`.** A fourth profile below `LOW` for the frame rate: no post at all, no emission,
  no waves or wind, a 512 shadow map and 32 blocks of shadow. `Auto` ranks it lightest and
  picks it when even `LOW` is too much.
- **The block outline stays black** and every include still resolves.

## What is new in 2.1

- **The white-block bug is fixed.** The old specular returned the peak of a Blinn-Phong lobe
  (about four) times a full sun's irradiance, so every top face at noon sat inside the highlight
  and clipped. The lobe is now Fresnel-weighted (4% head-on, strong only at a grazing look) and
  the emissive blocks emit from their own texture with a small, bounded amount instead of a
  large flat constant. Glowstone, lava, fire, sea lanterns and redstone keep their colour and
  roll into the film curve instead of becoming a sheet of white.
- **The block outline is black.** `gbuffers_basic` was shipped pointing at a `program/basic.glsl`
  that did not exist, so any client that draws basic geometry (the block outline, debug lines)
  got a broken program. The program now exists and is unlit: it never samples the block atlas,
  and a black basic vertex (the outline) is written opaque, so the film curve cannot lift it to
  white. `tools/check_includes.py` and CI now fail if an include is missing again.
- **The lens has a real black point.** The default curve is ACES (Stephen Hill's RRT + ODT fit)
  with a soft filmic and an extended Reinhard alternative. Midtones are no longer lifted to
  grey, the top of the range desaturates like film instead of clipping, and bloom uses a soft
  knee.
- **Cheaper on a phone.** The shadow edge is two taps (one on LOW) instead of four; the bloom is
  eight fetches instead of twenty; the rays test two points before the loop and skip most of the
  screen; SSAO fades out past 26 blocks; the Fresnel edge and the sun's highlight moved to the
  vertex stage (every face is flat); the sky's night noise is 2D (four hashes, not eight); the
  haze uses one cheap sky sample instead of a full directional one per pixel.
- **A better sky.** A two-lobe Mie sun with a tight aureole, a warm low-sun horizon, the moon's
  cool halo, and the same two star layers, milky way and aurora for less.
- **Better water.** A Fresnel reflection of the average sky, a sun/moon path with a tight and a
  broad lobe, the shore foam, the depth body colour and rain chop, all shadowed.
- **A smoother frame.** A light edge-aware smooth for distant blocks and leaves, a gentler
  unsharp mask, a restrained teal-and-amber grade, vignette, animated grain and a final dither.
- **Wet surfaces.** Rain darkens upward faces a little and the Fresnel highlight gets stronger,
  so wet stone and wet grass read as wet without a second material pass.
- **A polished material.** Ice, snow, glass, quartz, copper and the metal blocks have their own
  gloss (`block.10007`) for a tighter highlight.
- **Profiles that the game can rank.** `LOW`, `HIGH` and `ULTRA`; Auto reads what each asks of
  the options, not the names, and picks `HIGH` on a strong phone and `LOW` on a weak one.

## Profiles

| Profile | What it is for | What it turns off or down |
| --- | --- | --- |
| `POTATO` | the most frames a phone can make | everything `LOW` turns off, plus emission, water waves, wind, the held light and the grade; 512 shadow map, 32 block shadows, 1 shadow tap |
| `LOW` | a weak phone, or a long battery | contact shadows, rays, glow, highlights, stars, aurora, edge smooth, sharpen, vignette, grain; 512 shadow map, 32 block shadows, 1 shadow tap, 4 SSAO taps, 6 ray samples |
| `HIGH` | the default and what Auto picks on a strong phone | nothing; 1024 shadow map, 64 block shadows, 2 shadow taps, 6 SSAO taps, 8 ray samples |
| `ULTRA` | a tablet or a PC | 2048 shadow map, 96 block shadows, 4 shadow taps, 10 SSAO taps, 12 ray samples, wider softness |

Choose **Auto** on the Shader Packs page and the game limits the shadow map and distance to what
the device can pay for, then loads the profile it ranked for that device. Choose a profile by
name to override the device's choice.

## Install

Copy `StarlingVisuals.zip` into the game's `shaderpacks/` folder (Options > Video Settings >
Shader Packs > Open Pack Folder), then pick **StarlingVisuals.zip** and set its profile to
**Auto**. On a phone the pack is already there when Starling puts a new version in
`shaderpacks/`; a pack the player deleted stays deleted until an update brings a new one.

## Build and check

```sh
python3 tools/check_includes.py   # every include resolves, every gbuffers stage is paired
bash build.sh                     # dist/StarlingVisuals.zip
HORIZON_REPO=../minecraft bash check.sh
```

`check.sh` builds Starling's `pack_report` example and runs every program of the pack through
the real reader, writes every module with the SPIR-V writer wgpu uses on Vulkan, then repeats
with every switch on and off and every value at its highest and lowest. A pass is:

```text
== dist/StarlingVisuals.zip: 13 translate, 0 fail, 1 unused
   profiles, lightest first (what Auto reads): LOW -13.5, HIGH 0.0, ULTRA 3.9
   spir-v: 34 modules, 0 errors, 0 panics
```

The one unused program is `gbuffers_basic`, which the Starling client does not draw itself but
Iris and OptiFine use for the block outline; it translates, and the check above also loads it as
the sky fallback so a broken basic cannot ship again.

## A note on realism

Minecraft's world is made of one-metre cubes with 16x16 textures and no per-pixel material maps.
A shader pack can add light, air, water, shadow and lens behaviour, and this one does; it cannot
turn that geometry and those textures into the asset density, motion and art direction of a
modern open-world game. The aim is a coherent, filmic Minecraft, not a claim to be another game.

## Licence

MIT, like Starling. The original pack and this version are in `LICENSE`.
