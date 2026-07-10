; projectscr.asm — the PROJECT screen: song-level settings.
;
;   NAME    the song's 8-char name (renamed on FILES, shown here)
;   TMPO    the song's tick BPM (B-hold + d-pad, 80-255; applied to
;           the APU timer immediately and at play start)
;   GROOVE  default groove id (B-hold + left/right)
;   TSP     song transpose, signed semitones (applied at trigger)
;   MODE    SONG or LIVE — in LIVE the S map position opens the
;           launcher view
;   NEW     wipe to a fresh song (tap B, then tap again to confirm)
;
; Reached with A+Up from CHAIN.

.ACCU 8
.INDEX 16

.DEFINE PJ_FIELDS 6

project_init:
    lda #SCREEN_PROJECT
    sta ui_mode
    stz pj_cur
    stz pj_arm
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
    ldx #str_project
    jsr text_puts
    rts

project_update:
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
    jmp project_draw
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
    ; B tap: only NEW acts on a tap (armed, then confirmed)
    lda pj_cur
    cmp #$05
    bne @tap_done
    lda pj_arm
    bne @do_new
    lda #$01
    sta pj_arm
    bra @tap_done
@do_new:
    stz pj_arm
    jsr song_renew
@tap_done:
    jmp project_draw
@b_held:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_DPAD
    sep #$20
.ACCU 8
    beq @b_draw
    lda #$01
    sta b_used
    jsr pj_nudge
@b_draw:
    jmp project_draw
@cursor:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_UP
    sep #$20
.ACCU 8
    beq @nu
    stz pj_arm              ; moving the cursor disarms NEW
    lda pj_cur
    dec a
    bpl @up_ok
    lda #PJ_FIELDS - 1
@up_ok:
    sta pj_cur
@nu:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_DOWN
    sep #$20
.ACCU 8
    beq @draw
    stz pj_arm
    lda pj_cur
    inc a
    cmp #PJ_FIELDS
    bcc @dn_ok
    lda #$00
@dn_ok:
    sta pj_cur
@draw:
    jmp project_draw

pj_nudge:
    ; big step per field: TMPO = 16, transpose = an octave, others 4
    lda pj_cur
    cmp #$01
    bne @not_tmpo
    lda #16
    bra @mag_have
@not_tmpo:
    cmp #$03
    bne @mag_4
    lda #12
    bra @mag_have
@mag_4:
    lda #4
@mag_have:
    sta tmp2
    jsr nudge_delta         ; -> tmp1+1
    lda tmp1 + 1
    bne @have
    rts
@have:
    sta es3 + 1
    lda pj_cur
    cmp #$01
    beq @tmpo
    cmp #$02
    beq @groove
    cmp #$03
    beq @tsp
    cmp #$04
    beq @mode
    rts
@tmpo:
    lda.l $7E0000 + SB_HEADER + SH_BPM
    bne +
    lda #150
+
    clc
    adc es3 + 1
    cmp #80
    bcs +
    lda #80                 ; the tick divider needs BPM >= 80
+
    sta.l $7E0000 + SB_HEADER + SH_BPM
    jmp apu_set_tempo       ; applies immediately
@groove:
    lda.l $7E0000 + SB_HEADER + SH_GROOVE
    clc
    adc es3 + 1
    and #(GROOVE_COUNT - 1)
    sta.l $7E0000 + SB_HEADER + SH_GROOVE
    rts
@tsp:
    ; signed semitones, free wrap
    lda.l $7E0000 + SB_HEADER + SH_TRANSPOSE
    clc
    adc es3 + 1
    sta.l $7E0000 + SB_HEADER + SH_TRANSPOSE
    rts
@mode:
    lda.l $7E0000 + SB_HEADER + SH_MODE
    eor #$01
    sta.l $7E0000 + SB_HEADER + SH_MODE
    rts

project_draw:
    stz ui_cnt
@rows:
    lda ui_cnt
    clc
    adc #8
    sta text_y
    lda #2
    sta text_x
    ; labels stay dim; the VALUE carries the cursor accent
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    sta text_attr
    sep #$20
.ACCU 8
@label:
    lda ui_cnt
    rep #$30
.ACCU 16
    and #$00FF
    asl
    tax
    lda.w pj_labels,x
    tax
    sep #$20
.ACCU 8
    jsr text_puts
    ; value at x12 (accent under the cursor)
    lda #12
    sta text_x
    lda ui_cnt
    cmp pj_cur
    bne @val_plain
    rep #$20
.ACCU 16
    lda #ATTR_ACCENT
    sta text_attr
    sep #$20
.ACCU 8
    bra @val_go
@val_plain:
    rep #$20
.ACCU 16
    lda #ATTR_TEXT
    sta text_attr
    sep #$20
.ACCU 8
@val_go:
    lda ui_cnt
    bne @not_name
    ; NAME from the song header
    stz sv_run
@name:
    lda sv_run
    phx
    rep #$30
.ACCU 16
    and #$00FF
    tax
    sep #$20
.ACCU 8
    lda.l $7E0000 + SB_HEADER + SH_NAME,x
    plx
    sec
    sbc #32
    jsr text_puttile
    inc sv_run
    lda sv_run
    cmp #$08
    bne @name
    jmp @next
@not_name:
    cmp #$01
    bne @not_tmpo
    ; TMPO: the song's tick BPM (editable; grooves scale the feel)
    lda.l $7E0000 + SB_HEADER + SH_BPM
    bne +
    lda #150
+
    rep #$30
.ACCU 16
    and #$00FF
    sta tmp0
    sep #$20
.ACCU 8
    jsr text_dec3
    jmp @next
@not_tmpo:
    cmp #$02
    bne @not_groove
    lda.l $7E0000 + SB_HEADER + SH_GROOVE
    jsr text_hex8
    jmp @next
@not_groove:
    cmp #$03
    bne @not_tsp
    lda.l $7E0000 + SB_HEADER + SH_TRANSPOSE
    jsr text_hex8
    jmp @next
@not_tsp:
    cmp #$04
    bne @not_mode
    lda.l $7E0000 + SB_HEADER + SH_MODE
    beq @m_song
    ldx #str_pj_live
    jsr text_puts
    jmp @next
@m_song:
    ldx #str_pj_song
    jsr text_puts
    jmp @next
@not_mode:
    ; NEW: show the armed state
    lda pj_arm
    beq @calm
    rep #$20
.ACCU 16
    lda #ATTR_ACCENT
    sta text_attr
    sep #$20
.ACCU 8
    ldx #str_pj_sure
    jsr text_puts
    bra @next
@calm:
    ldx #str_pj_tap
    jsr text_puts
@next:
    inc ui_cnt
    lda ui_cnt
    cmp #PJ_FIELDS
    beq @done
    jmp @rows
@done:
    rts

pj_labels: .DW str_pj_name, str_pj_tmpo, str_pj_grv, str_pj_tsp
           .DW str_pj_mode, str_pj_new

str_project: .DB "PROJECT", 0
str_pj_name: .DB "NAME", 0
str_pj_tmpo: .DB "TMPO", 0
str_pj_grv:  .DB "GROOVE", 0
str_pj_tsp:  .DB "TSP", 0
str_pj_mode: .DB "MODE", 0
str_pj_new:  .DB "NEW", 0
str_pj_song: .DB "SONG ", 0
str_pj_live: .DB "LIVE ", 0
str_pj_tap:  .DB "        ", 0
str_pj_sure: .DB "SURE?   ", 0
