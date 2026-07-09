; nmi.asm — VBlank: shadow-map DMA, auto-joypad sample, frame flag.
; The sequencer never runs here (invariant #7); main loop work only.

.ACCU 8
.INDEX 16

Vec_NMI:
    jml @body               ; vector lands in the $00 slow mirror; hop to $80
@body:
    rep #$30
.ACCU 16
    pha
    phx
    phy
    phb
    phd
    lda #$0000
    tcd                     ; re-assert our direct page (invariant #8)
    sep #$20
.ACCU 8
    lda #$80
    pha
    plb

    lda RDNMI               ; acknowledge

    ; --- BG3 shadow tilemap -> VRAM (2 KB, ~0.8 ms of ~2.4 ms VBlank) ---
    lda #$80
    sta VMAIN
    ldx #VRAM_BG3_MAP
    stx VMADDL
    lda #$01                ; linear, 2 bytes -> $2118/19
    sta DMAP0
    lda #$18
    sta BBAD0
    ldx #SHADOW_BG3
    stx A1T0L
    lda #$7E
    sta A1B0
    ldx #$0800
    stx DAS0L
    lda #$01
    sta MDMAEN

    ; --- palette: drain pal_buf into CGRAM when a scheme was applied ---
    lda pal_dirty
    beq @no_pal
    stz CGADD
    ldx #$0000
@pal:
    lda.w pal_buf,x
    sta CGDATA
    inx
    cpx #$0020
    bne @pal
    stz pal_dirty
@no_pal:
    ; --- pads: wait for auto-read completion, then latch raw state ---
@joywait:
    lda HVBJOY
    and #$01
    bne @joywait
    rep #$20
.ACCU 16
    lda JOY1L
    and #$FFF0              ; mask controller-ID bits
    sta pad_raw
    inc frame_cnt
    sep #$20
.ACCU 8
    lda #$01
    sta frame_flag

    rep #$30
.ACCU 16
    pld
    plb
    ply
    plx
    pla
    rti
.ACCU 8
