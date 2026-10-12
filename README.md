# AlphaTitan SoC

### Microcontroller Design, Lab: HaDes-V (Adapted Work)

![image](https://www.scheipel.com/wp-content/uploads/2024/12/hades_logo.svg)

This repository is based on the **HaDes-V Open Educational Resource (OER)** developed by **Tobias Scheipel**, David Beikircher, and Florian Riedl from the Embedded Architectures & Systems Group at **Graz University of Technology**.

We gratefully acknowledge and credit the original authors for making this resource publicly available under an open license. Their work provides a structured and highly effective foundation for learning processor design, and it has significantly contributed to our development process.

> This repository contains adaptations and extensions built upon the original HaDes-V framework for educational and research purposes.

---

**Alpha Titan** is a quad-core RISC-V System-on-Chip (SoC) developed at **Alpha Science Lab, Mymensingh Engineering College**. The project builds upon **Hadi-V**, an in-house-developed RISC-V processor core, and explores multicore system organization inspired by the microarchitecture and system-level design philosophy of **OpenTitan**.

Alpha Titan extends the single-core Hadi-V processor into a four-core system, providing a platform for exploring multicore processor integration, shared system resources, interconnect design, and scalable hardware architectures.

This repository contains adaptations and extensions of Hadi-V for educational and research purposes.

---

## About AlphaTitan SoC

**AlphaTitan** is a quad-core RISC-V SoC built around four instances of the Hadi-V processor core. The project draws architectural inspiration from OpenTitan, particularly its approach to organizing processor-centric systems and integrating hardware components into a cohesive SoC.

While Hadi-V provides the single-core processing foundation, AlphaTitan focuses on extending that foundation into a multicore system.

The project aims to develop practical experience in multicore architecture, hardware integration, and SoC design while contributing to the growth of indigenous deep-technology capabilities in Bangladesh.

### Project Lineage

- **HaDes-V:** The original open educational resource developed by researchers at Graz University of Technology.
- **Hadi-V:** An in-house-developed, five-stage, single-core RISC-V processor derived from the HaDes-V educational framework.
- **AlphaTitan:** A quad-core RISC-V SoC built upon Hadi-V, with system-level architectural inspiration from OpenTitan.

---

## Core and System Specifications

### Processor Core — Hadi-V

- RV32IM with Zicsr support
- Machine-mode support
- Five-stage scalar pipeline
- Dynamic branch prediction
- Modular and extensible RTL design

### SoC — AlphaTitan

- Four Hadi-V processor cores
- RISC-V-based multicore architecture
- System-level design inspired by OpenTitan
- Integration of multiple processor cores into a unified SoC
- A platform for investigating multicore execution and shared hardware resources

*Note: Shared memory organization, interconnect topology, cache coherence, interrupt distribution, and synchronization mechanisms depend on the implemented SoC design. These features should be documented as they are implemented and verified.*

---

## Development Status

- **Processor Core:** Hadi-V's initial design phase completed.
- **Core Verification:** Hadi-V functionally verified using the verification platform provided by Graz University of Technology.
- **FPGA Deployment:** Hadi-V successfully deployed on the Tang Nano9K FPGA board.
- **Multicore SoC:** Alpha Titan builds upon the Hadi-V core to develop a four-core system. SoC-level verification and FPGA deployment status should be updated as development progresses.

---

## Design Philosophy

Alpha Titan represents an effort to move beyond standalone processor design toward complete system-on-chip engineering.

The project explores the challenges involved in integrating multiple processor cores into a unified system, including:

- Multicore system organization and processor integration
- Instruction and data memory connectivity
- Interconnect and shared-resource design
- Concurrent program execution across multiple cores
- Hardware verification and system-level debugging
- FPGA-based prototyping and hardware realization

Inspired by OpenTitan's system-level architectural approach, Alpha Titan serves as an educational and research platform for understanding how processor cores become part of a larger computing system.

Our broader objective is to strengthen local expertise in processor architecture, VLSI, and SoC design, contributing to the development of Bangladesh's indigenous semiconductor and deep-technology ecosystem.

---

## Getting Started

This section describes the basic workflow for setting up the development environment, running simulations, and synthesizing the design. The commands below reflect the inherited Hadi-V build flow; Alpha Titan's multicore targets may require additional configuration.

### 1. Prerequisites

Ensure the following tools are installed:

- **Verilator** — RTL simulation
- **GTKWave** — waveform inspection and debugging
- **Xilinx Vivado** — synthesis and FPGA deployment
- **RISC-V GNU Toolchain** — compiling RISC-V assembly and C programs
- **GNU Make** — build orchestration

Ensure that the toolchain and FPGA tool paths in the relevant Makefiles match your local installation.

### 2. Clone the Repository

```bash
git clone <your-repo-url>
cd <repo-name>
```

### 3. Run an Assembly Test

```bash
make test/asm/<test_name>
```

### 4. Run a C Test

```bash
make test/c/<test_name>
```

These targets compile the program, generate memory initialization files, and run the simulation using Verilator.

Check the repository's test configuration to determine whether a given test targets a single Hadi-V core or the complete Alpha Titan SoC.

### 5. View Waveforms

After running a test:

```bash
make show
```

This opens the generated waveform in GTKWave, allowing you to inspect processor activity and debug RTL behavior.

### 6. Run SystemVerilog Testbenches

```bash
make test/sv/<testbench_name>
```

Use the available testbenches to verify processor functionality and, where supported, multicore system behavior.

### 7. Synthesize for FPGA

```bash
make synthesis
```

This invokes the configured Xilinx Vivado flow. Ensure that the selected top-level module, constraints, and synthesis configuration target Alpha Titan rather than the original single-core Hadi-V design.

### 8. Clean Build Files

```bash
make clean
```

### Notes

- Generated build artifacts are stored in the `build/` directory.
- Waveform save configurations are located in the `saves/` directory.
- Available commands and target names may change as Alpha Titan's build and verification infrastructure evolves.

---

## Acknowledgments

We gratefully acknowledge:

- **Tobias Scheipel, David Beikircher, Florian Riedl, and the Embedded Architectures & Systems Group at Graz University of Technology** for developing the original HaDes-V open educational resource.
- The **OpenTitan project and its contributors** for their work on open-source silicon design and system-level architectural concepts that inspire Alpha Titan.
- Our mentors, collaborators, and peers at Alpha Science Lab.
- The broader academic and open-source hardware communities.

AlphaTitan builds upon existing open-source educational work. We acknowledge the original authors and their contributions while continuing to develop our own multicore processor and SoC capabilities.

Please refer to the original project's license and applicable upstream licensing terms when using or redistributing adapted materials.

---

**Alpha Science Lab**

*Mymensingh Engineering College, Bangladesh*

*Building indigenous capabilities in processor architecture, multicore systems, and semiconductor engineering.*
