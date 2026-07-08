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

; called every frame from the main loop
screen_update:
    lda ui_mode
    beq @splash
    jsr nav_update
    lda ui_mode
    cmp #SCREEN_PHRASE
    beq @phrase
    cmp #SCREEN_CHAIN
    beq @chain
    jmp song_update
@phrase:
    jmp phrase_update
@chain:
    jmp chain_update
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
    beq @done
    lda #$01
    sta a_used
    ; left/right along the spine
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_RIGHT
    sep #$20
.ACCU 8
    beq @try_left
    ; deeper: SONG -> CHAIN -> PHRASE
    lda ui_mode
    cmp #SCREEN_SONG
    beq @to_chain
    cmp #SCREEN_CHAIN
    beq @to_phrase
    rts
@to_chain:
    ; enter the chain under the SONG cursor (if any)
    jsr song_cursor_cell
    cmp #$FF
    beq @done
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
    beq @done
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
    rts
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
