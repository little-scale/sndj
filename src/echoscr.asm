; echoscr.asm — the ECHO screen: the room as a first-class instrument.
; Edits the song header's echo block; EDL changes run the driver's safe
; reconfiguration; everything else is a live register write. The ARAM cost
; of the delay line is shown, not hidden (CLAUDE.md §11). FIR preset taps
; are displayed; deep tap design belongs to the browser designer.

.ACCU 8
.INDEX 16

.DEFINE EF_COUNT 6

; field: header offset, max
ef_fields:
    .DB SH_EDL, 15
    .DB SH_EFB, 255
    .DB SH_EVL, 127
    .DB SH_EVR, 127
    .DB SH_EON, 255
    .DB SH_FIR, 7

ef_labels:
    .DW ef_l0, ef_l1, ef_l2, ef_l3, ef_l4, ef_l5
ef_l0: .DB "DELAY", 0
ef_l1: .DB "FEEDBACK", 0
ef_l2: .DB "ECHO L", 0
ef_l3: .DB "ECHO R", 0
ef_l4: .DB "EON MASK", 0
ef_l5: .DB "FIR", 0

echo_init:
    lda #SCREEN_ECHO
    sta ui_mode
    stz if_cur              ; reuse the INSTR field cursor
    jsr text_clear
    stz text_x
    lda #1
    sta text_y
    rep #$20
.ACCU 16
    lda #ATTR_HILITE
    sta text_attr
    sep #$20
.ACCU 8
    ldx #str_echo
    jsr text_puts
    rts

echo_update:
    rep #$20
.ACCU 16
    lda pad_pressed
    and #PAD_START
    sep #$20
.ACCU 8
    beq @no_start
    jsr engine_toggle
@no_start:
    lda a_down
    beq @edit_ok
    jmp echo_draw
@edit_ok:
    ; B edges (B+d-pad nudges; no tap action here)
    rep #$20
.ACCU 16
    lda pad_pressed
    and #PAD_B
    sep #$20
.ACCU 8
    beq @no_press
    lda #$01
    sta b_down
    stz b_used
@no_press:
    rep #$20
.ACCU 16
    lda pad_held
    and #PAD_B
    sep #$20
.ACCU 8
    bne @b_held
    stz b_down
    bra @cursor
@b_held:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_DPAD
    sep #$20
.ACCU 8
    beq @draw
    lda #$01
    sta b_used
    jsr ef_nudge
    bra @draw
@cursor:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_UP
    sep #$20
.ACCU 8
    beq @nu
    lda if_cur
    dec a
    bpl @up_ok
    lda #EF_COUNT - 1
@up_ok:
    sta if_cur
@nu:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_DOWN
    sep #$20
.ACCU 8
    beq @draw
    lda if_cur
    inc a
    cmp #EF_COUNT
    bcc @dn_ok
    lda #$00
@dn_ok:
    sta if_cur
@draw:
    jmp echo_draw

; header byte address of field A -> X (offset within bank $7E)
ef_addr:
    rep #$30
.ACCU 16
    and #$00FF
    asl
    tax
    sep #$20
.ACCU 8
    lda.w ef_fields,x       ; header offset
    rep #$30
.ACCU 16
    and #$00FF
    clc
    adc #(SB_HEADER + $0000)
    tax
    sep #$20
.ACCU 8
    rts

ef_nudge:
    lda #4
    sta tmp2
    jsr nudge_delta         ; delta -> tmp1+1
    lda tmp1 + 1
    bne @have
    rts
@have:
    sta es0                 ; pending delta
    lda if_cur
    rep #$30
.ACCU 16
    and #$00FF
    asl
    tax
    sep #$20
.ACCU 8
    lda.w ef_fields + 1,x
    sta es0 + 1             ; max
    lda if_cur
    bne @max_ok
    ; EDL: the echo buffer may never reach down into resident samples.
    ; max = ($10000 - res_cursor) / 2 KB, capped by the field max (15)
    rep #$30
.ACCU 16
    lda res_cursor
    eor #$FFFF
    inc a                   ; $10000 - res_cursor
    xba
    and #$00FF
    lsr
    lsr
    lsr                     ; >> 11 = free 2 KB steps
    sep #$20
.ACCU 8
    cmp es0 + 1
    bcs @max_ok
    sta es0 + 1
@max_ok:
    lda if_cur
    jsr ef_addr
    lda.l $7E0000,x
    clc
    adc es0
    ; free byte fields (max 255) wrap; others clamp
    ldy #$0000
    cpy #$0000              ; (keep flags sane)
    pha
    lda es0 + 1
    cmp #$FF
    beq @wrap
    pla
    cmp es0 + 1
    bcc @store
    beq @store
    ; out of range: clamp by delta sign
    lda es0
    bmi @lo
    lda es0 + 1
    bra @store
@lo:
    lda #$00
    bra @store
@wrap:
    pla
@store:
    sta.l $7E0000,x
    ; apply: EDL (field 0) walks the safe reconfig; the FIR field (5)
    ; recalls the preset into the song's taps; the rest are live writes
    lda if_cur
    bne @not_edl
    jmp apu_echo_apply
@not_edl:
    cmp #$05
    bne @light
    lda.l $7E0000 + SB_HEADER + SH_FIR
    jmp apu_fir_preset
@light:
    jmp apu_echo_apply_light

; --- fresh song: open the delay as wide as the resident set allows -------------
; (runs after residency_build on boot/NEW; the caller applies the echo).
; max EDL = free 2 KB steps above the samples, capped by the field's 15.
echo_auto_edl:
    rep #$30
.ACCU 16
    lda res_cursor
    eor #$FFFF
    inc a                   ; $10000 - res_cursor
    xba
    and #$00FF
    lsr
    lsr
    lsr                     ; >> 11 = free 2 KB steps
    sep #$20
.ACCU 8
    cmp #$0F
    bcc @have
    lda #$0F
@have:
    sta.l $7E0000 + SB_HEADER + SH_EDL
    rts

echo_draw:
    stz ui_cnt
@rows:
    lda ui_cnt
    asl
    clc
    adc #4
    sta text_y
    lda #2
    sta text_x
    lda ui_cnt
    cmp if_cur
    bne @dim
    rep #$20
.ACCU 16
    lda #ATTR_ACCENT
    sta text_attr
    sep #$20
.ACCU 8
    bra @label
@dim:
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    sta text_attr
    sep #$20
.ACCU 8
@label:
    lda ui_cnt
    rep #$30
.ACCU 16
    and #$00FF
    asl
    tax
    lda.w ef_labels,x
    tax
    sep #$20
.ACCU 8
    jsr text_puts
    ; value
    lda #14
    sta text_x
    rep #$20
.ACCU 16
    lda #ATTR_TEXT
    sta text_attr
    sep #$20
.ACCU 8
    lda ui_cnt
    jsr ef_addr
    lda.l $7E0000,x
    jsr text_hex8
    ; EON row: the eight channel gates as toggles (solid = open)
    lda ui_cnt
    cmp #$04
    bne @no_gates
    lda #18
    sta text_x
    stz sv_run
@gate:
    lda sv_run
    rep #$30
.ACCU 16
    and #$00FF
    tax
    sep #$20
.ACCU 8
    lda.l $7E0000 + SB_HEADER + SH_EON
    and.w bit_for_track,x
    beq @gate_shut
    rep #$20
.ACCU 16
    lda #ATTR_ACCENT        ; the one attr with the inverted glyph bank
    sta text_attr
    sep #$20
.ACCU 8
    lda #' ' - 32           ; inverted space = a solid cell
    jsr text_puttile
    bra @gate_next
@gate_shut:
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    sta text_attr
    sep #$20
.ACCU 8
    lda #'-' - 32
    jsr text_puttile
@gate_next:
    inc sv_run
    lda sv_run
    cmp #$08
    bne @gate
@no_gates:
    ; EDL row: show the live ARAM trade (EDL * 2 KB)
    lda ui_cnt
    bne @no_cost
    lda #18
    sta text_x
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    sta text_attr
    sep #$20
.ACCU 8
    lda #'-' - 32
    jsr text_puttile
    lda ui_cnt
    jsr ef_addr
    lda.l $7E0000,x
    asl                     ; KB = EDL * 2
    ; two decimal digits
    ldy #$0000
@tens:
    cmp #10
    bcc @tens_done
    sbc #10
    iny
    bra @tens
@tens_done:
    pha
    tya
    clc
    adc #'0' - 32
    jsr text_puttile
    pla
    clc
    adc #'0' - 32
    jsr text_puttile
    lda #'K' - 32
    jsr text_puttile
    lda #'B' - 32
    jsr text_puttile
    ; ...and the same setting as time: EDL * 16 ms
    lda #' ' - 32
    jsr text_puttile
    lda ui_cnt
    jsr ef_addr
    lda.l $7E0000,x
    and #$0F
    asl
    asl
    asl
    asl
    sta tmp0
    stz tmp0 + 1
    jsr text_dec3
    lda #'M' - 32
    jsr text_puttile
    lda #'S' - 32
    jsr text_puttile
@no_cost:
    inc ui_cnt
    lda ui_cnt
    cmp #EF_COUNT
    beq @taps
    jmp @rows
@taps:
    ; ARAM ledger: resident samples vs what the current EDL leaves free
    ; (the echo buffer and the sample set share the same 64 KB) — drawn
    ; at the top, above the DELAY it trades against
    lda #2
    sta text_x
    lda #2
    sta text_y
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    sta text_attr
    sep #$20
.ACCU 8
    ldx #str_ram
    jsr text_puts
    rep #$30
.ACCU 16
    lda res_cursor
    sec
    sbc #$1200
    sta tmp0
    sep #$20
.ACCU 8
    jsr fl_kb
    ldx #str_free
    jsr text_puts
    ; free = echo floor - resident end; floor page = $100 - 8*EDL
    ; (EDL 0 still reserves the top page, matching residency_build)
    lda.l $7E0000 + SB_HEADER + SH_EDL
    and #$0F
    asl
    asl
    asl
    eor #$FF
    inc a
    bne @floor_ok
    lda #$FF
@floor_ok:
    rep #$30
.ACCU 16
    and #$00FF
    xba                     ; floor page -> byte address
    sec
    sbc res_cursor
    bcs @free_ok
    lda #$0000              ; floor at/below the samples: nothing free
@free_ok:
    pha                     ; free bytes survive fl_kb's tmp scratch
    sta tmp0
    sep #$20
.ACCU 8
    jsr fl_kb
    ; ...and as time: how much LONGER the delay could get from here
    ; (free / 2 KB steps, capped by the register's 15) * 16 ms
    rep #$30
.ACCU 16
    pla
    xba
    and #$00FF
    lsr
    lsr
    lsr                     ; free >> 11 = spare 2 KB steps
    sep #$20
.ACCU 8
    sta tmp2
    lda.l $7E0000 + SB_HEADER + SH_EDL
    and #$0F
    eor #$0F                ; 15 - EDL = register headroom
    cmp tmp2
    bcs @steps_ok
    sta tmp2
@steps_ok:
    lda tmp2
    asl
    asl
    asl
    asl                     ; * 16 ms (<= 240)
    sta tmp0
    stz tmp0 + 1
    lda #' ' - 32
    jsr text_puttile
    lda #'+' - 32
    jsr text_puttile
    jsr text_dec3
    lda #'M' - 32
    jsr text_puttile
    lda #'S' - 32
    jsr text_puttile
    ; current FIR preset taps, read-only
    lda #2
    sta text_x
    lda #18
    sta text_y
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    sta text_attr
    sep #$20
.ACCU 8
    ldx #str_taps
    jsr text_puts
    lda.l $7E0000 + SB_HEADER + SH_FIR
    and #$07
    rep #$30
.ACCU 16
    and #$00FF
    asl
    asl
    asl
    tax
    sep #$20
.ACCU 8
    stz es1                 ; tap counter
@tap:
    lda es1
    asl
    clc
    adc es1
    adc #2                  ; x = 2 + tap*3
    sta text_x
    lda #19
    sta text_y
    phx
    lda.w fir_presets,x
    jsr text_hex8
    plx
    inx
    inc es1
    lda es1
    cmp #$08
    bne @tap
    rts

str_echo: .DB "ECHO", 0
str_taps: .DB "FIR TAPS", 0
str_ram:  .DB "RAM ", 0
str_free: .DB "  FREE ", 0
