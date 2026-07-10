; ============================================================================
; sndj — an LSDJ-inspired music tracker for the SNES / Super Famicom
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
.INCLUDE "logo.inc"          ; generated: LOGO_TW / LOGO_TH / LOGO_NTILES

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
.INCLUDE "sync.asm"
.INCLUDE "midi.asm"
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
.INCLUDE "optionscr.asm"
.INCLUDE "groovescr.asm"
.INCLUDE "projectscr.asm"
.INCLUDE "firscr.asm"
.INCLUDE "tablescr.asm"
.INCLUDE "clone.asm"
.INCLUDE "palette.asm"
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
    jsr midi_service
    jsr tick_track

    jsr screen_update
    ; chrome draws after the screen so it overlays on every screen
    jsr draw_status
    jsr draw_minimap
    jmp main_loop

; fold the streamed APU tick byte into a free-running 16-bit counter
tick_track:
    lda apu_tick
    sec
    sbc tick_last8
    beq @done
    rep #$30
.ACCU 16
    and #$00FF
    clc
    adc tick_ctr
    sta tick_ctr
    sep #$20
.ACCU 8
    lda apu_tick
    sta tick_last8
@done:
    rts

; right-column chrome, sibling-style (top-right, top to bottom):
; tick counter / blank / PLAY-STOP / blank / mini map (draw_minimap)
draw_status:
    lda ui_mode
    bne @go                 ; not on the splash
    rts
@go:
    ; y1: 4-hex tick counter, or APU? on a mailbox fault
    lda #27
    sta text_x
    lda #1
    sta text_y
    lda apu_status
    bne @bad
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    sta text_attr
    sep #$20
.ACCU 8
    lda tick_ctr + 1
    jsr text_hex8
    lda tick_ctr
    jsr text_hex8
    bra @transport
@bad:
    rep #$20
.ACCU 16
    lda #ATTR_ACCENT
    sta text_attr
    sep #$20
.ACCU 8
    ldx #str_apu_bad
    jsr text_puts
@transport:
    ; y3: PLAY / STOP (sync state joins this line with M12)
    lda #27
    sta text_x
    lda #3
    sta text_y
    lda eng_playing
    beq @stopped
    rep #$20
.ACCU 16
    lda #ATTR_ACCENT
    sta text_attr
    sep #$20
.ACCU 8
    ldx #str_play
    lda sync_wait            ; armed slave: holding for the external clock
    beq @have_str
    ldx #str_wait
@have_str:
    jmp text_puts
@stopped:
    rep #$20
.ACCU 16
    lda #ATTR_TEXT
    sta text_attr
    sep #$20
.ACCU 8
    ldx #str_stop
    jmp text_puts

str_apu_bad: .DB "APU?", 0
str_play:    .DB "PLAY", 0
str_wait:    .DB "WAIT", 0
str_stop:    .DB "STOP", 0

; the mini map (sibling chrome, smsggdj letters): 3x5 at the top right,
; current screen accented, built screens bright, future screens dim.
; PHRASE and PROJECT share P; FILES and FIR share F (as on smsggdj).
;   [O][P][ ][W][K]      OPTIONS PROJECT  -   WAVE  KIT
;   [S][C][P][I][T]      SONG    CHAIN  PHRASE INSTR TABLE
;   [F][G][ ][E][F]      FILES   GROOVE   -   ECHO  FIR
minimap_chars: .DB "OP WKSCPITFG EF"
minimap_impl:  .DB 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1
; ui_mode -> minimap cell index ($FF = no highlight; LIVE is a mode of
; SONG so it highlights S)
minimap_pos:   .DB $FF, 7, 6, 5, 8, 10, 13, 3, 5, 4, 0, 11, 1, 14, 9

draw_minimap:
    lda ui_mode
    bne @go                 ; not on the splash
    rts
@go:
    stz ui_cnt              ; cell 0-14
@cell:
    ; x = 27 + cell%5, y = 25 + cell/5
    lda ui_cnt
@mod5:
    cmp #$05
    bcc @m_done
    sec
    sbc #$05
    bra @mod5
@m_done:
    clc
    adc #27
    sta text_x
    lda ui_cnt
    ldy #$0000
@div5:
    cmp #$05
    bcc @d_done
    sec
    sbc #$05
    iny
    bra @div5
@d_done:
    tya
    clc
    adc #5
    sta text_y
    ; attr: accent if current, text if built, dim otherwise
    lda ui_mode
    rep #$30
.ACCU 16
    and #$00FF
    tax
    sep #$20
.ACCU 8
    lda.w minimap_pos,x
    cmp ui_cnt
    bne @not_here
    rep #$20
.ACCU 16
    lda #ATTR_ACCENT
    sta text_attr
    sep #$20
.ACCU 8
    bra @put
@not_here:
    lda ui_cnt
    rep #$30
.ACCU 16
    and #$00FF
    tax
    sep #$20
.ACCU 8
    lda.w minimap_impl,x
    bne @built
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    sta text_attr
    sep #$20
.ACCU 8
    bra @put
@built:
    rep #$20
.ACCU 16
    lda #ATTR_TEXT
    sta text_attr
    sep #$20
.ACCU 8
@put:
    lda ui_cnt
    rep #$30
.ACCU 16
    and #$00FF
    tax
    sep #$20
.ACCU 8
    lda.w minimap_chars,x
    sec
    sbc #32
    jsr text_puttile
    inc ui_cnt
    lda ui_cnt
    cmp #$0F
    beq @done
    jmp @cell
@done:
    rts

; --- data ---------------------------------------------------------------------
str_version:
    .DB "V", VERSION, 0
str_stamp:
    .DB BUILD_STAMP, 0

; font, marker-wrapped so patcher.html can locate and replace it
    .DB "SNFONT"
font_data:
    .INCBIN "font.bin"
font_data_end:

; factory palette (marker-wrapped for the patcher)
    .DB "SNPAL0"
pal_schemes:
    .INCBIN "schemes.bin"

; factory defaults (track instruments), marker-wrapped so browser tools
; can re-voice a built ROM without a toolchain: 8 instrument types,
; 8 samples/banks/kits, 8 extras (record byte 7: SLICES-1 high nibble,
; EON bit 0). maketables.py extracts the rows from samples/factory.sndjfact.
    .DB "SNDEF1"
factory_instr_type: .INCBIN "defaults.bin" SKIP 0 READ 8
factory_instr_smp:  .INCBIN "defaults.bin" SKIP 8 READ 8
factory_instr_x7:   .INCBIN "defaults.bin" SKIP 16 READ 8


; 8 factory FIR curves x 8 taps, marker-wrapped so firdesign.html patches
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

.BANK 6 SLOT 0
.ORG $0000
; the tri-pixel wordmark (art/sndj-logo.png via makelogo.py); DMA-only
; data, so it lives outside the crowded code bank
logo_data:
    .INCBIN "logo.bin"
logo_data_end:

; factory kits: 16 kits x 16 slots x 4 bytes (sample, tune, vol, flags;
; vol 0 = empty), copied verbatim into the song block by NEW.
; Marker-wrapped so patcher.html's kit builder edits it in place.
    .DB "SNKIT0"
factory_kits:
    .INCBIN "kits.bin"

; SPC700 driver blob, uploaded via the IPL protocol at boot (read with
; long addressing; parked here to keep the code bank breathing)
driver_blob:
    .INCBIN "driver.spc700.bin"
driver_blob_end:

.BANK 0 SLOT 0
; --- internal header (hand-rolled; checksum fixed by tools/fixsum.py) --------
.ORG $7FC0
    .DB "SNDJ                 "    ; 21-byte title
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
