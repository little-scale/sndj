; chainscr.asm — the CHAIN screen: 16 rows of (PHRASE id, TRANSPOSE).
; Same B-grammar as everywhere: tap insert, B+d-pad nudge, Y+B cut.
; Transpose is a signed byte, displayed as hex.

.ACCU 8
.INDEX 16

chain_init:
    lda #SCREEN_CHAIN
    sta ui_mode
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
    ldx #str_chain
    jsr text_puts
    lda ed_chain
    jsr text_hex8
    ; column ruler
    lda #4
    sta text_x
    lda #3
    sta text_y
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    sta text_attr
    sep #$20
.ACCU 8
    ldx #str_ruler
    jsr text_puts
    rts

; A = phrase id under the cursor ($FF if empty)
chain_cursor_phrase:
    jsr chain_cell_addr_p
    lda.l $7E0000 + SB_CHAINS,x
    rts

; X = offset of the cursor row's PHRASE byte (chain*32 + row*2)
chain_cell_addr_p:
    rep #$30
.ACCU 16
    lda ed_chain
    and #$00FF
    asl
    asl
    asl
    asl
    asl
    sta tmp2
    lda chain_cy
    and #$00FF
    asl
    clc
    adc tmp2
    tax
    sep #$20
.ACCU 8
    rts

chain_update:
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
    jmp @draw
@edit_ok:
    ; Y+B cut
    rep #$20
.ACCU 16
    lda pad_held
    and #PAD_Y
    sep #$20
.ACCU 8
    beq @no_cut
    rep #$20
.ACCU 16
    lda pad_pressed
    and #PAD_B
    sep #$20
.ACCU 8
    beq @no_cut
    jsr chain_cell_addr_p
    lda chain_cx
    bne @cut_tsp
    lda.l $7E0000 + SB_CHAINS,x
    cmp #$FF
    beq @cut_wr
    sta ed_lastphrid
@cut_wr:
    lda #$FF
    sta.l $7E0000 + SB_CHAINS,x
    bra @cut_done
@cut_tsp:
    lda #$00
    sta.l $7E0000 + SB_CHAINS + 1,x
@cut_done:
    lda #$01
    sta b_used
    bra @cursor
@no_cut:
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
    ; tap: insert
    jsr chain_cell_addr_p
    lda chain_cx
    bne @tap_tsp
    lda ed_lastphrid
    sta.l $7E0000 + SB_CHAINS,x
    bra @draw
@tap_tsp:
    lda ed_lasttsp
    sta.l $7E0000 + SB_CHAINS + 1,x
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
    jsr chain_nudge
    bra @draw
@cursor:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_DPAD
    sep #$20
.ACCU 8
    beq @draw
    jsr chain_cursor_move
@draw:
    jmp chain_draw

; signed delta from pad_event -> tmp1+1 (L/R = 1, U/D = 16 or 12)
nudge_delta:
    stz tmp1 + 1
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_RIGHT
    sep #$20
.ACCU 8
    beq @nr
    lda #$01
    sta tmp1 + 1
@nr:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_LEFT
    sep #$20
.ACCU 8
    beq @nl
    lda #$FF
    sta tmp1 + 1
@nl:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_UP
    sep #$20
.ACCU 8
    beq @nu
    lda tmp2
    sta tmp1 + 1
@nu:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_DOWN
    sep #$20
.ACCU 8
    beq @nd
    lda tmp2
    eor #$FF
    inc a
    sta tmp1 + 1
@nd:
    rts

chain_nudge:
    lda chain_cx
    bne @tsp
    ; phrase id column
    lda #16
    sta tmp2
    jsr nudge_delta
    lda tmp1 + 1
    beq @done
    jsr chain_cell_addr_p
    lda.l $7E0000 + SB_CHAINS,x
    cmp #$FF
    bne @have
    lda ed_lastphrid
    sta.l $7E0000 + SB_CHAINS,x
    rts
@have:
    clc
    adc tmp1 + 1
    and #(PHRASE_COUNT - 1)
    sta.l $7E0000 + SB_CHAINS,x
    sta ed_lastphrid
@done:
    rts
@tsp:
    ; transpose column: signed byte, U/D = octave
    lda #12
    sta tmp2
    jsr nudge_delta
    lda tmp1 + 1
    beq @done
    jsr chain_cell_addr_p
    lda.l $7E0000 + SB_CHAINS + 1,x
    clc
    adc tmp1 + 1
    sta.l $7E0000 + SB_CHAINS + 1,x
    sta ed_lasttsp
    rts

chain_cursor_move:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_LEFT
    sep #$20
.ACCU 8
    beq @nl
    stz chain_cx
@nl:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_RIGHT
    sep #$20
.ACCU 8
    beq @nr
    lda #$01
    sta chain_cx
@nr:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_UP
    sep #$20
.ACCU 8
    beq @nu
    lda chain_cy
    dec a
    and #$0F
    sta chain_cy
@nu:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_DOWN
    sep #$20
.ACCU 8
    beq @nd
    lda chain_cy
    inc a
    and #$0F
    sta chain_cy
@nd:
    rts

chain_draw:
    stz tmp0 + 1
@rows:
    lda tmp0 + 1
    clc
    adc #4
    sta text_y
    lda #1
    sta text_x
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    sta text_attr
    sep #$20
.ACCU 8
    lda tmp0 + 1
    jsr text_hex8
    ; fetch row bytes
    rep #$30
.ACCU 16
    lda ed_chain
    and #$00FF
    asl
    asl
    asl
    asl
    asl
    sta tmp2
    lda tmp0 + 1
    and #$00FF
    asl
    clc
    adc tmp2
    tax
    sep #$20
.ACCU 8
    lda.l $7E0000 + SB_CHAINS,x
    sta str_buf + 32
    lda.l $7E0000 + SB_CHAINS + 1,x
    sta str_buf + 33
    ; PHRASE cell
    stz tmp0
    lda #4
    sta text_x
    jsr chain_cell_attr
    lda str_buf + 32
    cmp #$FF
    bne @p_hex
    lda #'-' - 32
    jsr text_puttile
    lda #'-' - 32
    jsr text_puttile
    bra @tsp_cell
@p_hex:
    jsr text_hex8
@tsp_cell:
    inc tmp0
    lda #8
    sta text_x
    jsr chain_cell_attr
    lda str_buf + 33
    jsr text_hex8
    inc tmp0 + 1
    lda tmp0 + 1
    cmp #CHAIN_ROWS
    beq @done
    jmp @rows
@done:
    rts

chain_cell_attr:
    lda tmp0 + 1
    cmp chain_cy
    bne @plain
    lda tmp0
    cmp chain_cx
    bne @plain
    rep #$20
.ACCU 16
    lda #ATTR_ACCENT
    sta text_attr
    sep #$20
.ACCU 8
    rts
@plain:
    rep #$20
.ACCU 16
    lda #ATTR_TEXT
    sta text_attr
    sep #$20
.ACCU 8
    rts

str_chain: .DB "CHAIN ", 0
str_ruler: .DB "PHR TSP", 0
