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
"""


def block(type_byte, data):
    length = len(data)
    checksum = (type_byte + length + sum(data)) & 0xFF
    return bytes([0x55, 0x3C, type_byte, length]) + bytes(data) + bytes([checksum, 0x55])


def build():
    leader = bytes([0x55] * 128)

    filename = b"TEST    "  # 8 chars, space-padded
    fn_data = list(filename) + [0x00, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00]  # BASIC ASCII row
    assert len(fn_data) == 15
    filename_block = block(0x00, fn_data)

    program_text = b'10 PRINT "HELLO FROM CLAUDE"\r20 GOTO 10\r'
    data_block = block(0x01, list(program_text))

    eof_block = block(0xFF, [])

    return leader + filename_block + leader + data_block + eof_block


if __name__ == "__main__":
    cas = build()
    with open("test.cas", "wb") as f:
        f.write(cas)
    print(f"Wrote {len(cas)} bytes to test.cas")
