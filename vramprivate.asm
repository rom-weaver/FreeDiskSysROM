; FreeDiskSysROM
; Copyright (c) 2026 rom-weaver contributors
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

; Private VRAM helpers. They live outside the fixed API slots because they do
; not fit in them, and they use only the zero-page bytes the APIs document.

; Fetch the direct pointer that follows the caller's caller's JSR into $00-$01,
; and fix that return address to skip it. Unlike FetchDirectPtr, it does not
; touch $05-$06.
; Affects: A, X, Y, $00, $01
FetchPtr00:
	TSX
	LDA $103,X ; return address of the caller's caller, minus 1
	STA $00
	CLC
	ADC #2
	STA $103,X
	LDA $104,X
	STA $01
	ADC #0
	STA $104,X
	LDY #2
	LDA ($00),Y ; high byte of the direct pointer
	PHA
	DEY
	LDA ($00),Y ; low byte
	STA $00
	PLA
	STA $01
	RTS

; If the PPU address high byte in A is in the palette, move PPUADDR to $3F00 and
; then $0000, so the PPU does not draw palette colors while rendering is off.
; Affects: A
LeavePalette:
	AND #$3F
	CMP #$3F
	BNE +
	STA PPUADDR
	LDA #$00
	STA PPUADDR
	STA PPUADDR
	STA PPUADDR
+:
	RTS

VRAMStructWriteImpl:
	LDA ZP_PPUCTRL
	AND #%11111011 ; increment by 1 unless a structure asks for 32
	STA ZP_PPUCTRL
@structure:
	LDA PPUSTATUS ; clear PPUADDR latch
	LDY #0
	LDA ($00),Y ; high byte of the destination PPU address, or a command
	BPL +
	RTS         ; >= $80 ends the structure
+:
	CMP #$4C    ; "call" a sub-structure
	BEQ @call
	CMP #$60    ; "return" from a sub-structure
	BEQ @return
	STA PPUADDR
	INY
	LDA ($00),Y
	STA PPUADDR
	INY
	LDA ($00),Y ; length and flags
	BPL @incr1
	LDA ZP_PPUCTRL
	ORA #%00000100 ; increment by 32
	BNE @setincr
@incr1:
	LDA ZP_PPUCTRL
	AND #%11111011
@setincr:
	STA ZP_PPUCTRL
	STA PPUCTRL
	LDA ($00),Y
	AND #%00111111 ; a length of 0 means 64
	BNE +
	LDA #64
+:
	TAX
	LDA ($00),Y
	AND #%01000000
	BNE @fill
@copy:
	INY
	LDA ($00),Y
	STA PPUDATA
	DEX
	BNE @copy
	BEQ @next
@fill:
	INY
	LDA ($00),Y
@fillLoop:
	STA PPUDATA
	DEX
	BNE @fillLoop
@next:
	; Y is the offset of this structure's last byte
	TYA
	PHA
	LDY #0
	LDA ($00),Y
	JSR LeavePalette
	PLA
	SEC ; skip past the last byte too
	ADC $00
	STA $00
	BCC @structure
	INC $01
	JMP @structure
@call:
	; push the address after the call, then continue at the sub-structure
	LDA $00
	CLC
	ADC #3
	TAX
	LDA $01
	ADC #0
	PHA
	TXA
	PHA
	LDY #1
	LDA ($00),Y
	TAX
	INY
	LDA ($00),Y
	STA $01
	STX $00
	JMP @structure
@return:
	PLA
	STA $00
	PLA
	STA $01
	JMP @structure

WriteVRAMBuffersImpl:
	LDA ZP_PPUCTRL
	AND #%11111011 ; Address increment of 1
	STA PPUCTRL
	STA ZP_PPUCTRL
	LDA PPUSTATUS ; clear PPUADDR latch
	LDY #0 ; Start at the beginning of $302
@structure:
	LDA $302,Y  ; high byte of destination PPU address
	BMI @done   ; an "opcode" of $80 or more marks the end of the list
	PHA         ; kept for the palette check
	STA PPUADDR
	INY
	LDA $302,Y
	STA PPUADDR
	INY
	LDX $302,Y  ; length
	INY
@loop:
	LDA $302,Y
	STA PPUDATA
	INY
	DEX
	BNE @loop
	PLA
	JSR LeavePalette
	JMP @structure
@done:
	STA $302 ; write the $80 "opcode" to the first structure's address to clear the list
	LDA #0   ; clear the write buffer, i.e., move the read buffer to the beginning
	STA $301
	RTS
