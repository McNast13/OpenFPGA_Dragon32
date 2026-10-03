#!/usr/bin/env python3
"""Generates src/fpga/core/dragon/osd/osd_keyboard_tables.sv - the on-screen
keyboard's font, key table and position map, as plain combinational logic
(no block RAM is free: M10K is 308/308).

    python3 tools/gen_osd_tables.py

Layout units are "half-units" (hu) of 8 pixels; the panel is 32 hu = 256 px
wide. Each key has a start hu, a width in hu, a label (up to 5 chars), an
optional shifted label (1 char, shown while Shift is latched), and its
Dragon matrix position (row, col - see dragon_keyboard.sv's table).
"""
import os

# ---------------------------------------------------------------------------
# Character set (6-bit codes) and 5x7 font, drawn in an 8x8 cell (cols 1-5,
# rows 0-6). '#' = lit.
# ---------------------------------------------------------------------------
FONT = {
    ' ': ["     "] * 7,
    '0': [" ### ", "#   #", "#  ##", "# # #", "##  #", "#   #", " ### "],
    '1': ["  #  ", " ##  ", "  #  ", "  #  ", "  #  ", "  #  ", " ### "],
    '2': [" ### ", "#   #", "    #", "  ## ", " #   ", "#    ", "#####"],
    '3': [" ### ", "#   #", "    #", "  ## ", "    #", "#   #", " ### "],
    '4': ["   # ", "  ## ", " # # ", "#  # ", "#####", "   # ", "   # "],
    '5': ["#####", "#    ", "#### ", "    #", "    #", "#   #", " ### "],
    '6': ["  ## ", " #   ", "#    ", "#### ", "#   #", "#   #", " ### "],
    '7': ["#####", "    #", "   # ", "  #  ", " #   ", " #   ", " #   "],
    '8': [" ### ", "#   #", "#   #", " ### ", "#   #", "#   #", " ### "],
    '9': [" ### ", "#   #", "#   #", " ####", "    #", "   # ", " ##  "],
    'A': [" ### ", "#   #", "#   #", "#####", "#   #", "#   #", "#   #"],
    'B': ["#### ", "#   #", "#   #", "#### ", "#   #", "#   #", "#### "],
    'C': [" ### ", "#   #", "#    ", "#    ", "#    ", "#   #", " ### "],
    'D': ["#### ", "#   #", "#   #", "#   #", "#   #", "#   #", "#### "],
    'E': ["#####", "#    ", "#    ", "#### ", "#    ", "#    ", "#####"],
    'F': ["#####", "#    ", "#    ", "#### ", "#    ", "#    ", "#    "],
    'G': [" ### ", "#   #", "#    ", "# ###", "#   #", "#   #", " ####"],
    'H': ["#   #", "#   #", "#   #", "#####", "#   #", "#   #", "#   #"],
    'I': [" ### ", "  #  ", "  #  ", "  #  ", "  #  ", "  #  ", " ### "],
    'J': ["  ###", "   # ", "   # ", "   # ", "   # ", "#  # ", " ##  "],
    'K': ["#   #", "#  # ", "# #  ", "##   ", "# #  ", "#  # ", "#   #"],
    'L': ["#    ", "#    ", "#    ", "#    ", "#    ", "#    ", "#####"],
    'M': ["#   #", "## ##", "# # #", "# # #", "#   #", "#   #", "#   #"],
    'N': ["#   #", "#   #", "##  #", "# # #", "#  ##", "#   #", "#   #"],
    'O': [" ### ", "#   #", "#   #", "#   #", "#   #", "#   #", " ### "],
    'P': ["#### ", "#   #", "#   #", "#### ", "#    ", "#    ", "#    "],
    'Q': [" ### ", "#   #", "#   #", "#   #", "# # #", "#  # ", " ## #"],
    'R': ["#### ", "#   #", "#   #", "#### ", "# #  ", "#  # ", "#   #"],
    'S': [" ####", "#    ", "#    ", " ### ", "    #", "    #", "#### "],
    'T': ["#####", "  #  ", "  #  ", "  #  ", "  #  ", "  #  ", "  #  "],
    'U': ["#   #", "#   #", "#   #", "#   #", "#   #", "#   #", " ### "],
    'V': ["#   #", "#   #", "#   #", "#   #", "#   #", " # # ", "  #  "],
    'W': ["#   #", "#   #", "#   #", "# # #", "# # #", "# # #", " # # "],
    'X': ["#   #", "#   #", " # # ", "  #  ", " # # ", "#   #", "#   #"],
    'Y': ["#   #", "#   #", " # # ", "  #  ", "  #  ", "  #  ", "  #  "],
    'Z': ["#####", "    #", "   # ", "  #  ", " #   ", "#    ", "#####"],
    ':': ["     ", " ##  ", " ##  ", "     ", " ##  ", " ##  ", "     "],
    '-': ["     ", "     ", "     ", "#####", "     ", "     ", "     "],
    '@': [" ### ", "#   #", "# ###", "# # #", "# ###", "#    ", " ####"],
    ';': ["     ", " ##  ", " ##  ", "     ", " ##  ", "  #  ", " #   "],
    ',': ["     ", "     ", "     ", "     ", " ##  ", "  #  ", " #   "],
    '.': ["     ", "     ", "     ", "     ", "     ", " ##  ", " ##  "],
    '/': ["     ", "    #", "   # ", "  #  ", " #   ", "#    ", "     "],
    'UP': ["  #  ", " ### ", "# # #", "  #  ", "  #  ", "  #  ", "  #  "],
    'DN': ["  #  ", "  #  ", "  #  ", "  #  ", "# # #", " ### ", "  #  "],
    'LT': ["     ", "  #  ", " #   ", "#####", " #   ", "  #  ", "     "],
    'RT': ["     ", "  #  ", "   # ", "#####", "   # ", "  #  ", "     "],
    '!': ["  #  ", "  #  ", "  #  ", "  #  ", "  #  ", "     ", "  #  "],
    '"': [" # # ", " # # ", " # # ", "     ", "     ", "     ", "     "],
    '#': [" # # ", " # # ", "#####", " # # ", "#####", " # # ", " # # "],
    '$': ["  #  ", " ####", "# #  ", " ### ", "  # #", "#### ", "  #  "],
    '%': ["##   ", "##  #", "   # ", "  #  ", " #   ", "#  ##", "   ##"],
    '&': [" ##  ", "#  # ", "# #  ", " #   ", "# # #", "#  # ", " ## #"],
    "'": ["  #  ", "  #  ", " #   ", "     ", "     ", "     ", "     "],
    '(': ["   # ", "  #  ", " #   ", " #   ", " #   ", "  #  ", "   # "],
    ')': [" #   ", "  #  ", "   # ", "   # ", "   # ", "  #  ", " #   "],
    '*': ["     ", "  #  ", "# # #", " ### ", "# # #", "  #  ", "     "],
    '=': ["     ", "     ", "#####", "     ", "#####", "     ", "     "],
    '+': ["     ", "  #  ", "  #  ", "#####", "  #  ", "  #  ", "     "],
    '<': ["   # ", "  #  ", " #   ", "#    ", " #   ", "  #  ", "   # "],
    '>': [" #   ", "  #  ", "   # ", "    #", "   # ", "  #  ", " #   "],
    '?': [" ### ", "#   #", "    #", "   # ", "  #  ", "     ", "  #  "],
}
CHARS = list(FONT.keys())
assert len(CHARS) <= 64, len(CHARS)
CODE = {c: i for i, c in enumerate(CHARS)}
for c, rows in FONT.items():
    assert len(rows) == 7 and all(len(r) == 5 for r in rows), c

# ---------------------------------------------------------------------------
# Keys: (label, shifted label or None, width hu, matrix row, matrix col,
# kind) per panel row; kind 'k' = normal key, 's' = SHIFT (latch toggle).
# Labels are lists of FONT keys. Matrix positions: dragon_keyboard.sv.
# ---------------------------------------------------------------------------
def k(label, shifted, w, mr, mc, kind='k'):
    lab = label if isinstance(label, list) else list(label)
    return dict(label=lab, shifted=shifted, w=w, mr=mr, mc=mc, kind=kind)

digits_shift = {'1': '!', '2': '"', '3': '#', '4': '$', '5': '%',
                '6': '&', '7': "'", '8': '(', '9': ')'}
row0 = [k(d, digits_shift[d], 2, 0, int(d)) for d in "1234567"]
row0 += [k('8', '(', 2, 1, 0), k('9', ')', 2, 1, 1), k('0', None, 2, 0, 0),
         k(':', '*', 2, 1, 2), k('-', '=', 2, 1, 5), k("BRK", None, 4, 6, 2)]
letters = {c: (2 + (i + 1) // 8, (i + 1) % 8) for i, c in enumerate("ABCDEFGHIJKLMNOPQRSTUVWXYZ")}
def L(c):
    r, col = letters[c]
    return k(c, None, 2, r, col)
row1 = [k(['UP'], None, 2, 5, 3)] + [L(c) for c in "QWERTYUIOP"] \
     + [k('@', None, 2, 2, 0), k(['LT'], None, 2, 5, 5), k(['RT'], None, 2, 5, 6)]
row2 = [k(['DN'], None, 2, 5, 4)] + [L(c) for c in "ASDFGHJKL"] \
     + [k(';', '+', 2, 1, 3), k("ENT", None, 4, 6, 0), k("CLR", None, 4, 6, 1)]
row3 = [k("SHF", None, 4, 6, 7, 's')] + [L(c) for c in "ZXCVBNM"] \
     + [k(',', '<', 2, 1, 4), k('.', '>', 2, 1, 6), k('/', '?', 2, 1, 7),
        k("SHF", None, 4, 6, 7, 's')]
row4 = [k("SPACE", None, 16, 5, 7)]
ROWS = [row0, row1, row2, row3, row4]

# sanity: matrix positions against dragon_keyboard.sv's grid
GRID = [
    "0 1 2 3 4 5 6 7".split(),
    "8 9 : ; , - . /".split(),
    "@ A B C D E F G".split(),
    "H I J K L M N O".split(),
    "P Q R S T U V W".split(),
    "X Y Z UP DN LT RT SPACE".split(),
    "ENT CLR BRK - - - - SHF".split(),
]
for row in ROWS:
    for key in row:
        name = ''.join(key['label'])
        assert GRID[key['mr']][key['mc']] == name, (name, key['mr'], key['mc'])

# place each row centred in 32 hu
keys = []
row_first, row_count = [], []
for r, row in enumerate(ROWS):
    total = sum(key['w'] for key in row)
    x = (32 - total) // 2
    row_first.append(len(keys))
    row_count.append(len(row))
    for key in row:
        key['row'] = r
        key['start'] = x
        x += key['w']
        keys.append(key)
NKEYS = len(keys)
assert NKEYS <= 64
for key in keys:
    assert len(key['label']) <= key['w'], key  # 8 px per char = 1 hu

# ---------------------------------------------------------------------------
# Emit SystemVerilog
# ---------------------------------------------------------------------------
out = []
w = out.append
w("// GENERATED by tools/gen_osd_tables.py - do not edit by hand.")
w("//")
w("// On-screen keyboard tables, as combinational logic (no block RAM is")
w("// free). See osd_keyboard.sv.")
w("`default_nettype none")
w("")
w(f"// {len(CHARS)} glyphs, 5x7 in an 8x8 cell: bits[4:0] = pixel columns 1..5")
w("// (bit 4 leftmost). Rows 7 are blank.")
w("module osd_font_rom (")
w("    input  wire [5:0] ch,")
w("    input  wire [2:0] row,")
w("    output reg  [4:0] bits")
w(");")
w("    always_comb begin")
w("        case ({ch, row})")
for c in CHARS:
    for r, line in enumerate(FONT[c]):
        v = int(''.join('1' if p == '#' else '0' for p in line), 2)
        if v:
            w(f"            {{6'd{CODE[c]}, 3'd{r}}}: bits = 5'b{v:05b}; // {c!r}")
w("            default: bits = 5'b00000;")
w("        endcase")
w("    end")
w("endmodule")
w("")
w(f"// Key attributes by key id (0..{NKEYS-1}).")
w("//   start/width - in 8-pixel half-units across the 256-pixel panel")
w("//   nchars, c0..c4 - label; sh - shifted label (1 char), has_sh valid")
w("//   mrow/mcol - Dragon matrix position; is_shift - SHIFT latch key")
w("//   prow - panel row (0..4) the key sits on")
w("module osd_key_table (")
w("    input  wire [5:0] id,")
w("    output reg  [4:0] start,")
w("    output reg  [4:0] width,")
w("    output reg  [2:0] nchars,")
w("    output reg  [5:0] c0, c1, c2, c3, c4,")
w("    output reg  [5:0] sh,")
w("    output reg        has_sh,")
w("    output reg  [2:0] mrow,")
w("    output reg  [2:0] mcol,")
w("    output reg        is_shift,")
w("    output reg  [2:0] prow")
w(");")
w("    always_comb begin")
w("        start = 5'd0; width = 5'd0; nchars = 3'd0;")
w("        c0 = 6'd0; c1 = 6'd0; c2 = 6'd0; c3 = 6'd0; c4 = 6'd0;")
w("        sh = 6'd0; has_sh = 1'b0; mrow = 3'd0; mcol = 3'd0; is_shift = 1'b0; prow = 3'd0;")
w("        case (id)")
for i, key in enumerate(keys):
    cs = [CODE[c] for c in key['label']] + [0] * (5 - len(key['label']))
    shc = CODE[key['shifted']] if key['shifted'] else 0
    assert key['w'] < 32
    w(f"            6'd{i}: begin start = 5'd{key['start']}; width = 5'd{key['w']}; "
      f"nchars = 3'd{len(key['label'])}; "
      f"c0 = 6'd{cs[0]}; c1 = 6'd{cs[1]}; c2 = 6'd{cs[2]}; c3 = 6'd{cs[3]}; c4 = 6'd{cs[4]}; "
      f"sh = 6'd{shc}; has_sh = 1'b{1 if key['shifted'] else 0}; "
      f"mrow = 3'd{key['mr']}; mcol = 3'd{key['mc']}; is_shift = 1'b{1 if key['kind'] == 's' else 0}; prow = 3'd{key['row']}; "
      f"end // {''.join(key['label'])}")
w("            default: ;")
w("        endcase")
w("    end")
w("endmodule")
w("")
w("// Which key covers half-unit hu of panel row prow: {hit, id}.")
w("module osd_key_map (")
w("    input  wire [2:0] prow,")
w("    input  wire [4:0] hu,")
w("    output reg        hit,")
w("    output reg  [5:0] id")
w(");")
w("    always_comb begin")
w("        hit = 1'b0; id = 6'd0;")
w("        case ({prow, hu})")
for i, key in enumerate(keys):
    for h in range(key['start'], key['start'] + key['w']):
        w(f"            {{3'd{key['row']}, 5'd{h}}}: begin hit = 1'b1; id = 6'd{i}; end")
w("            default: ;")
w("        endcase")
w("    end")
w("endmodule")
w("")
w("// First key id and key count of each panel row.")
w("module osd_row_info (")
w("    input  wire [2:0] prow,")
w("    output reg  [5:0] first,")
w("    output reg  [5:0] count")
w(");")
w("    always_comb begin")
w("        case (prow)")
for r in range(5):
    w(f"            3'd{r}: begin first = 6'd{row_first[r]}; count = 6'd{row_count[r]}; end")
w("            default: begin first = 6'd0; count = 6'd1; end")
w("        endcase")
w("    end")
w("endmodule")
w("")
w("`default_nettype wire")

here = os.path.dirname(os.path.abspath(__file__))
dst = os.path.join(here, '..', 'src', 'fpga', 'core', 'dragon', 'osd', 'osd_keyboard_tables.sv')
os.makedirs(os.path.dirname(dst), exist_ok=True)
with open(dst, 'w') as f:
    f.write('\n'.join(out) + '\n')
print(f"wrote {os.path.relpath(dst)}: {len(CHARS)} glyphs, {NKEYS} keys, rows {row_count}")
