; save.asm — SNDJ1 save/load (SAVEFORMAT.md owns the layout).
;
; Save: song block -> column-planar image at $7E:6000 -> RLE-pack straight
; into the free SRAM region (CRC as we go) -> flip the slot table entry
; (status byte last). Load: CRC pass over the packed bytes, refuse on
; mismatch, then unpack + un-planar. Journalled: 4 slots, 5 regions.

.ACCU 8
.INDEX 16

.DEFINE SRAM_MAGIC0  $700000
.DEFINE SRAM_TABLE   $700010
.DEFINE SRAM_DATA    $700100
.DEFINE REGION_SZ    $1880
.DEFINE SLOT_COUNT   4
.DEFINE REGION_COUNT 5
.DEFINE IMAGE        $8000       ; staging buffer in bank $7E (block ends $7300)
.DEFINE IMAGE_SZ     $5300

.DEFINE SV_OK        0
.DEFINE SV_FULL      1
.DEFINE SV_EMPTY     2
.DEFINE SV_BADCRC    3

; --- boot: format SRAM if the magic is missing ---------------------------------
sram_check:
    lda.l SRAM_MAGIC0
    cmp #'S'
    bne @format
    lda.l SRAM_MAGIC0 + 1
    cmp #'N'
    bne @format
    lda.l SRAM_MAGIC0 + 4
    cmp #'1'
    bne @format
    rts
@format:
    lda #'S'
    sta.l SRAM_MAGIC0
    lda #'N'
    sta.l SRAM_MAGIC0 + 1
    lda #'D'
    sta.l SRAM_MAGIC0 + 2
    lda #'J'
    sta.l SRAM_MAGIC0 + 3
    lda #'1'
    sta.l SRAM_MAGIC0 + 4
    lda #$01
    sta.l SRAM_MAGIC0 + 5
    ldx #$0000
    lda #$FF
@slots:
    sta.l SRAM_TABLE,x
    inx
    cpx #(SLOT_COUNT * 16)
    bne @slots
    rts

; --- song block <-> planar image at IMAGE -----------------------------------
; image = [4 phrase planes $C00][2 chain planes $600][rest of block $1700]
; (SAVEFORMAT.md v2). Table-driven: each pass de/interleaves one column.

stage_tab:  ; src offset (bank $7E), stride, image offset, plane length
    .DW SB_PHRASES + 0
    .DB 4
    .DW $0000, $0C00
    .DW SB_PHRASES + 1
    .DB 4
    .DW $0C00, $0C00
    .DW SB_PHRASES + 2
    .DB 4
    .DW $1800, $0C00
    .DW SB_PHRASES + 3
    .DB 4
    .DW $2400, $0C00
    .DW SB_CHAINS + 0
    .DB 2
    .DW $3000, $0600
    .DW SB_CHAINS + 1
    .DB 2
    .DW $3600, $0600

; pass sv_i (0-5) -> sv_src pointer, X = image offset, Y = length,
; sv_b = stride
stage_setup:
    lda sv_i
    rep #$30
.ACCU 16
    and #$00FF
    ; * 7 (table entry size)
    sta sv_chunk
    asl
    asl
    asl                     ; *8
    sec
    sbc sv_chunk            ; *7
    tax
    sep #$20
.ACCU 8
    lda.w stage_tab + 2,x
    sta sv_b                ; stride
    rep #$30
.ACCU 16
    lda.w stage_tab,x
    sta sv_src
    lda.w stage_tab + 5,x
    tay                     ; length
    lda.w stage_tab + 3,x
    tax                     ; image offset
    sep #$20
.ACCU 8
    lda #$7E
    sta sv_src + 2
    rts

stage_out:
    stz sv_i
@pass:
    jsr stage_setup
@plane:
    lda [sv_src]
    sta.l $7E0000 + IMAGE,x
    rep #$20
.ACCU 16
    lda sv_b
    and #$00FF
    clc
    adc sv_src
    sta sv_src
    sep #$20
.ACCU 8
    inx
    dey
    bne @plane
    inc sv_i
    lda sv_i
    cmp #$06
    bne @pass
    ldx #$0000
@rest:
    lda.l $7E0000 + SB,x
    sta.l $7E0000 + IMAGE + $3C00,x
    inx
    cpx #(SB_CHAINS - SB)
    bne @rest
    rts

stage_in:
    stz sv_i
@pass:
    jsr stage_setup
@plane:
    lda.l $7E0000 + IMAGE,x
    sta [sv_src]
    rep #$20
.ACCU 16
    lda sv_b
    and #$00FF
    clc
    adc sv_src
    sta sv_src
    sep #$20
.ACCU 8
    inx
    dey
    bne @plane
    inc sv_i
    lda sv_i
    cmp #$06
    bne @pass
    ldx #$0000
@rest:
    lda.l $7E0000 + IMAGE + $3C00,x
    sta.l $7E0000 + SB,x
    inx
    cpx #(SB_CHAINS - SB)
    bne @rest
    rts

; --- CRC-16/CCITT: update sv_crc with byte A ------------------------------------
crc16_update:
    rep #$20
.ACCU 16
    and #$00FF
    xba                     ; byte << 8
    eor sv_crc
    sta sv_crc
    sep #$20
.ACCU 8
    phy
    ldy #$0008
@bit:
    rep #$20
.ACCU 16
    lda sv_crc
    asl
    sta sv_crc
    sep #$20
.ACCU 8
    bcc @no_poly
    rep #$20
.ACCU 16
    lda sv_crc
    eor #$1021
    sta sv_crc
    sep #$20
.ACCU 8
@no_poly:
    dey
    bne @bit
    ply
    rts

; --- emit packed byte A -> [sv_dst]; CRC + size + region-overflow tracking ------
sv_emit:
    pha
    rep #$20
.ACCU 16
    lda sv_size
    cmp #REGION_SZ
    sep #$20
.ACCU 8
    bcc @fits
    pla
    lda #$01
    sta sv_ovf
    rts
@fits:
    pla
    sta [sv_dst]
    pha
    rep #$20
.ACCU 16
    inc sv_dst
    inc sv_size
    sep #$20
.ACCU 8
    pla
    jmp crc16_update

; --- read packed byte [sv_src] -> A ----------------------------------------------
sv_getc:
    lda [sv_src]
    pha
    rep #$20
.ACCU 16
    inc sv_src
    sep #$20
.ACCU 8
    pla
    rts

; --- flush pending literals [sv_lit, sv_i) ----------------------------------------
pack_flush_lit:
    rep #$20
.ACCU 16
    lda sv_i
    cmp sv_lit
    sep #$20
.ACCU 8
    bne @chunk
    rts
@chunk:
    ; chunk = min(128, sv_i - sv_lit)
    rep #$20
.ACCU 16
    lda sv_i
    sec
    sbc sv_lit
    cmp #$0081
    bcc @sz_ok
    lda #$0080
@sz_ok:
    sta sv_chunk
    sep #$20
.ACCU 8
    lda sv_chunk
    dec a
    jsr sv_emit             ; control: count-1
@bytes:
    ldx sv_lit
    lda.l $7E0000 + IMAGE,x
    jsr sv_emit
    rep #$20
.ACCU 16
    inc sv_lit
    dec sv_chunk
    sep #$20
.ACCU 8
    bne @bytes
    rep #$20
.ACCU 16
    lda sv_i
    cmp sv_lit
    sep #$20
.ACCU 8
    bne @chunk
    rts

; --- RLE-pack the image via sv_emit ------------------------------------------------
rle_pack:
    stz sv_ovf
    rep #$30
.ACCU 16
    lda #$0000
    sta sv_i
    sta sv_lit
    sep #$20
.ACCU 8
@loop:
    lda sv_ovf
    beq @go
    rts                     ; overflowed the region: caller reports FULL
@go:
    rep #$20
.ACCU 16
    lda sv_i
    cmp #IMAGE_SZ
    sep #$20
.ACCU 8
    bcc @more
    jmp pack_flush_lit      ; flush the tail and return
@more:
    ; count the run at sv_i (max 130, bounded by the image end)
    ldx sv_i
    lda.l $7E0000 + IMAGE,x
    sta sv_b
    lda #$01
    sta sv_run
@count:
    lda sv_run
    cmp #130
    bcs @counted
    rep #$30
.ACCU 16
    lda sv_run
    and #$00FF
    clc
    adc sv_i
    cmp #IMAGE_SZ
    bcs @counted16
    tax
    sep #$20
.ACCU 8
    lda.l $7E0000 + IMAGE,x
    cmp sv_b
    bne @counted
    inc sv_run
    bra @count
@counted16:
.ACCU 16
    sep #$20
.ACCU 8
@counted:
    lda sv_run
    cmp #$03
    bcc @literal
    ; run: flush literals, emit token + byte, advance
    jsr pack_flush_lit
    lda sv_run
    clc
    adc #$7D                ; $80 + run - 3
    jsr sv_emit
    lda sv_b
    jsr sv_emit
    rep #$20
.ACCU 16
    lda sv_run
    and #$00FF
    clc
    adc sv_i
    sta sv_i
    sta sv_lit
    sep #$20
.ACCU 8
    jmp @loop
@literal:
    ; short run: leave it pending as literals
    rep #$20
.ACCU 16
    lda sv_run
    and #$00FF
    clc
    adc sv_i
    sta sv_i
    sep #$20
.ACCU 8
    jmp @loop

; --- RLE-unpack [sv_src] -> image --------------------------------------------------
rle_unpack:
    ldx #$0000
@loop:
    cpx #IMAGE_SZ
    bcs @done
    jsr sv_getc
    cmp #$80
    bcs @run
    ; literals: c+1 bytes
    inc a
    sta sv_run
@lit:
    jsr sv_getc
    sta.l $7E0000 + IMAGE,x
    inx
    dec sv_run
    bne @lit
    bra @loop
@run:
    sec
    sbc #$7D                ; count = c - $80 + 3
    sta sv_run
    jsr sv_getc
    sta sv_b
@rep:
    lda sv_b
    sta.l $7E0000 + IMAGE,x
    inx
    dec sv_run
    bne @rep
    bra @loop
@done:
    rts

; --- point sv_dst / sv_src at region A's data -------------------------------------
region_ptr:
    rep #$30
.ACCU 16
    and #$00FF
    ; * $1880
    sta sv_chunk
    xba
    asl
    asl
    asl
    asl                     ; * $1000
    sta sv_i
    lda sv_chunk
    xba
    lsr                     ; * $80... careful: recompute cleanly below
    sep #$20
.ACCU 8
    ; sv_i = region * $1000; add region * $800 and region * $80
    rep #$30
.ACCU 16
    lda sv_chunk
    xba
    lsr                     ; * $80
    clc
    adc sv_i
    sta sv_i
    lda sv_chunk
    xba
    asl
    asl
    asl                     ; * $800
    clc
    adc sv_i
    clc
    adc #$0100              ; data base offset
    sta sv_i
    sep #$20
.ACCU 8
    rts

; --- save to slot A (0-3); returns A = SV_* status --------------------------------
save_slot:
    sta sv_slot
    jsr stage_out
    ; find a region not referenced by any valid slot entry
    stz sv_region
@try_region:
    ldy #$0000              ; slot counter
@scan:
    rep #$30
.ACCU 16
    tya
    asl
    asl
    asl
    asl
    tax
    sep #$20
.ACCU 8
    lda.l SRAM_TABLE,x      ; status
    cmp #$A5
    bne @next_slot
    lda.l SRAM_TABLE + 1,x  ; region
    cmp sv_region
    beq @region_used
@next_slot:
    iny
    cpy #SLOT_COUNT
    bne @scan
    bra @region_free
@region_used:
    inc sv_region
    lda sv_region
    cmp #REGION_COUNT
    bcc @try_region
    lda #SV_FULL            ; can't happen (5 regions, 4 slots), but be safe
    rts
@region_free:
    ; set up the write pointer + counters
    lda sv_region
    jsr region_ptr          ; sv_i = SRAM offset of the region
    rep #$30
.ACCU 16
    lda sv_i
    sta sv_dst
    lda #$FFFF
    sta sv_crc
    lda #$0000
    sta sv_size
    sep #$20
.ACCU 8
    lda #$70
    sta sv_dst + 2
    jsr rle_pack
    lda sv_ovf
    beq @packed
    lda #SV_FULL
    rts
@packed:
    ; flip the table entry: everything first, status byte last
    lda sv_slot
    rep #$30
.ACCU 16
    and #$00FF
    asl
    asl
    asl
    asl
    tax
    sep #$20
.ACCU 8
    lda sv_region
    sta.l SRAM_TABLE + 1,x
    lda sv_size
    sta.l SRAM_TABLE + 2,x
    lda sv_size + 1
    sta.l SRAM_TABLE + 3,x
    lda sv_crc
    sta.l SRAM_TABLE + 4,x
    lda sv_crc + 1
    sta.l SRAM_TABLE + 5,x
    ; name: "SONG" + slot digit + spaces
    lda #'S'
    sta.l SRAM_TABLE + 6,x
    lda #'O'
    sta.l SRAM_TABLE + 7,x
    lda #'N'
    sta.l SRAM_TABLE + 8,x
    lda #'G'
    sta.l SRAM_TABLE + 9,x
    lda sv_slot
    clc
    adc #'0'
    sta.l SRAM_TABLE + 10,x
    lda #' '
    sta.l SRAM_TABLE + 11,x
    sta.l SRAM_TABLE + 12,x
    sta.l SRAM_TABLE + 13,x
    lda #$A5
    sta.l SRAM_TABLE,x      ; the atomic flip
    lda #SV_OK
    rts

; --- load slot A (0-3); returns A = SV_* status ------------------------------------
load_slot:
    sta sv_slot
    rep #$30
.ACCU 16
    and #$00FF
    asl
    asl
    asl
    asl
    tax
    sep #$20
.ACCU 8
    lda.l SRAM_TABLE,x
    cmp #$A5
    beq @valid
    lda #SV_EMPTY
    rts
@valid:
    lda.l SRAM_TABLE + 1,x
    sta sv_region
    lda.l SRAM_TABLE + 2,x
    sta sv_size
    lda.l SRAM_TABLE + 3,x
    sta sv_size + 1
    lda.l SRAM_TABLE + 4,x
    sta es2                 ; expected CRC (region_ptr scratches sv_chunk)
    lda.l SRAM_TABLE + 5,x
    sta es2 + 1
    ; CRC pass over the packed bytes
    lda sv_region
    jsr region_ptr
    rep #$30
.ACCU 16
    lda sv_i
    sta sv_src
    lda #$FFFF
    sta sv_crc
    sep #$20
.ACCU 8
    lda #$70
    sta sv_src + 2
    rep #$30
.ACCU 16
    ldy sv_size
    sep #$20
.ACCU 8
    cpy #$0000
    beq @crc_done
@crc_loop:
    jsr sv_getc
    jsr crc16_update
    dey
    bne @crc_loop
@crc_done:
    rep #$20
.ACCU 16
    lda sv_crc
    cmp es2
    sep #$20
.ACCU 8
    beq @crc_ok
    lda #SV_BADCRC
    rts
@crc_ok:
    ; unpack for real
    lda eng_playing
    beq @stopped
    jsr engine_stop
@stopped:
    lda sv_region
    jsr region_ptr
    rep #$30
.ACCU 16
    lda sv_i
    sta sv_src
    sep #$20
.ACCU 8
    lda #$70
    sta sv_src + 2
    jsr rle_unpack
    jsr stage_in
    jsr wave_sync_all       ; the loaded song's waves come back with it
    jsr apu_echo_apply      ; ...and its room (long sequence last)
    lda #SV_OK
    rts
