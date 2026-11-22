#!/usr/bin/env python3
"""Independent check (NOT a VHDL simulation): encodes the 6 instructions with a
separate implementation, decodes them back, and runs a Python model of the CPU."""

def enc_r(f7, rs2, rs1, f3, rd, op): return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op
def enc_i(imm, rs1, f3, rd, op):     return ((imm & 0xFFF) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op
def enc_s(imm, rs2, rs1, f3, op):    i = imm & 0xFFF; return ((i >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | ((i & 31) << 7) | op
def enc_b(imm, rs2, rs1, f3, op):
    i = imm & 0x1FFF
    return (((i >> 12) & 1) << 31) | (((i >> 5) & 63) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (((i >> 1) & 15) << 8) | (((i >> 11) & 1) << 7) | op

prog = [enc_r(0,2,1,0,3,0x33), enc_s(0,3,4,2,0x23), enc_i(0,4,2,5,0x03),
        enc_b(8,5,3,0,0x63), enc_r(0,1,1,0,6,0x33), enc_r(0,2,1,0,7,0x33)]
expected = [0x002081B3, 0x00322023, 0x00022283, 0x00518463, 0x00108333, 0x002083B3]
for a, (p, e) in enumerate(zip(prog, expected)):
    print(f"{a*4:2d}: {p:08X}  expected {e:08X}  {'OK' if p == e else 'MISMATCH'}")
assert prog == expected

def sx(v, bits): return v - (1 << bits) if v & (1 << (bits - 1)) else v
regs = [0]*32; regs[1], regs[2], regs[4] = 10, 20, 100
mem = {}; pc = 0
while pc // 4 < len(prog):
    i = prog[pc // 4]; op = i & 0x7F; rd = (i >> 7) & 31; f3 = (i >> 12) & 7
    rs1 = (i >> 15) & 31; rs2 = (i >> 20) & 31; npc = pc + 4
    if op == 0x33 and f3 == 0 and (i >> 25) == 0: regs[rd] = (regs[rs1] + regs[rs2]) & 0xFFFFFFFF
    elif op == 0x03: regs[rd] = mem.get(regs[rs1] + sx(i >> 20, 12), 0)
    elif op == 0x23: mem[regs[rs1] + sx(((i >> 25) << 5) | ((i >> 7) & 31), 12)] = regs[rs2]
    elif op == 0x63:
        imm = sx((((i >> 31) & 1) << 12) | (((i >> 7) & 1) << 11) | (((i >> 25) & 63) << 5) | (((i >> 8) & 15) << 1), 13)
        if regs[rs1] == regs[rs2]: npc = pc + imm
    regs[0] = 0
    print(f"PC {pc:2d} -> {npc:2d}  x3={regs[3]} x5={regs[5]} x6={regs[6]} x7={regs[7]} mem[100]={mem.get(100)}")
    pc = npc
assert regs[3] == 30 and regs[5] == 30 and regs[6] == 0 and regs[7] == 30 and mem[100] == 30
print("Python model: all checks passed")
