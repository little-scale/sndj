; save.asm — SNDJ1 v2 save/load (SAVEFORMAT.md owns the layout).
;
; genmddj-style variable packing: a 16-entry directory at $0010 and one
; contiguous heap of RLE-packed songs at $0110-$7FFF. Valid entries are
; packed (0..used-1) and their heap blocks stay contiguous in entry
; order; SAVE appends at the free end then flips the entry, CLEAR and
; overwrites close the hole by sliding the tail down (per-song CRCs
; guard a power cut mid-slide). Entry: status, offset16, size16, crc16,
; rsvd, name8.

.ACCU 8
.INDEX 16

.DEFINE SRAM_MAGIC0  $700000
.DEFINE SRAM_TABLE   $700010
.DEFINE SRAM_HEAP    $700110
.DEFINE HEAP_SZ      $7EF0
.DEFINE SLOT_COUNT   16
.DEFINE IMAGE        $8000       ; staging buffer in bank $7E (block ends $7300)
.DEFINE IMAGE_SZ     $5300

.DEFINE SV_OK        0
.DEFINE SV_FULL      1
.DEFINE SV_EMPTY     2
.DEFINE SV_BADCRC    3
.DEFINE SV_FREED     4

; --- boot: format SRAM if the magic or version is wrong --------------------------
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
    lda.l SRAM_MAGIC0 + 5
    cmp #$02
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
    lda #$02
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

; --- emit packed byte A -> [sv_dst]; CRC + size + budget tracking ----------------
sv_emit:
    pha
    rep #$20
.ACCU 16
    lda sv_size
    cmp sv_limit
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

; --- helpers ----------------------------------------------------------------------
; A = slot -> X = its directory entry offset (slot * 16)
dir_x:
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
    rts

; free heap offset (= offset+size of the last valid entry) -> sv_i (16-bit)
heap_free:
    rep #$30
.ACCU 16
    lda #$0000
    sta sv_i
    sep #$20
.ACCU 8
    ldy #$0000
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
    lda.l SRAM_TABLE,x
    cmp #$A5
    bne @next
    ; end = offset + size; track the max (entries are contiguous, so
    ; the last valid entry's end IS the free offset)
    rep #$30
.ACCU 16
    lda.l SRAM_TABLE + 1,x
    clc
    adc.l SRAM_TABLE + 3,x
    cmp sv_i
    bcc +
    sta sv_i
+
    sep #$20
.ACCU 8
@next:
    iny
    cpy #SLOT_COUNT
    bne @scan
    rts

; close a heap hole at sv_hole (size sv_hsize): slide everything above
; it down, then shrink the offsets of entries past the hole
heap_close:
    rep #$30
.ACCU 16
    lda sv_hsize
    bne +
    sep #$20
.ACCU 8
    rts
+
.ACCU 16
    ; bytes to move = free_end - (hole + size)
    sep #$20
.ACCU 8
    jsr heap_free
    rep #$30
.ACCU 16
    ; tail above the hole = free_end - (hole + size); when the hole is
    ; the last block there is nothing to slide (and an unsigned
    ; underflow here once marched the move loop through all of SRAM)
    lda sv_i
    sec
    sbc sv_hole
    bcc @nothing_above
    sec
    sbc sv_hsize
    bcc @nothing_above
    beq @nothing_above
    sta sv_mlen
    bra @have_len
@nothing_above:
    sep #$20
.ACCU 8
    rts
@have_len:
.ACCU 16
    ; src = HEAP + hole + hsize, dst = HEAP + hole (forward copy, down)
    lda sv_hole
    clc
    adc sv_hsize
    clc
    adc #$0110
    sta sv_src
    lda sv_hole
    clc
    adc #$0110
    sta sv_dst
    sep #$20
.ACCU 8
    lda #$70
    sta sv_src + 2
    sta sv_dst + 2
    rep #$30
.ACCU 16
    ldy sv_mlen
    sep #$20
.ACCU 8
    cpy #$0000
    beq @moved
@mv:
    lda [sv_src]
    sta [sv_dst]
    rep #$30
.ACCU 16
    inc sv_src
    inc sv_dst
    sep #$20
.ACCU 8
    dey
    bne @mv
@moved:
    ; every entry above the hole shifts down by hsize
    ldy #$0000
@fix:
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
    lda.l SRAM_TABLE,x
    cmp #$A5
    bne @f_next
    rep #$30
.ACCU 16
    lda.l SRAM_TABLE + 1,x
    cmp sv_hole
    bcc +
    beq +
    sec
    sbc sv_hsize
    sta.l SRAM_TABLE + 1,x
+
    sep #$20
.ACCU 8
@f_next:
    iny
    cpy #SLOT_COUNT
    bne @fix
    rts

; --- save to slot A (0-15); returns A = SV_* status --------------------------------
save_slot:
    sta sv_slot
    jsr stage_out
    ; pack budget = heap size - current free offset
    jsr heap_free
    rep #$30
.ACCU 16
    lda #HEAP_SZ
    sec
    sbc sv_i
    sta sv_limit
    ; write pointer = heap free end
    lda sv_i
    pha
    clc
    adc #$0110
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
    rep #$30
.ACCU 16
    ply                     ; the new block's heap offset
    sep #$20
.ACCU 8
    lda sv_ovf
    beq @packed
    lda #SV_FULL            ; didn't fit above the live data
    rts
@packed:
    ; remember the OLD block (it becomes a hole after the flip)
    lda sv_slot
    jsr dir_x
    lda.l SRAM_TABLE,x
    cmp #$A5
    beq @had_old
    rep #$30
.ACCU 16
    lda #$0000
    sta sv_hsize
    sep #$20
.ACCU 8
    bra @flip
@had_old:
    rep #$30
.ACCU 16
    lda.l SRAM_TABLE + 1,x
    sta sv_hole
    lda.l SRAM_TABLE + 3,x
    sta sv_hsize
    sep #$20
.ACCU 8
@flip:
    ; entry: offset (the appended block), size, crc, name, status last
    rep #$30
.ACCU 16
    tya
    sta.l SRAM_TABLE + 1,x
    lda sv_size
    sta.l SRAM_TABLE + 3,x
    lda sv_crc
    sta.l SRAM_TABLE + 5,x
    sep #$20
.ACCU 8
    ; name travels from the song header
    ldy #$0000
@name_cp:
    phx
    rep #$30
.ACCU 16
    tyx
    sep #$20
.ACCU 8
    lda.l $7E0000 + SB_HEADER + SH_NAME,x
    plx
    sta.l SRAM_TABLE + 8,x
    inx
    iny
    cpy #$0008
    bne @name_cp
    rep #$30
.ACCU 16
    txa
    sec
    sbc #$0008
    tax
    sep #$20
.ACCU 8
    lda #$A5
    sta.l SRAM_TABLE,x      ; the atomic flip
    ; an overwrite leaves the old block as a hole: close it
    jsr heap_close
    lda #SV_OK
    rts

; --- clear slot A (0-15): drop the entry, slide the directory + heap -------------
slot_clear:
    sta sv_slot
    jsr dir_x
    lda.l SRAM_TABLE,x
    cmp #$A5
    beq @valid
    lda #SV_OK
    rts
@valid:
    ; the freed block becomes the hole
    rep #$30
.ACCU 16
    lda.l SRAM_TABLE + 1,x
    sta sv_hole
    lda.l SRAM_TABLE + 3,x
    sta sv_hsize
    sep #$20
.ACCU 8
    lda #$FF
    sta.l SRAM_TABLE,x
    ; slide later entries down one slot so the directory stays packed
    ; (16 bytes each; the status byte moves last, source freed after)
    lda sv_slot
    sta sv_run              ; dst entry index
@shift:
    lda sv_run
    cmp #(SLOT_COUNT - 1)
    bcs @shifted
    lda sv_run
    jsr dir_x               ; X = dst entry base
    lda.l SRAM_TABLE + 16,x
    cmp #$A5
    bne @shifted            ; packed directory: first free ends the run
    lda #$0F
    sta tmp2
@cp:
    phx
    rep #$30
.ACCU 16
    lda tmp2
    and #$00FF
    sta tmp0
    txa
    clc
    adc tmp0
    clc
    adc #$0010
    tax
    sep #$20
.ACCU 8
    lda.l SRAM_TABLE,x      ; source byte (entry n+1)
    pha
    rep #$30
.ACCU 16
    txa
    sec
    sbc #$0010
    tax
    sep #$20
.ACCU 8
    pla
    sta.l SRAM_TABLE,x      ; dest byte (entry n)
    plx
    dec tmp2
    bpl @cp
    ; release the source entry
    rep #$30
.ACCU 16
    txa
    clc
    adc #$0010
    tax
    sep #$20
.ACCU 8
    lda #$FF
    sta.l SRAM_TABLE,x
    inc sv_run
    bra @shift
@shifted:
    jsr heap_close
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
    rep #$30
.ACCU 16
    lda.l SRAM_TABLE + 3,x
    sta sv_size
    lda.l SRAM_TABLE + 5,x
    sta es2                 ; expected CRC
    lda.l SRAM_TABLE + 1,x
    clc
    adc #$0110              ; heap base
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
    lda sv_slot
    jsr dir_x
    rep #$30
.ACCU 16
    lda.l SRAM_TABLE + 1,x
    clc
    adc #$0110
    sta sv_src
    sep #$20
.ACCU 8
    lda #$70
    sta sv_src + 2
    jsr rle_unpack
    jsr stage_in
    jsr wave_sync_all       ; the loaded song's waves come back with it
    jsr residency_build     ; ...its resident sample set
    jsr apu_echo_apply      ; ...and its room (long sequence last)
    lda #SV_OK
    rts
