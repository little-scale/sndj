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
up_src       ds 3    ; bulk upload: 24-bit source pointer
up_dest      dw      ;              dest ARAM address
up_len       dw      ;              byte count (multiple of 3)
; save/load state (sv_src/sv_dst used with [dp] — must stay below $100)
sv_src       ds 3    ; 24-bit read pointer
sv_dst       ds 3    ; 24-bit write pointer
sv_crc       dw      ; CRC-16/CCITT accumulator
sv_size      dw      ; packed byte count
sv_i         dw      ; pack: current image index
sv_lit       dw      ; pack: pending literal start
sv_run       db      ; pack: current run length
sv_b         db      ; pack: current run byte
sv_chunk     dw      ; pack: literal chunk counter
sv_ovf       db      ; pack: region overflow flag
sv_slot      db
sv_region    db
fl_slot      db      ; FILES cursor slot
fl_col       db      ; FILES cursor column (0=load 1=save)
fl_msg       db      ; FILES status message id
; hot scalars (keep below $100 for direct-page speed)
apu_tmo      db      ; apu_wait_p0 outer timeout counter
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
ed_wave      db      ; wave bank under edit (WAVE screen)
wv_x         db      ; WAVE screen cursor column (0-31)
wv_stamp     db      ; WAVE preset-stamp cycle position
trig_type    db      ; instrument type at trigger time
pool_count   db      ; samples in the ROM pool (set at boot)
pool_map     ds 64   ; pool index -> resident SRCN (0 = silent stub)
res_cursor   dw      ; residency: next free ARAM byte
res_slot     db      ; residency: next directory slot
res_scan     db      ; residency: scan counter
res_cur      db      ; residency: pool index being marked
res_ceil     db      ; residency: ARAM ceiling page (echo buffer floor)
ed_kit       db      ; kit under edit (KIT screen)
kt_row       db      ; KIT screen cursor slot
kt_col       db      ; KIT screen cursor column (0=sample 1=tune 2=vol)
hop_guard    db      ; H-command chain-hop limiter per row tick
eng_eon      db      ; live per-voice echo-send mask (EON shadow)
blk_mode     db      ; block select active on the current grid screen
blk_start    db      ; block anchor row
clip_kind    db      ; clipboard: 0 none, 1 phrase rows, 2 chain rows, 3 song cells
clip_len     db      ; clipboard row count
tap_timer    db      ; frames left to accept a B double-tap (paste)
ed_track     db      ; track context (set when descending from SONG)
trk_pending  ds 8    ; LIVE: chain queued to launch at the phrase boundary
trk_mute     db      ; bit per track: muted
envx_mirror  ds 8    ; per-voice ENVX from driver telemetry
live_prev    db      ; screen to return to when Select leaves LIVE
eng_noise    db      ; global noise clock (FLG bits 0-4)
eng_non      db      ; NON mask shadow
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
trig_semis   db      ; pitch-calc tune context: whole semitones (signed)
trig_fine    db      ; and 1/256-semitone fraction (signed)
np_note      db      ; note_pitch_calc_only scratch
np_fine      db
np_base      dw
np_delta     dw
np_frac      dw
fl_menu      db      ; FILES action menu open
fl_mitem     db      ; menu cursor (0 save, 1 load, 2 clear)
fl_ncur      db      ; name-edit character cursor 0-7
tick_ctr     dw      ; free-running 16-bit APU tick counter (top-right)
tick_last8   db      ; last apu_tick byte folded into tick_ctr
opt_pal      db      ; active palette scheme 0-7 (persists in SRAM $0007)
pal_dirty    db      ; pal_buf awaits its VBlank CGRAM write
pal_buf      ds 32   ; CGRAM colours 0-15, drained by the NMI
opt_cur      db      ; OPTIONS field cursor
res_dir      ds 224  ; ARAM directory staging (56 slots x 4; NEVER str_buf —
                     ; 40 resident samples overflowed it and smashed vars)
walk_guard   db      ; empty-entry recursion budget (block loops must halt)
ed_groove    db      ; GROOVE screen: edited groove id
gv_row       db      ; GROOVE screen: step cursor
ed_lastgroove db     ; GROOVE insert buffer
pj_cur       db      ; PROJECT field cursor
pj_arm       db      ; PROJECT NEW confirm armed
pal_tmp      dw      ; palette_apply dim-blend scratch
fl_freed     db      ; FILES: PURGE result count for the status line
pg_i         dw      ; purge scan indices
pg_j         dw
fl_usedv     db      ; FILES: packed slot count (first empty row)
fs_row       db      ; FIR screen tap cursor
trk_fine     ds 8    ; per-track F-command fine tune (signed 1/256 semi)
eng_pmon     db      ; PMON shadow (Z command)
trk_chord    ds 8    ; C-command chord override (x/y nibble offsets, 0 = off)
trk_playcnt  ds 8    ; phrase pass counter (I/J play-count schedules)
trk_tbl      ds 8    ; running table id ($FF = none; set at trigger)
trk_tbl_row  ds 8    ; table step 0-15
trk_tbl_spd  ds 8    ; TBS: ticks per table row (0 = advance per note)
trk_tbl_cnt  ds 8    ; tick countdown / note-sync pending flag
ed_table     db      ; TABLE screen: edited table id
tb_x         db      ; TABLE screen cursor col (0-3)
tb_y         db      ; TABLE screen cursor row
opt_clone    db      ; OPTIONS CLONE: 0 = SLIM, 1 = DEEP (SRAM $0008)
mint_prev    db      ; reference cell value before the arming tap
mint_empty   db      ; that cell was empty pre-tap
cl_i         dw      ; clone/mint scratch
cl_j         dw
cl_n         dw
cl_src       db
cl_dst       db
cl_csrc      db
cl_cdst      db
cl_e         db
cl_s         db
cl_p         db
video_pal    db      ; STAT78 bit 4 at boot: 1 = PAL console
sv_limit     dw      ; pack budget: free heap bytes for this save
sv_hole      dw      ; compaction: hole offset in the heap
sv_hsize     dw      ; compaction: hole size
sv_mlen      dw      ; compaction: bytes left to move
aud_note     db      ; chord audition: root note index (0-based)
aud_instr    db      ; chord audition: resolved instrument ($FF = none)
aud_chord    db      ; chord audition: C-command x/y nibbles
trk_vib      ds 8    ; live vibrato speed/depth (instr VIB at trigger; V overrides)
trk_trm      ds 8    ; live tremolo speed/depth (instr TRM at trigger)
trk_trm_ph   ds 8    ; tremolo phase
tg_vibtrm    dw      ; trigger scratch: instr VIB/TRM bytes (es3 is the tick loop's)
trk_voll     ds 8    ; live volume L (signed): record at load, X/P/U retarget,
trk_volr     ds 8    ; TRM dips from it              live volume R
ap_vol       dw      ; apply_instrument scratch: record VOL L/R pair
.ENDE

; Shadow of the BG3 tilemap (32x32 words). NMI DMAs this to VRAM every frame;
; the editor writes only here — it never touches PPU ports (invariant #6).
.DEFINE SHADOW_BG3 $0400     ; ..$0BFF (2 KB)

; Stack: S initialised to $1FFF, grows down.
