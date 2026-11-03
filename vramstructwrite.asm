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

; Transfer a VRAM structure to VRAM. The structure format is described in
; freedisksys.asm. Games call this from NMI handlers, so it touches only the
; documented zero-page bytes.
; Affects: A, X, Y, $00, $01, $FF
; Parameters: Direct Pointer to VRAM structure to be written
API_ENTRYPOINT $e7bb
VRAMStructWrite:
	JSR FetchPtr00 ; start of the structure is now in ($00)
	JMP VRAMStructWriteImpl
