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

str_defname: .DB "SONG    "

; command letter ids (1 = A ... 26 = Z)
.DEFINE CMDID_A 1
.DEFINE CMDID_B 2
.DEFINE CMDID_C 3
.DEFINE CMDID_D 4
.DEFINE CMDID_E 5
.DEFINE CMDID_F 6
.DEFINE CMDID_G 7
.DEFINE CMDID_H 8
.DEFINE CMDID_I 9
.DEFINE CMDID_J 10
.DEFINE CMDID_K 11
.DEFINE CMDID_L 12
.DEFINE CMDID_M 13
.DEFINE CMDID_N 14
.DEFINE CMDID_Q 17
.DEFINE CMDID_P 16
.DEFINE CMDID_R 18
.DEFINE CMDID_S 19
.DEFINE CMDID_T 20
.DEFINE CMDID_U 21
.DEFINE CMDID_V 22
.DEFINE CMDID_X 24
.DEFINE CMDID_Y 25
.DEFINE CMDID_Z 26

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
    ; factory instruments 0-7 (the MIDI channel map): 0-6 pitched SMP
    ; on pool samples 0-6, 7 = KIT 0 — the whole factory boot set
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
    lda #$FF
    sta.l $7E0000 + SB_INSTR + 12,x ; TBL: no table
    lda #$01
    sta.l $7E0000 + SB_INSTR + 13,x ; TBS: per tick
    rep #$30
.ACCU 16
    tyx
    sep #$20
.ACCU 8
    inx
    cpx #$0008
    bne @finstr
    ; 8-63: SMP on sample 0 — every slot plays out of the box, but the
    ; factory boot set stays 0-7: residency follows REFERENCES, so a
    ; sample only costs ARAM once an instrument or kit slot points at
    ; it (edits rebuild the resident set on the spot)
@autoinstr:
    lda #$00
    sta es0                 ; type SMP
    sta es0 + 1             ; sample 0
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
    lda #$FF
    sta.l $7E0000 + SB_INSTR + 12,x ; TBL: no table
    lda #$01
    sta.l $7E0000 + SB_INSTR + 13,x ; TBS: per tick
    plx
    inx
    cpx #INSTR_COUNT
    beq @ai_done
    jmp @autoinstr
@ai_done:
    ; factory kits: the marker-wrapped SNKIT0 block, copied verbatim
    ; (16 kits x 16 slots x 4 bytes; patcher.html edits the ROM block)
    ldx #$0000
@fk_copy:
    lda.l factory_kits,x
    sta.l $7E0000 + SB_KITS,x
    inx
    cpx #$0400
    bne @fk_copy
    ; header: name "SONG    " then settings
    ldx #$0000
@sname:
    lda.w str_defname,x
    sta.l $7E0000 + SB_HEADER + SH_NAME,x
    inx
    cpx #$0008
    bne @sname
    lda #150
    sta.l $7E0000 + SB_HEADER + SH_BPM
    ; FIR taps seed from preset 0 (FLAT)
    ldx #$0000
@ftaps:
    lda.w fir_presets,x
    sta.l $7E0000 + SB_HEADER + SH_FIRTAPS,x
    inx
    cpx #$0008
    bne @ftaps
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
    lda #16
    sta walk_guard          ; a real phrase resets the empty-walk budget
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
    ; end of chain: next song row, or loop back to the top of this
    ; track's contiguous block (same rule as the entry-15 wrap).
    ; The guard stops a block whose chains never yield a phrase from
    ; recursing forever (it decays here, resets on any real phrase).
    dec walk_guard
    beq @halt
    lda.w trk_songrow,x
    inc a
    cmp #SONG_ROWS
    bcs @block_top
    pha
    jsr track_song_cell
    cmp #$FF
    beq @next_empty
    pla
    sta.w trk_songrow,x
    jmp track_load_songrow
@next_empty:
    pla
@block_top:
    lda.w trk_songrow,x
@scan:
    cmp #$00
    beq @top
    dec a
    pha
    jsr track_song_cell
    cmp #$FF
    beq @gap
    pla
    bra @scan
@gap:
    pla
    inc a
@top:
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

; NEW as an action: wipe + reseed, then rebuild everything downstream
; (used by PROJECT's NEW and FILES' load-on-empty)
song_renew:
    jsr engine_stop
    jsr song_init
    jsr wave_sync_all
    jsr residency_build
    jmp apu_echo_apply

engine_go:
    jsr sync_play_start     ; port config + slave arming per opt_sync
    ldx #$0000
@fx_reset:
    lda #$00
    sta.w trk_instr,x       ; instrument-less notes play instrument 0
    lda #$FF
    sta.w trk_instr_active,x
    sta.w trk_dly_cnt,x
    sta.w trk_kill_cnt,x
    sta.w trk_pending,x
    sta.w trk_tbl,x
    lda #$00
    sta.w trk_tbl_spd,x
    sta.w trk_tbl_cnt,x
    lda #$FF
    lda #$00
    sta.w trk_cmd,x
    sta.w trk_ret_per,x
    sta.w trk_sl_rate,x
    sta.w trk_arp_ph,x
    sta.w trk_vib_ph,x
    sta.w trk_vib,x
    sta.w trk_trm,x
    sta.w trk_trm_ph,x
    sta.w trk_voll,x
    sta.w trk_volr,x
    sta.w trk_fine,x
    sta.w trk_chord,x
    sta.w trk_playcnt,x
    inx
    cpx #TRACKS
    bne @fx_reset
    stz eng_pmon
    lda.l $7E0000 + SB_HEADER + SH_GROOVE
    and #(GROOVE_COUNT - 1)
    sta eng_groove
    ; the song's tick BPM drives the APU timer (0 -> the 150 default)
    lda.l $7E0000 + SB_HEADER + SH_BPM
    bne +
    lda #150
+
    jsr apu_set_tempo
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
    jsr apu_dsp_write
    jmp sync_stop

; Start: the transport — stop if playing, else play the whole song,
; whatever screen you're on (contextual play lives on A+B)
engine_toggle:
    lda eng_playing
    beq @start
    jmp engine_stop
@start:
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
    ; SYNC IN/IN24: the wire drives row advance (groove ignored); fx and
    ; the KON/KOF ship still run per APU tick
    lda opt_sync
    cmp #SYNC_IN
    beq @slv_tramp
    cmp #SYNC_IN24
    bne @master
@slv_tramp:
    jmp engine_tick_slave
@master:
    lda eng_tickwait
    beq @row
    dec eng_tickwait
    jmp engine_tick_fx
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
engine_tick_row:
    ldx #$0000
@each:
    jsr track_row
    inx
    cpx #TRACKS
    bne @each
    lda trk_prow            ; mirror track 0 for playhead/checks
    sta eng_row
@fx:
engine_tick_fx:
    ; per-tick effects on every live track
    ldx #$0000
@fxloop:
    jsr track_fx
    jsr track_table
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
    ; PULSE master: drive the analog clock line every tick
    lda opt_sync
    cmp #SYNC_PULSE
    bne @no_pulse
    jsr sync_pulse_tick
@no_pulse:
    rts

; --- SYNC IN/IN24 row gate: external clocks decide the row, one per tick ---------
; (excess clocks carry in sync_gctr and catch up on following ticks)
engine_tick_slave:
    jsr sync_in_poll
    lda sync_wait
    bne @hold                ; armed: row 0 stays silent until the first clock
    lda opt_sync
    cmp #SYNC_IN24
    beq @div6
    lda sync_gctr            ; IN: one row per clock
    beq @hold
    dec a
    sta sync_gctr
    bra @go
@div6:
    lda sync_gctr            ; IN24: 24 PPQN, six clocks per row
    cmp #$06
    bcc @hold
    sbc #$06
    sta sync_gctr
@go:
    jmp engine_tick_row
@hold:
    jmp engine_tick_fx

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
    ; wrapped past entry 15: next song row, or loop back to the top of
    ; this track's contiguous block when the block (or the grid) ends
    lda.w trk_songrow,x
    inc a
    cmp #SONG_ROWS
    bcs @block_top
    pha
    jsr track_song_cell     ; peek the next row's cell
    cmp #$FF
    beq @next_empty
    pla
    sta.w trk_songrow,x
    jmp track_load_songrow
@next_empty:
    pla
@block_top:
    ; scan up from the current row to the first row of the block
    lda.w trk_songrow,x
@scan:
    cmp #$00
    beq @top
    dec a
    pha
    jsr track_song_cell
    cmp #$FF
    beq @gap
    pla
    bra @scan
@gap:
    pla
    inc a                   ; the row just below the gap
@top:
    sta.w trk_songrow,x
    jmp track_load_songrow
@entry:
    jmp track_load_chain_entry
@done:
    rts

; A = song row -> A = that row's chain cell on track X (X preserved)
track_song_cell:
    sta tmp2
    phx
    rep #$30
.ACCU 16
    txa
    xba
    lsr                     ; track * 128
    sta tmp0
    lda tmp2
    and #$00FF
    clc
    adc tmp0
    tax
    sep #$20
.ACCU 8
    lda.l $7E0000 + SB_SONG,x
    plx
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
    lda.w trk_playcnt,x     ; one more pass done (I/J schedules)
    inc a
    sta.w trk_playcnt,x
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
    ; the instrument's table: TBL >= 32 (shown --) = none; TBS 0 =
    ; note-sync (each trigger advances one row, position persists),
    ; TBS n = a row every n ticks from the top
    lda trig_id
    cmp #INSTR_NONE
    bne @have_id
    jmp @no_tbl
@have_id:
    phx
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
    lda.l $7E0000 + SB_INSTR + 13,x
    and #$0F
    sta es2                 ; TBS
    lda.l $7E0000 + SB_INSTR + 12,x
    sta es2 + 1             ; TBL
    lda.l $7E0000 + SB_INSTR + 14,x
    sta tg_vibtrm           ; VIB
    lda.l $7E0000 + SB_INSTR + 15,x
    sta tg_vibtrm + 1       ; TRM
    plx
    ; the instrument's VIB/TRM seed this note's LFOs (a row V overrides
    ; vibrato after the trigger, for this note only)
    lda tg_vibtrm
    sta.w trk_vib,x
    lda tg_vibtrm + 1
    sta.w trk_trm,x
    lda #$00
    sta.w trk_vib_ph,x
    sta.w trk_trm_ph,x
    lda es2 + 1
    cmp #$20
    bcc @tbl_on
    lda #$FF                ; nil: no table on this voice
    sta.w trk_tbl,x
    bra @no_tbl
@tbl_on:
    lda es2
    sta.w trk_tbl_spd,x
    bne @tick_mode
    ; note-sync: keep the row when re-triggering the same table
    lda es2 + 1
    cmp.w trk_tbl,x
    beq @same
    lda #$00
    sta.w trk_tbl_row,x
@same:
    lda es2 + 1
    sta.w trk_tbl,x
    lda #$01
    sta.w trk_tbl_cnt,x     ; one pending step for this note
    bra @no_tbl
@tick_mode:
    lda es2 + 1
    sta.w trk_tbl,x
    lda #$00
    sta.w trk_tbl_row,x
    lda #$01
    sta.w trk_tbl_cnt,x     ; row 0 executes on the trigger tick
@no_tbl:
    ; F command: per-track fine tune folds into the trigger tune context
    lda.w trk_fine,x
    clc
    adc trig_fine
    sta trig_fine
    lda.w str_buf + 26
    clc
    adc.w trk_tsp,x
    clc
    adc.l $7E0000 + SB_HEADER + SH_TRANSPOSE
    dec a                   ; note byte 1..96 -> index 0..95
    cmp #NOTE_MAX
    bcc @in_range
    lda #NOTE_MAX - 1
@in_range:
    sta trig_note
    sta.w trk_note,x
    ; type-aware pitch: NSE sets the global noise clock instead; WAV plays
    ; a 32-sample loop, tuned via the trig tune context + one LSR
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
    lsr last_pitch          ; -1 octave; the tune context does the rest
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

; --- post-trigger commands (X = track): X/P retarget the voice's live
; volume, V overrides the instrument VIB (all last until the voice
; reloads its instrument / the next trigger) ------------------------------------
row_cmd_post:
    lda.w trk_cmd,x
    cmp #CMDID_V
    bne @not_v
    lda.w trk_cval,x
    sta.w trk_vib,x
    rts
@not_v:
    cmp #CMDID_X
    bne @not_x
    ; X: volume/accent — this voice's level, both sides (the family
    ; accent command, as in genmddj)
    lda.w trk_cval,x
    and #$7F
    sta.w trk_voll,x
    sta.w trk_volr,x
    jmp track_vol_write
@not_x:
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
    sta.w trk_voll,x
    lda es0
    lsr
    sta.w trk_volr,x
    ; fall through to the writer

; write trk_voll/volr to voice X's DSP volume registers; preserves X
track_vol_write:
    lda.w trk_voll,x
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
    lda.w trk_volr,x
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
    cmp #CMDID_E
    bne @not_e
    ; E: echo send on/off for this voice (val 0 = off, else on)
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
@not_e:
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
    cmp #CMDID_N
    bne @not_n
    ; N: global noise clock (like the NSE trigger path)
    lda.w trk_cval,x
    and #$1F
    sta eng_noise
    tay
    lda #DSP_FLG
    phx
    jsr apu_dsp_write
    plx
    rts
@not_n:
    cmp #CMDID_C
    bne @not_c
    ; C xy: chord override — fan the next triggers out to +x and +y
    ; semitones on the two voices to the right (works on any SMP/WAV
    ; instrument, GRP or not); C00 back to the instrument's own GRP
    lda.w trk_cval,x
    sta.w trk_chord,x
    rts
@not_c:
    cmp #CMDID_I
    bne @not_i
    ; I: 8-bit play-count mask — the row's note fires only on set bits
    ; ($FF always, $55/$AA alternate passes, $0F the first four of 8)
    lda.w trk_cval,x
    sta es0
    lda.w trk_playcnt,x
    and #$07
    beq @i_test
    sta es0 + 1
@i_sh:
    lsr es0
    dec es0 + 1
    bne @i_sh
@i_test:
    lda es0
    and #$01
    bne @i_play
    lda #$00
    sta.w str_buf + 28      ; drop the note this pass
@i_play:
    rts
@not_i:
    cmp #CMDID_J
    bne @not_j
    ; J xy: on passes picked by 4-bit mask x, transpose the row's note
    ; by signed nibble y (kits: swaps the pad)
    lda.w str_buf + 28
    beq @j_out
    cmp #NOTE_OFF
    beq @j_out
    lda.w trk_cval,x
    lsr
    lsr
    lsr
    lsr
    sta es0
    lda.w trk_playcnt,x
    and #$03
    beq @j_test
    sta es0 + 1
@j_sh:
    lsr es0
    dec es0 + 1
    bne @j_sh
@j_test:
    lda es0
    and #$01
    beq @j_out
    lda.w trk_cval,x
    and #$0F
    cmp #$08
    bcc @j_add
    ora #$F0                ; y is signed
@j_add:
    clc
    adc.w str_buf + 28
    beq @j_out              ; clamp: never underflow to empty
    cmp #NOTE_MAX + 1
    bcs @j_out
    sta.w str_buf + 28
@j_out:
    rts
@not_j:
    cmp #CMDID_M
    bne @not_m
    ; M: master volume (both channels)
    lda.w trk_cval,x
    and #$7F
    tay
    lda #DSP_MVOLL
    phx
    jsr apu_dsp_write
    plx
    lda.w trk_cval,x
    and #$7F
    tay
    lda #DSP_MVOLR
    phx
    jsr apu_dsp_write
    plx
    rts
@not_m:
    cmp #CMDID_F
    bne @not_f
    ; F: per-track fine tune (signed 1/256 semitone, applied at trigger)
    lda.w trk_cval,x
    sta.w trk_fine,x
    rts
@not_f:
    cmp #CMDID_S
    bne @not_s
    ; S xy: sweep up at rate x, or down at rate y (rides the slide fx)
    lda.w trk_note,x
    sta.w trk_sl_note,x
    lda.w trk_cval,x
    and #$F0
    beq @s_down
    lsr
    lsr
    lsr
    lsr
    sta.w trk_sl_rate,x
    lda #$FF
    sta.w trk_sl_tlo,x
    lda #$3F
    sta.w trk_sl_thi,x
    rts
@s_down:
    lda.w trk_cval,x
    and #$0F
    sta.w trk_sl_rate,x
    lda #$00
    sta.w trk_sl_tlo,x
    sta.w trk_sl_thi,x
    rts
@not_s:
    cmp #CMDID_Q
    bne @not_q
    jmp cmd_gain
@not_q:
    cmp #CMDID_U
    bne @not_u
    jmp cmd_surround
@not_u:
    cmp #CMDID_Z
    bne @not_z
    ; Z: pitch-mod by the left neighbour (voice 0's bit is inert)
    lda.w trk_cval,x
    beq @z_off
    lda.w bit_for_track,x
    ora eng_pmon
    bra @z_wr
@z_off:
    lda.w bit_for_track,x
    eor #$FF
    and eng_pmon
@z_wr:
    sta eng_pmon
    tay
    lda #DSP_PMON
    phx
    jsr apu_dsp_write
    plx
    rts
@not_z:
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

; --- Q xy: GAIN override — mode x (0 = back to ADSR, 1 direct, 2 lin dec,
; 3 exp dec, 4 lin inc, 5 bent inc), value/rate y ------------------------------
cmd_gain:
    lda.w trk_instr,x
    cmp #$FF
    beq @out
    ; the instrument's ADSR1 byte -> es0
    phx
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
    lda.l $7E0000 + SB_INSTR + 2,x
    sta es0
    plx
    lda.w trk_cval,x
    and #$F0
    bne @gain
    ; Q00: ADSR again (bit 7 on)
    lda es0
    ora #$80
    tay
    txa
    asl
    asl
    asl
    asl
    ora #DSP_V0ADSR1
    phx
    jsr apu_dsp_write
    plx
    rts
@gain:
    lsr
    lsr
    lsr
    lsr
    cmp #$01
    bne @ramp
    ; direct level: 0vvvvvvv from y<<3
    lda.w trk_cval,x
    and #$0F
    asl
    asl
    asl
    bra @g_wr
@ramp:
    ; modes 2-5 -> $80/$A0/$C0/$E0 | rate y
    dec a
    dec a
    and #$03
    asl                     ; 0,2,4,6
    asl
    asl
    asl
    asl                     ; <<5: $00,$40? no: (mode-2)<<5 = $00,$20,$40,$60
    ora #$80
    sta es0 + 1
    lda.w trk_cval,x
    and #$0F
    ora es0 + 1
@g_wr:
    tay
    txa
    asl
    asl
    asl
    asl
    ora #DSP_V0GAIN
    phx
    jsr apu_dsp_write
    plx
    ; ADSR1 bit 7 off = GAIN active
    lda es0
    and #$7F
    tay
    txa
    asl
    asl
    asl
    asl
    ora #DSP_V0ADSR1
    phx
    jsr apu_dsp_write
    plx
    ; envelope no longer matches the record
    lda #$FF
    sta.w trk_instr_active,x
@out:
    rts

; --- U xy: surround — invert L (x) / R (y) phase via signed volumes ------------
; Sets the SIGN of the voice's live level (magnitude — record, X or P —
; is untouched), so U00 is always both-upright. The instrument shadow is
; invalidated so the next trigger restores the record's own signs.
cmd_surround:
    lda.w trk_voll,x
    bpl @l_mag
    eor #$FF
    inc a
@l_mag:
    sta es0
    lda.w trk_cval,x
    and #$F0
    beq @l_up
    lda es0
    eor #$FF
    inc a
    sta es0
@l_up:
    lda es0
    sta.w trk_voll,x
    lda.w trk_volr,x
    bpl @r_mag
    eor #$FF
    inc a
@r_mag:
    sta es0
    lda.w trk_cval,x
    and #$0F
    beq @r_up
    lda es0
    eor #$FF
    inc a
    sta es0
@r_up:
    lda es0
    sta.w trk_volr,x
    lda #$FF
    sta.w trk_instr_active,x
    jmp track_vol_write

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
    ; the C command overrides the record's GRP with a 2-voice chord
    lda.w trk_chord,x
    beq @from_rec
    lda #$02
    sta grp_span
    bra @go
@from_rec:
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
    bne @go
    jmp @out
@go:
    lda #$01
    sta grp_m
@member:
    lda grp_track
    clc
    adc grp_m
    cmp #TRACKS
    bcs @out
    sta trig_voice
    ; member offset: the C-command nibbles when overriding, else rec[8+m]
    phx
    rep #$30
.ACCU 16
    lda grp_track
    and #$00FF
    tax
    sep #$20
.ACCU 8
    lda.w trk_chord,x
    plx
    cmp #$00                ; plx set the flags; re-test the chord byte
    beq @rec_ofs
    ; m=1 -> x nibble, m=2 -> y nibble
    pha
    lda grp_m
    cmp #$01
    beq @hi_nib
    pla
    and #$0F
    bra @ofs_have
@hi_nib:
    pla
    lsr
    lsr
    lsr
    lsr
    bra @ofs_have
@rec_ofs:
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
@ofs_have:
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

; --- per-tick table step: run both command columns through the shared
; executor, then advance (H inside a table hops its own rows) ------------------
track_table:
    lda.w trk_tbl,x
    cmp #$FF
    bne @live
    rts
@live:
    lda.w trk_tbl_spd,x
    bne @tick
    ; note-sync: run only when a trigger left a step pending
    lda.w trk_tbl_cnt,x
    bne @consume
    rts
@consume:
    lda #$00
    sta.w trk_tbl_cnt,x
    lda.w trk_tbl,x
    bra @run
@tick:
    ; a row every TBS ticks
    lda.w trk_tbl_cnt,x
    dec a
    sta.w trk_tbl_cnt,x
    beq @due
    rts
@due:
    lda.w trk_tbl_spd,x
    sta.w trk_tbl_cnt,x
    lda.w trk_tbl,x
@run:
    ; cell base = table*64 + row*4 -> es1
    rep #$30
.ACCU 16
    and #$00FF
    asl
    asl
    asl
    asl
    asl
    asl                     ; * 64
    sta es1
    sep #$20
.ACCU 8
    lda.w trk_tbl_row,x
    rep #$30
.ACCU 16
    and #$00FF
    asl
    asl
    clc
    adc es1
    sta es1
    sep #$20
.ACCU 8
    ; column 1
    phx
    rep #$30
.ACCU 16
    lda es1
    tax
    sep #$20
.ACCU 8
    lda.l $7E0000 + SB_TABLES + 1,x
    sta es0                 ; val
    lda.l $7E0000 + SB_TABLES,x
    plx
    jsr table_exec
    ; column 2
    phx
    rep #$30
.ACCU 16
    lda es1
    tax
    sep #$20
.ACCU 8
    lda.l $7E0000 + SB_TABLES + 3,x
    sta es0
    lda.l $7E0000 + SB_TABLES + 2,x
    plx
    jsr table_exec
    ; advance
    lda.w trk_tbl_row,x
    inc a
    and #$0F
    sta.w trk_tbl_row,x
    rts

; A = command id, es0 = value: run one table cell on track X.
; Row-scoped commands (D/I/J) are inert here; H hops the table.
table_exec:
    cmp #$00
    beq @skip
    cmp #CMDID_H
    beq @hop
    cmp #CMDID_D
    beq @skip
    cmp #CMDID_I
    beq @skip
    cmp #CMDID_J
    beq @skip
    sta es0 + 1
    lda.w trk_cmd,x
    pha
    lda.w trk_cval,x
    pha
    lda es0 + 1
    sta.w trk_cmd,x
    lda es0
    sta.w trk_cval,x
    jsr row_cmd_pre
    jsr row_cmd_post
    pla
    sta.w trk_cval,x
    pla
    sta.w trk_cmd,x
@skip:
    rts
@hop:
    ; the NEXT tick plays row val (the stepper's advance lands there)
    lda es0
    dec a
    and #$0F
    sta.w trk_tbl_row,x
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
    ; A retunes per tick and owns the pitch for its row; otherwise the
    ; track vibrato (instrument VIB, V-overridable) rides the base pitch
    lda.w trk_cmd,x
    cmp #CMDID_A
    bne @not_arp
    jsr fx_arp
    bra @pitch_done
@not_arp:
    lda.w trk_vib,x
    beq @pitch_done
    jsr fx_vib
@pitch_done:
    ; tremolo (instrument TRM) dips the volume below the set level
    lda.w trk_trm,x
    beq @fx_done
    jsr fx_trm
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

; --- trk_vib xy: triangle vibrato around the base pitch (speed x, depth y) -----
; Seeded from the instrument's VIB at trigger; a row V command overrides.
fx_vib:
    txa
    sta trig_voice
    ; phase += speed
    lda.w trk_vib,x
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
    lda.w trk_vib,x
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

; --- trk_trm xy: triangle tremolo below the instrument volume ------------------
; Seeded from the instrument's TRM at trigger. One dip per cycle (0..15
; fold), dip = tri * depth / 2 (0..112), subtracted from the record's
; VOL L/R and clamped at zero — the level only ever moves down, so it
; composes with the hardware envelope. Preserves X.
fx_trm:
    ; phase += speed
    lda.w trk_trm,x
    lsr
    lsr
    lsr
    lsr
    clc
    adc.w trk_trm_ph,x
    sta.w trk_trm_ph,x
    ; one-sided triangle 0..15
    and #$1F
    cmp #$10
    bcc @rising
    eor #$1F                ; falling half: 31-t
@rising:
    sta es0                 ; tri 0..15
    lda.w trk_trm,x
    and #$0F
    sta es1 + 1             ; depth counter
    stz es1
    lda es1 + 1
    beq @dip_have
@mul:
    lda es1
    clc
    adc es0
    sta es1                 ; tri * depth, max 225
    dec es1 + 1
    bne @mul
@dip_have:
    lsr es1                 ; dip 0..112
    ; dip the live level (record / X / P), sign-preserved: a negative
    ; (surround) side moves toward zero, never through it
    lda.w trk_voll,x
    jsr @dip_side
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
    lda.w trk_volr,x
    jsr @dip_side
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
@dip_side:
    ; A = signed level -> A = level dipped by es1, clamped at zero
    bpl @pos
    eor #$FF
    inc a                   ; magnitude
    sec
    sbc es1
    bcs @renegate
    lda #$00
@renegate:
    eor #$FF
    inc a
    rts
@pos:
    sec
    sbc es1
    bcs @done
    lda #$00
@done:
    rts
