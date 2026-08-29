#!/usr/bin/env python3
"""Minimal QMP client for the VM harness.

Usage: qmp.py <socket> <command> [json-arguments]
Prints the reply as JSON; exits non-zero if QMP returns an error.
"""
import json
import socket
import sys


def main() -> int:
    sock_path, command = sys.argv[1], sys.argv[2]
    arguments = json.loads(sys.argv[3]) if len(sys.argv) > 3 else {}

    sock = socket.socket(socket.AF_UNIX)
    sock.connect(sock_path)
    stream = sock.makefile("rw")

    json.loads(stream.readline())  # server greeting
    reply = {}
    for payload in (
        {"execute": "qmp_capabilities"},
        {"execute": command, "arguments": arguments},
    ):
        stream.write(json.dumps(payload) + "\n")
        stream.flush()
        while True:
            line = stream.readline()
            if not line:  # e.g. the VM exited on "quit"
                reply = {"return": {}}
                break
            reply = json.loads(line)
            if "event" not in reply:
                break

    print(json.dumps(reply))
    return 0 if "return" in reply else 1


if __name__ == "__main__":
    sys.exit(main())
