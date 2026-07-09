; clone.asm — minting and cloning (genmddj §4). SONG cells hold chain
; numbers and CHAIN cells hold phrase numbers — references — so a B
; double-tap with an empty clipboard mints (on a blank cell) or clones
; (on a populated one). OPTIONS -> CLONE picks SLIM (a chain clone
; shares its phrases) or DEEP (phrases are copied too). Phrase clones
; are always independent. No free slot -> carry set, nothing changes.

.ACCU 8
.INDEX 16

; --- find the first blank chain -> A (carry set: none) ---------------------------
; blank = all 16 phrase entries are $FF
find_free_chain:
    stz cl_i
@chain:
    lda cl_i
    rep #$30
.ACCU 16
    and #$00FF
    asl
    asl
    asl
    asl
    asl                     ; * 32
    tax
    sep #$20
.ACCU 8
    lda #$10
    sta cl_j
@entry:
    lda.l $7E0000 + SB_CHAINS,x
    cmp #$FF
    bne @next_chain
    rep #$30
.ACCU 16
    inx
    inx
    sep #$20
.ACCU 8
    dec cl_j
    bne @entry
    lda cl_i                ; every entry blank: this one
    clc
    rts
@next_chain:
    inc cl_i
    lda cl_i
    cmp #CHAIN_COUNT
    bcc @chain
    sec
    rts

; --- find the first blank phrase -> A (carry set: none) --------------------------
; blank = every row is (0, $FF, 0, 0)
find_free_phrase:
    stz cl_i
@phrase:
    lda cl_i
    rep #$30
.ACCU 16
    and #$00FF
    xba
    lsr
    lsr                     ; * 64
    tax
    sep #$20
.ACCU 8
    lda #$10
    sta cl_j
@row:
    lda.l $7E0000 + SB_PHRASES,x
    bne @next_phrase
    lda.l $7E0000 + SB_PHRASES + 1,x
    cmp #$FF
    bne @next_phrase
    lda.l $7E0000 + SB_PHRASES + 2,x
    bne @next_phrase
    lda.l $7E0000 + SB_PHRASES + 3,x
    bne @next_phrase
    rep #$30
.ACCU 16
    inx
    inx
    inx
    inx
    sep #$20
.ACCU 8
    dec cl_j
    bne @row
    lda cl_i
    clc
    rts
@next_phrase:
    inc cl_i
    lda cl_i
    cmp #PHRASE_COUNT
    bcc @phrase
    sec
    rts

; --- clone phrase A into a fresh slot -> A = new id (carry set: no room) ---------
clone_phrase:
    sta cl_src
    jsr find_free_phrase
    bcc @have
    rts
@have:
    sta cl_dst
    ; copy 64 bytes src -> dst
    rep #$30
.ACCU 16
    lda cl_src
    and #$00FF
    xba
    lsr
    lsr
    sta cl_i                ; src offset
    lda cl_dst
    and #$00FF
    xba
    lsr
    lsr
    sta cl_j                ; dst offset
    sep #$20
.ACCU 8
    lda #64
    sta cl_n
@copy:
    rep #$30
.ACCU 16
    lda cl_i
    tax
    sep #$20
.ACCU 8
    lda.l $7E0000 + SB_PHRASES,x
    pha
    rep #$30
.ACCU 16
    lda cl_j
    tax
    inc cl_i
    inc cl_j
    sep #$20
.ACCU 8
    pla
    sta.l $7E0000 + SB_PHRASES,x
    dec cl_n
    bne @copy
    lda cl_dst
    clc
    rts

; --- clone chain A into a fresh slot -> A = new id (carry set: no room) ----------
; SLIM shares the phrases; DEEP (opt_clone = 1) copies them too, with
; duplicate entries staying consistent inside the clone.
clone_chain:
    sta cl_csrc
    jsr find_free_chain
    bcc @have
    rts
@have:
    sta cl_cdst
    ; copy the 32 chain bytes first (SLIM's whole job)
    rep #$30
.ACCU 16
    lda cl_csrc
    and #$00FF
    asl
    asl
    asl
    asl
    asl
    sta cl_i
    lda cl_cdst
    and #$00FF
    asl
    asl
    asl
    asl
    asl
    sta cl_j
    sep #$20
.ACCU 8
    lda #32
    sta cl_n
@copy:
    rep #$30
.ACCU 16
    lda cl_i
    tax
    sep #$20
.ACCU 8
    lda.l $7E0000 + SB_CHAINS,x
    pha
    rep #$30
.ACCU 16
    lda cl_j
    tax
    inc cl_i
    inc cl_j
    sep #$20
.ACCU 8
    pla
    sta.l $7E0000 + SB_CHAINS,x
    dec cl_n
    bne @copy
    lda opt_clone
    beq @done               ; SLIM
    ; DEEP: clone every referenced phrase, entry by entry; when an
    ; earlier entry already cloned the same phrase, reuse its copy
    stz cl_e
@deep:
    lda cl_e
    jsr cl_dst_entry        ; X = dst chain entry offset, A = phrase id
    cmp #$FF
    beq @e_next
    sta cl_p
    ; scan earlier entries of the SOURCE chain for the same phrase
    stz cl_s
@scanback:
    lda cl_s
    cmp cl_e
    bcs @fresh              ; no earlier duplicate: clone it
    lda cl_s
    jsr cl_src_entry
    cmp cl_p
    beq @reuse
    inc cl_s
    bra @scanback
@reuse:
    ; take the value the earlier DST entry already holds
    lda cl_s
    jsr cl_dst_entry
    pha
    lda cl_e
    jsr cl_dst_entry
    pla
    sta.l $7E0000 + SB_CHAINS,x
    bra @e_next
@fresh:
    lda cl_p
    jsr clone_phrase
    bcs @abort              ; DEEP doesn't fit: leave a SLIM clone
    pha
    lda cl_e
    jsr cl_dst_entry
    pla
    sta.l $7E0000 + SB_CHAINS,x
@e_next:
    inc cl_e
    lda cl_e
    cmp #$10
    bcc @deep
@abort:
@done:
    lda cl_cdst
    clc
    rts

; A = entry index -> X = offset of that entry in the DST chain, A = its phrase
cl_dst_entry:
    rep #$30
.ACCU 16
    and #$00FF
    asl
    sta cl_n
    lda cl_cdst
    and #$00FF
    asl
    asl
    asl
    asl
    asl
    clc
    adc cl_n
    tax
    sep #$20
.ACCU 8
    lda.l $7E0000 + SB_CHAINS,x
    rts

; A = entry index -> A = that entry's phrase in the SRC chain
cl_src_entry:
    rep #$30
.ACCU 16
    and #$00FF
    asl
    sta cl_n
    lda cl_csrc
    and #$00FF
    asl
    asl
    asl
    asl
    asl
    clc
    adc cl_n
    tax
    sep #$20
.ACCU 8
    lda.l $7E0000 + SB_CHAINS,x
    rts
