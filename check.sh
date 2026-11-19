#!/usr/bin/env bash
# Translate every program with Starling's own shader-pack reader, including the option extremes
# (all switches on or off, every value at its highest or lowest). This is the check the release
# notes name; it needs a checkout of mdmuntakim/minecraft and a Rust toolchain.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="${HORIZON_REPO:-$root/../minecraft}"
if [ ! -f "$repo/Cargo.toml" ]; then
    echo "error: set HORIZON_REPO to a checkout of mdmuntakim/minecraft (tried $repo)" >&2
    exit 1
fi
bash "$root/build.sh" >/dev/null
cargo build --release --manifest-path "$repo/Cargo.toml" -p horizon-shaders --example pack_report
"$repo/target/release/examples/pack_report" "$root/dist/StarlingVisuals.zip" \
    --programs --backends --stress --example 3
