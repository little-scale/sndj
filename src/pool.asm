; pool.asm — the ROM sample pool (format v2) and per-song residency.
;
; The pool spans ROM banks 1-5; entry offsets/sizes are in 9-byte BRR
; blocks and no sample crosses a bank boundary (the builder pads), so a
; sample's data is addressable with one bank byte + 16-bit maths.
;
; Residency (CLAUDE.md §14.2): only the samples a song references are
; uploaded. residency_build scans instruments (SMP sample fields) and
; kits (slots with vol > 0), assigns ARAM directory slots 1..55 in
; first-seen order, uploads each sample, and fills pool_map[pool idx] ->
; SRCN. Slot 0 is a permanently-resident silent stub, and unreferenced /
; over-budget samples map to it. Waves own directory slots 56-63.

.ACCU 8
.INDEX 16

.DEFINE POOL_TABLE   (POOL_ROM + 16)
.DEFINE DIR_SLOT_MAX 56           ; sample slots 0-55 (0 = silence)

; A = pool entry index -> sets up_src (24-bit) + up_len for its BRR data;
; also leaves the entry's loop block in es2 (16-bit; $FFFF one-shot).
pool_entry_src:
    rep #$30
.ACCU 16
    and #$00FF
    asl
    asl
    asl
    asl                     ; * 16
    tax
    sep #$20
.ACCU 8
    ; linear byte offset F = entry.offset_blocks * 9 + 6 (marker skip)
    rep #$30
.ACCU 16
    lda.l POOL_TABLE + 8,x  ; offset in blocks (POOL_ROM is a constant)
    sta es0
    lsr
    lsr
    lsr
    lsr
    lsr
    lsr
    lsr
    lsr
    lsr
    lsr
    lsr
    lsr
    lsr                     ; blocks >> 13 = bits of blocks*8 above 16
    sta es3
    lda es0
    asl
    asl
    asl                     ; blocks * 8 (low 16)
    clc
    adc es0                 ; * 9
    sta es1
    lda es3
    adc #$0000              ; carry from the *9 add
    sta es3
    lda es1
    clc
    adc #$0006              ; skip the SNPOOL marker
    sta es1
    lda es3
    adc #$0000
    sta es3                 ; F = es3:es1 (17-bit)
    ; bank = $81 + (F >> 15); addr = $8000 | (F & $7FFF)
    lda es1
    and #$7FFF
    ora #$8000
    sta up_src
    lda es1
    xba
    and #$00FF
    lsr
    lsr
    lsr
    lsr
    lsr
    lsr
    lsr                     ; (F_lo >> 15)
    sta es0
    lda es3
    asl                     ; F bit 16 counts double in bank steps
    clc
    adc es0
    clc
    adc #$0081
    sep #$20
.ACCU 8
    sta up_src + 2
    ; length in bytes = blocks * 9 (entries stay comfortably under 32 KB)
    rep #$30
.ACCU 16
    lda.l POOL_TABLE + 10,x
    sta es0
    asl
    asl
    asl
    clc
    adc es0
    sta up_len
    lda.l POOL_TABLE + 12,x ; loop block
    sta es2
    sep #$20
.ACCU 8
    rts

; --- rebuild the resident sample set from the song ------------------------------
; Carry set on mailbox failure.
residency_build:
    lda.l POOL_ROM + 8
    cmp #$02
    beq @v_ok
    sec
    rts
@v_ok:
    lda.l POOL_ROM + 9
    sta pool_count
    ; clear the map (all samples -> silence)
    ldx #$0000
    lda #$00
@clr:
    sta.w pool_map,x
    inx
    cpx #$0040
    bne @clr
    ; slot 0: the silent stub, always resident at ARAM_SAMPLES
    ldx #silent_brr
    stx up_src
    lda #:silent_brr
    sta up_src + 2
    ldx #ARAM_SAMPLES
    stx up_dest
    ldx #$0009
    stx up_len
    jsr apu_upload_block
    bcc @stub_ok
    rts
@stub_ok:
    lda #<ARAM_SAMPLES
    sta.w res_dir
    sta.w res_dir + 2
    lda #>ARAM_SAMPLES
    sta.w res_dir + 1
    sta.w res_dir + 3
    rep #$30
.ACCU 16
    lda #(ARAM_SAMPLES + 9)
    sta res_cursor
    sep #$20
.ACCU 8
    lda #$01
    sta res_slot
    ; ARAM ceiling: below the echo buffer (ESA page = $100 - 8*EDL)
    lda.l $7E0000 + SB_HEADER + SH_EDL
    and #$0F
    asl
    asl
    asl
    eor #$FF
    inc a
    bne @ceil_ok
    lda #$FF
@ceil_ok:
    sta res_ceil
    ; scan instruments: SMP (type 0) sample fields
    stz res_scan
@instr:
    lda res_scan
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
    lda.l $7E0000 + SB_INSTR,x
    and #$07
    bne @not_smp
    lda.l $7E0000 + SB_INSTR + 1,x
    jsr res_mark
@not_smp:
    inc res_scan
    lda res_scan
    cmp #INSTR_COUNT
    bne @instr
    ; scan kits: every slot with vol > 0
    stz res_scan
@kit_slot:
    lda res_scan
    rep #$30
.ACCU 16
    and #$00FF
    asl
    asl                     ; * 4 (slot record)
    tax
    sep #$20
.ACCU 8
    lda.l $7E0000 + SB_KITS + 2,x   ; vol
    beq @kit_next
    lda.l $7E0000 + SB_KITS,x       ; sample
    jsr res_mark
@kit_next:
    inc res_scan            ; 256 slots: loop until the counter wraps
    lda res_scan
    bne @kit_slot
    ; scan instruments again: SLICE (type 4) alias windows — n consecutive
    ; directory entries pointing into the blob's resident data at equal,
    ; block-aligned divisions. slice_base[instr] = the window's first SRCN
    ; (0 = no window: silent stub). Zero extra sample bytes.
    ldx #$0000
    lda #$00
@sb_clr:
    sta.w slice_base,x
    inx
    cpx #INSTR_COUNT
    bne @sb_clr
    stz res_scan
@slice:
    lda res_scan
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
    lda.l $7E0000 + SB_INSTR,x
    and #$07
    cmp #$04
    beq @sl_do
@sl_skip:
    jmp @sl_next
@sl_do:
    lda.l $7E0000 + SB_INSTR + 7,x
    lsr
    lsr
    lsr
    lsr
    inc a
    sta sl_n                ; slices 1-16
    lda.l $7E0000 + SB_INSTR + 1,x
    and #$3F
    sta sl_blob
    jsr res_mark            ; blob resident (uploads if new; clobbers X)
    ; blob SRCN (0 = silence / over budget: no window)
    lda sl_blob
    rep #$30
.ACCU 16
    and #$00FF
    tax
    sep #$20
.ACCU 8
    lda.w pool_map,x
    beq @sl_skip
    ; window must fit the directory (slots res_slot .. res_slot+n-1 < 56)
    pha
    lda res_slot
    clc
    adc sl_n
    cmp #(DIR_SLOT_MAX + 1)
    bcc @sl_fits
    pla
    bra @sl_skip
@sl_fits:
    pla
    ; base ARAM start = the blob's directory entry
    rep #$30
.ACCU 16
    and #$00FF
    asl
    asl
    tax
    lda.w res_dir,x
    sta sl_addr
    ; step = (blocks / n) whole blocks -> bytes (*9); 0 = blob too short
    lda sl_blob
    and #$00FF
    asl
    asl
    asl
    asl
    tax
    lda.l POOL_TABLE + 10,x ; blocks (16-bit)
    sep #$20
.ACCU 8
    sta.w WRDIVL
    xba
    sta.w WRDIVH
    lda sl_n
    sta.w WRDIVB            ; divide starts; 16 cycles until the quotient
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    rep #$30
.ACCU 16
    lda.w RDDIVL            ; step in blocks
    beq @sl_short
    sta sl_step
    asl
    asl
    asl
    clc
    adc sl_step
    sta sl_step             ; * 9 = bytes per slice
    ; write the n entries into the directory staging
    lda res_slot
    and #$00FF
    asl
    asl
    clc
    adc #res_dir
    tay
    sep #$20
.ACCU 8
    lda sl_n
    sta sl_blob             ; countdown (blob index no longer needed)
@sl_ent:
    rep #$30
.ACCU 16
    lda sl_addr
    sta.w $0000,y           ; start
    sta.w $0002,y           ; loop (unused: slices are one-shots)
    clc
    adc sl_step
    sta sl_addr
    iny
    iny
    iny
    iny
    sep #$20
.ACCU 8
    dec sl_blob
    bne @sl_ent
    ; publish the window
    lda res_scan
    rep #$30
.ACCU 16
    and #$00FF
    tax
    sep #$20
.ACCU 8
    lda res_slot
    sta.w slice_base,x
    clc
    adc sl_n
    sta res_slot
    bra @sl_next
@sl_short:
.ACCU 16
    sep #$20
.ACCU 8
@sl_next:
    inc res_scan
    lda res_scan
    cmp #INSTR_COUNT
    bne @slice_far
    bra @dir_up
@slice_far:
    jmp @slice
@dir_up:
    ; upload the directory (sample slots only; waves live at 56-63)
    lda res_slot
    rep #$30
.ACCU 16
    and #$00FF
    asl
    asl
@pad3:
    sta es0
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
    lda #res_dir
    sta up_src
    lda #ARAM_DIR
    sta up_dest
    sep #$20
.ACCU 8
    lda #$7E
    sta up_src + 2
    jmp apu_upload_block

; --- mark pool sample A as needed: assign a slot + upload if new -----------------
res_mark:
    cmp pool_count
    bcs @done               ; out of range: stays mapped to silence
    sta res_cur
    rep #$30
.ACCU 16
    and #$00FF
    tax
    sep #$20
.ACCU 8
    lda.w pool_map,x
    beq @new
@done:
    rts
@new:
    lda res_slot
    cmp #DIR_SLOT_MAX
    bcs @done               ; directory full: silence
    phx
    lda res_cur
    jsr pool_entry_src      ; up_src/up_len + es2 (loop block)
    ; budget: end page must stay under the echo ceiling (a 16-bit carry
    ; here means we wrapped ARAM entirely — definitely over)
    rep #$30
.ACCU 16
    lda res_cursor
    clc
    adc up_len
    bcs @over16
    xba
    and #$00FF
    sta es0
    sep #$20
.ACCU 8
    lda es0
    cmp res_ceil
    bcc @fits
    plx
    rts                     ; over budget: silence
@over16:
.ACCU 16
    sep #$20
.ACCU 8
    plx
    rts
@fits:
    rep #$30
.ACCU 16
    lda res_cursor
    sta up_dest
    sep #$20
.ACCU 8
    ; dir entry: start + loop (start + loopblock*9; one-shot -> start)
    lda res_slot
    rep #$30
.ACCU 16
    and #$00FF
    asl
    asl
    clc
    adc #res_dir
    tay
    lda res_cursor
    sta.w $0000,y
    ldx es2
    cpx #$FFFF
    beq @oneshot
    lda es2
    asl
    asl
    asl
    clc
    adc es2
    clc
    adc res_cursor
    bra @loop_set
@oneshot:
    lda res_cursor
@loop_set:
    sta.w $0002,y
    lda res_cursor
    clc
    adc up_len
    sta res_cursor
    sep #$20
.ACCU 8
    jsr apu_upload_block
    bcs @up_fail
    plx
    lda res_slot
    sta.w pool_map,x
    inc res_slot
    rts
@up_fail:
    plx
    rts

; one silent BRR block (END, no loop)
silent_brr:
    .DB $01, $00, $00, $00, $00, $00, $00, $00, $00
