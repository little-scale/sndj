; chainscr.asm — the CHAIN screen: 16 rows of (PHRASE id, TRANSPOSE).
; Same B-grammar as everywhere: tap insert, B+d-pad nudge, B+A cut, Y+B block
; select (B copy / Y cut / A cancel, B double-tap paste).
; Transpose is a signed byte, displayed as hex.

.ACCU 8
.INDEX 16

chain_init:
    stz blk_mode
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
    lda #8
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
    ; A held + B: play this chain from its top
    lda a_down
    beq @no_ab
    rep #$20
.ACCU 16
    lda pad_pressed
    and #PAD_B
    sep #$20
.ACCU 8
    beq @no_ab
    lda eng_playing
    beq @ab_play
    jsr engine_stop         ; A+B while playing = stop, on every screen
    bra @ab_used
@ab_play:
    jsr engine_play_chain   ; from the top of the chain
@ab_used:
    lda #$01
    sta a_used
@no_ab:
    lda a_down
    beq @edit_y
    jmp @draw
@edit_y:
    ; Y held + up/down: previous / next chain (genmddj A+up/down)
    rep #$20
.ACCU 16
    lda pad_held
    and #PAD_Y
    sep #$20
.ACCU 8
    beq @edit_ok
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_UP
    sep #$20
.ACCU 8
    beq @y_dn
    lda ed_chain
    dec a
    bpl @y_set
    lda #(CHAIN_COUNT - 1)
@y_set:
    sta ed_chain
    jmp chain_hdr
@y_dn:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_DOWN
    sep #$20
.ACCU 8
    beq @edit_ok
    lda ed_chain
    inc a
    cmp #CHAIN_COUNT
    bcc @y_set2
    lda #$00
@y_set2:
    sta ed_chain
    jmp chain_hdr
@edit_ok:
    ; block mode: B copy / Y cut / A cancel / d-pad stretch
    lda blk_mode
    beq @no_blk
    jmp chain_block
@no_blk:
    ; Y held + B pressed: enter block select
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
    lda #$01
    sta blk_mode
    lda chain_cy
    sta blk_start
    lda #$01
    sta b_used
    jmp @cursor
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
    lda frame_cnt
    sec
    sbc tap_timer
    cmp #7                  ; double-tap = two taps within 6 frames
    bcs @single
    lda frame_cnt
    clc
    adc #$80
    sta tap_timer           ; close the window
    jsr chain_dtap          ; paste / mint / clone
    bra @draw
@single:
    lda frame_cnt
    sta tap_timer
    ; tap: remember the pre-tap state (the phrase column is a reference)
    jsr chain_cell_addr_p
    lda chain_cx
    bne @tap_tsp
    lda.l $7E0000 + SB_CHAINS,x
    sta mint_prev
    cmp #$FF
    beq @was_empty
    stz mint_empty
    bra @ins
@was_empty:
    lda #$01
    sta mint_empty
@ins:
    lda ed_lastphrid
    sta.l $7E0000 + SB_CHAINS,x
    bra @draw
@tap_tsp:
    lda ed_lasttsp
    sta.l $7E0000 + SB_CHAINS + 1,x
    bra @draw
@b_held:
    ; B held + A tap: cut the cell
    rep #$20
.ACCU 16
    lda pad_pressed
    and #PAD_A
    sep #$20
.ACCU 8
    beq @no_cut_a
    lda #$01
    sta b_used
    jsr chain_cell_cut
    bra @draw
@no_cut_a:
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

; --- block mode on CHAIN: 2-byte rows, kind 2 -------------------------------
chain_block:
    rep #$20
.ACCU 16
    lda pad_pressed
    and #PAD_A
    sep #$20
.ACCU 8
    beq @not_cancel
    stz blk_mode
    lda #$01
    sta a_used
    jmp chain_draw
@not_cancel:
    rep #$20
.ACCU 16
    lda pad_pressed
    and #PAD_B
    sep #$20
.ACCU 8
    beq @not_copy
    jsr chain_blk_copy
    stz blk_mode
    lda #$01
    sta b_used
    stz b_down
    jmp chain_draw
@not_copy:
    rep #$20
.ACCU 16
    lda pad_pressed
    and #PAD_Y
    sep #$20
.ACCU 8
    beq @not_cut
    jsr chain_blk_copy
    jsr chain_blk_clear
    stz blk_mode
    jmp chain_draw
@not_cut:
    rep #$20
.ACCU 16
    lda pad_event
    and #(PAD_UP | PAD_DOWN)
    sep #$20
.ACCU 8
    beq @blk_done
    jsr chain_cursor_move
@blk_done:
    jmp chain_draw

; carry set when drawn row (tmp0+1) is inside the block
chain_blk_range_row:
    jsr chain_blk_range
    lda tmp0 + 1
    cmp es0
    bcc @out
    lda es0
    clc
    adc es0 + 1
    dec a
    cmp tmp0 + 1
    bcc @out
    sec
    rts
@out:
    clc
    rts

chain_blk_range:
    lda blk_start
    cmp chain_cy
    bcc @fwd
    lda chain_cy
    sta es0
    lda blk_start
    sec
    sbc chain_cy
    inc a
    sta es0 + 1
    rts
@fwd:
    sta es0
    lda chain_cy
    sec
    sbc blk_start
    inc a
    sta es0 + 1
    rts

chain_blk_copy:
    jsr chain_blk_range
    lda #$02
    sta clip_kind
    lda es0 + 1
    sta clip_len
    rep #$30
.ACCU 16
    lda ed_chain
    and #$00FF
    asl
    asl
    asl
    asl
    asl                     ; * 32
    sta es1
    lda es0
    and #$00FF
    asl                     ; * 2
    clc
    adc es1
    sta es1
    lda es0 + 1
    and #$00FF
    asl
    sta es2
    ldy #$0000
@copy:
    tya
    clc
    adc es1
    tax
    sep #$20
.ACCU 8
    lda.l $7E0000 + SB_CHAINS,x
    pha
    rep #$30
.ACCU 16
    tyx
    sep #$20
.ACCU 8
    pla
    sta.l $7E7400,x
    rep #$30
.ACCU 16
    iny
    cpy es2
    bne @copy
    sep #$20
.ACCU 8
    rts

chain_blk_clear:
    jsr chain_blk_range
    rep #$30
.ACCU 16
    lda ed_chain
    and #$00FF
    asl
    asl
    asl
    asl
    asl
    sta es1
    lda es0
    and #$00FF
    asl
    clc
    adc es1
    tax
    sep #$20
.ACCU 8
@row:
    lda #$FF
    sta.l $7E0000 + SB_CHAINS,x
    lda #$00
    sta.l $7E0000 + SB_CHAINS + 1,x
    rep #$30
.ACCU 16
    inx
    inx
    sep #$20
.ACCU 8
    dec es0 + 1
    bne @row
    rts

chain_paste:
    lda clip_kind
    cmp #$02
    beq @kind_ok
    rts
@kind_ok:
    lda #$10
    sec
    sbc chain_cy
    cmp clip_len
    bcc @have_n
    lda clip_len
@have_n:
    sta es0 + 1
    beq @done
    rep #$30
.ACCU 16
    lda ed_chain
    and #$00FF
    asl
    asl
    asl
    asl
    asl
    sta es1
    lda chain_cy
    and #$00FF
    asl
    clc
    adc es1
    sta es1
    lda es0 + 1
    and #$00FF
    asl
    sta es2
    ldy #$0000
@copy:
    tyx
    sep #$20
.ACCU 8
    lda.l $7E7400,x
    pha
    rep #$30
.ACCU 16
    tya
    clc
    adc es1
    tax
    sep #$20
.ACCU 8
    pla
    sta.l $7E0000 + SB_CHAINS,x
    rep #$30
.ACCU 16
    iny
    cpy es2
    bne @copy
    sep #$20
.ACCU 8
@done:
    rts

; B double-tap on the phrase column: paste, mint or clone (always deep)
chain_dtap:
    lda clip_kind
    cmp #$02
    bne @not_paste
    jmp chain_paste
@not_paste:
    lda chain_cx
    bne @out                ; the transpose column isn't a reference
    lda mint_empty
    beq @clone
    jsr find_free_phrase
    bcs @out
    bra @point
@clone:
    lda mint_prev
    jsr clone_phrase
    bcs @out
@point:
    pha
    jsr chain_cell_addr_p
    pla
    sta.l $7E0000 + SB_CHAINS,x
    sta ed_lastphrid
@out:
    rts

; B+A: cut the cursor cell (phrase id feeds the next insert; tsp -> 0)
chain_cell_cut:
    jsr chain_cell_addr_p
    lda chain_cx
    bne @tsp
    lda.l $7E0000 + SB_CHAINS,x
    cmp #$FF
    beq @wr
    sta ed_lastphrid
@wr:
    lda #$FF
    sta.l $7E0000 + SB_CHAINS,x
    rts
@tsp:
    lda #$00
    sta.l $7E0000 + SB_CHAINS + 1,x
    rts

chain_hdr:
    lda #7
    sta text_x
    lda #1
    sta text_y
    rep #$20
.ACCU 16
    lda #ATTR_HILITE
    sta text_attr
    sep #$20
.ACCU 8
    lda ed_chain
    jsr text_hex8
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
    adc #9
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
    lda blk_mode
    beq @no_blk_hl
    jsr chain_blk_range_row
    bcc @no_blk_hl
    lda tmp0 + 1
    cmp chain_cy
    beq @no_blk_hl
    rep #$20
.ACCU 16
    lda #ATTR_ACCENT
    sta text_attr
    sep #$20
.ACCU 8
    rts
@no_blk_hl:
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
