; kitscr.asm — the KIT screen: 16 slots x (SAMPLE, TUNE, VOL).
; B+d-pad nudges the cell (L/R = 1, U/D = big); B tap auditions the
; slot; Y+up/down pages between kits (the family gesture — chains,
; phrases, kits and tables all page the same way; the number in the
; title is a readout, not a field). Sample edits rebuild the resident
; set so new drums are audible immediately.

.ACCU 8
.INDEX 16

kit_init:
    lda #SCREEN_KIT
    sta ui_mode
    stz kt_row
    stz kt_col
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
    ldx #str_kit
    jsr text_puts
    lda #3
    sta text_x
    lda #4
    sta text_y
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    sta text_attr
    sep #$20
.ACCU 8
    ldx #str_kruler
    jsr text_puts
    rts

; X = song-block offset of the cursor's slot byte (kit*64 + slot*4 + col)
kt_addr:
    rep #$30
.ACCU 16
    lda ed_kit
    and #$00FF
    xba
    lsr
    lsr                     ; * 64
    sta es1
    lda kt_row
    and #$00FF
    asl
    asl                     ; * 4
    clc
    adc es1
    sta es1
    lda kt_col
    and #$00FF
    clc
    adc es1
    clc
    adc #SB_KITS
    tax
    sep #$20
.ACCU 8
    rts

kit_update:
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
    jmp kit_draw
@edit_ok:
    ; Y + up/down: kit page (the family gesture)
    rep #$20
.ACCU 16
    lda pad_held
    and #PAD_Y
    sep #$20
.ACCU 8
    beq @no_page
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_UP
    sep #$20
.ACCU 8
    beq @pg_dn
    lda ed_kit
    dec a
    and #(KIT_COUNT - 1)
    sta ed_kit
@pg_dn:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_DOWN
    sep #$20
.ACCU 8
    beq @pg_done
    lda ed_kit
    inc a
    and #(KIT_COUNT - 1)
    sta ed_kit
@pg_done:
    jmp kit_draw
@no_page:
    ; B edges
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
    lda b_down
    beq @cursor
    stz b_down
    lda b_used
    bne @cursor
    ; tap: audition this slot on voice 0 (kit id via a scratch instrument
    ; path: reuse kit_trigger with trig_id pointing at a temp record is
    ; overkill — drive it directly)
    jsr kit_audition
    bra @draw
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
    jsr kt_nudge
    bra @draw
@cursor:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_UP
    sep #$20
.ACCU 8
    beq @nu
    lda kt_row
    dec a
    bpl @up_ok
    lda #15
@up_ok:
    sta kt_row
@nu:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_DOWN
    sep #$20
.ACCU 8
    beq @nd
    lda kt_row
    inc a
    cmp #16
    bcc @dn_ok
    lda #$00
@dn_ok:
    sta kt_row
@nd:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_LEFT
    sep #$20
.ACCU 8
    beq @nl
    lda kt_col
    beq @nl
    dec kt_col
@nl:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_RIGHT
    sep #$20
.ACCU 8
    beq @draw
    lda kt_col
    cmp #$02
    bcs @draw
    inc kt_col
@draw:
    jmp kit_draw

; audition the cursor slot on voice 0 (only while stopped)
kit_audition:
    lda eng_playing
    beq +
    rts
+
    stz trig_voice
    lda kt_col
    pha
    stz kt_col
    jsr kt_addr
    pla
    sta kt_col
    lda.l $7E0002,x         ; vol
    beq @silent
    pha
    lda.l $7E0000,x         ; sample: pool default tune applies
    and #$3F
    phx
    stz np_fine
    jsr trig_tune_pool
    plx
    lda.l $7E0000,x         ; sample -> SRCN
    and #$3F
    phx
    rep #$30
.ACCU 16
    and #$00FF
    tay
    sep #$20
.ACCU 8
    phy
    plx
    lda.w pool_map,x
    tay
    lda #DSP_V0SRCN
    jsr apu_dsp_write
    plx
    pla
    tay
    lda #DSP_V0VOLL
    jsr apu_dsp_write
    lda #DSP_V0VOLR
    jsr apu_dsp_write
    lda.l $7E0001,x         ; tune
    clc
    adc #60
    cmp #NOTE_MAX
    bcc @tuned
    lda #60
@tuned:
    jsr note_pitch_calc_only
    jsr voice_pitch_write
    lda #$FF
    sta.w trk_instr_active
    lda #DSP_KON
    ldy #$0001
    jsr apu_dsp_write
    inc kon_count
@silent:
    rts

kt_nudge:
    ; big step per column: sample = 16, tune = an octave, vol = 16
    lda kt_col
    cmp #$01
    bne @mag_16
    lda #12
    bra @mag_have
@mag_16:
    lda #16
@mag_have:
    sta tmp2
    jsr nudge_delta         ; delta -> tmp1+1
    lda tmp1 + 1
    bne @have
    rts
@have:
    sta es3 + 1
    jsr kt_addr
    lda.l $7E0000,x
    clc
    adc es3 + 1
    ; clamp per column: sample 0-63 wrap, tune free signed, vol 0-127
    pha
    lda kt_col
    beq @smp
    cmp #$01
    beq @tune
    pla
    and #$7F
    bra @wr
@smp:
    pla
    and #$3F
    bra @wr
@tune:
    pla
@wr:
    sta.l $7E0000,x
    ; sample edits change the resident set
    lda kt_col
    bne @done
    jsr residency_build
@done:
    rts

kit_draw:
    ; the kit number: a title readout (Y+up/down pages it)
    lda #4
    sta text_x
    lda #1
    sta text_y
    rep #$20
.ACCU 16
    lda #ATTR_HILITE
    sta text_attr
    sep #$20
.ACCU 8
    lda ed_kit
    jsr text_hex8
    stz ui_cnt
@rows:
    lda ui_cnt
    clc
    adc #5
    sta text_y
    stz text_x
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    sta text_attr
    sep #$20
.ACCU 8
    lda ui_cnt
    jsr text_hex8
    ; fetch the slot's three bytes
    lda kt_row
    pha
    lda kt_col
    pha
    lda ui_cnt
    sta kt_row
    stz kt_col
    jsr kt_addr
    pla
    sta kt_col
    pla
    sta kt_row
    lda.l $7E0000,x
    sta.w str_buf + 28
    lda.l $7E0001,x
    sta.w str_buf + 29
    lda.l $7E0002,x
    sta.w str_buf + 30
    ; SAMPLE cell
    lda #3
    sta text_x
    stz es3
    jsr kt_attr
    lda.w str_buf + 28
    jsr text_hex8
    ; TUNE cell
    lda #7
    sta text_x
    lda #$01
    sta es3
    jsr kt_attr
    lda.w str_buf + 29
    jsr text_hex8
    ; VOL cell
    lda #11
    sta text_x
    lda #$02
    sta es3
    jsr kt_attr
    lda.w str_buf + 30
    jsr text_hex8
    inc ui_cnt
    lda ui_cnt
    cmp #$10
    beq @done
    jmp @rows
@done:
    rts

; attr for cell (col es3, slot row ui_cnt)
kt_attr:
    lda ui_cnt
    cmp kt_row
    bne @plain
    lda es3
    cmp kt_col
    bne @plain
    rep #$20
.ACCU 16
    lda #ATTR_ACCENT
    sta text_attr
    sep #$20
.ACCU 8
    rts
@plain:
    rep #$20
.ACCU 16
    lda #ATTR_TEXT
    sta text_attr
    sep #$20
.ACCU 8
    rts

str_kit:    .DB "KIT  ", 0
str_kruler: .DB "SMP TUNE VOL", 0
