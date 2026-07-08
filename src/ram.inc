; ram.inc — WRAM layout (bank $7E low RAM, reachable via DB=$80 mirrors)
;
; The first 16 bytes are FROZEN: check scripts (tools/checks/*.lua) assert on
; them by absolute address. Never reorder; add new vars after the frozen
; block.
;
; text_x MUST stay immediately before text_y (text_dest reads them as one
; 16-bit word).

.DEFINE MAGIC_BOOT_OK $5D    ; written to magic_boot when init completes

.ENUM $0000
frame_flag   db      ; $00  set by NMI, cleared by main loop
magic_boot   db      ; $01  = MAGIC_BOOT_OK once init is complete
frame_cnt    dw      ; $02  free-running frame counter (NMI)
pad_raw      dw      ; $04  raw JOY1 sampled in NMI
pad_held     dw      ; $06  held buttons (main-loop copy, ID bits masked)
pad_pressed  dw      ; $08  newly pressed this frame
pad_event    dw      ; $0A  pressed | DAS repeats (edit actions consume this)
ui_mode      db      ; $0C  0=splash 1=song-stub
apu_status   db      ; $0D  0=ok, 1=timeout ("APU?")  (M2)
cur_x        db      ; $0E  editor cursor column
cur_y        db      ; $0F  editor cursor row
; --- check-visible APU block: also frozen for tools/checks/ ---
apu_seq      db      ; $10  last mailbox port-0 byte sent (flip handshake)
apu_tick     db      ; $11  APU master tick (port-3 telemetry mirror)
hb_val       db      ; $12  heartbeat value (lands in DSP unused reg $1D)
last_pitch   dw      ; $13  last DSP pitch value sent (audition/engine)
kon_count    db      ; $15  count of KON commands issued
; --- end frozen block ---
up_src       dw      ; bulk upload: source (DB-relative)
up_dest      dw      ;              dest ARAM address
up_len       dw      ;              byte count (multiple of 3)
pad_prev     dw
pad_das_dir  dw      ; d-pad bits DAS is tracking
das_cnt      db
text_x       db
text_y       db      ; must follow text_x
text_attr    dw
tmp0         dw
tmp1         dw
tmp2         dw
str_buf      ds 40   ; scratch line buffer for formatted text
.ENDE

; Shadow of the BG3 tilemap (32x32 words). NMI DMAs this to VRAM every frame;
; the editor writes only here — it never touches PPU ports (invariant #6).
.DEFINE SHADOW_BG3 $0400     ; ..$0BFF (2 KB)

; Stack: S initialised to $1FFF, grows down.
