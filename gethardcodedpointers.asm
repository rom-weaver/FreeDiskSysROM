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

; This routine does 3 things. First, it fetches 1 or 2 hardcoded 16-bit
; pointers that follow the second return address. Second, it checks the
; disk set or even write-protect status of the disk, and if the checks fail,
; the first return address on the stack is discarded, and program control is
; returned to the second return address. Finally, it saves the position of
; the stack so that when an error occurs, program control will be returned to
; the same place.
; Parameters: A == -1 means there are two 16-bit pointer parameters, otherwise just 1.
; Returns: A == OK (0) if no error, or DISK_NOT_SET (1) if the disk is not set. ($00) contains where results were loaded
; Affects:
;params
;------
;2nd call addr	1 or 2 16-bit pointers

;A	-1	2 16-bit pointers are present
;	other values	1 16-bit pointer present


;rtns (no error)
;---------------
;PC	original call address

;A	00

;[$00]	where parameters were loaded (A	is placed in [$02] if not -1)


;(error)
;-------
;PC	second call address

;Y	byte stored in [$0E]

;A	01	if disk wasn't set
;	03	if disk is write-protected

API_ENTRYPOINT $e3e7
GetHardCodedPointers:
    CLC
    BCC GetHardCodedPointersImpl

; Same as GetHardCodedPointers, except that
; Returns: A == OK (0) if no error, DISK_NOT_SET (1) if disk is not set, and WRITE_PROTECTED (3) if the disk is write-protected.
API_ENTRYPOINT $e3ea
GetHardCodedPointersWriteProtected:
    SEC
GetHardCodedPointersImpl:
    ldy #$01
    tsx
    sta $02
    lda $103,x
    sta $03
    lda $104,x
    sta $04
@loadPointers:
    lda ($03),y;load first 2 bytes
    sta $00
    iny
    lda ($03),y
    sta $01
    lda $02
    eor #$ff ; unlike INC, this leaves A intact in $02 and keeps C
    bne @endLoadPointers;if A was not $ff
    iny                 ;load 2 more bytes
    lda ($03),y
    sta $02
    iny
    lda ($03),y
    sta $03
@endLoadPointers:
    php
    tya
    clc
    adc $103,x;correct return address to skip parameter bytes
    sta $103,x
    bcc +
    inc $104,x;increment only when there is overflow
+:
    plp
    inx
    inx
    stx $04

    lda DRIVESTATUS
    and #%00000001; bit 0 contains disk-set status
    bne @error;a will be 1 if error, conveniently the needed error code
    BCC @end ; skip write-protect check if C is false
    LDA DRIVESTATUS
    AND #%00000100 ; bit 2 contains the write-protect status
    BEQ @end
    lda #WRITE_PROTECTED
@error:
    ; return to user program rather than function in case of error. PLA, not
    ; PLP, so the flags follow the error code and BNE sees the error.
    TAX
    PLA
    PLA
    TXA
@end:
    RTS
