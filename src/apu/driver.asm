; ============================================================================
; sndj SPC700 driver — pure chip servant (CLAUDE.md §3.1)
;
; Holds no song state. Drains mailbox commands into the DSP, runs the
; timer-derived master tick, reports telemetry on port 3.
;
; Mailbox protocol (§3.2):
;   CPU->APU: ports 1/2 = 16-bit payload, then port 0 = (flip<<7 | cmd).
;   The driver processes on any port-0 change and echoes the exact byte
;   back on its port 0 when done. The CPU alternates bit 7 per command, so
;   consecutive identical commands still differ.
;   APU->CPU: port 3 = master tick counter (low byte), continuously.
;
; Loaded at $0200 by the IPL protocol. Only this file ever touches $F2/$F3
; (invariant #2).
; ============================================================================

.MEMORYMAP
  DEFAULTSLOT 0
  SLOT 0 START $0200 SIZE $0E00
.ENDME
.ROMBANKSIZE $0E00
.ROMBANKS 1

; --- hardware registers ------------------------------------------------------
.DEFINE rTEST     $F0
.DEFINE rCONTROL  $F1
.DEFINE rDSPADDR  $F2
.DEFINE rDSPDATA  $F3
.DEFINE rPORT0    $F4
.DEFINE rPORT1    $F5
.DEFINE rPORT2    $F6
.DEFINE rPORT3    $F7
.DEFINE rT0TARGET $FA
.DEFINE rT0OUT    $FD

; --- commands (port 0 low 7 bits) --------------------------------------------
.DEFINE CMD_NOP       $00
.DEFINE CMD_DSP_WRITE $01   ; port1 = dsp reg, port2 = value
.DEFINE CMD_UPLOAD    $02   ; ports1/2 = dest ARAM addr; then bulk stream:
                            ;   port0 = 1..255 (cycling, !=0), ports1-3 = 3 data
                            ;   bytes each round, echoed; port0 = 0 ends bulk
.DEFINE CMD_TICKRATE  $03   ; port1 = Timer-0 target (engine tick divider)
.DEFINE CMD_ECHO_CFG  $04   ; port1 = new EDL (0-15), port2 = new ESA page.
                            ; Runs the erratum-safe sequence: mute + ECEN off,
                            ; wait out the OLD delay, move ESA/EDL, zero the
                            ; new buffer, re-enable. (CLAUDE.md invariant #4)

; --- zero-page state ----------------------------------------------------------
.ENUM $0010
last_cmd  db      ; last port-0 byte processed
tick      db      ; master tick counter (T0-derived)
dest_lo   db      ; bulk upload write pointer
dest_hi   db
cur_edl   db      ; currently configured echo delay
cur_esa   db
wait_cnt  db
new_edl   db      ; latched CMD_ECHO_CFG payload (ports change under us)
new_esa   db
.ENDE

.BANK 0 SLOT 0
.ORG 0

entry:
    mov x, #$EF
    mov sp, x               ; stack in page 1 ($01EF down)

    ; timer 0: 8000 Hz / 133 = 60.15 Hz master tick — the region-free
    ; engine clock (grooves are the tempo: groove 6 = ~150 BPM)
    mov rT0TARGET, #133
    mov rCONTROL, #$31      ; clear port latches, start timer 0

    ; DSP to a safe state: soft reset off, mute on, echo writes disabled
    mov rDSPADDR, #$6C      ; FLG
    mov rDSPDATA, #$60
    mov rDSPADDR, #$5C      ; KOF: release all voices
    mov rDSPDATA, #$FF
    mov rDSPADDR, #$0C      ; MVOL L
    mov rDSPDATA, #$00
    mov rDSPADDR, #$1C      ; MVOL R
    mov rDSPDATA, #$00

    mov cur_edl, #$00
    mov cur_esa, #$FF       ; matches the CPU's boot parking value

    ; adopt whatever the CPU last wrote (the IPL kick byte) as "processed"
    mov a, rPORT0
    mov last_cmd, a
    mov tick, #$00

    ; ready signal for the uploader
    mov rPORT0, #$EE

main:
    ; --- telemetry: accumulate timer-0 ticks, publish on port 3; each tick
    ; also publish two voices' live ENVX on ports 1/2 (voice pair = tick&3,
    ; the CPU reconstructs the meters from its mirrored tick) ---
    mov a, rT0OUT           ; reads and clears the 4-bit tick count
    beq @no_tick
    clrc
    adc a, tick
    mov tick, a
    mov rPORT3, a
    and a, #$03             ; voice pair
    asl a
    asl a
    asl a
    asl a
    asl a                   ; pair * 32 = first voice's register base
    or a, #$08              ; VxENVX
    mov rDSPADDR, a
    mov a, rDSPDATA
    mov rPORT1, a
    mov a, tick
    and a, #$03
    asl a
    asl a
    asl a
    asl a
    asl a
    or a, #$28              ; second voice of the pair
    mov rDSPADDR, a
    mov a, rDSPDATA
    mov rPORT2, a
    ; NOTE: Mesen 2 returns 0 for live ENVX reads (verified: FLG reads
    ; back fine through the same path) — the meters are flat in the
    ; emulator and real on hardware, where ENVX reads are serviced.
@no_tick:

    ; --- mailbox ---
    mov a, rPORT0
    cmp a, last_cmd
    beq main
    mov last_cmd, a
    and a, #$7F

    cmp a, #CMD_DSP_WRITE
    bne @not_dsp
    ; single DSP register write; the only $F2/$F3 code path
    mov a, rPORT1
    mov rDSPADDR, a
    mov a, rPORT2
    mov rDSPDATA, a
    bra @ack
@not_dsp:
    cmp a, #CMD_UPLOAD
    beq @upload
    cmp a, #CMD_TICKRATE
    bne @not_tick
    mov a, rPORT1
    mov rT0TARGET, a        ; T command: retune the master tick
    bra @ack
@not_tick:
    cmp a, #CMD_ECHO_CFG
    bne @not_echo
    ; latch the payload NOW — the CPU will reuse ports 1/2 for its next
    ; command as soon as we ack
    mov a, rPORT1
    and a, #$0F
    mov new_edl, a
    mov a, rPORT2
    mov new_esa, a
    ; ack FIRST: the sequence below can take ~0.5 s (wait + buffer clear)
    ; and must not stall the CPU's echo-wait past its timeout
    mov a, last_cmd
    mov rPORT0, a
    call !echo_cfg
    jmp !main
@not_echo:
    ; unknown commands ack as NOP
@ack:
    mov a, last_cmd
    mov rPORT0, a           ; echo completes the handshake
    bra main

; --- bulk upload: 3 bytes per handshake round into ARAM -----------------------
@upload:
    mov a, rPORT1
    mov dest_lo, a
    mov a, rPORT2
    mov dest_hi, a
    mov a, last_cmd
    mov rPORT0, a           ; ack; CPU may now stream rounds
@bulk_wait:
    mov a, rPORT0
    cmp a, last_cmd
    beq @bulk_wait
    mov last_cmd, a
    cmp a, #$00
    beq @bulk_end           ; counter 0 = end of stream
    mov y, #$00
    mov a, rPORT1
    mov [dest_lo]+y, a
    inc y
    mov a, rPORT2
    mov [dest_lo]+y, a
    inc y
    mov a, rPORT3
    mov [dest_lo]+y, a
    clrc
    adc dest_lo, #$03
    adc dest_hi, #$00
    mov a, last_cmd
    mov rPORT0, a           ; echo the round counter
    bra @bulk_wait
@bulk_end:
    mov rPORT0, a           ; echo the 0; both sides now at seq 0
    jmp !main

; --- safe echo reconfiguration (port1 = EDL, port2 = ESA page) -----------------
echo_cfg:
    ; fast path: nothing changes, nothing to do (keeps boot + reloads quick)
    mov a, new_edl
    cmp a, cur_edl
    bne @do_cfg
    mov a, new_esa
    cmp a, cur_esa
    bne @do_cfg
    ret
@do_cfg:
    ; 1. mute + disable echo buffer writes
    mov rDSPADDR, #$6C
    mov rDSPDATA, #$60
    ; 2. wait out the OLD delay: (cur_edl + 1) T0 periods (~16.6 ms each)
    mov a, cur_edl
    inc a
    mov wait_cnt, a
    mov a, rT0OUT           ; clear the counter
@wait:
    mov a, rT0OUT
    beq @wait
    dbnz wait_cnt, @wait
    ; 3. move the buffer (latched payload)
    mov a, new_esa
    mov rDSPADDR, #$6D      ; ESA
    mov rDSPDATA, a
    mov a, new_edl
    mov rDSPADDR, #$7D      ; EDL
    mov rDSPDATA, a
    mov cur_edl, a
    mov a, new_esa
    mov cur_esa, a
    ; 4. zero the new buffer region: EDL*2048 bytes (min 4) from ESA<<8
    mov a, new_esa
    mov dest_hi, a
    mov dest_lo, #$00
    mov a, cur_edl
    asl a
    asl a
    asl a                   ; pages = EDL * 8
    bne @have_pages
    mov a, #$01             ; EDL 0 still owns 4 bytes; clear one page
@have_pages:
    mov wait_cnt, a
    mov y, #$00
    mov a, #$00
@clear:
    mov [dest_lo]+y, a
    inc y
    bne @clear
    inc dest_hi
    dbnz wait_cnt, @clear
    ; 5. the echo OFFSET counter free-runs even with ECEN off; if the new
    ; EDL is smaller, an in-flight offset never hits the new wrap point and
    ; the DSP would write past the buffer (wrapping into low ARAM!) once
    ; re-enabled. Wait a full max-delay (16 x ~16.6 ms) for the offset to
    ; wrap around before enabling writes.
    mov wait_cnt, #17
    mov a, rT0OUT           ; clear the counter
@offset_wait:
    mov a, rT0OUT
    beq @offset_wait
    dbnz wait_cnt, @offset_wait
    ; 6. re-enable: unmute, echo writes on
    mov rDSPADDR, #$6C
    mov rDSPDATA, #$00
    ret
