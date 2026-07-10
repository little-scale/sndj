; instrscr.asm — the INSTR screen: field-list editor over the 16-byte
; instrument record, grouped (identity / envelope / mix / tune+motion /
; chord / table) and type-aware: fields a type doesn't use are hidden
; (KIT slots own their volume+tune; NSE has no sample or pitch).
; B held + d-pad nudges the field (L/R = 1, U/D = 4, clamped); B tap
; auditions C-4 with this instrument; Y + up/down flips instruments.
; Edits invalidate every voice's loaded-instrument shadow so changes
; are heard immediately.
;
; Scratch layout (text_* own tmp0/tmp1; apu_send owns tmp1):
;   str_buf+34/35  shift work / pending delta
;   str_buf+36..39 field descriptor: mask, max, byte offset, shift

.ACCU 8
.INDEX 16

.DEFINE IF_COUNT 22

; field table, in DISPLAY order: byte offset in record, shift, value
; mask (post-shift), max
if_fields:
    .DB 0,  0, $3F, 63   ; 0  INSTR — the number itself (pseudo-field)
    .DB 0,  0, $07, 4    ; 1  TYPE
    .DB 1,  0, $FF, 63   ; 2  SAMPLE / KIT / BANK (max re-clamped per type)
    .DB 7,  4, $0F, 15   ; 3  SLICES (drawn +1: 01-10 equal divisions)
    .DB 2,  0, $0F, 15   ; 4  ATTACK
    .DB 2,  4, $0F, 15   ; 5  FADE (SLICE: cut rate; 0 = ring/bleed)
    .DB 2,  4, $07, 7    ; 6  DECAY
    .DB 3,  5, $07, 7    ; 7  SUS LVL
    .DB 3,  0, $1F, 31   ; 8  SUS RATE
    .DB 4,  0, $FF, 127  ; 9  VOL L
    .DB 5,  0, $FF, 127  ; 10 VOL R
    .DB 7,  0, $01, 1    ; 11 EON (echo send)
    .DB 6,  0, $FF, 255  ; 12 FINE (signed 1/256 semitone; free wrap)
    .DB 14, 0, $FF, 255  ; 13 VIB speed/depth nibbles (free wrap)
    .DB 15, 0, $FF, 255  ; 14 TRM speed/depth nibbles (free wrap)
    .DB 9,  0, $FF, 255  ; 15 TUNE (SLICE: signed semitones; free wrap)
    .DB 8,  0, $03, 3    ; 16 GRP
    .DB 9,  0, $FF, 24   ; 17 OFS 1
    .DB 10, 0, $FF, 24   ; 18 OFS 2
    .DB 11, 0, $FF, 24   ; 19 OFS 3
    .DB 12, 0, $FF, 255  ; 20 TBL (>= 32 shows -- = no table; free wrap)
    .DB 13, 0, $0F, 15   ; 21 TBS ticks/row (0 = advance per note)

; screen row per field: blank rows separate the groups (fields with
; exclusive visibility may share a row: FADE/DECAY, TUNE/GRP)
if_row:
    .DB 0, 1, 2, 3                 ; number + identity (+ SLICES)
    .DB 4, 5, 5, 6, 7              ; envelope (FADE on DECAY's row)
    .DB 9, 10, 11                  ; mix + send
    .DB 13, 14, 15                 ; tune + motion
    .DB 17, 17, 18, 19, 20         ; chord span (TUNE on GRP's row)
    .DB 22, 23                     ; table

; visibility per type (bit 0 SMP, 1 KIT, 2 WAV, 3 NSE, 4 SLICE): a type
; hides the fields its trigger path never reads
if_vis:
    .DB $1F              ; INSTR number
    .DB $1F              ; TYPE
    .DB $1F              ; SAMPLE / KIT / BANK / CLOCK
    .DB $10              ; SLICES (SLICE only)
    .DB $1F              ; ATTACK
    .DB $10              ; FADE (SLICE only)
    .DB $0F, $0F, $0F    ; DECAY/SUS: SLICE synthesizes its envelope
    .DB $1D, $1D         ; VOL L/R (KIT: the slot's vol rules)
    .DB $1F              ; ECHO
    .DB $15              ; FINE (KIT: slot+pool tune; NSE: no pitch)
    .DB $15              ; VIB  (pitch wobble: SMP/WAV/SLICE)
    .DB $1D              ; TRM  (KIT: slot volume domain)
    .DB $10              ; TUNE (SLICE only)
    .DB $05, $05, $05, $05   ; GRP+OFS (kit ids aren't pool samples; NSE unison is noise)
    .DB $1F, $1F         ; TBL/TBS

if_labels:
    .DW if_lnum
    .DW if_l0, if_l1, if_lsli, if_l2, if_lfad, if_l3, if_l4, if_l5
    .DW if_l6, if_l7, if_l12, if_l13, if_l14, if_l15, if_ltun
    .DW if_l8, if_l9, if_l10, if_l11, if_l16, if_l17
if_lnum: .DB "INSTR", 0
if_l0:  .DB "TYPE", 0
if_l1:  .DB "SAMPLE", 0
if_l1k: .DB "KIT   ", 0
if_l1w: .DB "BANK  ", 0
if_l1n: .DB "CLOCK ", 0
if_l2:  .DB "ATTACK", 0
if_l3:  .DB "DECAY", 0
if_l4:  .DB "SUS LVL", 0
if_l5:  .DB "SUS RATE", 0
if_l6:  .DB "VOL L", 0
if_l7:  .DB "VOL R", 0
if_l8:  .DB "GRP", 0
if_l9:  .DB "OFS 1", 0
if_l10: .DB "OFS 2", 0
if_l11: .DB "OFS 3", 0
if_l12: .DB "ECHO", 0
if_l13: .DB "FINE", 0
if_l14: .DB "VIB", 0
if_l15: .DB "TRM", 0
if_l16: .DB "TBL", 0
if_l17: .DB "TBS", 0
if_lsli: .DB "SLICES", 0
if_lfad: .DB "FADE", 0
if_ltun: .DB "TUNE", 0

; A = 1 << current instrument's type
if_typebit:
    lda ed_instr
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
    rep #$30
.ACCU 16
    and #$00FF
    tax
    sep #$20
.ACCU 8
    lda.w bit_for_track,x
    rts

; carry set when field A is visible for the current type; preserves A
if_field_vis:
    pha
    rep #$30
.ACCU 16
    and #$00FF
    tax
    sep #$20
.ACCU 8
    lda.w if_vis,x
    sta tmp2 + 1
    jsr if_typebit
    and tmp2 + 1
    beq @no
    pla
    sec
    rts
@no:
    pla
    clc
    rts

if_types:
    .DB "SMPKITWAVNSESLC"  ; 3 chars each

instr_init:
    lda #SCREEN_INSTR
    sta ui_mode
    stz if_cur
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
    ldx #str_instr
    jsr text_puts
    rts

; load field if_cur's descriptor into str_buf+36.. and X = record-relative
; byte offset (SB_INSTR + ed_instr*16 + field offset)
if_desc:
    lda if_cur
    rep #$30
.ACCU 16
    and #$00FF
    asl
    asl                     ; *4
    tax
    sep #$20
.ACCU 8
    lda.w if_fields + 2,x
    sta str_buf + 36        ; mask
    lda.w if_fields + 3,x
    sta str_buf + 37        ; max
    lda.w if_fields,x
    sta str_buf + 38        ; byte offset
    lda.w if_fields + 1,x
    sta str_buf + 39        ; shift
    ; the SAMPLE field's range follows the type: KIT 0-15, WAV bank
    ; 0-7, NSE clock 0-32 (0 = follow the note)
    lda if_cur
    cmp #$02
    bne @max_ok
    jsr if_typebit
    cmp #$02                ; KIT
    bne @not_kitmax
    lda #15
    sta str_buf + 37
    bra @max_ok
@not_kitmax:
    cmp #$04                ; WAV
    bne @not_wavmax
    lda #7
    sta str_buf + 37
    bra @max_ok
@not_wavmax:
    cmp #$08                ; NSE
    bne @max_ok
    lda #32
    sta str_buf + 37
@max_ok:
    rep #$30
.ACCU 16
    lda ed_instr
    and #$00FF
    asl
    asl
    asl
    asl
    sta tmp2
    lda str_buf + 38
    and #$00FF
    clc
    adc tmp2
    tax
    sep #$20
.ACCU 8
    rts

; A = field value (descriptor loaded, X = record offset); preserves X
if_get_x:
    lda.l $7E0000 + SB_INSTR,x
    sta str_buf + 34
    lda str_buf + 39
    beq @done
@shift:
    lsr str_buf + 34
    dec a
    bne @shift
@done:
    lda str_buf + 34
    and str_buf + 36
    rts

; write field value A (unshifted, pre-clamped); descriptor + X loaded
if_set_x:
    sta str_buf + 34
    ; shifted mask + shifted value
    lda str_buf + 36
    sta str_buf + 35
    lda str_buf + 39
    beq @aligned
@shift:
    asl str_buf + 34
    asl str_buf + 35
    dec a
    bne @shift
@aligned:
    lda str_buf + 35
    eor #$FF
    sta str_buf + 35        ; inverted field mask
    lda.l $7E0000 + SB_INSTR,x
    and str_buf + 35
    ora str_buf + 34
    sta.l $7E0000 + SB_INSTR,x
    ; force reload on every voice
    phx
    ldx #$0000
    lda #$FF
@inval:
    sta.w trk_instr_active,x
    inx
    cpx #TRACKS
    bne @inval
    plx
    rts

instr_update:
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
    jmp instr_draw
@edit_ok:
    ; Y held + up/down: previous / next instrument (as PHRASE/TABLE do)
    rep #$20
.ACCU 16
    lda pad_held
    and #PAD_Y
    sep #$20
.ACCU 8
    beq @no_y
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_UP
    sep #$20
.ACCU 8
    beq @y_dn
    lda ed_instr
    dec a
    and #(INSTR_COUNT - 1)
    sta ed_instr
    jsr if_cur_fix
    jmp instr_draw
@y_dn:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_DOWN
    sep #$20
.ACCU 8
    beq @y_done
    lda ed_instr
    inc a
    and #(INSTR_COUNT - 1)
    sta ed_instr
    jsr if_cur_fix
    jmp instr_draw
@y_done:
    jmp instr_draw
@no_y:
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
    ; tap: audition this instrument at C-4
    lda ed_instr
    sta ed_lastinstr
    lda #48
    jsr audition_note
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
    jsr if_nudge
    bra @draw
@cursor:
    ; plain up/down moves the field cursor, skipping hidden fields
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_UP
    sep #$20
.ACCU 8
    beq @nu
    lda if_cur
@up_next:
    dec a
    bpl @up_vis
    lda #IF_COUNT - 1
@up_vis:
    jsr if_field_vis
    bcc @up_next
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
@dn_next:
    inc a
    cmp #IF_COUNT
    bcc @dn_vis
    lda #$00
@dn_vis:
    jsr if_field_vis
    bcc @dn_next
    sta if_cur
@draw:
    jmp instr_draw

; after an instrument switch the cursor may sit on a hidden field
if_cur_fix:
    lda if_cur
    jsr if_field_vis
    bcs @ok
    stz if_cur              ; TYPE is always visible
@ok:
    rts

if_nudge:
    ; big step (U/D): the high nibble for byte fields, an octave for
    ; the semitone fields (TUNE, OFS 1-3), 4 for short ranges; L/R
    ; always steps 1
    lda if_cur
    cmp #15
    beq @mag_semi           ; TUNE
    cmp #17
    bcc @mag_std
    cmp #20
    bcs @mag_std
@mag_semi:
    lda #12                 ; semitones
    bra @mag_have
@mag_std:
    lda if_cur
    rep #$30
.ACCU 16
    and #$00FF
    asl
    asl
    tax
    sep #$20
.ACCU 8
    lda.w if_fields + 3,x   ; the field's max
    cmp #16
    bcc @mag_small
    lda #16
    bra @mag_have
@mag_small:
    lda #4
@mag_have:
    sta tmp2
    jsr nudge_delta         ; -> tmp1+1 (nudge_delta uses tmp2 as magnitude)
    lda tmp1 + 1
    bne @have
    rts
@have:
    sta str_buf + 35        ; pending delta (if_desc clobbers tmp1/tmp2? no,
                            ; but if_get_x reuses +34; keep delta at +35 until
                            ; the add, then let if_set_x reuse it)
    lda if_cur
    bne @record_field
    ; field 0 nudges the NUMBER: switch which instrument is edited
    lda ed_instr
    clc
    adc str_buf + 35
    and #(INSTR_COUNT - 1)
    sta ed_instr
    rts
@record_field:
    jsr if_desc
    jsr if_get_x
    clc
    adc str_buf + 35
    ; power-of-two ranges WRAP (nibble editing); the rest clamp
    pha
    lda str_buf + 37
    inc a
    and str_buf + 37
    bne @clamped
    pla
    and str_buf + 37
    bra @store
@clamped:
    pla
    bpl @not_neg
    lda #$00
@not_neg:
    cmp str_buf + 37
    bcc @in_range
    beq @in_range
    ; distinguish small overflow (clamp to max) from underflow wrap
    lda str_buf + 35
    bmi @clamp_lo
    lda str_buf + 37
    bra @store
@clamp_lo:
    lda #$00
    bra @store
@in_range:
@store:
    jsr if_set_x
    ; type / sample / slice-count edits change the resident set and
    ; the slice alias windows
    lda if_cur
    beq @no_res
    cmp #$04
    bcs @no_res
    jsr residency_build
@no_res:
    rts

instr_draw:
    stz ui_cnt
@rows:
    ; row position from the group map
    lda ui_cnt
    rep #$30
.ACCU 16
    and #$00FF
    tax
    sep #$20
.ACCU 8
    lda.w if_row,x
    clc
    adc #4
    sta text_y
    lda #2
    sta text_x
    ; fields the current type never reads draw blank — unless a visible
    ; field shares the row (FADE/DECAY, TUNE/GRP): blanking would erase it
    lda ui_cnt
    jsr if_field_vis
    bcs @shown
    jsr if_row_shared
    bcc @blank_ok
    jmp @next
@blank_ok:
    rep #$20
.ACCU 16
    lda #ATTR_TEXT
    sta text_attr
    sep #$20
.ACCU 8
    ldx #str_if_blank
    jsr text_puts
    jmp @next
@shown:
    ; labels stay dim; the VALUE carries the cursor accent
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    sta text_attr
    sep #$20
.ACCU 8
@label:
    ; the SAMPLE row reads KIT / BANK / CLOCK on those types
    lda ui_cnt
    cmp #$02
    bne @lab_std
    jsr if_typebit
    cmp #$02
    bne @not_klab
    ldx #if_l1k
    bra @lab_put
@not_klab:
    cmp #$04
    bne @not_wlab
    ldx #if_l1w
    bra @lab_put
@not_wlab:
    cmp #$08
    bne @lab_std
    ldx #if_l1n
    bra @lab_put
@lab_std:
    lda ui_cnt
    rep #$30
.ACCU 16
    and #$00FF
    asl
    tax
    lda.w if_labels,x
    tax
    sep #$20
.ACCU 8
@lab_put:
    jsr text_puts
    ; value at x12 (text colour)
    lda #12
    sta text_x
    lda ui_cnt
    cmp if_cur
    beq @val_attr_done      ; keep accent on the cursor row's value too
    rep #$20
.ACCU 16
    lda #ATTR_TEXT
    sta text_attr
    sep #$20
.ACCU 8
@val_attr_done:
    lda if_cur
    pha
    lda ui_cnt
    sta if_cur              ; borrow the descriptor path for this row
    jsr if_desc
    jsr if_get_x
    sta str_buf + 33
    pla
    sta if_cur
    lda ui_cnt
    cmp #$0B
    bne @not_echo_v
    ; ECHO: a toggle reads ON/OFF, not 00/01
    lda str_buf + 33
    beq @e_off
    phx
    ldx #str_if_on
    jsr text_puts
    plx
    jmp @next
@e_off:
    phx
    ldx #str_if_off
    jsr text_puts
    plx
    jmp @next
@not_echo_v:
    cmp #$14
    bne @not_tbl_v
    ; TBL: anything past the 32 tables is the nil state
    lda str_buf + 33
    cmp #$20
    bcc @tbl_hex
    phx
    ldx #str_if_nil
    jsr text_puts
    plx
    jmp @next
@tbl_hex:
    lda str_buf + 33
    jsr text_hex8
    jmp @next
@not_tbl_v:
    lda ui_cnt
    cmp #$02
    bne @not_clk_v
    jsr if_typebit
    cmp #$08
    bne @not_clk_v
    ; NSE CLOCK: 0 = follow the note, else the fixed rate (value-1)
    lda str_buf + 33
    bne @clk_fixed
    phx
    ldx #str_if_note
    jsr text_puts
    plx
    jmp @next
@clk_fixed:
    dec a
    jsr text_hex8
    lda #' ' - 32
    jsr text_puttile
    jmp @next
@not_clk_v:
    lda ui_cnt
    cmp #$03
    bne @not_sli_v
    ; SLICES: the stored nibble is divisions-1
    lda str_buf + 33
    inc a
    jsr text_hex8
    jmp @next
@not_sli_v:
    lda ui_cnt
    bne @not_num_v
    ; INSTR: the edited instrument's number
    lda ed_instr
    jsr text_hex8
    jmp @next
@not_num_v:
    cmp #$01
    bne @hex
    ; TYPE: 3-char name (fetch all chars first; text_puttile clobbers X)
    lda str_buf + 33
    asl
    clc
    adc str_buf + 33        ; *3
    rep #$30
.ACCU 16
    and #$00FF
    tax
    sep #$20
.ACCU 8
    lda.w if_types,x
    sta str_buf + 30
    lda.w if_types + 1,x
    sta str_buf + 31
    lda.w if_types + 2,x
    sta str_buf + 32
    lda str_buf + 30
    sec
    sbc #32
    jsr text_puttile
    lda str_buf + 31
    sec
    sbc #32
    jsr text_puttile
    lda str_buf + 32
    sec
    sbc #32
    jsr text_puttile
    bra @next
@hex:
    lda str_buf + 33
    jsr text_hex8
@next:
    inc ui_cnt
    lda ui_cnt
    cmp #IF_COUNT
    beq @done
    jmp @rows
@done:
    rts

; carry set when another, VISIBLE field shares field ui_cnt's screen row
if_row_shared:
    lda ui_cnt
    rep #$30
.ACCU 16
    and #$00FF
    tax
    sep #$20
.ACCU 8
    lda.w if_row,x
    sta str_buf + 30        ; the row under test
    stz str_buf + 31        ; scan index
@scan:
    lda str_buf + 31
    cmp ui_cnt
    beq @skip
    rep #$30
.ACCU 16
    and #$00FF
    tax
    sep #$20
.ACCU 8
    lda.w if_row,x
    cmp str_buf + 30
    bne @skip
    lda str_buf + 31
    jsr if_field_vis
    bcs @yes
@skip:
    inc str_buf + 31
    lda str_buf + 31
    cmp #IF_COUNT
    bne @scan
    clc
    rts
@yes:
    sec
    rts

str_instr: .DB "INSTR ", 0
str_if_blank: .DB "                   ", 0
str_if_on:  .DB "ON ", 0
str_if_off: .DB "OFF", 0
str_if_nil: .DB "-- ", 0
str_if_note: .DB "NOTE", 0
