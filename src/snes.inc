; snes.inc — S-CPU hardware registers + project-wide constants
; Register naming follows fullsnes.

; --- PPU ---------------------------------------------------------------
.DEFINE INIDISP  $2100   ; force blank / brightness
.DEFINE OBSEL    $2101
.DEFINE OAMADDL  $2102
.DEFINE OAMADDH  $2103
.DEFINE OAMDATA  $2104
.DEFINE BGMODE   $2105
.DEFINE MOSAIC   $2106
.DEFINE BG1SC    $2107
.DEFINE BG2SC    $2108
.DEFINE BG3SC    $2109
.DEFINE BG4SC    $210A
.DEFINE BG12NBA  $210B
.DEFINE BG34NBA  $210C
.DEFINE BG1HOFS  $210D
.DEFINE BG1VOFS  $210E
.DEFINE BG2HOFS  $210F
.DEFINE BG2VOFS  $2110
.DEFINE BG3HOFS  $2111
.DEFINE BG3VOFS  $2112
.DEFINE BG4HOFS  $2113
.DEFINE BG4VOFS  $2114
.DEFINE VMAIN    $2115
.DEFINE VMADDL   $2116
.DEFINE VMADDH   $2117
.DEFINE VMDATAL  $2118
.DEFINE VMDATAH  $2119
.DEFINE M7SEL    $211A
.DEFINE CGADD    $2121
.DEFINE CGDATA   $2122
.DEFINE W12SEL   $2123
.DEFINE W34SEL   $2124
.DEFINE WOBJSEL  $2125
.DEFINE TM       $212C
.DEFINE TS       $212D
.DEFINE TMW      $212E
.DEFINE TSW      $212F
.DEFINE CGWSEL   $2130
.DEFINE CGADSUB  $2131
.DEFINE COLDATA  $2132
.DEFINE SETINI   $2133

; --- APU mailbox --------------------------------------------------------
.DEFINE APUIO0   $2140
.DEFINE APUIO1   $2141
.DEFINE APUIO2   $2142
.DEFINE APUIO3   $2143

; --- WRAM data port ------------------------------------------------------
.DEFINE WMDATA   $2180
.DEFINE WMADDL   $2181
.DEFINE WMADDM   $2182
.DEFINE WMADDH   $2183

; --- CPU / system --------------------------------------------------------
.DEFINE JOYSER0  $4016
.DEFINE JOYSER1  $4017
.DEFINE NMITIMEN $4200
.DEFINE WRIO     $4201
.DEFINE WRMPYA   $4202
.DEFINE WRMPYB   $4203
.DEFINE WRDIVL   $4204
.DEFINE WRDIVH   $4205
.DEFINE WRDIVB   $4206
.DEFINE HTIMEL   $4207
.DEFINE HTIMEH   $4208
.DEFINE VTIMEL   $4209
.DEFINE VTIMEH   $420A
.DEFINE MDMAEN   $420B
.DEFINE HDMAEN   $420C
.DEFINE MEMSEL   $420D
.DEFINE RDNMI    $4210
.DEFINE TIMEUP   $4211
.DEFINE HVBJOY   $4212
.DEFINE RDIO     $4213
.DEFINE RDDIVL   $4214
.DEFINE RDDIVH   $4215
.DEFINE RDMPYL   $4216
.DEFINE RDMPYH   $4217
.DEFINE JOY1L    $4218
.DEFINE JOY1H    $4219
.DEFINE JOY2L    $421A
.DEFINE JOY2H    $421B

; --- DMA channel 0 (general) / 7 (HDMA gradient) --------------------------
.DEFINE DMAP0    $4300
.DEFINE BBAD0    $4301
.DEFINE A1T0L    $4302
.DEFINE A1T0H    $4303
.DEFINE A1B0     $4304
.DEFINE DAS0L    $4305
.DEFINE DAS0H    $4306
.DEFINE DMAP7    $4370
.DEFINE BBAD7    $4371
.DEFINE A1T7L    $4372
.DEFINE A1T7H    $4373
.DEFINE A1B7     $4374

; --- Joypad bits (as read from JOY1L/H, 16-bit: H:L = BYSTUDLR AXLR0000) ---
; 16-bit layout after `lda JOY1L` (rep #$20):
;   bit15 B, 14 Y, 13 Select, 12 Start, 11 Up, 10 Down, 9 Left, 8 Right
;   bit7  A, 6 X, 5 L, 4 R
.DEFINE PAD_B      $8000
.DEFINE PAD_Y      $4000
.DEFINE PAD_SELECT $2000
.DEFINE PAD_START  $1000
.DEFINE PAD_UP     $0800
.DEFINE PAD_DOWN   $0400
.DEFINE PAD_LEFT   $0200
.DEFINE PAD_RIGHT  $0100
.DEFINE PAD_A      $0080
.DEFINE PAD_X      $0040
.DEFINE PAD_L      $0020
.DEFINE PAD_R      $0010
.DEFINE PAD_DPAD   $0F00

; --- VRAM layout (word addresses) -----------------------------------------
.DEFINE VRAM_BG3_MAP  $0000   ; 32x32 tilemap, 2KB
.DEFINE VRAM_BG1_MAP  $0400
.DEFINE VRAM_BG3_CHR  $1000   ; 2bpp font
.DEFINE VRAM_BG1_CHR  $2000   ; 4bpp dynamic layer

; --- Text attributes (tilemap word high bits) ------------------------------
; vhopppcc: priority set, palette 0-3
.DEFINE ATTR_TEXT   $2000     ; palette 0, priority
.DEFINE ATTR_ACCENT $2400     ; palette 1, priority
.DEFINE ATTR_HILITE $2800     ; palette 2, priority
.DEFINE ATTR_DIM    $2C00     ; palette 3, priority
.DEFINE ATTR_PLAY   $3000     ; palette 4, priority — the playhead cell:
                              ; negative glyphs in the DIM shade (a soft
                              ; grey block, distinct from the cursor's
                              ; full inversion and from plain text)

; Extra font glyphs (tile indices; ASCII glyphs are tile = char-32)
.DEFINE GLYPH_BLOCK    64
.DEFINE GLYPH_BLOCK34  65
.DEFINE GLYPH_BLOCK12  66
.DEFINE GLYPH_BLOCK14  67
.DEFINE GLYPH_ARROW_R  68
.DEFINE GLYPH_ARROW_L  69
.DEFINE GLYPH_ARROW_U  70
.DEFINE GLYPH_ARROW_D  71
.DEFINE GLYPH_NOTE     72
