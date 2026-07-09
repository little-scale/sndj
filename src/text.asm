; text.asm — text rendering into the BG3 shadow tilemap.
; All routines assume A8 X16, DB=$80, D=$0000. The shadow map lives in WRAM;
; NMI DMAs it to VRAM each frame, so nothing here touches the PPU.

.ACCU 8
.INDEX 16

; Fill the whole shadow map with spaces (palette 0, priority).
text_clear:
    rep #$30
.ACCU 16
    lda #ATTR_TEXT          ; tile 0 = space
    ldx #$0000
@loop:
    sta.w SHADOW_BG3,x
    inx
    inx
    cpx #$0800
    bne @loop
    sep #$20
.ACCU 8
    rts

; Compute shadow byte offset from text_x/text_y -> X.
; Relies on text_y living directly after text_x.
text_dest:
    rep #$30
.ACCU 16
    lda text_x              ; lo = x, hi = y
    pha
    and #$FF00
    lsr
    lsr                     ; y*64
    sta tmp1
    pla
    and #$00FF
    asl                     ; x*2
    ora tmp1                ; disjoint bits: x*2 <= 62
    tax
    sep #$20
.ACCU 8
    rts

; Print NUL-terminated string. X = string address (in DB), text_x/y = position,
; text_attr = tilemap attribute bits. Advances text_x by the string length.
text_puts:
    stx tmp0
    jsr text_dest
    txy
    ldx tmp0
@loop:
    lda.w $0000,x
    beq @done
    cmp #'a'
    bcc @upper
    sbc #32                 ; fold lowercase (git hashes) to uppercase
@upper:
    sec
    sbc #32
    rep #$20
.ACCU 16
    and #$00FF
    ; accent + hilite draw as negatives (inverted glyph set at +96)
    pha
    lda text_attr
    cmp #ATTR_ACCENT
    beq @inv
    cmp #ATTR_HILITE
    beq @inv
    pla
    bra @pl
@inv:
    pla
    clc
    adc #96
@pl:
    ora text_attr
    sta.w SHADOW_BG3,y
    sep #$20
.ACCU 8
    inx
    iny
    iny
    inc text_x
    bra @loop
@done:
    rts

; Print a single glyph. A = raw tile index, position/attr as text_puts.
; Advances text_x.
text_puttile:
    pha
    jsr text_dest
    pla
    rep #$20
.ACCU 16
    and #$00FF
    ; accent + hilite draw as negatives (inverted glyph set at +96)
    pha
    lda text_attr
    cmp #ATTR_ACCENT
    beq @invert
    cmp #ATTR_HILITE
    beq @invert
    pla
    bra @plain
@invert:
    pla
    clc
    adc #96
@plain:
    ora text_attr
    sta.w SHADOW_BG3,x
    sep #$20
.ACCU 8
    inc text_x
    rts

; Print A as two uppercase hex digits at text_x/y. Advances text_x by 2.
text_hex8:
    pha
    lsr
    lsr
    lsr
    lsr
    jsr @digit
    pla
    and #$0F
@digit:
    cmp #10
    bcc @num
    adc #6                  ; carry set: +7 total ('A'-'0'-10)
@num:
    adc #'0'
    sec
    sbc #32                 ; to tile index
    jmp text_puttile
