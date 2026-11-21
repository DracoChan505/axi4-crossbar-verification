# Verilator Code Coverage Report (Measured)

**Date**: 2026-11-20  
**Tool**: Verilator 5.052 `--coverage`  
**Tests**: 18 (6 scenarios × 3 seeds), all PASS  
**Measured by**: `scripts/run_coverage.py build/regress/report`

---

## Summary

| Metric | Result | Coverage Points |
|--------|--------|-----------------|
| **Line Coverage** | **84.2%** | 446 / 530 |
| **Toggle Coverage** | **100.0%** | 299 / 299 |
| **Functional Coverage** | **100.0%** | 28 / 28 bins |

> These are **measured numbers** from Verilator `--coverage` instrumentation,  
> not estimates. All 18 regression tests passed before coverage collection.

---

## Per-Module Line / Toggle Coverage

| Module | Line | Toggle |
|--------|------|--------|
| `axi_address_decode.sv` | 76% (10/13) | 100% (10/10) |
| `axi_crossbar.sv` | 75% (31/41) | 100% (37/37) |
| `axi_crossbar_read.sv` | 73% (17/23) | 100% (31/31) |
| `axi_crossbar_write.sv` | 86% (26/30) | 100% (41/41) |
| `axi_read_data_path.sv` | 95% (38/40) | 100% (22/22) |
| `axi_read_decerr.sv` | 36% (12/33) | 100% (9/9) |
| `axi_read_frontend.sv` | 98% (55/56) | 100% (31/31) |
| `axi_record_fifo.sv` | 100% (11/11) | 100% (30/30) |
| `axi_rr_arbiter.sv` | 85% (35/41) | 100% (8/8) |
| `axi_write_data_path.sv` | 100% (46/46) | 100% (17/17) |
| `axi_write_decerr.sv` | 37% (13/35) | 100% (9/9) |
| `axi_write_frontend.sv` | 98% (63/64) | 100% (36/36) |
| `axi_write_response_path.sv` | 93% (31/33) | 100% (12/12) |
| `axi_write_tracker.sv` | 90% (58/64) | 100% (6/6) |
| **TOTAL** | **84.2%** | **100.0%** |

---

## Notes on Low-Coverage Modules

**`axi_read_decerr.sv` (36%) and `axi_write_decerr.sv` (37%)**  
These modules generate DECERR (Decode Error) AXI responses when a master targets  
an address outside all configured slave ranges. The current 6 test scenarios use  
valid mapped addresses only. To hit these paths, a future test scenario would need  
to inject an unmapped address transaction. This is a known gap, not a defect.

All other modules achieved ≥73% line coverage, with the two main data-path modules  
(`axi_write_data_path.sv`, `axi_record_fifo.sv`) reaching 100%.

---

## How to Reproduce

```bash
cd axi4-crossbar
python3 scripts/run_coverage.py build    # ~2 min, Verilator --coverage build
python3 scripts/run_coverage.py regress  # ~20 sec, 18 tests, merge .dat files
python3 scripts/run_coverage.py report   # parse annotated output, print table
```

Raw data: `coverage/uvm7_cov_d32/merged.dat`, `coverage/uvm7_cov_d32/code_coverage.json`  
Annotated source: `coverage/uvm7_cov_d32/annotated/*.sv`
