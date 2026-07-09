; songscr.asm — the SONG screen: 8 track columns x a 16-row window into the
; 128-row grid. Cells are chain ids. B tap = insert (last chain), B+d-pad =
; nudge, B+A = cut, Y+B = block select (B copy / Y cut / A cancel, B double-tap
; paste). Playheads highlight
; each track's current song row while playing.

.ACCU 8
.INDEX 16

song_init_screen:
    stz blk_mode
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
    lda #7
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
    ; A held + B: play the song from the cursor row (genmddj C+B)
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
    jsr engine_play_from_cursor
@ab_used:
    lda #$01
    sta a_used
@no_ab:
    lda a_down
    beq @edit_y
    jmp @draw
@edit_y:
    ; Y held + up/down: page the 128-row view (genmddj A+up/down)
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
    beq @pg_dn
    lda song_cy
    sec
    sbc #$10
    bcs @pg_set
    lda #$00
@pg_set:
    sta song_cy
    bra @pg_win
@pg_dn:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_DOWN
    sep #$20
.ACCU 8
    beq @edit_ok
    lda song_cy
    clc
    adc #$10
    cmp #SONG_ROWS
    bcc @pg_set2
    lda #(SONG_ROWS - 1)
@pg_set2:
    sta song_cy
@pg_win:
    jsr song_snap_window
    jmp @draw
@edit_ok:
    ; block mode: B copy / Y cut / A cancel / d-pad stretch
    lda blk_mode
    beq @no_blk
    jmp song_block
@no_blk:
    ; Y held + B pressed: enter block select on this track column
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
    lda song_cy
    sta blk_start
    lda #$01
    sta b_used
    jmp @cursor
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
    lda frame_cnt
    sec
    sbc tap_timer
    cmp #7                  ; double-tap = two taps within 6 frames
    bcs @single
    lda frame_cnt
    clc
    adc #$80
    sta tap_timer           ; close the window
    jsr song_paste          ; B double-tap = paste
    bra @draw
@single:
    lda frame_cnt
    sta tap_timer
    ; tap: insert last chain
    jsr song_cell_addr
    lda ed_lastchain
    sta.l $7E0000 + SB_SONG,x
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
    jsr song_cell_cut
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
    ; fall through: scroll window follows the cursor
song_snap_window:
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
    adc #8
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

; B+A: cut the cursor cell (chain id feeds the next insert)
song_cell_cut:
    jsr song_cell_addr
    lda.l $7E0000 + SB_SONG,x
    cmp #$FF
    beq @wr
    sta ed_lastchain
@wr:
    lda #$FF
    sta.l $7E0000 + SB_SONG,x
    rts

; --- block mode on SONG: 1-byte cells along the cursor track, kind 3 --------
song_block:
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
    jmp song_draw
@not_cancel:
    rep #$20
.ACCU 16
    lda pad_pressed
    and #PAD_B
    sep #$20
.ACCU 8
    beq @not_copy
    jsr song_blk_copy
    stz blk_mode
    lda #$01
    sta b_used
    stz b_down
    jmp song_draw
@not_copy:
    rep #$20
.ACCU 16
    lda pad_pressed
    and #PAD_Y
    sep #$20
.ACCU 8
    beq @not_cut
    jsr song_blk_copy
    jsr song_blk_clear
    stz blk_mode
    jmp song_draw
@not_cut:
    rep #$20
.ACCU 16
    lda pad_event
    and #(PAD_UP | PAD_DOWN)
    sep #$20
.ACCU 8
    beq @blk_done
    jsr song_cursor_move
@blk_done:
    jmp song_draw

song_blk_range:
    lda blk_start
    cmp song_cy
    bcc @fwd
    lda song_cy
    sta es0
    lda blk_start
    sec
    sbc song_cy
    inc a
    sta es0 + 1
    rts
@fwd:
    sta es0
    lda song_cy
    sec
    sbc blk_start
    inc a
    sta es0 + 1
    rts

song_blk_copy:
    jsr song_blk_range
    lda #$03
    sta clip_kind
    lda es0 + 1
    sta clip_len
    ; src = track*128 + first
    rep #$30
.ACCU 16
    lda song_cx
    and #$00FF
    xba
    lsr
    sta es1
    lda es0
    and #$00FF
    clc
    adc es1
    sta es1
    lda es0 + 1
    and #$00FF
    sta es2
    ldy #$0000
@copy:
    tya
    clc
    adc es1
    tax
    sep #$20
.ACCU 8
    lda.l $7E0000 + SB_SONG,x
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

song_blk_clear:
    jsr song_blk_range
    rep #$30
.ACCU 16
    lda song_cx
    and #$00FF
    xba
    lsr
    sta es1
    lda es0
    and #$00FF
    clc
    adc es1
    tax
    sep #$20
.ACCU 8
@row:
    lda #$FF
    sta.l $7E0000 + SB_SONG,x
    rep #$30
.ACCU 16
    inx
    sep #$20
.ACCU 8
    dec es0 + 1
    bne @row
    rts

song_paste:
    lda clip_kind
    cmp #$03
    beq @kind_ok
    rts
@kind_ok:
    ; n = min(clip_len, 128 - song_cy)
    lda #SONG_ROWS
    sec
    sbc song_cy
    cmp clip_len
    bcc @have_n
    lda clip_len
@have_n:
    sta es0 + 1
    beq @done
    rep #$30
.ACCU 16
    lda song_cx
    and #$00FF
    xba
    lsr
    sta es1
    lda song_cy
    and #$00FF
    clc
    adc es1
    sta es1
    lda es0 + 1
    and #$00FF
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
    sta.l $7E0000 + SB_SONG,x
    rep #$30
.ACCU 16
    iny
    cpy es2
    bne @copy
    sep #$20
.ACCU 8
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
    ; block-select rows on the cursor track render hilite
    lda blk_mode
    beq @no_blk_hl
    lda tmp0
    cmp song_cx
    bne @no_blk_hl
    jsr song_blk_range
    lda tmp1                ; absolute row of this cell
    cmp es0
    bcc @no_blk_hl
    lda es0
    clc
    adc es0 + 1
    dec a
    cmp tmp1
    bcc @no_blk_hl
    rep #$20
.ACCU 16
    lda #ATTR_HILITE
    sta text_attr
    sep #$20
.ACCU 8
    rts
@no_blk_hl:
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
