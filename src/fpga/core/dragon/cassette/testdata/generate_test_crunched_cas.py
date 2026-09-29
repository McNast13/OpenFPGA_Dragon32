#!/usr/bin/env python3
"""
Generates test_crunched.cas: the same trivial test program as test.cas
("10 PRINT "HELLO FROM CLAUDE" / 20 GO TO 10"), but pre-tokenized
("crunched") instead of stored as literal ASCII source.

Why this file exists: a 2026-09-29 hardware test found CLOAD/RUN both
report success on test.cas, but LIST shows no program - CLOAD's ASCII
path (TYPE=00, ASCII=FF, MODE=FF - see generate_test_cas.py's header for
the full table) reports "done" without ever storing anything. By that
point the tape delivery pipeline had already been proven bit-accurate
(both independently, via cassette-nibbler and manual checksum
recomputation, and again that same session via a real cas_ram timing
simulation showing the exact intended bytes arrive in order), and a
hand-typed program at the keyboard was confirmed to LIST/RUN fine - so
the fault isn't the file's bytes, and isn't BASIC's program
storage/editor in general. What's left is specifically ASCII CLOAD's own
mechanism of re-feeding tape bytes through the line-input/tokenizer as
if typed - a different code path from both manual typing and from
crunched-format loading (TYPE=00, ASCII=00, MODE=00), which (per the
disassembly-sourced note in generate_test_cas.py's header) shares its
low-level block-fetch with CLOADM's raw machine-code loader - the one
path already confirmed to make real progress on hardware (Jet Set
Willy's CLOADM reaches its own loading screen). If this crunched file
loads correctly where the ASCII one doesn't, that's decisive
confirmation the bug is confined to ASCII CLOAD's re-tokenizing
mechanism specifically.

Tokenized (crunched) program format in memory (and, per real CSAVE/CLOAD
behavior, identically on tape - crunched CLOAD copies bytes directly
into place with no address relocation, so this file's "next line"
pointers must already target the real runtime addresses the program
will occupy):

    [next_line_addr: 2 bytes, big-endian][line_number: 2 bytes][
        tokenized statement bytes][0x00 line terminator]

repeated per line, with the LAST line's own next_line_addr field set to
0x0000 - that's the complete end-of-program marker; no extra trailing
record is needed. (Sourced from subethasoftware.com's Color BASIC
program-memory-format writeup and corroborated by the MSX-wiki/GW-BASIC
tokenized-format pages, which describe the same Microsoft BASIC-derived
scheme; this project's own dragon32.info-sourced token table - see
generate_test_cas.py - separately confirms PRINT=$87 and GO=$81, with
"GO TO"/"GO SUB" stored as the GO token followed by literal,
unabbreviated ASCII text, not a dedicated TO/SUB token.)

TXTTAB was originally guessed as $1E00 (per dragon32.info's Dragon-
specific memmap page), flagged as unverified against a 1-byte-different
generic-CoCo figure ($1E01) with no way to resolve from documentation
alone. Resolved directly against this core's own running ROM: a
2026-09-29 hardware test read PEEK(25)=30, PEEK(26)=1, i.e. TXTTAB=
30*256+1=7681=$1E01 - confirming the generic-CoCo figure, not the
Dragon-specific doc, was right for this core. Value below updated
accordingly.
"""

TXTTAB = 0x1E01  # confirmed via PEEK(25)*256+PEEK(26) on real hardware, 2026-09-29

PRINT_TOKEN = 0x87
GO_TOKEN = 0x81


def block(type_byte, data):
    length = len(data)
    checksum = (type_byte + length + sum(data)) & 0xFF
    return bytes([0x55, 0x3C, type_byte, length]) + bytes(data) + bytes([checksum, 0x55])


def basic_line(line_number, token_bytes, next_addr):
    body = bytes([next_addr >> 8, next_addr & 0xFF, line_number >> 8, line_number & 0xFF]) \
        + bytes(token_bytes) + bytes([0x00])
    return body


def build():
    leader = bytes([0x55] * 128)

    filename = b"TESTC   "  # 8 chars, space-padded - distinct name from test.cas
    fn_data = list(filename) + [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]  # BASIC CRUNCHED row
    assert len(fn_data) == 15
    filename_block = block(0x00, fn_data)

    line1_tokens = bytes([PRINT_TOKEN]) + b'"HELLO FROM CLAUDE"'
    line2_tokens = bytes([GO_TOKEN]) + b' TO 10'

    line1_len = 2 + 2 + len(line1_tokens) + 1  # next_addr + line_num + tokens + terminator
    line2_addr = TXTTAB + line1_len

    line1 = basic_line(10, line1_tokens, next_addr=line2_addr)
    line2 = basic_line(20, line2_tokens, next_addr=0x0000)  # 0x0000 = end of program

    program = line1 + line2
    data_block = block(0x01, list(program))

    eof_block = block(0xFF, [])
    trailing_eofs = eof_block * 200

    return leader + filename_block + data_block + trailing_eofs


if __name__ == "__main__":
    cas = build()
    with open("test_crunched.cas", "wb") as f:
        f.write(cas)
    print(f"Wrote {len(cas)} bytes to test_crunched.cas (TXTTAB=0x{TXTTAB:04X})")
