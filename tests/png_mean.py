#!/usr/bin/env python3
"""Mean brightness of a PNG, 0 (black) to 255, with no dependencies.

    png_mean.py <file.png>

Reads 8-bit RGB and RGBA, non-interlaced — what screendump.py writes and
what niri's screenshot action saves. Suites compare two captures of the
same screen with it (a fading screen gets darker), so the number only has
to be consistent, not colorimetric: it is the plain mean of the R, G and
B samples.
"""

import struct
import sys
import zlib


def main(path: str) -> int:
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        print(f"{path}: not a PNG", file=sys.stderr)
        return 2
    pos = 8
    idat = bytearray()
    width = height = depth = ctype = interlace = None
    while pos + 8 <= len(data):
        (length,) = struct.unpack(">I", data[pos : pos + 4])
        tag = data[pos + 4 : pos + 8]
        body = data[pos + 8 : pos + 8 + length]
        pos += 12 + length
        if tag == b"IHDR":
            width, height, depth, ctype, _, _, interlace = struct.unpack(">IIBBBBB", body)
        elif tag == b"IDAT":
            idat += body
        elif tag == b"IEND":
            break
    if depth != 8 or ctype not in (2, 6) or interlace:
        print(f"{path}: unsupported PNG (depth {depth}, colour type {ctype}, "
              f"interlace {interlace})", file=sys.stderr)
        return 2
    bpp = 3 if ctype == 2 else 4
    stride = width * bpp
    raw = zlib.decompress(bytes(idat))
    if len(raw) != height * (stride + 1):
        print(f"{path}: image data is {len(raw)} bytes, expected "
              f"{height * (stride + 1)}", file=sys.stderr)
        return 2

    total = 0
    prev = bytearray(stride)
    pos = 0
    for _ in range(height):
        filt = raw[pos]
        line = bytearray(raw[pos + 1 : pos + 1 + stride])
        pos += 1 + stride
        if filt == 1:
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 255
        elif filt == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 255
        elif filt == 3:
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + (a + prev[i]) // 2) & 255
        elif filt == 4:
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                b = prev[i]
                c = prev[i - bpp] if i >= bpp else 0
                pr = a + b - c
                pa, pb, pc = abs(pr - a), abs(pr - b), abs(pr - c)
                pred = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 255
        elif filt != 0:
            print(f"{path}: bad filter byte {filt}", file=sys.stderr)
            return 2
        total += sum(line)
        if bpp == 4:
            total -= sum(line[3::4])
        prev = line

    print(round(total / (width * height * 3), 1))
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__.strip().splitlines()[2].strip(), file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
