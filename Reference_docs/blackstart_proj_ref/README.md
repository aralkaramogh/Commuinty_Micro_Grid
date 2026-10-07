=# DC Solar Microgrid Black-Start Controller
### Aarambh Hackathon #34 - Hardware Track

---

## 1. What is this project? (plain language)

A **microgrid** is a small, self-contained power network. Ours is a **6 V DC "bus"** (a shared power rail on a breadboard) fed by:

- a **solar panel** (6 V / 3 W), and
- a **"battery"**: emulated by a 12 V power supply + buck converter set to about 6.15 V, with a software "state of charge" (SOC) counter,

and it powers **four loads of different importance**:

| Tier | Load | Importance |
|---|---|---|
| T1 | LED bar (36 Ohm) | Critical, restored first, never shed by priority |
| T2 | 47 Ohm resistor | Important |
| T3 | DC fan motor (30 Ohm, big start-up surge) | Normal |
| T4 | 100 Ohm dummy | Lowest priority |

**Black start** means bringing that network back up from a **total blackout with no outside help**. Switching everything on at once would cause a big current surge, a voltage collapse and probably a blown fuse. So an **ESP32 controller** does it safely, step by step:

1. **Detect** the blackout (bus below 20% for 1 s).
2. **Authorise**: an operator taps an **RFID card**. 3 wrong cards locks the system.
3. **Self-check**: sensors sane? Enough battery (SOC at least 20%)? It also zero-calibrates the current sensors.
4. **Soft-start**: ramp the battery switch up gradually over about 1 s (PWM) so there is no surge.
5. **Wait** until the bus is stable for 2 s.
6. **Connect solar** if the panel voltage is high enough.
7. **Restore loads one at a time**, most important first, and only if there is enough power headroom and SOC.
8. **Run normally**: keep watching, shed low-priority loads if the bus is stressed, and trip on faults.

Protections: over-current, I2t (overheating), over-voltage, low SOC, a stuck source switch, a frozen sensor, and a **shorted load branch** (the bad tier is isolated while the others keep running).

The project has **two halves that must agree**:

| Half | What it is | Where |
|---|---|---|
| **Digital twin** (MATLAB) | A simulation of the circuit plus the controller logic, used to prove the logic works in 9 test scenarios and 30 randomised Monte Carlo runs | `params/`, `src/`, `tests/`, `run_all.m` |
| **Firmware** (ESP32, C++) | The same controller logic, ported to run on the real board | `firmware/` |

The **SIL test** ("software-in-the-loop") feeds the exact sensor readings from every MATLAB scenario into the real C++ code and checks it makes the **same decisions, tick for tick**.

### Diagrams

| Diagram | What it shows |
|---|---|
| [System architecture](docs/diagrams/01_system_architecture.svg) | Laptop (MATLAB) to ESP32 firmware to power hardware, and how they connect |
| [Hardware wiring](docs/diagrams/02_hardware_wiring.svg) | Every power path, sensor, switch and ESP32 pin |
| [MOSFET gates explained](docs/diagrams/03_gate_drive_explained.svg) | How a GPIO pin turns a power switch on or off, the two switch types, soft-start PWM, safety defaults |

![System architecture](docs/diagrams/01_system_architecture.svg)

---

## 2. How to use it

### A. Run the whole simulation (about 2.5 minutes)
1. Open MATLAB (R2025b used; Simulink/Simscape are **not** required).
2. In MATLAB, go to this folder and run:
   ```matlab
   cd('D:\Amogh\MATLAB_Projects\aarambh_hackathon')
   run_all
   ```
3. It runs, in order: parameter checks, PV model, 7 FSM unit tests, scenarios T1-T9, the C++ SIL check (only if `g++` is installed), 30 Monte Carlo runs, exports `firmware/include/config.h`, and writes the report.

**What you get:**

| Output | What it shows |
|---|---|
| `docs/results_summary.md` | The headline numbers: pass/fail per scenario, Monte Carlo pass rate |
| `results/figures/scenario_T1.png` ... `T9.png` | One figure per scenario (see below) |
| `results/figures/pv_*_curves.png` | Solar panel I-V / P-V curves |
| `results/tables/montecarlo_results.csv` | Pass/fail of each random run |
| `results/logs/sil_T*.csv` | Sensor and decision recordings used by the SIL test |
| `results/logs/run_all_log.txt` | Full console log of the run (when started from the MATLAB window) |
| `firmware/include/config.h` | All parameters exported for the firmware (never edit by hand) |

**Reading a scenario figure** (8 panels):

| Panel | Meaning |
|---|---|
| V_bus | Bus voltage. Should rise smoothly to about 6 V and stay inside the dashed band |
| I_src | Battery current. Spikes at each load connect, never above the limit |
| I_load | Total load current, which steps up as each tier comes on |
| V_pv / P_pv | Solar voltage and power |
| SOC | Virtual battery charge |
| SRC duty | The soft-start ramp, 0 to 1 over about 1 s |
| FSM state | Which step the controller is in (S0 ... S7, S8 = fault recovery, S9 = lockout) |

### B. The 9 test scenarios

| ID | Situation | Expected (and achieved) behaviour |
|---|---|---|
| T1 | Normal sunny black start | Bus up at about 1 s. T1, T2, T3, T4 restored at 5.0 / 6.5 / 8.0 / 9.5 s. No faults |
| T2 | Night, no solar | Same, using the battery only |
| T3 | Battery low (SOC 20%) | Only the critical tier T1 is restored |
| T4 | Cloud passes (solar drops 15-21 s) | Loads ride through, no trip |
| T5 | Motor start-up surge | No false trip |
| T6 | Battery switch fails open at 15 s | Detected, then safe alarm lockout (S9) |
| T7 | Tier 2 short-circuits at 12 s | Loads shed in about 20 ms. T2 is blamed, retried once, then **locked out**. T1, T3 and T4 keep running |
| T8 | Bus-voltage sensor freezes at 10 s | Detected after 2 s, then safe lockout |
| T9 | 3 wrong RFID cards | Lockout. The bus is **never** energised |

### C. Change something
All numbers live in **one file**: `params/dc_microgrid_params.m` (bus voltage, current limits, load values, timings, thresholds). Edit it and run `run_all` again. The firmware header `config.h` is regenerated automatically.

### D. (Optional) Run the C++ SIL check on Windows
Install a C++ compiler once, then restart MATLAB:
```
winget install BrechtSanders.WinLibs.POSIX.UCRT
```
After that, `run_all` runs it automatically (step 5b). You can also run it on its own in MATLAB with `run_sil`.

### E. Build and flash the ESP32 (not done yet: the first build may need small fixes)
```
pip install platformio
cd firmware
pio run -e esp32dev                 # compile
pio run -e esp32dev -t upload       # flash (board on USB)
pio device monitor                  # watch live telemetry
```

### F. Test on real hardware
Follow `docs/bench_bringup.md`, phase by phase (sensors first, then switches, then soft-start, then solar, then the full black start, then fault tests). Record telemetry and overlay it on the simulation:
```
pip install pyserial
python tools/capture_serial.py --port COM3 --duration 30 --out hw_telemetry.csv
```
```matlab
p = dc_microgrid_params(); sc = define_scenarios(p);
sim = plant_fallback(p, sc(1), 30);
compare_hw_vs_sim('hw_telemetry.csv', sim);
```

---

## 3. Current status

| Item | Status |
|---|---|
| FSM unit tests | 7/7 pass |
| Scenarios T1-T9 (MATLAB) | 9/9 pass |
| Monte Carlo (30 random variations of loads, solar, capacitor, ADC gain, SOC) | 30/30 (requirement: at least 95%) |
| C++ firmware vs MATLAB (SIL), all 9 scenarios | 0 mismatches |
| ESP32 build (PlatformIO) | **Not yet compiled** |
| Real-hardware bench test | **Not yet done** |

**Things the hardware must provide that the simulation assumes:**

1. A **PV over-voltage clamp or shunt**. The sim assumes solar can't push the bus above about 6.48 V when lightly loaded.
2. The **current-sensor zero offset is captured with everything switched off**, which happens in the self-check step.
3. A **hardware fuse or PTC**. Firmware over-current trip takes 5-10 ms, so it is not a fuse replacement.

---

## 4. Repository layout

```
aarambh_hackathon/
  README.md                    <- this file
  run_all.m                    <- MASTER SCRIPT: run this
  params/dc_microgrid_params.m <- ALL parameters (single source of truth)
  src/
    blackstart_fsm.m           <- controller state machine + protection (reference logic)
    load_restoration_engine.m  <- which load to connect/shed, faulty-tier lockout
    plant_fallback.m           <- the simulated circuit (bus capacitor, PV, battery, loads, ADC noise)
    define_scenarios.m         <- T1-T9 + Monte Carlo baseline
    kpi_compute.m              <- measures each run, decides pass/fail
    montecarlo.m               <- 30 randomised runs (parallel on machines with 8+ cores)
    pv_model.m, build_model.m  <- solar panel model and curves
    export_sil_vectors.m       <- writes results/logs/sil_T*.csv
  tests/
    test_fsm_transitions.m     <- 7 unit tests of the state machine
    test_scenarios.m           <- runs scenarios, makes figures
  tools/
    export_params_to_header.m  <- params -> firmware/include/config.h
    run_sil.m                  <- compiles + runs the C++ SIL test (needs g++)
    generate_results_summary.m <- writes docs/results_summary.md
    compare_hw_vs_sim.m        <- overlay hardware telemetry on simulation
    capture_serial.py          <- record ESP32 telemetry to CSV
  firmware/                    <- ESP32 C++ (PlatformIO)
    include/config.h           <- AUTO-GENERATED, do not edit
    src/fsm.cpp, protection.cpp, restoration.cpp  <- ports of the MATLAB logic
    src/main.cpp, sensors.cpp, pwm_soft_start.cpp, auth_rfid.cpp, telemetry.cpp
    test/test_sil_equivalence.cpp
  docs/
    architecture.md            <- design decisions and assumptions
    hardware_mapping.md        <- pin map, sensor wiring
    bench_bringup.md           <- step-by-step hardware bring-up + BOM
    results_summary.md         <- auto-generated results
    HANDOFF_DOCUMENT.md        <- engineering status / change log
  results/                     <- generated figures, tables, logs
  _to_delete/                  <- old files kept for reference, safe to delete
```

## 5. Controller states

| State | What happens |
|---|---|
| S0 BLACKOUT_DETECT | Everything off; confirm the blackout lasts 1 s |
| S1 AUTH_WAIT | Wait for an authorised RFID card (3 bad scans = lockout) |
| S2 SELF_CHECK | Sensor sanity, SOC at least 20%, current-sensor zero calibration |
| S3 SOFT_START_BUS | Ramp the source switch PWM 0 to 100% over 1 s, current-limited |
| S4 BUS_STABLE_DWELL | Hold 2 s, confirm the bus is stable |
| S5 CONNECT_PV | Connect solar if V_pv > V_bus + 0.45 V |
| S6 LOAD_RESTORATION | Connect T1 to T4 one at a time with headroom and SOC checks |
| S7 NORMAL_ISLANDED | Monitor; shed and restore; isolate faulty tiers |
| S8 FAULT_RECOVERY | Everything off, retry with back-off (max 3) |
| S9 LOCKOUT_ALARM | Hard stop; only an authorised RFID card resets it |

## 6. Safety notes
- Low voltage only (12 V DC maximum). Mains side of the SMPS enclosed and isolated.
- Fuse (1.5 A) on the SMPS output; PTC (1 A) on the buck output.
- All MOSFET gates default LOW (off) at boot and on watchdog reset.
- E-stop switch cuts gate-driver supply (hardware all-off).
- Keep breadboard currents at or below 1 A. Flyback diode mandatory on the motor (T3).
- Star ground at the SMPS 0 V.
