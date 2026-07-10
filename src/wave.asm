; wave.asm — drawn wavetables (CLAUDE.md §8 WAVE): 8 banks x 32 samples
; (4-bit) in the song block, compiled on the fly into tiny looped BRRs
; (2 blocks, filter 0) and bulk-uploaded to the ARAM scratch slots at
; $1100. Directory entries 32-39 point at the slots, so WAV instruments
; play them as SRCN 32+bank and the B command wave-sequences per row.

.ACCU 8
.INDEX 16

.DEFINE WAVE_SLOT0   $1100      ; ARAM scratch (18 bytes per bank)
.DEFINE WAVE_SLOT_SZ 18
.DEFINE WAVE_SRCN0   56
.DEFINE WAVE_DIR     (ARAM_DIR + WAVE_SRCN0 * 4)
.DEFINE BRR_RANGE    11         ; nibble -8..7 -> +/-8192 (filter 0)

; --- seed the song block's wave banks from the ROM defaults --------------------
waves_seed:
    ldx #$0000
@copy:
    lda.l default_waves,x
    sta.l $7E0000 + SB_WAVES,x
    inx
    cpx #$0100
    bne @copy
    rts

; --- compile bank A (0-7) to BRR in str_buf and upload to its slot -------------
wave_compile:
    sta es1                 ; bank
    ; source offset: SB_WAVES + bank*32
    rep #$30
.ACCU 16
    and #$00FF
    xba
    lsr
    lsr
    lsr                     ; * 32
    clc
    adc #SB_WAVES
    tax
    sep #$20
.ACCU 8
    ; block 0 header: range 11, filter 0
    lda #(BRR_RANGE << 4)
    sta.w str_buf
    ; block 1 header: range 11, filter 0, LOOP+END
    lda #((BRR_RANGE << 4) | $03)
    sta.w str_buf + 9
    ; pack 32 samples as signed nibbles (value - 8)
    stz es0                 ; sample-pair counter (0-15)
@pair:
    lda.l $7E0000,x
    sec
    sbc #$08
    and #$0F
    asl
    asl
    asl
    asl
    sta es2                 ; high nibble
    inx
    lda.l $7E0000,x
    sec
    sbc #$08
    and #$0F
    ora es2
    sta es2                 ; packed byte
    inx
    phx
    lda es0
    rep #$30
.ACCU 16
    and #$00FF
    cmp #$0008
    bcc @blk0
    inc a                   ; skip the block-1 header byte at +9
@blk0:
    clc
    adc #(str_buf + 1)
    tax
    sep #$20
.ACCU 8
    lda es2
    sta.w $0000,x
    plx
    inc es0
    lda es0
    cmp #$10
    bne @pair
    ; upload the 18-byte BRR to this bank's scratch slot
    lda es1
    rep #$30
.ACCU 16
    and #$00FF
    sta es2
    asl
    asl
    asl
    asl                     ; * 16
    sta es3
    lda es2
    asl                     ; * 2
    clc
    adc es3
    clc
    adc #WAVE_SLOT0
    sta up_dest
    sep #$20
.ACCU 8
    ldx #str_buf
    stx up_src
    lda #$7E
    sta up_src + 2
    ldx #WAVE_SLOT_SZ
    stx up_len
    jmp apu_upload_block

; --- compile + upload all 8 banks (boot / song load) ----------------------------
; The directory goes FIRST: its 33-byte (3-padded) upload ends exactly on
; $1100, and bank 0's compile must overwrite that pad byte, not lose its
; BRR header to it.
wave_sync_all:
    ; directory entries 56-63 -> the scratch slots (start = loop)
    stz es0                 ; bank
@dir:
    lda es0
    rep #$30
.ACCU 16
    and #$00FF
    sta es1
    asl
    asl
    asl
    asl
    sta es2
    lda es1
    asl
    clc
    adc es2
    clc
    adc #WAVE_SLOT0
    sta es2                 ; slot address
    ; entry offset = bank*4
    lda es1
    asl
    asl
    clc
    adc #str_buf
    tax
    sep #$20
.ACCU 8
    lda es2
    sta.w $0000,x           ; start lo
    sta.w $0002,x           ; loop lo
    lda es2 + 1
    sta.w $0001,x           ; start hi
    sta.w $0003,x           ; loop hi
    inc es0
    lda es0
    cmp #$08
    bne @dir
    lda #$00
    sta.w str_buf + 32      ; pad to a multiple of 3 (33 bytes)
    ldx #str_buf
    stx up_src
    lda #$7E
    sta up_src + 2
    ldx #WAVE_DIR
    stx up_dest
    ldx #33
    stx up_len
    jsr apu_upload_block
    ; now the banks (bank 0 restores the byte the dir pad touched)
    stz sv_slot             ; bank loop counter (wave_compile eats es0-es3)
@bank:
    lda sv_slot
    jsr wave_compile
    inc sv_slot
    lda sv_slot
    cmp #$08
    bne @bank
    rts
