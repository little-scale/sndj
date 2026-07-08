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
eng_playing  db      ; $16  sequencer running
eng_row      db      ; $17  track-0 phrase row mirror (playhead/checks)
ed_phrase    db      ; $18  phrase id under edit (PHRASE screen)
ed_col       db      ; $19  phrase cursor column (0=note 1=instr 2=cmd 3=val)
; --- second pinned block ($1A-$3F): editor + track state for checks ---
ed_chain     db      ; $1A  chain id under edit (CHAIN screen)
song_cx      db      ; $1B  SONG cursor track (0-7)
song_cy      db      ; $1C  SONG cursor row (0-127)
song_top     db      ; $1D  SONG scroll window top row
chain_cy     db      ; $1E  CHAIN cursor row (0-15)
chain_cx     db      ; $1F  CHAIN cursor column (0=phrase 1=transpose)
trk_chain    ds 8    ; $20  per-track: chain id ($FF = halted)
trk_phrase   ds 8    ; $28  per-track: phrase id ($FF = halted)
trk_prow     ds 8    ; $30  per-track: phrase row
trk_songrow  ds 8    ; $38  per-track: song grid row
; --- end pinned blocks ---
; DP-required (used with (dp),y indirect addressing — must stay below $100)
up_src       dw      ; bulk upload: source (DB-relative)
up_dest      dw      ;              dest ARAM address
up_len       dw      ;              byte count (multiple of 3)
; hot scalars (keep below $100 for direct-page speed)
das_last_fc  db      ; frame_cnt low byte at last DAS update
text_x       db
text_y       db      ; must follow text_x
text_attr    dw
tmp0         dw
tmp1         dw
tmp2         dw
trk_cpos     ds 8    ; per-track: position within chain
trk_tsp      ds 8    ; per-track: active transpose (chain entry)
trk_instr    ds 8    ; per-track: current instrument id ($FF = none yet)
trk_instr_active ds 8 ; per-voice: instrument whose regs are loaded ($FF = force)
trig_id      db      ; instrument id being applied
trig_note    db      ; final note index of the main trigger (GRP base)
grp_track    db      ; GRP fanout state
grp_span     db
grp_m        db
ed_instr     db      ; instrument id under edit (INSTR screen)
if_cur       db      ; INSTR screen field cursor
; --- per-track command/effect state (M7) — grows past the direct page; all
; access is indexed absolute, which WLA emits automatically ---
eng_groove   db      ; active groove id
trk_cmd      ds 8    ; current row command id (0 = none)
trk_cval     ds 8    ; current row command value
trk_note     ds 8    ; current note index (arp/vib base)
trk_pitch_lo ds 8    ; current pitch (slides move it)
trk_pitch_hi ds 8
trk_dly_cnt  ds 8    ; D: ticks until deferred trigger ($FF = none)
trk_dly_note ds 8
trk_kill_cnt ds 8    ; K: ticks until KOF ($FF = none)
trk_ret_per  ds 8    ; R: retrigger period (0 = off)
trk_ret_cnt  ds 8
trk_arp_ph   ds 8
trk_vib_ph   ds 8
trk_sl_rate  ds 8    ; L: slide rate (0 = off)
trk_sl_tlo   ds 8    ; L: target pitch
trk_sl_thi   ds 8
trk_sl_note  ds 8    ; L: target note index (arp base once reached)
es0          dw      ; engine scratch (safe across apu_send/text_*)
es1          dw
es2          dw
es3          dw
kon_mask     db      ; voices to key on at end of row tick
koff_mask    db      ; voices to key off at end of row tick
trig_voice   db      ; note_on target voice
eng_tickwait db      ; ticks left in current row
eng_gpos     db      ; groove position
eng_tick_last db     ; last consumed apu_tick
ed_lastnote  db
ed_lastinstr db
ed_lastcmd   db
ed_lastval   db
ed_lastchain db      ; SONG insert default
ed_lastphrid db      ; CHAIN insert default (phrase id)
ed_lasttsp   db      ; CHAIN insert default (transpose)
ui_cnt       db      ; screen-draw loop counter (text_* clobber tmp0/tmp1)
b_down       db      ; B modifier edge state
b_used       db      ; B was used as a modifier (suppress tap on release)
a_down       db      ; A (screen) modifier edge state
a_used       db
pad_prev     dw
pad_das_dir  dw      ; d-pad bits DAS is tracking
das_cnt      db
str_buf      ds 40   ; scratch line buffer for formatted text
.ENDE

; Shadow of the BG3 tilemap (32x32 words). NMI DMAs this to VRAM every frame;
; the editor writes only here — it never touches PPU ports (invariant #6).
.DEFINE SHADOW_BG3 $0400     ; ..$0BFF (2 KB)

; Stack: S initialised to $1FFF, grows down.
