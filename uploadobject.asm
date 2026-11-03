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

; Object structure offsets
OBJ_RENDER	EQU $00 ; $00 = render, $01-$7F = skip, $80-$FF = hide
OBJ_Y		EQU $01 ; Y position of the upper left corner
OBJ_X		EQU $03 ; X position of the upper left corner
OBJ_FRAME	EQU $05 ; animation frame
OBJ_TILES	EQU $06 ; tile arrangement pointer, big endian
OBJ_FLAGS	EQU $08 ; bit 4 = flip horizontally, bit 0 = flip vertically
OBJ_PALETTE	EQU $09
OBJ_SIZE	EQU $0A ; upper nybble = height, lower nybble = width, in tiles
OBJ_OAM		EQU $0B ; byte offset of the object's first sprite in $0200-$02FF
; Offsets $02 and $04 hold fractional positions, which this routine ignores.

; Upload an object (a group of sprites) to the OAM buffer at $0200-$02FF.
; Tiles are arranged column by column. If the tile arrangement pointer is less
; than $100, it is the upper left tile ID, and the tiles that follow are
; consecutive. Otherwise it points to a list of tile IDs. Either way, each
; animation frame advances by width * height tiles.
; Parameters: ($00) = object structure
; Affects: A, X, Y, $02-$0C
API_ENTRYPOINT $ec22
UploadObject:
	LDY #OBJ_SIZE
	LDA ($00),y
	AND #$0F
	STA $02 ; width
	LDA ($00),y
	LSR A
	LSR A
	LSR A
	LSR A
	STA $03 ; height
	; $0C = width * height
	LDA #$00
	LDX $03
	BEQ @haveCount
@multiply:
	CLC
	ADC $02
	DEX
	BNE @multiply
@haveCount:
	STA $0C
	TAY ; STA does not set the flags
	BEQ @rts ; empty object
	LDY #OBJ_OAM
	LDA ($00),y
	TAX ; X = OAM buffer offset

	LDY #OBJ_RENDER
	LDA ($00),y
	BEQ @render
	BPL @rts
	; hide every sprite in the object
	LDY $0C
	LDA #$FF
@hideLoop:
	STA $0200,x
	INX
	INX
	INX
	INX
	DEY
	BNE @hideLoop
@rts:
	RTS

@render:
	; $04 = OAM attributes
	LDY #OBJ_PALETTE
	LDA ($00),y
	AND #%00000011
	STA $04
	LDY #OBJ_FLAGS
	LDA ($00),y
	AND #%00010000
	BEQ @noHFlip
	LDA #%01000000
	ORA $04
	STA $04
@noHFlip:
	LDA ($00),y
	LSR A
	BCC @noVFlip
	LDA #%10000000
	ORA $04
	STA $04
@noVFlip:
	; $05-$06 = tile pointer advanced by frame * width * height
	LDY #OBJ_TILES
	LDA ($00),y
	STA $06
	INY
	LDA ($00),y
	STA $05
	LDY #OBJ_FRAME
	LDA ($00),y
	TAY
	BEQ @haveTiles
@frameLoop:
	LDA $05
	CLC
	ADC $0C
	STA $05
	BCC +
	INC $06
+:
	DEY
	BNE @frameLoop
@haveTiles:
	LDA #$00
	STA $07 ; column
	STA $09 ; tile index within the frame
@columnLoop:
	; $0A = X position of this column
	LDA $07
	BIT $04
	BVC +
	EOR #$FF ; flipped: column (width - 1 - column)
	SEC
	ADC $02
	SEC
	SBC #$01
+:
	ASL A
	ASL A
	ASL A
	LDY #OBJ_X
	CLC
	ADC ($00),y
	STA $0A
	LDA #$00
	STA $08 ; row
@rowLoop:
	; Y position of this row
	LDA $08
	BIT $04
	BPL +
	EOR #$FF ; flipped: row (height - 1 - row)
	SEC
	ADC $03
	SEC
	SBC #$01
+:
	ASL A
	ASL A
	ASL A
	LDY #OBJ_Y
	CLC
	ADC ($00),y
	STA $0200,x
	; tile ID
	LDA $06
	BNE @tileFromList
	LDA $05
	CLC
	ADC $09
	JMP @haveTile
@tileFromList:
	LDY $09
	LDA ($05),y
@haveTile:
	STA $0201,x
	LDA $04
	STA $0202,x
	LDA $0A
	STA $0203,x
	INX
	INX
	INX
	INX
	INC $09
	INC $08
	LDA $08
	CMP $03
	BNE @rowLoop
	INC $07
	LDA $07
	CMP $02
	BNE @columnLoop
	RTS
