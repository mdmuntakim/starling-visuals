#!/usr/bin/env python3
"""Check that every shader in the pack is complete before it is zipped.

Two classes of mistake have shipped in this pack before and neither is caught by a build:

* an `#include` that names a file which does not exist (the 2.0 `gbuffers_basic` pointed at a
  `program/basic.glsl` that was never committed, so every client that draws basic geometry got
  a broken program and a white block outline);
* a `gbuffers_*` stage without its pair, which the loader silently treats as a missing program.

Run from the repository root: `python3 tools/check_includes.py`.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHADERS = ROOT / "shaders"
INCLUDE = re.compile(r'^\s*#include\s+"([^"]+)"')


def resolve(including: Path, target: str) -> Path:
    if target.startswith("/"):
        return SHADERS / target.lstrip("/")
    return (including.parent / target).resolve()


def main() -> int:
    if not SHADERS.is_dir():
        print(f"error: {SHADERS} is not a directory", file=sys.stderr)
        return 1

    problems: list[str] = []
    files = sorted(p for p in SHADERS.rglob("*") if p.is_file())
    for path in files:
        if path.suffix not in {".glsl", ".vsh", ".fsh", ".gsh", ".csh"}:
            continue
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            match = INCLUDE.match(line)
            if not match:
                continue
            target = resolve(path, match.group(1))
            if not target.is_file():
                shown = path.relative_to(ROOT).as_posix()
                problems.append(f"{shown}:{number}: missing include {match.group(1)!r}")

    # A gbuffers program needs both stages; one without the other is never drawn.
    stems = {p.stem for p in (SHADERS).glob("gbuffers_*")}
    for stem in sorted(stems):
        for ext in ("vsh", "fsh"):
            if not (SHADERS / f"{stem}.{ext}").is_file():
                problems.append(f"gbuffers program {stem} has no .{ext}")

    # The block outline's program must exist: this is the regression that turned it white.
    if not (SHADERS / "program" / "basic.glsl").is_file():
        problems.append("program/basic.glsl is missing: the block outline has no program")

    # An emissive id on a sprite that a plain block also draws makes that block glow. Horizon
    # hands the pack an id per sprite layer, and the beacon's base is the obsidian sprite while
    # the jack o'lantern's side and top are the pumpkin sprites: those two ids turned ordinary
    # obsidian and pumpkin into pale, almost white blocks. Keep them out of the emissive groups,
    # and keep obsidian and pumpkin at material 0.
    assigned: dict[str, int] = {}
    for line in (SHADERS / "block.properties").read_text(encoding="utf-8").splitlines():
        line = line.split("#", 1)[0].replace("\\", " ").strip()
        if not line.startswith("block."):
            continue
        key, _, value = line.partition("=")
        try:
            block_id = int(key.strip()[len("block.") :])
        except ValueError:
            continue
        for name in value.split():
            assigned.setdefault(name, block_id)
    emissive_ids = {10004, 10005, 10006}
    for name in ("minecraft:beacon", "minecraft:jack_o_lantern"):
        if assigned.get(name) in emissive_ids:
            problems.append(
                f"block.properties: {name} has emissive id {assigned[name]}; "
                "its sprite is shared with a plain block"
            )
    for name in ("minecraft:obsidian", "minecraft:pumpkin"):
        if name in assigned:
            problems.append(f"block.properties: {name} must stay material 0, not {assigned[name]}")

    if problems:
        for problem in problems:
            print(f"error: {problem}", file=sys.stderr)
        return 1
    print(f"checked {len(files)} files: every include resolves, every gbuffers stage is paired")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
