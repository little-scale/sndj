; ============================================================================
; snesdj — an LSDJ-inspired music tracker for the SNES / Super Famicom
; main.asm — single translation unit for the S-CPU (65816)
;
; Register-width convention (CLAUDE.md invariant #8): natural state is
; A 8-bit, X/Y 16-bit, D=$0000, DB=$80. Any routine that changes widths
; restores them; interrupt entry re-asserts.
; ============================================================================

.DEFINE VERSION "0.1.0"     ; drives the splash and `make dist` filenames

.MEMORYMAP
  DEFAULTSLOT 0
  SLOTSIZE $8000
  SLOT 0 $8000
.ENDME
.ROMBANKSIZE $8000
.ROMBANKS 32                ; 1 MB LoROM
.EMPTYFILL $FF

.INCLUDE "snes.inc"
.INCLUDE "ram.inc"
.INCLUDE "buildid.inc"      ; generated: .DEFINE BUILD_STAMP "..."

.BANK 0 SLOT 0
.ORG $0000
.BASE $80                   ; run from the FastROM mirror

; --- code -------------------------------------------------------------------
.INCLUDE "init.asm"
.INCLUDE "nmi.asm"
.INCLUDE "text.asm"
.INCLUDE "input.asm"
.INCLUDE "apu.asm"
.INCLUDE "splash.asm"

; --- main loop ---------------------------------------------------------------
.ACCU 8
.INDEX 16

main_loop:
@wait:
    wai
    lda frame_flag
    beq @wait
    stz frame_flag

    jsr input_update
    jsr apu_update
    jsr draw_apu_status

    lda ui_mode
    beq @splash
    jsr stub_update
    bra @frame_done
@splash:
    jsr splash_update
@frame_done:
    jmp main_loop

; top-right APU health widget: dim "APU" when alive, accent "APU?" on timeout
draw_apu_status:
    lda #27
    sta text_x
    stz text_y
    lda apu_status
    bne @bad
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    sta text_attr
    sep #$20
.ACCU 8
    ldx #str_apu_ok
    jmp text_puts
@bad:
    rep #$20
.ACCU 16
    lda #ATTR_ACCENT
    sta text_attr
    sep #$20
.ACCU 8
    ldx #str_apu_bad
    jmp text_puts

str_apu_ok:  .DB "APU ", 0
str_apu_bad: .DB "APU?", 0

; --- data ---------------------------------------------------------------------
str_version:
    .DB "V", VERSION, " ", BUILD_STAMP, 0

; font, marker-wrapped so patcher.html can locate and replace it
    .DB "SNFONT"
font_data:
    .INCBIN "font.bin"
font_data_end:

; factory palette (marker-wrapped for the patcher)
    .DB "SNPAL0"
pal_data:
    .INCBIN "pal.bin"

; HDMA backdrop gradient table
gradient_data:
    .INCBIN "gradient.bin"

; SPC700 driver blob, uploaded via the IPL protocol at boot
driver_blob:
    .INCBIN "driver.spc700.bin"
driver_blob_end:

; --- internal header (hand-rolled; checksum fixed by tools/fixsum.py) --------
.ORG $7FC0
    .DB "SNESDJ               "      ; 21-byte title
    .DB $30                          ; LoROM, FastROM
    .DB $02                          ; ROM + RAM + battery
    .DB $0A                          ; 1 MB
    .DB $05                          ; 32 KB SRAM
    .DB $01                          ; region: NTSC (video is switchable in-app)
    .DB $00                          ; licensee
    .DB $00                          ; version
    .DW $FFFF, $0000                 ; checksum complement / checksum

; native-mode vectors ($FFE0)
    .DW $0000, $0000
    .DW Vec_Null                     ; COP
    .DW Vec_Null                     ; BRK
    .DW Vec_Null                     ; ABORT
    .DW Vec_NMI                      ; NMI
    .DW $0000
    .DW Vec_Null                     ; IRQ
; emulation-mode vectors ($FFF0)
    .DW $0000, $0000
    .DW Vec_Null                     ; COP
    .DW $0000
    .DW Vec_Null                     ; ABORT
    .DW Vec_Null                     ; NMI
    .DW Reset                        ; RESET
    .DW Vec_Null                     ; IRQ/BRK
