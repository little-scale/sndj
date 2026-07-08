; engine.asm — the per-tick sequencer core (M4: single phrase on voice 0).
;
; The master tick comes from SPC700 Timer 0 (via port-3 telemetry, mirrored
; into apu_tick each frame). The engine consumes tick deltas in the MAIN
; LOOP — never in NMI (invariant #7). Groove entries are ticks-per-row;
; grooves ARE the tempo (§9): at the fixed 60.15 Hz tick, groove 6 =
; ~150 BPM at 4 rows/beat.

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
engine_play:
    lda #$01
    sta eng_playing
    lda #$0F
    sta eng_row             ; pre-first row: first tick advances to row 0
    stz eng_tickwait
    stz eng_gpos
    lda apu_tick
    sta eng_tick_last
    rts

engine_stop:
    stz eng_playing
    lda #DSP_KOF
    ldy #$0001              ; release voice 0
    jsr apu_dsp_write
    lda #DSP_KOF
    ldy #$0000              ; drop the KOF latch so later KONs win
    jmp apu_dsp_write

engine_toggle:
    lda eng_playing
    beq engine_play
    bra engine_stop

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
    sta tmp1
    lda apu_tick
    sta eng_tick_last
@tickloop:
    jsr engine_tick
    dec tmp1
    bne @tickloop
@done:
    rts

; --- one engine tick ------------------------------------------------------------
engine_tick:
    lda eng_tickwait
    beq @advance
    dec eng_tickwait
    rts
@advance:
    ; next row
    lda eng_row
    inc a
    and #$0F
    sta eng_row
    ; ticks for this row from the groove (skip 0 entries defensively)
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
    lda #6                  ; zero groove entry: sane fallback
@g_ok:
    dec a                   ; this tick counts as the first
    sta eng_tickwait
    lda eng_gpos
    inc a
    and #(GROOVE_SZ - 1)
    sta eng_gpos
    ; fall through: trigger the new row

; --- trigger phrase row eng_row on voice 0 ---------------------------------------
engine_trigger_row:
    ; X = phrase*64 + row*4
    rep #$30
.ACCU 16
    lda eng_phrase          ; lo=phrase, hi=eng_row... not adjacent; load parts
    and #$00FF
    xba                     ; *256
    lsr
    lsr                     ; *64
    sta tmp2
    lda eng_row
    and #$00FF
    asl
    asl                     ; *4
    clc
    adc tmp2
    tax
    sep #$20
.ACCU 8
    lda.l $7E0000 + SB_PHRASES,x
    beq @done               ; empty row
    cmp #NOTE_OFF
    bne @note
    ; key off voice 0
    lda #DSP_KOF
    ldy #$0001
    jsr apu_dsp_write
    lda #DSP_KOF
    ldy #$0000
    jmp apu_dsp_write
@note:
    dec a                   ; note byte 1..96 -> note index 0..95
    jmp audition_note       ; pitch + KON on voice 0 (M6 routes instruments)
@done:
    rts
