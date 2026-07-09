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
    PUTS  2, 24, ATTR_DIM,    str_pad
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
    ; pad echo: one glyph per button, accent when held
    lda #6
    sta text_x
    lda #24
    sta text_y
    ldx #$0000
@padloop:
    phx
    rep #$20
.ACCU 16
    lda.w pad_glyphs,x
    and pad_held
    bne @held
    lda #ATTR_DIM
    bra @setattr
@held:
    lda #ATTR_ACCENT
@setattr:
    sta text_attr
    sep #$20
.ACCU 8
    lda.w pad_glyphs+2,x
    jsr text_puttile
    plx
    inx
    inx
    inx
    cpx #(12 * 3)
    bne @padloop

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

; button glyph table: mask (word), tile (byte)
pad_glyphs:
    .DW PAD_B
    .DB 'B' - 32
    .DW PAD_Y
    .DB 'Y' - 32
    .DW PAD_SELECT
    .DB 'E' - 32
    .DW PAD_START
    .DB 'S' - 32
    .DW PAD_UP
    .DB GLYPH_ARROW_U
    .DW PAD_DOWN
    .DB GLYPH_ARROW_D
    .DW PAD_LEFT
    .DB GLYPH_ARROW_L
    .DW PAD_RIGHT
    .DB GLYPH_ARROW_R
    .DW PAD_A
    .DB 'A' - 32
    .DW PAD_X
    .DB 'X' - 32
    .DW PAD_L
    .DB 'L' - 32
    .DW PAD_R
    .DB 'R' - 32

str_band:     .DB "                                ", 0
str_start:    .DB "PRESS START", 0
str_pad:      .DB "PAD", 0
