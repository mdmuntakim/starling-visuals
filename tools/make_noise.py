#!/usr/bin/env python3
"""Generate shaders/noise.png: a deterministic 256x256 RGB white-noise texture.

The shaders use it for dithering (the sun's rays, the film grain and the final 8-bit dither),
not as an artistic texture, so every byte is independent and the PNG is deliberately not
compressed away. Run this only when the texture must be regenerated.
"""
import struct
import zlib
from pathlib import Path


def chunk(kind: bytes, payload: bytes) -> bytes:
    return (
        struct.pack(">I", len(payload))
        + kind
        + payload
        + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)
    )


def main() -> None:
    width = height = 256
    state = 0x9E3779B97F4A7C15
    rows = bytearray()
    for _ in range(height):
        rows.append(0)  # PNG filter: none
        for _ in range(width * 3):
            state ^= (state << 13) & 0xFFFFFFFFFFFFFFFF
            state ^= state >> 7
            state ^= (state << 17) & 0xFFFFFFFFFFFFFFFF
            rows.append((state >> 33) & 0xFF)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(rows), 9))
    png += chunk(b"IEND", b"")
    out = Path(__file__).resolve().parent.parent / "shaders" / "noise.png"
    out.write_bytes(png)
    print(f"{out}: {len(png)} bytes")


if __name__ == "__main__":
    main()
