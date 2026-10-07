# AC community microgrid model (PS #38) - MATLAB plant + ESP32 controller

Separate from `../mg_twin` (the 12 V DC model), which is unchanged.
Everything electrical is simulated in MATLAB as a **phasor (RMS) AC model**: 230 V, 50 Hz,
active power P and reactive power Q, voltages at every house, frequency, phase angle.
The only hardware is the ESP32 controller (+ 4 indicator LEDs), linked over USB.

```
 Utility grid --Zth-- [grid breaker] --- COMMUNITY BUS ---cable--- House 1 (3 kWp PV, critical, flexible)
                                          |  BESS 10 kWh / 6 kVA   ---cable--- House 2 (2 kWp PV, ...)
                                          |  community PV 5 kWp    ---cable--- House 3 (no PV, ...)
                                          |  community load (pump, lights) - critical
 ESP32: grid breaker, sync, house ties, flexible loads, BESS set-points, prepaid credit, cards, LEDs
```

## Folders
| Folder | Contents |
|---|---|
| `params/ac_params.m` | every number (houses are rows: copy one to add a house) |
| `models/` | `pv_power`, `volt_var`, `net_solve` (AC power flow), `plant_step` (grid / island / dead), `ac_profiles` |
| `controller/` | `ac_controller_step.m` = MATLAB twin of the firmware |
| `comms/` | USB text protocol (docs/protocol.md) |
| `sim/` | scenarios, KPIs, P2P ledger, Monte Carlo, AI dataset generator, plots |
| `firmware/` | ESP32 PlatformIO project (`config.h` generated) |
| `hil/` | run with the real ESP32 (`run_hil_demo.m`) |
| `tests/` | unit tests + pass rules |
| `docs/` | `protocol.md`, `data_contract.md` (for the AI/ML team) |
| `results/` | figures, tables, datasets, `results_summary.md` |

## Run
- `cd mg_ac; run_all` (about 10 min): everything, then read `results/results_summary.md`.
- One scenario: `P = ac_params(); S = define_scenarios(P); R = run_scenario(S(2), P); plot_scenario(R, P, 'x.png')`
  (run the `addpath` line at the top of `run_all.m` first).
- Real ESP32: `hil/run_hil_demo.m`. C++ vs MATLAB: `bash tools/run_sil.sh` (needs g++).

## LEDs on the ESP32 (330 ohm each)
GPIO25 green = grid breaker closed - GPIO26 red = island (blinks while synchronising) -
GPIO27 yellow = a flexible load is shed - GPIO14 white = fault / lockout / E-stop. E-stop: GPIO33 to GND.
