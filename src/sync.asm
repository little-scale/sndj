; sync.asm — M12: sync clock on controller port 2, genmddj protocol and
; numbering (opt_sync: 0 OFF, 1 OUT, 2 PULSE, 3 IN, 4 MIDI, 5 IN24).
;
; The SNES port asymmetry: as a SLAVE, IN and IN24 both read a one-wire
; toggle on D0 ($4017 bit 0). IN treats each edge as a row; IN24 treats it
; as one 24-PPQN clock and divides by six (no bridge reflash needed);
; as a MASTER the console's one clean output is IOBit ($4201 bit 7), which
; drives PULSE (and the MIDI clock, midi.asm). OUT is a dummy for now:
; selectable, inert (the single-line row clock arrives with the
; cross-sibling "edge IN" decision).
;
; IN: a D0 change is one ROW clock. IN24: a D0 change is one MIDI clock.
; Both arm in WAIT with the first change counting as exactly one clock.
; A four-times-per-frame V-timer IRQ captures changes independently of the
; song tempo. IN24 clocks drive engine ticks directly; sync_cnt starts at five
; so the first of the six-clock row cycle plays row 0.

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

; --- A = one-wire toggle on port 2 Data1 ----------------------------------------
sync_read:
    lda JOYSER1
    and #$01
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
    jsr sync_irq_disarm
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
    ; IN24 phase head-start = divisor-1 so the FIRST clock plays row 0.
    ; sync_gctr is now only the IRQ-to-main pending-clock queue.
    lda opt_sync
    cmp #SYNC_IN24
    bne @hs_in
    lda #$05
    sta sync_cnt
    jsr sync_irq_arm
    rts
@hs_in:
    stz sync_cnt             ; IN has no sub-row clock phase
    jsr sync_irq_arm
    rts

; --- transport stop: release the line ------------------------------------------
sync_stop:
    stz sync_wait
    jsr sync_irq_disarm
    lda opt_sync
    cmp #SYNC_MIDI
    beq @done                ; MIDI owns the pin while the mode is armed
    lda #$FF
    sta WRIO
@done:
    rts

; --- four-times-per-frame vertical IRQ ------------------------------------------
; V-only IRQ is reprogrammed after every hit. Positions are spread across the
; whole video period; the PAL fourth sample occurs after auto-joypad has cleared.
sync_irq_arm:
    stz sync_irq_slot
    lda #$10
    sta VTIMEL
    stz VTIMEH
    lda TIMEUP               ; clear a stale IRQ before enabling
    lda #$A1                 ; NMI + V-IRQ + auto-joypad
    sta NMITIMEN
    cli                      ; ordinary modes retain the original IRQ-masked state
    rts

sync_irq_disarm:
    sei                      ; close the mask before disabling the timer source
    lda #$81                 ; NMI + auto-joypad, no timer IRQ
    sta NMITIMEN
    lda TIMEUP
    rts

; The IRQ body and capture path live in bank 6 to keep the packed bank-0 code
; below the internal header. Vec_IRQ in bank 0 jumps here directly.
.BANK 6 SLOT 0
.SECTION "Sync IRQ Capture" FREE

Sync_IRQ_Body:
    rep #$30
.ACCU 16
    pha
    phx
    phy
    phb
    phd
    lda #$0000
    tcd
    sep #$20
.ACCU 8
    lda #$80
    pha
    plb

    lda TIMEUP               ; acknowledge the V-timer IRQ
    jsr sync_irq_next
    jsr sync_irq_poll

    rep #$30
.ACCU 16
    pld
    plb
    ply
    plx
    pla
    rti
.ACCU 8

sync_irq_next:
    lda sync_irq_slot
    inc a
    and #$03
    sta sync_irq_slot
    rep #$30
.ACCU 16
    and #$00FF
    tax
    sep #$20
.ACCU 8
    lda video_pal
    beq @ntsc
    lda.w sync_vtime_pal,x
    bra @set
@ntsc:
    lda.w sync_vtime_ntsc,x
@set:
    sta VTIMEL
    stz VTIMEH
    rts

sync_vtime_ntsc: .DB 16, 82, 148, 214
sync_vtime_pal:  .DB 16, 94, 172, 250

; IRQ entry guard: capture only while a slave transport is running.
sync_irq_poll:
    lda eng_playing
    beq @done
    lda opt_sync
    cmp #SYNC_IN
    beq sync_in_capture
    cmp #SYNC_IN24
    beq sync_in_capture
@done:
    rts

; --- IRQ capture: accrue external clocks into sync_gctr -------------------------
; Skips the poll while auto-joypad owns the port. Both slave modes use the
; persistent D0 toggle: IN counts an edge as a row, while IN24 counts it as one
; 24-PPQN clock. Data2 is deliberately ignored so bit ordering cannot double
; the clock. Musical processing is deferred until after RTI.
sync_in_capture:
    lda HVBJOY
    and #$01
    bne @done
    lda JOYSER1
    and #$01
    pha                      ; new D0 state
    eor sync_last            ; any D0 transition is exactly one wire clock
    and #$01
    sta sync_irq_delta       ; always 0 or 1 (IRQ-private scratch)
    pla
    sta sync_last
    lda sync_irq_delta
    beq @done
    lda sync_wait            ; armed: the first change counts as exactly ONE
    beq @accrue
    stz sync_wait
@accrue:
    lda sync_gctr            ; pending clocks for main-loop service
    clc
    adc sync_irq_delta
    sta sync_gctr
    rep #$20
.ACCU 16
    lda sync_irq_delta
    and #$00FF
    clc
    adc sync_act
    sta sync_act
    sep #$20
.ACCU 8
@done:
    rts

.ENDS
.BANK 0 SLOT 0

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
