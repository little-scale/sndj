; groovescr.asm — the GROOVE screen: 16 steps of ticks-per-row for the
; selected groove. Grooves ARE the tempo (CLAUDE.md §1.5): the header
; shows the BPM this groove yields at the 60.15 Hz engine tick
; (BPM = tick*60 / (avg ticks * 4 rows per beat) = 14436 / step sum).
;
;   B + d-pad   nudge the step (L/R = 1, U/D = 4), clamped 1-15
;   B tap       repeat the last inserted value
;   Y + up/down previous / next groove
;
; Edits are live: the engine reads steps from WRAM every row.
; Reached with A+Down from CHAIN.

.ACCU 8
.INDEX 16

groove_init:
    lda #SCREEN_GROOVE
    sta ui_mode
    stz gv_row
    lda ed_lastgroove
    bne +
    lda #6
    sta ed_lastgroove       ; sensible first insert
+
    jsr text_clear
    lda #1
    sta text_x
    lda #1
    sta text_y
    rep #$20
.ACCU 16
    lda #ATTR_HILITE
    sta text_attr
    sep #$20
.ACCU 8
    ldx #str_groove
    jsr text_puts
    ; ruler
    lda #4
    sta text_x
    lda #7
    sta text_y
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    sta text_attr
    sep #$20
.ACCU 8
    ldx #str_gruler
    jsr text_puts
    rts

; X = song-block offset of the cursor step (groove*16 + row)
gv_addr:
    rep #$30
.ACCU 16
    lda ed_groove
    and #$00FF
    asl
    asl
    asl
    asl
    sta tmp2
    lda gv_row
    and #$00FF
    clc
    adc tmp2
    clc
    adc #SB_GROOVES
    tax
    sep #$20
.ACCU 8
    rts

groove_update:
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
    jmp groove_draw
@edit_ok:
    ; Y + up/down: previous / next groove
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
    lda ed_groove
    dec a
    and #(GROOVE_COUNT - 1)
    sta ed_groove
@pg_dn:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_DOWN
    sep #$20
.ACCU 8
    beq @pg_done
    lda ed_groove
    inc a
    and #(GROOVE_COUNT - 1)
    sta ed_groove
@pg_done:
    jmp groove_draw
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
    lda b_down
    beq @cursor
    stz b_down
    lda b_used
    bne @cursor
    ; tap: repeat the last inserted value
    jsr gv_addr
    lda ed_lastgroove
    sta.l $7E0000,x
    bra @draw
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
    jsr gv_nudge
    bra @draw
@cursor:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_UP
    sep #$20
.ACCU 8
    beq @nu
    lda gv_row
    dec a
    and #$0F
    sta gv_row
@nu:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_DOWN
    sep #$20
.ACCU 8
    beq @draw
    lda gv_row
    inc a
    and #$0F
    sta gv_row
@draw:
    jmp groove_draw

gv_nudge:
    lda #4
    sta tmp2
    jsr nudge_delta         ; delta -> tmp1+1
    lda tmp1 + 1
    bne @have
    rts
@have:
    sta es3 + 1
    jsr gv_addr
    lda.l $7E0000,x
    clc
    adc es3 + 1
    bpl @not_lo
    lda #$01
@not_lo:
    bne @not_zero
    lda #$01
@not_zero:
    cmp #$10
    bcc @store
    lda #$0F
@store:
    sta.l $7E0000,x
    sta ed_lastgroove
    rts

groove_draw:
    ; header: groove number + BPM readout
    lda #8
    sta text_x
    lda #1
    sta text_y
    rep #$20
.ACCU 16
    lda #ATTR_HILITE
    sta text_attr
    sep #$20
.ACCU 8
    lda ed_groove
    jsr text_hex8
    lda #12
    sta text_x
    lda #1
    sta text_y
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    sta text_attr
    sep #$20
.ACCU 8
    ldx #str_bpm
    jsr text_puts
    lda ed_groove
    jsr groove_bpm          ; -> tmp0 (text_puts clobbers tmp0: compute after)
    jsr text_dec3
    ; 16 step rows
    stz ui_cnt
@rows:
    lda ui_cnt
    clc
    adc #8
    sta text_y
    lda #2
    sta text_x
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    sta text_attr
    sep #$20
.ACCU 8
    lda ui_cnt
    jsr text_hex8
    ; value cell
    lda #6
    sta text_x
    lda ui_cnt
    cmp gv_row
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
    lda gv_row
    pha
    lda ui_cnt
    sta gv_row
    jsr gv_addr
    pla
    sta gv_row
    lda.l $7E0000,x
    jsr text_hex8
    ; playing-position marker on the active groove
    lda #9
    sta text_x
    lda eng_playing
    beq @no_head
    lda eng_groove
    cmp ed_groove
    bne @no_head
    lda eng_gpos
    dec a
    and #$0F
    cmp ui_cnt
    bne @no_head
    rep #$20
.ACCU 16
    lda #ATTR_HILITE
    sta text_attr
    sep #$20
.ACCU 8
    lda #GLYPH_ARROW_R
    jsr text_puttile
    bra @next
@no_head:
    lda #' ' - 32
    jsr text_puttile
@next:
    inc ui_cnt
    lda ui_cnt
    cmp #$10
    beq @done
    jmp @rows
@done:
    rts

; print tmp0 (16-bit, <= 999) as three decimal digits at text_x/y
text_dec3:
    rep #$30
.ACCU 16
    lda tmp0
    sep #$20
.ACCU 8
    sta.w WRDIVL
    lda tmp0 + 1
    sta.w WRDIVH
    lda #100
    sta.w WRDIVB
    jsr div_wait
    lda.w RDDIVL            ; hundreds (quotient < 10)
    clc
    adc #'0' - 32
    jsr text_puttile
    lda.w RDMPYL            ; remainder of the divide lands in RDMPY
    sta.w WRDIVL
    lda.w RDMPYH
    sta.w WRDIVH
    lda #10
    sta.w WRDIVB
    jsr div_wait
    lda.w RDDIVL
    clc
    adc #'0' - 32
    jsr text_puttile
    lda.w RDMPYL
    clc
    adc #'0' - 32
    jsr text_puttile
    rts

; A = groove id -> tmp0 = its BPM at the 60.15 Hz tick
; (BPM = tick*60 / (avg ticks * 4 rows/beat) = 14436 / step sum)
groove_bpm:
    rep #$30
.ACCU 16
    and #$00FF
    asl
    asl
    asl
    asl
    clc
    adc #SB_GROOVES
    tax
    sep #$20
.ACCU 8
    stz tmp2                ; sum
    stz tmp1
@sum:
    lda.l $7E0000,x
    bne @s_ok
    lda #6                  ; the engine substitutes 6 for zero steps
@s_ok:
    clc
    adc tmp2
    sta tmp2
    rep #$30
.ACCU 16
    inx
    sep #$20
.ACCU 8
    inc tmp1
    lda tmp1
    cmp #$10
    bne @sum
    lda #<14436
    sta.w WRDIVL
    lda #>14436
    sta.w WRDIVH
    lda tmp2
    sta.w WRDIVB
    jsr div_wait
    rep #$30
.ACCU 16
    lda.w RDDIVL
    sta tmp0                ; BPM (<= 902)
    sep #$20
.ACCU 8
    rts

; 5A22 divider settling time (16 cycles after WRDIVB)
div_wait:
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    rts

str_groove: .DB "GROOVE ", 0
str_gruler: .DB "TICKS", 0
str_bpm:    .DB "BPM ", 0
