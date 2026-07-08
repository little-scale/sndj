; songscr.asm — the SONG screen: 8 track columns x a 16-row window into the
; 128-row grid. Cells are chain ids. B tap = insert (last chain), B+d-pad =
; nudge, Y+B = cut (value goes to the insert buffer). Playheads highlight
; each track's current song row while playing.

.ACCU 8
.INDEX 16

song_init_screen:
    lda #SCREEN_SONG
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
    ldx #str_song
    jsr text_puts
    ; track headers V1..V8 at x = 4 + t*3
    ; (counter must survive text_puttile, which clobbers tmp1 via text_dest)
    stz ui_cnt
@heads:
    lda ui_cnt
    asl
    clc
    adc ui_cnt
    adc #4
    sta text_x
    lda #3
    sta text_y
    lda #'V' - 32
    jsr text_puttile
    lda ui_cnt
    clc
    adc #'1' - 32
    jsr text_puttile
    inc ui_cnt
    lda ui_cnt
    cmp #TRACKS
    bne @heads
    rts

; A = chain id under the cursor ($FF if empty)
song_cursor_cell:
    jsr song_cell_addr
    lda.l $7E0000 + SB_SONG,x
    rts

; X = song block offset of cursor cell (track*128 + row)
song_cell_addr:
    rep #$30
.ACCU 16
    lda song_cx
    and #$00FF
    xba
    lsr                     ; track * 128
    sta tmp2
    lda song_cy
    and #$00FF
    clc
    adc tmp2
    tax
    sep #$20
.ACCU 8
    rts

song_update:
    ; Start: toggle song playback
    rep #$20
.ACCU 16
    lda pad_pressed
    and #PAD_START
    sep #$20
.ACCU 8
    beq @no_start
    jsr engine_toggle
@no_start:
    ; skip editing while A (nav) is held
    lda a_down
    beq @edit_ok
    jmp @draw
@edit_ok:
    ; Y+B: cut
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
    jsr song_cell_addr
    lda.l $7E0000 + SB_SONG,x
    cmp #$FF
    beq @cut_done
    sta ed_lastchain        ; cut into the insert buffer
@cut_done:
    lda #$FF
    sta.l $7E0000 + SB_SONG,x
    lda #$01
    sta b_used
    bra @cursor
@no_cut:
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
    ; tap: insert last chain
    jsr song_cell_addr
    lda ed_lastchain
    sta.l $7E0000 + SB_SONG,x
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
    jsr song_nudge
    bra @draw
@cursor:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_DPAD
    sep #$20
.ACCU 8
    beq @draw
    jsr song_cursor_move
@draw:
    jmp song_draw

song_nudge:
    jsr song_cell_addr
    lda.l $7E0000 + SB_SONG,x
    cmp #$FF
    bne @have
    lda ed_lastchain        ; nudge on empty inserts
    sta.l $7E0000 + SB_SONG,x
    rts
@have:
    sta tmp1
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_RIGHT
    sep #$20
.ACCU 8
    beq @nr
    inc tmp1
@nr:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_LEFT
    sep #$20
.ACCU 8
    beq @nl
    dec tmp1
@nl:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_UP
    sep #$20
.ACCU 8
    beq @nu
    lda tmp1
    clc
    adc #16
    sta tmp1
@nu:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_DOWN
    sep #$20
.ACCU 8
    beq @nd
    lda tmp1
    sec
    sbc #16
    sta tmp1
@nd:
    lda tmp1
    and #(CHAIN_COUNT - 1)
    sta.l $7E0000 + SB_SONG,x
    sta ed_lastchain
    rts

song_cursor_move:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_LEFT
    sep #$20
.ACCU 8
    beq @nl
    lda song_cx
    beq @nl
    dec song_cx
@nl:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_RIGHT
    sep #$20
.ACCU 8
    beq @nr
    lda song_cx
    cmp #TRACKS - 1
    bcs @nr
    inc song_cx
@nr:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_UP
    sep #$20
.ACCU 8
    beq @nu
    lda song_cy
    beq @nu
    dec song_cy
@nu:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_DOWN
    sep #$20
.ACCU 8
    beq @nd
    lda song_cy
    cmp #SONG_ROWS - 1
    bcs @nd
    inc song_cy
@nd:
    ; scroll window follows the cursor
    lda song_cy
    cmp song_top
    bcs @not_above
    sta song_top
@not_above:
    lda song_top
    clc
    adc #15
    cmp song_cy
    bcs @done
    lda song_cy
    sec
    sbc #15
    sta song_top
@done:
    rts

song_draw:
    stz tmp0 + 1            ; visible row counter
@rows:
    lda tmp0 + 1
    clc
    adc #4
    sta text_y
    ; row label = song_top + i
    lda #1
    sta text_x
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    sta text_attr
    sep #$20
.ACCU 8
    lda song_top
    clc
    adc tmp0 + 1
    jsr text_hex8
    ; 8 cells
    stz tmp0                ; track counter
@cells:
    lda tmp0
    asl
    clc
    adc tmp0
    adc #4                  ; x = 4 + track*3
    sta text_x
    jsr song_cell_attr
    ; cell value
    rep #$30
.ACCU 16
    lda tmp0
    and #$00FF
    xba
    lsr                     ; track*128
    sta tmp2
    lda song_top
    and #$00FF
    clc
    adc tmp2
    sta tmp2
    lda tmp0 + 1
    and #$00FF
    clc
    adc tmp2
    tax
    sep #$20
.ACCU 8
    lda.l $7E0000 + SB_SONG,x
    cmp #$FF
    bne @hex
    lda #'-' - 32
    jsr text_puttile
    lda #'-' - 32
    jsr text_puttile
    bra @next
@hex:
    jsr text_hex8
@next:
    inc tmp0
    lda tmp0
    cmp #TRACKS
    bne @cells
    inc tmp0 + 1
    lda tmp0 + 1
    cmp #16
    beq @done
    jmp @rows
@done:
    rts

; attr for cell (track tmp0, visible row tmp0+1): cursor accent beats
; playhead hilite beats plain text
song_cell_attr:
    ; cursor?
    lda song_top
    clc
    adc tmp0 + 1
    sta tmp1                ; absolute row of this cell
    cmp song_cy
    bne @not_cursor
    lda tmp0
    cmp song_cx
    bne @not_cursor
    rep #$20
.ACCU 16
    lda #ATTR_ACCENT
    sta text_attr
    sep #$20
.ACCU 8
    rts
@not_cursor:
    lda eng_playing
    beq @plain
    phx
    rep #$30
.ACCU 16
    lda tmp0
    and #$00FF
    tax
    sep #$20
.ACCU 8
    lda.w trk_phrase,x
    cmp #$FF
    beq @plain_x
    lda.w trk_songrow,x
    plx
    cmp tmp1
    bne @plain
    rep #$20
.ACCU 16
    lda #ATTR_HILITE
    sta text_attr
    sep #$20
.ACCU 8
    rts
@plain_x:
    plx
@plain:
    rep #$20
.ACCU 16
    lda #ATTR_TEXT
    sta text_attr
    sep #$20
.ACCU 8
    rts

str_song: .DB "SONG", 0
