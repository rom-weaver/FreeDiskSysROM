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

; Read the Family BASIC Keyboard on the expansion port.
; The keyboard is scanned through $4016: bit 0 resets the scan to row 0, bit 1
; selects the column, and bit 2 enables the keyboard. Writing column 0 after
; column 1 advances to the next row. Keys are read from $4017 bits 1-4, where a
; 0 means pressed. With no keyboard connected, those bits read as 0.
; Parameters: $FB = controller latch bits to keep in bits 3-7
; Returns: A = $FF if a keyboard was read, $00 if none is connected.
;          $00 = row 8 down to $08 = row 0. Lower nybble = column 0, upper
;          nybble = column 1. A set bit means the key is pressed.
; Affects: A, X, Y, $00-$08, $FB
API_ENTRYPOINT $eb13
ReadKeyboard:
	LDA ZP_JOYPAD1
	AND #%11111000
	TAY ; Y = latch bits to keep
	ORA #%00000101 ; reset to row 0
	STA JOYPAD1
	JSR Delay131
	LDX #$08
@rowLoop:
	TYA
	ORA #%00000100 ; column 0
	STA JOYPAD1
	JSR Delay131
	LDA JOYPAD2
	LSR A
	AND #$0F
	STA $00,x
	TYA
	ORA #%00000110 ; column 1
	STA JOYPAD1
	JSR Delay131
	LDA JOYPAD2
	ASL A
	ASL A
	ASL A
	AND #$F0
	ORA $00,x
	EOR #$FF ; the keyboard reports pressed keys as 0
	STA $00,x
	DEX
	BPL @rowLoop
	TYA
	STA JOYPAD1 ; stop scanning
	STY ZP_JOYPAD1

	; Without a keyboard every key reads as pressed.
	LDA #$FF
	LDX #$08
@detectLoop:
	AND $00,x
	DEX
	BPL @detectLoop
	EOR #$FF ; $00 if every key read as pressed
	BEQ @done
	LDA #$FF
@done:
	RTS
