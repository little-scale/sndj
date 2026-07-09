; filescr.asm — the FILES screen, genmddj-style: a slot list with names
; and sizes, live renaming, and an action menu.
;
;   Up/Down            pick a slot (empty slots show (EMPTY))
;   B-hold + Left/Right  move the name cursor
;   B-hold + Up/Down     cycle the character (saved slot renames the file;
;                        an empty slot edits the working song's name,
;                        which becomes the file name on SAVE)
;   A + B              open the action menu: SAVE / LOAD / CLEAR /
;                      PURGE PH / PURGE CH (Up/Down choose, B runs and
;                      closes, A cancels). CLEAR closes the gap; LOAD
;                      on the (EMPTY) row blanks the working song;
;                      PURGE blanks phrases/chains not reachable from
;                      the SONG grid and reports FREED nn.
;
; Playback stops on entry, like genmddj. Reached with A+Down from SONG.

.ACCU 8
.INDEX 16

files_init:
    lda #SCREEN_FILES
    sta ui_mode
    stz fl_slot
    stz fl_menu
    stz fl_mitem
    stz fl_ncur
    lda #$FF
    sta fl_msg              ; no message
    jsr engine_stop         ; playback stops while managing files
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
    ldx #str_files
    jsr text_puts
    ; ruler
    lda #5
    sta text_x
    lda #7
    sta text_y
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    sta text_attr
    sep #$20
.ACCU 8
    ldx #str_fruler
    jsr text_puts
    rts

; X = SRAM table offset of slot fl_slot (16 bytes/entry)
fl_entry:
    lda fl_slot
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

files_update:
    lda fl_menu
    beq @no_menu
    jmp files_menu
@no_menu:
    ; A held + B pressed: open the action menu
    lda a_down
    beq @no_ab
    rep #$20
.ACCU 16
    lda pad_pressed
    and #PAD_B
    sep #$20
.ACCU 8
    beq @a_draw
    lda #$01
    sta fl_menu
    stz fl_mitem
    stz fl_freed
    lda #$01
    sta a_used
@a_draw:
    jmp files_draw
@no_ab:
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
    bra @cursor
@b_held:
    ; B-hold + left/right: name cursor; up/down: cycle the character
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_LEFT
    sep #$20
.ACCU 8
    beq @nc_r
    lda #$01
    sta b_used
    lda fl_ncur
    dec a
    and #$07
    sta fl_ncur
@nc_r:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_RIGHT
    sep #$20
.ACCU 8
    beq @nc_ud
    lda #$01
    sta b_used
    lda fl_ncur
    inc a
    and #$07
    sta fl_ncur
@nc_ud:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_UP
    sep #$20
.ACCU 8
    beq @nc_dn
    lda #$01
    sta b_used
    lda #$01
    jsr fl_char_cycle
@nc_dn:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_DOWN
    sep #$20
.ACCU 8
    beq @b_done
    lda #$01
    sta b_used
    lda #$FF
    jsr fl_char_cycle
@b_done:
    jmp files_draw
@cursor:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_UP
    sep #$20
.ACCU 8
    beq @nu
    lda fl_slot
    beq @nu
    dec fl_slot
@nu:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_DOWN
    sep #$20
.ACCU 8
    beq @nd
    inc fl_slot
    jsr fl_clamp
@nd:
    jmp files_draw

; --- the action menu -------------------------------------------------------------
files_menu:
    ; A cancels
    rep #$20
.ACCU 16
    lda pad_pressed
    and #PAD_A
    sep #$20
.ACCU 8
    beq @not_cancel
    stz fl_menu
    lda #$01
    sta a_used
    jmp files_draw
@not_cancel:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_UP
    sep #$20
.ACCU 8
    beq @m_dn
    lda fl_mitem
    dec a
    bpl @m_set
    lda #$04
@m_set:
    sta fl_mitem
@m_dn:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_DOWN
    sep #$20
.ACCU 8
    beq @m_b
    lda fl_mitem
    inc a
    cmp #$05
    bcc @m_set2
    lda #$00
@m_set2:
    sta fl_mitem
@m_b:
    rep #$20
.ACCU 16
    lda pad_pressed
    and #PAD_B
    sep #$20
.ACCU 8
    beq @m_draw
    ; run the action on fl_slot
    stz fl_menu
    lda fl_mitem
    beq @do_save
    cmp #$01
    beq @do_load
    cmp #$02
    beq @do_clear
    cmp #$03
    beq @do_purge_ph
    jsr purge_chains        ; 4: PURGE CH
    bra @purged
@do_purge_ph:
    jsr purge_phrases
@purged:
    lda #SV_FREED
    sta fl_msg
    bra @m_draw
@do_clear:
    lda fl_slot
    jsr slot_clear
    jsr slots_compact       ; the list stays packed, genmddj-style
    jsr fl_clamp
    sta fl_msg
    bra @m_draw
@do_save:
    lda fl_slot
    jsr save_slot
    sta fl_msg
    ora #$80                ; bit7: message reads SAVED
    sta fl_msg
    bra @m_draw
@do_load:
    ; LOAD on the empty row blanks the working song (fresh start)
    jsr fl_entry
    lda.l SRAM_TABLE,x
    cmp #$A5
    beq @load_real
    jsr song_renew
    lda #SV_OK
    sta fl_msg
    bra @m_draw
@load_real:
    lda fl_slot
    jsr load_slot
    sta fl_msg
@m_draw:
    jmp files_draw

; --- naming ------------------------------------------------------------------------
; A = +1 / -1: cycle the character at fl_ncur of the cursor slot's name.
; Saved slot: the SRAM entry (renames the file). Empty slot: the working
; song's header name (becomes the file name on the next SAVE).
fl_char_cycle:
    sta tmp2                ; delta
    jsr fl_entry
    lda.l SRAM_TABLE,x
    cmp #$A5
    beq @sram
    ; empty slot: edit the song header name
    lda fl_ncur
    rep #$30
.ACCU 16
    and #$00FF
    tax
    sep #$20
.ACCU 8
    lda.l $7E0000 + SB_HEADER + SH_NAME,x
    jsr fl_next_char
    sta.l $7E0000 + SB_HEADER + SH_NAME,x
    rts
@sram:
    rep #$30
.ACCU 16
    txa
    clc
    adc #$0006
    sta tmp0                ; entry name base
    lda fl_ncur
    and #$00FF
    clc
    adc tmp0
    tax
    sep #$20
.ACCU 8
    lda.l SRAM_TABLE,x
    jsr fl_next_char
    sta.l SRAM_TABLE,x
    rts

; A = current char -> next/prev char in the name charset (delta in tmp2)
fl_next_char:
    sta tmp0
    ; find it in the charset (unknown chars snap to entry 0 = space)
    ldx #$0000
@find:
    lda.w fl_charset,x
    beq @at0                ; end: not found
    cmp tmp0
    beq @found
    inx
    bra @find
@at0:
    ldx #$0000
@found:
    rep #$30
.ACCU 16
    txa
    sep #$20
.ACCU 8
    clc
    adc tmp2                ; +1 / -1
    bpl @no_wrap_lo
    lda #FL_CHARSET_N - 1
@no_wrap_lo:
    cmp #FL_CHARSET_N
    bcc @ok
    lda #$00
@ok:
    rep #$30
.ACCU 16
    and #$00FF
    tax
    sep #$20
.ACCU 8
    lda.w fl_charset,x
    rts

; --- packed-list helpers -----------------------------------------------------------
; A = number of valid slots (the table stays packed, so this is also
; the index of the (EMPTY) row)
fl_used:
    stz tmp2
    ldx #$0000
@u:
    lda.l SRAM_TABLE,x
    cmp #$A5
    bne @u_next
    inc tmp2
@u_next:
    rep #$30
.ACCU 16
    txa
    clc
    adc #$0010
    tax
    sep #$20
.ACCU 8
    cpx #$0040
    bne @u
    lda tmp2
    rts

; keep the cursor on a saved slot or the single (EMPTY) row
fl_clamp:
    jsr fl_used
    cmp #$04
    bcc +
    lda #$03
+
    cmp fl_slot
    bcs +
    sta fl_slot
+
    rts

; close the gap after a CLEAR: valid entries slide up (three bubble
; passes over the 4-entry table; the status byte moves last)
slots_compact:
    lda #$03
    sta fl_usedv            ; pass counter (scratch)
@pass:
    rep #$30
.ACCU 16
    lda #$0000
    sta pg_i                ; entry base offset (slots 0-2)
    sep #$20
.ACCU 8
@pair:
    rep #$30
.ACCU 16
    lda pg_i
    tax
    sep #$20
.ACCU 8
    lda.l SRAM_TABLE,x
    cmp #$A5
    beq @next
    rep #$30
.ACCU 16
    lda pg_i
    clc
    adc #$0010
    tax
    sep #$20
.ACCU 8
    lda.l SRAM_TABLE,x
    cmp #$A5
    bne @next
    ; copy entry down, bytes 15..1 then the status byte, and blank
    ; the source status so the entry moves rather than duplicates
    lda #$0F
    sta tmp2
@cp:
    rep #$30
.ACCU 16
    lda tmp2
    and #$00FF
    clc
    adc pg_i
    clc
    adc #$0010
    tax
    sep #$20
.ACCU 8
    lda.l SRAM_TABLE,x      ; source byte (slot i+1)
    pha
    rep #$30
.ACCU 16
    lda tmp2
    and #$00FF
    clc
    adc pg_i
    tax
    sep #$20
.ACCU 8
    pla
    sta.l SRAM_TABLE,x      ; dest byte (slot i)
    dec tmp2
    bpl @cp
    ; release the source slot
    rep #$30
.ACCU 16
    lda pg_i
    clc
    adc #$0010
    tax
    sep #$20
.ACCU 8
    lda #$FF
    sta.l SRAM_TABLE,x
@next:
    rep #$30
.ACCU 16
    lda pg_i
    clc
    adc #$0010
    sta pg_i
    cmp #$0030
    sep #$20
.ACCU 8
    bcc @pair_far
    dec fl_usedv
    beq @done
    jmp @pass
@pair_far:
    jmp @pair
@done:
    rts

; --- PURGE: blank phrases/chains not reachable from the SONG grid ------------------
; Reachability marks live in scratch WRAM: chains at $7E:7600 (96),
; phrases at $7E:7700 (192). fl_freed counts what got blanked.
purge_scan:
    ldx #$0000
    lda #$00
@z:
    sta.l $7E7600,x
    inx
    cpx #$0200
    bne @z
    ; every chain referenced by the song grid
    ldx #$0000
@grid:
    lda.l $7E0000 + SB_SONG,x
    cmp #CHAIN_COUNT
    bcs @g_next             ; $FF and out-of-range cells don't mark
    phx
    rep #$30
.ACCU 16
    and #$00FF
    tax
    sep #$20
.ACCU 8
    lda #$01
    sta.l $7E7600,x
    plx
@g_next:
    inx
    cpx #(TRACKS * SONG_ROWS)
    bne @grid
    ; every phrase referenced by a marked chain
    rep #$30
.ACCU 16
    lda #$0000
    sta pg_i                ; chain id
    sep #$20
.ACCU 8
@chain:
    rep #$30
.ACCU 16
    lda pg_i
    tax
    sep #$20
.ACCU 8
    lda.l $7E7600,x
    beq @c_next
    rep #$30
.ACCU 16
    lda pg_i
    asl
    asl
    asl
    asl
    asl                     ; * 32
    sta pg_j
    sep #$20
.ACCU 8
    lda #$10
    sta tmp2                ; 16 entries
@entry:
    rep #$30
.ACCU 16
    lda pg_j
    tax
    sep #$20
.ACCU 8
    lda.l $7E0000 + SB_CHAINS,x
    cmp #PHRASE_COUNT
    bcs @e_next
    phx
    rep #$30
.ACCU 16
    and #$00FF
    tax
    sep #$20
.ACCU 8
    lda #$01
    sta.l $7E7700,x
    plx
@e_next:
    rep #$30
.ACCU 16
    inc pg_j
    inc pg_j
    sep #$20
.ACCU 8
    dec tmp2
    bne @entry
@c_next:
    rep #$30
.ACCU 16
    inc pg_i
    lda pg_i
    cmp #CHAIN_COUNT
    sep #$20
.ACCU 8
    bcc @chain
    rts

purge_chains:
    jsr purge_scan
    stz fl_freed
    rep #$30
.ACCU 16
    lda #$0000
    sta pg_i
    sep #$20
.ACCU 8
@each:
    rep #$30
.ACCU 16
    lda pg_i
    tax
    sep #$20
.ACCU 8
    lda.l $7E7600,x
    bne @keep
    ; unreachable: blank it if it holds anything
    rep #$30
.ACCU 16
    lda pg_i
    asl
    asl
    asl
    asl
    asl
    sta pg_j
    sep #$20
.ACCU 8
    lda #$10
    sta tmp2
    stz tmp0                ; dirty flag
@scan:
    rep #$30
.ACCU 16
    lda pg_j
    tax
    sep #$20
.ACCU 8
    lda.l $7E0000 + SB_CHAINS,x
    cmp #$FF
    beq @s_ok
    lda #$01
    sta tmp0
@s_ok:
    ; wipe as we go (phrase $FF, transpose 0)
    lda #$FF
    sta.l $7E0000 + SB_CHAINS,x
    lda #$00
    sta.l $7E0000 + SB_CHAINS + 1,x
    rep #$30
.ACCU 16
    inc pg_j
    inc pg_j
    sep #$20
.ACCU 8
    dec tmp2
    bne @scan
    lda tmp0
    beq @keep
    inc fl_freed
@keep:
    rep #$30
.ACCU 16
    inc pg_i
    lda pg_i
    cmp #CHAIN_COUNT
    sep #$20
.ACCU 8
    bcc @each
    rts

purge_phrases:
    jsr purge_scan
    stz fl_freed
    rep #$30
.ACCU 16
    lda #$0000
    sta pg_i
    sep #$20
.ACCU 8
@each:
    rep #$30
.ACCU 16
    lda pg_i
    tax
    sep #$20
.ACCU 8
    lda.l $7E7700,x
    bne @keep
    rep #$30
.ACCU 16
    lda pg_i
    xba
    lsr
    lsr                     ; * 64
    sta pg_j
    sep #$20
.ACCU 8
    lda #$10
    sta tmp2                ; 16 rows
    stz tmp0                ; dirty flag
@row:
    rep #$30
.ACCU 16
    lda pg_j
    tax
    sep #$20
.ACCU 8
    lda.l $7E0000 + SB_PHRASES,x       ; note
    bne @dirty
    lda.l $7E0000 + SB_PHRASES + 2,x   ; cmd
    bne @dirty
    lda.l $7E0000 + SB_PHRASES + 3,x   ; val
    beq @wipe
@dirty:
    lda #$01
    sta tmp0
@wipe:
    lda #$00
    sta.l $7E0000 + SB_PHRASES,x
    sta.l $7E0000 + SB_PHRASES + 2,x
    sta.l $7E0000 + SB_PHRASES + 3,x
    lda #INSTR_NONE
    sta.l $7E0000 + SB_PHRASES + 1,x
    rep #$30
.ACCU 16
    lda pg_j
    clc
    adc #$0004
    sta pg_j
    sep #$20
.ACCU 8
    dec tmp2
    bne @row
    lda tmp0
    beq @keep
    inc fl_freed
@keep:
    rep #$30
.ACCU 16
    inc pg_i
    lda pg_i
    cmp #PHRASE_COUNT
    sep #$20
.ACCU 8
    bcc @each
    rts

; --- draw --------------------------------------------------------------------------
files_draw:
    jsr fl_used
    sta fl_usedv            ; the (EMPTY) row index; rows below stay blank
    stz ui_cnt              ; slot counter
@slots:
    lda ui_cnt
    clc
    adc #8
    sta text_y
    ; slot number (accent on the cursor row)
    lda #2
    sta text_x
    lda ui_cnt
    cmp fl_slot
    bne @num_dim
    rep #$20
.ACCU 16
    lda #ATTR_ACCENT
    sta text_attr
    sep #$20
.ACCU 8
    bra @num_put
@num_dim:
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    sta text_attr
    sep #$20
.ACCU 8
@num_put:
    lda ui_cnt
    clc
    adc #'0' - 32
    jsr text_puttile
    ; entry
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
    bne +
    jmp @named
+
    ; the table is packed: only the first free row is the (EMPTY) slot,
    ; anything below it stays blank
    lda ui_cnt
    cmp fl_usedv
    beq @first_free
    lda #5
    sta text_x
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    sta text_attr
    sep #$20
.ACCU 8
    phx
    ldx #str_frowclr
    jsr text_puts
    plx
    jmp @next
@first_free:
    lda ui_cnt
    cmp fl_slot
    beq @empty_named
    lda #5
    sta text_x
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    sta text_attr
    sep #$20
.ACCU 8
    phx
    ldx #str_fempty
    jsr text_puts
    plx
    jmp @next
@empty_named:
    stz sv_run              ; char counter
@ename:
    lda sv_run
    clc
    adc #5
    sta text_x
    jsr fl_name_attr
    lda sv_run
    phx
    rep #$30
.ACCU 16
    and #$00FF
    tax
    sep #$20
.ACCU 8
    lda.l $7E0000 + SB_HEADER + SH_NAME,x
    plx
    sec
    sbc #32
    jsr text_puttile
    inc sv_run
    lda sv_run
    cmp #$08
    bne @ename
    lda #15
    sta text_x
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    sta text_attr
    sep #$20
.ACCU 8
    phx
    ldx #str_fnew
    jsr text_puts
    plx
    jmp @next
@named:
    stz sv_run              ; char counter
@name:
    lda sv_run
    clc
    adc #5
    sta text_x
    jsr fl_name_attr
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
    rep #$30
.ACCU 16
    txa
    sec
    sbc #$0008              ; back to the entry base
    tax
    sep #$20
.ACCU 8
    ; packed size in hex bytes
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
    phx
    ldx #str_bytes
    jsr text_puts
    plx
@next:
    inc ui_cnt
    lda ui_cnt
    cmp #SLOT_COUNT
    beq @menu
    jmp @slots
@menu:
    ; action menu column (blank when closed)
    stz ui_cnt
@mrow:
    lda ui_cnt
    clc
    adc #8
    sta text_y
    lda #23
    sta text_x
    lda fl_menu
    beq @m_blank
    lda ui_cnt
    cmp fl_mitem
    bne @m_dim
    rep #$20
.ACCU 16
    lda #ATTR_ACCENT
    sta text_attr
    sep #$20
.ACCU 8
    bra @m_txt
@m_dim:
    rep #$20
.ACCU 16
    lda #ATTR_TEXT
    sta text_attr
    sep #$20
.ACCU 8
@m_txt:
    lda ui_cnt
    rep #$30
.ACCU 16
    and #$00FF
    asl
    tax
    lda.w fl_menu_tab,x
    tax
    sep #$20
.ACCU 8
    jsr text_puts
    bra @m_next
@m_blank:
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    sta text_attr
    sep #$20
.ACCU 8
    ldx #str_fblank
    jsr text_puts
@m_next:
    inc ui_cnt
    lda ui_cnt
    cmp #$05
    bne @mrow
    ; used-slots readout
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
    ldx #str_fused
    jsr text_puts
    stz ui_cnt
    stz sv_run              ; used counter
@count:
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
    bne @c_next
    inc sv_run
@c_next:
    inc ui_cnt
    lda ui_cnt
    cmp #SLOT_COUNT
    bne @count
    lda sv_run
    clc
    adc #'0' - 32
    jsr text_puttile
    lda #'/' - 32
    jsr text_puttile
    lda #'4' - 32
    jsr text_puttile
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
    ldx #str_fpad
    jmp text_puts
@have_msg:
    and #$7F
    cmp #SV_OK
    bne @not_ok
    lda fl_msg
    bmi @saved
    ldx #str_floaded
    jmp text_puts
@saved:
    ldx #str_fsaved
    jmp text_puts
@not_ok:
    cmp #SV_FULL
    bne @not_full
    ldx #str_ffull
    jmp text_puts
@not_full:
    cmp #SV_EMPTY
    bne @not_empty
    ldx #str_fnoempty
    jmp text_puts
@not_empty:
    cmp #SV_FREED
    bne @badcrc
    ldx #str_ffreed
    jsr text_puts
    lda fl_freed
    rep #$30
.ACCU 16
    and #$00FF
    sta tmp0
    sep #$20
.ACCU 8
    jmp text_dec3
@badcrc:
    ldx #str_fbadcrc
    jmp text_puts

; name char attr: accent under the name cursor of the cursor slot while
; B is held (naming), text otherwise
fl_name_attr:
    pha
    lda ui_cnt
    cmp fl_slot
    bne @plain
    lda b_down
    beq @plain
    lda sv_run
    cmp fl_ncur
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

.DEFINE FL_CHARSET_N 39
fl_charset:  .DB " ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-.", 0

fl_menu_tab: .DW str_fsave, str_fload, str_fclear, str_fpurgep, str_fpurgec

str_files:   .DB "FILES", 0
str_fruler:  .DB "NAME      SIZE", 0
str_fempty:  .DB "(EMPTY)   ", 0
str_fnew:    .DB " NEW", 0
str_bytes:   .DB "B", 0
str_fused:   .DB "SLOTS USED ", 0
str_fsave:   .DB "SAVE ", 0
str_fload:   .DB "LOAD ", 0
str_fclear:  .DB "CLEAR", 0
str_fpurgep: .DB "PURGE PH", 0
str_fpurgec: .DB "PURGE CH", 0
str_ffreed:  .DB "FREED ", 0
str_frowclr: .DB "               ", 0
str_fblank:  .DB "        ", 0
str_fpad:    .DB "        ", 0
str_fsaved:  .DB "SAVED   ", 0
str_floaded: .DB "LOADED  ", 0
str_ffull:   .DB "FULL    ", 0
str_fnoempty: .DB "EMPTY   ", 0
str_fbadcrc: .DB "BAD CRC ", 0
