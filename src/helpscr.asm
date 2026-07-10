; helpscr.asm — the HELP screen, genmddj-style: a paged, read-only
; reference generated from help.txt (tools/makehelp.py -> build/help.inc,
; data in bank 6). Plain d-pad turns pages (wrapping); the indicator
; under the title reads N/M. Reached above TABLE (vertically only), or
; from ANY screen by holding A alone for ~2.5 s — which toggles back to
; where you came from (help_prev, tracked by the hotkey).

.ACCU 8
.INDEX 16

.DEFINE HELP_HOLD 150       ; lone-A frames to toggle (2.5 s NTSC)

help_init:
    lda #SCREEN_HELP
    sta ui_mode
    stz help_page
    jsr text_clear
    jsr help_draw_page
    rts

help_update:
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
    bne @done               ; A-held = map navigation, not page turns
    ; plain d-pad: right/down = next page, left/up = previous (wrap)
    rep #$20
.ACCU 16
    lda pad_event
    and #(PAD_RIGHT | PAD_DOWN)
    sep #$20
.ACCU 8
    beq @try_prev
    lda help_page
    inc a
    cmp #HELP_PAGES
    bcc @have
    lda #$00
    bra @have
@try_prev:
    rep #$20
.ACCU 16
    lda pad_event
    and #(PAD_LEFT | PAD_UP)
    sep #$20
.ACCU 8
    beq @done
    lda help_page
    dec a
    bpl @have
    lda #HELP_PAGES - 1
@have:
    sta help_page
    jsr text_clear
    jsr help_draw_page
@done:
    rts

; ---- the page renderer: walks the help_data byte stream -----------------------
;   $FF end · $00 blank row · $01 version stamp · $02 text · $03 title
help_draw_page:
    ; title + N/M page indicator
    stz text_x
    lda #1
    sta text_y
    rep #$20
.ACCU 16
    lda #ATTR_HILITE
    sta text_attr
    sep #$20
.ACCU 8
    ldx #str_help
    jsr text_puts
    lda #6
    sta text_x
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    sta text_attr
    sep #$20
.ACCU 8
    lda help_page
    inc a
    clc
    adc #'0' - 32
    jsr text_puttile
    lda #'/' - 32
    jsr text_puttile
    lda #HELP_PAGES
    clc
    adc #'0' - 32
    jsr text_puttile
    ; body from row 8: clear of the right-side chrome (the genmddj rule)
    lda #8
    sta.w str_buf + 26      ; screen row
    lda help_page
    rep #$30
.ACCU 16
    and #$00FF
    asl
    tax
    lda.l help_pgtab,x      ; page offset (16-bit read of the .DW)
    sta.w str_buf + 24      ; stream cursor
    sep #$20
.ACCU 8
@line:
    rep #$30
.ACCU 16
    ldx.w str_buf + 24
    sep #$20
.ACCU 8
    lda.l help_data,x
    cmp #$FF
    bne @not_end
    rts
@not_end:
    cmp #$00
    bne @not_blank
    jsr @advance1
    bra @row_done
@not_blank:
    cmp #$01
    bne @not_ver
    ; the live version + build stamp
    jsr @advance1
    lda #1
    sta text_x
    lda.w str_buf + 26
    sta text_y
    rep #$20
.ACCU 16
    lda #ATTR_TEXT
    sta text_attr
    sep #$20
.ACCU 8
    ldx #str_version
    jsr text_puts
    lda #' ' - 32
    jsr text_puttile
    ldx #str_stamp
    jsr text_puts
    bra @row_done
@not_ver:
    ; a text ($02) or title ($03) line
    cmp #$03
    bne @plain
    rep #$20
.ACCU 16
    lda #ATTR_ACCENT
    sta text_attr
    sep #$20
.ACCU 8
    bra @attr_done
@plain:
    rep #$20
.ACCU 16
    lda #ATTR_TEXT
    sta text_attr
    sep #$20
.ACCU 8
@attr_done:
    jsr @advance1
    lda #1
    sta text_x
    lda.w str_buf + 26
    sta text_y
@chars:
    rep #$30
.ACCU 16
    ldx.w str_buf + 24
    sep #$20
.ACCU 8
    lda.l help_data,x
    jsr @advance1
    cmp #$00
    beq @row_done
    sec
    sbc #32
    jsr text_puttile
    bra @chars
@row_done:
    lda.w str_buf + 26
    inc a
    sta.w str_buf + 26
    jmp @line

@advance1:
    rep #$30
.ACCU 16
    inc.w str_buf + 24
    sep #$20
.ACCU 8
    rts

; ---- the hotkey: a LONE A held ~2.5 s toggles HELP <-> where you were ---------
; Any other button or d-pad resets the counter, so A-modifier gestures
; never accumulate. Once fired it holds until release (no re-fire).
; Runs every frame from screen_update.
help_hotkey:
    ; real-frame delta: heavy screens run the main loop under 60 fps,
    ; so the hold is measured against the NMI frame counter (the DAS
    ; lesson)
    lda frame_cnt
    sec
    sbc help_lfc
    sta tmp2
    lda frame_cnt
    sta help_lfc
    lda ui_mode
    beq @reset              ; not on the splash
    cmp #SCREEN_HELP
    beq @counting
    sta help_prev           ; track the last non-HELP screen
@counting:
    rep #$20
.ACCU 16
    lda pad_held
    and #$FFFF
    cmp #PAD_A              ; A and ONLY A
    sep #$20
.ACCU 8
    bne @reset
    lda help_actr
    cmp #HELP_HOLD
    bcs @done               ; already fired: wait for release
    clc
    adc tmp2
    bcc @acc_ok
    lda #$FF
@acc_ok:
    sta help_actr
    cmp #HELP_HOLD
    bcc @done
    ; toggle
    lda ui_mode
    cmp #SCREEN_HELP
    beq @leave
    jsr help_init
    rts
@leave:
    jsr help_reopen
    rts
@reset:
    stz help_actr
@done:
    rts

; back to the screen the hotkey came from
help_reopen:
    lda help_prev
    cmp #SCREEN_SONG
    beq @song
    cmp #SCREEN_CHAIN
    beq @chain
    cmp #SCREEN_PHRASE
    beq @phrase
    cmp #SCREEN_INSTR
    beq @instr
    cmp #SCREEN_FILES
    beq @files
    cmp #SCREEN_ECHO
    beq @echo
    cmp #SCREEN_WAVE
    beq @wave
    cmp #SCREEN_LIVE
    beq @live
    cmp #SCREEN_KIT
    beq @kit
    cmp #SCREEN_OPTIONS
    beq @options
    cmp #SCREEN_GROOVE
    beq @groove
    cmp #SCREEN_PROJECT
    beq @project
    cmp #SCREEN_FIR
    beq @fir
    cmp #SCREEN_TABLE
    beq @table
    jmp song_init_screen
@song:
    jmp song_init_screen
@chain:
    jmp chain_init
@phrase:
    jmp phrase_init
@instr:
    jmp instr_init
@files:
    jmp files_init
@echo:
    jmp echo_init
@wave:
    jmp wave_init
@live:
    jmp live_init
@kit:
    jmp kit_init
@options:
    jmp options_init
@groove:
    jmp groove_init
@project:
    jmp project_init
@fir:
    jmp fir_init
@table:
    jmp table_init

; ---- boot hint: "HOLD A TO VIEW HELP" over the SONG title for ~3 s ------------
; Ticks from the main loop; only draws while SONG is up.
hint_tick:
    rep #$30
.ACCU 16
    lda hint_ctr
    beq @off
    dec a
    sta hint_ctr
    sep #$20
.ACCU 8
    lda ui_mode
    cmp #SCREEN_SONG
    bne @done
    rep #$30
.ACCU 16
    lda hint_ctr
    bne @show
    sep #$20
.ACCU 8
    ; expired: give the title back
    stz text_x
    lda #1
    sta text_y
    rep #$20
.ACCU 16
    lda #ATTR_HILITE
    sta text_attr
    sep #$20
.ACCU 8
    ldx #str_hint_wipe
    jmp text_puts
@show:
.ACCU 16
    sep #$20
.ACCU 8
    stz text_x
    lda #1
    sta text_y
    rep #$20
.ACCU 16
    lda #ATTR_ACCENT
    sta text_attr
    sep #$20
.ACCU 8
    ldx #str_hint_help
    jmp text_puts
@off:
.ACCU 16
    sep #$20
.ACCU 8
@done:
    rts

str_help:      .DB "HELP ", 0
str_hint_help: .DB "HOLD A TO VIEW HELP", 0
str_hint_wipe: .DB "SONG               ", 0
