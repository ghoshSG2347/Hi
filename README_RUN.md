# Running the project (GHDL + GTKWave)

Files: `riscv_cpu.vhd` (the complete CPU, the only file you submit), `tb_riscv_cpu.vhd` (testbench), `verify_model.py` (Python cross-check).

```bash
# Install (Ubuntu/Kali):  sudo apt install ghdl gtkwave
ghdl -a --std=08 riscv_cpu.vhd
ghdl -a --std=08 tb_riscv_cpu.vhd
ghdl -e --std=08 tb_riscv_cpu
ghdl -r --std=08 tb_riscv_cpu --assert-level=error --vcd=wave.vcd
gtkwave wave.vcd
```

Expected last line: `ALL TESTS PASSED`. Any failed check prints `FAIL: ...` and the run exits with an error.

In GTKWave add these signals: `clk`, `reset`, `pc_out`, `instr_out`, `reg_data1_out`, `reg_data2_out`, `alu_result_out`, `mem_read_out`, `mem_write_out`, `mem_data_out`, `branch_taken_out`.
Set value format to Hex or Decimal. You will see `pc_out` go 0, 4, 8, 12, 20, 24 (16 is never visited).

Your original modular repo is untouched; this is a separate implementation.
