; screens.asm — screen ids, dispatch, and A-modifier navigation along the
; composing spine of the 2-D screen map (CLAUDE.md §8):
;
;     [S][C][H]   SONG -> CHAIN -> PHRASE   (A held + left/right)
;
; Moving right descends into the cursor's context (SONG cell -> that chain,
; CHAIN cell -> that phrase), exactly like the siblings. The full 13-screen
; map fills in as screens land.

.ACCU 8
.INDEX 16

.DEFINE SCREEN_SPLASH 0
.DEFINE SCREEN_PHRASE 1
.DEFINE SCREEN_CHAIN  2
.DEFINE SCREEN_SONG   3
.DEFINE SCREEN_INSTR  4
.DEFINE SCREEN_FILES  5
.DEFINE SCREEN_ECHO   6
.DEFINE SCREEN_WAVE   7
.DEFINE SCREEN_LIVE   8
.DEFINE SCREEN_KIT    9

; called every frame from the main loop
screen_update:
    lda ui_mode
    beq @splash
    ; Select: jump to LIVE; in LIVE, jump back where you came from
    rep #$20
.ACCU 16
    lda pad_pressed
    and #PAD_SELECT
    sep #$20
.ACCU 8
    beq @no_select
    lda ui_mode
    cmp #SCREEN_LIVE
    beq @leave_live
    jsr live_init
    bra @no_select
@leave_live:
    jsr screen_reopen
@no_select:
    jsr nav_update
    lda ui_mode
    cmp #SCREEN_PHRASE
    beq @phrase
    cmp #SCREEN_CHAIN
    beq @chain
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
    jmp song_update
@phrase:
    jmp phrase_update
@files:
    jmp files_update
@echo:
    jmp echo_update
@wave:
    jmp wave_update
@live:
    jmp live_update
@kit:
    jmp kit_update
@chain:
    jmp chain_update
@instr:
    jmp instr_update
@splash:
    jmp splash_update

; --- A (screen modifier) held + d-pad: navigate the map -------------------------
; Also swallows A-tap (reserved for A+B play-from-cursor later).
nav_update:
    rep #$20
.ACCU 16
    lda pad_pressed
    and #PAD_A
    sep #$20
.ACCU 8
    beq @no_edge
    lda #$01
    sta a_down
    stz a_used
@no_edge:
    rep #$20
.ACCU 16
    lda pad_held
    and #PAD_A
    sep #$20
.ACCU 8
    bne @held
    stz a_down
    rts
@held:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_DPAD
    sep #$20
.ACCU 8
    bne @has_dpad
    rts
@has_dpad:
    lda #$01
    sta a_used
    ; up/down: SONG <-> FILES (the map's vertical axis grows with screens)
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_DOWN
    sep #$20
.ACCU 8
    beq @not_down
    lda ui_mode
    cmp #SCREEN_SONG
    bne @down_not_song
    jsr files_init
    bra @eat_far
@down_not_song:
    cmp #SCREEN_INSTR
    bne @down_not_instr
    jsr echo_init
    bra @eat_far
@down_not_instr:
    cmp #SCREEN_WAVE
    bne @not_down
    jsr instr_init
    bra @eat_far
@not_down:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_UP
    sep #$20
.ACCU 8
    beq @not_up
    lda ui_mode
    cmp #SCREEN_FILES
    bne @up_not_files
    jsr song_init_screen
    bra @eat_far
@up_not_files:
    cmp #SCREEN_ECHO
    bne @up_not_echo
    jsr instr_init
    bra @eat_far
@up_not_echo:
    cmp #SCREEN_INSTR
    bne @not_up
    jsr wave_init
@eat_far:
    rep #$20
.ACCU 16
    lda #$0000
    sta pad_event
    sep #$20
.ACCU 8
    rts
@not_up:
    ; left/right along the spine
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_RIGHT
    sep #$20
.ACCU 8
    beq @try_left
    ; deeper: SONG -> CHAIN -> PHRASE -> INSTR
    lda ui_mode
    cmp #SCREEN_SONG
    beq @to_chain
    cmp #SCREEN_CHAIN
    beq @to_phrase
    cmp #SCREEN_PHRASE
    beq @to_instr
    cmp #SCREEN_WAVE
    bne @no_right
    jsr kit_init
    rep #$20
.ACCU 16
    lda #$0000
    sta pad_event
    sep #$20
.ACCU 8
@no_right:
    rts
@to_instr:
    ; instrument under the phrase cursor row, else the insert default
    jsr phrase_cursor_instr
    cmp #INSTR_NONE
    bne @instr_ok
    lda ed_lastinstr
    cmp #INSTR_NONE
    beq @done_far
    ; fall through with the default
@instr_ok:
    sta ed_instr
    jsr instr_init
    rep #$20
.ACCU 16
    lda #$0000
    sta pad_event
    sep #$20
.ACCU 8
@done_far:
    rts
@to_chain:
    ; enter the chain under the SONG cursor (if any)
    jsr song_cursor_cell
    cmp #$FF
    bne @chain_ok
    rts
@chain_ok:
    sta ed_chain
    jsr chain_init
    ; eat the d-pad event so the new screen's cursor doesn't move
    rep #$20
.ACCU 16
    lda #$0000
    sta pad_event
    sep #$20
.ACCU 8
    rts
@to_phrase:
    jsr chain_cursor_phrase
    cmp #$FF
    bne @phrase_ok
    rts
@phrase_ok:
    sta ed_phrase
    jsr phrase_init
    rep #$20
.ACCU 16
    lda #$0000
    sta pad_event
    sep #$20
.ACCU 8
    rts
@try_left:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_LEFT
    sep #$20
.ACCU 8
    beq @done
    lda ui_mode
    cmp #SCREEN_PHRASE
    beq @to_chain2
    cmp #SCREEN_CHAIN
    beq @to_song
    cmp #SCREEN_INSTR
    beq @to_phrase2
    cmp #SCREEN_KIT
    bne @no_left
    jsr wave_init
    rep #$20
.ACCU 16
    lda #$0000
    sta pad_event
    sep #$20
.ACCU 8
@no_left:
    rts
@to_phrase2:
    jsr phrase_init
    bra @eat
@to_chain2:
    jsr chain_init
    bra @eat
@to_song:
    jsr song_init_screen
@eat:
    rep #$20
.ACCU 16
    lda #$0000
    sta pad_event
    sep #$20
.ACCU 8
@done:
    rts

; true (A returned non-FF) helpers implemented by the screens:
;   song_cursor_cell   -> A = chain id under SONG cursor
;   chain_cursor_phrase-> A = phrase id under CHAIN cursor

; reopen the screen we were on before LIVE
screen_reopen:
    lda live_prev
    cmp #SCREEN_PHRASE
    bne +
    jmp phrase_init
+
    cmp #SCREEN_CHAIN
    bne +
    jmp chain_init
+
    cmp #SCREEN_INSTR
    bne +
    jmp instr_init
+
    cmp #SCREEN_FILES
    bne +
    jmp files_init
+
    cmp #SCREEN_ECHO
    bne +
    jmp echo_init
+
    cmp #SCREEN_WAVE
    bne +
    jmp wave_init
+
    jmp song_init_screen
