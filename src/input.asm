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
    ; Frame-delta based: heavy screens may run the main loop below 60 fps,
    ; but auto-repeat cadence must track real (NMI) frames.
    lda pad_held
    and #PAD_DPAD
    beq @idle
    cmp pad_das_dir
    bne @newdir
    ; same direction held: advance the repeat clock by elapsed frames
    sep #$20
.ACCU 8
    lda frame_cnt
    sec
    sbc das_last_fc
    clc
    adc das_cnt
    sta das_cnt
    lda frame_cnt
    sta das_last_fc
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
    lda frame_cnt
    sta das_last_fc
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
