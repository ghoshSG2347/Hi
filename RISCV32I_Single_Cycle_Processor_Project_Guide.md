# Single-Cycle RISC-V (RV32I) Processor Using VHDL

## Assignment Guide, Development Plan, Simulation and Demonstration Instructions

**Project type:** Individual project  
**Hardware description language:** VHDL  
**Target architecture:** 32-bit RISC-V (RV32I)  
**Recommended development environment:** Visual Studio Code on Linux  
**Simulator:** GHDL  
**Waveform viewer:** GTKWave  
**Report format stated by teacher:** Handwritten report on A4 sheets  

> **Important:** This document translates the instructions visible in the class WhatsApp conversation into a practical development plan. It is not an official specification issued by the teacher. The exact instruction-set scope, report format, submission date and demonstration rules still need to be confirmed with the teacher.

---

## 1. What has the teacher assigned?

The assignment is to **design and implement a working 32-bit, single-cycle RISC-V processor using VHDL**. The processor must be able to fetch, decode and execute basic assembly instructions. The examples specifically mentioned in the class message are:

- `ADD` — add the values in two registers.
- `LW` — load a 32-bit word from data memory into a register.
- `SW` — store a 32-bit word from a register into data memory.
- `BEQ` — branch to a target instruction when two register values are equal.

The teacher's messages also establish these submission expectations:

1. It is an **individual project**.
2. It is to be submitted after the Puja holidays (the exact date was not stated in the screenshot).
3. A working `.vhd` file or set of VHDL files is required.
4. The student must be able to show the project in working condition.
5. A project report must also be written on A4 sheets.

The phrase “such as ADD, LW, SW, BEQ” may mean that these are examples rather than the complete required instruction list. This guide therefore proposes a manageable initial instruction subset, but the final scope must be checked with the teacher.

## 2. What does “single-cycle RISC-V processor” mean?

### 2.1 CPU in simple terms

A processor executes instructions stored in memory. For each instruction, a CPU normally performs these logical tasks:

1. **Fetch:** Read the instruction from instruction memory using the Program Counter (PC).
2. **Decode:** Determine which instruction it is and identify its source and destination registers or immediate value.
3. **Execute:** Perform an arithmetic operation, calculate a memory address, or compare values.
4. **Memory access:** Read from or write to data memory when the instruction requires it.
5. **Write-back:** Write the result into a destination register when required.
6. **Update the PC:** Select the next instruction address.

In a **single-cycle** design, the whole operation for one instruction is completed within one clock cycle. The instruction does not take several separate clock cycles to pass through fetch, decode, execute and write-back stages. The combinational datapath performs the work during the cycle, and clocked state elements update at the active clock edge.

### 2.2 What is RISC-V RV32I?

- **RISC-V** is an open instruction-set architecture (ISA). An ISA defines the instructions a processor understands and how those instructions are encoded.
- **RV32I** refers to the base integer instruction set using 32-bit registers and a 32-bit address/integer width.
- A register is a small, fast storage location inside the CPU.
- An instruction is represented in the processor's instruction memory as a 32-bit machine-code value. Assembly such as `ADD x3, x1, x2` is a human-readable representation of that value.

The assignment does not automatically mean that every instruction in the full RV32I specification must be implemented. We should implement exactly the subset the teacher expects.

### 2.3 What does “using VHDL” mean?

VHDL (VHSIC Hardware Description Language) describes digital hardware. We will write VHDL entities and architectures for parts of a processor, then connect those parts. A simulator will model the resulting digital circuit over time.

This is not an ordinary C/Python program that simply calculates an answer. We are describing hardware components, signals, clocked registers and how signals connect.

---

## 3. What are we going to create?

We will create a **simulation-ready CPU design**, consisting of multiple VHDL modules connected together as one processor.

### 3.1 Proposed first implementation scope

Until the teacher confirms the full requirement, use the following as the proposed minimum demonstrable subset:

| Instruction | Purpose | Main hardware action |
|---|---|---|
| `ADD rd, rs1, rs2` | Add two register values | ALU adds `rs1` and `rs2`; result is written to `rd` |
| `ADDI rd, rs1, imm` | Add a signed immediate value | ALU adds `rs1` and the sign-extended immediate |
| `LW rd, offset(rs1)` | Load a word from memory | ALU calculates address; data memory is read; value is written to `rd` |
| `SW rs2, offset(rs1)` | Store a word in memory | ALU calculates address; value from `rs2` is written to data memory |
| `BEQ rs1, rs2, label` | Branch if equal | Compare register values; update PC to branch target when equal |

**Why include `ADDI`?** A small test program needs a way to put useful values into registers. `ADDI` is a simple standard RV32I instruction that lets the test program initialize registers without relying on hidden preloaded values. If the teacher explicitly limits the design to four instructions, we will follow that instruction and initialize test registers in a documented test setup instead.

Optional instructions such as `SUB`, `AND`, `OR`, `SLT`, `BNE`, `JAL` and `JALR` should not be added until the required subset is clear and the basic processor works.

### 3.2 Main components of the processor

| Component | What it does | Why the CPU needs it |
|---|---|---|
| Program Counter (PC) | Holds the address of the current instruction | Tells instruction memory which instruction to provide |
| Instruction Memory | Stores the 32-bit machine-code instructions | Supplies instructions to the CPU |
| Instruction Decoder / Control Unit | Reads opcode and function fields and generates control signals | Tells the datapath which operation to perform |
| Register File | Holds 32 general-purpose 32-bit registers (`x0`–`x31`) | Supplies operands and receives register results |
| Immediate Generator | Extracts and sign-extends immediate bits from I-, S- or B-type instructions | Supplies constants, load/store offsets and branch offsets |
| ALU | Performs addition and comparison-related operations | Calculates results and memory addresses |
| Data Memory | Stores data that can be loaded or written by instructions | Supports `LW` and `SW` |
| Multiplexers (MUXes) | Select one input from multiple alternatives | Select ALU operands, write-back data and the next PC |
| Branch / PC Selection Logic | Decides between `PC + 4` and the branch target | Implements `BEQ` |
| Testbench | Applies clock/reset and checks the processor | Proves that the processor behaves as expected |

### 3.3 How the components connect

The simplified datapath will follow this flow:

```text
                      +------------------+
             PC ----->| Instruction      |
              |      | Memory           |
              |      +--------+---------+
              |               |
              |          32-bit instruction
              |               |
              |       +-------v--------+
              |       | Decoder /      |
              |       | Control Unit   |
              |       +-------+--------+
              |               |
              |      +--------+---------+
              |      |                  |
              |   rs1/rs2, rd       Immediate
              |      |               Generator
              |      v                  |
              |  +----------------+     |
              |  | Register File  |     |
              |  +-------+--------+     |
              |          |              |
              |          +-------+------+
              |                  |
              |             +----v----+
              |             |   ALU   |
              |             +----+----+
              |                  |
              |          effective address /
              |             ALU result
              |                  |
              |        +---------v---------+
              |        |    Data Memory    |
              |        +---------+---------+
              |                  |
              |          load data / ALU result
              |                  |
              |          +-------v-------+
              |          | Write-back    |
              |          | selection     |
              |          +-------+-------+
              |                  |
              |                  +-------> Register File
              |
              +---- PC + 4 / branch-target selection <--- BEQ decision
```

This is a conceptual diagram. The final VHDL design may have additional signals, control lines and multiplexers.

### 3.4 How each required instruction works

#### A. `ADD rd, rs1, rs2`

Example: `ADD x3, x1, x2`

1. The PC selects the instruction in instruction memory.
2. The decoder recognizes the R-type `ADD` instruction.
3. The register file provides the values stored in `x1` and `x2`.
4. The ALU adds the two values.
5. The result is written into `x3` at the clock edge.
6. The next PC is normally `PC + 4`.

#### B. `LW rd, offset(rs1)`

Example: `LW x5, 8(x1)`

1. The processor reads the base address from `x1`.
2. The immediate generator extracts and sign-extends the load offset.
3. The ALU calculates the effective address: `x1 + offset`.
4. Data memory returns the 32-bit word at that address.
5. The data is written into `x5`.
6. The PC normally advances to `PC + 4`.

#### C. `SW rs2, offset(rs1)`

Example: `SW x3, 8(x1)`

1. The processor reads the base address from `x1` and the data from `x3`.
2. The immediate generator reconstructs the S-type immediate.
3. The ALU calculates the effective address: `x1 + offset`.
4. Data memory stores the value from `x3` at that address on the appropriate clock edge.
5. No register is written by `SW`.
6. The PC normally advances to `PC + 4`.

#### D. `BEQ rs1, rs2, label`

Example: `BEQ x1, x2, target`

1. The register file supplies the values in `x1` and `x2`.
2. The processor compares the values.
3. If they are equal, the next PC is the branch target (`PC + branch immediate`).
4. If they are not equal, the next PC is `PC + 4`.
5. `BEQ` does not write a register or access data memory.

**Important:** Branch and load/store immediates have different bit layouts in the RISC-V instruction encoding. We must implement the correct I-, S- and B-type immediate extraction rather than treating every immediate as the same format.

---

## 4. Tools and where we will do the project

The main workspace will be **Visual Studio Code (VS Code)**. We will create and edit all `.vhd` source files inside VS Code and use its integrated terminal to compile and run simulations.

VS Code is an editor, not the VHDL simulator. The supporting tools have separate jobs:

| Tool | Role | Where it appears during work |
|---|---|---|
| Visual Studio Code | Write and organize VHDL, testbench, notes and report material | Main project window |
| GHDL | Analyze/compile, elaborate and run the VHDL design | VS Code integrated terminal |
| GTKWave | Display signal values over simulation time | Separate waveform window, launched from terminal |
| Git (optional) | Keep version history and recover earlier working code | VS Code source-control panel or terminal |

### 4.1 Why this toolchain?

- It is suitable for a small academic VHDL design.
- It can run locally on Linux without requiring FPGA hardware.
- It allows us to show compiler output and simulation results in VS Code.
- GTKWave makes internal CPU signals visible as timing waveforms.
- GHDL supports the usual analyze → elaborate → run flow, and can generate waveform files for viewing. See the technical references at the end of this document.

**No FPGA board is assumed.** The class message asks for a working project and a `.vhd` file, but does not mention a physical FPGA board. We will use simulation unless the teacher specifically requires hardware implementation.

### 4.2 Install the tools on Kali Linux / Debian-based Linux

Open a terminal and run:

```bash
sudo apt update
sudo apt install ghdl gtkwave
```

If VS Code is already installed, no need to reinstall it. If the `code` command is available, we can open the project folder using `code .`.

Check the tools:

```bash
ghdl --version
gtkwave --version
```

If either command is not found, check whether the package installation completed successfully and whether the executable is available in `PATH`.

> Package availability can depend on the Kali/Debian repository snapshot and architecture. If `apt` cannot find a package, check the configured repositories and package search before downloading random installers.

### 4.3 VS Code setup

1. Open VS Code.
2. Select **File → Open Folder**.
3. Open the project folder described below.
4. Use **Terminal → New Terminal** to open the integrated terminal.
5. Keep the Explorer panel visible so the VHDL files are easy to access.
6. A VHDL syntax-highlighting extension may be installed if desired, but it is optional. GHDL is still responsible for checking and simulating the code.

---

## 5. Project folder structure

Create one folder for the complete assignment. Suggested name:

```text
RV32I-Single-Cycle-Processor/
│
├── README.md
├── Makefile                     # Optional: shortcuts for common commands
│
├── src/                         # Actual processor implementation
│   ├── rv32i_pkg.vhd             # Shared constants/types (if needed)
│   ├── program_counter.vhd
│   ├── instruction_memory.vhd
│   ├── register_file.vhd
│   ├── immediate_generator.vhd
│   ├── alu.vhd
│   ├── control_unit.vhd
│   ├── data_memory.vhd
│   └── rv32i_cpu.vhd             # Top-level CPU that connects everything
│
├── tb/                          # Testbench files
│   └── tb_rv32i_cpu.vhd
│
├── programs/                    # Test program and instruction notes
│   ├── demo_program.asm
│   └── instruction_notes.md
│
├── build/                       # Generated simulation files (not hand-written)
│   └── cpu_tb.ghw
│
├── docs/                        # Design notes and report material
│   ├── datapath.md
│   └── report_outline.md
│
└── .gitignore                   # Optional: exclude generated build files
```

The exact source-file list may change as the design becomes clearer. For example, some small modules may be combined, and `rv32i_pkg.vhd` is needed only if we decide to share package definitions.

### 5.1 Meaning of the important files

- `alu.vhd`: arithmetic and comparison operations.
- `register_file.vhd`: the 32 registers and read/write behaviour.
- `immediate_generator.vhd`: extracts and extends instruction immediate values.
- `control_unit.vhd`: translates instruction fields into control signals.
- `instruction_memory.vhd`: contains the test program's machine-code instructions.
- `data_memory.vhd`: contains data used by `LW` and `SW`.
- `program_counter.vhd`: stores the address of the instruction being executed.
- `rv32i_cpu.vhd`: top-level design that connects the hardware blocks.
- `tb_rv32i_cpu.vhd`: testbench that generates a clock, applies reset, runs the CPU and checks results.

---

## 6. How development will happen in VS Code

We will build the design in stages. We should not start by writing one huge VHDL file containing everything. Small modules are easier to understand, test and debug.

### Stage 1 — Learn only the VHDL needed for this assignment

Understand these concepts before building the CPU:

| VHDL concept | Meaning |
|---|---|
| `library` / `use` | Make standard logic and numeric definitions available |
| `entity` | Defines a module's external ports |
| `architecture` | Describes the module's internal behaviour/structure |
| `signal` | Represents a connection or value inside the hardware model |
| `std_logic` | A single digital logic value |
| `std_logic_vector(31 downto 0)` | A 32-bit logic vector |
| `numeric_std` | Standard arithmetic types and operations such as `unsigned` and `signed` |
| `process` | Describes sequential or combinational behaviour |
| `rising_edge(clk)` | Detects the active rising clock edge |
| `port map` | Connects one module's ports to signals or other module ports |

Use `ieee.numeric_std.all` for normal numeric conversions and arithmetic. Avoid mixing non-standard arithmetic packages into the design.

### Stage 2 — Build and test the ALU

Start with the ALU because it is a small and visible component.

Initial operations:

- 32-bit addition for `ADD`, `ADDI`, `LW` address calculation and `SW` address calculation.
- Equality comparison for `BEQ` (this can be a dedicated comparator or an ALU subtraction/zero result).

Test the ALU separately with a small testbench before connecting it to the CPU.

### Stage 3 — Build the register file

The register file should contain 32 registers, each 32 bits wide.

Important RV32I rule: **`x0` always reads as zero.** A write to `x0` must not change its value. We should test this explicitly.

A typical simple register file has two combinational read ports (`rs1` and `rs2`) and one clocked write port (`rd`).

### Stage 4 — Build the immediate generator and control unit

The immediate generator will support the instruction formats needed by the selected subset:

- I-type: `ADDI`, `LW`
- S-type: `SW`
- B-type: `BEQ`

The control unit will decode the opcode and relevant function fields and generate signals such as:

- register write enable;
- memory write enable;
- memory read / load selection;
- ALU operand selection;
- ALU operation;
- write-back source selection;
- branch enable.

Unsupported opcodes should not silently execute as a valid instruction. They should be treated as unsupported/invalid in a clearly documented way.

### Stage 5 — Build memories and the Program Counter

For the first simulation, instruction memory and data memory can be small VHDL arrays initialized with a known test program and data values.

Keep the memory model simple and document its assumptions. For example:

- data memory stores 32-bit words;
- `LW` and `SW` use aligned 32-bit word accesses initially;
- effective addresses are byte addresses, as in RISC-V;
- the low address bits are used appropriately to select a word entry in the simplified memory model;
- misaligned accesses may be unsupported in the first version and should be documented.

The PC should normally advance by 4 bytes for the next 32-bit instruction. A taken `BEQ` selects the branch target instead.

### Stage 6 — Connect the top-level CPU

Connect all modules in `rv32i_cpu.vhd`. At this point the CPU should have:

- a clock input;
- a reset input;
- a PC register;
- instruction fetch and decode;
- register reads;
- ALU and memory address calculation;
- data memory access;
- register write-back;
- branch selection.

The top-level CPU is the design that the testbench will instantiate.

### Stage 7 — Write a testbench

A testbench is a VHDL simulation-only module. It is not part of the hardware that would be synthesized into a CPU. It creates the conditions needed to test the processor.

The testbench should:

1. Generate a repeating clock.
2. Apply reset for the required initial time.
3. Release reset.
4. Allow the CPU to execute the program for enough clock cycles.
5. Check expected register and memory results using assertions.
6. Stop the simulation after the checks complete.
7. Generate a waveform file for inspection.

The testbench should test both taken and not-taken branch outcomes. A branch test that checks only one condition is not sufficient to show both paths work.

---

## 7. How to compile and simulate inside VS Code

All commands below are entered in the **VS Code integrated terminal**, with the terminal's current directory set to the root project folder.

### 7.1 Open the project

```bash
cd path/to/RV32I-Single-Cycle-Processor
code .
```

If the folder is already open in VS Code, only open a new integrated terminal.

### 7.2 Create the output folder

```bash
mkdir -p build
```

### 7.3 Analyze the VHDL source files

GHDL's workflow has three main steps: analysis, elaboration and simulation. Analysis checks and reads the design units into the work library. The package, if present, must be analyzed before files that use it. Other dependencies must also be analyzed before the modules that instantiate them.

Example command (adjust the file list to match the files that actually exist):

```bash
ghdl -a --std=08 src/rv32i_pkg.vhd \
  src/alu.vhd \
  src/register_file.vhd \
  src/immediate_generator.vhd \
  src/control_unit.vhd \
  src/program_counter.vhd \
  src/instruction_memory.vhd \
  src/data_memory.vhd \
  src/rv32i_cpu.vhd \
  tb/tb_rv32i_cpu.vhd
```

If we do not create `rv32i_pkg.vhd`, remove it from the command. If the source dependency order changes, change the order accordingly.

A successful analysis should finish without VHDL errors. Warnings should be reviewed rather than automatically ignored.

### 7.4 Elaborate the testbench

```bash
ghdl -e --std=08 tb_rv32i_cpu
```

Elaboration checks the top-level simulation unit and prepares it to run. The entity name must match the entity declared in the testbench.

### 7.5 Run the simulation and generate a waveform

```bash
ghdl -r --std=08 tb_rv32i_cpu \
  --assert-level=error \
  --wave=build/cpu_tb.ghw
```

- `-r` runs the simulation.
- `--assert-level=error` makes assertion errors fail the run.
- `--wave=build/cpu_tb.ghw` writes the GHDL waveform file.

The testbench should print or report useful PASS messages and fail if an expected result is wrong. A simulation that merely runs without errors is not enough; the assertions must check meaningful CPU behaviour.

### 7.6 Open the waveform

```bash
gtkwave build/cpu_tb.ghw
```

GTKWave opens in a separate window. In its signal hierarchy, add useful signals to the waveform display. The exact hierarchical names depend on our VHDL entity and signal names.

Useful signals to inspect include:

- `clk` and `reset`;
- `pc` / current program counter;
- fetched instruction;
- decoded opcode and control signals;
- source register values;
- ALU operation and ALU result;
- effective memory address;
- data-memory write enable and write data;
- register write enable, destination register and write-back data;
- branch-taken decision and next PC.

### 7.7 How to understand the waveform

The horizontal axis represents simulation time. Each signal's value changes as the simulation progresses.

- The clock should repeatedly transition between 0 and 1.
- The PC should normally increase by 4 for each instruction.
- During a taken `BEQ`, the next PC should become the branch target instead of the sequential `PC + 4` value.
- During `ADD`, the ALU result should equal the sum of the two source register values, and the destination register should be written at the clock edge.
- During `LW`, the calculated memory address should be used to obtain the load value, and the destination register should receive that value.
- During `SW`, the memory write enable should be asserted and the value from the source register should be stored at the calculated address.

The waveform is supporting evidence. It should agree with the testbench assertions and the values printed in the simulation log.

### 7.8 Important VS Code clarification

The normal workflow is:

- Write/edit VHDL in VS Code.
- Compile and simulate using GHDL from VS Code's integrated terminal.
- Open the generated `.ghw` file in GTKWave, which appears as a separate application window.

The waveform is not automatically embedded inside the VS Code editor. This is still a valid and straightforward VS Code-based demonstration: the code, terminal output and waveform can all be shown during the same presentation.

---

## 8. What exactly should we demonstrate to the teacher?

The goal is to prove that the implemented CPU executes the required instructions correctly, not merely that the VHDL files exist.

### 8.1 Recommended demonstration sequence

1. **Show the project folder in VS Code.** Briefly explain that `src/` contains processor modules and `tb/` contains the testbench.
2. **Show the top-level CPU file.** Point out how the PC, instruction memory, control unit, register file, ALU and data memory are connected.
3. **Show one or two component files.** For example, show the ALU and control unit. Do not read every line of every file aloud.
4. **Open the integrated terminal.** Show the GHDL analysis, elaboration and simulation commands.
5. **Run the testbench.** Show the PASS messages and demonstrate that no assertion failed.
6. **Open the GTKWave waveform.** Show the clock, PC, instruction, ALU result, memory controls and register write-back signals.
7. **Explain instruction execution.** Select one example each for `ADD`, `LW`, `SW` and `BEQ` and explain the relevant signal changes.
8. **Show a final result.** Explain the expected register/memory values and how the testbench verified them.
9. **Show the A4 report.** The report should describe the same design and results that are actually present in the code.

### 8.2 Example of what a successful test should prove

Use a small, documented program whose expected outcomes are known in advance. For instance, the test can:

- place two known values in registers (using `ADDI` if included, or a documented test initialization method);
- execute `ADD` and verify the sum in the destination register;
- execute `SW` and verify the value appears in the selected data-memory word;
- execute `LW` and verify that the value is copied back into a register;
- execute one `BEQ` where the operands are equal and confirm that the branch is taken;
- execute another `BEQ` where the operands differ and confirm that execution continues sequentially.

Do not claim specific final register values until the actual test program and machine-code encodings have been implemented and verified.

### 8.3 Evidence to save for the report

Keep screenshots of:

- the VS Code project structure;
- the top-level CPU VHDL code;
- successful GHDL analysis/elaboration/simulation output;
- GTKWave with useful signals visible;
- the simulation log showing test assertions or PASS messages.

Screenshots should come from the actual working implementation, not from diagrams or examples copied from the internet.

---

## 9. How the handwritten A4 report should be organized

The teacher said the report must be written on A4 sheets, but no specific template or page count is visible in the class message. The following is a suggested academic report structure. Confirm the required page count, cover-page format and whether printed screenshots are allowed.

### Suggested report sections

1. **Cover Page**
   - Project title: *Design and Simulation of a 32-bit Single-Cycle RISC-V Processor Using VHDL*.
   - Student name, roll number, registration number, department, semester and college.
   - Subject name, teacher's name and submission date (as required by college).

2. **Abstract**
   - A short summary of what the processor does, which instructions are implemented and how it was tested.

3. **Introduction**
   - What a processor is.
   - What RISC-V and RV32I mean.
   - What VHDL is.
   - What single-cycle execution means.

4. **Objectives**
   - Design a 32-bit processor datapath.
   - Implement the agreed RV32I instruction subset.
   - Simulate the design and verify instruction execution.

5. **Software and Tools Used**
   - VS Code, VHDL, GHDL and GTKWave.
   - Mention the operating system used.

6. **Processor Architecture / Block Diagram**
   - Draw and label PC, instruction memory, control unit, register file, immediate generator, ALU, data memory, multiplexers and branch logic.
   - Explain the connection between the blocks.

7. **Description of Components**
   - Explain each VHDL module and its responsibility.

8. **Instruction Set Implemented**
   - List every supported instruction, its format and its operation.
   - Include only instructions that the final design actually supports.

9. **Working Principle / Instruction Execution**
   - Explain fetch, decode, execute, memory access, write-back and PC update.
   - Explain ADD, LW, SW and BEQ individually.

10. **VHDL Implementation**
    - Describe the important modules and how they are connected.
    - Include short, relevant code excerpts only if required. Do not fill the report with every source-code line unless the teacher asks for that.

11. **Simulation and Testing**
    - Describe the testbench, sample program and test cases.
    - Include actual terminal output and waveform screenshots if permitted.

12. **Results and Discussion**
    - State which test cases passed.
    - Explain what the waveform demonstrates.
    - Mention limitations honestly (for example, only a subset of RV32I or only aligned word accesses).

13. **Conclusion**
    - Summarize what was successfully designed and tested.

14. **Future Scope**
    - Mention possible extensions such as additional RV32I instructions, byte/halfword memory operations, exceptions, or FPGA implementation. These are future work, not completed features.

15. **References**
    - Cite the RISC-V specification, VHDL/GHDL documentation and GTKWave documentation used.

### Report-writing rule

The report must match the final working source code. If an instruction is not implemented or tested, do not write that it is fully supported. If a feature is simplified, explain the simplification.

---

## 10. Testing checklist

Use this checklist before calling the processor complete.

### Basic toolchain

- [ ] VS Code opens the project folder correctly.
- [ ] `ghdl --version` works.
- [ ] `gtkwave --version` works.
- [ ] All VHDL source files analyze without errors.
- [ ] The testbench elaborates successfully.
- [ ] The simulation completes and generates a waveform file.

### Component tests

- [ ] ALU addition gives correct 32-bit results.
- [ ] Register file reads the expected values.
- [ ] Register `x0` always reads as zero.
- [ ] Writes to `x0` are ignored.
- [ ] I-type immediate is sign-extended correctly.
- [ ] S-type immediate is reconstructed correctly.
- [ ] B-type immediate is reconstructed correctly.
- [ ] Data memory stores and returns the expected word.
- [ ] PC normally increments by 4.

### CPU instruction tests

- [ ] `ADD` writes the correct result to `rd`.
- [ ] `LW` reads the correct data-memory word and writes it to `rd`.
- [ ] `SW` writes the correct register value to data memory.
- [ ] `BEQ` takes the branch when the operands are equal.
- [ ] `BEQ` does not take the branch when the operands are not equal.
- [ ] Instructions that should not write a register do not accidentally write one.
- [ ] Instructions that should not write memory do not accidentally write memory.
- [ ] The final testbench assertions pass.

### Submission readiness

- [ ] The `.vhd` source files are present and organized.
- [ ] The testbench is included.
- [ ] The exact supported instruction subset is documented.
- [ ] The project runs from a clean terminal using documented commands.
- [ ] A waveform file can be generated and opened.
- [ ] Demonstration screenshots have been saved.
- [ ] The handwritten A4 report matches the final implementation.
- [ ] The final submission copy contains the required files and does not rely on temporary files from another folder.

---

## 11. Common mistakes to avoid

1. **Confusing VS Code with a simulator.** VS Code edits files; GHDL performs VHDL analysis and simulation.
2. **Assuming that a successful compile proves the CPU works.** Compilation checks syntax and design consistency. The testbench must also check behaviour.
3. **Writing assembly text directly into instruction memory.** A processor fetches encoded machine instructions, not strings such as `ADD x1, x2, x3`.
4. **Ignoring instruction formats.** I-, S- and B-type immediates have different bit arrangements.
5. **Allowing `x0` to change.** RISC-V register `x0` is hardwired to zero.
6. **Updating the PC incorrectly.** Normal sequential execution advances by 4 bytes; a taken branch selects its target.
7. **Mixing up byte addresses and word-array indexes.** Document how the simplified data-memory model converts addresses into word entries.
8. **Using incomplete tests.** Test both taken and not-taken branches, loads, stores and register write-back.
9. **Making report claims that the code does not support.** The report must describe the actual implementation.
10. **Trying to implement the whole RV32I ISA immediately.** Confirm the required scope and complete a correct subset before adding optional instructions.

---

## 12. Questions to confirm with the teacher

These questions affect the design, amount of work and final report. Ask them before the architecture is finalized.

1. Is the required implementation limited to `ADD`, `LW`, `SW` and `BEQ`, or are these only examples of a larger required subset?
2. Is `ADDI` allowed/expected so that the test program can initialize registers?
3. Does “RV32I processor” mean the complete RV32I base integer ISA, or a selected subset sufficient to demonstrate the listed instructions?
4. Is simulation using GHDL/GTKWave acceptable, or is a specific simulator such as Vivado/ModelSim required?
5. Is an FPGA board implementation required, or is a working simulation demonstration sufficient?
6. Is there a prescribed A4 report format or page count? Are printed block diagrams, code excerpts and screenshots permitted?
7. What is the exact submission date after the Puja holidays, and should the `.vhd` files be submitted digitally as well as demonstrated?

Until those answers are available, the safest plan is to build a clean simulation-based processor for the listed core instructions, with `ADDI` as a practical test-program helper, and keep the design modular so the instruction set can be extended if required.

---

## 13. Final deliverable checklist

The final project folder should contain at least:

- [ ] All VHDL source files (`.vhd`).
- [ ] The top-level CPU entity.
- [ ] The testbench (`tb_rv32i_cpu.vhd`).
- [ ] A sample test program and a note explaining its expected behaviour.
- [ ] A short `README.md` with setup and run commands.
- [ ] A generated waveform file or instructions to regenerate it.
- [ ] Actual simulation evidence/screenshots.
- [ ] The handwritten A4 project report.

**Definition of done:** Another person should be able to open the project folder, follow the README, run GHDL from the terminal, see the testbench pass, open the waveform in GTKWave, and understand from the report which instructions the CPU implements and how they were verified.

---

## 14. Technical references

Use official documentation and specifications as technical references. These links are for implementation guidance; the teacher's assignment instructions take priority.

1. **RISC-V Unprivileged ISA Specification** — instruction formats and RV32I instruction definitions:  
   https://docs.riscv.org/reference/isa/unpriv/unpriv-index.html
2. **GHDL Documentation — Quick Start / Simulation** — analysis, elaboration, simulation and waveform generation:  
   https://ghdl.github.io/ghdl/quick_start/simulation/index.html
3. **GHDL Documentation — Simulation Options** — waveform output options such as `--wave` and `--vcd`:  
   https://ghdl.github.io/ghdl/using/Simulation.html
4. **GTKWave Documentation** — viewing and inspecting simulation waveform files:  
   https://gtkwave.github.io/gtkwave/
5. **GTKWave command reference** — supported dump formats and launching GTKWave with a waveform file:  
   https://gtkwave.github.io/gtkwave/man/gtkwave.1.html
6. **Debian GHDL package information** — GHDL is a VHDL compiler/simulator:  
   https://packages.debian.org/stable/electronics/ghdl
7. **Debian GTKWave package information:**  
   https://packages.debian.org/stable/electronics/gtkwave

---

**Document status:** Planning and implementation guide. The VHDL source code and testbench are to be developed and verified as separate project files; this document does not claim that a working CPU has already been implemented.
