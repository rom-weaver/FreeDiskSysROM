"""Writes a one-side .fds demo disk that boots with any FDS BIOS and prints
"FREE BIOS OK" through BIOS routines. Use it to check a BIOS in an emulator.

Usage: python tests/make_demo_disk.py demo.fds
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fds_sim import build_disk  # noqa: E402

SIDE_SIZE = 65500

# BIOS font tiles: 0-9 are digits, $0A-$23 are A-Z, $24 is a space.
def text(s):
    return [0x24 if c == " " else int(c, 36) for c in s]

MESSAGE = text("FREE BIOS OK")
CODE = [
    0xA9, 0x21,              # $6000 LDA #$21
    0xA2, 0xCA,              # $6002 LDX #$CA
    0xA0, len(MESSAGE),      # $6004 LDY #len
    0x20, 0xD2, 0xE8,        # $6006 JSR PrepareVRAMString
    0x1A, 0x60,              # $6009 .word message
    0x20, 0xB2, 0xE1,        # $600B JSR VINTWait
    0x20, 0x6A, 0xE8,        # $600E JSR WriteVRAMBuffers
    0x20, 0xEA, 0xEA,        # $6011 JSR SetScroll
    0x4C, 0x0B, 0x60,        # $6014 JMP $600B
    0x40,                    # $6017 RTI, for the game NMI vectors
    0x00, 0x00,              # $6018
] + MESSAGE                  # $601A
VECTORS = [0x17, 0x60] * 3 + [0x00, 0x60, 0x17, 0x60]  # $DFF6-$DFFF

DISK_ID = [0x00] + list(b"DMO") + [0x20, 0x00, 0x00, 0x00, 0x00, 0x00]


def main(path):
    blocks = build_disk(DISK_ID, 1, [
        dict(id=0, name=b"DEMOPRG-", addr=0x6000, data=CODE),
        dict(id=1, name=b"VECTORS-", addr=0xDFF6, data=VECTORS),
    ])
    side = [b for block in blocks for b in block]
    side += [0] * (SIDE_SIZE - len(side))
    header = list(b"FDS\x1a") + [1] + [0] * 11
    with open(path, "wb") as f:
        f.write(bytes(header + side))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "demo.fds")
