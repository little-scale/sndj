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
    PUTS 13,  7, ATTR_ACCENT, str_title
    PUTS  5,  9, ATTR_TEXT,   str_subtitle
    PUTS  8, 11, ATTR_TEXT,   str_version
    PUTS  2, 14, ATTR_DIM,    str_family
    PUTS 10, 18, ATTR_ACCENT, str_start
    PUTS  2, 24, ATTR_DIM,    str_pad
    rts

splash_update:
    ; blink PRESS START on frame_cnt bit 5
    lda frame_cnt
    and #$20
    beq @dimmed
    PUTS 10, 18, ATTR_ACCENT, str_start
    bra @pads
@dimmed:
    PUTS 10, 18, ATTR_DIM,    str_start
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

str_title:    .DB "SNDJ", 0
str_subtitle: .DB "SNES/SFC MUSIC TRACKER", 0
str_family:   .DB "SIBLING OF SMSGGDJ + GENMDDJ", 0
str_start:    .DB "PRESS START", 0
str_pad:      .DB "PAD", 0
