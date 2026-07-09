; palette.asm — runtime palette schemes (CLAUDE.md §6.1).
;
; 8 schemes live in the marker-wrapped SNPAL0 block (built by
; maketables.py, patchable in the ROM): 16 bytes each, little-endian
; 15-bit BGR words bg, text, dim, accent, hilite, grad top, grad bottom.
;
; palette_apply builds the 16-colour CGRAM image in pal_buf (the NMI
; drains it next VBlank — invariant #6) and regenerates the HDMA
; backdrop gradient table in WRAM by lerping grad top -> bottom over
; 224 lines with the 5A22 divider (apply time only, never per frame).
; The chosen scheme persists in the reserved SRAM header byte $0007.

.ACCU 8
.INDEX 16

.DEFINE GRAD_TAB   $7800     ; bank $7E: 224 x 5-byte HDMA entries + end
.DEFINE SRAM_OPTPAL $700007  ; reserved byte in the SRAM header

; scheme word offsets
.DEFINE PS_BG      0
.DEFINE PS_TEXT    2
.DEFINE PS_DIM     4
.DEFINE PS_ACCENT  6
.DEFINE PS_HILITE  8
.DEFINE PS_GTOP    10
.DEFINE PS_GBOT    12

; --- boot: pick the persisted scheme and build everything -----------------------
; Called under force-blank; writes CGRAM directly (no queue needed yet).
palette_boot:
    lda.l $700000           ; SRAM magic "SNDJ1"?
    cmp #'S'
    bne @default
    lda.l $700004
    cmp #'1'
    bne @default
    lda.l SRAM_OPTPAL
    and #$07
    bra @have
@default:
    lda #$00
@have:
    jsr palette_apply
    ; force-blank: write CGRAM 0-15 directly and clear the dirty flag
    stz CGADD
    ldx #$0000
@cg:
    lda.w pal_buf,x
    sta CGDATA
    inx
    cpx #$0020
    bne @cg
    stz pal_dirty
    rts

; --- select scheme A from the UI: apply + persist --------------------------------
palette_select:
    jsr palette_apply
    lda.l $700000
    cmp #'S'
    bne @done
    lda opt_pal
    sta.l SRAM_OPTPAL
@done:
    rts

; --- A = scheme 0-7: build pal_buf + the gradient table, set pal_dirty ----------
palette_apply:
    and #$07
    sta opt_pal
    ; X = scheme base (opt_pal * 16)
    rep #$30
.ACCU 16
    and #$00FF
    asl
    asl
    asl
    asl
    tax
    ; colour 0 = bg
    lda.l pal_schemes + PS_BG,x
    sta.w pal_buf + 0
    ; BG3 palette 0 (text): 1=dim, 2=text, 3=text
    lda.l pal_schemes + PS_DIM,x
    sta.w pal_buf + 2
    lda.l pal_schemes + PS_TEXT,x
    sta.w pal_buf + 4
    sta.w pal_buf + 6
    ; BG3 palette 1 (accent): 5=dim, 6=accent, 7=accent
    lda.l pal_schemes + PS_DIM,x
    sta.w pal_buf + 10
    lda.l pal_schemes + PS_ACCENT,x
    sta.w pal_buf + 12
    sta.w pal_buf + 14
    ; BG3 palette 2 (hilite): 9=dim, 10=hilite, 11=hilite
    lda.l pal_schemes + PS_DIM,x
    sta.w pal_buf + 18
    lda.l pal_schemes + PS_HILITE,x
    sta.w pal_buf + 20
    sta.w pal_buf + 22
    ; BG3 palette 3 (dim): 13, 14, 15 = dim
    lda.l pal_schemes + PS_DIM,x
    sta.w pal_buf + 26
    sta.w pal_buf + 28
    sta.w pal_buf + 30
    ; unused entries stay transparent-ish (bg)
    lda.l pal_schemes + PS_BG,x
    sta.w pal_buf + 8
    sta.w pal_buf + 16
    sta.w pal_buf + 24
    ; gradient endpoints
    lda.l pal_schemes + PS_GTOP,x
    sta gr_top
    lda.l pal_schemes + PS_GBOT,x
    sta gr_bot
    sep #$20
.ACCU 8
    jsr grad_build
    lda #$01
    sta pal_dirty
    rts

; --- build the HDMA gradient table at $7E:GRAD_TAB -------------------------------
; Per channel: 8.8 fixed-point accumulator from top, step = (bot-top)<<8/224
; (5A22 divider; sign handled by negate-divide-negate).
grad_build:
    ; unpack the two endpoint colours into 5-bit channels
    rep #$30
.ACCU 16
    lda gr_top
    and #$001F
    xba                     ; << 8
    sta gr_racc
    lda gr_bot
    and #$001F
    sta gr_tmp
    lda gr_top
    and #$001F
    jsr grad_step           ; A = end, gr_tmp = end; computes step from A(start)
    sta gr_rstep
    lda gr_top
    lsr
    lsr
    lsr
    lsr
    lsr
    and #$001F
    xba
    sta gr_gacc
    lda gr_bot
    lsr
    lsr
    lsr
    lsr
    lsr
    and #$001F
    sta gr_tmp
    lda gr_top
    lsr
    lsr
    lsr
    lsr
    lsr
    and #$001F
    jsr grad_step
    sta gr_gstep
    lda gr_top
    xba
    lsr
    lsr
    and #$001F
    xba
    sta gr_bacc
    lda gr_bot
    xba
    lsr
    lsr
    and #$001F
    sta gr_tmp
    lda gr_top
    xba
    lsr
    lsr
    and #$001F
    jsr grad_step
    sta gr_bstep
    ; fill 224 entries: [1, 0, 0, lo, hi]
    ldx #GRAD_TAB
    ldy #$00E0              ; 224 lines
    sep #$20
.ACCU 8
@line:
    lda #$01
    sta.l $7E0000,x
    inx
    lda #$00
    sta.l $7E0000,x
    inx
    sta.l $7E0000,x
    inx
    ; colour word = (b5 << 10) | (g5 << 5) | r5 from the accumulator highs
    rep #$30
.ACCU 16
    lda gr_bacc
    xba
    and #$001F
    asl
    asl
    asl
    asl
    asl
    sta gr_tmp
    lda gr_gacc
    xba
    and #$001F
    asl
    asl
    asl
    asl
    asl
    ora gr_tmp
    asl
    asl
    asl
    asl
    asl
    sta gr_tmp
    lda gr_racc
    xba
    and #$001F
    ora gr_tmp
    sep #$20
.ACCU 8
    sta.l $7E0000,x
    inx
    xba
    sta.l $7E0000,x
    inx
    ; advance the accumulators
    rep #$30
.ACCU 16
    lda gr_racc
    clc
    adc gr_rstep
    sta gr_racc
    lda gr_gacc
    clc
    adc gr_gstep
    sta gr_gacc
    lda gr_bacc
    clc
    adc gr_bstep
    sta gr_bacc
    dey
    sep #$20
.ACCU 8
    bne @line
    lda #$00
    sta.l $7E0000,x         ; HDMA end
    rts

; A (16-bit) = start channel, gr_tmp = end channel -> A = signed 8.8 step
; ((end - start) << 8) / 224 via the hardware divider.
.ACCU 16
grad_step:
    sta gr_tmp2
    lda gr_tmp
    sec
    sbc gr_tmp2             ; diff (signed, |diff| <= 31)
    bmi @neg
    xba                     ; << 8 (diff < 256)
    and #$FF00
    sep #$20
.ACCU 8
    sta.w WRDIVL            ; dividend low
    xba
    sta.w WRDIVH
    lda #224
    sta.w WRDIVB
    jsr div_wait
    rep #$30
.ACCU 16
    lda.w RDDIVL
    rts
@neg:
.ACCU 16
    eor #$FFFF
    inc a                   ; |diff|
    xba
    and #$FF00
    sep #$20
.ACCU 8
    sta.w WRDIVL
    xba
    sta.w WRDIVH
    lda #224
    sta.w WRDIVB
    jsr div_wait
    rep #$30
.ACCU 16
    lda.w RDDIVL
    eor #$FFFF
    inc a
    rts

.ACCU 8
div_wait:
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop                     ; 16 cycles > divider latency
    rts
