; palette.asm — runtime palette schemes (CLAUDE.md §6.1).
;
; 8 schemes live in the marker-wrapped SNPAL0 block (built by
; maketables.py, patchable in the ROM): 16 bytes each, little-endian
; 15-bit BGR words bg, text, dim, accent, hilite (rest padding).
;
; palette_apply builds the 16-colour CGRAM image in pal_buf; the NMI
; drains it next VBlank (invariant #6). Solid backdrop, no gradient.
; The chosen scheme persists in the reserved SRAM header byte $0007.

.ACCU 8
.INDEX 16

.DEFINE SRAM_OPTPAL $700007  ; reserved byte in the SRAM header

; scheme word offsets
.DEFINE PS_BG      0
.DEFINE PS_TEXT    2
.DEFINE PS_DIM     4
.DEFINE PS_ACCENT  6
.DEFINE PS_HILITE  8

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
    sep #$20
.ACCU 8
    lda #$01
    sta pal_dirty
    rts
