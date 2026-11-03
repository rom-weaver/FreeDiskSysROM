"""A small Famicom Disk System simulator for testing the BIOS.

It models the 6502 (through py65), a minimal PPU, and an FDS drive whose
disk is a list of blocks. Drive positioning is event based: starting a
transfer moves to the next block, and transfer reset rewinds to block 0.
Bytes arrive every BYTE_CYCLES CPU cycles while a transfer runs.
"""

from py65.devices.mpu6502 import MPU
from py65.memory import ObservableMemory

BYTE_CYCLES = 148  # 96.4 kbit/s at 1.79 MHz is about 148.5 cycles per byte
FRAME_CYCLES = 29781
DELAYMS = 0xE153


class Kil(Exception):
    pass


class FdsMPU(MPU):
    """py65 MPU with the unofficial opcodes the BIOS uses."""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.instruct = list(self.instruct)
        self.cycletime = list(self.cycletime)
        self.instruct[0x0C] = FdsMPU._top
        self.cycletime[0x0C] = 4
        self.instruct[0x72] = FdsMPU._kil

    def _top(self):
        self.memory[self.WordAt(self.pc)]
        self.pc += 2

    def _kil(self):
        raise Kil("KIL at $%04X" % ((self.pc - 1) & 0xFFFF))


def crc_bytes():
    return [0x00, 0x00]


def build_disk(disk_id, boot_id, files):
    """Builds disk blocks. disk_id is 10 bytes; files are dicts with id,
    name (8 bytes), addr, type, data."""
    block1 = [0x01] + list(b"*NINTENDO-HVC*") + list(disk_id) + [boot_id]
    block1 += [0x00] * (56 - len(block1))
    blocks = [block1, [0x02, len(files)]]
    for number, f in enumerate(files):
        data = list(f["data"])
        header = [0x03, number, f["id"]] + list(f["name"])
        header += [f["addr"] & 0xFF, f["addr"] >> 8]
        header += [len(data) & 0xFF, len(data) >> 8, f.get("type", 0)]
        blocks.append(header)
        blocks.append([0x04] + data)
    return blocks


SIDE_SIZE = 65500
DSK_INIT, DSK_VOLUME, DSK_FILECNT, DSK_FILEHDR, DSK_FILEDATA = range(5)


def flatten(blocks):
    side = [b for block in blocks for b in block]
    return side + [0] * (SIDE_SIZE - len(side))


def unflatten(side):
    """Splits a flat disk side back into blocks, using the block lengths."""
    blocks = [side[0:56], side[56:58]]
    pos = 58
    for _ in range(side[57]):
        header = side[pos:pos + 16]
        size = header[13] | (header[14] << 8)
        blocks.append(header)
        blocks.append(side[pos + 16:pos + 17 + size])
        pos += 17 + size
    return blocks


class FceummDrive:
    """Models the FDS drive the way the FCEUmm core (used by EmulatorJS)
    does in src/fds.c: blocks follow a fixed order with fixed lengths, a byte
    becomes ready 150 cycles after the last $4031 read or $4025 write, and the
    first $4024 write after a block starts is taken as the start mark."""

    def __init__(self, machine, blocks):
        self.m = machine
        self.disk = flatten(blocks)
        self.control = 0
        self.block = DSK_INIT
        self.start = 0
        self.length = 0
        self.addr = 0
        self.filesize = 0
        self.access = 0
        self.seek = 0
        self.irq = False
        self.marks = []

    def write(self, addr, value):
        if addr == 0x4024 and self.m.inserted and not self.control & 0x04:
            if self.access == 0:
                self.access = 1
                self.marks.append(value)
            elif self.addr < self.length:
                self.disk[self.start + self.addr] = value
                if self.block == DSK_FILEHDR and self.addr in (13, 14):
                    self._filesize(value)
                self.addr += 1
        elif addr == 0x4025:
            self.irq = False
            if self.m.inserted:
                if value & 0x40 and not self.control & 0x40:
                    self.access = 0
                    self.seek = 150
                    self.start += self.addr
                    self.addr = 0
                    self.block += 1
                    if self.block > DSK_FILEDATA:
                        self.block = DSK_FILEHDR
                    self.length = {DSK_VOLUME: 0x38, DSK_FILECNT: 2, DSK_FILEHDR: 0x10,
                                   DSK_FILEDATA: 1 + self.filesize}[self.block]
                if value & 0x02:
                    self.block = DSK_INIT
                    self.start = self.length = self.addr = 0
                    self.seek = 150
                if value & 0x40:
                    self.seek = 150
            self.control = value
        return value

    def _filesize(self, value):
        if self.addr == 13:
            self.filesize = value
        else:
            self.filesize |= value << 8

    def read(self, addr):
        if addr == 0x4030:
            value = 0x02 if self.irq else 0
            self.irq = False
            return value
        if addr == 0x4031:
            value = 0xFF
            if self.m.inserted and self.control & 0x04:
                self.access = 1
                value = 0
                if self.addr < self.length:
                    value = self.disk[self.start + self.addr]
                    if self.block == DSK_FILEHDR and self.addr in (13, 14):
                        self._filesize(value)
                    self.addr += 1
                self.seek = 150
                self.irq = False
            return value
        if addr == 0x4032:
            value = 0x40
            if not self.m.inserted:
                value |= 0x05
            if not self.m.inserted or not self.control & 1 or self.control & 2:
                value |= 0x02
            if self.m.write_protected:
                value |= 0x04
            return value
        if addr == 0x4033:
            return 0x80
        return 0

    def tick(self, cycles):
        if self.seek > 0:
            self.seek -= cycles
            if self.seek <= 0 and self.control & 0x80:
                self.irq = True


class Machine:
    def __init__(self, rom, blocks=None, inserted=True, write_protected=False, drive="exact"):
        self.mem = ObservableMemory()
        self.mem.write(0xE000, list(rom))
        # register mirrors and vector flags as left by the BIOS boot
        self.mem.write(0x00F9, [0xFF, 0x2E, 0x00, 0x00, 0x00, 0x06, 0x80])
        self.mem.write(0x0100, [0xC0, 0x80])
        self.mpu = FdsMPU(memory=self.mem)
        self.blocks = [list(b) for b in (blocks or [])]
        self.inserted = inserted
        self.write_protected = write_protected
        self.keyboard = None  # None = no keyboard connected

        # PPU
        self.vram = [0] * 0x4000
        self.ppuctrl = 0
        self.ppuaddr = 0
        self.latch = False
        self.read_buffer = 0
        self.vblank = False
        self.next_frame = FRAME_CYCLES
        self.nmi_pending = False

        # drive
        self.fdsctrl = 0x2E
        self.next_block = 0
        self.current = None
        self.stream = []
        self.stream_pos = 0
        self.capture = None
        self.byte_flag = False
        self.data = 0
        self.next_byte = None
        self.overruns = 0
        self.marks = []
        self.mark_pending = False
        self.write_latch = 0
        self.crc_written = 0
        self.pending = False  # a byte arrived and was not yet read or written
        self.irq_line = False

        m = self.mem
        m.subscribe_to_write(range(0xE000, 0x10000), lambda a, v: m._subject[a])
        m.subscribe_to_write(range(0x2000, 0x2008), self._ppu_write)
        m.subscribe_to_read(range(0x2000, 0x2008), self._ppu_read)
        self.fceumm = FceummDrive(self, self.blocks) if drive == "fceumm" else None
        if self.fceumm:
            m.subscribe_to_write(range(0x4020, 0x4027), self.fceumm.write)
            m.subscribe_to_read(range(0x4030, 0x4034), self.fceumm.read)
        else:
            m.subscribe_to_write(range(0x4020, 0x4027), self._fds_write)
            m.subscribe_to_read(range(0x4030, 0x4034), self._fds_read)
        self.last_cycles = 0
        m.subscribe_to_read([0x4016, 0x4017], self._pad_read)
        m.subscribe_to_write([0x4016], self._pad_write)
        self.kb_row = 0
        self.kb_col = 0
        self.kb_enabled = False

    # PPU
    def _ppu_write(self, addr, value):
        reg = addr & 7
        if reg == 0:
            if value & 0x80 and not self.ppuctrl & 0x80 and self.vblank:
                self.nmi_pending = True
            self.ppuctrl = value
        elif reg == 6:
            if not self.latch:
                self.ppuaddr = (value << 8) | (self.ppuaddr & 0xFF)
            else:
                self.ppuaddr = (self.ppuaddr & 0xFF00) | value
            self.ppuaddr &= 0x3FFF
            self.latch = not self.latch
        elif reg == 5:
            self.latch = not self.latch
        elif reg == 7:
            self.vram[self.ppuaddr & 0x3FFF] = value
            self._ppu_inc()
        return value

    def _ppu_inc(self):
        self.ppuaddr = (self.ppuaddr + (32 if self.ppuctrl & 4 else 1)) & 0x3FFF

    def _ppu_read(self, addr):
        reg = addr & 7
        if reg == 2:
            value = 0x80 if self.vblank else 0
            self.vblank = False
            self.latch = False
            return value
        if reg == 7:
            value = self.read_buffer
            self.read_buffer = self.vram[self.ppuaddr & 0x3FFF]
            self._ppu_inc()
            return value
        return 0

    # controllers and keyboard
    def _pad_write(self, addr, value):
        if value & 1:
            self.kb_row = 0
            self.kb_col = 0
        else:
            col = (value >> 1) & 1
            if self.kb_col == 1 and col == 0:
                self.kb_row = (self.kb_row + 1) % 10
            self.kb_col = col
        self.kb_enabled = bool(value & 4)
        return value

    def _pad_read(self, addr):
        if addr == 0x4017 and self.keyboard is not None and self.kb_enabled:
            if self.kb_row < 9:
                pressed = self.keyboard[self.kb_row][self.kb_col]  # 4 bits
                return ((~pressed) & 0x0F) << 1
            return 0x1E
        return 0

    # FDS drive
    def _transferring(self):
        return self.fdsctrl & 0x40 and self.fdsctrl & 0x01 and not self.fdsctrl & 0x02

    def _fds_write(self, addr, value):
        if addr == 0x4024:
            self._ack()
            self.pending = False
            # The drive shifts this byte out at the next byte event.
            self.write_latch = value
        elif addr == 0x4025:
            old = self.fdsctrl
            self.fdsctrl = value
            if value & 0x02:
                self.next_block = 0
            if not old & 0x40 and value & 0x40 and self.current is None:
                self._start_block()
            if old & 0x40 and not value & 0x40:
                self._end_block()
            if not value & 0x80:
                self.irq_line = False
        return value

    def _start_block(self):
        self.current = self.next_block
        if self.fdsctrl & 0x04:  # read
            block = self.blocks[self.current] if self.current < len(self.blocks) else []
            self.stream = block + crc_bytes()
            self.stream_pos = 0
            self.capture = None
        else:
            self.capture = []
            self.mark_pending = True
            self.crc_written = 0
        self.next_byte = self.mpu.processorCycles + BYTE_CYCLES
        self.pending = False

    def _end_block(self):
        if self.current is None:
            return
        if self.capture is not None:
            block = self.capture
            if self.current < len(self.blocks):
                self.blocks[self.current] = block
            else:
                self.blocks.append(block)
            self.capture = None
        self.next_block = self.current + 1
        self.current = None
        self.next_byte = None

    def _ack(self):
        self.byte_flag = False
        self.irq_line = False

    def _fds_read(self, addr):
        if addr == 0x4030:
            value = 0x02 if self.byte_flag else 0
            self._ack()
            return value
        if addr == 0x4031:
            self._ack()
            self.pending = False
            return self.data
        if addr == 0x4032:
            value = 0
            if not self.inserted:
                value |= 0x07
            else:
                if self.next_block > len(self.blocks):
                    value |= 0x02
                if self.write_protected:
                    value |= 0x04
            return value | 0x40
        if addr == 0x4033:
            return 0x80
        return 0

    def _tick_drive(self):
        if self.next_byte is None or not self._transferring():
            return
        if self.mpu.processorCycles < self.next_byte:
            return
        self.next_byte += BYTE_CYCLES
        if self.pending and not self.fdsctrl & 0x10:
            self.overruns += 1
        if not self.fdsctrl & 0x04 and self.capture is not None:
            if self.fdsctrl & 0x10:
                # Sending the CRC. Some drives flag these bytes too, so raise
                # the flag and the IRQ if it is enabled.
                self.crc_written += 1
                self.pending = False
                self.byte_flag = True
                if self.fdsctrl & 0x80:
                    self.irq_line = True
                return
            value = self.write_latch
            if self.mark_pending:
                # Zeros form the gap; the $80 start mark begins the block.
                if value:
                    self.marks.append(value)
                    self.mark_pending = False
            else:
                self.capture.append(value)
        self.pending = True
        if self.fdsctrl & 0x04:
            if self.stream_pos < len(self.stream):
                self.data = self.stream[self.stream_pos]
            else:
                self.data = 0
            self.stream_pos += 1
        self.byte_flag = True
        if self.fdsctrl & 0x80:
            self.irq_line = True

    # execution
    def step(self):
        mpu = self.mpu
        if mpu.pc == DELAYMS:
            # Fast-forward the millisecond delay loop, keeping cycle time.
            y = mpu.y or 256
            mpu.processorCycles += y * 1790
            mpu.x = 0
            mpu.y = 0
            mpu.p |= mpu.ZERO
            lo = mpu.stPop()
            hi = mpu.stPop()
            mpu.pc = ((hi << 8) | lo) + 1
        else:
            mpu.step()
        if mpu.processorCycles >= self.next_frame:
            self.next_frame += FRAME_CYCLES
            self.vblank = True
            if self.ppuctrl & 0x80:
                self.nmi_pending = True
        if self.fceumm:
            self.fceumm.tick(mpu.processorCycles - self.last_cycles)
            self.last_cycles = mpu.processorCycles
            irq = self.fceumm.irq
        else:
            self._tick_drive()
            irq = self.irq_line
        if self.nmi_pending:
            self.nmi_pending = False
            mpu.nmi()
        elif irq and not mpu.p & mpu.INTERRUPT:
            mpu.irq()

    def run_until(self, pc, max_cycles=40_000_000):
        limit = self.mpu.processorCycles + max_cycles
        while self.mpu.pc != pc:
            if self.mpu.processorCycles > limit:
                raise TimeoutError("PC $%04X after %d cycles" % (self.mpu.pc, max_cycles))
            self.step()

    def reset(self):
        self.mpu.pc = self.mpu.WordAt(0xFFFC)
        self.mpu.p |= self.mpu.INTERRUPT

    def call(self, address, a=0, x=0, params=(), max_cycles=40_000_000):
        """Calls a BIOS routine from a stub at $0400, followed by 16-bit
        parameter words. Returns (A, X, Y)."""
        stub = [0x20, address & 0xFF, address >> 8]
        for p in params:
            stub += [p & 0xFF, p >> 8]
        end = 0x0400 + len(stub)
        stub += [0x4C, end & 0xFF, end >> 8]
        self.mem.write(0x0400, stub)
        mpu = self.mpu
        mpu.pc = 0x0400
        mpu.sp = 0xFF
        mpu.a = a
        mpu.x = x
        mpu.p = mpu.UNUSED | mpu.INTERRUPT
        self.run_until(end, max_cycles)
        return mpu.a, mpu.x, mpu.y

    def disk_blocks(self):
        return unflatten(self.fceumm.disk) if self.fceumm else self.blocks

    def file_count(self):
        return self.disk_blocks()[1][1]
