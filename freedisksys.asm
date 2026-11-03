; FreeDiskSysROM
; Copyright (c) 2018 James Athey
;
; This program is free software: you can redistribute it and/or modify it under
; the terms of the GNU Lesser General Public License version 3 as published by
; the Free Software Foundation.
;
; This program is distributed in the hope that it will be useful, but WITHOUT
; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
; FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public License for more
; details.
;
; You should have received a copy of the GNU Lesser General Public License
; along with this program. If not, see <https://www.gnu.org/licenses/>.

; zero-page registers
ZP_PPUCTRL		EQU $FF; value last written to $2000   $80 on reset.
ZP_PPUMASK		EQU $FE; value last written to $2001   $06 on reset
ZP_PPUSCROLL1	EQU $FD; value last written to $2005/1 $00 on reset.
ZP_PPUSCROLL2	EQU $FC; value last written to $2005/2 $00 on reset.
ZP_JOYPAD1		EQU $FB; value last written to $4016   $00 on reset.
ZP_FDSCTRL		EQU $FA; value last written to $4025 $2E on reset.
ZP_EXTCONN		EQU $F9; value last written to $4026 $FF on reset.

; [$0102]/[$0103]: PC action on reset

; PPU registers
PPUCTRL		EQU $2000
PPUMASK		EQU $2001
PPUSTATUS	EQU $2002
OAMADDR		EQU $2003
OAMDATA		EQU $2004
PPUSCROLL	EQU $2005
PPUADDR		EQU $2006
PPUDATA		EQU $2007
OAMDMA		EQU $4014

; undocumented instructions not explicitly supported by asm6f
; TOP (abs)
MACRO TOP address
	DB $0C
	DW #address
ENDM

; Input registers
JOYPAD1 EQU $4016
JOYPAD2 EQU $4017

; FDS registers
IRQLOW		EQU $4020
IRQHIGH		EQU $4021
IRQCTRL		EQU $4022
MASTERIO	EQU $4023
WRITEDATA	EQU $4024
FDSCTRL		EQU $4025
EXTCONNWR	EQU $4026
DISKSTATUS	EQU $4030
READDATA	EQU $4031
DRIVESTATUS	EQU $4032
EXTCONNRD	EQU $4033

; Error codes:
OK EQU $00 ; no error
DISK_NOT_SET EQU $01 ; disk set, ($4032.0) disk not set
POWER_SUPPLY_FAILURE EQU $02 ; battery, ($4033.7) power supply failure
WRITE_PROTECTED EQU $03 ; ($4032.2) disk is write protected
WRONG_MAKER_ID EQU $04 ; Wrong maker ID
WRONG_GAME EQU $05 ; Wrong game
WRONG_GAME_VER EQU $06 ; Wrong game version
WRONG_SIDE_NUM EQU $07 ; a,b side, wrong side number
WRONG_DISK_NUM EQU $08 ; disk no., wrong disk number
WRONG_ADDL_DISK_ID1 EQU $09 ; wrong additional disk ID 1
WRONG_ADDL_DISK_ID2 EQU $0a ; wrong additional disk ID 2
APPROVAL_CHECK_FAILED EQU $20 ; disk trouble, approval check failed
WRONG_SIGNATURE EQU $21 ; disk trouble, '*NINTENDO-HVC*' string in block 1 doesn't match
BLOCK_TYPE_1_EXPECTED EQU $22 ; disk trouble, block type 1 expected
BLOCK_TYPE_2_EXPECTED EQU $23 ; disk trouble, block type 2 expected
BLOCK_TYPE_3_EXPECTED EQU $24 ; disk trouble, block type 3 expected
BLOCK_TYPE_4_EXPECTED EQU $25 ; disk trouble, block type 4 expected
BLOCK_FAILED_CRC EQU $27 ;	disk trouble, ($4030.4) block failed CRC
EOF_READ EQU $28 ; disk trouble, ($4030.6) file ends prematurely during read
EOF_WRITE EQU $29 ; disk trouble, ($4030.6) file ends prematurely during write
DISK_FULL EQU $30 ; disk trouble, ($4032.1) disk is full

MACRO API_ENTRYPOINT address
	IF $ > #address
		ERROR "Previous function overflowed into following public API"
	ELSE
		PAD #address
	ENDIF
ENDM

; Fill with a KIL opcode, so we die immediately if we jump into crazytown
FILLVALUE $72

; Start assembling at the beginning of the FDS ROM area
ORG $E000
DB $00

INCLUDE font.asm
INCLUDE delay.asm
INCLUDE ppumask.asm
INCLUDE nmi.asm
INCLUDE irq.asm

; Loads files specified by DiskID into memory from disk. Load addresses are
; decided by the file's header.
; Parameters: Pointer to Disk ID, Pointer to File List
; Returns: A = error #, Y = # of files loaded
API_ENTRYPOINT $e1f8
LoadFiles:
	LDA #$00
	STA $0e
	LDA #$ff
	JSR GetHardCodedPointers
	LDA $101
	PHA
	JSR CheckDiskHeader
	JSR GetNumFiles
	LDA $06
	BEQ @done ; a disk with no files would otherwise loop 256 times
@FileLoop:
	LDA #$03
	JSR CheckBlockType
	JSR FileMatchTest
	JSR LoadData
	DEC $06
	BNE @FileLoop
@done:
	PLA
	STA $101
	LDY $0e ; number of files loaded
	JSR XferDone
	RTS

; Appends the file data given by DiskID to the disk. This means that the file
; is tacked onto the end of the disk, and the disk file count is incremented.
; The file is then read back to verify the write. If an error occurs during
; verification, the disk's file count is decremented (logically hiding the
; written file).
; Parameters: Pointer to Disk ID, Pointer to File Header
; Returns: A = error #
API_ENTRYPOINT $e237
AppendFile:
	LDA #$ff

; Same as "Append File", but instead of writing the file to the end of the
; disk, A specifies the sequential position on the disk to write the file (0
; is the first). The disk's file count becomes A + 1, so the written file stays
; visible and any files after it are hidden.
; Parameters: Pointer to Disk ID, Pointer to File Header, A = file #
; Returns: A = error #
API_ENTRYPOINT $e239
WriteFile:
	STA $05
	LDA #$ff
	JSR GetHardCodedPointersWriteProtected
	LDA $101
	PHA

	JSR CheckDiskHeader;write data pass
	JSR GetNumFiles
	LDA $05
	CMP #$ff
	BNE @haveFileNum
	LDA $06 ; appending, so the new file goes after the last one
	STA $05
@haveFileNum:
	STA $06
	JSR SkipFiles
	LDA #$03
	JSR WriteBlockType
	LDA #$00
	JSR SaveData;write the file to disk

	JSR CheckDiskHeader;verify write pass
	JSR GetNumFiles
	LDA $05
	STA $06
	JSR SkipFiles
	LDA #$03
	JSR CheckBlockType
	LDA #$FF
	JSR SaveData;verify written data. A mismatch exits with error $26.

	; The written file stays visible and any files after it are hidden.
	JSR CheckDiskHeader;adjust file count pass
	LDX $05
	INX
	TXA
	JSR SetNumFiles
	PLA
	STA $101
	LDA #OK
	RTS

; Reads in disk's file count, compares it to A, then sets the disk's file count
; to A.
; Parameters: Pointer to Disk ID, A = # to set file count to
; Returns: A = error #
API_ENTRYPOINT $e2b7
CheckFileCount:
	LDX #$ff
	NOP
	DB $2C ; BIT abs: skip the LDX #$00 of AdjustFileCount

; Reads in disk's file count, decrements it by A, then writes the new value
; back.
; Parameters: Pointer to Disk ID, A = number to reduce current file count by
; Returns: A = error #
API_ENTRYPOINT $e2bb
AdjustFileCount:
	LDX #$00
	STX $09 ; $ff = CheckFileCount, $00 = AdjustFileCount
	JSR GetHardCodedPointersWriteProtected ; A goes to $02
	LDA $101
	PHA
	JSR CheckDiskHeader
	JSR GetNumFiles
	LDA $06
	CMP $02
	BCS @inRange
	LDA #$31 ; A is greater than the file count
	JMP ErrorOccurred
@inRange:
	BIT $09
	BMI @setCount
	SBC $02 ; carry is still set from the CMP
	STA $02
@setCount:
	JSR CheckDiskHeader
	LDA $02
	JSR SetNumFiles
	PLA
	STA $101
	LDA #OK
	RTS

; Set the file count to A + 1
; Parameters: Pointer to Disk ID, A = file count minus one = # of the last file
; Returns: A = error #
API_ENTRYPOINT $e301
SetFileCount1:
	tax
	inx
	txa
	nop

; Set the file count to A
; Parameters: Pointer to Disk ID, A = file count
; Returns: A = error #
API_ENTRYPOINT $e305
SetFileCount:
	JSR GetHardCodedPointersWriteProtected ; single pointer (disk ID), A goes to $02
	LDA $101
	PHA
	JSR CheckDiskHeader ; leaves the disk at block 2, the file count
	LDA $02
	JSR SetNumFiles
	PLA
	STA $101
	LDA #OK
	RTS

; Fills provided DiskInfo structure with data read off the current disk.
; DiskInfo layout: 10 Disk ID bytes, file count, then file ID and 8-byte name
; for each file, then disk size (big endian). Disk size is the sum of every
; file's size plus 261 per file.
; Parameters: Pointer to Disk Info
; Returns: A = error #
; Affects: $00-$0F
API_ENTRYPOINT $e32a
GetDiskInfo:
	LDA #$00
	JSR GetHardCodedPointers ; ($00) = DiskInfo
	LDA $101
	PHA
	LDA #$00
	STA $0e ; disk size, low byte
	STA $0f ; disk size, high byte
	JSR StartXfer
	LDY #$00
@diskIdLoop:
	JSR XferByte
	STA ($00),y
	INY
	CPY #10
	BNE @diskIdLoop
	LDY #31 ; skip the boot file ID and the rest of block 1
@skipBlock1:
	JSR XferByte
	DEY
	BNE @skipBlock1
	JSR EndOfBlockRead
	JSR GetNumFiles
	LDA $06
	LDY #10
	STA ($00),y
	INY
	STY $05 ; next DiskInfo index
	LDA $06
	BEQ @done
@fileLoop:
	LDA #$03
	JSR CheckBlockType
	JSR XferByte ; file number, not reported
	LDX #9 ; file ID and 8-byte name
@nameLoop:
	JSR XferByte
	LDY $05
	STA ($00),y
	INC $05
	DEX
	BNE @nameLoop
	JSR XferByte ; load address, not reported
	JSR XferByte
	JSR XferByte
	STA $0c ; file size
	JSR XferByte
	STA $0d
	JSR XferByte ; file type, not reported
	; disk size += file size + 261 ($105)
	LDA $0c
	CLC
	ADC $0e
	STA $0e
	LDA $0d
	ADC $0f
	STA $0f
	LDA $0e
	CLC
	ADC #$05
	STA $0e
	LDA $0f
	ADC #$01
	STA $0f
	JSR EndOfBlockRead
	LDA #$04
	JSR CheckBlockType
@skipData:
	JSR DecPtr0C
	BCC @endData
	JSR XferByte
	JMP @skipData
@endData:
	JSR EndOfBlockRead
	DEC $06
	BNE @fileLoop
@done:
	LDY $05
	LDA $0f
	STA ($00),y
	INY
	LDA $0e
	STA ($00),y
	PLA
	STA $101
	JMP XferDone

; Adds Y to the 16-bit pointer at $0A.
; Parameters: Y = value to add
; Affects: A, $0A, $0B
API_ENTRYPOINT $e3da
AddYtoPtr0A:
	TYA
	CLC
	ADC $0a
	STA $0a
	BCC +
	INC $0b
+:
	RTS

INCLUDE gethardcodedpointers.asm

; Compares the first 10 bytes on the disk coming after the FDS string, to 10
; bytes pointed to by Ptr($00). To bypass the checking of any byte, a -1 can be
; placed in the equivelant place in the compare string. Otherwise, if the
; comparison fails, an appropriate error will be generated.
; Parameters: Pointer to 10 byte string at $00
API_ENTRYPOINT $e445
CheckDiskHeader:
	JSR StartXfer
	LDY #$ff
@loop:
	INY
	CPY #10
	BCS @endLoop
	JSR XferByte
	CMP ($00),y
	BEQ @loop
	LDA ($00),y
	CMP #$FF
	BEQ @loop
	;failed comparison
	INY
	TYA
	CMP #$06
	BCS @errorCode
	ADC #$03
	CMP #$05
	BCC @errorCode
	LDA #$05
@errorCode:
	TAX
	JSR $E77F
@endLoop:
	JSR XferByte;get boot file ID
	STA $08
	LDY #30
@waitforskip:
	JSR XferByte
	DEY
	BNE @waitforskip
	JSR EndOfBlockRead
	RTS

; Reads number of files stored on disk, stores the result in $06
API_ENTRYPOINT $e484
GetNumFiles:
	LDA #$02
	JSR CheckBlockType
	JSR XferByte
	STA $06
	JSR EndOfBlockRead
	RTS

; Writes new number of files to disk header.
; Parameters: A = number of files
API_ENTRYPOINT $e492
SetNumFiles:
	PHA
	LDA #$02
	JSR WriteBlockType
	PLA
	JSR Xfer1stByte ; writes rewrite $4025 for every byte, which FCEUmm needs
	JSR EndOfBlkWrite
	RTS

; Uses a byte string pointed at by Ptr($02) to tell the disk system which files
; to load. The file ID's number is searched for in the string. If an exact
; match is found, [$09] is 0'd, and [$0E] is incremented. If no matches are
; found after 20 bytes, or a -1 entry is encountered, [$09] is set to -1. If
; the first byte in the string is -1, the BootID number is used for matching
; files (any FileID that is not greater than the BootID qualifies as a match).
; Parameters: Pointer to FileID list at $02
API_ENTRYPOINT $e4a0
FileMatchTest:
	JSR Xfer1stByte
	JSR XferByte; get file id
	STA $09;let $09 be file ID until load is decided

	LDA #$08
	STA $101;skip 8 bytes (the file name)
	CLI

	LDY #$00
@loop:
	LDA ($02),Y
	CMP #$ff
	BEQ @endlist
	CMP $09
	BEQ @load
	INY
	CPY #20
	BNE @loop

@endlist:
	TYA
	BNE @noload

@boot:
	LDA $08
	CMP $09
	BCC @noload
@load:
	INC $0e
	LDA #$00
	BEQ @end
@noload:
	LDA #$ff
@end:
	STA $09

@waitforskip:
	LDA $101
	BNE @waitforskip

	RTS

; Skips over specified number of files.
; Parameters: Number of files to skip in $06
; Affects: $06, $09, $0A-$0D, $0F
API_ENTRYPOINT $e4da
SkipFiles:
	LDA $06
	BEQ @done
@loop:
	LDA #$03
	JSR CheckBlockType
	LDY #10 ; file number, file ID, and 8-byte name
@skipHeader:
	JSR XferByte
	DEY
	BNE @skipHeader
	LDA #$ff ; read the file without storing it
	STA $09
	JSR LoadData
	DEC $06
	BNE @loop
@done:
	RTS

;load if $09 is 0, otherwise skip
API_ENTRYPOINT $e4f9
LoadData:
	LDY #$00
@setupLoop:
	JSR Xfer1stByte
	STA $0a,y
	INY
	CPY #$04
	BNE @setupLoop

API_ENTRYPOINT $e506
ReadData:
	JSR XferByte
	STA $0f ; file type. $05 stays free for WriteFile's file number.
	BEQ @notVram
	BIT $09
	BMI @notVram;if dummy read, don't set up PPU for write
	JSR DisPFObj
	LDA $2002;reset PPU data latch
	LDA $0b
	STA PPUADDR
	LDA $0a
	STA PPUADDR
	LDA #$20
	STA $0b
	LDA #$07
	STA $0a
@notVram:
	JSR EndOfBlockRead
	LDA #$04
	JSR CheckBlockType
	LDY #$00
@loopDec0C:
	JSR DecPtr0C;decrement before loop to prevent off-by-one
	BCC @endloop;because eof is determined by underflow
@loop:
	JSR XferByte ; CheckBlockType already enabled transfer IRQs
	BIT $09
	BMI @loopDec0C;if $09 is $ff, don't store data
	LDY $0f
	BEQ @storePRG
	STA PPUDATA
	JMP @loopDec0C ; a BNE here would fall through when the byte is 0
@storePRG:
	LDY #$00
	STA ($0a),y
	JSR Inc0ADec0C
	BCS @loop
@endloop:
	JSR EndOfBlockRead
	RTS

; Writes or verifies one file: the rest of the header block (whose block type
; was already transferred), then the data block.
; Parameters: A = $00 to write, $ff to verify; ($02) = File Header; $05 = file
;             number on disk
; Returns: on a verify mismatch, exits through ErrorOccurred with error $26
; Affects: $07-$0E
API_ENTRYPOINT $e5b5
SaveData:
	STA $09
	LDY #$0b
	LDA ($02),y;get file size
	STA $0c
	INY
	LDA ($02),y
	STA $0d
	LDY #$0e
	LDA ($02),y;get file address
	STA $0a
	INY
	LDA ($02),y
	STA $0b
	INY
	LDA ($02),y;get file location (RAM/VRAM)
	STA $0e; 0 means CPU RAM

	LDA $05 ; file number
	JSR XferOrVerify
	LDY #$00
@headerLoop:
	LDA ($02),y ; file ID, name, load address, size, and type
	JSR XferOrVerify
	INY
	CPY #$0e
	BNE @headerLoop
	JSR EndOfBlockXfer
	LDA #$04
	JSR StartDataBlock

	LDA $0e
	BEQ @begin
	JSR DisPFObj
	BIT PPUSTATUS
	LDA $0b
	STA PPUADDR
	LDA $0a
	STA PPUADDR
	LDA PPUDATA ; VRAM reads are buffered, so discard the first one
@begin:
	; This loop is inlined because a byte arrives about every 148 cycles.
@dataLoop:
	LDA $0c ; bytes left
	ORA $0d
	BEQ @end
	LDA $0e
	BNE @VRAMSource
	LDY #$00
	LDA ($0a),y
	INC $0a
	BNE @xfer
	INC $0b
	JMP @xfer
@VRAMSource:
	LDA PPUDATA
@xfer:
	BIT $09
	BMI @verify
	JSR Xfer1stByte
	JMP @next
@verify:
	JSR XferOrVerify
@next:
	LDA $0c
	BNE +
	DEC $0d
+:
	DEC $0c
	JMP @dataLoop
@end:
	JMP EndOfBlockXfer

API_ENTRYPOINT $e64d
WaitForDriveReady:
	JSR StopMotor
	LDY #$00
	JSR Delayms
	JSR Delayms
	JSR StartMotor
	BIT EXTCONNRD
	BMI @wait
	LDA #$02
	JSR ErrorOccurred
@wait:
	LDA DRIVESTATUS
	AND #$01
	JSR ErrorNotZero
	LDA EXTCONNRD
	LDA DRIVESTATUS
	AND #$02
	BNE @wait
	RTS

API_ENTRYPOINT $e685
StopMotor:
	LDA ZP_FDSCTRL
	ORA #$02
	AND #$2e
	STA FDSCTRL
	RTS

API_ENTRYPOINT $e68f
CheckBlockType:
	STA $07
	LDY #$05
	JSR Delayms;wait 5ms to avoid any bits near the start of the gap that may be set in error
	LDA ZP_FDSCTRL
	ORA #$40
	STA ZP_FDSCTRL
	STA FDSCTRL
	JSR Xfer1stByte
	CMP $07
	BEQ @end
	CLC
	LDA $07
	ADC #$21
	JSR $E77F
@end:
	RTS

API_ENTRYPOINT $e6b0
WriteBlockType:
	PHA
	LDA ZP_FDSCTRL
	AND #$2B
	STA ZP_FDSCTRL
	STA FDSCTRL
	LDY #$0a
	JSR Delayms;wait 10ms to make lots of space between the files
	STY WRITEDATA;Y is 0 after Delayms, so the gap stays zeros
	LDA ZP_FDSCTRL
	ORA #$40
	STA ZP_FDSCTRL
	STA FDSCTRL
	LDA #$80
	JSR Xfer1stByte;the start mark that ends the gap
	PLA
	JMP Xfer1stByte



API_ENTRYPOINT $e6e3-14
FDSString:
	.byte "*CVH-ODNETNIN*"
API_ENTRYPOINT $e6e3
StartXfer:
	JSR WaitForDriveReady
	LDY #$00
	JSR Delayms
	LDA #$01
	JSR CheckBlockType
	LDY #13;length of FDS string
@loop:
	JSR Xfer1stByte
	CMP FDSString,y
	BNE @error
	DEY
	BPL @loop
	RTS
@error:
	LDA #WRONG_SIGNATURE
	JSR ErrorOccurred

API_ENTRYPOINT $e706
EndOfBlockRead:
	JSR XferByte
	JSR XferByte
	LDA #$28
	BIT DISKSTATUS
	BVS @error
	LDA DISKSTATUS
	AND #$10
	BNE @CRCerror
	JSR XferDone
	RTS
@CRCerror:
	LDA #$27
@error:
	JSR ErrorOccurred

; Finishes writing a block: has the drive write the block's CRC, checks that
; the disk did not run out, then switches the drive back to read mode.
; Returns: on a full disk, exits through ErrorOccurred with error $30
API_ENTRYPOINT $e729
EndOfBlkWrite:
	; A byte written to $4024 goes out at the next byte event, so wait for one
	; more event before switching to CRC, or the block loses its last byte.
	JSR Xfer1stByte
	LDA ZP_FDSCTRL
	ORA #$10 ; transfer the CRC
	AND #$7F ; no transfer IRQs: nothing services them during the CRC
	STA ZP_FDSCTRL
	STA FDSCTRL
	; Drives differ on flagging CRC bytes, so wait out the two CRC bytes with
	; a delay: about 450 cycles until the second one finishes shifting out.
	JSR Delay131
	JSR Delay131
	JSR Delay131
	LDA DRIVESTATUS
	AND #$02
	BEQ @ok
	LDA #DISK_FULL
	JMP ErrorOccurred
@ok:
	LDA ZP_FDSCTRL
	ORA #$04 ; read mode
	STA ZP_FDSCTRL
	JMP XferDone

API_ENTRYPOINT $e778
XferDone:
	LDA #$00
	BEQ EndRead

API_ENTRYPOINT $e77f
ErrorNotZero:
	BNE ErrorOccurred
	RTS
ErrorOccurred:
	JMP ErrorUnwind
EndRead:
	PHA
	LDA ZP_FDSCTRL
	AND #$2F
	STA ZP_FDSCTRL
	STA FDSCTRL
	PLA
	CLI
	RTS

; Waits for the first byte to be transferred between the drive and RAM adapter.
; Does not know or care whether it's a read or write. An interrupt is involved,
; but the stack is manipulated in the ISR such that control returns to the
; caller of this function as if it were a simple subroutine.
; Parameters: A = byte to write to disk (if this is a write)
; Affects: $101, $FA
; Returns: A = byte read from disk (if this is a read)
API_ENTRYPOINT $e794
Xfer1stByte:
	pha
	lda #$40
	sta $101
	asl a
	ora $fa
	sta $fa
	sta $4025
	pla

; Waits for a byte to be transferred between the drive and the RAM adapter.
; Does not know or care whether it's a read or write. An interrupt is involved,
; but the stack is manipulated in the ISR such that control returns to the
; caller of this function as if it were a simple subroutine.
; Parameters: A = byte to write to disk (if this is a write)
; Affects: X
; Returns: A = byte read from disk (if this is a read)
API_ENTRYPOINT $e7a3
XferByte:
	cli
	jmp XferByte+1;infinite loop while waiting for interrupt

API_ENTRYPOINT $e7a7
Inc0ADec0C:
	INC $0a
	BNE DecPtr0C
	INC $0b
DecPtr0C:
	LDA $0c
	SEC
	SBC #$01
	STA $0c
	LDA $0d
	SBC #$00
	STA $0d
	RTS

; VRAM Buffers
;  The structure of VRAM buffers are as follows:
;
; SIZE   CONTENTS
; 2      VRAM Address (big endian)
; 1      bit 0-5 length of data ($0 means a length of 64)
;        bit 6 : 0 = copy, 1 = fill
;        bit 7 : 0 = increment by 1, 1 = increment by 32
; n      Data to copy to VRAM
; .....  repeated as many times as needed
; 1      $ff
;
; * The main structure is terminated by a byte >= $80 (High address is always
;   supposed to be in $00..$3f range)
; * $4c is a "call" command. The 2 bytes that follow is the address of a sub-
;   VRAM structure. The sub-structure can call another sub-structure and so on.
; * $60 is a "return" command. It will terminate a sub-structure.
; * If Fill mode is used, the routine takes only 1 byte of data which is
;   repeated.
;
; The VRAM buffer is located at $300-$3xx. $300 holds the size of the buffer
; (maximum), and $301 holds the end index of the buffer. The actual buffer lies
; at $302-$3xx, and is of variable length.
;
; * $300 is initialized to the value $7d, effectively making the buffer lie at
;   $300-$37f. It's possible to change the value here to make it bigger or
;   smaller, but the biggest possible value is $fd, making the buffer lie at
;   $300-$3ff.
; * Format of the buffer is equivalent to the VRAM structure above, except that
;   there are no sub-structures, no increment by 32 flag and no fill flag.
; * For this reason, the VRAM buffer at $302 can be used as a sub-structure.
; * A call to WriteVRAMBuffers will execute faster than a call to
;   VRAMStructWrite with $302 as an argument, but both will have the same
;   effect.
;
; The structure of the VRAM read buffer itself is trivial - only single bytes
; are read (there's no runs of data). All reads are mapped to a structure of 3
; bytes in the read buffer:
;
; SIZE   CONTENTS
; 2      VRAM Address (big endian)
; 1      data
;
; Therfore, for each byte which is read from VRAM, 3 bytes have to be reserved
; in the read buffer. Once data from VRAM has been read, if it must be written
; back after a modification, the user need to copy it to the write buffer
; manually.

INCLUDE vramstructwrite.asm
INCLUDE fetchdirectptr.asm
INCLUDE vrambuffers.asm
INCLUDE vramstrings.asm
INCLUDE getvrambufferbyte.asm
INCLUDE nametable.asm
INCLUDE random.asm

; Run Sprite DMA from RAM $200-$2FF
; Affects: A
API_ENTRYPOINT $e9c8
SpriteDMA:
	LDA #0
	STA OAMADDR
	LDA #$02
	STA OAMDMA
	RTS

INCLUDE counterlogic.asm
INCLUDE gamepads.asm
INCLUDE vramfill.asm

; Fill RAM pages with specified value.
; Parameters: A = fill value, X = first page #, Y = last page #
; Affects: A, X, Y, $00, $01
API_ENTRYPOINT $ead2
MemFill:
	; Start from the high end and count down
	; The address of the start of the last page is just the Y register in the high byte of the pointer and 0 in the low byte
	STY $01
@outerloop:
	LDY #0
	STY $00
@loop:
	STA ($00),Y
	INY
	BNE @loop
	DEC $01 ; work on the next page down
	CPX $01
	BMI @outerloop ; cover the X < $01 case
	BEQ @outerloop ; cover the X == $01 case
	RTS

; Set scroll registers according to values in $FC, $FD and $FF.
; Should typically be called in VBlank after VRAM updates
; Parameters: $FC, $FD, $FF
; Affects: A
API_ENTRYPOINT $eaea
SetScroll:
	LDA PPUSTATUS ; reset PPU's "w" register to 0
	LDA ZP_PPUSCROLL1
	STA PPUSCROLL
	LDA ZP_PPUSCROLL2
	STA PPUSCROLL
	LDA ZP_PPUCTRL
	STA PPUCTRL
	RTS

; The instruction calling this is supposed to be followed by a jump table
; (16-bit pointers little endian, up to 128 pointers). A is the entry # to jump
; to, return address on stack is used to get jump table entries.
; Parameters: A = Jump table entry
; Affects: A, X, Y, $00, $01
API_ENTRYPOINT $eafd
JumpEngine:
	; the top of the stack is 1 less than the address of the table
	SEC   ; to rotate a 1 into the LSB, set the carry
	ROL A ; Each entry is 2 bytes, so multiply A by two to get the offset
	TAY   ; now A is freed up and Y has the offset, which will be useful later
; get the address of the jump table
	PLA ; low byte of the jump table address
	STA $00
	PLA ; high byte of the jump table address
	STA $01
; post-indexed indirect load of the entry in the jump table
	LDA ($00),Y
	TAX
	INY
	LDA ($00),Y
	STX $00
	STA $01
; (indirect) jump!
	JMP ($00)

INCLUDE keyboard.asm
INCLUDE loadtileset.asm
INCLUDE uploadobject.asm

API_ENTRYPOINT $ee17
StartMotor:
	ORA #$01
	AND #$2D
	STA ZP_FDSCTRL
	STA FDSCTRL
	RTS

; private functions

; Returns from a disk API with an error. GetHardCodedPointers saved the stack
; position in $04, and every disk API pushes $0101 right after calling it, so
; that byte sits just below the saved position.
; Parameters: A = error #
ErrorUnwind:
	LDX $04
	TXS
	LDY $0100,x
	STY IRQ_ACTION
	PHA
	LDA ZP_FDSCTRL
	ORA #$04 ; leave the drive in read mode, even after a failed write
	STA ZP_FDSCTRL
	PLA
	JMP EndRead

; Writes A to the disk, or reads a byte and compares it to A, depending on $09.
; Writes go through Xfer1stByte because FCEUmm only signals the next byte to
; write after a $4025 write. Reads use the faster XferByte.
; Parameters: A = byte, $09 = $00 to write, $ff to verify
; Returns: on a mismatch, exits through ErrorOccurred with error $26
; Affects: A, $08
XferOrVerify:
	BIT $09
	BMI @verify
	JMP Xfer1stByte
@verify:
	STA $08
	JSR XferByte
	CMP $08
	BNE @mismatch
	RTS
@mismatch:
	LDA #$26 ; readback verification failed
	JMP ErrorOccurred

; Ends the current block with EndOfBlkWrite or EndOfBlockRead, depending on $09.
EndOfBlockXfer:
	BIT $09
	BMI @read
	JMP EndOfBlkWrite
@read:
	JMP EndOfBlockRead

; Starts the next block with WriteBlockType or CheckBlockType, depending on $09.
; Parameters: A = block type
StartDataBlock:
	BIT $09
	BMI @read
	JMP WriteBlockType
@read:
	JMP CheckBlockType

; Checks whether the little-endian address provided in ($02) plus the offset in
; $04 is in the range $3Fxx (or one of its mirrors). Checks the current PPU
; increment mode to do the correct arithmetic. If the current PPU address is in
; the palette, reset to $0000. Assumes that the PPUADDR latch is currently
; clear.
; Parameters: $00-$01 = PPU address, $02 = offset
; Affects: A, X, Y
PreventPalettePpuAddr:
	LDA #%00000100 ; increment mode flag bit test
	AND ZP_PPUCTRL
	BEQ @incr1
	LDA $02 ; low address byte
	LDY $03 ; high address byte
	LDX $04 ; offset
	BEQ @check ; if the offset is 0, jump straight to the check
@incr32:
	CLC
	ADC #32 ; for (X = $04; X != 0; X--) $02,$03 += 32;
	BCC @nextiter
	INY
@nextiter:
	DEX
	BNE @incr32
	BEQ @check
@incr1:
	LDA $02  ; low address byte
	LDY $03  ; high address byte
	CLC
	ADC $04  ; add length to low address byte
	BCC @check
	INY ; add C to high address byte
@check:
	TYA
	AND #$3F ; we might be in the mirror $7Fxx range instead of $3Fxx
	CMP #$3F ; now check for exactly $3F
	BNE @done
	LDA #0 ; reset PPUADDR to 0 to get it out of the palette area
	STA PPUADDR
	STA PPUADDR
@done:
	RTS

INCLUDE reset.asm

; the hard-coded interrupt vectors at the end of ROM
API_ENTRYPOINT $fffa
	DW NMI
	DW RESET
	DW IRQ
