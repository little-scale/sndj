; init.asm — reset, hardware init, VRAM/CGRAM upload, main loop entry

.ACCU 8
.INDEX 16

Vec_Null:
    rti

Reset:
    sei
    clc
    xce                     ; native mode
    rep #$30
.ACCU 16
    ldx #$1FFF
    txs                     ; stack
    lda #$0000
    tcd                     ; direct page = $0000
    sep #$20
.ACCU 8
    lda #$80
    pha
    plb                     ; data bank = $80 (fast mirror: WRAM low + MMIO + ROM)
    lda #$01
    sta MEMSEL              ; FastROM
    jml @fast               ; leave the $00 slow mirror
@fast:
    lda #$8F
    sta INIDISP             ; force blank, full brightness latched
    stz NMITIMEN            ; interrupts off during init
    stz HDMAEN
    stz MDMAEN

    ; --- clear all 128 KB of WRAM, inline: this wipes the stack, so it must
    ; run before any jsr (two 64 KB fixed-source DMAs to WMDATA) ---
    stz WMADDL
    stz WMADDM
    stz WMADDH
    ldx #zero_byte
    lda #$08                ; fixed source, 1 byte -> 1 reg
    sta DMAP0
    lda #$80                ; -> $2180 WMDATA
    sta BBAD0
    stx A1T0L
    lda #:zero_byte
    sta A1B0
    ldx #$0000              ; 64 KB
    stx DAS0L
    lda #$01
    sta MDMAEN
    ldx #$0000
    stx DAS0L
    lda #$01
    sta MDMAEN              ; second 64 KB (WMADD carried into bank $7F)

    jsr init_regs
    jsr init_video
    jsr apu_upload_driver   ; on timeout: apu_status=1, UI shows "APU?"
    bcs +
    jsr apu_audio_init      ; factory sample + directory + voice 0 config
+
    jsr song_init           ; fresh song block (NEW)
    jsr sram_check          ; format SNDJ1 SRAM on first boot
    lda apu_status
    bne +
    jsr wave_sync_all       ; compile + upload the 8 wave banks
    jsr residency_build     ; upload the samples this song references
    jsr apu_echo_apply      ; song echo defaults -> DSP (safe reconfig)
+

    ; per-voice instrument shadows start unknown so the first apply loads
    ldx #$0000
    lda #$FF
-
    sta.w trk_instr_active,x
    inx
    cpx #TRACKS
    bne -

    ; editor defaults: first B tap inserts C-4 / instrument 0 / command A
    lda #49
    sta ed_lastnote
    stz ed_lastinstr
    lda #$01
    sta ed_lastcmd
    stz ed_lastval
    stz ed_instr

    ; init complete: mark it, enable NMI + auto-joypad, screen on
    lda #MAGIC_BOOT_OK
    sta magic_boot
    lda #$81
    sta NMITIMEN
    lda #$0F
    sta INIDISP

    jsr splash_init
    jmp main_loop

; --- clear/park every PPU register we rely on -------------------------------
init_regs:
    stz OBSEL
    stz OAMADDL
    stz OAMADDH
    stz BGMODE
    stz MOSAIC
    stz BG1SC
    stz BG2SC
    stz BG3SC
    stz BG4SC
    stz BG12NBA
    stz BG34NBA
    ; scroll: H = 0, V = -1 (so map row 0 lands on scanline 0)
    stz BG1HOFS
    stz BG1HOFS
    stz BG2HOFS
    stz BG2HOFS
    stz BG3HOFS
    stz BG3HOFS
    stz BG4HOFS
    stz BG4HOFS
    lda #$FF
    sta BG1VOFS
    lda #$03
    sta BG1VOFS
    lda #$FF
    sta BG2VOFS
    lda #$03
    sta BG2VOFS
    lda #$FF
    sta BG3VOFS
    lda #$03
    sta BG3VOFS
    lda #$FF
    sta BG4VOFS
    lda #$03
    sta BG4VOFS
    lda #$80
    sta VMAIN               ; word increment on $2119 write
    stz M7SEL
    stz W12SEL
    stz W34SEL
    stz WOBJSEL
    stz TM
    stz TS
    stz TMW
    stz TSW
    stz CGWSEL
    stz CGADSUB
    lda #$E0
    sta COLDATA
    stz SETINI
    lda #$FF
    sta WRIO                ; IOBit high (sync line idle)
    rts

; --- VRAM / CGRAM / OAM init + asset upload ---------------------------------
init_video:
    ; clear all VRAM: fixed word source -> $2118/19, 64 KB
    ldx #$0000
    stx VMADDL
    lda #$09                ; fixed source, 2 bytes -> 2 regs
    sta DMAP0
    lda #$18
    sta BBAD0
    ldx #zero_word
    stx A1T0L
    lda #:zero_word
    sta A1B0
    ldx #$0000
    stx DAS0L
    lda #$01
    sta MDMAEN

    ; OAM: fill with $F0 (all sprites parked offscreen)
    stz OAMADDL
    stz OAMADDH
    lda #$08
    sta DMAP0
    lda #$04                ; -> $2104 OAMDATA
    sta BBAD0
    ldx #oam_fill
    stx A1T0L
    lda #:oam_fill
    sta A1B0
    ldx #544
    stx DAS0L
    lda #$01
    sta MDMAEN

    ; palette
    stz CGADD
    lda #$00                ; linear source, 1 byte -> 1 reg
    sta DMAP0
    lda #$22                ; -> $2122 CGDATA
    sta BBAD0
    ldx #pal_data
    stx A1T0L
    lda #:pal_data
    sta A1B0
    ldx #512
    stx DAS0L
    lda #$01
    sta MDMAEN

    ; font -> BG3 chr
    ldx #VRAM_BG3_CHR
    stx VMADDL
    lda #$01                ; linear source, 2 bytes -> 2 regs
    sta DMAP0
    lda #$18
    sta BBAD0
    ldx #font_data
    stx A1T0L
    lda #:font_data
    sta A1B0
    ldx #(font_data_end - font_data)
    stx DAS0L
    lda #$01
    sta MDMAEN

    ; video mode: mode 1, BG3 priority, BG3 = text UI
    lda #$09
    sta BGMODE
    lda #(VRAM_BG3_MAP >> 8)  ; map base ($400-word steps), 32x32
    sta BG3SC
    lda #(VRAM_BG3_CHR >> 12)
    sta BG34NBA
    lda #$04                ; BG3 only for now
    sta TM

    ; HDMA channel 7: backdrop gradient (mode 3 -> $2121)
    lda #$03
    sta DMAP7
    lda #$21
    sta BBAD7
    ldx #gradient_data
    stx A1T7L
    lda #:gradient_data
    sta A1B7
    lda #$80
    sta HDMAEN
    rts

zero_byte: .DB $00
zero_word: .DW $0000
oam_fill:  .DB $F0
