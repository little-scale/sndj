; midi.asm — M14: MIDI note takeover (SYNC: MIDI), the genmddj protocol
; on SNES pins. sndj becomes an 8-voice BRR sample module: the transport
; stays stopped, an external keyboard/DAW plays the voices live through
; the ESP32-S3 link bridge (same firmware as the siblings — no reflash).
;
; Wire (3 wires: CLK, DAT, GND): the console is the clock master.
;   CLK = IOBit, port 2 pin 6  ($4201 bit 7, push-pull — the genmddj
;         open-drain lesson: a pull-up RC ramp loses edges)
;   DAT = D0,    port 2 pin 4  ($4017 bit 0, input)
; Per event the S3 presents a leading flag bit (1 = a 3-byte frame
; follows, 0 = queue empty); bits are MSB first, sampled on the rising
; CLK edge; the S3 presents the next bit on the falling edge. The frame
; is bridge-normalised: status = type<<4 | channel with type 1 note-off,
; 2 note-on, 3 CC, 4 program change, 5 pitch bend, 7 panic.
;
; Channels 1-8 map 1:1 onto V1-V8 (9-16 ignored). Each voice keeps a
; console-side "current instrument" — seeded to channel-1 on entry,
; changed live by Program Change. Velocity drives the live volume,
; pitch bend rides the tune context (+/-2 semitones), CC 7/10/91/74 =
; volume / pan / echo send / FIR preset.

.ACCU 8
.INDEX 16

.DEFINE MIDI_CAP    8    ; max events drained per frame
.DEFINE MIDI_SETTLE 24   ; CLK low-phase settle loop (S3 ISR presents the bit)

; --- every frame from the main loop ---------------------------------------------
; Detects OPTIONS flipping SYNC into/out of MIDI (silence + pin config),
; then drains the wire while the mode is armed and the transport stopped.
midi_service:
    lda opt_sync
    cmp sync_shadow
    beq @steady
    pha
    lda sync_shadow
    cmp #SYNC_MIDI
    beq @edge                ; leaving MIDI
    pla
    pha
    cmp #SYNC_MIDI
    bne @no_edge             ; a change between non-MIDI modes
@edge:
    pla
    sta sync_shadow
    jmp midi_mode_change
@no_edge:
    pla
    sta sync_shadow
@steady:
    lda opt_sync
    cmp #SYNC_MIDI
    bne @done
    lda eng_playing          ; takeover runs with the transport stopped
    bne @done
    jmp midi_poll
@done:
    rts

; --- entering/leaving MIDI: clean slate + pin state ------------------------------
midi_mode_change:
    jsr midi_panic_all       ; all-notes-off both ways
    lda opt_sync
    cmp #SYNC_MIDI
    bne @leave
    lda #$7F
    sta WRIO                 ; CLK idles low
    ; seed each voice's instrument = its index (ch1 -> 00 .. ch8 -> 07);
    ; recomputed on every entry, so PCs reset to the default map
    ldx #$0000
@seed:
    txa
    sta.w midi_instr,x
    lda #$FF
    sta.w midi_note,x
    lda #$00
    sta.w midi_bsemi,x
    sta.w midi_bfine,x
    inx
    cpx #TRACKS
    bne @seed
    ; fresh monitor each session
    stz midi_rx
    stz midi_rx + 1
    stz midi_last
    stz midi_last + 1
    stz midi_last + 2
    rts
@leave:
    lda #$FF                 ; release the line
    sta WRIO
    rts

; --- drain buffered events off the S3 wire ---------------------------------------
midi_poll:
    lda HVBJOY               ; never clock the port during the auto-read
    and #$01
    bne @busy
    lda #MIDI_CAP
    sta mp_cap
@loop:
    jsr midi_clock_bit       ; leading flag
    beq @drained             ; 0 -> queue empty
    jsr midi_clock_byte
    sta mp_ev                ; status: type<<4 | channel
    jsr midi_clock_byte
    sta mp_ev + 1            ; data 1
    jsr midi_clock_byte
    sta mp_ev + 2            ; data 2
    jsr midi_dispatch
    dec mp_cap
    bne @loop
@drained:
    lda #$7F                 ; leave CLK low (idle = the S3's re-arm gap)
    sta WRIO
@busy:
    rts

; --- one clocked bit: A = DAT (0/1), Z reflects it -------------------------------
midi_clock_bit:
    lda #$FF                 ; CLK high (push-pull rising edge)
    sta WRIO
    lda JOYSER1              ; sample DAT immediately (stable since the last fall)
    and #$01
    pha
    lda #$7F                 ; CLK low -> the S3's edge ISR presents the next bit
    sta WRIO
    lda #MIDI_SETTLE
    sta mp_settle
@settle:
    dec mp_settle
    bne @settle
    pla
    rts

; --- one byte, MSB first ---------------------------------------------------------
midi_clock_byte:
    lda #$08
    sta mp_bits
    stz mp_b
@bit:
    jsr midi_clock_bit       ; A = 0/1
    asl mp_b
    ora mp_b
    sta mp_b
    dec mp_bits
    bne @bit
    lda mp_b
    rts

; --- dispatch mp_ev --------------------------------------------------------------
midi_dispatch:
    ; monitor first, before any filtering: a climbing counter proves the
    ; console is decoding frames at all (the two-sided bring-up lesson)
    lda mp_ev
    sta midi_last
    lda mp_ev + 1
    sta midi_last + 1
    lda mp_ev + 2
    sta midi_last + 2
    rep #$20
.ACCU 16
    lda midi_rx
    inc a
    sta midi_rx
    sep #$20
.ACCU 8
    lda mp_ev
    and #$0F                 ; channel -> voice
    cmp #TRACKS
    bcs @done                ; channels 9-16: no voice
    sta mp_voice
    lda mp_ev
    lsr
    lsr
    lsr
    lsr                      ; type
    cmp #$02
    beq @on
    cmp #$01
    beq @off
    cmp #$03
    beq @cc
    cmp #$04
    beq @pgm
    cmp #$05
    beq @bend
    cmp #$07
    beq @panic
@done:
    rts
@on:
    jmp midi_note_on
@off:
    jmp midi_note_off
@cc:
    jmp midi_cc
@pgm:
    rep #$30
.ACCU 16
    lda mp_voice
    and #$00FF
    tax
    sep #$20
.ACCU 8
    lda mp_ev + 1
    and #(INSTR_COUNT - 1)   ; PC 0-63 -> instrument slot
    sta.w midi_instr,x
    rts
@bend:
    jmp midi_bend
@panic:
    jmp midi_panic_all

; --- note on: mp_voice, mp_ev+1 = MIDI note, mp_ev+2 = velocity -------------------
midi_note_on:
    lda mp_ev + 2
    bne @really_on
    jmp midi_note_off        ; velocity 0 = note off (running-status idiom)
@really_on:
    ; MIDI note - 12 -> console note index 0..95 (MIDI C1(24) = C-1)
    lda mp_ev + 1
    sec
    sbc #$0C
    bpl @lo_ok
    lda #$00
@lo_ok:
    cmp #NOTE_MAX
    bcc @hi_ok
    lda #NOTE_MAX - 1
@hi_ok:
    pha
    lda mp_voice
    sta trig_voice
    rep #$30
.ACCU 16
    and #$00FF
    tax
    sep #$20
.ACCU 8
    pla
    sta.w midi_note,x
    sta trig_note            ; kit_trigger reads the note from here
    lda.w midi_instr,x
    jsr apply_instrument
    lda trig_type
    cmp #$01
    bne @pitched
    jsr kit_trigger          ; kits play the note's slot
    bcs @vel
    rts                      ; empty slot: silence
@pitched:
    jsr midi_pitch_apply     ; note + bend through the instrument tune
@vel:
    ; velocity -> the voice's live level (both sides), riding trk_voll
    rep #$30
.ACCU 16
    lda mp_voice
    and #$00FF
    tax
    sep #$20
.ACCU 8
    lda mp_ev + 2
    and #$7F
    sta.w trk_voll,x
    sta.w trk_volr,x
    jsr track_vol_write
    ; key on
    lda.w bit_for_track,x
    tay
    lda #DSP_KON
    jsr apu_dsp_write
    inc kon_count
    rts

; --- note off ---------------------------------------------------------------------
midi_note_off:
    rep #$30
.ACCU 16
    lda mp_voice
    and #$00FF
    tax
    sep #$20
.ACCU 8
    lda.w midi_note,x
    cmp #$FF
    beq @done
    lda #$FF
    sta.w midi_note,x
    lda.w bit_for_track,x
    tay
    lda #DSP_KOF
    jsr apu_dsp_write
    ldy #$0000
    lda #DSP_KOF             ; drop the KOF bit so the next KON isn't masked
    jsr apu_dsp_write
@done:
    rts

; --- pitch bend: 14-bit d2:d1 - 8192 -> +/-2 semitones ----------------------------
midi_bend:
    ; total = (value - 8192) / 16 = signed 1/256-semi offset, -512..+511
    rep #$20
.ACCU 16
    lda mp_ev + 2
    and #$007F
    xba
    lsr                      ; d2 << 7
    sta mb_tot
    lda mp_ev + 1
    and #$007F
    ora mb_tot
    sec
    sbc #$2000
    ; arithmetic >> 4 (cmp #$8000 seeds the sign into carry for ror)
    cmp #$8000
    ror a
    cmp #$8000
    ror a
    cmp #$8000
    ror a
    cmp #$8000
    ror a
    sta mb_tot
    ; semi = high byte of (total + 128); fine = low byte of total —
    ; exact for the whole -512..+511 range
    clc
    adc #$0080
    xba
    sep #$20
.ACCU 8
    pha                      ; semi
    rep #$30
.ACCU 16
    lda mp_voice
    and #$00FF
    tax
    sep #$20
.ACCU 8
    pla
    sta.w midi_bsemi,x
    lda mb_tot
    sta.w midi_bfine,x
    ; retune live if the voice is sounding (kit slots don't bend)
    lda.w midi_note,x
    cmp #$FF
    beq @done
    lda mp_voice
    sta trig_voice
    lda.w midi_instr,x
    jsr apply_instrument     ; refreshes the tune context (cached = cheap)
    lda trig_type
    cmp #$01
    beq @done
    jmp midi_pitch_apply
@done:
    rts

; --- CC: 7 volume, 10 pan, 91 echo send, 74 FIR preset ----------------------------
midi_cc:
    rep #$30
.ACCU 16
    lda mp_voice
    and #$00FF
    tax
    sep #$20
.ACCU 8
    lda mp_ev + 1
    cmp #$07
    beq @vol
    cmp #$0A
    beq @pan
    cmp #$5B
    beq @echo
    cmp #$4A
    beq @fir
    rts
@vol:
    lda mp_ev + 2
    and #$7F
    sta.w trk_voll,x
    sta.w trk_volr,x
    jmp track_vol_write
@pan:
    ; CC10 0-127 -> the P curve: val = cc*2; L = (255-val)/2, R = val/2
    lda mp_ev + 2
    asl
    sta sy_tmp
    lda #$FF
    sec
    sbc sy_tmp
    lsr
    sta.w trk_voll,x
    lda sy_tmp
    lsr
    sta.w trk_volr,x
    jmp track_vol_write
@echo:
    lda mp_ev + 2
    cmp #$40
    bcs @eon_on
    lda.w bit_for_track,x
    eor #$FF
    sta sy_tmp
    lda.l $7E0000 + SB_HEADER + SH_EON
    and sy_tmp
    bra @eon_wr
@eon_on:
    lda.l $7E0000 + SB_HEADER + SH_EON
    ora.w bit_for_track,x
@eon_wr:
    sta.l $7E0000 + SB_HEADER + SH_EON
    jmp eon_sync
@fir:
    lda mp_ev + 2
    lsr
    lsr
    lsr
    lsr
    and #$07                 ; CC74 0-127 -> preset 0-7
    sta.l $7E0000 + SB_HEADER + SH_FIR
    jmp apu_fir_preset

; --- pitch for mp_voice: tune context (fresh from apply_instrument) + bend --------
; WAV keeps its -1 octave, like every other trigger path.
midi_pitch_apply:
    rep #$30
.ACCU 16
    lda mp_voice
    and #$00FF
    tax
    sep #$20
.ACCU 8
    lda trig_fine
    clc
    adc.w midi_bfine,x
    sta trig_fine
    bvc @fine_ok             ; signed overflow carries a semitone
    bmi @carry_up
    lda trig_semis
    dec a
    sta trig_semis
    bra @fine_ok
@carry_up:
    lda trig_semis
    inc a
    sta trig_semis
@fine_ok:
    lda trig_semis
    clc
    adc.w midi_bsemi,x
    sta trig_semis
    lda.w midi_note,x
    jsr note_pitch_calc_only
    lda trig_type
    cmp #$02
    bne @wr
    rep #$20
.ACCU 16
    lsr last_pitch
    sep #$20
.ACCU 8
@wr:
    jmp voice_pitch_write

; --- all-notes-off (mode entry/exit + MIDI panic) ---------------------------------
midi_panic_all:
    ldy #$00FF
    lda #DSP_KOF
    jsr apu_dsp_write
    ldy #$0000
    lda #DSP_KOF
    jsr apu_dsp_write
    ldx #$0000
@clr:
    lda #$FF
    sta.w midi_note,x
    inx
    cpx #TRACKS
    bne @clr
    rts
