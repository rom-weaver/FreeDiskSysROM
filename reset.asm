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

;[$0102]/[$0103]: PC action on reset
;($DFFC):         disk game reset vector     (if [$0102] = $35, and [$0103] = $53 or $AC)
RESET_ACTION_1 EQU $0102
RESET_ACTION_2 EQU $0103
DISK_RESET_VEC EQU $DFFC


RESET:
    SEI ; disable interrupts
    CLD ; clear decimal mode flag, which doesn't work on the 2A03 anyway
    LDX #$FF
    TXS

    ; don't allow NMIs until we're ready
    LDY #$00
    STY ZP_PPUCTRL
    STY PPUCTRL

    ; disable rendering, but enable left 8 pixels
    LDA #$06
    STA ZP_PPUMASK
    STA PPUMASK

    ; disable disk I/O and IRQs
    STY IRQCTRL
    STY MASTERIO
    ; enable disk I/O
    LDA #$83
    STA MASTERIO

    LDA #$40
    STA $4015;disable audio
    STA $4017;disable frame interrupt



    ; the PPU takes a while to warm up. Wait for at least 2 VBlanks before
    ; trying to set the scroll registers
    LDX #2
@waitForVBL:
    LDA PPUSTATUS
    BPL @waitForVBL
    DEX
    BNE @waitForVBL

    ; clear the scroll registers
    LDA #0
    STA ZP_PPUSCROLL1
    STA PPUSCROLL
    STA ZP_PPUSCROLL2
    STA PPUSCROLL

    ; nothing has been written to the joypads or expansion port
    STA ZP_JOYPAD1

    LDA #$2E
    STA ZP_FDSCTRL
    STA FDSCTRL

    LDA #$FF
    STA ZP_EXTCONN
    STA EXTCONNWR

    LDA #$C0 ; game NMI #3
    STA NMI_ACTION
    LDA #$80 ; BIOS acknowledge and delay
    STA IRQ_ACTION

    ; A game that is already loaded restarts at its own reset vector.
    LDA RESET_ACTION_1
    CMP #$35
    BNE @coldBoot
    LDA RESET_ACTION_2
    CMP #$AC
    BEQ @softReset
    CMP #$53
    BNE @coldBoot
@softReset:
    LDA #$53 ; the game has already booted once
    STA RESET_ACTION_2
    JSR HandOffPpu
    JMP (DISK_RESET_VEC)
@coldBoot:

    ; prepare the VRAM buffer
    LDA #$7D ; initial write buffer found at $302-$37F
    STA $300
    LDA #0
    STA $301
    LDA #$80 ; "end" opcode for the write buffer
    STA $302

    LDA #$04; 1BPP using colors 0 and 1
    LDY #$00; to VRAM $0000
    LDX #40 ; load 40 characters
    JSR LoadTileset
    .word $E000

    LDA #$20; VRAM $[20]00
    LDX #$24; space
    LDY #$00; attribute 0
    JSR VRAMFill; fill the nametable with spaces

    LDA #$3F
    STA PPUADDR
    LDY #$00
    STY PPUADDR
@paletteLoop:
    LDA Palette,y
    STA PPUDATA
    INY
    CPY #$04
    BNE @paletteLoop

@prepareInsertDiskStr:
    LDA #$21
    LDX #$C9
    LDY #12
    JSR PrepareVRAMString; "INSERT DISK"
    .word InsertDiskStr

    JSR EnPF
@LoadInsertedDisk:
    JSR VINTWait
    JSR WriteVRAMBuffers
    JSR SetScroll
    LDA DRIVESTATUS
    AND #$01
    BNE @LoadInsertedDisk

    LDA #$21
    LDX #$C9
    LDY #12
    JSR PrepareVRAMString; "LOADING"
    .word LoadingStr
    JSR VINTWait
    JSR WriteVRAMBuffers
    JSR SetScroll

    JSR LoadFiles
    .word BootList
    .word BootList
    BNE @printErrorCode
    LDA #$35; game is loaded
    STA $102
    LDA #$AC; first boot
    STA $103

    LDA #$80
    STA $101
    JSR HandOffPpu

    LDA #$C0
    STA $100

    JMP (DISK_RESET_VEC)



@printErrorCode:
    TAX

    AND #$0f
    STA $0f; separate the nibbles of the error code to be printed
    TXA
    LSR A
    LSR A
    LSR A
    LSR A
    STA $0e


    LDA #$21
    LDX #$C9
    LDY #10
    JSR PrepareVRAMString; "ERROR NO."
    .word ErrorStr

    LDA #$21
    LDX #$D3
    LDY #$02
    JSR PrepareVRAMString; print the error code
    .word $000e
@errorLoop:
    JSR VINTWait
    JSR WriteVRAMBuffers
    JSR SetScroll
    LDA DRIVESTATUS
    AND #$01
    BEQ @errorLoop

    JSR DisPF
    LDA #$20
    LDX #$24
    LDY #$00
    JSR VRAMFill
    JSR EnPF

    JMP @prepareInsertDiskStr



Palette:
    .byte $0F,$30,$10,$00

InsertDiskStr:
    .byte $12,$17,$1c,$0e,$1b,$1d,$24,$0d,$12,$1c,$14,$24;"INSERT DISK "
LoadingStr:
    .byte $24,$24,$15,$18,$0a,$0d,$12,$17,$10,$24,$24,$24;"  LOADING   "
ErrorStr:
    .byte $0e,$1b,$1b,$18,$1b,$24,$17,$18,$26,$24;"ERROR NO. "
StrEnd:
BootList:
    .byte $ff,$ff,$ff,$ff,$ff,$ff
    .byte $00,$00
    .byte $ff,$ff


; Start the game with NMIs on, as some games expect, but just after a vblank,
; so the game gets a whole frame to set itself up before its first NMI.
HandOffPpu:
    PHP ; VINTWait returns with IRQs masked; keep the caller's I flag
    JSR VINTWait
    PLP
    LDA PPUSTATUS ; clear the vblank flag so enabling NMIs doesn't fire one now
    LDA #$80
    STA ZP_PPUCTRL
    STA PPUCTRL
    RTS
