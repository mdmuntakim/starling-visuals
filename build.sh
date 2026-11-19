#!/usr/bin/env bash
# Build StarlingVisuals.zip from shaders/. The archive is deterministic: the same files make the
# same bytes, so the app can tell one release from the next by the file alone.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out="${1:-$root/dist/StarlingVisuals.zip}"
mkdir -p "$(dirname "$out")"
python3 - "$root/shaders" "$out" <<'PY'
import sys
import zipfile
from pathlib import Path

source = Path(sys.argv[1])
out = Path(sys.argv[2])
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for file in sorted(p for p in source.rglob("*") if p.is_file()):
        info = zipfile.ZipInfo(f"shaders/{file.relative_to(source).as_posix()}", (2026, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        archive.writestr(info, file.read_bytes())
print(f"{out}: {out.stat().st_size} bytes")
PY
