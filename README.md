# UVM Verification of DMA Controller with SVA, Coverage-Driven & Corner Case Regression

A **SystemVerilog UVM 1.2** verification environment for a **Direct Memory Access (DMA) Controller**, implementing transaction modeling, sequence generation, scoreboard with reference model, SVA protocol assertions, and functional coverage closure — runnable directly on **EDA Playground (Aldec Riviera-PRO)**.

---

## 📌 Project Overview

This project implements a complete UVM testbench to verify a DMA controller DUT capable of memory-to-memory and memory-to-peripheral transfers. The environment exercises high-speed burst transfers, interrupt generation, boundary violations, buffer overflow corner cases, and concurrent back-to-back transactions — all verified through a scoreboard reference model and functional coverage collectors.

The DUT is a synthesizable DMA controller with a 5-state FSM (IDLE → FETCH → WRITE → DONE / ERROR), 256-word internal memory, and interrupt gating logic.

---

## ✨ Features

- **Transaction Modeling** — `dma_seq_item` with constrained-random fields covering source/destination addresses, transfer length, burst size, direction, and interrupt enable
- **Virtual Sequencer** — coordinates all agent sequences for multi-scenario regression
- **Reference Model Scoreboard** — checks five independent correctness conditions per transaction:
  - Done must assert after every transfer
  - Boundary violations must produce an error response
  - Normal transfers must never produce an error
  - Interrupt must fire when `int_enable=1`
  - Interrupt must not fire when `int_enable=0`
- **SVA Protocol Assertions** — three concurrent properties:
  - `DONE` must not assert without prior `BUSY`
  - `BUSY` must deassert after `DONE`
  - `INTERRUPT` only fires when `int_enable` is set
- **Functional Coverage** — covergroup with cross-coverage targeting:
  - Transfer lengths: single, small, burst
  - Burst sizes: 1, 4, 8 beats
  - Direction: mem2mem, mem2periph
  - Interrupt: enabled vs disabled
  - Error: expected vs unexpected
  - Cross: length × direction, irq × error, length × burst
- **Five Sequence Types**:
  - `dma_rand_seq` — 20 constrained-random transfers
  - `dma_burst_seq` — all burst sizes (1, 4, 8, 16 beats)
  - `dma_interrupt_seq` — IRQ enabled and disabled scenarios
  - `dma_boundary_seq` — buffer overflow injection (src=0xF0 + len=32 > 256)
  - `dma_concurrent_seq` — back-to-back transfers simulating concurrent access

---

## 🏗️ UVM Environment Architecture

```
dma_regression_test
└── dma_env
    ├── dma_agent
    │   ├── dma_driver         (programs DMA registers, drives start pulse)
    │   ├── dma_monitor        (observes start/done, broadcasts transactions)
    │   └── uvm_sequencer
    │       ├── dma_rand_seq
    │       ├── dma_burst_seq
    │       ├── dma_interrupt_seq
    │       ├── dma_boundary_seq
    │       └── dma_concurrent_seq
    ├── dma_scoreboard         (5-point reference model checker)
    ├── dma_coverage           (functional coverage + cross coverage)
    └── dma_virtual_seqr       (coordinates multi-scenario regression)
```

---

## 🛠️ Files

| File | Description |
|---|---|
| `design.sv` | DMA interface with SVA assertions + DMA controller DUT |
| `testbench.sv` | Complete UVM environment: transaction, sequences, driver, monitor, coverage, scoreboard, agent, env, tests, top module |

---

## ⚙️ Running on EDA Playground

### Step 1 — Open EDA Playground
Go to [edaplayground.com](https://edaplayground.com) and log in.

### Step 2 — Simulator Settings
| Setting | Value |
|---|---|
| Testbench + Design | `SystemVerilog/Verilog` |
| UVM / OVM | `UVM 1.2` |
| Tools & Simulators | `Aldec Riviera-PRO` |

### Step 3 — Paste the files
- Paste `design.sv` content into the **design.sv** tab
- Paste `testbench.sv` content into the **testbench.sv** tab

### Step 4 — Compile Options
```
-timescale 1ns/1ns +incdir+$RIVIERA_HOME/vlib/uvm-1.2/src
```

### Step 5 — Run Options
```
+access+r +UVM_TESTNAME=dma_regression_test +UVM_VERBOSITY=UVM_MEDIUM
```

### Step 6 — Run
Tick **"Open EPWave after run"** and click **Run**.

---

## ✅ Simulation Results

Verified and passing on **Aldec Riviera-PRO 2025.04** with **UVM 1.2**:

```
SUCCESS "Compile success 0 Errors 0 Warnings  Analysis time: 5[s]."

UVM_INFO @ 0:    reporter [RNTST] Running test dma_regression_test...
UVM_INFO @ 0:    uvm_test_top [TEST] === DMA Topology ===
UVM_INFO @ 0:    uvm_test_top [TEST] --- Running: Random Transfers ---
UVM_INFO @ 175:  uvm_test_top.env.sb [SB] PASS: src=0x9d dst=0xb7 len=1 irq=1 err=0
UVM_INFO @ 255:  uvm_test_top.env.sb [SB] PASS: src=0x87 dst=0x89 len=1 irq=0 err=0
UVM_INFO @ 475:  uvm_test_top.env.sb [SB] PASS: src=0x32 dst=0x83 len=8 irq=1 err=0
...
UVM_INFO @ 2705: uvm_test_top [TEST] --- Running: Burst Transfers ---
UVM_INFO @ 2775: uvm_test_top.env.sb [SB] PASS: src=0x0 dst=0x40 len=1  irq=1 err=0
UVM_INFO @ 2915: uvm_test_top.env.sb [SB] PASS: src=0x0 dst=0x40 len=4  irq=1 err=0
UVM_INFO @ 3135: uvm_test_top.env.sb [SB] PASS: src=0x0 dst=0x40 len=8  irq=1 err=0
UVM_INFO @ 3515: uvm_test_top.env.sb [SB] PASS: src=0x0 dst=0x40 len=16 irq=1 err=0
UVM_INFO @ 3525: uvm_test_top [TEST] --- Running: Interrupt Tests ---
UVM_INFO @ 3655: uvm_test_top.env.sb [SB] PASS: src=0x10 dst=0x60 len=4 irq=1 err=0
UVM_INFO @ 3795: uvm_test_top.env.sb [SB] PASS: src=0x20 dst=0x70 len=4 irq=0 err=0
UVM_INFO @ 3805: uvm_test_top [TEST] --- Running: Boundary/Overflow ---
UVM_INFO @ 3855: uvm_test_top.env.sb [SB] BOUNDARY ERR OK: src=0xf0 len=32 errored as expected
UVM_INFO @ 3865: uvm_test_top [TEST] --- Running: Concurrent Transfers ---
UVM_INFO @ 3955: uvm_test_top.env.sb [SB] PASS: src=0x98 dst=0x26 len=2 irq=1 err=0
...
UVM_INFO @ 4485: uvm_test_top.env.sb [SB] === DMA Scoreboard Report === PASS:31 FAIL:0 ERR_CAUGHT:1 IRQ_FIRED:15
UVM_INFO @ 4485: uvm_test_top [TEST] *** TEST PASSED ***

--- UVM Report Summary ---
UVM_INFO    : 43
UVM_WARNING :  0
UVM_ERROR   :  0
UVM_FATAL   :  0

Simulation finished at: 4485 ns
```

| Metric | Result |
|---|---|
| Compile errors | 0 |
| Compile warnings | 0 |
| Scoreboard PASS | 31 |
| Scoreboard FAIL | 0 |
| Boundary errors caught | 1 |
| Interrupts verified | 15 |
| UVM_ERROR | 0 |
| UVM_FATAL | 0 |
| Simulation time | 4485 ns |
| Coverage database | fcover.acdb saved |

---

## 🧪 Test Scenarios

| Test Sequence | Transactions | What it verifies |
|---|---|---|
| `dma_rand_seq` | 20 | Constrained-random transfers, all directions and lengths |
| `dma_burst_seq` | 4 | All burst sizes: 1, 4, 8, 16 beats with IRQ enabled |
| `dma_interrupt_seq` | 2 | IRQ fires when `int_enable=1`; silent when `int_enable=0` |
| `dma_boundary_seq` | 1 | src=0xF0 + len=32 overflows 256 → DUT must assert error |
| `dma_concurrent_seq` | 4 | Back-to-back transfers simulating concurrent access |

---

## 📊 Coverage Targets

| Coverpoint | Bins |
|---|---|
| Transfer length | single (1), small (2,4), burst (8,16) |
| Burst size | 1-beat, 4-beat, 8-beat |
| Direction | mem2mem, mem2periph |
| Interrupt enable | off, on |
| Error | no error, error triggered |
| Interrupt fired | not fired, fired |
| Cross: length × direction | 6 cross bins |
| Cross: irq × error | 4 cross bins |
| Cross: length × burst | 9 cross bins |

---

## 🔒 SVA Protocol Assertions

Three concurrent assertions run throughout simulation inside the interface:

```systemverilog
// DONE must not assert without prior BUSY
property done_after_busy;
  @(posedge clk) disable iff (!rst_n)
  $rose(done) |-> $past(busy, 1);
endproperty
assert property (done_after_busy)
  else $error("DONE asserted without prior BUSY");
```

Similar properties enforce `BUSY` clears after `DONE` and interrupt gating by `int_enable`.

---

## 📁 Project Structure

```
├── design.sv         # DMA interface (SVA) + DMA controller DUT
├── testbench.sv      # Full UVM environment + top module
└── README.md
```

---

## 🤝 Contributing

Contributions are welcome!

1. Fork this repository
2. Create a feature branch
3. Commit your changes
4. Submit a pull request

---

**License**
MIT License – see [LICENSE](LICENSE) for details.

**Author**: [Sunil Dabbiru](https://github.com/DabbiruSunil)
