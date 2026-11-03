"""Tests for FreeDiskSysROM, run against an assembled ROM in a simulator.

Usage: python tests/test_bios.py [path/to/rom.bin]
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fds_sim import Machine, build_disk  # noqa: E402

ROM_PATH = os.environ.get("FDS_ROM", "disksys.rom")

LOAD_FILES = 0xE1F8
APPEND_FILE = 0xE237
WRITE_FILE = 0xE239
CHECK_FILE_COUNT = 0xE2B7
ADJUST_FILE_COUNT = 0xE2BB
SET_FILE_COUNT1 = 0xE301
SET_FILE_COUNT = 0xE305
GET_DISK_INFO = 0xE32A
READ_KEYBOARD = 0xEB13
UPLOAD_OBJECT = 0xEC22

DISK_ID = [0x01, 0x54, 0x53, 0x54, 0x20, 0x00, 0x00, 0x00, 0x00, 0x00]
GAME_LOOP = 0x6005

# Boot program: store $AA at $10, then loop forever at GAME_LOOP.
BOOT_CODE = [0xA9, 0xAA, 0x85, 0x10, 0xEA, 0x4C, GAME_LOOP & 0xFF, GAME_LOOP >> 8]
VECTORS = [0x00, 0x60, 0x00, 0x60, 0x00, 0x60, 0x00, 0x60, 0x00, 0x60]  # $DFF6-$DFFF
CHR = [0x00, 0x11, 0x00, 0x22, 0x00, 0x00, 0x33, 0x44]  # zeros catch doubled VRAM writes


def files():
    return [
        dict(id=0, name=b"KYODAKU-", addr=0x6000, data=BOOT_CODE),
        dict(id=1, name=b"VECTORS-", addr=0xDFF6, data=VECTORS),
        dict(id=2, name=b"CHARS---", addr=0x0000, type=1, data=CHR),
        dict(id=5, name=b"LATER---", addr=0x7000, data=[0x55] * 20),
    ]


def disk():
    return build_disk(DISK_ID, 2, files())


class BiosTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(ROM_PATH, "rb") as f:
            cls.rom = f.read()
        assert len(cls.rom) == 8192, "ROM must be 8 KiB"

    DRIVE = "exact"

    def machine(self, **kwargs):
        kwargs.setdefault("blocks", disk())
        kwargs.setdefault("drive", self.DRIVE)
        return Machine(self.rom, **kwargs)

    def write_disk_id(self, m, address=0x0300):
        m.mem.write(address, DISK_ID)
        return address

    def assertNoOverruns(self, m):
        self.assertEqual(m.overruns, 0, "BIOS missed disk bytes")


class BootTest(BiosTest):
    def test_boots_disk_and_jumps_to_reset_vector(self):
        m = self.machine()
        m.reset()
        m.run_until(GAME_LOOP)
        self.assertEqual(m.mem[0x10], 0xAA)
        self.assertEqual(m.mem[0x7000], 0x00, "file above the boot ID was loaded")
        self.assertEqual(m.vram[0:len(CHR)], CHR)
        self.assertEqual(m.mem[0x0102], 0x35)
        self.assertEqual(m.mem[0x0103], 0xAC)
        self.assertNoOverruns(m)

    def test_soft_reset_skips_loading(self):
        m = self.machine()
        m.reset()
        m.run_until(GAME_LOOP)
        m.mem[0x10] = 0
        m.mem[0x6002] = 0x85  # unchanged code; jump straight back in
        m.reset()
        m.run_until(GAME_LOOP, max_cycles=200_000)
        self.assertEqual(m.mem[0x0103], 0x53)


class DemoDiskTest(BiosTest):
    def test_demo_disk_prints_message(self):
        import make_demo_disk as demo
        blocks = build_disk(demo.DISK_ID, 1, [
            dict(id=0, name=b"DEMOPRG-", addr=0x6000, data=demo.CODE),
            dict(id=1, name=b"VECTORS-", addr=0xDFF6, data=demo.VECTORS),
        ])
        m = self.machine(blocks=blocks)
        m.reset()
        m.run_until(0x600B)
        m.run_until(0x6014)
        self.assertEqual(m.vram[0x21CA:0x21CA + len(demo.MESSAGE)], demo.MESSAGE)


class LoadFilesTest(BiosTest):
    def test_loads_listed_file(self):
        m = self.machine()
        disk_id = self.write_disk_id(m)
        m.mem.write(0x0310, [0x05, 0xFF])
        a, _, y = m.call(LOAD_FILES, params=[disk_id, 0x0310])
        self.assertEqual(a, 0)
        self.assertEqual(y, 1)
        self.assertEqual(m.mem[0x7000:0x7014], [0x55] * 20)
        self.assertEqual(m.mem[0x6000], 0x00)
        self.assertNoOverruns(m)

    def test_disk_not_set(self):
        m = self.machine(inserted=False)
        disk_id = self.write_disk_id(m)
        m.mem.write(0x0310, [0x05, 0xFF])
        a, _, _ = m.call(LOAD_FILES, params=[disk_id, 0x0310])
        self.assertEqual(a, 0x01)

    def test_wrong_maker_id(self):
        m = self.machine()
        disk_id = self.write_disk_id(m)
        m.mem[disk_id] = 0x99
        m.mem.write(0x0310, [0x05, 0xFF])
        m.mem[0x0101] = 0x80
        a, _, _ = m.call(LOAD_FILES, params=[disk_id, 0x0310])
        self.assertEqual(a, 0x04)
        self.assertEqual(m.mem[0x0101], 0x80, "$0101 not restored after error")

    def test_wildcard_disk_id(self):
        m = self.machine()
        m.mem.write(0x0300, [0xFF] * 10)
        m.mem.write(0x0310, [0x05, 0xFF])
        a, _, y = m.call(LOAD_FILES, params=[0x0300, 0x0310])
        self.assertEqual((a, y), (0, 1))


class LargeFileTest(BiosTest):
    def test_loads_large_prg_and_vram_files_without_missing_bytes(self):
        prg = [(i * 13 + 1) & 0xFF for i in range(4096)]
        chr_data = [(i * 5) & 0xFF if i % 3 else 0 for i in range(2048)]
        blocks = build_disk(DISK_ID, 0, [
            dict(id=1, name=b"BIGPRG--", addr=0x6000, data=prg),
            dict(id=2, name=b"BIGCHR--", addr=0x0000, type=1, data=chr_data),
        ])
        m = self.machine(blocks=blocks)
        disk_id = self.write_disk_id(m)
        m.mem.write(0x0310, [0x01, 0x02, 0xFF])
        a, _, y = m.call(LOAD_FILES, params=[disk_id, 0x0310])
        self.assertEqual((a, y), (0, 2))
        self.assertEqual(m.mem[0x6000:0x7000], prg)
        self.assertEqual(m.vram[0:2048], chr_data)
        self.assertNoOverruns(m)

    def test_appends_large_file_from_ram_and_vram(self):
        m = self.machine()
        disk_id = self.write_disk_id(m)
        data = [(i * 11) & 0xFF for i in range(1024)]
        m.vram[0x1000:0x1400] = data
        header = [9] + list(b"VRAMSAVE") + [0x00, 0x10, 0x00, 0x04, 0x01]
        header += [0x00, 0x10, 0x01]  # source: VRAM $1000
        m.mem.write(0x0320, header)
        a, _, _ = m.call(APPEND_FILE, params=[disk_id, 0x0320])
        self.assertEqual(a, 0)
        self.assertEqual(m.disk_blocks()[11], [0x04] + data)
        self.assertNoOverruns(m)


class GetDiskInfoTest(BiosTest):
    def test_reports_disk_id_files_and_size(self):
        m = self.machine()
        a, _, _ = m.call(GET_DISK_INFO, params=[0x0500])
        self.assertEqual(a, 0)
        self.assertEqual(m.mem[0x0500:0x050A], DISK_ID)
        self.assertEqual(m.mem[0x050A], 4)
        index = 0x050B
        for f in files():
            self.assertEqual(m.mem[index], f["id"])
            self.assertEqual(bytes(m.mem[index + 1:index + 9]), f["name"])
            index += 9
        size = sum(len(f["data"]) + 261 for f in files())
        self.assertEqual(m.mem[index], size >> 8)
        self.assertEqual(m.mem[index + 1], size & 0xFF)
        self.assertNoOverruns(m)


class WriteTest(BiosTest):
    def header(self, m, file_id=7, addr=0x7100, data=None, source=0x0600):
        data = data or [(i * 7) & 0xFF for i in range(32)]
        m.mem.write(source, data)
        header = [file_id] + list(b"SAVEDATA") + [addr & 0xFF, addr >> 8]
        header += [len(data) & 0xFF, len(data) >> 8, 0x00]
        header += [source & 0xFF, source >> 8, 0x00]
        m.mem.write(0x0320, header)
        return data

    def test_append_file(self):
        m = self.machine()
        disk_id = self.write_disk_id(m)
        data = self.header(m)
        a, _, _ = m.call(APPEND_FILE, params=[disk_id, 0x0320])
        self.assertEqual(a, 0)
        self.assertEqual(m.file_count(), 5)
        self.assertEqual(m.disk_blocks()[10][0:3], [0x03, 4, 7])
        self.assertEqual(m.disk_blocks()[11], [0x04] + data)
        drive = m.fceumm or m
        self.assertEqual(set(drive.marks), {0x80}, "blocks must start with an $80 mark")
        if not m.fceumm:
            self.assertGreaterEqual(m.crc_written, 2, "last block did not end with 2 CRC bytes")
        self.assertNoOverruns(m)

        m.mem.write(0x0310, [0x07, 0xFF])
        a, _, y = m.call(LOAD_FILES, params=[disk_id, 0x0310])
        self.assertEqual((a, y), (0, 1))
        self.assertEqual(m.mem[0x7100:0x7120], data)

    def test_write_file_hides_later_files(self):
        m = self.machine()
        disk_id = self.write_disk_id(m)
        data = self.header(m, data=[0x00, 0x01, 0x00, 0x02])
        a, _, _ = m.call(WRITE_FILE, a=1, params=[disk_id, 0x0320])
        self.assertEqual(a, 0)
        self.assertEqual(m.file_count(), 2)
        self.assertEqual(m.disk_blocks()[5], [0x04] + data)

    def test_write_protected(self):
        m = self.machine(write_protected=True)
        disk_id = self.write_disk_id(m)
        self.header(m)
        a, _, _ = m.call(APPEND_FILE, params=[disk_id, 0x0320])
        self.assertEqual(a, 0x03)
        self.assertEqual(m.file_count(), 4)


class FileCountTest(BiosTest):
    def test_set_file_count(self):
        m = self.machine()
        disk_id = self.write_disk_id(m)
        a, _, _ = m.call(SET_FILE_COUNT, a=2, params=[disk_id])
        self.assertEqual((a, m.file_count()), (0, 2))

    def test_set_file_count1(self):
        m = self.machine()
        disk_id = self.write_disk_id(m)
        a, _, _ = m.call(SET_FILE_COUNT1, a=2, params=[disk_id])
        self.assertEqual((a, m.file_count()), (0, 3))

    def test_adjust_file_count(self):
        m = self.machine()
        disk_id = self.write_disk_id(m)
        a, _, _ = m.call(ADJUST_FILE_COUNT, a=1, params=[disk_id])
        self.assertEqual((a, m.file_count()), (0, 3))

    def test_check_file_count(self):
        m = self.machine()
        disk_id = self.write_disk_id(m)
        a, _, _ = m.call(CHECK_FILE_COUNT, a=3, params=[disk_id])
        self.assertEqual((a, m.file_count()), (0, 3))

    def test_check_file_count_too_large(self):
        m = self.machine()
        disk_id = self.write_disk_id(m)
        a, _, _ = m.call(CHECK_FILE_COUNT, a=9, params=[disk_id])
        self.assertEqual((a, m.file_count()), (0x31, 4))


class KeyboardTest(BiosTest):
    def test_no_keyboard(self):
        m = self.machine()
        a, _, _ = m.call(READ_KEYBOARD)
        self.assertEqual(a, 0x00)

    def test_reads_pressed_keys(self):
        m = self.machine()
        m.keyboard = [[0, 0] for _ in range(9)]
        m.keyboard[0] = [0b0001, 0b0000]
        m.keyboard[8] = [0b0000, 0b1000]
        a, _, _ = m.call(READ_KEYBOARD)
        self.assertEqual(a, 0xFF)
        self.assertEqual(m.mem[0x08], 0x01)  # row 0
        self.assertEqual(m.mem[0x00], 0x80)  # row 8
        self.assertEqual(m.mem[0x01:0x08], [0] * 7)


class UploadObjectTest(BiosTest):
    def obj(self, m, render=0, flags=0):
        # 2 wide, 2 tall at Y=$20, X=$30, frame 1, base tile $10, palette 2, OAM $08
        m.mem.write(0x0340, [render, 0x20, 0, 0x30, 0, 1, 0x00, 0x10, flags, 2, 0x22, 0x08])
        m.mem.write(0x00, [0x40, 0x03])

    def sprites(self, m, count=4):
        return [m.mem[0x0208 + i * 4:0x020C + i * 4] for i in range(count)]

    def test_renders_column_by_column(self):
        m = self.machine()
        self.obj(m)
        m.call(UPLOAD_OBJECT)
        self.assertEqual(self.sprites(m), [
            [0x20, 0x14, 0x02, 0x30],
            [0x28, 0x15, 0x02, 0x30],
            [0x20, 0x16, 0x02, 0x38],
            [0x28, 0x17, 0x02, 0x38],
        ])

    def test_horizontal_flip(self):
        m = self.machine()
        self.obj(m, flags=0x10)
        m.call(UPLOAD_OBJECT)
        self.assertEqual(self.sprites(m)[0], [0x20, 0x14, 0x42, 0x38])

    def test_frame_offset_stays_in_tile_ids(self):
        # base tile $F0 plus frame 4 * 4 tiles wraps to $00, not a tile list at $0100
        m = self.machine()
        self.obj(m)
        m.mem.write(0x0345, [4, 0x00, 0xF0])
        m.call(UPLOAD_OBJECT)
        self.assertEqual([s[1] for s in self.sprites(m)], [0x00, 0x01, 0x02, 0x03])

    def test_hide(self):
        m = self.machine()
        self.obj(m, render=0x80)
        m.call(UPLOAD_OBJECT)
        self.assertEqual([s[0] for s in self.sprites(m)], [0xFF] * 4)


# FCEUmm, the NES core EmulatorJS uses, models the drive differently, so the
# disk tests run against its model too.
for _cls in (BootTest, DemoDiskTest, LoadFilesTest, LargeFileTest, GetDiskInfoTest,
             WriteTest, FileCountTest):
    _name = "Fceumm" + _cls.__name__
    globals()[_name] = type(_name, (_cls,), {"DRIVE": "fceumm"})


if __name__ == "__main__":
    if len(sys.argv) > 1 and not sys.argv[1].startswith("-"):
        ROM_PATH = sys.argv.pop(1)
    unittest.main()
