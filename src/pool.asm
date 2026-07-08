; pool.asm — parse the self-describing ROM sample pool, upload every BRR to
; ARAM (sequential from ARAM_SAMPLES), and build the directory entries.
; Songs will reference by name+hash later (M15); the runtime uses indices.

.ACCU 8
.INDEX 16

; carry set on failure
pool_upload:
    ; sanity: entry count
    lda.l pool_data + 9
    beq @bad_near
    cmp #33
    bcc @count_ok
@bad_near:
    sec
    rts
@count_ok:
    sta pool_count
    ; ARAM write cursor
    ldx #ARAM_SAMPLES
    stx es3
    stz es2                 ; entry index
@entry:
    ; table entry address -> X (pool_data + 16 + i*16)
    lda es2
    rep #$30
.ACCU 16
    and #$00FF
    asl
    asl
    asl
    asl
    clc
    adc #$0010              ; table starts at +16
    tax                     ; X = entry offset within the pool image
    sep #$20
.ACCU 8
    lda #:pool_data
    sta up_src + 2
    ; up_src = pool_data + entry.offset ; up_len = entry.size (mult of 9)
    rep #$30
.ACCU 16
    lda.l pool_data + 8,x   ; BRR offset within the pool image
    clc
    adc #pool_data
    sta up_src
    lda.l pool_data + 10,x  ; BRR byte length
    sta up_len
    lda es3
    sta up_dest
    sep #$20
.ACCU 8
    ; directory entry i in str_buf: start, loop (start + loopblk*9)
    phx
    lda es2
    rep #$30
.ACCU 16
    and #$00FF
    asl
    asl
    clc
    adc #str_buf
    tay                     ; dir entry dest in str_buf
    lda es3
    sta.w $0000,y           ; start (16-bit store writes lo+hi)
    sep #$20
.ACCU 8
    plx
    ; loop address
    rep #$30
.ACCU 16
    lda.l pool_data + 12,x  ; loop block ($FFFF = one-shot)
    cmp #$FFFF
    beq @oneshot
    ; loop addr = start + loop*9
    sta es0
    asl
    asl
    asl                     ; *8
    clc
    adc es0                 ; *9
    clc
    adc es3
    bra @loop_set
@oneshot:
    lda es3                 ; loop = start (never taken without the flag)
@loop_set:
    sta es1                 ; hold the loop address
    ; advance the ARAM cursor
    lda es3
    clc
    adc up_len
    sta es3
    sep #$20
.ACCU 8
    ; write loop into the dir entry (+2)
    lda es2
    rep #$30
.ACCU 16
    and #$00FF
    asl
    asl
    clc
    adc #(str_buf + 2)
    tay
    lda es1
    sta.w $0000,y
    sep #$20
.ACCU 8
    ; upload this sample
    jsr apu_upload_block
    bcc @up_ok
    sec
    rts
@up_ok:
    inc es2
    lda es2
    cmp pool_count
    beq @entries_done
    jmp @entry
@entries_done:
    ; upload the directory (count*4, padded to a multiple of 3)
    lda pool_count
    rep #$30
.ACCU 16
    and #$00FF
    asl
    asl                     ; bytes
@pad3:
    ; round up to /3: while (n % 3) n++
    sta es0
    ; n mod 3 via subtraction
    lda es0
@mod3:
    cmp #$0003
    bcc @mod_done
    sec
    sbc #$0003
    bra @mod3
@mod_done:
    cmp #$0000
    beq @aligned
    lda es0
    inc a
    bra @pad3
@aligned:
    lda es0
    sta up_len
    lda #str_buf
    sta up_src
    lda #ARAM_DIR
    sta up_dest
    sep #$20
.ACCU 8
    lda #$7E
    sta up_src + 2
    jsr apu_upload_block
    bcs @bad
    clc
    rts
@bad:
    sec
    rts
