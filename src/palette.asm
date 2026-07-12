; palette.asm — runtime palette schemes (CLAUDE.md §6.1).
;
; 8 schemes live in the marker-wrapped SNPAL0 block (built by
; maketables.py, patchable in the ROM): 16 bytes each, little-endian
; 15-bit BGR words bg, text (rest padding). Two colours per scheme,
; genmddj-style: cursors/playheads render as palette negatives (the
; inverted glyph set). No midpoint/dim colour is synthesized: every
; visible pixel is exactly bg or text for composite/RF readability.
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

; --- boot: pick the persisted scheme and build everything -----------------------
; Called under force-blank; writes CGRAM directly (no queue needed yet).
palette_boot:
    lda.l $700000           ; SRAM magic "SNDJ1"?
    cmp #'S'
    bne @default
    lda.l $700004
    cmp #'1'
    bne @default
    lda.l $700008           ; CLONE: SLIM/DEEP persists next door
    cmp #$02                ; unwritten SRAM reads $FF: default DEEP
    bcs @clone_def
    sta opt_clone
    bra @clone_ok
@clone_def:
    lda #$01                ; DEEP is the default (Seb, 2026-07-12)
    sta opt_clone
@clone_ok:
    lda.l SRAM_OPTPAL
    cmp #$08                ; unwritten SRAM reads $FF ($FF & 7 = the
    bcc @have               ; "palette 7 on every reset" hardware bug)
    lda #$00
    bra @have
@default:
    lda #$01                ; DEEP is the default clone depth
    sta opt_clone
    lda #$00
@have:
    jsr palette_apply
    ; force-blank: write CGRAM 0-19 directly and clear the dirty flag
    stz CGADD
    ldx #$0000
@cg:
    lda.w pal_buf,x
    sta CGDATA
    inx
    cpx #$0020
    bne @cg
    lda #$10
    sta CGADD               ; colours 16-19: the ATTR_PLAY palette
    ldx #$0000
@cg2:
    lda.w pal_buf2,x
    sta CGDATA
    inx
    cpx #$0008
    bne @cg2
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

; --- A = scheme 0-7: build pal_buf, set pal_dirty ---------------------------------
; Line layout (normal glyphs ink with colour 3; inverted glyphs ink
; with colour 1 on a colour-3 field):
;   line 0 TEXT    1=bg  2=text 3=text
;   line 1 ACCENT  (negative) same colours as line 0
;   line 2 HILITE  (negative) same colours as line 0
;   line 3 DIM     1=bg  2=text 3=text  (semantic only; full contrast)
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
    ; lines 0-2: 1=bg, 2=text, 3=text
    lda.l pal_schemes + PS_BG,x
    sta.w pal_buf + 2
    sta.w pal_buf + 10
    sta.w pal_buf + 18
    lda.l pal_schemes + PS_TEXT,x
    sta.w pal_buf + 4
    sta.w pal_buf + 6
    sta.w pal_buf + 12
    sta.w pal_buf + 14
    sta.w pal_buf + 20
    sta.w pal_buf + 22
    ; line 3: DIM retains its semantic attribute but renders full-contrast
    lda.l pal_schemes + PS_BG,x
    sta.w pal_buf + 26
    lda.l pal_schemes + PS_TEXT,x
    sta.w pal_buf + 28
    sta.w pal_buf + 30
    ; colours 4/8/12 stay at bg
    lda.l pal_schemes + PS_BG,x
    sta.w pal_buf + 8
    sta.w pal_buf + 16
    sta.w pal_buf + 24
    ; palette 4 (ATTR_PLAY): same two-colour negative as the cursor
    sta.w pal_buf2 + 0      ; colour 16 (unused by glyphs; keep bg)
    sta.w pal_buf2 + 2      ; inverted glyph ink = bg
    lda.l pal_schemes + PS_TEXT,x
    sta.w pal_buf2 + 4
    sta.w pal_buf2 + 6      ; inverted glyph field = text
    sep #$20
.ACCU 8
    lda #$01
    sta pal_dirty
    rts
