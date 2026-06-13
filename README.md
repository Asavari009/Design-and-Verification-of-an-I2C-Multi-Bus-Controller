# I2C Multi-Bus Controller (I2CMB) — Layered Verification Testbench

A multi-phase SystemVerilog verification suite for the [OpenCores I2C Multiple Bus Controller (I2CMB)](https://opencores.org/projects/i2cmb) IP Core, evolving from a flat testbench to a complete layered environment with constraint-driven random testing, functional coverage tracking, and regression closure.

---

## Table of Contents
- [Overview](#overview)
- [Verification Architecture](#verification-architecture)
- [Verification Flow](#verification-flow)
- [Repository Structure](#repository-structure)
- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)

---

## Overview

This repository consolidates a step-by-step evolutionary migration from a basic flat testbench interface up to a complete SystemVerilog layered verification environment. The final environment supports:

- Constraint-driven random testing
- Functional coverage tracking with SystemVerilog covergroups
- Automated regression with coverage merging
- Self-checking scoreboard with predictor validation

---

## Verification Architecture

Built across four progressive phases:

### Phase 1 — Interface & Hardware Tasks
- Established **Wishbone (`wb_if`)** and **I2C (`i2c_if`)** interface connections to the DUT
- Implemented core driver tasks: `wait_for_i2c_transfer` (write/read cycles) and `provide_read_data` handlers

### Phase 2 — Layered Testbench Environment
- Migrated to a fully modular architecture using the `ncsu_pkg` foundation class library
- Built the following independent components:
  - `i2cmb_test` — top-level test wrapper
  - `i2cmb_generator` — stimulus generator arrays
  - `wb_monitor` / `i2c_monitor` — independent protocol monitors
  - `i2cmb_predictor` — active prediction module
  - `i2cmb_scoreboard` — automated transaction comparator

### Phase 3 — Test Plan & Functional Coverage
- Defined **20+ verification targets** covering register-level access (CSR, DPR, CMDR) and multi-bus state hazards
- Implemented SystemVerilog **covergroups**, parameterized **coverpoints**, and **cross coverage** criteria
- Mapped runtime metrics to a structural XML test plan within the **Siemens Questa UCDB** database

### Phase 4 — Constraint-Driven Random Testing & Regression
- Developed specialized random transaction constraints and directed edge-case scenarios
- Configured `regress.sh` to trigger concurrent randomized simulations, capture isolated coverage databases, and merge them into a cumulative coverage summary

---

## Verification Flow

The testbench validates four core scenarios across all phases:

| Scenario | Description |
|---|---|
| **Sequential Write Streams** | Verifies multi-byte write transfers from Wishbone down to physical I2C lines |
| **Bidirectional Read Handshakes** | Exercises dynamic bus response with internal monitor pipeline validation |
| **Interleaved Stress Testing** | Floods bus arbiters with read/write boundaries to detect deadlocks or state discrepancies |
| **Scoreboard Cross-Checking** | Automatically flags structural discrepancies or illegal bus states across both interfaces |

---

## Repository Structure

```
.
├── proj_1/          # Phase 1: Basic interface & hardware tasks
├── proj_2/          # Phase 2: Layered testbench architecture
├── proj_3/          # Phase 3: Test plan & functional coverage
├── proj_4/          # Phase 4: Constraint-driven random testing & regression
│   └── sim/
│       └── Makefile
├── regress.sh       # Automated regression script
└── README.md
```

---

## Prerequisites

- Linux / Unix compute cluster environment
- **Siemens Questa Sim** / ModelSim simulation environment
- Standard shell utilities (`bash`, `tar`, `make`)

---

## Getting Started

**Run a single phase simulation:**
```bash
cd ece745_projects/proj_4/sim
make debug
```

**Run full regression with coverage merge:**
```bash
./regress.sh
```
