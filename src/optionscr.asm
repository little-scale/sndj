; optionscr.asm — the OPTIONS screen (device settings, persist in the
; reserved SRAM header bytes). One live field for now:
;
;   PALETTE  — B-hold + left/right cycles the 8 schemes (applies
;              instantly, persists in SRAM)
;
; VIDEO shows the detected console standard (display only — pitch and
; tempo ride the region-free APU crystal); SYNC arrives with M12.
; Reached with A+Up from SONG.

.ACCU 8
.INDEX 16

.DEFINE OPT_FIELDS 4

options_init:
    lda #SCREEN_OPTIONS
    sta ui_mode
    stz opt_cur
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
    ldx #str_options
    jsr text_puts
    rts

options_update:
    lda a_down
    beq @edit_ok
    jmp options_draw
@edit_ok:
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
    stz b_down
    jmp @cursor
@b_held:
    lda opt_cur
    cmp #$01
    bne @not_clone
    ; CLONE: any left/right toggles SLIM <-> DEEP and persists
    rep #$20
.ACCU 16
    lda pad_event
    and #(PAD_LEFT | PAD_RIGHT)
    sep #$20
.ACCU 8
    beq @b_done_far
    lda #$01
    sta b_used
    lda opt_clone
    eor #$01
    sta opt_clone
    lda.l $700000
    cmp #'S'
    bne @b_done_far
    lda opt_clone
    sta.l $700008
@b_done_far:
    jmp options_draw
@not_clone:
    lda opt_cur
    cmp #$03
    bne @not_sync
    ; SYNC: B + left/right cycles the six modes and persists
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_LEFT
    sep #$20
.ACCU 8
    beq @sy_r
    lda #$01
    sta b_used
    lda opt_sync
    dec a
    bpl @sy_set
    lda #$05
    bra @sy_set
@sy_r:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_RIGHT
    sep #$20
.ACCU 8
    beq @b_done_far
    lda #$01
    sta b_used
    lda opt_sync
    inc a
    cmp #$06
    bcc @sy_set
    lda #$00
@sy_set:
    sta opt_sync             ; midi_service applies MIDI entry/exit next frame
    lda.l $700000
    cmp #'S'
    bne @b_done_far
    lda opt_sync
    sta.l $700009
    jmp options_draw
@not_sync:
    ; PALETTE (field 0) edits
    lda opt_cur
    bne @b_done
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_LEFT
    sep #$20
.ACCU 8
    beq @try_r
    lda #$01
    sta b_used
    lda opt_pal
    dec a
    and #$07
    jsr palette_select
    bra @b_done
@try_r:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_RIGHT
    sep #$20
.ACCU 8
    beq @b_done
    lda #$01
    sta b_used
    lda opt_pal
    inc a
    and #$07
    jsr palette_select
@b_done:
    jmp options_draw
@cursor:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_UP
    sep #$20
.ACCU 8
    beq @nu
    lda opt_cur
    dec a
    bpl @up_ok
    lda #OPT_FIELDS - 1
@up_ok:
    sta opt_cur
@nu:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_DOWN
    sep #$20
.ACCU 8
    beq @draw
    lda opt_cur
    inc a
    cmp #OPT_FIELDS
    bcc @dn_ok
    lda #$00
@dn_ok:
    sta opt_cur
@draw:
options_draw:
    stz ui_cnt
@rows:
    lda ui_cnt
    clc
    adc #8
    sta text_y
    lda #2
    sta text_x
    lda ui_cnt
    cmp opt_cur
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
    lda.w opt_labels,x
    tax
    sep #$20
.ACCU 8
    jsr text_puts
    ; value at x12
    lda #12
    sta text_x
    lda ui_cnt
    cmp #$01
    bne @not_clone_v
    rep #$20
.ACCU 16
    lda #ATTR_TEXT
    sta text_attr
    sep #$20
.ACCU 8
    lda opt_clone
    beq @slim
    ldx #str_o_deep
    jsr text_puts
    jmp @next
@slim:
    ldx #str_o_slim
    jsr text_puts
    jmp @next
@not_clone_v:
    lda ui_cnt
    cmp #$02
    bne @not_video
    ; VIDEO: the detected console standard (tempo is region-free)
    rep #$20
.ACCU 16
    lda #ATTR_TEXT
    sta text_attr
    sep #$20
.ACCU 8
    lda video_pal
    beq @ntsc
    ldx #str_o_pal50
    jsr text_puts
    jmp @next
@ntsc:
    ldx #str_o_ntsc
    jsr text_puts
    jmp @next
@not_video:
    lda ui_cnt
    bne @fixed
    ; PALETTE: index + 4-char name (text attr)
    rep #$20
.ACCU 16
    lda #ATTR_TEXT
    sta text_attr
    sep #$20
.ACCU 8
    lda opt_pal
    clc
    adc #'0' - 32
    jsr text_puttile
    lda #' ' - 32
    jsr text_puttile
    ; name chars (text_puttile clobbers X: fetch each by index)
    stz sv_run
@pname:
    lda opt_pal
    rep #$30
.ACCU 16
    and #$00FF
    asl
    asl                     ; * 4
    sta tmp2
    lda sv_run
    and #$00FF
    clc
    adc tmp2
    tax
    sep #$20
.ACCU 8
    lda.w pal_names,x
    sec
    sbc #32
    jsr text_puttile
    inc sv_run
    lda sv_run
    cmp #$04
    bne @pname
    bra @next
@fixed:
    ; SYNC (field 3): the live mode name
    rep #$20
.ACCU 16
    lda #ATTR_TEXT
    sta text_attr
    sep #$20
.ACCU 8
    lda opt_sync
    rep #$30
.ACCU 16
    and #$00FF
    asl
    tax
    lda.w sync_names,x
    tax
    sep #$20
.ACCU 8
    jsr text_puts
@next:
    inc ui_cnt
    lda ui_cnt
    cmp #OPT_FIELDS
    bne @rows_far
    ; monitor line (y14): IN/IN24 show clocks received, MIDI shows the
    ; decoded-event counter + last frame — the bring-up diagnostic
    lda opt_sync
    cmp #SYNC_IN
    beq @mon
    cmp #SYNC_IN24
    beq @mon
    cmp #SYNC_MIDI
    beq @mon
    ; not a monitored mode: blank the line (stale RX text otherwise)
    lda #2
    sta text_x
    lda #14
    sta text_y
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    sta text_attr
    sep #$20
.ACCU 8
    ldx #str_o_blank
    jmp text_puts
@mon:
    lda #2
    sta text_x
    lda #14
    sta text_y
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    sta text_attr
    sep #$20
.ACCU 8
    ldx #str_o_rx
    jsr text_puts
    lda opt_sync
    cmp #SYNC_MIDI
    beq @mon_midi
    lda sync_act + 1
    jsr text_hex8
    lda sync_act
    jmp text_hex8
@mon_midi:
    lda midi_rx + 1
    jsr text_hex8
    lda midi_rx
    jsr text_hex8
    lda #' ' - 32
    jsr text_puttile
    lda midi_last
    jsr text_hex8
    lda #' ' - 32
    jsr text_puttile
    lda midi_last + 1
    jsr text_hex8
    lda midi_last + 2
    jmp text_hex8
@rows_far:
    jmp @rows

opt_labels: .DW str_o_pal, str_o_clone, str_o_vid, str_o_sync
sync_names: .DW str_o_soff, str_o_sout, str_o_spul, str_o_sin, str_o_smid, str_o_s24

str_options: .DB "OPTIONS", 0
str_o_pal:   .DB "PALETTE", 0
str_o_clone: .DB "CLONE", 0
str_o_slim:  .DB "SLIM", 0
str_o_deep:  .DB "DEEP", 0
str_o_vid:   .DB "VIDEO", 0
str_o_sync:  .DB "SYNC", 0
str_o_v60:   .DB "60HZ", 0
str_o_ntsc:  .DB "NTSC 60HZ", 0
str_o_pal50: .DB "PAL 50HZ ", 0
str_o_soff:  .DB "OFF  ", 0
str_o_sout:  .DB "OUT  ", 0
str_o_spul:  .DB "PULSE", 0
str_o_sin:   .DB "IN   ", 0
str_o_smid:  .DB "MIDI ", 0
str_o_s24:   .DB "IN24 ", 0
str_o_rx:    .DB "RX ", 0
str_o_blank: .DB "                ", 0
