#!/usr/bin/env python3
"""Generates test_cart.rom: a minimal 8K Dragon 32 cartridge (original
code, hand-assembled 6809) for testing the Cartridge data slot.

The Dragon autostarts a cartridge through its CART line (PIA1 CB1 ->
FIRQ -> BASIC jumps to $C000). This one clears the text screen ($0400-
$05FF, $60 = space as BASIC stores it) and prints CARTRIDGE OK in the
middle, then loops forever. 8K, so it also checks the 8K mirroring:
$E000 reads the same bytes as $C000.

    python3 gen_test_cart.py      # writes test_cart.rom next to this file
"""
import os

def vdg(text):
    # Dragon text screen codes, as BASIC POKEs them: 'A' = $41, space = $60
    return bytes(0x60 if c == ' ' else ord(c) for c in text)

msg_row, msg = 7, "CARTRIDGE OK"
msg_addr = 0x0400 + msg_row * 32 + (32 - len(msg)) // 2

code = bytes([
    0x8E, 0x04, 0x00,                   # C000 LDX  #$0400
    0x86, 0x60,                         # C003 LDA  #$60
    0xA7, 0x80,                         # C005 STA  ,X+
    0x8C, 0x06, 0x00,                   # C007 CMPX #$0600
    0x26, 0xF9,                         # C00A BNE  $C005
    0x8E, msg_addr >> 8, msg_addr & 0xFF,  # C00C LDX #msg_addr
    0x10, 0x8E, 0xC0, 0x20,             # C00F LDY  #$C020
    0xA6, 0xA0,                         # C013 LDA  ,Y+
    0x27, 0x04,                         # C015 BEQ  $C01B
    0xA7, 0x80,                         # C017 STA  ,X+
    0x20, 0xF8,                         # C019 BRA  $C013
    0x20, 0xFE,                         # C01B BRA  $C01B
])
rom = bytearray(code + bytes([0x12] * (0x20 - len(code))))   # NOP pad to $C020
rom += vdg(msg) + b"\x00"
rom += bytes([0xFF] * (8192 - len(rom)))
assert len(rom) == 8192

# sanity: branch targets
def target(pc, off):  # pc = address of the branch opcode, 2-byte branch
    return pc + 2 + (off - 256 if off > 127 else off)
assert target(0xC00A, 0xF9) == 0xC005
assert target(0xC015, 0x04) == 0xC01B
assert target(0xC019, 0xF8) == 0xC013
assert target(0xC01B, 0xFE) == 0xC01B

out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "test_cart.rom")
open(out, "wb").write(rom)
print(f"wrote {out} ({len(rom)} bytes), message at ${msg_addr:04X}")
