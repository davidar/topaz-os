#!/usr/bin/env python3
"""Screendump via the VNC socket.

QMP screendump cannot capture the GL scanout egl-headless uses (the
console has no 2D surface, with or without display clients attached),
but the VNC server reads the rendered frame back on demand — so grab
one full framebuffer update over RFB and write it out as a PNG.

Usage: screendump.py <vnc-socket> <out.png>
"""
import socket
import struct
import sys
import zlib


def read_exact(sock: socket.socket, n: int) -> bytes:
    buf = b""
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise RuntimeError("VNC connection closed mid-message")
        buf += chunk
    return buf


def grab_frame(path: str) -> tuple[int, int, bytearray]:
    """RFB 3.8 handshake, then one raw-encoded full-screen update."""
    sock = socket.socket(socket.AF_UNIX)
    sock.settimeout(15)
    sock.connect(path)
    read_exact(sock, 12)  # ProtocolVersion
    sock.sendall(b"RFB 003.008\n")
    types = read_exact(sock, read_exact(sock, 1)[0])
    if 1 not in types:  # 1 = None; the socket is a private unix path
        raise RuntimeError("VNC server demands authentication")
    sock.sendall(bytes([1]))
    if struct.unpack(">I", read_exact(sock, 4))[0] != 0:
        raise RuntimeError("VNC security handshake failed")
    sock.sendall(bytes([1]))  # ClientInit, shared
    width, height = struct.unpack(">HH", read_exact(sock, 4))
    read_exact(sock, 16)  # server pixel format (overridden below)
    read_exact(sock, struct.unpack(">I", read_exact(sock, 4))[0])  # name

    # SetPixelFormat: 32bpp true-colour little-endian, R:G:B at 16:8:0.
    sock.sendall(
        struct.pack(">BxxxBBBBHHHBBBxxx", 0, 32, 24, 0, 1, 255, 255, 255, 16, 8, 0)
    )
    sock.sendall(struct.pack(">BxH", 2, 1) + struct.pack(">i", 0))  # raw only
    # FramebufferUpdateRequest: non-incremental, full screen.
    sock.sendall(struct.pack(">BBHHHH", 3, 0, 0, 0, width, height))

    canvas = bytearray(width * height * 4)
    while True:
        msg_type = read_exact(sock, 1)[0]
        if msg_type != 0:  # e.g. bell / clipboard; nothing else expected
            raise RuntimeError(f"unexpected VNC message type {msg_type}")
        (nrects,) = struct.unpack(">xH", read_exact(sock, 3))
        for _ in range(nrects):
            x, y, w, h, enc = struct.unpack(">HHHHi", read_exact(sock, 12))
            if enc != 0:
                raise RuntimeError(f"unexpected VNC encoding {enc}")
            data = read_exact(sock, w * h * 4)
            for row in range(h):
                dst = ((y + row) * width + x) * 4
                canvas[dst : dst + w * 4] = data[row * w * 4 : (row + 1) * w * 4]
        sock.close()
        return width, height, canvas


def write_png(out: str, width: int, height: int, bgrx: bytearray) -> None:
    raw = bytearray()
    for row in range(height):
        raw.append(0)  # filter: none
        line = bgrx[row * width * 4 : (row + 1) * width * 4]
        for px in range(width):
            b, g, r = line[px * 4 : px * 4 + 3]
            raw += bytes((r, g, b))

    def chunk(tag: bytes, body: bytes) -> bytes:
        return (
            struct.pack(">I", len(body))
            + tag
            + body
            + struct.pack(">I", zlib.crc32(tag + body))
        )

    with open(out, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(bytes(raw))))
        f.write(chunk(b"IEND", b""))


def main() -> int:
    vnc_path, out = sys.argv[1], sys.argv[2]
    width, height, canvas = grab_frame(vnc_path)
    write_png(out, width, height, canvas)
    return 0


if __name__ == "__main__":
    sys.exit(main())
