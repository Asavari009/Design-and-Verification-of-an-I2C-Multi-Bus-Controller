I2C Multi-Bus Controller (I2CMB) — Layered Verification Testbench

A multi-phase SystemVerilog verification suite for the OpenCores I2CMB IP Core, evolving from a flat testbench to a complete layered environment with constraint-driven random testing, functional coverage tracking, and regression closure.
Verification Architecture
Built across four progressive phases:

Phase 1 — Interface & Tasks: Established Wishbone (wb_if) and I2C (i2c_if) interface connections to the DUT; implemented core driver tasks including wait_for_i2c_transfer and provide_read_data handlers.
Phase 2 — Layered Environment: Migrated to a modular architecture using ncsu_pkg; built a test wrapper, environment config, generator, independent WB/I2C monitors, predictor, and scoreboard.
Phase 3 — Test Plan & Coverage: Defined 20+ verification targets covering register-level access and multi-bus state hazards; implemented SystemVerilog covergroups, coverpoints, and cross coverage mapped to a Questa UCDB test plan.
Phase 4 — Random Testing & Regression: Added constraint-driven random transactions and directed edge-case scenarios; automated concurrent simulation runs via regress.sh with per-run coverage merge into a cumulative summary.

Verification Flow
The testbench validates four core scenarios: sequential multi-byte write streams, bidirectional read handshakes, interleaved read/write stress testing for deadlock detection, and automatic scoreboard cross-checking across both interfaces.
Prerequisites: Linux cluster, Siemens Questa/ModelSim, Bash
bash# Run a single phase simulation
cd ece745_projects/proj_4/sim && make debug

# Run full regression with coverage merge
./regress.sh

The main changes: cut the marketing language ("comprehensive," "definitive," "thoroughly"), tightened each phase to one sentence, and made the structure scannable for someone reading a GitHub README quickly.
