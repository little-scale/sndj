; ============================================================================
; snesdj SPC700 driver — pure chip servant (CLAUDE.md §3.1)
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

; --- zero-page state ----------------------------------------------------------
.ENUM $0010
last_cmd  db      ; last port-0 byte processed
tick      db      ; master tick counter (T0-derived)
dest_lo   db      ; bulk upload write pointer
dest_hi   db
.ENDE

.BANK 0 SLOT 0
.ORG 0

entry:
    mov x, #$EF
    mov sp, x               ; stack in page 1 ($01EF down)

    ; timer 0: 8000 Hz / 125 = 64 Hz master tick (placeholder rate; the
    ; groove engine will set this in M4)
    mov rT0TARGET, #125
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

    ; adopt whatever the CPU last wrote (the IPL kick byte) as "processed"
    mov a, rPORT0
    mov last_cmd, a
    mov tick, #$00

    ; ready signal for the uploader
    mov rPORT0, #$EE

main:
    ; --- telemetry: accumulate timer-0 ticks, publish on port 3 ---
    mov a, rT0OUT           ; reads and clears the 4-bit tick count
    beq @no_tick
    clrc
    adc a, tick
    mov tick, a
    mov rPORT3, a
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
    bra main
