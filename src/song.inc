; song.inc — the contiguous WRAM song block (CLAUDE.md §3.5).
;
; Lives in bank $7E above the $0000-$1FFF mirror, so ALL access uses long
; addressing (lda.l/sta.l $7E0000,x with X = block-relative offset + SB).
; Layout freezes in M8 when SAVEFORMAT.md is written; keep additions at the
; end. Save/load is a straight copy of [SB, SB_END).
;
; Pool sizes (v1, SMDJ4-derived, SRAM 4-slot target — CLAUDE.md §15):
;   128 phrases, 64 chains, 8x128 song grid, 32 instruments, 32 tables,
;   8 grooves, 8 wave banks.

.DEFINE SB            $2000            ; song block base (bank $7E)

.DEFINE PHRASE_COUNT  128
.DEFINE PHRASE_ROWS   16
.DEFINE PHRASE_ROW_SZ 4                ; note, instr, cmd, val
.DEFINE PHRASE_SZ     64               ; 16 rows * 4

.DEFINE CHAIN_COUNT   64
.DEFINE CHAIN_ROWS    16
.DEFINE CHAIN_SZ      32               ; 16 * (phrase id, transpose)

.DEFINE SONG_ROWS     128
.DEFINE TRACKS        8

.DEFINE INSTR_COUNT   32
.DEFINE INSTR_SZ      16

.DEFINE TABLE_COUNT   32
.DEFINE TABLE_SZ      64               ; 16 rows * (cmd,val)*2 columns

.DEFINE GROOVE_COUNT  8
.DEFINE GROOVE_SZ     16

.DEFINE SB_PHRASES    (SB + $0000)     ; $2000 bytes
.DEFINE SB_CHAINS     (SB + $2000)     ; $0800
.DEFINE SB_SONG       (SB + $2800)     ; $0400 (8 tracks * 128 rows)
.DEFINE SB_INSTR      (SB + $2C00)     ; $0200
.DEFINE SB_TABLES     (SB + $2E00)     ; $0800
.DEFINE SB_GROOVES    (SB + $3600)     ; $0080
.DEFINE SB_WAVES      (SB + $3680)     ; $0100 (8 banks * 32 samples)
.DEFINE SB_HEADER     (SB + $3780)     ; $0080 (song-level settings)
.DEFINE SB_END        (SB + $3800)

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

; phrase row cell values
.DEFINE NOTE_EMPTY    0                ; note byte: 0=empty, 1-96=C-0..B-7
.DEFINE NOTE_OFF      97               ; key off ("OFF")
.DEFINE NOTE_MAX      96
.DEFINE INSTR_NONE    $FF
.DEFINE CMD_NONE      0

; ROM pool reservation (patcher.html may grow the pool up to this)
.DEFINE POOL_RESERVED $4000
