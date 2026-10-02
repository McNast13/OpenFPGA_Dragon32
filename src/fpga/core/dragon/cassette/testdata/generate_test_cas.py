#!/usr/bin/env python3
"""
Generates test.cas: a minimal, valid Dragon 32 cassette BASIC program, used
as both a real-hardware test file and tb_cas_fullfile.sv's regression input.

Format facts (leader/block/checksum structure, and the CASBUF+8/9/10
TYPE/ASCII/MODE table) came from two public hardware references - see
../cas_player.sv's header and NOTES.md's "Cassette (.cas) loading" section
for the full sourcing writeup. Byte 10 of the filename block is NOT a "gap
flag" (an earlier, less authoritative reading led to a real bug - see
BUILD_LOG.md, 2026-09-27 "hardware test (dual-path diagnostic)") - it's
part of a combined ASCII+MODE selector, confirmed against the actual
Color BASIC ROM disassembly ("Color BASIC Unravelled"):

  File kind        TYPE(8) ASCII(9) MODE(10)
  BASIC CRUNCHED    00      00       00
  BASIC ASCII       00      FF       FF
  DATA              01      FF       FF
  MACHINE LANGUAGE  02      00       00

A second leader IS required between the filename and data blocks (an
earlier version removed it - wrongly). Confirmed against the real Dragon
32 ROM: every block fetch after the filename goes through the ROM's
"motor on" routine ($BDCF: set PIA1 CRA bit 3, then LDX $95 / LEAX -1,X
/ BNE - a ~447k-CPU-cycle spin, $95 initialised to $DA5C from the ROM's
init table at $BBA5), i.e. ~0.5s of tape at real speed rolling past
*with the motor on and nobody listening*, before it starts hunting for
the next sync byte. Real CSAVE output always has a leader there to
absorb that. Without one, the whole ~0.25s data block played straight
through the delay unheard, and the first sync the ROM found was in an
EOF block - so CLOAD said OK having loaded nothing (and, with only one
EOF block, wrapped round into the header and gave ?IO ERROR - the
original reason for the 200 EOF blocks below). 256 leader bytes
(~1.3s) gives comfortable margin over the 0.5s delay.

"GOTO" is not one word to Color BASIC's tokenizer - GOTO/GOSUB tokenize
as GO (a real token, 0x81) followed by literal, unabbreviated text " TO"/
" SUB", not a single two-word token (confirmed via a public tokens
reference, dragon32.info/info/cocotokn.html) - so the test program uses
"GO TO", not "GOTO".

Multiple trailing EOF blocks: a hardware test with cas_player.sv looping
the whole file at end-of-tape (rather than going silent - see that
file's header) turned an infinite hang into a clean "?IO ERROR" for this
file specifically - real, measurable progress (the CPU is no longer
stuck waiting for an edge that structurally can never arrive), but the
retry-after-EOF this exposed lands back on the leader/filename block
(the file's own start, once cas_player wraps), which CLOAD correctly
rejects as an unexpected header where it expected another data-or-EOF
block. Repeating the EOF block several times gives any such retry
another valid "no more data" signal instead, without needing to teach
cas_player.sv anything about block boundaries (it has no concept of the
.cas format's internal structure - it just plays bytes as tone cycles).
"""


def block(type_byte, data):
    length = len(data)
    checksum = (type_byte + length + sum(data)) & 0xFF
    return bytes([0x55, 0x3C, type_byte, length]) + bytes(data) + bytes([checksum, 0x55])


def build():
    leader = bytes([0x55] * 256)

    filename = b"TEST    "  # 8 chars, space-padded
    fn_data = list(filename) + [0x00, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00]  # BASIC ASCII row
    assert len(fn_data) == 15
    filename_block = block(0x00, fn_data)

    program_text = b'10 PRINT "HELLO FROM CLAUDE"\r20 GO TO 10\r'
    data_block = block(0x01, list(program_text))

    eof_block = block(0xFF, [])
    trailing_eofs = eof_block * 200

    return leader + filename_block + leader + data_block + trailing_eofs


if __name__ == "__main__":
    cas = build()
    with open("test.cas", "wb") as f:
        f.write(cas)
    print(f"Wrote {len(cas)} bytes to test.cas")
