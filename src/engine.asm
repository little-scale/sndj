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

factory_instr_type: .DB 0, 0, 0, 0, 0, 2, 3, 1
factory_instr_smp:  .DB 0, 1, 2, 3, 4, 0, 0, 0

; command letter ids (1 = A ... 26 = Z)
.DEFINE CMDID_A 1
.DEFINE CMDID_B 2
.DEFINE CMDID_D 4
.DEFINE CMDID_G 7
.DEFINE CMDID_H 8
.DEFINE CMDID_K 11
.DEFINE CMDID_L 12
.DEFINE CMDID_P 16
.DEFINE CMDID_R 18
.DEFINE CMDID_T 20
.DEFINE CMDID_V 22
.DEFINE CMDID_X 24
.DEFINE CMDID_Y 25

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
    jsr waves_seed          ; factory single-cycle waves into the song block
    ; grooves: groove 0 = 6 ticks/row on all 16 steps
    ldx #$0000
    lda #6
@groove:
    sta.l $7E0000 + SB_GROOVES,x
    inx
    cpx #GROOVE_SZ
    bne @groove
    ; factory instruments 0-7 (matching the MIDI track defaults):
    ; 0-4 SMP on pool samples 0-4, 5 WAV bank 0, 6 NSE, 7 KIT 0
    ldx #$0000
@finstr:
    rep #$30
.ACCU 16
    txa
    asl
    asl
    asl
    asl
    tay
    sep #$20
.ACCU 8
    lda.w factory_instr_type,x
    phx
    rep #$30
.ACCU 16
    tyx
    sep #$20
.ACCU 8
    sta.l $7E0000 + SB_INSTR,x      ; type
    ply
    lda.w factory_instr_smp,y
    sta.l $7E0000 + SB_INSTR + 1,x  ; sample / bank / kit
    lda #$2F
    sta.l $7E0000 + SB_INSTR + 2,x  ; ADSR1 (bit7 forced on at apply)
    lda #$CA
    sta.l $7E0000 + SB_INSTR + 3,x  ; ADSR2
    lda #$50
    sta.l $7E0000 + SB_INSTR + 4,x  ; vol L
    sta.l $7E0000 + SB_INSTR + 5,x  ; vol R
    rep #$30
.ACCU 16
    tyx
    sep #$20
.ACCU 8
    inx
    cpx #$0008
    bne @finstr
    ; auto-populate 8-63 so every slot is playable out of the box:
    ; 8-47 SMP on pool samples 0-39, 48-55 WAV banks 0-7,
    ; 56-57 the two kits, 58 NSE, 59-63 SMP melodics 0-4 again
@autoinstr:
    txa
    sec
    sbc #$08
    sta es0 + 1             ; default: SMP, sample = slot - 8
    lda #$00
    sta es0
    txa
    cmp #$30
    bcc @ai_have            ; 8-47: SMP
    cmp #$38
    bcs @ai_not_wav
    sec
    sbc #$30
    sta es0 + 1
    lda #$02                ; 48-55: WAV bank 0-7
    sta es0
    bra @ai_have
@ai_not_wav:
    cmp #$3A
    bcs @ai_not_kit
    sec
    sbc #$38
    sta es0 + 1
    lda #$01                ; 56-57: KIT 0/1
    sta es0
    bra @ai_have
@ai_not_kit:
    bne @ai_tail
    lda #$03                ; 58: NSE
    sta es0
    lda #$00
    sta es0 + 1
    bra @ai_have
@ai_tail:
    sec
    sbc #$3B                ; 59-63: melodics 0-4
    sta es0 + 1
    lda #$00
    sta es0
@ai_have:
    phx
    rep #$30
.ACCU 16
    txa
    asl
    asl
    asl
    asl
    tax
    sep #$20
.ACCU 8
    lda es0
    sta.l $7E0000 + SB_INSTR,x      ; type
    lda es0 + 1
    sta.l $7E0000 + SB_INSTR + 1,x  ; sample / bank / kit
    lda #$2F
    sta.l $7E0000 + SB_INSTR + 2,x
    lda #$CA
    sta.l $7E0000 + SB_INSTR + 3,x
    lda #$50
    sta.l $7E0000 + SB_INSTR + 4,x
    sta.l $7E0000 + SB_INSTR + 5,x
    plx
    inx
    cpx #INSTR_COUNT
    beq @ai_done
    jmp @autoinstr
@ai_done:
    ; factory kits: kit 0 = 808 (pool 8-23), kit 1 = 909 (pool 24-39)
    ldx #$0000
@fkits:
    rep #$30
.ACCU 16
    txa
    asl
    asl                     ; slot record offset (kit*64 + slot*4 = x*4)
    tay
    sep #$20
.ACCU 8
    txa
    clc
    adc #$08                ; 808 starts at pool sample 8; kit 1 follows
    phx
    rep #$30
.ACCU 16
    tyx
    sep #$20
.ACCU 8
    sta.l $7E0000 + SB_KITS,x       ; sample
    lda #$F4
    sta.l $7E0000 + SB_KITS + 1,x   ; tune -12: factory drums are 16 kHz
    lda #$50
    sta.l $7E0000 + SB_KITS + 2,x   ; vol
    plx
    inx
    cpx #$0020                      ; 32 slots = kits 0 and 1
    bne @fkits
    ; header
    lda #$00
    sta.l $7E0000 + SB_HEADER + SH_GROOVE
    sta.l $7E0000 + SB_HEADER + SH_EDL
    sta.l $7E0000 + SB_HEADER + SH_EON
    sta.l $7E0000 + SB_HEADER + SH_FIR
    lda #$30
    sta.l $7E0000 + SB_HEADER + SH_EFB
    sta.l $7E0000 + SB_HEADER + SH_EVL
    sta.l $7E0000 + SB_HEADER + SH_EVR
    lda #$D7
    sta.l $7E0000 + SB_HEADER + SH_MAGIC
    rts

; --- start/stop ----------------------------------------------------------------
; A+B on SONG: play from the cursor row (genmddj C+B "play from here")
engine_play_from_cursor:
    lda song_cy
    bra engine_play_row

; Start playback from song row 0: every track loads its first chain.
engine_play:
    lda #$00
engine_play_row:
    sta es3 + 1
    ldx #$0000
@track:
    lda es3 + 1
    sta.w trk_songrow,x
    lda #$00
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
    ldx #$0000
@fx_reset:
    lda #$00
    sta.w trk_instr,x       ; instrument-less notes play instrument 0
    lda #$FF
    sta.w trk_instr_active,x
    sta.w trk_dly_cnt,x
    sta.w trk_kill_cnt,x
    sta.w trk_pending,x
    lda #$00
    sta.w trk_cmd,x
    sta.w trk_ret_per,x
    sta.w trk_sl_rate,x
    sta.w trk_arp_ph,x
    sta.w trk_vib_ph,x
    inx
    cpx #TRACKS
    bne @fx_reset
    lda.l $7E0000 + SB_HEADER + SH_GROOVE
    and #(GROOVE_COUNT - 1)
    sta eng_groove
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
    bne @not_phr
    jmp engine_play_phrase
@not_phr:
    cmp #SCREEN_CHAIN
    bne @not_chn
    jmp engine_play_chain
@not_chn:
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
    sta es3                 ; NOT tmp0: apu_wait_p0 clobbers it on DSP writes
    lda apu_tick
    sta eng_tick_last
@tickloop:
    jsr engine_tick
    dec es3
    bne @tickloop
@done:
    rts

; --- one engine tick ------------------------------------------------------------
engine_tick:
    stz kon_mask
    stz koff_mask
    lda eng_tickwait
    beq @row
    dec eng_tickwait
    bra @fx
@row:
    ; ticks for this row from the active groove
    lda eng_groove
    rep #$30
.ACCU 16
    and #$00FF
    asl
    asl
    asl
    asl
    sta es0
    lda eng_gpos
    and #$00FF
    clc
    adc es0
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

    ; advance + trigger every track
    ldx #$0000
@each:
    jsr track_row
    inx
    cpx #TRACKS
    bne @each
    lda trk_prow            ; mirror track 0 for playhead/checks
    sta eng_row
@fx:
    ; per-tick effects on every live track
    ldx #$0000
@fxloop:
    jsr track_fx
    inx
    cpx #TRACKS
    bne @fxloop
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

; --- advance to the next chain position for track X ------------------------------
; (LIVE-queued launch beats everything; standalone phrase loops; chain end
; walks the song grid or loops a standalone chain.) May halt the track.
track_chain_step:
    ; a LIVE-queued chain launches exactly here (quantised)
    lda.w trk_pending,x
    cmp #$FF
    beq @no_launch
    sta.w trk_chain,x
    lda #$FF
    sta.w trk_pending,x
    sta.w trk_songrow,x     ; behave as a standalone (looping) chain
    lda #$00
    sta.w trk_cpos,x
    jmp track_load_chain_entry
@no_launch:
    ; standalone phrase mode just loops
    lda.w trk_chain,x
    cmp #$FE
    beq @done
    lda.w trk_cpos,x
    inc a
    and #$0F
    sta.w trk_cpos,x
    bne @entry
    ; wrapped past entry 15: next song row
    lda.w trk_songrow,x
    inc a
    cmp #SONG_ROWS
    bcc @row_ok
    lda #$FF                ; end of grid: halt this track
    sta.w trk_phrase,x
    rts
@row_ok:
    sta.w trk_songrow,x
    jmp track_load_songrow
@entry:
    jmp track_load_chain_entry
@done:
    rts

; --- advance one row on track X and trigger its phrase cell --------------------
track_row:
    lda.w trk_phrase,x
    cmp #$FF
    bne @alive
    rts
@alive:
    lda #$04
    sta hop_guard
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
    jsr track_chain_step    ; wrapped: next chain entry / launch / loop
    lda.w trk_phrase,x
    cmp #$FF
    bne @trigger
    rts
@trigger:
    ; muted tracks advance but stay silent
    lda.w bit_for_track,x
    and trk_mute
    beq @not_muted
    rts
@not_muted:
    ; read the phrase cell (4 bytes): SB_PHRASES + phrase*64 + prow*4
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
    sta.w str_buf + 28      ; note byte
    lda.l $7E0000 + SB_PHRASES + 1,x
    sta.w str_buf + 29      ; instrument byte
    lda.l $7E0000 + SB_PHRASES + 2,x
    sta.w str_buf + 30      ; command id
    lda.l $7E0000 + SB_PHRASES + 3,x
    sta.w str_buf + 31      ; command value
    plx
    ; H hops NOW: this row tick plays row 0 of the next chain entry
    ; (hop_guard caps chained hops so a hop cycle can't wedge the tick)
    lda.w str_buf + 30
    cmp #CMDID_H
    bne @no_hop
    lda hop_guard
    beq @no_hop             ; guard exhausted: treat as a plain row
    dec hop_guard
    jsr track_chain_step
    lda.w trk_phrase,x
    cmp #$FF
    bne @hopped
    rts
@hopped:
    lda #$00
    sta.w trk_prow,x
    jmp @trigger
@no_hop:
    ; latch row command + per-row effect resets
    lda.w str_buf + 30
    sta.w trk_cmd,x
    lda.w str_buf + 31
    sta.w trk_cval,x
    lda #$FF
    sta.w trk_dly_cnt,x     ; pending delay is per-row
    lda #$00
    sta.w trk_arp_ph,x
    sta.w trk_ret_per,x     ; retrig re-arms only via R
    sta.w str_buf + 27      ; flags: bit0 = trigger consumed by a command
    ; instrument column selects the track's instrument (empty = keep)
    lda.w str_buf + 29
    cmp #INSTR_NONE
    beq @no_new_instr
    sta.w trk_instr,x
@no_new_instr:
    jsr row_cmd_pre         ; G/T/P/K/R immediates; D/L may consume the note
    ; note handling
    lda.w str_buf + 28
    beq @after_note         ; empty
    cmp #NOTE_OFF
    bne @maybe_note
    lda.w bit_for_track,x
    ora koff_mask
    sta koff_mask
    bra @after_note
@maybe_note:
    lda.w str_buf + 27
    bne @after_note         ; D or L consumed the trigger
    lda.w str_buf + 28
    jsr track_trigger_note
@after_note:
    jsr row_cmd_post
@done:
    rts

; --- trigger raw note byte A on track X (transpose, instrument, pitch, KON) ----
track_trigger_note:
    sta.w str_buf + 26
    stz trig_type           ; instrument-less triggers keep plain pitch
    txa
    sta trig_voice
    lda.w trk_instr,x
    cmp #INSTR_NONE
    beq @no_apply
    phx
    jsr apply_instrument
    plx
@no_apply:
    lda.w str_buf + 26
    clc
    adc.w trk_tsp,x
    dec a                   ; note byte 1..96 -> index 0..95
    cmp #NOTE_MAX
    bcc @in_range
    lda #NOTE_MAX - 1
@in_range:
    sta trig_note
    sta.w trk_note,x
    ; type-aware pitch: NSE sets the global noise clock instead; WAV plays
    ; a 32-sample loop, two octaves above the sampler's reference
    lda trig_type
    cmp #$01
    bne @not_kit
    phx
    jsr kit_trigger         ; full slot lookup; clears C when nothing to play
    plx
    bcs @kit_played
    ; empty slot: no KON for this voice
    rts
@kit_played:
    bra @pitched
@not_kit:
    cmp #$03
    bne @not_nse
    lda trig_note
    and #$1F
    sta eng_noise
    tay
    lda #DSP_FLG
    phx
    jsr apu_dsp_write
    plx
    bra @pitched
@not_nse:
    cmp #$02
    bne @plain_pitch
    lda trig_note
    phx
    jsr note_pitch_calc_only
    rep #$20
.ACCU 16
    lsr last_pitch
    lsr last_pitch          ; -2 octaves for the short loop
    sep #$20
.ACCU 8
    jsr voice_pitch_write
    plx
    bra @pitched
@plain_pitch:
    lda trig_note
    phx
    jsr note_pitch
    plx
@pitched:
    lda last_pitch
    sta.w trk_pitch_lo,x
    lda last_pitch + 1
    sta.w trk_pitch_hi,x
    lda #$00
    sta.w trk_sl_rate,x     ; a fresh note ends any slide
    lda.w bit_for_track,x
    ora kon_mask
    sta kon_mask
    jmp grp_fanout

; --- post-trigger commands (X = track): P overrides the instrument volume ------
row_cmd_post:
    lda.w trk_cmd,x
    cmp #CMDID_P
    beq @pan
    rts
@pan:
    ; pan: L = (255-val)>>1, R = val>>1
    lda.w trk_cval,x
    sta es0
    lda #$FF
    sec
    sbc es0
    lsr
    tay
    txa
    asl
    asl
    asl
    asl
    ora #DSP_V0VOLL
    phx
    jsr apu_dsp_write
    plx
    lda es0
    lsr
    tay
    txa
    asl
    asl
    asl
    asl
    ora #DSP_V0VOLR
    phx
    jsr apu_dsp_write
    plx
    rts

; --- row command pre-trigger dispatch (X = track) -------------------------------
row_cmd_pre:
    lda.w trk_cmd,x
    bne @dispatch
    rts
@dispatch:
    cmp #CMDID_G
    bne @not_g
    lda.w trk_cval,x
    and #(GROOVE_COUNT - 1)
    sta eng_groove
    rts
@not_g:
    cmp #CMDID_B
    bne @not_b
    ; B: wave bank select for this voice (SRCN = 56 + bank)
    lda.w trk_cval,x
    and #$07
    clc
    adc #56
    tay
    txa
    asl
    asl
    asl
    asl
    ora #DSP_V0SRCN
    phx
    jsr apu_dsp_write
    plx
    ; the voice now plays a different source than its instrument claims
    lda #$FF
    sta.w trk_instr_active,x
    rts
@not_b:
    cmp #CMDID_T
    bne @not_t
    lda.w trk_cval,x
    phx
    jsr apu_set_tempo
    plx
    rts
@not_t:
    cmp #CMDID_X
    bne @not_x
    ; X: echo send on/off for this voice (val 0 = off, else on)
    lda.w trk_cval,x
    beq @eon_off
    lda.w bit_for_track,x
    ora eng_eon
    bra @eon_wr
@eon_off:
    lda.w bit_for_track,x
    eor #$FF
    and eng_eon
@eon_wr:
    sta eng_eon
    tay
    lda #DSP_EON
    phx
    jsr apu_dsp_write
    plx
    rts
@not_x:
    cmp #CMDID_Y
    bne @not_y
    ; Y: FIR preset select (global)
    lda.w trk_cval,x
    and #$07
    sta.l $7E0000 + SB_HEADER + SH_FIR
    phx
    jsr apu_fir_preset
    plx
    rts
@not_y:
    cmp #CMDID_K
    bne @not_k
    lda.w trk_cval,x
    inc a                   ; val 0 kills on this very tick
    sta.w trk_kill_cnt,x
    rts
@not_k:
    cmp #CMDID_R
    bne @not_r
    lda.w trk_cval,x
    and #$0F
    bne @r_ok
    lda #$01
@r_ok:
    sta.w trk_ret_per,x
    sta.w trk_ret_cnt,x
    rts
@not_r:
    cmp #CMDID_D
    bne @not_d
    lda.w str_buf + 28
    beq @out                ; no note to delay
    cmp #NOTE_OFF
    beq @out
    lda.w trk_cval,x
    beq @out                ; D00 = no delay
    sta.w trk_dly_cnt,x
    lda.w str_buf + 28
    sta.w trk_dly_note,x
    lda #$01
    sta.w str_buf + 27      ; consume the trigger
    rts
@not_d:
    cmp #CMDID_L
    beq @is_l
    rts
@is_l:
    ; slide to the row's note without retriggering
    lda.w str_buf + 28
    beq @out
    cmp #NOTE_OFF
    beq @out
    clc
    adc.w trk_tsp,x
    dec a
    cmp #NOTE_MAX
    bcc @l_ok
    lda #NOTE_MAX - 1
@l_ok:
    sta.w trk_sl_note,x
    pha
    phx
    jsr track_tune_load
    plx
    pla
    phx
    jsr note_pitch_calc_only
    plx
    lda last_pitch
    sta.w trk_sl_tlo,x
    lda last_pitch + 1
    sta.w trk_sl_thi,x
    lda.w trk_cval,x
    bne @l_rate
    lda #$01
@l_rate:
    sta.w trk_sl_rate,x
    lda #$01
    sta.w str_buf + 27      ; legato: no retrigger
@out:
    rts
@halt:
    lda #$FF
    sta.w trk_phrase,x
    rts

; --- GRP: instrument on track X drives voices X+1..X+span with offsets --------
; trig_note = the (transposed) base note index. Preserves X.
grp_fanout:
    lda.w trk_instr,x
    cmp #INSTR_NONE
    bne @has
    rts
@has:
    phx
    sta trig_id
    txa
    sta grp_track
    rep #$30
.ACCU 16
    lda trig_id
    and #$00FF
    asl
    asl
    asl
    asl
    tax
    sep #$20
.ACCU 8
    lda.l $7E0000 + SB_INSTR + 8,x  ; span
    and #$03
    sta grp_span
    beq @out
    lda #$01
    sta grp_m
@member:
    lda grp_track
    clc
    adc grp_m
    cmp #TRACKS
    bcs @out
    sta trig_voice
    ; member offset = rec[8 + m]
    rep #$30
.ACCU 16
    lda trig_id
    and #$00FF
    asl
    asl
    asl
    asl
    sta tmp2
    lda grp_m
    and #$00FF
    clc
    adc tmp2
    tax
    sep #$20
.ACCU 8
    lda.l $7E0000 + SB_INSTR + 8,x
    clc
    adc trig_note
    cmp #NOTE_MAX
    bcc @m_ok
    lda #NOTE_MAX - 1
@m_ok:
    pha
    lda trig_id
    jsr apply_instrument
    pla
    jsr note_pitch
    lda trig_voice
    rep #$30
.ACCU 16
    and #$00FF
    tax
    sep #$20
.ACCU 8
    lda.w bit_for_track,x
    ora kon_mask
    sta kon_mask
    inc grp_m
    lda grp_m
    cmp grp_span
    bcc @member
    beq @member
@out:
    plx
    rts

bit_for_track:
    .DB $01, $02, $04, $08, $10, $20, $40, $80

; --- KIT trigger: LSDJ-style 16-slot kits ----------------------------------------
; Instrument rec[1] low nibble = kit id; slot = note % 16. A slot is
; sample + tune (signed semitones around native) + vol. Returns carry SET
; when a note was played, CLEAR for an empty (vol 0) slot. Uses trig_id /
; trig_note / trig_voice; clobbers X.
; tune context for track X's active instrument — fx paths (slide, arp)
; recompute pitch without a fresh apply_instrument, and trig_semis/fine
; are global, so another track's trigger may have replaced them.
track_tune_load:
    lda.w trk_instr,x
    cmp #$FF
    beq @none
    sta trig_id
    jmp trig_tune_load
@none:
    stz trig_semis
    stz trig_fine
    rts

kit_trigger:
    ; kit id from the instrument record
    lda trig_id
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
    lda.l $7E0000 + SB_INSTR + 1,x
    and #$0F
    sta es0                 ; kit id
    lda trig_note
    and #$0F
    sta es0 + 1             ; slot
    ; record = SB_KITS + kit*64 + slot*4
    rep #$30
.ACCU 16
    lda es0
    and #$00FF
    xba
    lsr
    lsr                     ; * 64
    sta es1
    lda es0 + 1
    and #$00FF
    asl
    asl                     ; * 4
    clc
    adc es1
    tax
    sep #$20
.ACCU 8
    lda.l $7E0000 + SB_KITS + 2,x   ; vol
    bne @has
    clc
    rts
@has:
    sta es1                 ; vol
    lda.l $7E0000 + SB_KITS + 1,x   ; tune (signed semitones)
    sta es1 + 1
    lda.l $7E0000 + SB_KITS,x       ; sample: pool default tune applies
    and #$3F
    pha
    stz np_fine
    jsr trig_tune_pool
    pla
    lda.l $7E0000 + SB_KITS,x       ; sample -> resident SRCN
    and #$3F
    rep #$30
.ACCU 16
    and #$00FF
    tax
    sep #$20
.ACCU 8
    lda.w pool_map,x
    tay
    lda trig_voice
    asl
    asl
    asl
    asl
    ora #DSP_V0SRCN
    jsr apu_dsp_write
    ; per-slot volume overrides the instrument's
    lda es1
    tay
    lda trig_voice
    asl
    asl
    asl
    asl
    ora #DSP_V0VOLL
    jsr apu_dsp_write
    lda es1
    tay
    lda trig_voice
    asl
    asl
    asl
    asl
    ora #DSP_V0VOLR
    jsr apu_dsp_write
    ; pitch: native ($1000 = note 60) +/- tune
    lda es1 + 1
    clc
    adc #60
    cmp #NOTE_MAX
    bcc @tuned
    lda #60                 ; wild tunes snap back to native
@tuned:
    jsr note_pitch_calc_only
    jsr voice_pitch_write
    ; SRCN/vol no longer match the instrument record on this voice
    lda trig_voice
    rep #$30
.ACCU 16
    and #$00FF
    tax
    sep #$20
.ACCU 8
    lda #$FF
    sta.w trk_instr_active,x
    sec
    rts

; --- per-tick effects on track X (delay, kill, retrig, slide, arp, vibrato) ----
track_fx:
    lda.w trk_phrase,x
    cmp #$FF
    bne @alive
    rts
@alive:
    ; D: deferred trigger
    lda.w trk_dly_cnt,x
    cmp #$FF
    beq @no_dly
    dec a
    sta.w trk_dly_cnt,x
    bne @no_dly
    lda #$FF
    sta.w trk_dly_cnt,x
    lda.w trk_dly_note,x
    jsr track_trigger_note
@no_dly:
    ; K: deferred key-off
    lda.w trk_kill_cnt,x
    cmp #$FF
    beq @no_kill
    dec a
    sta.w trk_kill_cnt,x
    bne @no_kill
    lda #$FF
    sta.w trk_kill_cnt,x
    lda.w bit_for_track,x
    ora koff_mask
    sta koff_mask
@no_kill:
    ; R: retrigger
    lda.w trk_ret_per,x
    beq @no_ret
    lda.w trk_ret_cnt,x
    dec a
    sta.w trk_ret_cnt,x
    bne @no_ret
    lda.w trk_ret_per,x
    sta.w trk_ret_cnt,x
    lda.w bit_for_track,x
    ora kon_mask
    sta kon_mask
@no_ret:
    ; L: slide
    lda.w trk_sl_rate,x
    beq @no_slide
    jsr fx_slide
@no_slide:
    ; A / V retune the voice every tick
    lda.w trk_cmd,x
    cmp #CMDID_A
    bne @not_arp
    jmp fx_arp
@not_arp:
    cmp #CMDID_V
    bne @fx_done
    jmp fx_vib
@fx_done:
    rts

; --- L: move trk_pitch toward the target by rate*4 per tick --------------------
fx_slide:
    txa
    sta trig_voice
    lda.w trk_sl_rate,x
    sta es0
    stz es0 + 1
    lda.w trk_pitch_lo,x
    sta es1
    lda.w trk_pitch_hi,x
    sta es1 + 1
    lda.w trk_sl_tlo,x
    sta es2
    lda.w trk_sl_thi,x
    sta es2 + 1
    rep #$20
.ACCU 16
    lda es0
    asl
    asl                     ; step = rate * 4
    sta es0
    lda es1
    cmp es2
    beq @reached16
    bcc @up
    ; sliding down
    sec
    sbc es0
    bcc @snap               ; underflow: snap to target
    cmp es2
    bcc @snap
    bra @store16
@up:
    clc
    adc es0
    bcs @snap
    cmp es2
    bcs @snap
    bra @store16
@snap:
    lda es2
@store16:
    sta last_pitch
    cmp es2
    sep #$20
.ACCU 8
    bne @still_moving
    ; target reached: stop sliding, adopt the target note as the new base
    lda #$00
    sta.w trk_sl_rate,x
    lda.w trk_sl_note,x
    sta.w trk_note,x
@still_moving:
    lda last_pitch
    sta.w trk_pitch_lo,x
    lda last_pitch + 1
    sta.w trk_pitch_hi,x
    phx
    jsr voice_pitch_write
    plx
    rts
@reached16:
    sep #$20
.ACCU 8
    lda #$00
    sta.w trk_sl_rate,x
    rts

; --- A xy: cycle root / +x / +y each tick ---------------------------------------
fx_arp:
    txa
    sta trig_voice
    lda.w trk_arp_ph,x
    inc a
    cmp #3
    bcc @ph_ok
    lda #$00
@ph_ok:
    sta.w trk_arp_ph,x
    beq @root
    cmp #1
    beq @hi_nib
    lda.w trk_cval,x
    and #$0F
    bra @add
@hi_nib:
    lda.w trk_cval,x
    lsr
    lsr
    lsr
    lsr
    bra @add
@root:
    lda #$00
@add:
    clc
    adc.w trk_note,x
    cmp #NOTE_MAX
    bcc @n_ok
    lda #NOTE_MAX - 1
@n_ok:
    pha
    phx
    jsr track_tune_load
    plx
    pla
    phx
    jsr note_pitch          ; calc + write (base pitch untouched)
    plx
    rts

; --- V xy: triangle vibrato around the base pitch (speed x, depth y) -----------
fx_vib:
    txa
    sta trig_voice
    ; phase += speed
    lda.w trk_cval,x
    lsr
    lsr
    lsr
    lsr
    clc
    adc.w trk_vib_ph,x
    sta.w trk_vib_ph,x
    ; triangle 0..15 from phase bits
    and #$1F
    cmp #$10
    bcc @rising
    eor #$1F                ; falling half: 31-t
@rising:
    sec
    sbc #$08                ; centre: -8..7
    sta es0                 ; signed offset
    ; |offset| * depth -> es1 (max 8*15 = 120)
    bpl @pos
    eor #$FF
    inc a
@pos:
    sta es0 + 1             ; magnitude
    lda.w trk_cval,x
    and #$0F
    sta es1 + 1             ; depth counter
    stz es1
    lda es1 + 1
    beq @apply
@mul:
    lda es1
    clc
    adc es0 + 1
    sta es1
    dec es1 + 1
    bne @mul
@apply:
    ; pitch = base +/- (product << 2)
    lda.w trk_pitch_lo,x
    sta last_pitch
    lda.w trk_pitch_hi,x
    sta last_pitch + 1
    rep #$20
.ACCU 16
    lda es1
    and #$00FF
    asl
    asl
    sta es1
    lda es0
    and #$0080              ; sign of the centred offset
    beq @add16
    lda last_pitch
    sec
    sbc es1
    bra @wr16
@add16:
    lda last_pitch
    clc
    adc es1
@wr16:
    sta last_pitch
    sep #$20
.ACCU 8
    phx
    jsr voice_pitch_write
    plx
    rts
