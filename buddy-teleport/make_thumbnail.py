#!/usr/bin/env python3
"""Generate buddy-teleport/thumbnail.png: a simple solid blue 512x512 image.

Pure stdlib (struct + zlib), no third-party deps.
"""
import struct, zlib

W = H = 512
R, G, B = 30, 110, 220  # solid blue

row = bytes([R, G, B, 255]) * W
raw = bytearray()
for _ in range(H):
    raw.append(0)  # filter type 0
    raw += row


def chunk(tag, data):
    return (struct.pack(">I", len(data)) + tag + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff))


png = (b"\x89PNG\r\n\x1a\n"
       + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 6, 0, 0, 0))
       + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
       + chunk(b"IEND", b""))

with open("thumbnail.png", "wb") as f:
    f.write(png)
print("wrote thumbnail.png", len(png), "bytes")
