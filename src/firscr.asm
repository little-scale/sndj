; firscr.asm — the FIR screen: the echo feedback filter's 8 taps as
; editable signed hex bytes. The song OWNS its taps (header SH_FIRTAPS);
; ROM presets are starting points.
;
;   B + d-pad     nudge the tap (L/R = 1, U/D = 16), applied live
;   Y + up/down   recall the previous/next ROM preset into the taps
;
; Editing a tap marks the preset readout "--" (custom). Deep design
; work lives in tools/firdesign.html (response plot + audition);
; this screen is for hardware-side tweaks and preset recall.
; Reached with A+Right from ECHO.

.ACCU 8
.INDEX 16

fir_init:
    lda #SCREEN_FIR
    sta ui_mode
    stz fs_row
    jsr text_clear
    stz text_x
    lda #1
    sta text_y
    rep #$20
.ACCU 16
    lda #ATTR_HILITE
    sta text_attr
    sep #$20
.ACCU 8
    ldx #str_fir
    jsr text_puts
    ; ruler (the family grid: header y4, rows from y5)
    lda #4
    sta text_x
    lda #4
    sta text_y
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    sta text_attr
    sep #$20
.ACCU 8
    ldx #str_fsruler
    jsr text_puts
    rts

fir_update:
    rep #$20
.ACCU 16
    lda pad_pressed
    and #PAD_START
    sep #$20
.ACCU 8
    beq @no_start
    jsr engine_toggle
@no_start:
    lda a_down
    beq @edit_ok
    jmp fir_draw
@edit_ok:
    ; Y + up/down: recall the previous/next ROM preset
    rep #$20
.ACCU 16
    lda pad_held
    and #PAD_Y
    sep #$20
.ACCU 8
    beq @no_page
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_UP
    sep #$20
.ACCU 8
    beq @pg_dn
    lda.l $7E0000 + SB_HEADER + SH_FIR
    dec a
    and #$07
    jsr apu_fir_preset
@pg_dn:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_DOWN
    sep #$20
.ACCU 8
    beq @pg_done
    lda.l $7E0000 + SB_HEADER + SH_FIR
    inc a
    and #$07
    jsr apu_fir_preset
@pg_done:
    jmp fir_draw
@no_page:
    ; B edges
    rep #$20
.ACCU 16
    lda pad_pressed
    and #PAD_B
    sep #$20
.ACCU 8
    beq @no_press
    lda #$01
    sta b_down
    stz b_used
@no_press:
    rep #$20
.ACCU 16
    lda pad_held
    and #PAD_B
    sep #$20
.ACCU 8
    bne @b_held
    stz b_down
    bra @cursor
@b_held:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_DPAD
    sep #$20
.ACCU 8
    beq @draw
    lda #$01
    sta b_used
    jsr fs_nudge
    bra @draw
@cursor:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_UP
    sep #$20
.ACCU 8
    beq @nu
    lda fs_row
    dec a
    and #$07
    sta fs_row
@nu:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_DOWN
    sep #$20
.ACCU 8
    beq @draw
    lda fs_row
    inc a
    and #$07
    sta fs_row
@draw:
    jmp fir_draw

fs_nudge:
    lda #16
    sta tmp2
    jsr nudge_delta         ; -> tmp1+1
    lda tmp1 + 1
    bne @have
    rts
@have:
    sta es3 + 1
    lda fs_row
    rep #$30
.ACCU 16
    and #$00FF
    tax
    sep #$20
.ACCU 8
    lda.l $7E0000 + SB_HEADER + SH_FIRTAPS,x
    clc
    adc es3 + 1
    sta.l $7E0000 + SB_HEADER + SH_FIRTAPS,x
    ; hand edits make this a custom curve
    lda #$FF
    sta.l $7E0000 + SB_HEADER + SH_FIR
    jmp apu_fir_apply

fir_draw:
    ; header: preset id, or -- for a custom curve
    lda #5
    sta text_x
    lda #1
    sta text_y
    rep #$20
.ACCU 16
    lda #ATTR_HILITE
    sta text_attr
    sep #$20
.ACCU 8
    lda.l $7E0000 + SB_HEADER + SH_FIR
    cmp #$08
    bcs @custom
    jsr text_hex8
    bra @rows_start
@custom:
    lda #'-' - 32
    jsr text_puttile
    lda #'-' - 32
    jsr text_puttile
@rows_start:
    stz ui_cnt
@rows:
    lda ui_cnt
    clc
    adc #5
    sta text_y
    lda #2
    sta text_x
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    sta text_attr
    sep #$20
.ACCU 8
    lda #'T' - 32
    jsr text_puttile
    lda ui_cnt
    clc
    adc #'0' - 32
    jsr text_puttile
    ; tap value
    lda #6
    sta text_x
    lda ui_cnt
    cmp fs_row
    bne @plain
    rep #$20
.ACCU 16
    lda #ATTR_ACCENT
    sta text_attr
    sep #$20
.ACCU 8
    bra @val
@plain:
    rep #$20
.ACCU 16
    lda #ATTR_TEXT
    sta text_attr
    sep #$20
.ACCU 8
@val:
    lda ui_cnt
    rep #$30
.ACCU 16
    and #$00FF
    tax
    sep #$20
.ACCU 8
    lda.l $7E0000 + SB_HEADER + SH_FIRTAPS,x
    jsr text_hex8
    inc ui_cnt
    lda ui_cnt
    cmp #$08
    bne @rows_far
    rts
@rows_far:
    jmp @rows

str_fir:     .DB "FIR ", 0
str_fsruler: .DB "TAPS", 0
