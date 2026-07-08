; livescr.asm — LIVE mode: the clip launcher (CLAUDE.md §8).
; A grid of song-row chain cells like SONG, but B queues the cursor cell's
; chain on its track, launching exactly at that track's next phrase
; boundary (quantised). X held + up/down mutes the cursor track, X held +
; left/right solos it. ENVX meters ride the header — the chip's own
; envelopes, streamed up by the driver. Select toggles LIVE from anywhere.

.ACCU 8
.INDEX 16

live_init:
    lda ui_mode
    cmp #SCREEN_LIVE
    beq +
    sta live_prev
+
    lda #SCREEN_LIVE
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
    ldx #str_live
    jsr text_puts
    rts

live_update:
    ; Start: play/stop the song
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
    jmp live_draw
@edit_ok:
    ; X held: mute/solo the cursor track
    rep #$20
.ACCU 16
    lda pad_held
    and #PAD_X
    sep #$20
.ACCU 8
    beq @no_x
    rep #$20
.ACCU 16
    lda pad_event
    and #(PAD_UP | PAD_DOWN)
    sep #$20
.ACCU 8
    beq @try_solo
    ; toggle mute on the cursor track
    lda song_cx
    rep #$30
.ACCU 16
    and #$00FF
    tax
    sep #$20
.ACCU 8
    lda.w bit_for_track,x
    eor trk_mute
    sta trk_mute
    jsr live_mute_koff
    jmp live_draw
@try_solo:
    rep #$20
.ACCU 16
    lda pad_event
    and #(PAD_LEFT | PAD_RIGHT)
    sep #$20
.ACCU 8
    beq @x_done
    ; solo: mute everyone else (or clear if already soloed)
    lda song_cx
    rep #$30
.ACCU 16
    and #$00FF
    tax
    sep #$20
.ACCU 8
    lda.w bit_for_track,x
    eor #$FF
    cmp trk_mute
    bne @solo_set
    stz trk_mute            ; already soloed: unmute all
    bra @solo_done
@solo_set:
    sta trk_mute
@solo_done:
    jsr live_mute_koff
@x_done:
    jmp live_draw
@no_x:
    ; B tap: queue the cursor cell's chain on this track
    rep #$20
.ACCU 16
    lda pad_pressed
    and #PAD_B
    sep #$20
.ACCU 8
    beq @no_b
    jsr song_cursor_cell    ; A = chain under cursor ($FF = empty)
    cmp #$FF
    beq @no_b
    pha
    lda song_cx
    rep #$30
.ACCU 16
    and #$00FF
    tax
    sep #$20
.ACCU 8
    pla
    sta.w trk_pending,x
    ; if stopped, launch immediately as a standalone chain
    lda eng_playing
    bne @no_b
    jsr engine_play_live
@no_b:
    ; plain cursor movement (reuses the SONG cursor + window)
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_DPAD
    sep #$20
.ACCU 8
    beq @draw
    jsr song_cursor_move
@draw:
    jmp live_draw

; key off any newly muted voices so they don't ring
live_mute_koff:
    lda trk_mute
    beq @done
    tay
    lda #DSP_KOF
    jsr apu_dsp_write
    lda #DSP_KOF
    ldy #$0000
    jsr apu_dsp_write
@done:
    rts

; start transport with all tracks idle; queued launches fire on tick 1
engine_play_live:
    jsr engine_halt_all
    ldx #$0000
@seed:
    lda.w trk_pending,x
    cmp #$FF
    beq @next
    sta.w trk_chain,x
    lda #$FF
    sta.w trk_pending,x
    sta.w trk_songrow,x     ; standalone chain semantics (loops)
    sta.w trk_prow,x        ; start sentinel
    lda #$00
    sta.w trk_cpos,x
    jsr track_load_chain_entry
@next:
    inx
    cpx #TRACKS
    bne @seed
    jmp engine_go

live_draw:
    ; ENVX meters in the header (driver telemetry, the chip's own envelopes)
    stz ui_cnt
@meters:
    lda ui_cnt
    asl
    clc
    adc ui_cnt
    adc #4                  ; x = 4 + t*3 (aligned with the grid)
    sta text_x
    lda #2
    sta text_y
    ; muted tracks show a dim dash instead of a meter
    lda ui_cnt
    rep #$30
.ACCU 16
    and #$00FF
    tax
    sep #$20
.ACCU 8
    lda.w bit_for_track,x
    and trk_mute
    beq @meter_on
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    sta text_attr
    sep #$20
.ACCU 8
    lda #'-' - 32
    jsr text_puttile
    bra @meter_next
@meter_on:
    rep #$20
.ACCU 16
    lda #ATTR_HILITE
    sta text_attr
    sep #$20
.ACCU 8
    lda.w envx_mirror,x
    lsr
    lsr
    lsr
    lsr
    lsr                     ; level 0-3 (ENVX is 7 bits)
    cmp #$04
    bcc @lvl
    lda #$03
@lvl:
    sta es0
    lda #GLYPH_BLOCK14      ; glyphs run full(64)..quarter(67)
    sec
    sbc es0                 ; level 0 -> 1/4, 3 -> full
    jsr text_puttile
@meter_next:
    inc ui_cnt
    lda ui_cnt
    cmp #TRACKS
    bne @meters
    ; the launch grid is the SONG grid renderer (cursor/window shared)
    jsr song_draw
    rts

str_live: .DB "LIVE", 0
