; song.inc — the contiguous WRAM song block (CLAUDE.md §3.5, SAVEFORMAT.md).
;
; Lives in bank $7E above the $0000-$1FFF mirror, so ALL access uses long
; addressing (lda.l/sta.l $7E0000,x with X = block-relative offset + SB).
; Layout v2: fixed-size sections first, growable pools last, so future
; phrase-count growth doesn't move anything else. Save/load is a straight
; copy of [SB, SB_END).
;
; Pool sizes (v2 "option B"): 192 phrases, 96 chains, 64 instruments,
; 16 kits x 16 slots, 16 grooves — sized against the 4-slot SRAM target.

.DEFINE SB            $2000            ; song block base (bank $7E)

.DEFINE PHRASE_COUNT  192
.DEFINE PHRASE_ROWS   16
.DEFINE PHRASE_ROW_SZ 4                ; note, instr, cmd, val
.DEFINE PHRASE_SZ     64               ; 16 rows * 4

.DEFINE CHAIN_COUNT   96
.DEFINE CHAIN_ROWS    16
.DEFINE CHAIN_SZ      32               ; 16 * (phrase id, transpose)

.DEFINE SONG_ROWS     128
.DEFINE TRACKS        8

.DEFINE INSTR_COUNT   64
.DEFINE INSTR_SZ      16

.DEFINE TABLE_COUNT   32
.DEFINE TABLE_SZ      64               ; 16 rows * (V, TSP, CMD, VAL)

.DEFINE GROOVE_COUNT  16
.DEFINE GROOVE_SZ     16

.DEFINE KIT_COUNT     16
.DEFINE KIT_SLOTS     16
.DEFINE KIT_SLOT_SZ   4                ; sample, tune(signed), vol, flags
.DEFINE KIT_SZ        64               ; 16 slots * 4

.DEFINE SB_SONG       (SB + $0000)     ; $0400 (8 tracks * 128 rows)
.DEFINE SB_INSTR      (SB + $0400)     ; $0400 (64 * 16)
.DEFINE SB_TABLES     (SB + $0800)     ; $0800 (reserved until tables land)
.DEFINE SB_GROOVES    (SB + $1000)     ; $0100 (16 * 16)
.DEFINE SB_WAVES      (SB + $1100)     ; $0100 (8 banks * 32 samples)
.DEFINE SB_KITS       (SB + $1200)     ; $0400 (16 kits * 64)
.DEFINE SB_HEADER     (SB + $1600)     ; $0100 (song-level settings)
.DEFINE SB_CHAINS     (SB + $1700)     ; $0C00 (96 * 32)
.DEFINE SB_PHRASES    (SB + $2300)     ; $3000 (192 * 64)
.DEFINE SB_END        (SB + $5300)

; song header fields (offsets into SB_HEADER)
.DEFINE SH_GROOVE     0                ; default groove id
.DEFINE SH_TRANSPOSE  1
.DEFINE SH_MAGIC      2                ; $DJ ($D7) once initialised
.DEFINE SH_EDL        3                ; echo delay 0-15 (x16 ms, x2 KB ARAM)
.DEFINE SH_EFB        4                ; echo feedback (signed)
.DEFINE SH_EVL        5                ; echo volume L
.DEFINE SH_EVR        6                ; echo volume R
.DEFINE SH_EON        7                ; per-voice echo send mask
.DEFINE SH_FIR        8                ; FIR preset 0-7
.DEFINE SH_NAME       9                ; 8-char song name (ASCII, space pad)
.DEFINE SH_MODE       17               ; 0 = SONG, 1 = LIVE (S shows launcher)
.DEFINE SH_BPM        18               ; engine tick BPM (80-255; 0 -> 150)
.DEFINE SH_FIRTAPS    19               ; 8 signed FIR taps (the song's room)

; phrase row cell values
.DEFINE NOTE_EMPTY    0                ; note byte: 0=empty, 1-96=C-0..B-7
.DEFINE NOTE_OFF      97               ; key off ("OFF")
.DEFINE NOTE_MAX      96
.DEFINE INSTR_NONE    $FF
.DEFINE CMD_NONE      0

; ROM pool reservation (patcher.html may grow the pool up to this; the
; pool spans ROM banks 1-5 — entry offsets/sizes are in 9-byte BRR blocks).
; POOL_ROM is a NUMERIC constant (fixed by main.asm's bank-1 layout)
; because WLA drops the bank byte on cross-bank label expressions in
; long-indexed operands.
.DEFINE POOL_RESERVED $27FFA           ; banks 1-5 minus the SNPOOL marker
.DEFINE POOL_BANKS    5
.DEFINE POOL_ROM      $818006
