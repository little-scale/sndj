; groovescr.asm — the GROOVE screen: THE groove, one public 2-step pair
; (ticks per row, alternating). Grooves ARE the feel: 6/6 is straight,
; 7/5 lilts, 8/4 swings hard. The header shows the BPM the pair yields
; at the song's tick BPM (effective = 12 * song BPM / (a+b); 6/6 reads
; back the PROJECT tempo exactly). The G command writes the same two
; bytes live: G84 = swing on the drop.
;
;   B + d-pad   nudge the step (L/R = 1, U/D = 4), clamped 1-15
;   B tap       repeat the last inserted value
;
; Edits are live: the engine reads the pair from WRAM every row.
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
    stz text_x
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
    ldx #str_gruler
    jsr text_puts
    rts

; X = song-block offset of the cursor step (the public pair)
gv_addr:
    rep #$30
.ACCU 16
    lda gv_row
    and #$0001
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
    and #(PAD_UP | PAD_DOWN)
    sep #$20
.ACCU 8
    beq @draw
    lda gv_row
    eor #$01                ; two steps: up/down just swaps
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
    ; header: BPM readout
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
    jsr groove_bpm          ; -> tmp0 (text_puts clobbers tmp0: compute after)
    jsr text_dec3
    ; the two steps
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
    lda ui_cnt
    clc
    adc #'1' - 32
    jsr text_puttile
    ; playhead: left of the ticks column, drawn plain (the value below
    ; carries the highlight)
    lda #5
    sta text_x
    jsr gv_playrow
    bcc @no_head
    lda #GLYPH_ARROW_R
    jsr text_puttile
    bra @val_cell
@no_head:
    lda #' ' - 32
    jsr text_puttile
@val_cell:
    ; value cell: cursor accent > playing hilite > plain
    lda #6
    sta text_x
    lda ui_cnt
    cmp gv_row
    bne @not_cur
    rep #$20
.ACCU 16
    lda #ATTR_ACCENT
    sta text_attr
    sep #$20
.ACCU 8
    bra @val
@not_cur:
    jsr gv_playrow
    bcc @plain
    rep #$20
.ACCU 16
    lda #ATTR_HILITE
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
    inc ui_cnt
    lda ui_cnt
    cmp #$02
    beq @rows_done
    jmp @rows
@rows_done:
    rts

; carry set when step ui_cnt is the playing position of the pair
gv_playrow:
    lda eng_playing
    beq @no
    lda eng_gpos
    dec a
    and #$01
    cmp ui_cnt
    bne @no
    sec
    rts
@no:
    clc
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

; tmp0 = the pair's BPM at the song's tick BPM
; (effective = 12 * song BPM / (a + b); 6/6 reads back the tempo)
groove_bpm:
    lda.l $7E0000 + SB_GROOVES
    bne @a_ok
    lda #6                  ; the engine substitutes 6 for zero steps
@a_ok:
    sta tmp2
    lda.l $7E0000 + SB_GROOVES + 1
    bne @b_ok
    lda #6
@b_ok:
    clc
    adc tmp2
    sta tmp2                ; a + b (<= 30)
    lda #12
    sta.w WRMPYA
    lda.l $7E0000 + SB_HEADER + SH_BPM
    bne +
    lda #150
+
    sta.w WRMPYB
    jsr div_wait            ; (multiplier settles in 8 cycles; reuse)
    lda.w RDMPYL
    sta.w WRDIVL
    lda.w RDMPYH
    sta.w WRDIVH
    lda tmp2
    sta.w WRDIVB
    jsr div_wait
    rep #$30
.ACCU 16
    lda.w RDDIVL
    cmp #1000
    bcc +
    lda #999                ; 3-digit display cap
+
    sta tmp0
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
