# AC microgrid model: results summary

Generated 07-Oct-2026 15:51:38 by run_all.m. Everything electrical is simulated in MATLAB (phasor model); the controller is the MATLAB twin of the ESP32 firmware.

| Check | Result |
|---|---|
| Unit tests | 7 / 7 pass |
| Scenarios | 10 / 10 pass |
| Monte Carlo | 40 / 40 pass (100.0 %, requirement 95 %) |
| SIL C++ firmware vs MATLAB | PASS: 195,000 ticks over all 10 scenarios, 0 mismatches (bash tools/run_sil.sh, g++ in the Linux workspace) |
| ESP32 main.cpp | compiles with -Wall -Wextra against a stub Arduino.h (no warnings); real ESP32 toolchain not run |
| AI training dataset | 120 days x 1440 rows (60 s), 65 columns, results/datasets/ai_dataset_60s.csv |

## Scenarios

| Scenario | Pass | V min pu | V max pu | f min | f max | SOC min | close angle deg | failed rules |
|---|---|---|---|---|---|---|---|---|
| S1_normal_day | true | 0.984 | 1.012 | 49.86 | 50.02 | 0.60 | 3.0 |  |
| S2_grid_outage | true | 0.975 | 0.999 | 49.61 | 50.11 | 0.10 | 1.2 |  |
| S3_low_battery_outage | true | 0.976 | 0.999 | 49.73 | 50.11 | 0.19 | 1.6 |  |
| S4_island_overload | true | 0.968 | 0.998 | 49.48 | 50.02 | 0.72 | 4.2 |  |
| S5_island_surplus | true | 0.982 | 1.010 | 50.02 | 50.98 | 0.90 | 4.3 |  |
| S6_faulty_house | true | 0.983 | 1.007 | 50.02 | 50.40 | 0.70 | 0.6 |  |
| S7_abnormal_grid | true | 0.983 | 1.013 | 49.20 | 50.40 | 0.70 | 4.5 |  |
| S8_prepaid_cards | true | 0.977 | 0.999 | 49.79 | 50.02 | 0.60 | 2.9 |  |
| S9_ai_advisor | true | 0.976 | 0.999 | 49.85 | 50.02 | 0.25 | 2.9 |  |
| S10_long_outage_blackout | true | 0.969 | 0.998 | 49.52 | 50.02 | 0.05 | 1.2 |  |

## Normal day (S1)

Grid import 28.9 kWh, export 23.0 kWh, cable losses 0.18 kWh. Grid power factor never below 0.997 (BESS supplies the reactive power).

P2P ledger (Wh, row sells to column):

| seller | H1 | H2 | H3 |
|---|---|---|---|
| H1 | 0 | 86 | 403 |
| H2 | 0 | 0 | 48 |
| H3 | 0 | 0 | 0 |
| C | 472 | 694 | 1241 |

## Monte Carlo

Runs 40. Voltage 0.969-1.012 pu, island frequency 49.58-50.12 Hz, worst closing angle 5.0 deg, worst SOC 0.19.

## Not verified / simplifications

- Phasor (RMS) model at 1 s steps: no waveforms, no sub-cycle transients. Real islanding detection and breaker opening take milliseconds; here the transfer gap is one 1 s tick.
- Over-current protection at 1 s is for logic only; real fault clearing is the MCB/fuse.
- Firmware not yet built with the ESP32 toolchain or run on the board (hil/run_hil_demo.m untested on hardware).
- All [assumed] numbers in params/ac_params.m; load profiles are synthetic.
