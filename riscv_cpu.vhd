--------------------------------------------------------------------------------
-- riscv_cpu.vhd  --  Single-cycle RISC-V (RV32I subset) processor, ONE FILE
--
-- Supported instructions : ADD, LW, SW, BEQ   (everything else = no-op)
-- Libraries              : IEEE.STD_LOGIC_1164, IEEE.NUMERIC_STD only
-- Compile (GHDL)         : ghdl -a --std=08 riscv_cpu.vhd
--
-- CONVENTIONS
--   * Clock   : rising edge.
--   * Reset   : ACTIVE-HIGH, SYNCHRONOUS (sampled at a rising clock edge).
--               While reset='1' at a clock edge: PC=0, registers are loaded with
--               the demo initial values (x1=10, x2=20, x4=100, rest 0), and the
--               data memory is cleared.
--   * Addresses are BYTE addresses.
--       Instruction memory : 16 words (byte addr 0..63). Word index = PC[5:2].
--       Data memory        : 64 words (byte addr 0..255). Word index = addr[7:2].
--       Unaligned (addr[1:0] /= "00") or out-of-range accesses are SAFE:
--         a load returns 0, a store is ignored. An out-of-range fetch returns
--         a NOP (0x00000013), which this CPU treats as "do nothing".
--   * Each instruction completes in ONE clock cycle: all combinational logic
--     settles during the cycle, and PC / registers / data memory are updated
--     together at the next rising edge.
--
-- DEBUG OUTPUTS (all are COMBINATIONAL views of the instruction CURRENTLY at
-- the PC, i.e. the one that will complete at the NEXT rising edge; they do not
-- feed back into the CPU):
--   pc_out, instr_out, alu_result_out, reg_data1_out, reg_data2_out,
--   mem_data_out (data read from memory; 0 when no load), mem_read_out,
--   mem_write_out, branch_taken_out.
--   After the rising edge they show the NEXT instruction's values.
--   dbg_reg_addr/dbg_reg_data and dbg_mem_addr/dbg_mem_data are read-only
--   inspection ports (register file / data memory contents) for the testbench.
--------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity riscv_cpu is
  port (
    clk             : in  std_logic;
    reset           : in  std_logic;                       -- active-high, synchronous
    -- read-only inspection ports
    dbg_reg_addr    : in  std_logic_vector(4 downto 0)  := (others => '0');
    dbg_reg_data    : out std_logic_vector(31 downto 0);
    dbg_mem_addr    : in  std_logic_vector(31 downto 0) := (others => '0'); -- byte address
    dbg_mem_data    : out std_logic_vector(31 downto 0);
    -- combinational debug outputs
    pc_out          : out std_logic_vector(31 downto 0);
    instr_out       : out std_logic_vector(31 downto 0);
    alu_result_out  : out std_logic_vector(31 downto 0);
    reg_data1_out   : out std_logic_vector(31 downto 0);
    reg_data2_out   : out std_logic_vector(31 downto 0);
    mem_data_out    : out std_logic_vector(31 downto 0);
    mem_read_out    : out std_logic;
    mem_write_out   : out std_logic;
    branch_taken_out: out std_logic
  );
end entity riscv_cpu;

architecture rtl of riscv_cpu is

  subtype word_t is std_logic_vector(31 downto 0);
  type reg_array_t is array (0 to 31) of word_t;
  type imem_t      is array (0 to 15) of word_t;
  type dmem_t      is array (0 to 63) of word_t;

  -- Opcodes / function codes (official RV32I)
  constant OPC_RTYPE  : std_logic_vector(6 downto 0) := "0110011";
  constant OPC_LOAD   : std_logic_vector(6 downto 0) := "0000011";
  constant OPC_STORE  : std_logic_vector(6 downto 0) := "0100011";
  constant OPC_BRANCH : std_logic_vector(6 downto 0) := "1100011";
  constant F3_ADD     : std_logic_vector(2 downto 0) := "000";
  constant F7_ADD     : std_logic_vector(6 downto 0) := "0000000";
  constant F3_LW      : std_logic_vector(2 downto 0) := "010";
  constant F3_SW      : std_logic_vector(2 downto 0) := "010";
  constant F3_BEQ     : std_logic_vector(2 downto 0) := "000";
  constant NOP        : word_t := x"00000013";   -- ADDI x0,x0,0 (not decoded -> no effect)

  ------------------------------------------------------------------------------
  -- Encoder functions: the demo program is built from these field-by-field
  -- (not typed as raw hex) so that the encodings follow the RV32I spec layout.
  ------------------------------------------------------------------------------
  function reg5(n : natural) return std_logic_vector is
  begin
    return std_logic_vector(to_unsigned(n, 5));
  end function;

  -- R-type: funct7 | rs2 | rs1 | funct3 | rd | opcode
  function enc_r(f7 : std_logic_vector(6 downto 0); rs2, rs1 : natural;
                 f3 : std_logic_vector(2 downto 0); rd : natural;
                 op : std_logic_vector(6 downto 0)) return word_t is
  begin
    return f7 & reg5(rs2) & reg5(rs1) & f3 & reg5(rd) & op;
  end function;

  -- I-type: imm[11:0] | rs1 | funct3 | rd | opcode
  function enc_i(imm : integer; rs1 : natural; f3 : std_logic_vector(2 downto 0);
                 rd : natural; op : std_logic_vector(6 downto 0)) return word_t is
    variable i12 : std_logic_vector(11 downto 0);
  begin
    i12 := std_logic_vector(to_signed(imm, 12));
    return i12 & reg5(rs1) & f3 & reg5(rd) & op;
  end function;

  -- S-type: imm[11:5] | rs2 | rs1 | funct3 | imm[4:0] | opcode
  function enc_s(imm : integer; rs2, rs1 : natural;
                 f3 : std_logic_vector(2 downto 0);
                 op : std_logic_vector(6 downto 0)) return word_t is
    variable i12 : std_logic_vector(11 downto 0);
  begin
    i12 := std_logic_vector(to_signed(imm, 12));
    return i12(11 downto 5) & reg5(rs2) & reg5(rs1) & f3 & i12(4 downto 0) & op;
  end function;

  -- B-type: imm[12] | imm[10:5] | rs2 | rs1 | funct3 | imm[4:1] | imm[11] | opcode
  function enc_b(imm : integer; rs2, rs1 : natural;
                 f3 : std_logic_vector(2 downto 0);
                 op : std_logic_vector(6 downto 0)) return word_t is
    variable i13 : std_logic_vector(12 downto 0);
  begin
    i13 := std_logic_vector(to_signed(imm, 13));
    return i13(12) & i13(10 downto 5) & reg5(rs2) & reg5(rs1) & f3 &
           i13(4 downto 1) & i13(11) & op;
  end function;

  ------------------------------------------------------------------------------
  -- Instruction memory (ROM) holding the demonstration program
  ------------------------------------------------------------------------------
  constant IMEM : imem_t := (
    0 => enc_r(F7_ADD, 2, 1, F3_ADD, 3, OPC_RTYPE),   --  0: ADD x3,x1,x2
    1 => enc_s(0, 3, 4, F3_SW, OPC_STORE),            --  4: SW  x3,0(x4)
    2 => enc_i(0, 4, F3_LW, 5, OPC_LOAD),             --  8: LW  x5,0(x4)
    3 => enc_b(8, 5, 3, F3_BEQ, OPC_BRANCH),          -- 12: BEQ x3,x5,+8  (target 20)
    4 => enc_r(F7_ADD, 1, 1, F3_ADD, 6, OPC_RTYPE),   -- 16: ADD x6,x1,x1  (must be skipped)
    5 => enc_r(F7_ADD, 2, 1, F3_ADD, 7, OPC_RTYPE),   -- 20: ADD x7,x1,x2
    others => NOP);

  constant INIT_REGS : reg_array_t :=
    (1 => x"0000000A", 2 => x"00000014", 4 => x"00000064",
     others => (others => '0'));

  -- State (updated only on the rising clock edge)
  signal pc   : word_t     := (others => '0');
  signal regs : reg_array_t := INIT_REGS;
  signal dmem : dmem_t      := (others => (others => '0'));

  -- Fetch
  signal imem_ok : std_logic;
  signal instr   : word_t;

  -- Decode fields
  signal opcode  : std_logic_vector(6 downto 0);
  signal funct3  : std_logic_vector(2 downto 0);
  signal funct7  : std_logic_vector(6 downto 0);
  signal rs1_idx, rs2_idx, rd_idx : std_logic_vector(4 downto 0);

  -- Control signals
  signal is_add, is_lw, is_sw, is_beq : std_logic;
  signal reg_write, alu_src, mem_read, mem_write, mem_to_reg : std_logic;

  -- Datapath
  signal rd1, rd2        : word_t;
  signal imm_i, imm_s, imm_b, imm : word_t;
  signal alu_b, alu_result : word_t;
  signal dmem_ok         : std_logic;
  signal dmem_idx        : natural range 0 to 63;
  signal mem_rdata       : word_t;
  signal wb_data         : word_t;
  signal branch_taken    : std_logic;
  signal pc_plus4, pc_branch, next_pc : word_t;

begin

  ------------------------------------------------------------------------------
  -- 1) INSTRUCTION MEMORY (fetch). Byte address -> word index PC[5:2].
  ------------------------------------------------------------------------------
  imem_ok <= '1' when (unsigned(pc(31 downto 6)) = 0) and (pc(1 downto 0) = "00")
             else '0';
  instr   <= IMEM(to_integer(unsigned(pc(5 downto 2)))) when imem_ok = '1' else NOP;

  ------------------------------------------------------------------------------
  -- 2) DECODER / CONTROL UNIT. Funct3/funct7 are checked, not just the opcode.
  ------------------------------------------------------------------------------
  opcode  <= instr(6 downto 0);
  rd_idx  <= instr(11 downto 7);
  funct3  <= instr(14 downto 12);
  rs1_idx <= instr(19 downto 15);
  rs2_idx <= instr(24 downto 20);
  funct7  <= instr(31 downto 25);

  is_add <= '1' when opcode = OPC_RTYPE  and funct3 = F3_ADD and funct7 = F7_ADD else '0';
  is_lw  <= '1' when opcode = OPC_LOAD   and funct3 = F3_LW  else '0';
  is_sw  <= '1' when opcode = OPC_STORE  and funct3 = F3_SW  else '0';
  is_beq <= '1' when opcode = OPC_BRANCH and funct3 = F3_BEQ else '0';

  reg_write  <= is_add or is_lw;      -- SW and BEQ never write a register
  alu_src    <= is_lw or is_sw;       -- 1: ALU operand B = immediate
  mem_read   <= is_lw;
  mem_write  <= is_sw;
  mem_to_reg <= is_lw;

  ------------------------------------------------------------------------------
  -- 3) REGISTER FILE (2 combinational read ports; x0 always reads 0)
  ------------------------------------------------------------------------------
  rd1 <= (others => '0') when rs1_idx = "00000" else regs(to_integer(unsigned(rs1_idx)));
  rd2 <= (others => '0') when rs2_idx = "00000" else regs(to_integer(unsigned(rs2_idx)));

  ------------------------------------------------------------------------------
  -- 4) IMMEDIATE GENERATOR (all sign-extended to 32 bits)
  ------------------------------------------------------------------------------
  imm_i <= std_logic_vector(resize(signed(instr(31 downto 20)), 32));
  imm_s <= std_logic_vector(resize(signed(instr(31 downto 25) & instr(11 downto 7)), 32));
  -- B-type: imm[12|10:5|4:1|11] with implicit 0 as bit 0 -> 13-bit value
  imm_b <= std_logic_vector(resize(signed(instr(31) & instr(7) & instr(30 downto 25) &
                                          instr(11 downto 8) & '0'), 32));
  imm   <= imm_i when is_lw = '1' else
           imm_s when is_sw = '1' else
           imm_b when is_beq = '1' else
           (others => '0');

  ------------------------------------------------------------------------------
  -- 5) ALU (this subset only needs addition: ADD, and address = rs1 + imm)
  ------------------------------------------------------------------------------
  alu_b      <= imm when alu_src = '1' else rd2;
  alu_result <= std_logic_vector(unsigned(rd1) + unsigned(alu_b));  -- 32-bit wrap-around

  ------------------------------------------------------------------------------
  -- 6) DATA MEMORY (word-oriented, byte addresses, combinational read)
  ------------------------------------------------------------------------------
  dmem_ok   <= '1' when (alu_result(31 downto 8) = x"000000") and (alu_result(1 downto 0) = "00")
               else '0';
  dmem_idx  <= to_integer(unsigned(alu_result(7 downto 2)));
  mem_rdata <= dmem(dmem_idx) when (mem_read = '1' and dmem_ok = '1') else (others => '0');

  ------------------------------------------------------------------------------
  -- 7) WRITE-BACK
  ------------------------------------------------------------------------------
  wb_data <= mem_rdata when mem_to_reg = '1' else alu_result;

  ------------------------------------------------------------------------------
  -- 8) BRANCH DECISION + 9) NEXT-PC SELECTION
  ------------------------------------------------------------------------------
  branch_taken <= '1' when (is_beq = '1' and rd1 = rd2) else '0';
  pc_plus4     <= std_logic_vector(unsigned(pc) + 4);
  pc_branch    <= std_logic_vector(unsigned(pc) + unsigned(imm_b));
  next_pc      <= pc_branch when branch_taken = '1' else pc_plus4;

  ------------------------------------------------------------------------------
  -- 10) STATE UPDATE: PC, register file write, data memory write.
  --     Synchronous active-high reset.
  ------------------------------------------------------------------------------
  state_update : process (clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        pc   <= (others => '0');
        regs <= INIT_REGS;
        dmem <= (others => (others => '0'));
      else
        pc <= next_pc;
        if reg_write = '1' and rd_idx /= "00000" then   -- never write x0
          regs(to_integer(unsigned(rd_idx))) <= wb_data;
        end if;
        if mem_write = '1' and dmem_ok = '1' then
          dmem(dmem_idx) <= rd2;
        end if;
      end if;
    end if;
  end process state_update;

  ------------------------------------------------------------------------------
  -- Debug / observation outputs (read-only; nothing feeds back)
  ------------------------------------------------------------------------------
  pc_out           <= pc;
  instr_out        <= instr;
  alu_result_out   <= alu_result;
  reg_data1_out    <= rd1;
  reg_data2_out    <= rd2;
  mem_data_out     <= mem_rdata;
  mem_read_out     <= mem_read;
  mem_write_out    <= mem_write;
  branch_taken_out <= branch_taken;

  dbg_reg_data <= regs(to_integer(unsigned(dbg_reg_addr)));
  dbg_mem_data <= dmem(to_integer(unsigned(dbg_mem_addr(7 downto 2))))
                  when dbg_mem_addr(31 downto 8) = x"000000" else (others => '0');

end architecture rtl;
