; phrase.asm — the PHRASE screen: 16 rows of NOTE / INSTR / CMD / VAL with
; the sibling B-grammar: B tap = insert/edit (+audition on the note column),
; B held + d-pad = nudge (L/R small, U/D big), B held + A = cut cell,
; Start = play/stop. CMD/VAL are stored but inert until M7; INSTR until M6.

.ACCU 8
.INDEX 16

; column geometry
col_x:  .DB 4, 8, 11, 13
col_w:  .DB 3, 2, 1, 2

phrase_init:
    stz tap_live
    stz blk_mode
    lda #SCREEN_PHRASE
    sta ui_mode
    stz ed_col
    stz cur_y
    stz b_down
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
    ldx #str_phrase
    jsr text_puts
    lda ed_phrase
    jsr text_hex8
    ; column titles
    lda #3
    sta text_x
    lda #4
    sta text_y
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    sta text_attr
    sep #$20
.ACCU 8
    ldx #str_cols
    jsr text_puts
    rts

; ---------------------------------------------------------------------------
; input
; ---------------------------------------------------------------------------
phrase_update:
    ; Start: play/stop
    rep #$20
.ACCU 16
    lda pad_pressed
    and #PAD_START
    sep #$20
.ACCU 8
    beq @no_start
    jsr engine_toggle
@no_start:
    ; A held + B tap: play this phrase from its top
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
    jsr engine_play_phrase  ; from the top of the phrase
@ab_used:
    lda #$01
    sta a_used
@no_ab:
    lda a_down
    beq @edit_y
    jmp phrase_draw
@edit_y:
    ; Y held + up/down: previous / next phrase (genmddj A+up/down)
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
    lda ed_phrase
    dec a
    bpl @y_set
    lda #(PHRASE_COUNT - 1)
@y_set:
    sta ed_phrase
    jmp phrase_draw_hdr
@y_dn:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_DOWN
    sep #$20
.ACCU 8
    beq @edit_ok
    lda ed_phrase
    inc a
    cmp #PHRASE_COUNT
    bcc @y_set2
    lda #$00
@y_set2:
    sta ed_phrase
    jmp phrase_draw_hdr
@edit_ok:

    ; block mode: B copy / Y cut / A cancel / d-pad stretch (genmddj)
    lda blk_mode
    beq @no_blk
    jmp phrase_block
@no_blk:
    ; Y held + B pressed: enter block select (genmddj A-hold + B)
    rep #$20
.ACCU 16
    lda pad_held
    and #PAD_Y
    sep #$20
.ACCU 8
    beq @no_clear
    rep #$20
.ACCU 16
    lda pad_pressed
    and #PAD_B
    sep #$20
.ACCU 8
    beq @no_clear
    lda #$01
    sta blk_mode
    lda cur_y
    sta blk_start
    lda #$01
    sta b_used              ; swallow the release tap
    jmp @dpad_cursor
@no_clear:

    ; B edge tracking
    rep #$20
.ACCU 16
    lda pad_pressed
    and #PAD_B
    sep #$20
.ACCU 8
    beq @no_bpress
    lda #$01
    sta b_down
    stz b_used
@no_bpress:
    rep #$20
.ACCU 16
    lda pad_held
    and #PAD_B
    sep #$20
.ACCU 8
    bne @b_is_down
    ; B not held: was it released as a tap?
    lda b_down
    beq @dpad_cursor
    stz b_down
    lda b_used
    bne @dpad_cursor
    lda tap_live
    beq @single             ; no pending first tap (moved / new screen)
    lda frame_cnt
    sec
    sbc tap_timer
    cmp #25                 ; double-tap = 24 frames (~400 ms), genmddj's feel
    bcs @single
    stz tap_live            ; the pair is consumed
    jsr phrase_paste        ; B double-tap = paste the block clipboard
    bra @dpad_cursor
@single:
    lda frame_cnt
    sta tap_timer
    lda #$01
    sta tap_live
    jsr cell_tap
    bra @dpad_cursor

@b_is_down:
    ; B held + A tap: cut the cell (deleted value feeds the next insert)
    rep #$20
.ACCU 16
    lda pad_pressed
    and #PAD_A
    sep #$20
.ACCU 8
    beq @no_cut_a
    lda #$01
    sta b_used
    jsr cell_clear
    bra @draw
@no_cut_a:
    ; B held + Y tap: copy the cell to the insert buffer (genmddj B+A)
    rep #$20
.ACCU 16
    lda pad_pressed
    and #PAD_Y
    sep #$20
.ACCU 8
    beq @no_copy
    lda #$01
    sta b_used
    jsr cell_copy
    bra @draw
@no_copy:
    ; B held + d-pad = nudge
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_DPAD
    sep #$20
.ACCU 8
    beq @draw
    lda #$01
    sta b_used
    jsr cell_nudge
    bra @draw

@dpad_cursor:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_DPAD
    sep #$20
.ACCU 8
    beq @draw
    jsr cursor_move
@draw:
    jmp phrase_draw

phrase_draw_hdr:
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
    lda ed_phrase
    jsr text_hex8
    jmp phrase_draw

; --- cursor movement (d-pad events in pad_event) -------------------------------
cursor_move:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_LEFT
    sep #$20
.ACCU 8
    beq @nl
    lda ed_col
    beq @nl
    dec ed_col
@nl:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_RIGHT
    sep #$20
.ACCU 8
    beq @nr
    lda ed_col
    cmp #3
    bcs @nr
    inc ed_col
@nr:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_UP
    sep #$20
.ACCU 8
    beq @nu
    lda cur_y
    dec a
    and #$0F
    sta cur_y
@nu:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_DOWN
    sep #$20
.ACCU 8
    beq @nd
    lda cur_y
    inc a
    and #$0F
    sta cur_y
@nd:
    ; moving the cursor ends any pending double-tap (same-cell gesture)
    stz tap_live
    rts

; --- X = song-block offset of the cell under the cursor ------------------------
cell_addr:
    rep #$30
.ACCU 16
    lda ed_phrase
    and #$00FF
    xba
    lsr
    lsr                     ; phrase*64
    sta tmp2
    lda cur_y
    and #$00FF
    asl
    asl                     ; row*4
    clc
    adc tmp2
    sta tmp2
    lda ed_col
    and #$00FF
    clc
    adc tmp2
    tax
    sep #$20
.ACCU 8
    rts

; A = instrument byte of the cursor row ($FF if none)
phrase_cursor_instr:
    lda ed_col
    pha
    lda #$01
    sta ed_col
    jsr cell_addr
    pla
    sta ed_col
    lda.l $7E0000 + SB_PHRASES,x
    rts

; --- B tap: insert/edit --------------------------------------------------------
cell_tap:
    jsr cell_addr
    lda ed_col
    bne @not_note
    ; note: insert the note AND the last instrument, then audition
    lda ed_lastnote
    sta.l $7E0000 + SB_PHRASES,x
    lda ed_lastinstr
    sta.l $7E0000 + SB_PHRASES + 1,x
    lda ed_lastnote
    dec a
    jmp audition_note
@not_note:
    cmp #1
    bne @not_instr
    ; instrument: insert, then audition this row's note with it
    lda ed_lastinstr
    sta.l $7E0000 + SB_PHRASES,x
    lda.l $7E0000 + SB_PHRASES - 1,x
    beq @silent
    cmp #NOTE_OFF
    bcs @silent
    dec a
    jmp audition_note
@silent:
    rts
@not_instr:
    cmp #2
    bne @val
    ; command: the letter (with its value) drops into an EMPTY cell only,
    ; the genmddj rule; a tap on a C chord auditions it through the row's
    ; note + instrument
    lda.l $7E0000 + SB_PHRASES,x
    beq @cmd_ins
    cmp #CMDID_C
    beq @chord_aud
    rts
@cmd_ins:
    lda ed_lastcmd
    sta.l $7E0000 + SB_PHRASES,x
    lda ed_lastval
    sta.l $7E0000 + SB_PHRASES + 1,x
    rts
@chord_aud:
    ; X = the cmd cell; the row reads note(-2) instr(-1) cmd(0) val(+1);
    ; empty note/instr cells inherit the insert buffers, as at playback
    lda.l $7E0000 + SB_PHRASES + 1,x
    sta aud_chord
    lda.l $7E0000 + SB_PHRASES - 1,x
    cmp #INSTR_NONE
    bne @ca_instr
    lda ed_lastinstr
@ca_instr:
    sta aud_instr
    lda.l $7E0000 + SB_PHRASES - 2,x
    beq @ca_last
    cmp #NOTE_OFF
    bcc @ca_note
@ca_last:
    lda ed_lastnote
    beq @ca_done            ; nothing sensible to root the chord on
@ca_note:
    dec a                   ; note byte 1..96 -> index 0..95
    jmp audition_chord
@ca_done:
    rts
@val:
    lda ed_lastval
    sta.l $7E0000 + SB_PHRASES,x
    rts

; --- B held + Y: copy cell into the per-column insert buffer -------------------
cell_copy:
    jsr cell_addr
    lda.l $7E0000 + SB_PHRASES,x
    sta es3
    lda ed_col
    bne @not_note
    lda es3
    beq @done
    sta ed_lastnote
@done:
    rts
@not_note:
    cmp #$01
    bne @not_instr
    lda es3
    cmp #INSTR_NONE
    beq @done
    sta ed_lastinstr
    rts
@not_instr:
    cmp #$02
    bne @is_val
    lda es3
    beq @done
    sta ed_lastcmd
    rts
@is_val:
    lda es3
    sta ed_lastval
    rts

; --- B+A: cut (deleted value becomes the next B-tap insert) --------------------
cell_clear:
    jsr cell_addr
    lda.l $7E0000 + SB_PHRASES,x
    sta tmp1
    lda ed_col
    cmp #1
    bne @zero
    lda tmp1
    cmp #INSTR_NONE
    beq @i_wr
    sta ed_lastinstr
@i_wr:
    lda #INSTR_NONE
    sta.l $7E0000 + SB_PHRASES,x
    rts
@zero:
    ; note/cmd/val columns: 0 = empty
    lda ed_col
    bne @not_note
    lda tmp1
    beq @note_gone
    sta ed_lastnote
@note_gone:
    ; a deleted note takes its instrument with it
    lda #INSTR_NONE
    sta.l $7E0000 + SB_PHRASES + 1,x
    lda #$00
    bra @wr2
@not_note:
    cmp #2
    bne @is_val
    lda tmp1
    beq @wr
    sta ed_lastcmd
    bra @wr
@is_val:
    lda tmp1
    sta ed_lastval
@wr:
    lda #$00
@wr2:
    sta.l $7E0000 + SB_PHRASES,x
    rts

; --- B held + d-pad: nudge -----------------------------------------------------
; delta from pad_event: L=-1 R=+1 U=+big D=-big (big: note=12, others=16)
cell_nudge:
    jsr cell_addr
    lda.l $7E0000 + SB_PHRASES,x
    sta tmp1                ; current value
    ; compute signed delta -> tmp1+1
    stz tmp1 + 1
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_RIGHT
    sep #$20
.ACCU 8
    beq @nr2
    lda #$01
    sta tmp1 + 1
@nr2:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_LEFT
    sep #$20
.ACCU 8
    beq @nl2
    lda #$FF                ; -1
    sta tmp1 + 1
@nl2:
    lda ed_col
    beq @big12
    lda #16
    bra @bigset
@big12:
    lda #12
@bigset:
    sta tmp2                ; "big" magnitude
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_UP
    sep #$20
.ACCU 8
    beq @nu2
    lda tmp2
    sta tmp1 + 1
@nu2:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_DOWN
    sep #$20
.ACCU 8
    beq @nd2
    lda tmp2
    eor #$FF
    inc a                   ; -big
    sta tmp1 + 1
@nd2:
    lda tmp1 + 1
    beq @done
    ; dispatch per column
    lda ed_col
    beq @note
    cmp #1
    beq @instr
    cmp #2
    beq @cmd
    ; val: free byte wrap
    lda tmp1
    clc
    adc tmp1 + 1
    sta.l $7E0000 + SB_PHRASES,x
    sta ed_lastval
@done:
    rts
@note:
    lda tmp1
    bne @note_live
    ; empty cell: B+d-pad inserts the last note (and its instrument)
    ; straight away — no separate tap needed
    lda ed_lastnote
    sta.l $7E0000 + SB_PHRASES,x
    lda ed_lastinstr
    sta.l $7E0000 + SB_PHRASES + 1,x
    lda ed_lastnote
    dec a
    jmp audition_note
@note_live:
    cmp #NOTE_OFF
    beq @done
    clc
    adc tmp1 + 1
    beq @done               ; clamp: never nudge to empty
    cmp #NOTE_MAX + 1
    bcs @done               ; clamp top/underflow (wraps look like >96)
    sta.l $7E0000 + SB_PHRASES,x
    sta ed_lastnote
    dec a
    jmp audition_note
@instr:
    lda tmp1
    cmp #INSTR_NONE
    bne @instr_adj
    lda #$00                ; first nudge on empty -> instrument 0
    bra @instr_store
@instr_adj:
    clc
    adc tmp1 + 1
@instr_store:
    and #(INSTR_COUNT - 1)
    sta.l $7E0000 + SB_PHRASES,x
    sta ed_lastinstr
    rts
@cmd:
    lda tmp1
    clc
    adc tmp1 + 1
    bpl @cmd_ok
    lda #26                 ; wrap below 0 -> Z
@cmd_ok:
    cmp #27
    bcc @cmd_store
    lda #$00                ; wrap above Z -> none
@cmd_store:
    sta.l $7E0000 + SB_PHRASES,x
    sta ed_lastcmd
    rts

; --- block mode: rows [min(blk_start,cur_y) .. max] -----------------------------
phrase_block:
    ; A cancels
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
    jmp phrase_draw
@not_cancel:
    ; B = copy + exit; Y = cut + exit
    rep #$20
.ACCU 16
    lda pad_pressed
    and #PAD_B
    sep #$20
.ACCU 8
    beq @not_copy
    jsr phrase_blk_copy
    stz blk_mode
    lda #$01
    sta b_used
    stz b_down
    jmp phrase_draw
@not_copy:
    rep #$20
.ACCU 16
    lda pad_pressed
    and #PAD_Y
    sep #$20
.ACCU 8
    beq @not_cut
    jsr phrase_blk_copy
    jsr phrase_blk_clear
    stz blk_mode
    jmp phrase_draw
@not_cut:
    ; d-pad stretches (rows only)
    rep #$20
.ACCU 16
    lda pad_event
    and #(PAD_UP | PAD_DOWN)
    sep #$20
.ACCU 8
    beq @blk_done
    jsr cursor_move
@blk_done:
    jmp phrase_draw

; carry set when the drawn row (tmp0+1) is inside the block
phrase_blk_range_row:
    jsr phrase_blk_range
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

; block row range -> es0 = first row, es0+1 = count
phrase_blk_range:
    lda blk_start
    cmp cur_y
    bcc @fwd
    lda cur_y
    sta es0
    lda blk_start
    sec
    sbc cur_y
    inc a
    sta es0 + 1
    rts
@fwd:
    sta es0
    lda cur_y
    sec
    sbc blk_start
    inc a
    sta es0 + 1
    rts

; copy the block rows into the clipboard ($7E:7400)
phrase_blk_copy:
    jsr phrase_blk_range
    lda #$01
    sta clip_kind
    lda es0 + 1
    sta clip_len
    ; src base = phrase*64 + first*4 -> es1 ; count*4 -> es2 (word)
    rep #$30
.ACCU 16
    lda ed_phrase
    and #$00FF
    xba
    lsr
    lsr
    sta es1
    lda es0
    and #$00FF
    asl
    asl
    clc
    adc es1
    sta es1
    lda es0 + 1
    and #$00FF
    asl
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
    lda.l $7E0000 + SB_PHRASES,x
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

; clear the block rows (cut): note 0, instr $FF, cmd 0, val 0
phrase_blk_clear:
    jsr phrase_blk_range
    rep #$30
.ACCU 16
    lda ed_phrase
    and #$00FF
    xba
    lsr
    lsr
    sta es1
    lda es0
    and #$00FF
    asl
    asl
    clc
    adc es1
    tax
    sep #$20
.ACCU 8
@row:
    lda #$00
    sta.l $7E0000 + SB_PHRASES,x
    lda #INSTR_NONE
    sta.l $7E0000 + SB_PHRASES + 1,x
    lda #$00
    sta.l $7E0000 + SB_PHRASES + 2,x
    sta.l $7E0000 + SB_PHRASES + 3,x
    rep #$30
.ACCU 16
    inx
    inx
    inx
    inx
    sep #$20
.ACCU 8
    dec es0 + 1
    bne @row
    rts

; B double-tap: paste the clipboard at the cursor row (clamped to row 15)
phrase_paste:
    lda clip_kind
    cmp #$01
    beq @kind_ok
    rts
@kind_ok:
    lda #$10
    sec
    sbc cur_y
    cmp clip_len
    bcc @have_n
    lda clip_len
@have_n:
    sta es0 + 1
    beq @done
    rep #$30
.ACCU 16
    lda ed_phrase
    and #$00FF
    xba
    lsr
    lsr
    sta es1
    lda cur_y
    and #$00FF
    asl
    asl
    clc
    adc es1
    sta es1
    lda es0 + 1
    and #$00FF
    asl
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
    sta.l $7E0000 + SB_PHRASES,x
    rep #$30
.ACCU 16
    iny
    cpy es2
    bne @copy
    sep #$20
.ACCU 8
@done:
    rts

phrase_draw:
    stz tmp0 + 1            ; row counter
@rows:
    lda tmp0 + 1
    clc
    adc #5
    sta text_y
    ; row label
    stz text_x
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    sta text_attr
    sep #$20
.ACCU 8
    lda tmp0 + 1
    jsr text_hex8
    ; playhead
    lda #2
    sta text_x
    lda eng_playing
    beq @nohead
    lda trk_phrase
    cmp ed_phrase
    bne @nohead
    lda eng_row
    cmp tmp0 + 1
    bne @nohead
    rep #$20
.ACCU 16
    lda #ATTR_HILITE
    sta text_attr
    sep #$20
.ACCU 8
    lda #GLYPH_ARROW_R
    jsr text_puttile
    bra @cells
@nohead:
    lda #' ' - 32
    jsr text_puttile
@cells:
    ; fetch the row's 4 bytes into str_buf+32..35
    rep #$30
.ACCU 16
    lda ed_phrase
    and #$00FF
    xba
    lsr
    lsr
    sta tmp2
    lda tmp0 + 1
    and #$00FF
    asl
    asl
    clc
    adc tmp2
    tax
    sep #$20
.ACCU 8
    lda.l $7E0000 + SB_PHRASES,x
    sta str_buf + 32
    lda.l $7E0000 + SB_PHRASES + 1,x
    sta str_buf + 33
    lda.l $7E0000 + SB_PHRASES + 2,x
    sta str_buf + 34
    lda.l $7E0000 + SB_PHRASES + 3,x
    sta str_buf + 35

    ; NOTE cell — kit rows read as sample names (the note picks a
    ; slot, so the slot's pool name says more than a pitch)
    stz tmp0                ; column counter
    lda #3
    sta text_x
    jsr cell_attr
    jsr row_is_kit
    bcc @plain_note
    jsr draw_kit_name
    bra @note_drawn
@plain_note:
    lda str_buf + 32
    jsr draw_note
@note_drawn:

    ; INSTR cell
    inc tmp0
    lda #8
    sta text_x
    jsr cell_attr
    lda str_buf + 33
    cmp #INSTR_NONE
    bne @i_hex
    jsr draw_dashes2
    bra @i_done
@i_hex:
    jsr text_hex8
@i_done:

    ; CMD cell
    inc tmp0
    lda #12
    sta text_x
    jsr cell_attr
    lda str_buf + 34
    bne @c_letter
    lda #'-' - 32
    jsr text_puttile
    bra @c_done
@c_letter:
    clc
    adc #'A' - 32 - 1       ; cmd 1..26 -> A..Z
    jsr text_puttile
@c_done:

    ; VAL cell (contiguous with the command letter)
    inc tmp0
    lda #13
    sta text_x
    jsr cell_attr
    lda str_buf + 34        ; empty cmd draws val dimmed as --
    bne @v_hex
    lda str_buf + 35
    bne @v_hex
    jsr draw_dashes2
    bra @v_done
@v_hex:
    lda str_buf + 35
    jsr text_hex8
@v_done:

    inc tmp0 + 1
    lda tmp0 + 1
    cmp #PHRASE_ROWS
    bne @rows_far
    rts
@rows_far:
    jmp @rows

; attr for the cell (col tmp0, row tmp0+1): accent under cursor, dim if the
; row is empty-ish, text otherwise
cell_attr:
    ; block-select rows render hilite (cursor accent wins)
    lda blk_mode
    beq @no_blk_hl
    jsr phrase_blk_range_row
    bcc @no_blk_hl
    lda tmp0 + 1
    cmp cur_y
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
    cmp cur_y
    bne @not_cursor
    lda tmp0
    cmp ed_col
    bne @not_cursor
    rep #$20
.ACCU 16
    lda #ATTR_ACCENT
    sta text_attr
    sep #$20
.ACCU 8
    rts
@not_cursor:
    rep #$20
.ACCU 16
    lda #ATTR_TEXT
    sta text_attr
    sep #$20
.ACCU 8
    rts

draw_dashes2:
    lda #'-' - 32
    jsr text_puttile
    lda #'-' - 32
    jmp text_puttile

; carry set when the fetched row (str_buf+32 note, +33 instr) is a
; sounding note on a KIT-type instrument
row_is_kit:
    lda str_buf + 32
    beq @no
    cmp #NOTE_OFF
    beq @no
    lda str_buf + 33
    cmp #INSTR_NONE
    beq @no
    rep #$30
.ACCU 16
    and #$00FF
    asl
    asl
    asl
    asl
    tax
    sep #$20
.ACCU 8
    lda.l $7E0000 + SB_INSTR,x
    and #$03
    cmp #$01
    bne @no
    sec
    rts
@no:
    clc
    rts

; the kit row's slot -> 3 chars of its pool sample's name ("---" = empty)
draw_kit_name:
    ; kit id (X still = the instrument record from row_is_kit)
    lda.l $7E0000 + SB_INSTR + 1,x
    and #$0F
    rep #$30
.ACCU 16
    and #$00FF
    xba
    lsr
    lsr                     ; kit * 64
    sta tmp2
    sep #$20
.ACCU 8
    lda str_buf + 32
    dec a
    and #$0F                ; slot from the note, as kit_trigger maps it
    rep #$30
.ACCU 16
    and #$00FF
    asl
    asl
    clc
    adc tmp2
    tax
    sep #$20
.ACCU 8
    lda.l $7E0000 + SB_KITS + 2,x   ; vol 0 = empty slot
    beq @empty
    lda.l $7E0000 + SB_KITS,x
    and #$3F
    rep #$30
.ACCU 16
    and #$00FF
    asl
    asl
    asl
    asl                     ; pool entry * 16
    tax
    sep #$20
.ACCU 8
    lda.l POOL_ROM + 16,x
    sec
    sbc #32
    phx
    jsr text_puttile
    plx
    lda.l POOL_ROM + 17,x
    sec
    sbc #32
    phx
    jsr text_puttile
    plx
    lda.l POOL_ROM + 18,x
    sec
    sbc #32
    jmp text_puttile
@empty:
    lda #'-' - 32
    jsr text_puttile
    lda #'-' - 32
    jsr text_puttile
    lda #'-' - 32
    jmp text_puttile

; --- draw a note byte (A) as 3 glyphs at text_x/y ------------------------------
draw_note:
    bne @not_empty
    lda #'-' - 32
    jsr text_puttile
    lda #'-' - 32
    jsr text_puttile
    lda #'-' - 32
    jmp text_puttile
@not_empty:
    cmp #NOTE_OFF
    bne @named
    lda #'O' - 32
    jsr text_puttile
    lda #'F' - 32
    jsr text_puttile
    lda #'F' - 32
    jmp text_puttile
@named:
    dec a                   ; note index 0..95
    pha
    rep #$20
.ACCU 16
    and #$00FF
    tax
    sep #$20
.ACCU 8
    lda.w note_semi2,x
    lsr                     ; semitone 0..11
    rep #$20
.ACCU 16
    and #$00FF
    tax
    sep #$20
.ACCU 8
    lda.w note_name2,x      ; fetch both chars first: text_puttile clobbers X
    pha
    lda.w note_name1,x
    sec
    sbc #32
    jsr text_puttile
    pla
    sec
    sbc #32
    jsr text_puttile
    pla
    rep #$20
.ACCU 16
    and #$00FF
    tax
    sep #$20
.ACCU 8
    lda.w note_shift,x      ; 7 - octave
    eor #$FF
    clc
    adc #8                  ; octave = 7 - shift
    clc
    adc #'0'
    sec
    sbc #32
    jmp text_puttile

note_name1: .DB "CCDDEFFGGAAB"
note_name2: .DB "-#-#--#-#-#-"

str_phrase: .DB "PHRASE ", 0
str_cols:   .DB "NOTE IN  CMD", 0
