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
.INCLUDE "song.inc"
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
.INCLUDE "pool.asm"
.INCLUDE "screens.asm"
.INCLUDE "engine.asm"
.INCLUDE "phrase.asm"
.INCLUDE "chainscr.asm"
.INCLUDE "songscr.asm"
.INCLUDE "instrscr.asm"
.INCLUDE "save.asm"
.INCLUDE "filescr.asm"
.INCLUDE "echoscr.asm"
.INCLUDE "wave.asm"
.INCLUDE "wavescr.asm"
.INCLUDE "livescr.asm"
.INCLUDE "kitscr.asm"
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
    jsr engine_update
    jsr draw_apu_status

    jsr screen_update
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

; 8 factory FIR curves x 8 taps, marker-wrapped so firdesign.html patches
; the ROM instead of rebuilding it
    .DB "SNFIR0"
fir_presets:
    .DB $7F, $00, $00, $00, $00, $00, $00, $00   ; 0 FLAT (pass-through)
    .DB $58, $30, $12, $08, $00, $00, $00, $00   ; 1 DARK (lowpass hall)
    .DB $70, $E8, $18, $F4, $00, $00, $00, $00   ; 2 BRIGHT (presence)
    .DB $40, $00, $00, $40, $00, $00, $00, $00   ; 3 COMB
    .DB $20, $30, $40, $30, $20, $10, $08, $04   ; 4 SOFT (smeared)
    .DB $4C, $21, $12, $09, $05, $03, $02, $01   ; 5 DKC HALL (decay tail)
    .DB $60, $A0, $40, $D0, $20, $E8, $10, $F8   ; 6 METAL (alternating)
    .DB $7F, $00, $00, $00, $00, $00, $00, $00   ; 7 USER (starts flat)

; SPC700 driver blob, uploaded via the IPL protocol at boot
driver_blob:
    .INCBIN "driver.spc700.bin"
driver_blob_end:

; pitch/note tables (single tuning source: tools/maketables.py)
.INCLUDE "tables.inc"



; --- banks 1-3: the self-describing sample pool (tools/sndj_pool.py) ---------
; marker-wrapped and padded to POOL_RESERVED so patcher.html can grow it in
; place; pool.bin is emitted pre-padded and split across the banks here
.BANK 1 SLOT 0
.ORG $0000
    .DB "SNPOOL"
pool_data:
    .INCBIN "pool.bin" READ $7FFA
.BANK 2 SLOT 0
.ORG $0000
    .INCBIN "pool.bin" SKIP $7FFA READ $8000
.BANK 3 SLOT 0
.ORG $0000
    .INCBIN "pool.bin" SKIP $FFFA READ $8000
.BANK 4 SLOT 0
.ORG $0000
    .INCBIN "pool.bin" SKIP $17FFA READ $8000
.BANK 5 SLOT 0
.ORG $0000
    .INCBIN "pool.bin" SKIP $1FFFA READ $8000

.BANK 0 SLOT 0
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
