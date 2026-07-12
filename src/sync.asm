; sync.asm — M12: sync clock on controller port 2, genmddj protocol and
; numbering (opt_sync: 0 OFF, 1 OUT, 2 PULSE, 3 IN, 4 MIDI, 5 IN24).
;
; The SNES port asymmetry: as a SLAVE, IN reads a one-wire row toggle on
; D0 ($4017 bit 0), while IN24 reads the family's full 2-bit counter on
; D0+D1 (wire-identical to the ESP32 Link bridge, no reflash needed);
; as a MASTER the console's one clean output is IOBit ($4201 bit 7), which
; drives PULSE (and the MIDI clock, midi.asm). OUT is a dummy for now:
; selectable, inert (the single-line row clock arrives with the
; cross-sibling "edge IN" decision).
;
; IN: a D0 change is one ROW clock. IN24: (read - last) & 3 catch-up.
; Both arm in WAIT with the first change counting as exactly one clock,
; and seed the row counter to divisor-1 so the first clock plays row 0.

.ACCU 8
.INDEX 16

.DEFINE PULSE_DIV  12            ; ticks per pulse (2 PPQN at groove 6)

; --- boot: opt_sync from the SRAM config stub ($700009) -------------------------
sync_boot:
    stz sync_shadow
    stz sync_wait
    lda.l $700000
    cmp #'S'
    bne @default
    lda.l $700004
    cmp #'1'
    bne @default
    lda.l $700009
    cmp #$06
    bcc @have
@default:
    lda #SYNC_OFF
@have:
    sta opt_sync
    sta sync_shadow          ; boot state is "already applied" (no MIDI edge)
    rts

; --- A = 2-bit counter on port 2's data lines -----------------------------------
sync_read:
    lda JOYSER1
    and #$03
    rts

; --- play-start: configure the port + arm a slave (from engine_go) --------------
sync_play_start:
    rep #$20
.ACCU 16
    lda #$0000
    sep #$20
.ACCU 8
    sta sync_act
    sta sync_act + 1
    stz sync_wait
    stz sync_cnt
    stz sync_gctr
    lda opt_sync
    cmp #SYNC_PULSE
    bne @not_pulse
    lda #$7F                 ; pulse line idles LOW (Volca clock is active-high)
    sta WRIO
    rts
@not_pulse:
    cmp #SYNC_IN
    beq @slave
    cmp #SYNC_IN24
    beq @slave
    lda #$FF                 ; OFF / OUT (dummy) / MIDI: IOBit released high
    sta WRIO
    rts
@slave:
    ; latch the counter so stale line levels never count as a clock
    jsr sync_read
    sta sync_last
    lda #$01
    sta sync_wait            ; armed: hold row 0 silently until the first clock
    ; head-start = divisor-1 so the FIRST clock plays row 0
    lda opt_sync
    cmp #SYNC_IN24
    bne @hs_in
    lda #$05
    sta sync_gctr
    rts
@hs_in:
    stz sync_gctr            ; IN (div 1): 0
    rts

; --- transport stop: release the line ------------------------------------------
sync_stop:
    stz sync_wait
    lda opt_sync
    cmp #SYNC_MIDI
    beq @done                ; MIDI owns the pin while the mode is armed
    lda #$FF
    sta WRIO
@done:
    rts

; --- per-tick (playing, IN/IN24): accrue external clocks into sync_gctr ---------
; Skips the poll while the auto-joypad read owns the port. IN is a persistent
; one-wire D0 toggle (at most one recoverable row per poll); IN24 keeps the
; 2-bit counter and its lossless catch-up of as many as 3 clocks per poll.
sync_in_poll:
    lda HVBJOY
    and #$01
    bne @done
    jsr sync_read
    pha                      ; new counter
    lda opt_sync
    cmp #SYNC_IN
    bne @delta24
    pla                      ; IN: any D0 transition is exactly one row clock
    pha
    eor sync_last
    and #$01
    bra @have_delta
@delta24:
    pla                      ; IN24: modulo-4 counter delta preserves bursts
    pha
    sec
    sbc sync_last
    and #$03
@have_delta:
    sta sy_tmp               ; clocks since last poll
    pla
    sta sync_last
    lda sy_tmp
    beq @done
    lda sync_wait            ; armed: the first change counts as exactly ONE
    beq @accrue              ; (never the raw idle->running counter jump)
    stz sync_wait
    lda #$01
    sta sy_tmp
@accrue:
    lda sync_gctr
    clc
    adc sy_tmp
    sta sync_gctr
    rep #$20
.ACCU 16
    lda sy_tmp
    and #$00FF
    clc
    adc sync_act
    sta sync_act
    sep #$20
.ACCU 8
@done:
    rts

; --- per-tick (playing, PULSE): IOBit high on tick 0 of every 12 ----------------
sync_pulse_tick:
    lda sync_cnt
    bne @low
    lda #$FF                 ; the clock edge
    sta WRIO
    rep #$20
.ACCU 16
    lda sync_act
    inc a
    sta sync_act
    sep #$20
.ACCU 8
    bra @adv
@low:
    lda #$7F
    sta WRIO
@adv:
    lda sync_cnt
    inc a
    cmp #PULSE_DIV
    bcc @st
    lda #$00
@st:
    sta sync_cnt
    rts
