# Advaita-V_Core (RV32I Single-Cycle RISC-V Processor Core)

This repository presents a synthesizable and functionally validated RISC-V core based on the **RV32I base integer instruction set architecture**, supporting all standard instruction formats: **R, I, S, B, U, and J**. The core is architected using a **single-cycle control flow**, and is built to enable self-contained simulation with integrated instruction and data memory modules. Its modular RTL design promotes ease of validation, debug, and future extensibility—making it suitable for hardware architecture research, education, and SoC integration.

---

##  Microarchitectural Execution Flow

Although the core operates within a single-cycle framework, the internal datapath is logically structured into five conceptual phases, following classical RISC-V execution semantics. This organization enhances design clarity and lays the groundwork for future pipeline extension, if desired.

### 1. **Instruction Fetch**
The control unit generates the next program counter (PC) based on sequential or control-transfer logic. The instruction is retrieved from instruction memory using this PC. Branch and jump target selection is resolved dynamically using immediate offset calculation and condition evaluation.

### 2. **Instruction Decode**
The fetched instruction is decoded to extract operand registers, operation type, and immediate values. The register file provides source operand values. The control unit generates all required control signals, and the immediate generator reconstructs 32-bit signed immediates for supported instruction formats.

### 3. **Execution**
This phase performs arithmetic, logical, and comparison operations via the ALU. Operand selection (register or immediate) is handled through a datapath multiplexer. For branch and jump instructions, the effective target address is computed, and the branch condition is evaluated based on ALU flags.

### 4. **Writeback**
The final result—either an ALU output, computed address, or memory-returned value—is selected through a prioritized multiplexer and written back to the destination register. This stage ensures correct update of architectural state for instructions producing a result.

---
## Project Structure

The repository is organized into functional directories to separate the hardware design, verification environment, and architectural documentation.

```text
Advaita-V_Core/
├── RTL/                  # Linted schematics & block diagrams
│   ├── Core.pdf          # Full processor core schematic
│   ├── IF_Stage.pdf      # Instruction Fetch stage diagram
│   ├── ID_Stage.pdf      # Instruction Decode stage diagram
│   ├── Ex_Stage.pdf      # Execution stage diagram
│   ├── WB_Stage.pdf      # Write-back stage diagram
│   └── Top_Module.pdf    # Core + Memory integration diagram
├── Source/               # SystemVerilog design files
│   ├── id_stage.sv       # Instruction Decode logic
│   ├── execution.sv      # ALU and execution control
│   ├── alu.sv            # Arithmetic Logic Unit
│   ├── reg_file.sv       # 32-bit Integer Register File
│   ├── control_gen.sv    # Main Control Unit logic
│   ├── imm_generator.sv  # Immediate value sign-extension
│   ├── data_mem.sv       # Data Memory module
│   ├── instruction_mem.sv # Instruction Memory module
│   └── ...               # (additional sub-modules & muxes)
├── Test_bench/           # Verification environment
│   ├── *_tb.sv           # Individual unit testbenches
│   ├── single_cycle_riscV_tb.sv # Full-core testbench
│   ├── instructions.hex  # Hex code for instruction memory initialization
│   └── data.hex          # Hex code for data memory initialization
└── RISCV_CARD.pdf        # RV32I Instruction Set Reference Card
```
---
##  Core Integration & Testability

The top-level module integrates the processor core with instruction and data memory blocks to create a self-contained simulation environment. The memory modules are external to the core and interact via standard interface signals. Testbenches are provided to evaluate instruction sequences, monitor control behavior, and validate data flow correctness. Outputs are easily observable through key register file reads and result ports.

Refer to: [Top_Module.pdf](https://github.com/snmcgs03/Single_cycle_RISC-V/raw/main/RTL/Top_Module.pdf)


---

##  Supported RV32I Instruction Formats

- **R-Type**: `ADD`, `SUB`, `AND`, `OR`, `XOR`, `SLL`, `SRL`, `SRA`, `SLT`, `SLTU`
- **I-Type**: `ADDI`, `ANDI`, `ORI`, `XORI`, `SLLI`, `SRLI`, `SRAI`,`SLTI`,`SLTIU`, `LW`,`LH`,`LB`,`LHU`,`LBU`, `JALR`
- **S-Type**: `SW`,`SH`,`SB`
- **B-Type**: `BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU`
- **U-Type**: `LUI`, `AUIPC`
- **J-Type**: `JAL`

All instructions are supported at the ISA level with correct control, datapath routing, and state updates.

---

## Development Objectives

- Maintain structural clarity across the RTL hierarchy
- Adhere strictly to RV32I ISA semantics
- Enable waveform-driven debug with modular testbenches
- Provide a baseline for pipelined and extended designs (e.g., M-extension, CSR)

---

##  Documentation Artifacts

- [IF_Stage.pdf](https://github.com/snmcgs03/Single_cycle_RISC-V/raw/main/RTL/IF_Stage.pdf)
- [ID_Stage.pdf](https://github.com/snmcgs03/Single_cycle_RISC-V/raw/main/RTL/ID_Stage.pdf)
- [Ex_Stage.pdf](https://github.com/snmcgs03/Single_cycle_RISC-V/raw/main/RTL/Ex_Stage.pdf)
- [WB_Stage.pdf](https://github.com/snmcgs03/Single_cycle_RISC-V/raw/main/RTL/WB_Stage.pdf)
- [Core.pdf](https://github.com/snmcgs03/Single_cycle_RISC-V/raw/main/RTL/Core.pdf)
- [Top_Module.pdf](https://github.com/snmcgs03/Single_cycle_RISC-V/raw/main/RTL/Top_Module.pdf)


These documents capture structural schematics and signal flow across individual modules.

---
## License
This project is licensed under the [Apache License 2.0](LICENSE).  
You are free to use, modify, and distribute this work with proper attribution.


