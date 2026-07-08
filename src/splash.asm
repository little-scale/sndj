; splash.asm — boot splash (build stamp, pad echo) + M1 cursor-grid stub.
; The stub SONG grid exists to exercise input/DAS end-to-end; the real SONG
; screen replaces it in M5.

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
    jsr stub_init
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

; ---------------------------------------------------------------------------
; M1 stub: an 8x16 grid of empty cells with a DAS-driven cursor.
; ---------------------------------------------------------------------------

.DEFINE STUB_COLS 8
.DEFINE STUB_ROWS 16

stub_init:
    lda #$01
    sta ui_mode
    stz cur_x
    stz cur_y
    jsr text_clear
    PUTS 1, 1, ATTR_TEXT, str_song
    PUTS 8, 1, ATTR_DIM,  str_stub
    ; track headers
    lda #$00
    sta tmp2                ; col
@heads:
    lda tmp2
    asl
    clc
    adc tmp2
    adc #3                  ; x = 3 + col*3
    sta text_x
    lda #3
    sta text_y
    SETATTR ATTR_HILITE
    lda #'V' - 32
    jsr text_puttile
    lda tmp2
    clc
    adc #'1' - 32
    jsr text_puttile
    inc tmp2
    lda tmp2
    cmp #STUB_COLS
    bne @heads
    ; row labels + cells
    stz tmp2 + 1            ; row
@rows:
    lda #1
    sta text_x
    lda tmp2 + 1
    clc
    adc #4
    sta text_y
    SETATTR ATTR_DIM
    lda tmp2 + 1
    jsr text_hex8
    stz tmp2                ; col
@cells:
    jsr stub_drawcell
    inc tmp2
    lda tmp2
    cmp #STUB_COLS
    bne @cells
    inc tmp2 + 1
    lda tmp2 + 1
    cmp #STUB_ROWS
    bne @rows
    jsr stub_cursor
    rts

; draw cell at col=tmp2, row=tmp2+1 with current text_attr
stub_drawcell:
    lda tmp2
    asl
    clc
    adc tmp2
    adc #4                  ; x = 4 + col*3
    sta text_x
    lda tmp2 + 1
    clc
    adc #4                  ; y = 4 + row
    sta text_y
    lda #'-' - 32
    jsr text_puttile
    lda #'-' - 32
    jsr text_puttile
    rts

; repaint cursor cell with accent
stub_cursor:
    lda cur_x
    sta tmp2
    lda cur_y
    sta tmp2 + 1
    SETATTR ATTR_ACCENT
    jsr stub_drawcell
    rts

; repaint cell under cursor as normal (before moving)
stub_uncursor:
    lda cur_x
    sta tmp2
    lda cur_y
    sta tmp2 + 1
    SETATTR ATTR_DIM
    jsr stub_drawcell
    rts

stub_update:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_DPAD
    sep #$20
.ACCU 8
    beq @done
    jsr stub_uncursor
    ; horizontal
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_LEFT
    sep #$20
.ACCU 8
    beq @notleft
    lda cur_x
    beq @notleft
    dec cur_x
@notleft:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_RIGHT
    sep #$20
.ACCU 8
    beq @notright
    lda cur_x
    cmp #STUB_COLS - 1
    bcs @notright
    inc cur_x
@notright:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_UP
    sep #$20
.ACCU 8
    beq @notup
    lda cur_y
    beq @notup
    dec cur_y
@notup:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_DOWN
    sep #$20
.ACCU 8
    beq @notdown
    lda cur_y
    cmp #STUB_ROWS - 1
    bcs @notdown
    inc cur_y
@notdown:
    jsr stub_cursor
@done:
    rts

str_title:    .DB "SNESDJ", 0
str_subtitle: .DB "SNES/SFC MUSIC TRACKER", 0
str_family:   .DB "SIBLING OF SMSGGDJ + GENMDDJ", 0
str_start:    .DB "PRESS START", 0
str_pad:      .DB "PAD", 0
str_song:     .DB "SONG", 0
str_stub:     .DB "M1 INPUT STUB", 0
