# FreeDiskSysROM

This project has one goal - a compatible re-implementation of the Famicom Disk System BIOS under an OSS license. Unlike the Famicom console itself, which has no program ROM built-in, the Famicom Disk System includes an 8 KiB PRG-ROM containing disk I/O routines, VRAM transfer routines, joypad reading code, an animation featuring Mario and Luigi when no disk is present in the drive, and more. The code, data, graphics, music, and animation contained in the original BIOS are copyrighted by Nintendo.

FreeDiskSysROM aims to provide a replacement for the original FDS BIOS that can be freely redistributed and that is capable of running all published FDS software.

# Credits

This repository is a fork maintained by [rom-weaver](https://github.com/rom-weaver), for use as a freely redistributable FDS BIOS in [EmulatorJS](https://github.com/EmulatorJS/EmulatorJS).

- [James Athey](https://github.com/jamesathey) created FreeDiskSysROM and wrote the original BIOS, VRAM, and input routines: [jamesathey/FreeDiskSysROM](https://github.com/jamesathey/FreeDiskSysROM)
- [yeah4578](https://github.com/yeah4578) (Nicholas Qualls) wrote the disk I/O routines and the boot screen: [yeah4578/FreeDiskSysROM](https://github.com/yeah4578/FreeDiskSysROM)
- Changes made in this fork are listed in its git history.

# Audience

## Emulators

Famicom and NES emulators historically require a dump of the Famicom Disk System BIOS to be able to emulate FDS titles. Emulators can ship FreeDiskSysROM with their installers instead of requiring end-users to either copy the ROM out of their own FDS hardware or breaking copyright law by downloading a BIOS rip from elsewhere on the Internet.

## Clone hardware

Modern hardware clones of the FDS RAM Adapter or FPGA re-implementations of the entire Famicom Disk System also need a BIOS.

# Status

## APIs

| Address | Name | # of Games | Implemented |
| ------- | ---- | ------- | ----------- |
| $e149 | Delay131 | | :white_check_mark: |
| $e153 | Delayms | | :white_check_mark: |
| $e161 | DisPFObj | | :white_check_mark: |
| $e16b | EnPFObj | | :white_check_mark: |
| $e171 | DisObj | | :white_check_mark: |
| $e178 | EnObj | | :white_check_mark: |
| $e17e | DisPF | | :white_check_mark: |
| $e185 | EnPF | | :white_check_mark: |
| $e18b | NMI | | :white_check_mark: |
| $e1b2 | VINTWait | | :white_check_mark: |
| $e1c7 | IRQ | | :white_check_mark: |
| $e1f8 | LoadFiles | | :white_check_mark: |
| $e237 | AppendFile | | :white_check_mark: |
| $e239 | WriteFile | | :white_check_mark: |
| $e2b7 | CheckFileCount | | :white_check_mark: |
| $e2bb | AdjustFileCount | | :white_check_mark: |
| $e301 | SetFileCount1 | | :white_check_mark: |
| $e305 | SetFileCount | | :white_check_mark: |
| $e32a | GetDiskInfo | | :white_check_mark: |
| $e3da | AddYtoPtr0A | | :white_check_mark: |
| $e3e7 | GetHardCodedPointers | | :white_check_mark: |
| $e3ea | GetHardCodedPointersWriteProtected | | :white_check_mark: |
| $e445 | CheckDiskHeader | | :white_check_mark: |
| $e484 | GetNumFiles | | :white_check_mark: |
| $e492 | SetNumFiles | | :white_check_mark: |
| $e4a0 | FileMatchTest | 0 | :white_check_mark: |
| $e4da | SkipFiles | 0 | :white_check_mark: |
| $e4f9 | LoadData | | :white_check_mark: |
| $e506 | ReadData | | :white_check_mark: |
| $e5b5 | SaveData | | :white_check_mark: |
| $e64d | WaitForDriveReady | | :white_check_mark: |
| $e685 | StopMotor | | :white_check_mark: |
| $e68f | CheckBlockType | | :white_check_mark: |
| $e6b0 | WriteBlockType | | :white_check_mark: |
| $e6e3 | StartXfer | | :white_check_mark: |
| $e706 | EndOfBlockRead | | :white_check_mark: |
| $e729 | EndOfBlkWrite | | :white_check_mark: |
| $e778 | XferDone | | :white_check_mark: |
| $e794 | Xfer1stByte | | :white_check_mark: |
| $e7a3 | XferByte | | :white_check_mark: |
| $e7bb | VRAMStructWrite | | :white_check_mark: |
| $e844 | FetchDirectPtr | | :white_check_mark: |
| $e86a | WriteVRAMBuffers | | :white_check_mark: |
| $e8b3 | ReadIndividualVRAMBytes | | :white_check_mark: |
| $e8d2 | PrepareVRAMString | | :white_check_mark: |
| $e8e1 | PrepareVRAMStrings | | :white_check_mark: |
| $e94f | GetVRAMBufferByte | | :white_check_mark: |
| $e97d | Pixel2NamConv | | :white_check_mark: |
| $e997 | Nam2PixelConv | | :white_check_mark: |
| $e9b1 | Random | | :white_check_mark: |
| $e9c8 | SpriteDMA | | :white_check_mark: |
| $e9d3 | CounterLogic | | :white_check_mark: |
| $e9eb | ReadPads | | :white_check_mark: |
| $ea1a | ReadDownPads | | :white_check_mark: |
| $ea1f | ReadOrDownPads | | :white_check_mark: |
| $ea36 | ReadDownVerifyPads | | :white_check_mark: |
| $ea4c | ReadOrDownVerifyPads | | :white_check_mark: |
| $ea68 | ReadDownExpPads | | :white_check_mark: |
| $ea84 | VRAMFill | | :white_check_mark: |
| $ead2 | MemFill | | :white_check_mark: |
| $eaea | SetScroll | | :white_check_mark: |
| $eafd | JumpEngine | | :white_check_mark: |
| $eb13 | ReadKeyboard | 0 | :white_check_mark: |
| $ebaf | LoadTileset | | :white_check_mark: |
| $ec22 | UploadObject | | :white_check_mark: |
| $ee17 | StartMotor | | :white_check_mark: |

## Initialization

Every entry point is implemented and covered by the simulator tests below. Not yet done:

- The license screen check. A free BIOS cannot contain Nintendo's license text, so disks boot without it.
- Retrying a failed write a second time, as the original BIOS does.
- Testing against a broad library of commercial disks.

# Building

To build, use [asm6f](https://github.com/freem/asm6f).

```asm6f freedisksys.asm disksys.rom```

The `-l` flag is very useful for development - it shows the addresses assigned
to each instruction, so you can easily see how much room remains for a given
subroutine.

# Testing

`tests/test_bios.py` runs the assembled ROM in a 6502 simulator ([py65](https://github.com/mnaberez/py65)) with a simulated PPU and FDS drive. It covers booting, soft reset, loading files to RAM and VRAM, writing and verifying files, file counts, disk info, error codes, the keyboard, and objects. The disk tests run twice: once against a drive that delivers a byte every 148 CPU cycles, as real hardware does, failing if the BIOS misses a byte; and once against a model of the FCEUmm core's drive, which EmulatorJS uses.

```
pip install py65
python tests/test_bios.py disksys.rom
```

# Using with EmulatorJS

EmulatorJS runs FDS games with its NES core and loads the BIOS from `EJS_biosUrl`:

```js
EJS_core = 'nes';
EJS_gameUrl = 'game.fds';
EJS_biosUrl = 'disksys.rom';
```

Prebuilt `disksys.rom` files are attached to each CI run.

To check a BIOS in an emulator, `python tests/make_demo_disk.py demo.fds` writes a small disk that prints `FREE BIOS OK` using BIOS routines.

# Contributing

Rules:

1. Do not even look at a disassembly of the original FDS BIOS.
1. Only contribute code to which you hold the copyright or which is already under a compatible license.

# License

FreeDiskSysROM is licensed under the GNU LGPL v3 (see `LICENSE`), which builds on the GNU GPL v3 (see `COPYING`). The intent in using this license is to allow anyone to replace the 8 KiB official FDS BIOS with FreeDiskSysROM, whether for commerical or non-commercial purposes, so long as the source of FreeDiskSysROM (including any modifications) is made available to the end-user under the same license.

Although the Famicom does not have an OS or any concept of dynamic linking, the FDS BIOS is analogous to a system library in practice. FDS titles, FDS emulators, and FDS clone systems are all permitted to utilize FreeDiskSysROM without regard to or changes to the licenses of their own code.
