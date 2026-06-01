# AXI4 Verification Plan

## Objective
Verify the AXI4 protocol implementation (master + slave) against ARM AMBA AXI4 Specification IHI0022.

## Verification Strategy
- Constrained-random transaction generation
- Scoreboard-based data integrity checking
- Functional coverage to measure completeness
- SVA protocol checker for real-time assertion monitoring

## Test Scenarios

| ID | Test | Goal |
|----|------|------|
| T1 | Single beat write | Basic handshake |
| T2 | Single beat read | Basic read path |
| T3 | Write-Read-Verify | Data integrity |
| T4 | INCR burst (16 beats) | Burst write |
| T5 | FIXED burst | Same-address writes |
| T6 | WRAP burst (8 beats) | Cache-line wrapping |
| T7 | Max burst (256 beats) | AXI4 max length |
| T8 | 4KB boundary | AXI4 boundary rule |
| T9 | Address alignment | All sizes 1B-128B |
| T10 | Back-to-back | Zero-delay pipelining |
| T11 | Outstanding x8 | Concurrent IDs |
| T12 | Random traffic (1000) | Stress coverage |
| T13 | Corner case stress | Edge cases |

## Coverage Goals

| Metric | Target |
|--------|--------|
| Code Coverage | > 95% |
| Functional Coverage | > 90% |
| Assertion Coverage | 100% |
| Toggle Coverage | > 90% |

## Protocol Rules Checked (SVA)
- VALID stability: VALID must not deassert while waiting for READY
- Address alignment: addr must be aligned to transfer size
- 4KB boundary: no burst may cross a 4KB boundary
- WRAP length: must be 2, 4, 8, or 16 beats
- WLAST: must be asserted exactly on the final beat
- Outstanding limit: max 16 concurrent write/read transactions
- Handshake timeout: READY must respond within 1000 cycles

## Known Issues Fixed
- Bug 1: WRAP burst could generate invalid lengths → fixed in `c_burst_len` constraint
- Bug 2: Outstanding overflow (>16) → caught by `outstanding_write_limit` SVA
- Bug 3: 4KB boundary crossing → caught by `aw_4kb_boundary` SVA
