# Results Summary

**Generated:** 02-Oct-2026 00:52:43

## Configuration
- Bus Config: **A** | V_nom = **6.0 V**
- Total load power: **3.33 W** | Source capacity: **6.0 W**
- PV Pmax (STC): **3.0 W**

## Verification Overview
| Check | Result |
|---|---|
| FSM unit tests (7) | **PASS** |
| C++ firmware SIL equivalence (all scenarios) | not run (needs g++, see README) |

## Monte Carlo Results (N=30)
| Metric | Value |
|---|---|
| Pass Rate | **100.0%** (req. >= 95%) |
| Result | **PASS** |

## Scenario Results (plant_fallback.m, pure-MATLAB plant)
| ID | Pass | Bus up [s] | Tier restore times [s] | Peak I_src [A] | Fault | Final state |
|---|---|---|---|---|---|---|
| T1 | PASS | 1.05 | 4.97 6.47 7.97 9.47 | 0.675 | 0 | S7 |
| T2 | PASS | 1.05 | 4.97 6.47 7.97 9.47 | 1.073 | 0 | S7 |
| T3 | PASS | 1.05 | 4.97  Inf  Inf  Inf | 0.330 | 0 | S7 |
| T4 | PASS | 1.05 | 4.97 6.47 7.97 9.47 | 0.675 | 0 | S7 |
| T5 | PASS | 1.05 | 4.97 6.47 7.97 9.47 | 0.675 | 0 | S7 |
| T6 | PASS | 1.05 | 4.97 6.47 7.97 9.47 | 0.675 | 1 | S9 |
| T7 | PASS | 1.05 | 4.97 6.47 7.97 9.47 | 1.500 | 0 | S7 |
| T8 | PASS | 1.05 | 4.97 6.47 7.97 9.47 | 0.675 | 1 | S9 |
| T9 | PASS | Inf | Inf Inf Inf Inf | 0.000 | 0 | S9 |

(Inf = tier never restored, expected for T3 low-SOC and T9 lockout. T7: T2 is locked out as a faulty branch after it is first restored, so its restore time is still shown.)

## Wall-clock
Generated 02-Oct-2026 00:52:43 by run_all.m; each 30 s scenario simulates in about 2 s of wall-clock; the full run_all (T1-T9, Monte Carlo, export) takes about 2.5 minutes.

## Assumptions
See [docs/architecture.md](architecture.md) for full list.
