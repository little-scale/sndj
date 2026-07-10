; tablescr.asm — the TABLE screen: 16 rows x (V, TSP, CMD+VAL) of
; per-tick automation — the family table shape: a voice level, a signed
; transpose, and ONE command through the shared phrase executor. Zero
; means "no change" in every column. An instrument's TABLE field starts
; its table from the top at every trigger; H inside a table hops the
; table's own rows.
;
;   B tap        insert (V: $40 · TSP: +12 · CMD: last letter + value)
;   B + d-pad    nudge (letters step; values L/R = 1, U/D = 16)
;   B + A        cut the cell (back to "no change")
;   Y + up/down  previous / next table
;
; Reached with A+Right from INSTR (follows the instrument's TABLE id).

.ACCU 8
.INDEX 16

table_init:
    lda #SCREEN_TABLE
    sta ui_mode
    stz tb_x
    stz tb_y
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
    ldx #str_table
    jsr text_puts
    ; ruler (the family grid: header y4, rows from y5)
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
    ldx #str_truler
    jsr text_puts
    rts

; X = song-block offset of the cursor cell (table*64 + row*4 + col)
tb_addr:
    rep #$30
.ACCU 16
    lda ed_table
    and #$00FF
    asl
    asl
    asl
    asl
    asl
    asl                     ; * 64
    sta tmp2
    lda tb_y
    and #$00FF
    asl
    asl
    clc
    adc tmp2
    sta tmp2
    lda tb_x
    and #$00FF
    clc
    adc tmp2
    clc
    adc #SB_TABLES
    tax
    sep #$20
.ACCU 8
    rts

table_update:
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
    jmp table_draw
@edit_ok:
    ; Y + up/down: page tables
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
    lda ed_table
    dec a
    and #(TABLE_COUNT - 1)
    sta ed_table
@pg_dn:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_DOWN
    sep #$20
.ACCU 8
    beq @pg_done
    lda ed_table
    inc a
    and #(TABLE_COUNT - 1)
    sta ed_table
@pg_done:
    jmp table_draw
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
    ; tap: insert a sensible starter for the column
    jsr tb_addr
    lda tb_x
    bne @tap_not_v
    lda #$40                ; V: a mid level
    sta.l $7E0000,x
    jmp @draw
@tap_not_v:
    cmp #$01
    bne @tap_not_tsp
    lda #12                 ; TSP: +1 octave
    sta.l $7E0000,x
    jmp @draw
@tap_not_tsp:
    cmp #$02
    bne @tap_val
    lda ed_lastcmd          ; CMD: the last letter + its value
    sta.l $7E0000,x
    lda ed_lastval
    sta.l $7E0000 + 1,x
    jmp @draw
@tap_val:
    lda ed_lastval
    sta.l $7E0000,x
    jmp @draw
@b_held:
    ; B + A: cut the cell
    rep #$20
.ACCU 16
    lda pad_pressed
    and #PAD_A
    sep #$20
.ACCU 8
    beq @no_cut
    lda #$01
    sta b_used
    jsr tb_addr
    lda #$00
    sta.l $7E0000,x
    jmp @draw
@no_cut:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_DPAD
    sep #$20
.ACCU 8
    beq @draw
    lda #$01
    sta b_used
    jsr tb_nudge
    bra @draw
@cursor:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_UP
    sep #$20
.ACCU 8
    beq @nu
    lda tb_y
    dec a
    and #$0F
    sta tb_y
@nu:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_DOWN
    sep #$20
.ACCU 8
    beq @nd
    lda tb_y
    inc a
    and #$0F
    sta tb_y
@nd:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_LEFT
    sep #$20
.ACCU 8
    beq @nl
    lda tb_x
    beq @nl
    dec tb_x
@nl:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_RIGHT
    sep #$20
.ACCU 8
    beq @draw
    lda tb_x
    cmp #$03
    bcs @draw
    inc tb_x
@draw:
    jmp table_draw

tb_nudge:
    lda #16
    sta tmp2
    jsr nudge_delta         ; -> tmp1+1
    lda tmp1 + 1
    bne @have
    rts
@have:
    sta es3 + 1
    jsr tb_addr
    lda tb_x
    cmp #$02
    beq @cmd
    cmp #$03
    beq @val
    cmp #$00
    beq @vcol
    ; TSP: free signed wrap (like kit TUNE)
    lda.l $7E0000,x
    clc
    adc es3 + 1
    sta.l $7E0000,x
    rts
@vcol:
    ; V: level 00-7F ($00 = no change)
    lda.l $7E0000,x
    clc
    adc es3 + 1
    and #$7F
    sta.l $7E0000,x
    rts
@cmd:
    ; command letter: step 0-26 with wrap (U/D also step by 1)
    lda es3 + 1
    bmi @cmd_dn
    lda.l $7E0000,x
    inc a
    cmp #27
    bcc @cmd_wr
    lda #$00
    bra @cmd_wr
@cmd_dn:
    lda.l $7E0000,x
    dec a
    bpl @cmd_wr
    lda #26
@cmd_wr:
    sta.l $7E0000,x
    sta ed_lastcmd
    rts
@val:
    lda.l $7E0000,x
    clc
    adc es3 + 1
    sta.l $7E0000,x
    sta ed_lastval
    rts

table_draw:
    ; header: table id + a marker when a running track is inside it
    lda #7
    sta text_x
    lda #1
    sta text_y
    rep #$20
.ACCU 16
    lda #ATTR_HILITE
    sta text_attr
    sep #$20
.ACCU 8
    lda ed_table
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
    ; the four cells: V (x3), TSP (x6), CMD letter (x10), VAL (x11)
    stz tmp0                ; col
@cells:
    lda tmp0
    cmp #$02
    beq @cmd_cell
    cmp #$03
    beq @val_cell
    ; V / TSP: hex, or -- when zero (no change)
    lda tmp0
    beq @vx0
    lda #6
    bra @hx
@vx0:
    lda #3
@hx:
    sta text_x
    jsr tb_attr
    jsr tb_cell
    cmp #$00
    beq @h_empty
    jsr text_hex8
    bra @next
@h_empty:
    lda #'-' - 32
    jsr text_puttile
    lda #'-' - 32
    jsr text_puttile
    bra @next
@cmd_cell:
    lda #10
    sta text_x
    jsr tb_attr
    jsr tb_cell
    cmp #$00
    beq @c_empty
    clc
    adc #'A' - 32 - 1
    jsr text_puttile
    bra @next
@c_empty:
    lda #'-' - 32
    jsr text_puttile
    bra @next
@val_cell:
    lda #11
    sta text_x
    jsr tb_attr
    ; VAL reads as dashes while its command cell is empty (phrase style)
    dec tmp0                ; peek the CMD byte
    jsr tb_cell
    inc tmp0
    cmp #$00
    beq @v_empty
    jsr tb_cell
    jsr text_hex8
    bra @next
@v_empty:
    lda #'-' - 32
    jsr text_puttile
    lda #'-' - 32
    jsr text_puttile
@next:
    inc tmp0
    lda tmp0
    cmp #$04
    bne @cells
    ; running-position marker (any live track inside this table)
    lda #14
    sta text_x
    jsr tb_head
    inc ui_cnt
    lda ui_cnt
    cmp #$10
    beq @done
    jmp @rows
@done:
    rts

; A = cell value at (col tmp0, row ui_cnt)
tb_cell:
    phx
    rep #$30
.ACCU 16
    lda ed_table
    and #$00FF
    asl
    asl
    asl
    asl
    asl
    asl
    sta tmp2
    lda ui_cnt
    and #$00FF
    asl
    asl
    clc
    adc tmp2
    sta tmp2
    lda tmp0
    and #$00FF
    clc
    adc tmp2
    tax
    sep #$20
.ACCU 8
    lda.l $7E0000 + SB_TABLES,x
    plx
    rts

tb_attr:
    pha
    lda ui_cnt
    cmp tb_y
    bne @plain
    lda tmp0
    cmp tb_x
    bne @plain
    rep #$20
.ACCU 16
    lda #ATTR_ACCENT
    sta text_attr
    sep #$20
.ACCU 8
    pla
    rts
@plain:
    rep #$20
.ACCU 16
    lda #ATTR_TEXT
    sta text_attr
    sep #$20
.ACCU 8
    pla
    rts

; playhead: arrow when any live track runs this table at this row
tb_head:
    lda eng_playing
    beq @none
    phx
    ldx #$0000
@scan:
    lda.w trk_tbl,x
    cmp ed_table
    bne @t_next
    lda.w trk_tbl_row,x
    cmp ui_cnt
    bne @t_next
    plx
    rep #$20
.ACCU 16
    lda #ATTR_HILITE
    sta text_attr
    sep #$20
.ACCU 8
    lda #GLYPH_ARROW_R
    jmp text_puttile
@t_next:
    inx
    cpx #TRACKS
    bne @scan
    plx
@none:
    lda #' ' - 32
    rep #$20
.ACCU 16
    ldy #ATTR_TEXT
    sty text_attr
    sep #$20
.ACCU 8
    jmp text_puttile

str_table:  .DB "TABLE ", 0
str_truler: .DB "V  TSP CMD", 0
