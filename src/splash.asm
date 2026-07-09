; splash.asm — boot splash (build stamp, pad echo). Start opens SONG.

.ACCU 8
.INDEX 16

; PUTS x, y, attr, string-label
.MACRO PUTS
    lda #\1
    sta text_x
    lda #\2
    sta text_y
    rep #$20
    lda #\3
    sta text_attr
    sep #$20
    ldx #\4
    jsr text_puts
.ENDM

.MACRO SETATTR
    rep #$20
    lda #\1
    sta text_attr
    sep #$20
.ENDM

splash_init:
    stz ui_mode
    jsr text_clear
    ; the wordmark: LOGO_TW x LOGO_TH tiles (chr index 192+), centred
    rep #$30
.ACCU 16
    lda #$0000
    sta tmp2                ; tile counter
    sep #$20
.ACCU 8
    stz tmp0 + 1            ; row
@lrow:
    stz tmp0                ; col
@lcol:
    ; shadow word offset = ((3 + row) * 32 + 5 + col) * 2
    lda tmp0 + 1
    clc
    adc #3
    rep #$30
.ACCU 16
    and #$00FF
    xba
    lsr
    lsr
    lsr                     ; * 32
    sta tmp1
    lda tmp0
    and #$00FF
    clc
    adc #5
    clc
    adc tmp1
    asl
    tax
    lda tmp2
    clc
    adc #192                ; logo tiles follow the two font sets
    ora #ATTR_TEXT
    sta.w SHADOW_BG3,x
    inc tmp2
    sep #$20
.ACCU 8
    inc tmp0
    lda tmp0
    cmp #LOGO_TW
    bne @lcol
    inc tmp0 + 1
    lda tmp0 + 1
    cmp #LOGO_TH
    bne @lrow
    ; full-width inverted band with the version (genmddj-style)
    PUTS  0, 14, ATTR_ACCENT, str_band
    PUTS 13, 14, ATTR_ACCENT, str_version
    ; git stamp below, plain
    PUTS 12, 16, ATTR_DIM,    str_stamp
    PUTS 10, 20, ATTR_ACCENT, str_start
    rts

splash_update:
    ; blink PRESS START on frame_cnt bit 5
    lda frame_cnt
    and #$20
    beq @dimmed
    PUTS 10, 20, ATTR_ACCENT, str_start
    bra @pads
@dimmed:
    PUTS 10, 20, ATTR_DIM,    str_start
@pads:
    ; Start -> song stub
    rep #$20
.ACCU 16
    lda pad_pressed
    and #PAD_START
    sep #$20
.ACCU 8
    beq @done
    jsr song_init_screen
@done:
    rts

str_band:     .DB "                                ", 0
str_start:    .DB "PRESS START", 0
