; input.asm — per-frame pad state: held / pressed / DAS auto-repeat.
; pad_event = newly pressed | DAS repeats; edit code consumes pad_event.
; NMI latches pad_raw; this runs from the main loop once per frame.

.ACCU 8
.INDEX 16

.DEFINE DAS_DELAY 14        ; frames before auto-repeat kicks in
.DEFINE DAS_RATE  3         ; frames between repeats

input_update:
    rep #$30
.ACCU 16
    lda pad_raw
    sta pad_held
    ; pressed = held & ~prev
    lda pad_prev
    eor #$FFFF
    and pad_held
    sta pad_pressed
    sta pad_event
    lda pad_held
    sta pad_prev

    ; --- DAS on the d-pad ---
    lda pad_held
    and #PAD_DPAD
    beq @idle
    cmp pad_das_dir
    bne @newdir
    ; same direction held: advance the repeat clock
    sep #$20
.ACCU 8
    inc das_cnt
    lda das_cnt
    cmp #DAS_DELAY
    bcc @done
    ; fire a repeat
    sec
    sbc #DAS_RATE
    sta das_cnt
    rep #$20
.ACCU 16
    lda pad_event
    ora pad_das_dir
    sta pad_event
    sep #$20
.ACCU 8
    rts

@newdir:
.ACCU 16
    sta pad_das_dir
    sep #$20
.ACCU 8
    stz das_cnt
    rts

@idle:
.ACCU 16
    lda #$0000
    sta pad_das_dir
    sep #$20
.ACCU 8
    stz das_cnt
@done:
    rts
