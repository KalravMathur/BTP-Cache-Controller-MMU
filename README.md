# RTL Design of a Memory Management Unit and Cache Controller

---

## Overview

This repository contains a comprehensive **Register Transfer Level (RTL)** design for a foundational **Memory Management Unit (MMU)** and a **2-Way Set-Associative Cache Controller**. The design is based on foundational principles of computer architecture, specifically virtual memory translation and cache hierarchies, which are critical for bridging the "memory wall" performance gap between modern CPUs and main memory [[1]](#references).

### Project Team

- **Akhil Sriram** 
- **Kalrav Mathur** 

**Institution:** Shiv Nadar Institution of Eminence  
**Project Type:** B.Tech Minor Project  
**Mentor:** Dr. Venkatnarayan Hariharan

---

## Features

### Memory Management Unit (MMU)
- 32-bit virtual address to 32-bit physical address translation
- Includes a conceptual model for a Translation Lookaside Buffer (TLB)
- High-level model developed in Verilog

### Cache Controller (2-Way Set-Associative)
- Manages an 8KB, 2-way set-associative cache
- Uses 64-Byte cache blocks (lines)
- Implements Write-Through (no-write-allocate) write policy
- Uses 1-bit LRU (Least Recently Used) replacement policy
- Written in synthesizable Verilog

---

## Repository Structure

```
BTP-Cache-Controller-MMU/
├── cache_controller.v       # 2-Way Cache Controller Design Unit (Verilog)
├── cc_tb.v                  # Testbench for cache controller
├── mmu.v                    # Memory Management Unit (Verilog)
├── MMU_declarations.v       # MMU module declarations
├── TB_MMU.v                 # Testbench for MMU
└── README.md                # This file
```

---

## Prerequisites

- **Synopsys VCS** or compatible Verilog-2001 simulator
- Verilog-2001 standard support

---

## Installation

Clone the repository:
```bash
git clone https://github.com/KalravMathur/BTP-Cache-Controller-MMU.git
cd BTP-Cache-Controller-MMU
```

---

## How to Simulate

Compile and run the simulation using Synopsys VCS:

```bash
# Compile the files
vcs file1.v file1tb.v +vcs+fsdbon -kdb -debug_access+all -full64

# Run the simulation
./simv +fsdb+all
```

---

## Design Specifications

### Cache Controller Specifications
| Parameter | Value |
|-----------|-------|
| **Cache Size** | 8 KB |
| **Associativity** | 2-Way |
| **Block Size** | 64 Bytes |
| **Address Width** | 32 bits |
| **Write Policy** | Write-Through |
| **Write Allocate** | No |
| **Replacement Policy** | 1-bit LRU |

### MMU Specifications
| Parameter | Value |
|-----------|-------|
| **Virtual Address Width** | 32 bits |
| **Physical Address Width** | 32 bits |
| **TLB Model** | Conceptual |
| **Implementation Language** | Verilog |

---

## References

[1] S. R. Sarangi, *Computer Architecture and Organization*. McGraw-Hill Education, 2017.

[2] SHAKTI Processor Project, "SHAKTI Cache Controller Implementation in Bluespec," https://gitlab.com/shaktiproject/uncore/caches

[3] Geeks for Geeks, "Cache Memory in Computer Organization," https://www.geeksforgeeks.org/cache-memory-in-computer-organization/

[4] Geeks for Geeks, "Virtually Indexed Physically Tagged (VIPT) Cache," https://www.geeksforgeeks.org/computer-organization-architecture/virtually-indexed-physically-tagged-vipt-cache/

---

## License

This project is licensed under **Shiv Nadar University License** as specified in the source files.

---