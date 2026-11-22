-- tb_riscv_cpu.vhd : self-checking testbench (verification only, not for submission)
library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity tb_riscv_cpu is
end entity;

architecture sim of tb_riscv_cpu is
  signal clk, reset : std_logic := '0';
  signal done       : boolean := false;
  signal dbg_reg_addr : std_logic_vector(4 downto 0)  := (others => '0');
  signal dbg_mem_addr : std_logic_vector(31 downto 0) := (others => '0');
  signal dbg_reg_data, dbg_mem_data : std_logic_vector(31 downto 0);
  signal pc_out, instr_out, alu_result_out, reg_data1_out, reg_data2_out, mem_data_out
         : std_logic_vector(31 downto 0);
  signal mem_read_out, mem_write_out, branch_taken_out : std_logic;
begin

  dut : entity work.riscv_cpu
    port map (clk => clk, reset => reset,
              dbg_reg_addr => dbg_reg_addr, dbg_reg_data => dbg_reg_data,
              dbg_mem_addr => dbg_mem_addr, dbg_mem_data => dbg_mem_data,
              pc_out => pc_out, instr_out => instr_out,
              alu_result_out => alu_result_out, reg_data1_out => reg_data1_out,
              reg_data2_out => reg_data2_out, mem_data_out => mem_data_out,
              mem_read_out => mem_read_out, mem_write_out => mem_write_out,
              branch_taken_out => branch_taken_out);

  clk_gen : process
  begin
    while not done loop
      clk <= '0'; wait for 5 ns;
      clk <= '1'; wait for 5 ns;
    end loop;
    wait;
  end process;

  stim : process
    variable errs : integer := 0;

    function w(v : natural) return std_logic_vector is
    begin
      return std_logic_vector(to_unsigned(v, 32));
    end function;

    procedure check(cond : boolean; msg : string) is
    begin
      if not cond then
        errs := errs + 1;
        report "FAIL: " & msg severity error;
      end if;
    end procedure;

    procedure check_reg(n : natural; exp : natural; msg : string) is
    begin
      dbg_reg_addr <= std_logic_vector(to_unsigned(n, 5));
      wait for 1 ps;
      check(dbg_reg_data = w(exp), msg & " (x" & integer'image(n) & ")");
    end procedure;

    procedure check_mem(byte_addr : natural; exp : natural; msg : string) is
    begin
      dbg_mem_addr <= w(byte_addr);
      wait for 1 ps;
      check(dbg_mem_data = w(exp), msg);
    end procedure;

    procedure all_regs(x1,x2,x3,x4,x5,x6,x7 : natural; tag : string) is
    begin
      check_reg(0, 0,  tag & ": x0 must be 0");
      check_reg(1, x1, tag); check_reg(2, x2, tag); check_reg(3, x3, tag);
      check_reg(4, x4, tag); check_reg(5, x5, tag); check_reg(6, x6, tag);
      check_reg(7, x7, tag);
    end procedure;
  begin
    -- ---------- Reset (2 rising edges at 5 ns and 15 ns) ----------
    reset <= '1';
    wait until falling_edge(clk);
    wait until falling_edge(clk);
    reset <= '0';
    wait for 1 ps;
    check(pc_out = w(0), "reset: PC = 0");
    all_regs(10, 20, 0, 100, 0, 0, 0, "reset regs");
    check_mem(100, 0, "reset: Mem[100] = 0");

    -- ---------- Instruction 1: ADD x3,x1,x2 at PC=0 ----------
    check(instr_out = x"002081B3", "ADD x3,x1,x2 encoding");
    check(reg_data1_out = w(10) and reg_data2_out = w(20), "ADD operands");
    check(alu_result_out = w(30), "ADD alu = 30");
    check(mem_read_out = '0' and mem_write_out = '0' and branch_taken_out = '0', "ADD controls");
    wait until falling_edge(clk);
    check(pc_out = w(4), "PC=4 after ADD");
    all_regs(10, 20, 30, 100, 0, 0, 0, "after ADD");

    -- ---------- Instruction 2: SW x3,0(x4) at PC=4 ----------
    check(instr_out = x"00322023", "SW x3,0(x4) encoding");
    check(alu_result_out = w(100) and mem_write_out = '1', "SW address=100, write");
    wait until falling_edge(clk);
    check(pc_out = w(8), "PC=8 after SW");
    check_mem(100, 30, "SW stored 30 at Mem[100]");
    all_regs(10, 20, 30, 100, 0, 0, 0, "after SW (no reg write)");

    -- ---------- Instruction 3: LW x5,0(x4) at PC=8 ----------
    check(instr_out = x"00022283", "LW x5,0(x4) encoding");
    check(mem_read_out = '1' and mem_data_out = w(30), "LW reads 30");
    wait until falling_edge(clk);
    check(pc_out = w(12), "PC=12 after LW");
    all_regs(10, 20, 30, 100, 30, 0, 0, "after LW");

    -- ---------- Instruction 4: BEQ x3,x5,+8 at PC=12 ----------
    check(instr_out = x"00518463", "BEQ x3,x5,+8 encoding");
    check(branch_taken_out = '1', "BEQ taken (30 = 30)");
    wait until falling_edge(clk);
    check(pc_out = w(20), "PC jumped 12 -> 20");
    all_regs(10, 20, 30, 100, 30, 0, 0, "after BEQ");

    -- ---------- Instruction at 20: ADD x7,x1,x2 (16 skipped) ----------
    check(instr_out = x"002083B3", "ADD x7,x1,x2 encoding at PC=20");
    wait until falling_edge(clk);
    check(pc_out = w(24), "PC=24 after final ADD");
    all_regs(10, 20, 30, 100, 30, 0, 30, "final: x6 = 0 proves addr 16 skipped");

    -- ---------- Extra cycles: NOPs, state must not change ----------
    wait until falling_edge(clk);
    all_regs(10, 20, 30, 100, 30, 0, 30, "NOP region stable");
    check_mem(100, 30, "Mem[100] still 30");

    -- ---------- Reset again mid-state ----------
    reset <= '1';
    wait until falling_edge(clk);
    check(pc_out = w(0), "second reset: PC = 0");
    all_regs(10, 20, 0, 100, 0, 0, 0, "second reset regs");
    check_mem(100, 0, "second reset clears memory");
    reset <= '0';

    done <= true;
    if errs = 0 then
      report "ALL TESTS PASSED" severity note;
    else
      report integer'image(errs) & " TEST(S) FAILED" severity failure;
    end if;
    wait;
  end process;

end architecture;
