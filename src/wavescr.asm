; wavescr.asm — the WAVE screen: draw a 32-sample single-cycle wave with
; the d-pad. B+up/down shapes the column under the cursor; B+left/right
; drags the current level sideways (paint). Y+left/right switches banks.
; Every edit recompiles the bank to BRR and re-uploads it, so the change
; is audible immediately on any playing WAV voice.

.ACCU 8
.INDEX 16

wave_init:
    lda #SCREEN_WAVE
    sta ui_mode
    stz wv_x
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
    ldx #str_wave
    jsr text_puts
    rts

; song-block offset of column A of the edited bank -> X
wv_addr:
    rep #$30
.ACCU 16
    and #$00FF
    sta es2
    lda ed_wave
    and #$00FF
    xba
    lsr
    lsr
    lsr                     ; * 32
    clc
    adc es2
    clc
    adc #SB_WAVES
    tax
    sep #$20
.ACCU 8
    rts

wave_update:
    rep #$20
.ACCU 16
    lda pad_pressed
    and #PAD_START
    sep #$20
.ACCU 8
    beq @no_start
    jsr engine_toggle
@no_start:
    ; A held + left/right: select the wave bank (genmddj C+left/right on WAVE)
    lda a_down
    bne @asel
    jmp @edit_ok
@asel:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_LEFT
    sep #$20
.ACCU 8
    beq @a_r
    lda ed_wave
    dec a
    and #$07
    sta ed_wave
    lda #$01
    sta a_used
    jsr wave_eat_dpad
@a_r:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_RIGHT
    sep #$20
.ACCU 8
    beq @a_done
    lda ed_wave
    inc a
    and #$07
    sta ed_wave
    lda #$01
    sta a_used
    jsr wave_eat_dpad
@a_done:
    lda a_down
    beq @edit_ok
    jmp wave_draw
@edit_ok:
    ; Y + left/right: bank page
    rep #$20
.ACCU 16
    lda pad_held
    and #PAD_Y
    sep #$20
.ACCU 8
    beq @no_bank
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_LEFT
    sep #$20
.ACCU 8
    beq @bank_r
    lda ed_wave
    dec a
    and #$07
    sta ed_wave
@bank_r:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_RIGHT
    sep #$20
.ACCU 8
    beq @bank_done
    lda ed_wave
    inc a
    and #$07
    sta ed_wave
@bank_done:
    jmp wave_draw
@no_bank:
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
    ; B held + A tap: stamp the next factory shape (genmddj B+C)
    rep #$20
.ACCU 16
    lda pad_pressed
    and #PAD_A
    sep #$20
.ACCU 8
    beq @no_stamp
    lda #$01
    sta b_used
    jsr wave_stamp
    jmp wave_draw
@no_stamp:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_DPAD
    sep #$20
.ACCU 8
    beq @draw_far
    lda #$01
    sta b_used
    jsr wave_edit
@draw_far:
    jmp wave_draw
@cursor:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_LEFT
    sep #$20
.ACCU 8
    beq @nl
    lda wv_x
    dec a
    and #$1F
    sta wv_x
@nl:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_RIGHT
    sep #$20
.ACCU 8
    beq @nr
    lda wv_x
    inc a
    and #$1F
    sta wv_x
@nr:
    jmp wave_draw

wave_eat_dpad:
    rep #$20
.ACCU 16
    lda #$0000
    sta pad_event
    sep #$20
.ACCU 8
    rts

; B held + A tap: stamp the next factory shape into this bank
; (sine -> tri -> saw -> square -> 25% -> 12.5% -> organ -> grit)
wave_stamp:
    inc wv_stamp
    lda wv_stamp
    and #$07
    sta wv_stamp
    stz es2                 ; column
@copy:
    lda wv_stamp
    rep #$30
.ACCU 16
    and #$00FF
    xba
    lsr
    lsr
    lsr                     ; * 32
    sta es1
    lda es2
    and #$00FF
    clc
    adc es1
    tax
    sep #$20
.ACCU 8
    lda.w default_waves,x
    pha
    lda es2
    jsr wv_addr
    pla
    sta.l $7E0000,x
    inc es2
    lda es2
    cmp #$20
    bne @copy
    lda ed_wave
    jmp wave_compile

; B held + d-pad: up/down shape, left/right paint-drag
wave_edit:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_UP
    sep #$20
.ACCU 8
    beq @not_up
    lda wv_x
    jsr wv_addr
    lda.l $7E0000,x
    cmp #$0F
    bcs @recompile
    inc a
    sta.l $7E0000,x
    bra @recompile
@not_up:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_DOWN
    sep #$20
.ACCU 8
    beq @not_down
    lda wv_x
    jsr wv_addr
    lda.l $7E0000,x
    beq @recompile
    dec a
    sta.l $7E0000,x
    bra @recompile
@not_down:
    ; left/right: move and copy the level (drag-draw)
    lda wv_x
    jsr wv_addr
    lda.l $7E0000,x
    sta es3 + 1             ; pen level
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_LEFT
    sep #$20
.ACCU 8
    beq @drag_r
    lda wv_x
    dec a
    and #$1F
    sta wv_x
    bra @paint
@drag_r:
    lda wv_x
    inc a
    and #$1F
    sta wv_x
@paint:
    lda wv_x
    jsr wv_addr
    lda es3 + 1
    sta.l $7E0000,x
@recompile:
    lda ed_wave
    jmp wave_compile

wave_draw:
    ; header bank digit
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
    lda ed_wave
    clc
    adc #'0' - 32
    jsr text_puttile
    ; 32 columns x 16 rows: bar chart of the bank
    stz ui_cnt              ; column
@cols:
    lda ui_cnt
    jsr wv_addr
    lda.l $7E0000,x
    sta es3                 ; column level 0-15
    ; attr: cursor column accent, others hilite
    lda ui_cnt
    cmp wv_x
    bne @plain
    rep #$20
.ACCU 16
    lda #ATTR_ACCENT
    sta text_attr
    sep #$20
.ACCU 8
    bra @rows
@plain:
    rep #$20
.ACCU 16
    lda #ATTR_HILITE
    sta text_attr
    sep #$20
.ACCU 8
@rows:
    stz es2                 ; row 0 (top) .. 15 (bottom)
@row:
    lda ui_cnt
    sta text_x
    lda es2
    clc
    adc #4
    sta text_y
    ; cell is filled when (15 - row) <= level
    lda #$0F
    sec
    sbc es2                 ; height of this cell
    cmp es3
    bcc @filled
    beq @filled
    lda #' ' - 32
    bra @put
@filled:
    lda #GLYPH_BLOCK
@put:
    jsr text_puttile
    inc es2
    lda es2
    cmp #$10
    bne @row
    inc ui_cnt
    lda ui_cnt
    cmp #$20
    beq @done
    jmp @cols
@done:
    rts

str_wave: .DB "WAVE  ", 0
