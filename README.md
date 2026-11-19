# Starling Visuals 2

Starling Visuals is Starling's own shader pack for Minecraft on a phone, written in the Iris /
OptiFine `shaders/` format. Version 2 is a full pass over the look and the cost: more of the
world is lit and shaded, the night sky has depth, the air and the lens have their own character,
and the whole pack is a ladder of three profiles so the game can pick the right one for the
device automatically.

The pack ships inside the Starling APK as `assets/StarlingVisuals.zip`; this repository is the
standalone source and the release download.

## What is new in 2

- **Contact shadows (SSAO).** Depth-only, eight taps, narrow enough to seat a fence post on the
  ground and darken the inside of a corner; off in the Low profile.
- **Surface highlights.** A sun/moon highlight on stone, ice, metal and wet ground, stronger in
  rain and after it, with a gloss that follows the block's material id.
- **Wind.** Grass and leaves move in the world and in their shadows, on the same phase, so a
  leaf's shadow moves with the leaf.
- **Emissive blocks.** Glowstone, sea lanterns, fire, lava, lanterns, redstone and the rest add
  their own light to their texture instead of only through the lightmap.
- **Better water.** Four travelling wave sets plus rain chop, a Fresnel reflection of the sky, a
  shore foam edge, the moon's path at night, and a depth-based body colour.
- **A night sky with depth.** Two layers of procedural stars, a faint milky way, a cool moon, and
  an optional aurora curtain low in the north.
- **Underwater.** Caustics on the bottom and in the water volume, with the eye's own tint.
- **Air and light.** Height fog with sun in-scattering, a broader sun halo, and a haze that knows
  whether the eye has sky above it.
- **A lens.** ACES / soft AgX / Reinhard tone curves, a restrained teal-and-amber grade, a small
  unsharp mask, a vignette, animated grain and a final dither so the night sky does not band.
- **Profiles that the game can rank.** `LOW`, `HIGH` and `ULTRA`; Auto reads what each asks of
  the options, not the names, and picks `HIGH` on a strong phone and `LOW` on a weak one.
- **A deterministic 256x256 noise texture** for the dithering and the rays, instead of hiding a
  random pattern in the shader.

## Profiles

| Profile | What it is for | What it turns off or down |
| --- | --- | --- |
| `LOW` | a weak phone, or a long battery | contact shadows, rays, glow, highlights, stars, aurora, sharpen, vignette, grain; 512 shadow map, 32 block shadows, 4 SSAO taps |
| `HIGH` | the default and what Auto picks on a strong phone | nothing; 1024 shadow map, 64 block shadows, 8 SSAO taps, 12 ray samples |
| `ULTRA` | a tablet or a PC | 2048 shadow map, 96 block shadows, 12 SSAO taps, 16 ray samples, wider softness |

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
bash build.sh                 # dist/StarlingVisuals.zip
HORIZON_REPO=../minecraft bash check.sh
```

`check.sh` builds Starling's `pack_report` example and runs every program of the pack through
the real reader and both backends, then repeats with every switch on and off and every value at
its highest and lowest. A pass is:

```text
== dist/StarlingVisuals.zip: 13 translate, 0 fail, 1 unused
   profiles, lightest first (what Auto reads): LOW -12.8, HIGH 0.0, ULTRA 3.5
   spir-v: 34 modules, 0 errors, 0 panics
```

The one unused program is `gbuffers_basic`, which this pack keeps for compatibility and which
the game does not draw on its own; it translates.

## A note on realism

Minecraft's world is made of one-metre cubes with 16x16 textures and no per-pixel material maps.
A shader pack can add light, air, water, shadow and lens behaviour, and this one does; it cannot
turn that geometry and those textures into the asset density, motion and art direction of a
modern open-world game. The aim is a coherent, filmic Minecraft, not a claim to be another game.

## Licence

MIT, like Starling. The original pack and this version are in `LICENSE`.
