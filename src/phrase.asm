; phrase.asm — the PHRASE screen: 16 rows of NOTE / INSTR / CMD / VAL with
; the sibling B-grammar: B tap = insert/edit (+audition on the note column),
; B held + d-pad = nudge (L/R small, U/D big), Y+B = clear cell,
; Start = play/stop. CMD/VAL are stored but inert until M7; INSTR until M6.

.ACCU 8
.INDEX 16

; column geometry
col_x:  .DB 4, 8, 11, 13
col_w:  .DB 3, 2, 1, 2

phrase_init:
    lda #SCREEN_PHRASE
    sta ui_mode
    stz ed_col
    stz cur_y
    stz b_down
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
    ldx #str_phrase
    jsr text_puts
    lda ed_phrase
    jsr text_hex8
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
    lda a_down
    beq @edit_ok
    jmp phrase_draw
@edit_ok:

    ; Y held + B pressed: clear cell
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
    jsr cell_clear
    lda #$01
    sta b_used              ; swallow the release tap
    bra @dpad_cursor
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
    jsr cell_tap
    bra @dpad_cursor

@b_is_down:
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

; --- B tap: insert/edit --------------------------------------------------------
cell_tap:
    jsr cell_addr
    lda ed_col
    bne @not_note
    lda ed_lastnote
    sta.l $7E0000 + SB_PHRASES,x
    dec a
    jmp audition_note
@not_note:
    cmp #1
    bne @not_instr
    lda ed_lastinstr
    sta.l $7E0000 + SB_PHRASES,x
    rts
@not_instr:
    cmp #2
    bne @val
    lda ed_lastcmd
    sta.l $7E0000 + SB_PHRASES,x
    rts
@val:
    lda ed_lastval
    sta.l $7E0000 + SB_PHRASES,x
    rts

; --- Y+B: cut (deleted value becomes the next B-tap insert) --------------------
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
    beq @wr
    sta ed_lastnote
    bra @wr
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
    beq @done               ; nudge on empty does nothing
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

; ---------------------------------------------------------------------------
; drawing (full redraw each frame; BG3 shadow map, NMI ships it)
; ---------------------------------------------------------------------------
phrase_draw:
    stz tmp0 + 1            ; row counter
@rows:
    lda tmp0 + 1
    clc
    adc #4
    sta text_y
    ; row label
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
    ; playhead
    lda #3
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

    ; NOTE cell
    stz tmp0                ; column counter
    lda #4
    sta text_x
    jsr cell_attr
    lda str_buf + 32
    jsr draw_note

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
    lda #11
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

    ; VAL cell
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
