; livescr.asm — LIVE mode: the clip launcher (CLAUDE.md §8).
; A grid of song-row chain cells like SONG. A+B (the genmddj C+B
; launch gesture) queues the cursor cell's chain on its track,
; launching at that track's next phrase boundary (quantised); on the
; cell the track is playing it queues that track's stop. Plain B is
; edit-only (insert a chain on an empty cell). X held + up/down mutes
; the cursor track, X held + left/right solos it. Muted tracks dash
; the header (signal metering is out for now). Select toggles LIVE
; from anywhere.

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
    stz text_x
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
    ; Start: stop when playing; from stopped, launch every populated track
    ; on the cursor row (genmddj LIVE Start)
    rep #$20
.ACCU 16
    lda pad_pressed
    and #PAD_START
    sep #$20
.ACCU 8
    beq @no_start
    lda eng_playing
    beq @launch_row
    jsr engine_stop
    bra @no_start
@launch_row:
    jsr live_launch_row
@no_start:
    ; A held + B: launch/queue the cursor cell (genmddj LIVE C+B)
    lda a_down
    beq @no_ab
    rep #$20
.ACCU 16
    lda pad_pressed
    and #PAD_B
    sep #$20
.ACCU 8
    beq @no_ab
    jsr live_queue_cursor
    lda #$01
    sta a_used
@no_ab:
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
    ; plain B is EDIT, never transport: insert a chain on an empty
    ; cell (Seb, 2026-07-12 — launching is the A+B gesture only)
    rep #$20
.ACCU 16
    lda pad_pressed
    and #PAD_B
    sep #$20
.ACCU 8
    beq @no_b
    jsr live_edit_cursor
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

; A+B: queue the cursor cell's chain on its track (launches now if
; stopped). On the cell the track is PLAYING it queues a STOP ($FE)
; instead: the track finishes its phrase and halts at the boundary
; under the X marker (never re-trigger the chain you're hearing —
; Seb, 2026-07-12). Empty cells are inert here; plain B edits them.
live_queue_cursor:
    jsr song_cursor_cell    ; A = chain under cursor ($FF = empty)
    pha
    lda song_cx
    rep #$30
.ACCU 16
    and #$00FF
    tax
    sep #$20
.ACCU 8
    pla
    cmp #$FF
    beq @done
    ; occupied cell: on the track's playing cell, stop; else launch
    pha
    lda eng_playing
    beq @not_playing
    lda.w trk_phrase,x
    cmp #$FF
    beq @not_playing
    ; the playing cell: song row for arrangement tracks, live_row
    ; for launched chains (same resolution as the playhead glyph)
    lda.w trk_songrow,x
    cmp #$FF
    bne +
    lda.w trk_live_row,x
+
    cmp song_cy
    bne @not_playing
    pla                     ; cursor is on the chain being heard
    lda #$FE
    sta.w trk_pending,x     ; queue its stop (X while it drains)
    rts
@not_playing:
    pla
    sta.w trk_pending,x
    lda song_cy
    sta.w trk_pend_row,x
    lda eng_playing
    bne @done
    jsr engine_play_live
@done:
    rts

; plain B: edit-only — insert a chain (SONG's tap insert) on an empty
; cell so material can be built without leaving the launcher; A+B then
; launches it. Occupied cells are inert (performance safety: a stray B
; must never overwrite or trigger anything).
live_edit_cursor:
    jsr song_cursor_cell    ; A = chain under cursor ($FF = empty)
    cmp #$FF
    bne @done
    jsr song_cell_addr
    lda ed_lastchain
    sta.l $7E0000 + SB_SONG,x
@done:
    rts

; queue every populated track on the cursor row, then launch
live_launch_row:
    ldx #$0000
@scan:
    ; cell = SONG[track][song_cy]
    phx
    rep #$30
.ACCU 16
    txa
    xba
    lsr                     ; track * 128
    sta es0
    lda song_cy
    and #$00FF
    clc
    adc es0
    tax
    sep #$20
.ACCU 8
    lda.l $7E0000 + SB_SONG,x
    plx
    cmp #$FF
    beq @next
    sta.w trk_pending,x
    lda song_cy
    sta.w trk_pend_row,x
@next:
    inx
    cpx #TRACKS
    bne @scan
    jmp engine_play_live

; clear all queued launches/stops ($FF = nothing pending). Boot WRAM is
; zero, and 0 is a valid chain id — without this the first LIVE launch
; reads "chain 0 queued" on every track and starts all eight.
live_pending_reset:
    ldx #$0000
    lda #$FF
@clr:
    sta.w trk_pending,x
    inx
    cpx #TRACKS
    bne @clr
    rts

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
    lda.w trk_pend_row,x
    sta.w trk_live_row,x    ; the playhead marks the launched cell
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
    ; mute state per track (a dim dash) — signal metering is out for
    ; now (Seb, 2026-07-12); the ENVX telemetry keeps flowing for
    ; checks and any future readout
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
    lda #ATTR_TEXT
    sta text_attr
    sep #$20
.ACCU 8
    lda #' ' - 32
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
