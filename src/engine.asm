; engine.asm — the per-tick sequencer core (M5: 8 tracks playing chains
; from the SONG grid; track t drives voice t).
;
; The master tick comes from SPC700 Timer 0 (via port-3 telemetry, mirrored
; into apu_tick each frame). The engine consumes tick deltas in the MAIN
; LOOP — never in NMI (invariant #7). Groove entries are ticks-per-row;
; grooves ARE the tempo (§9). All tracks advance rows in lockstep, but each
; walks its own chain/phrase (chain end -> next song row, empty cell halts
; the track). KON/KOF are batched per row into single DSP writes.

.ACCU 8
.INDEX 16

; --- initialise a NEW song block ----------------------------------------------
song_init:
    ; wipe the whole block
    rep #$30
.ACCU 16
    lda #$0000
    ldx #SB
@wipe:
    sta.l $7E0000,x
    inx
    inx
    cpx #SB_END
    bne @wipe
    sep #$20
.ACCU 8
    ; phrase instrument bytes: $FF = none (note/cmd/val stay 0 = empty)
    ldx #$0001              ; offset of the instr byte in row 0
    lda #INSTR_NONE
@instr_none:
    sta.l $7E0000 + SB_PHRASES,x
    inx
    inx
    inx
    inx
    cpx #(PHRASE_COUNT * PHRASE_SZ + 1)
    bcc @instr_none
    ; chain phrase entries: $FF = empty (transpose bytes stay 0)
    ldx #$0000
    lda #$FF
@chain_none:
    sta.l $7E0000 + SB_CHAINS,x
    inx
    inx
    cpx #(CHAIN_COUNT * CHAIN_SZ)
    bcc @chain_none
    ; song grid: $FF = empty
    ldx #$0000
    lda #$FF
@song_none:
    sta.l $7E0000 + SB_SONG,x
    inx
    cpx #(TRACKS * SONG_ROWS)
    bcc @song_none
    ; grooves: groove 0 = 6 ticks/row on all 16 steps
    ldx #$0000
    lda #6
@groove:
    sta.l $7E0000 + SB_GROOVES,x
    inx
    cpx #GROOVE_SZ
    bne @groove
    ; header
    lda #$00
    sta.l $7E0000 + SB_HEADER + SH_GROOVE
    lda #$D7
    sta.l $7E0000 + SB_HEADER + SH_MAGIC
    rts

; --- start/stop ----------------------------------------------------------------
; Start playback from song row 0: every track loads its first chain.
engine_play:
    ldx #$0000
@track:
    lda #$00
    sta.w trk_songrow,x
    sta.w trk_cpos,x
    sta.w trk_tsp,x
    lda #$FF
    sta.w trk_prow,x        ; start sentinel: first advance lands on row 0
    jsr track_load_songrow  ; sets trk_chain/trk_phrase (or halts track)
    inx
    cpx #TRACKS
    bne @track
    jmp engine_go

; load the chain + first phrase for trk_songrow of track X; halt on empty
track_load_songrow:
    phx
    ; song cell: SB_SONG + track*SONG_ROWS + row
    rep #$30
.ACCU 16
    txa
    xba                     ; track * 256... SONG_ROWS = 128: track*128:
    lsr                     ; track*128
    sta tmp2
    lda.w trk_songrow,x     ; low byte = row (high byte = neighbour, masked)
    and #$00FF
    clc
    adc tmp2
    tax
    sep #$20
.ACCU 8
    lda.l $7E0000 + SB_SONG,x
    plx
    sta.w trk_chain,x
    cmp #$FF
    beq @halt
    lda #$00
    sta.w trk_cpos,x
    jmp track_load_chain_entry
@halt:
    lda #$FF
    sta.w trk_phrase,x
    rts

; load chain entry trk_cpos for track X -> phrase + transpose; recurse to
; the next song row when the entry (or end of chain) is empty
track_load_chain_entry:
    phx
    rep #$30
.ACCU 16
    lda.w trk_chain,x
    and #$00FF
    asl
    asl
    asl
    asl
    asl                     ; chain * 32
    sta tmp2
    lda.w trk_cpos,x
    and #$00FF
    asl                     ; entry * 2
    clc
    adc tmp2
    tax
    sep #$20
.ACCU 8
    lda.l $7E0000 + SB_CHAINS,x
    sta tmp1                ; phrase id
    lda.l $7E0000 + SB_CHAINS + 1,x
    sta tmp1 + 1            ; transpose
    plx
    lda tmp1
    cmp #$FF
    beq @next_songrow
    sta.w trk_phrase,x
    lda tmp1 + 1
    sta.w trk_tsp,x
    rts
@next_songrow:
    lda.w trk_songrow,x
    cmp #$FF
    bne @from_song
    ; standalone chain (Start on the CHAIN screen): loop back to entry 0,
    ; unless the chain is empty at the top
    lda.w trk_cpos,x
    beq @halt
    lda #$00
    sta.w trk_cpos,x
    jmp track_load_chain_entry
@from_song:
    ; end of chain: advance the song row (halt at end of grid)
    lda.w trk_songrow,x
    inc a
    cmp #SONG_ROWS
    bcs @halt
    sta.w trk_songrow,x
    jmp track_load_songrow
@halt:
    lda #$FF
    sta.w trk_phrase,x
    rts

; Start on the PHRASE screen: loop ed_phrase on track 0, others silent.
engine_play_phrase:
    jsr engine_halt_all
    lda ed_phrase
    sta trk_phrase
    lda #$FE                ; sentinel: no chain, loop the phrase forever
    sta trk_chain
    lda #$FF
    sta trk_prow            ; start sentinel
    stz trk_tsp
    bra engine_go_near

; Start on the CHAIN screen: loop ed_chain on track 0, others silent.
engine_play_chain:
    jsr engine_halt_all
    lda ed_chain
    sta trk_chain
    lda #$FF
    sta trk_songrow         ; sentinel: standalone chain (loops)
    stz trk_cpos
    lda #$FF
    sta trk_prow            ; start sentinel
    ldx #$0000
    jsr track_load_chain_entry
engine_go_near:
    bra engine_go

engine_halt_all:
    ldx #$0000
    lda #$FF
@h:
    sta.w trk_phrase,x
    inx
    cpx #TRACKS
    bne @h
    rts

engine_go:
    lda #$0F
    sta eng_row
    stz eng_tickwait
    stz eng_gpos
    lda apu_tick
    sta eng_tick_last
    lda #$01
    sta eng_playing
    rts

engine_stop:
    stz eng_playing
    lda #DSP_KOF
    ldy #$00FF              ; release all voices
    jsr apu_dsp_write
    lda #DSP_KOF
    ldy #$0000              ; drop the latch so later KONs win
    jmp apu_dsp_write

; Start: stop if playing; else play what the current screen shows
engine_toggle:
    lda eng_playing
    beq @start
    bra engine_stop
@start:
    lda ui_mode
    cmp #SCREEN_PHRASE
    beq engine_play_phrase
    cmp #SCREEN_CHAIN
    beq engine_play_chain
    jmp engine_play

; --- per-frame: consume tick deltas from the APU -------------------------------
engine_update:
    lda eng_playing
    beq @done
    lda apu_tick
    sec
    sbc eng_tick_last
    beq @done
    cmp #$08                ; cap catch-up to avoid spiralling after stalls
    bcc @n_ok
    lda #$08
@n_ok:
    sta tmp0
    lda apu_tick
    sta eng_tick_last
@tickloop:
    jsr engine_tick
    dec tmp0
    bne @tickloop
@done:
    rts

; --- one engine tick ------------------------------------------------------------
engine_tick:
    lda eng_tickwait
    beq @row
    dec eng_tickwait
    rts
@row:
    ; ticks for this row from the groove
    ldx #$0000
    lda eng_gpos
    rep #$20
.ACCU 16
    and #$00FF
    tax
    sep #$20
.ACCU 8
    lda.l $7E0000 + SB_GROOVES,x
    bne @g_ok
    lda #6
@g_ok:
    dec a
    sta eng_tickwait
    lda eng_gpos
    inc a
    and #(GROOVE_SZ - 1)
    sta eng_gpos

    ; advance + trigger every track; batch KON/KOF
    stz kon_mask
    stz koff_mask
    ldx #$0000
@each:
    jsr track_row
    inx
    cpx #TRACKS
    bne @each
    lda trk_prow            ; mirror track 0 for playhead/checks
    sta eng_row
    ; ship the batched key events (KOF first, then KON — driver serialises)
    lda koff_mask
    beq @no_koff
    tay
    lda #DSP_KOF
    jsr apu_dsp_write
    lda #DSP_KOF
    ldy #$0000
    jsr apu_dsp_write
@no_koff:
    lda kon_mask
    beq @no_kon
    tay
    lda #DSP_KON
    jsr apu_dsp_write
    inc kon_count
@no_kon:
    rts

; --- advance one row on track X and trigger its phrase cell --------------------
track_row:
    lda.w trk_phrase,x
    cmp #$FF
    bne @alive
    rts
@alive:
    ; next phrase row
    lda.w trk_prow,x
    cmp #$FF
    bne @advance
    lda #$00                ; start sentinel: begin at row 0
    sta.w trk_prow,x
    bra @trigger
@advance:
    inc a
    and #$0F
    sta.w trk_prow,x
    bne @trigger
    ; wrapped: standalone phrase mode just loops
    lda.w trk_chain,x
    cmp #$FE
    beq @trigger
    ; next chain entry
    lda.w trk_cpos,x
    inc a
    and #$0F
    sta.w trk_cpos,x
    bne @entry
    ; wrapped past entry 15: next song row
    lda.w trk_songrow,x
    inc a
    cmp #SONG_ROWS
    bcs @halt
    sta.w trk_songrow,x
    jsr track_load_songrow
    bra @check
@entry:
    jsr track_load_chain_entry
@check:
    lda.w trk_phrase,x
    cmp #$FF
    beq @done
@trigger:
    ; read the phrase cell: SB_PHRASES + phrase*64 + prow*4
    phx
    rep #$30
.ACCU 16
    lda.w trk_phrase,x
    and #$00FF
    xba
    lsr
    lsr                     ; phrase * 64
    sta tmp2
    lda.w trk_prow,x
    and #$00FF
    asl
    asl
    clc
    adc tmp2
    tax                     ; (track index is saved on the stack)
    sep #$20
.ACCU 8
    lda.l $7E0000 + SB_PHRASES,x
    plx
    cmp #$00                ; plx clobbered the flags; re-test the note byte
    beq @done               ; empty
    cmp #NOTE_OFF
    bne @note
    ; key off this voice at end of tick
    lda.w bit_for_track,x
    ora koff_mask
    sta koff_mask
    rts
@note:
    ; apply transpose (signed), clamp to note range
    clc
    adc.w trk_tsp,x
    dec a                   ; note byte 1..96 -> index 0..95
    cmp #NOTE_MAX
    bcc @in_range
    lda #NOTE_MAX - 1       ; clamp (also catches signed underflow wraps)
@in_range:
    pha
    txa
    sta trig_voice
    pla
    phx
    jsr note_pitch          ; writes VxPITCH for trig_voice
    plx
    lda.w bit_for_track,x
    ora kon_mask
    sta kon_mask
@done:
    rts
@halt:
    lda #$FF
    sta.w trk_phrase,x
    rts

bit_for_track:
    .DB $01, $02, $04, $08, $10, $20, $40, $80
