; apu.asm — 65816 side of the APU mailbox: IPL upload, command send,
; DSP write path. Every wait here times out (invariant #1): a dead APU
; sets apu_status=1 -> visible "APU?" in the UI, never a hang.

.ACCU 8
.INDEX 16

.DEFINE CMD_NOP       $00
.DEFINE CMD_DSP_WRITE $01
.DEFINE CMD_UPLOAD    $02
.DEFINE CMD_TICKRATE  $03
.DEFINE CMD_ECHO_CFG  $04

; DSP register numbers
.DEFINE DSP_V0VOLL   $00
.DEFINE DSP_V0VOLR   $01
.DEFINE DSP_V0PITCHL $02
.DEFINE DSP_V0PITCHH $03
.DEFINE DSP_V0SRCN   $04
.DEFINE DSP_V0ADSR1  $05
.DEFINE DSP_V0ADSR2  $06
.DEFINE DSP_MVOLL    $0C
.DEFINE DSP_MVOLR    $1C
.DEFINE DSP_EVOLL    $2C
.DEFINE DSP_EVOLR    $3C
.DEFINE DSP_KON      $4C
.DEFINE DSP_KOF      $5C
.DEFINE DSP_FLG      $6C
.DEFINE DSP_ENDX     $7C
.DEFINE DSP_EFB      $0D
.DEFINE DSP_UNUSED   $1D    ; heartbeat lands here (no audible effect)
.DEFINE DSP_PMON     $2D
.DEFINE DSP_NON      $3D
.DEFINE DSP_EON      $4D
.DEFINE DSP_DIR      $5D
.DEFINE DSP_ESA      $6D
.DEFINE DSP_EDL      $7D

; ARAM layout (CLAUDE.md §14.1)
.DEFINE ARAM_DIR     $1000
.DEFINE ARAM_SAMPLES $1200

; --- wait until $2140 == A; carry set on timeout (~1.3 s) ----------------------
; Long enough to ride out the driver's echo reconfiguration (~0.3-0.6 s of
; busy time) with margin; a genuinely dead APU still surfaces as APU?.
apu_wait_p0:
    sta tmp0
    lda #$04
    sta apu_tmo
    ldy #$0000
@wait:
    lda APUIO0
    cmp tmp0
    beq @ok
    dey
    bne @wait
    dec apu_tmo
    bne @wait
    sec
    rts
@ok:
    clc
    rts

; --- upload the driver blob via the IPL ROM protocol, then wait for ready ----
apu_upload_driver:
    lda #$AA
    jsr apu_wait_p0
    bcs @fail
    ; begin transfer to $0200
    ldx #$0200
    stx APUIO2
    lda #$01
    sta APUIO1
    lda #$CC
    sta APUIO0
    jsr apu_wait_p0         ; A still $CC
    bcs @fail
    ; data bytes, index echoed low-byte by the IPL
    ldx #$0000
@loop:
    lda.w driver_blob,x
    sta APUIO1
    txa                     ; low byte of index
    sta APUIO0
    jsr apu_wait_p0
    bcs @fail
    inx
    cpx #(driver_blob_end - driver_blob)
    bne @loop
    ; kick: entry $0200, port0 jumps past the data index
    ldx #$0200
    stx APUIO2
    stz APUIO1
    lda #<(driver_blob_end - driver_blob)
    inc a
    sta APUIO0
    sta apu_seq             ; handshake state starts from the kick byte
    ; driver announces itself
    lda #$EE
    jsr apu_wait_p0
    bcs @fail
    stz apu_status
    clc
    rts
@fail:
    lda #$01
    sta apu_status
    sec
    rts

; --- send command A (0-127) with 16-bit payload X; carry set on timeout ------
; No idle-wait needed: the echo-wait below serializes sends, so the mailbox
; is idle whenever we get here. apu_seq starts from the IPL kick byte, which
; the driver adopted as its initial "last processed" state.
apu_send:
    sta tmp1
    stx APUIO1              ; payload -> ports 1/2
    lda apu_seq
    eor #$80
    and #$80
    ora tmp1                ; flip bit 7, new command in low 7
    sta apu_seq
    sta APUIO0
    lda apu_seq
    jsr apu_wait_p0
    bcs @timeout
    stz apu_status          ; a completed send heals a stale APU? flag
    clc
    rts
@timeout:
    lda #$01
    sta apu_status
    sec
    rts

; --- write DSP register: A = reg, Y = value -----------------------------------
apu_dsp_write:
    sta tmp2
    tya
    sta tmp2 + 1
    ldx tmp2                ; lo = reg, hi = value
    lda #CMD_DSP_WRITE
    jmp apu_send

; --- bulk upload to ARAM: up_src (CPU addr, DB), up_dest (ARAM), up_len -------
; up_len must be a multiple of 3 (pad; BRR blocks are 9 bytes so samples fit).
; Carry set on timeout.
apu_upload_block:
    ldx up_dest
    lda #CMD_UPLOAD
    jsr apu_send
    bcs @fail
    stz tmp1                ; round counter (1..255, cycling, never 0)
    ldy #$0000
@round:
    lda (up_src),y
    sta APUIO1
    iny
    lda (up_src),y
    sta APUIO2
    iny
    lda (up_src),y
    sta APUIO3
    iny
    lda tmp1
    inc a
    bne @nz
    inc a
@nz:
    sta tmp1
    sta APUIO0
    phy
    jsr apu_wait_p0
    ply
    bcs @fail
    cpy up_len
    bcc @round
    ; end of stream: counter 0 resyncs both sides' handshake state
    lda #$00
    sta APUIO0
    jsr apu_wait_p0
    bcs @fail
    stz apu_seq
    clc
    rts
@fail:
    lda #$01
    sta apu_status
    sec
    rts

; --- one-time audio setup after driver upload ---------------------------------
; Uploads the factory sample + directory, configures the DSP for voice 0.
apu_audio_init:
    ; sample 0 -> ARAM_SAMPLES
    ldx #sample0_brr
    stx up_src
    ldx #ARAM_SAMPLES
    stx up_dest
    ldx #(sample0_brr_end - sample0_brr)
    stx up_len
    jsr apu_upload_block
    bcc +
    jmp @fail
+
    ; directory (entry 0: start/loop = ARAM_SAMPLES) -> ARAM_DIR
    ldx #dir0_data
    stx up_src
    ldx #ARAM_DIR
    stx up_dest
    ldx #(dir0_data_end - dir0_data)
    stx up_len
    jsr apu_upload_block
    bcc +
    jmp @fail
+
    ; global DSP state
    lda #DSP_DIR
    ldy #(ARAM_DIR >> 8)
    jsr apu_dsp_write
    lda #DSP_MVOLL
    ldy #$60
    jsr apu_dsp_write
    lda #DSP_MVOLR
    ldy #$60
    jsr apu_dsp_write
    lda #DSP_ESA
    ldy #$FF                ; park the (disabled) echo buffer at top of ARAM
    jsr apu_dsp_write
    lda #DSP_EDL
    ldy #$00
    jsr apu_dsp_write
    lda #DSP_KOF
    ldy #$00                ; release the boot-time all-voices key-off latch
    jsr apu_dsp_write
    lda #DSP_NON
    ldy #$00                ; power-on DSP state is garbage: park the
    jsr apu_dsp_write       ; modulation/noise routing explicitly
    lda #DSP_PMON
    ldy #$00
    jsr apu_dsp_write
    lda #DSP_FLG
    ldy #$20                ; unmute; echo buffer writes stay disabled
    jsr apu_dsp_write
    ; all 8 voices: volumes, sample 0, musical ADSR (per-instrument in M6)
    ; (counter must survive apu_send, which clobbers tmp1)
    stz trig_voice
@voice:
    lda trig_voice
    asl
    asl
    asl
    asl                     ; voice * 16 = register base
    ora #DSP_V0VOLL
    ldy #$50
    jsr apu_dsp_write
    lda trig_voice
    asl
    asl
    asl
    asl
    ora #DSP_V0VOLR
    ldy #$50
    jsr apu_dsp_write
    lda trig_voice
    asl
    asl
    asl
    asl
    ora #DSP_V0SRCN
    ldy #$00
    jsr apu_dsp_write
    lda trig_voice
    asl
    asl
    asl
    asl
    ora #DSP_V0ADSR1
    ldy #$AF                ; adsr on, attack 15, decay 2
    jsr apu_dsp_write
    lda trig_voice
    asl
    asl
    asl
    asl
    ora #DSP_V0ADSR2
    ldy #$CA                ; sustain level 6, sustain rate 10
    jsr apu_dsp_write
    inc trig_voice
    lda trig_voice
    cmp #$08
    bne @voice
@fail:
    rts

; --- apply the song header's echo config to the DSP ---------------------------
; EVOL/EFB/FIR/EON are plain register writes; EDL/ESA go through the
; driver's safe reconfiguration service (CMD_ECHO_CFG).
apu_echo_apply_light:
    lda.l $7E0000 + SB_HEADER + SH_EVL
    tay
    lda #DSP_EVOLL
    jsr apu_dsp_write
    lda.l $7E0000 + SB_HEADER + SH_EVR
    tay
    lda #DSP_EVOLR
    jsr apu_dsp_write
    lda.l $7E0000 + SB_HEADER + SH_EFB
    tay
    lda #DSP_EFB
    jsr apu_dsp_write
    lda.l $7E0000 + SB_HEADER + SH_EON
    tay
    lda #DSP_EON
    jsr apu_dsp_write
    lda.l $7E0000 + SB_HEADER + SH_FIR
    jmp apu_fir_preset

apu_echo_apply:
    jsr apu_echo_apply_light
    ; EDL/ESA: echo buffer at the top of ARAM (ESA = $100 - EDL*8 pages)
    lda.l $7E0000 + SB_HEADER + SH_EDL
    and #$0F
    sta tmp2                ; payload lo = EDL
    asl
    asl
    asl                     ; pages
    eor #$FF
    inc a                   ; $100 - pages (mod 256; EDL 0 -> ESA $00... park)
    bne @esa_ok
    lda #$FF                ; EDL 0: 4-byte buffer parked at $FF00
@esa_ok:
    sta tmp2 + 1            ; payload hi = ESA page
    ldx tmp2
    lda #CMD_ECHO_CFG
    jmp apu_send

; --- write FIR preset A (0-7) to the 8 FIR tap registers ------------------------
apu_fir_preset:
    and #$07
    rep #$30
.ACCU 16
    and #$00FF
    asl
    asl
    asl                     ; * 8
    tax
    sep #$20
.ACCU 8
    stz trig_id             ; tap counter (borrow; safe outside triggers)
@tap:
    lda.w fir_presets,x
    tay
    lda trig_id
    asl
    asl
    asl
    asl
    ora #$0F                ; FIR tap register = v*16 + $0F
    phx
    jsr apu_dsp_write
    plx
    inx
    inc trig_id
    lda trig_id
    cmp #$08
    bne @tap
    rts

; 8 factory FIR curves x 8 taps (signed bytes; tap0-dominant = dry-ish)
fir_presets:
    .DB $7F, $00, $00, $00, $00, $00, $00, $00   ; 0 FLAT (pass-through)
    .DB $58, $30, $12, $08, $00, $00, $00, $00   ; 1 DARK (lowpass hall)
    .DB $70, $E8, $18, $F4, $00, $00, $00, $00   ; 2 BRIGHT (presence)
    .DB $40, $00, $00, $40, $00, $00, $00, $00   ; 3 COMB
    .DB $20, $30, $40, $30, $20, $10, $08, $04   ; 4 SOFT (smeared)
    .DB $4C, $21, $12, $09, $05, $03, $02, $01   ; 5 DKC HALL (decay tail)
    .DB $60, $A0, $40, $D0, $20, $E8, $10, $F8   ; 6 METAL (alternating)
    .DB $7F, $00, $00, $00, $00, $00, $00, $00   ; 7 USER (starts flat)

; --- T command: set the engine tick rate from a BPM value ---------------------
; tick Hz = BPM * 0.4 (groove 6 = 4 rows/beat); Timer-0 target = 20000/BPM.
; Range 80-255 BPM (slower tempos come from longer grooves).
apu_set_tempo:
    cmp #80
    bcs @ok
    lda #80
@ok:
    ldx #20000
    stx WRDIVL
    sta WRDIVB              ; starts the hardware division
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop                     ; 16 cycles for the divider
    ldx RDDIVL              ; quotient (fits a byte for BPM >= 79)
    lda #CMD_TICKRATE
    jmp apu_send

; --- set VxPITCH for note A (0-95) on voice trig_voice (no KON) ---------------
; pitch = pitch_octave7[semitone] >> (7 - octave); tables from maketables.py
; note_pitch_calc_only computes last_pitch without touching the DSP.
note_pitch:
    jsr note_pitch_calc_only
    bra voice_pitch_write

note_pitch_calc_only:
    rep #$20
.ACCU 16
    and #$00FF
    tax
    sep #$20
.ACCU 8
    lda.w note_shift,x
    sta tmp1
    stz tmp1 + 1
    lda.w note_semi2,x
    rep #$30
.ACCU 16
    and #$00FF
    tax
    lda.w pitch_octave7,x
    ldy tmp1
    beq @shifted
@shift:
    lsr a
    dey
    bne @shift
@shifted:
    sta last_pitch
    sep #$20
.ACCU 8
    rts

; --- write last_pitch to trig_voice's pitch registers --------------------------
voice_pitch_write:
    lda trig_voice
    asl
    asl
    asl
    asl                     ; voice * 16
    ora #DSP_V0PITCHL
    ldy last_pitch
    jsr apu_dsp_write
    lda last_pitch + 1
    tay
    lda trig_voice
    asl
    asl
    asl
    asl
    ora #DSP_V0PITCHH
    jmp apu_dsp_write

; --- load instrument A's registers onto voice trig_voice (if not active) ------
; SRCN, ADSR (bit7 forced on), VOL L/R from the record at SB_INSTR + id*16.
; Preserves X; returns A = id.
apply_instrument:
    sta trig_id
    phx
    lda trig_voice
    rep #$30
.ACCU 16
    and #$00FF
    tax
    sep #$20
.ACCU 8
    lda.w trk_instr_active,x
    cmp trig_id
    bne @load
    ; already loaded: still report the type for trigger routing
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
    lda.l $7E0000 + SB_INSTR,x
    and #$03
    sta trig_type
    plx
    lda trig_id
    rts
@load:
    lda trig_id
    sta.w trk_instr_active,x
    rep #$30
.ACCU 16
    lda trig_id
    and #$00FF
    asl
    asl
    asl
    asl
    tax                     ; record offset
    sep #$20
.ACCU 8
    ; type decides sample routing and the NON bit
    lda.l $7E0000 + SB_INSTR,x
    and #$03
    sta trig_type
    cmp #$02                ; WAV: SRCN = 32 + bank
    bne @not_wav
    lda.l $7E0000 + SB_INSTR + 1,x
    and #$07
    ora #$20
    bra @srcn
@not_wav:
    lda.l $7E0000 + SB_INSTR + 1,x
@srcn:
    tay
    lda trig_voice
    asl
    asl
    asl
    asl
    ora #DSP_V0SRCN
    phx
    jsr apu_dsp_write
    plx
    ; NON bit: on for NSE, off otherwise
    phx
    lda trig_voice
    rep #$30
.ACCU 16
    and #$00FF
    tax
    sep #$20
.ACCU 8
    lda trig_type
    cmp #$03
    beq @nse
    lda.w bit_for_track,x
    eor #$FF
    and eng_non
    bra @non_wr
@nse:
    lda.w bit_for_track,x
    ora eng_non
@non_wr:
    cmp eng_non
    beq @non_same
    sta eng_non
    tay
    lda #DSP_NON
    jsr apu_dsp_write
@non_same:
    plx
    ; ADSR1 (ADSR mode always on)
    lda.l $7E0000 + SB_INSTR + 2,x
    ora #$80
    tay
    lda trig_voice
    asl
    asl
    asl
    asl
    ora #DSP_V0ADSR1
    phx
    jsr apu_dsp_write
    plx
    ; ADSR2
    lda.l $7E0000 + SB_INSTR + 3,x
    tay
    lda trig_voice
    asl
    asl
    asl
    asl
    ora #DSP_V0ADSR2
    phx
    jsr apu_dsp_write
    plx
    ; VOL L/R
    lda.l $7E0000 + SB_INSTR + 4,x
    tay
    lda trig_voice
    asl
    asl
    asl
    asl
    ora #DSP_V0VOLL
    phx
    jsr apu_dsp_write
    plx
    lda.l $7E0000 + SB_INSTR + 5,x
    tay
    lda trig_voice
    asl
    asl
    asl
    asl
    ora #DSP_V0VOLR
    phx
    jsr apu_dsp_write
    plx
@skip:
    plx
    lda trig_id
    rts

; --- audition: immediate note on voice 0 (editor insert/nudge) ----------------
; Uses the last-inserted instrument so what you hear is what the row plays.
audition_note:
    pha
    stz trig_voice
    lda ed_lastinstr
    cmp #INSTR_NONE
    beq @no_instr
    jsr apply_instrument
@no_instr:
    pla
    jsr note_pitch
    lda #DSP_KON
    ldy #$0001
    jsr apu_dsp_write
    inc kon_count
    rts

; --- per-frame APU housekeeping (main loop) ------------------------------------
; Mirrors tick telemetry and sends the M2 heartbeat: an incrementing value
; into MVOLL every 64 frames, so checks can watch the full SCB path land in
; the DSP. Replaced by the real diff engine in M3.
apu_update:
    lda APUIO3
    sta apu_tick
    lda apu_status
    bne @done               ; don't hammer a dead mailbox every heartbeat
    rep #$20
.ACCU 16
    lda frame_cnt
    and #$003F
    sep #$20
.ACCU 8
    bne @done
    lda hb_val
    inc a
    and #$3F
    sta hb_val
    tay
    lda #DSP_UNUSED         ; APU-alive heartbeat, inaudible
    jsr apu_dsp_write
@done:
    rts
