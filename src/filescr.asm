; filescr.asm — the FILES screen: 4 SRAM slots, LOAD / SAVE actions.
; B tap runs the action under the cursor; the status line reports the
; result. Reached with A+Down from SONG (A+Up returns).

.ACCU 8
.INDEX 16

files_init:
    lda #SCREEN_FILES
    sta ui_mode
    stz fl_col
    stz fl_slot
    lda #$FF
    sta fl_msg              ; no message
    jsr text_clear
    lda #1
    sta text_x
    lda #1
    sta text_y
    rep #$20
.ACCU 16
    lda #ATTR_HILITE
    sta text_attr
    sep #$20
.ACCU 8
    ldx #str_files
    jsr text_puts
    rts

files_update:
    lda a_down
    beq @edit_ok
    jmp files_draw
@edit_ok:
    ; B tap = action (no hold semantics here)
    rep #$20
.ACCU 16
    lda pad_pressed
    and #PAD_B
    sep #$20
.ACCU 8
    beq @no_b
    lda fl_col
    bne @do_save
    lda fl_slot
    jsr load_slot
    sta fl_msg
    ; message ids: reuse SV_* (0 = LOADED)
    bra @acted
@do_save:
    lda fl_slot
    jsr save_slot
    sta fl_msg
    ora #$80                ; bit7: the action was a save (message text)
    sta fl_msg
@acted:
@no_b:
    ; cursor
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_UP
    sep #$20
.ACCU 8
    beq @nu
    lda fl_slot
    dec a
    and #$03
    sta fl_slot
@nu:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_DOWN
    sep #$20
.ACCU 8
    beq @nd
    lda fl_slot
    inc a
    and #$03
    sta fl_slot
@nd:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_LEFT
    sep #$20
.ACCU 8
    beq @nl
    stz fl_col
@nl:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_RIGHT
    sep #$20
.ACCU 8
    beq @nr
    lda #$01
    sta fl_col
@nr:
files_draw:
    stz ui_cnt              ; slot counter
@slots:
    lda ui_cnt
    asl
    clc
    adc #5
    sta text_y
    ; slot number
    lda #2
    sta text_x
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    sta text_attr
    sep #$20
.ACCU 8
    lda ui_cnt
    clc
    adc #'0' - 32
    jsr text_puttile
    ; name / EMPTY from the slot table
    lda #5
    sta text_x
    rep #$20
.ACCU 16
    lda #ATTR_TEXT
    sta text_attr
    sep #$20
.ACCU 8
    lda ui_cnt
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
    beq @named
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    sta text_attr
    sep #$20
.ACCU 8
    phx
    ldx #str_empty
    jsr text_puts
    plx
    bra @actions
@named:
    ; 8-char name straight from SRAM
    stz sv_run              ; char counter (scratch, save isn't running)
@name:
    phx
    lda.l SRAM_TABLE + 6,x
    sec
    sbc #32
    jsr text_puttile
    plx
    inx
    inc sv_run
    lda sv_run
    cmp #$08
    bne @name
    ; packed size in hex
    rep #$30
.ACCU 16
    txa
    sec
    sbc #$0008              ; back to the entry base
    tax
    sep #$20
.ACCU 8
    lda #15
    sta text_x
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    sta text_attr
    sep #$20
.ACCU 8
    phx
    lda.l SRAM_TABLE + 3,x
    jsr text_hex8
    plx
    phx
    lda.l SRAM_TABLE + 2,x
    jsr text_hex8
    plx
@actions:
    ; LOAD cell
    lda #21
    sta text_x
    lda ui_cnt
    cmp fl_slot
    bne @load_plain
    lda fl_col
    bne @load_plain
    rep #$20
.ACCU 16
    lda #ATTR_ACCENT
    sta text_attr
    sep #$20
.ACCU 8
    bra @load_put
@load_plain:
    rep #$20
.ACCU 16
    lda #ATTR_TEXT
    sta text_attr
    sep #$20
.ACCU 8
@load_put:
    ldx #str_load
    jsr text_puts
    ; SAVE cell
    lda #26
    sta text_x
    lda ui_cnt
    cmp fl_slot
    bne @save_plain
    lda fl_col
    beq @save_plain
    rep #$20
.ACCU 16
    lda #ATTR_ACCENT
    sta text_attr
    sep #$20
.ACCU 8
    bra @save_put
@save_plain:
    rep #$20
.ACCU 16
    lda #ATTR_TEXT
    sta text_attr
    sep #$20
.ACCU 8
@save_put:
    ldx #str_save
    jsr text_puts
    inc ui_cnt
    lda ui_cnt
    cmp #SLOT_COUNT
    beq @msg
    jmp @slots
@msg:
    ; status line
    lda #2
    sta text_x
    lda #20
    sta text_y
    rep #$20
.ACCU 16
    lda #ATTR_HILITE
    sta text_attr
    sep #$20
.ACCU 8
    lda fl_msg
    cmp #$FF
    bne @have_msg
    ldx #str_blank
    jmp text_puts
@have_msg:
    and #$7F
    cmp #SV_OK
    bne @not_ok
    lda fl_msg
    bmi @saved
    ldx #str_loaded
    jmp text_puts
@saved:
    ldx #str_saved
    jmp text_puts
@not_ok:
    cmp #SV_FULL
    bne @not_full
    ldx #str_full
    jmp text_puts
@not_full:
    cmp #SV_EMPTY
    bne @badcrc
    ldx #str_noempty
    jmp text_puts
@badcrc:
    ldx #str_badcrc
    jmp text_puts

str_files:   .DB "FILES", 0
str_empty:   .DB "--------", 0
str_load:    .DB "LOAD", 0
str_save:    .DB "SAVE", 0
str_saved:   .DB "SAVED   ", 0
str_loaded:  .DB "LOADED  ", 0
str_full:    .DB "FULL    ", 0
str_noempty: .DB "EMPTY   ", 0
str_badcrc:  .DB "BAD CRC ", 0
str_blank:   .DB "        ", 0
