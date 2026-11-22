# Single-Cycle RISC-V Processor in VHDL: Explanation for the Report

## 1. Single-cycle processor
A processor that finishes one complete instruction (fetch, decode, execute, memory, write-back) in exactly one clock cycle. All combinational logic settles during the cycle; at the next rising clock edge the PC, register file and data memory update together. It is simple, but the clock period must fit the slowest instruction (here LW).

## 2. RISC-V, RV32I
RISC-V is an open instruction set architecture (ISA). **RV32I** = the base integer ISA with 32-bit registers/addresses and 32-bit fixed-width instructions. This project implements the subset ADD, LW, SW, BEQ.

## 3. Components (all inside `riscv_cpu.vhd`)
| Component | Function | In the code |
|---|---|---|
| Program Counter | 32-bit register holding the address of the current instruction | signal `pc`, updated in `state_update` |
| Instruction memory | ROM with the demo program, word index = PC[5:2] | constant `IMEM`, signal `instr` |
| Decoder / control | Splits the instruction into fields; checks opcode, funct3, funct7; raises control signals | `is_add/is_lw/is_sw/is_beq`, `reg_write`, `alu_src`, `mem_read`, `mem_write`, `mem_to_reg` |
| Register file | 32 x 32-bit registers, 2 read ports, 1 write port, x0 hard-wired to 0 | `regs`, `rd1`, `rd2` |
| Immediate generator | Rebuilds and sign-extends I, S and B immediates | `imm_i`, `imm_s`, `imm_b`, `imm` |
| ALU | 32-bit adder (all that this subset needs) | `alu_result` |
| Data memory | 64 words, byte addresses, combinational read, synchronous write | `dmem` |
| Write-back | Picks memory data (LW) or ALU result (ADD) | `wb_data` |
| Branch logic | `branch_taken = is_beq AND (rs1 = rs2)` | `branch_taken` |
| Next-PC mux | PC+4, or PC + branch offset if taken | `next_pc` |

## 4. Instruction path
PC -> instruction memory -> decoder (fields + control) -> register file reads -> immediate generator -> ALU -> data memory -> write-back mux -> register write; in parallel, branch logic picks the next PC. Updates occur on the clock edge.

Fields: opcode [6:0], rd [11:7], funct3 [14:12], rs1 [19:15], rs2 [24:20], funct7 [31:25].

## 5. How each instruction executes
- **ADD** (R-type, opcode 0110011, funct3 000, funct7 0000000): read rs1, rs2, ALU adds, write result to rd (skipped if rd = x0). Other R-type instructions are *not* treated as ADD because funct3 and funct7 are checked.
- **LW** (I-type, opcode 0000011, funct3 010): imm = sign-extend(instr[31:20]); address = rs1 + imm; memory word at that address is written into rd.
- **SW** (S-type, opcode 0100011, funct3 010): imm = sign-extend(instr[31:25] & instr[11:7]); address = rs1 + imm; rs2 is written to memory. `reg_write` = 0, so no register changes.
- **BEQ** (B-type, opcode 1100011, funct3 000): imm = sign-extend(instr[31], instr[7], instr[30:25], instr[11:8], 0). The trailing 0 is the implicit LSB (branch offsets are even). If rs1 = rs2, next PC = PC + imm, else PC + 4. No register or memory write.

## 6. Program Counter
Reset sets PC = 0. Normally PC <- PC + 4. On a taken BEQ, PC <- PC + imm.

## 7. Register file
32 registers; two read ports are combinational (read at any time); one write on the rising edge when `reg_write = 1` and rd /= 0. x0 reads as 0 and is never written.

## 8. Decoding
Slice the instruction bits into fields, compare opcode/funct3/funct7 with the constants in the RV32I spec, and set the control signals. Unsupported instructions produce all-zero controls, so they change nothing (except PC advancing by 4).

## 9. ALU
`alu_result = rs1 + B`, where B = rs2 (ADD) or the immediate (LW/SW address). Arithmetic is modulo 2^32, so negative immediates work in two's complement. BEQ's equality test uses a separate comparator, not the ALU.

## 10. Memory addressing
Addresses are **bytes**; memory is word-oriented. Data memory index = address[7:2] (so byte address 100 is word 25). Valid addresses: 0 to 255 and multiple of 4. Unaligned or out-of-range: loads return 0, stores are ignored. Instruction memory uses PC[5:2], covers 0 to 63, and returns a NOP beyond that.

## 11. Reset
Active-high and synchronous: when `reset = 1` at a rising edge, PC = 0, registers = demo values (x1=10, x2=20, x4=100, others 0), data memory = all zeros.

## 12. Machine code (from the spec layouts)
| Addr | Assembly | Hex |
|---|---|---|
| 0 | ADD x3,x1,x2 | 0x002081B3 |
| 4 | SW x3,0(x4) | 0x00322023 |
| 8 | LW x5,0(x4) | 0x00022283 |
| 12 | BEQ x3,x5,+8 | 0x00518463 |
| 16 | ADD x6,x1,x1 | 0x00108333 |
| 20 | ADD x7,x1,x2 | 0x002083B3 |

## 13. Clock-by-clock execution
| Clock | PC before | Instruction | Important operation | PC after | State after |
|---|---|---|---|---|---|
| 1 | 0 | ADD x3,x1,x2 | 10 + 20 = 30 -> x3 | 4 | x3 = 30 |
| 2 | 4 | SW x3,0(x4) | address 0+100; Mem[100] = 30 | 8 | Mem[100] = 30 |
| 3 | 8 | LW x5,0(x4) | read Mem[100]; x5 = 30 | 12 | x5 = 30 |
| 4 | 12 | BEQ x3,x5,+8 | 30 = 30, taken; target 12 + 8 | 20 | none |
| 5 | 20 | ADD x7,x1,x2 | 10 + 20 = 30 -> x7 | 24 | x7 = 30 |

Address 16 is never executed, so x6 stays 0. This is the proof of the branch: x7 = 30 (reached address 20) and x6 = 0 (address 16 skipped). x3 = x5 = 30 together with Mem[100] = 30 proves SW and LW; x3 = 30 proves ADD.

## 14. How the demo proves correctness
Each instruction produces a distinct observable result: ADD (x3), SW (memory), LW (x5, read back from memory, not just copied), BEQ (PC jumps 12 -> 20, skipping 16). x0 stays 0 throughout.

## 15. Final review (honest answers)
1. One standalone VHDL file? **Yes**, `riscv_cpu.vhd`, IEEE libraries only. The testbench is a separate verification file.
2. Supports ADD, LW, SW, BEQ? **Yes.**
3. Encodings correct? **Yes.** Built field-by-field in VHDL functions, and cross-checked against an independent Python encoder (all 6 match).
4. x0 stays zero? **Yes by design** (never written, read forced to 0); the testbench asserts it.
5. Demo executes correctly? Confirmed by the **Python model** and static trace; the VHDL simulation was **not run** (see below).
6. Branch taken correctly? By design and the Python model: 12 -> 20.
7. Address 16 skipped? Same: yes in the model; the testbench asserts x6 = 0.
8. Compiles? **Not verified.** GHDL was not available in my environment.
9. Testbench passed? **Not run.** I could not execute it, so I can't claim it passed. Run the commands in README_RUN.md; the output should end with `ALL TESTS PASSED`.
10. Limitations: only ADD/LW/SW/BEQ; no byte/halfword access; no exceptions for misaligned/out-of-range access (silently safe); ALU only adds; memory sizes are small; GHDL compile/simulation unverified by me; I could only read summaries of your repo's files (the fetch tool could not return the source verbatim), so my comparison with your modular design is high level: its structure (PC, ROM, control, regfile, immgen, ALU, data memory) matches this one, but I did not audit it line by line for bugs.
