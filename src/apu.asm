; apu.asm — 65816 side of the APU mailbox: IPL upload, command send,
; DSP write path. Every wait here times out (invariant #1): a dead APU
; sets apu_status=1 -> visible "APU?" in the UI, never a hang.

.ACCU 8
.INDEX 16

.DEFINE CMD_NOP       $00
.DEFINE CMD_DSP_WRITE $01

; --- wait until $2140 == A; carry set on timeout ------------------------------
apu_wait_p0:
    sta tmp0
    ldy #$0000
@wait:
    lda APUIO0
    cmp tmp0
    beq @ok
    dey
    bne @wait
    sec
    rts
@ok:
    clc
    rts

; --- upload the driver blob via the IPL ROM protocol, then wait for ready ----
apu_upload_driver:
    lda #$AA
    jsr apu_wait_p0
    bcs @fail
    ; begin transfer to $0200
    ldx #$0200
    stx APUIO2
    lda #$01
    sta APUIO1
    lda #$CC
    sta APUIO0
    jsr apu_wait_p0         ; A still $CC
    bcs @fail
    ; data bytes, index echoed low-byte by the IPL
    ldx #$0000
@loop:
    lda.w driver_blob,x
    sta APUIO1
    txa                     ; low byte of index
    sta APUIO0
    jsr apu_wait_p0
    bcs @fail
    inx
    cpx #(driver_blob_end - driver_blob)
    bne @loop
    ; kick: entry $0200, port0 jumps past the data index
    ldx #$0200
    stx APUIO2
    stz APUIO1
    lda #<(driver_blob_end - driver_blob)
    inc a
    sta APUIO0
    sta apu_seq             ; handshake state starts from the kick byte
    ; driver announces itself
    lda #$EE
    jsr apu_wait_p0
    bcs @fail
    stz apu_status
    clc
    rts
@fail:
    lda #$01
    sta apu_status
    sec
    rts

; --- send command A (0-127) with 16-bit payload X; carry set on timeout ------
; No idle-wait needed: the echo-wait below serializes sends, so the mailbox
; is idle whenever we get here. apu_seq starts from the IPL kick byte, which
; the driver adopted as its initial "last processed" state.
apu_send:
    sta tmp1
    stx APUIO1              ; payload -> ports 1/2
    lda apu_seq
    eor #$80
    and #$80
    ora tmp1                ; flip bit 7, new command in low 7
    sta apu_seq
    sta APUIO0
    lda apu_seq
    jsr apu_wait_p0
    bcs @timeout
    clc
    rts
@timeout:
    lda #$01
    sta apu_status
    sec
    rts

; --- write DSP register: A = reg, Y = value -----------------------------------
apu_dsp_write:
    sta tmp2
    tya
    sta tmp2 + 1
    ldx tmp2                ; lo = reg, hi = value
    lda #CMD_DSP_WRITE
    jmp apu_send

; --- per-frame APU housekeeping (main loop) ------------------------------------
; Mirrors tick telemetry and sends the M2 heartbeat: an incrementing value
; into MVOLL every 64 frames, so checks can watch the full SCB path land in
; the DSP. Replaced by the real diff engine in M3.
apu_update:
    lda APUIO3
    sta apu_tick
    lda apu_status
    bne @done               ; don't hammer a dead mailbox every heartbeat
    rep #$20
.ACCU 16
    lda frame_cnt
    and #$003F
    sep #$20
.ACCU 8
    bne @done
    lda hb_val
    inc a
    and #$3F
    sta hb_val
    tay
    lda #$0C                ; MVOLL
    jsr apu_dsp_write
@done:
    rts
