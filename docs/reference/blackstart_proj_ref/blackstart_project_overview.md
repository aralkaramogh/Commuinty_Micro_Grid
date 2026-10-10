# DC Solar Microgrid Black-Start Controller: Project Overview & Status
Aarambh Hackathon #34 (hardware track). Code lives on Amogh's laptop at `D:\Amogh\MATLAB_Projects\aarambh_hackathon`. Last updated 2026-10-02.

## What it is
A 6 V DC microgrid on a breadboard: a solar panel (6 V/3 W), a "battery" emulated by a 12 V SMPS + buck (set to about 6.5 V, about 6.15 V at the bus after diode D1) with a virtual SOC, and 4 prioritised loads (T1 LED critical, T2 47 Ohm, T3 DC fan motor, T4 100 Ohm). An ESP32 performs a safe **black start** from total blackout: detect, RFID authorise, self-check, PWM soft-start, stable dwell, connect PV, restore loads one at a time by priority and headroom, then run normally with load shedding and protection.

Two halves:
- **MATLAB digital twin** (`params/`, `src/`, `tests/`, `run_all.m`): simulated plant plus the reference controller logic.
- **ESP32 C++ firmware** (`firmware/`, PlatformIO): a port of the same logic. `config.h` is generated from the MATLAB params.

## Diagrams (in the code folder, `docs/diagrams/`, SVG + PNG)
- `01_system_architecture`: laptop/MATLAB, ESP32 firmware modules, power hardware, and the links between them.
- `02_hardware_wiring`: full power path, sensors, the 6 switches with net labels G1-G6, ESP32 pin map, gate drivers, E-stop, RFID.
- `03_gate_drive_explained`: what a MOSFET gate is, the low-side load-switch and high-side source-switch circuits, soft-start PWM, and safety defaults.
- Generator scripts: `tools/diagrams/make_0*.py`. Embedded in `README.md`, `docs/architecture.md` and `docs/hardware_mapping.md`.

## How the switches work
Six GPIOs, one per MOSFET; HIGH = ON. GPIO25 SRC_SW (PWM 20 kHz), 26 PV_SW, 27/16/17/21 LOAD1-4. Each pin goes through a TC4427 driver channel (3.3 V logic to a 12 V gate), and the drivers' 12 V runs through the E-stop.
- Loads: IRF3205 N-MOSFET **low-side** (10 Ohm gate resistor, 10 kOhm pull-down).
- Sources: IRF4905 P-MOSFET **high-side** (1 kOhm gate-to-source pull-up; a 2N7000 pulls the gate low to turn it on). D1/D2 1N5822 block reverse current.
- **Design correction 2026-10-02:** the original docs said low-side for all switches. That cannot work for the sources: their minus terminals are tied to the common ground, so a minus-wire switch would be bypassed. The BOM and hardware_mapping.md have been updated (adds 2x IRF4905, 2x 2N7000, 3x TC4427, resistors).

## How to run
In MATLAB: `cd('D:\Amogh\MATLAB_Projects\aarambh_hackathon'); run_all` takes about 2.5 min. Results go to `docs/results_summary.md` and `results/figures/scenario_T*.png`. All parameters are in `params/dc_microgrid_params.m`. The README has the full user guide.

## Verified status (2026-10-02)
- FSM unit tests: 7/7
- Scenarios T1-T9: 9/9 pass. T1 bus up 1.05 s; tiers restored at 4.97, 6.47, 7.97, 9.47 s. T3 low SOC restores T1 only. T6 stuck switch, T8 frozen sensor and T9 bad RFID end in lockout. T7 shorted T2 is isolated after 2 strikes while T1, T3 and T4 keep running.
- Monte Carlo: 30/30 (requirement at least 95%)
- C++ firmware SIL equivalence vs MATLAB: 0 mismatches on all 9 scenarios
- ESP32 build and bench testing: **not done yet**

## Key decisions
- Leaky I2t (only current above 1.5 A heats); OC trip needs 5 ms sustained.
- Restoration headroom uses the short-term 1.5 A source rating (motor inrush is 150 ms).
- Stuck-switch detection threshold 1.5 A expected current (sized above ADC gain-error effects).
- Tier 2 minimum SOC is 0.25 (above the 0.20 start minimum).
- The sim assumes a PV over-voltage clamp (curtail 1.03 to 1.08 x V_nom); **the hardware must provide one**.
- ACS712 zero offset captured in S2 and subtracted.
- Plant sim is 34-42x faster after the 2026-10-02 rewrite (identical results).

## Open items
1. `pio run -e esp32dev`: first firmware build (main/sensors/pwm/rfid/telemetry never compiled).
2. Bench bring-up phases A-H (`docs/bench_bringup.md`), including the PV clamp and the T6/T7/T9 protection tests. Wire the source switches high-side as in diagram 03.
3. Tune params from bench telemetry (`tools/capture_serial.py` + `tools/compare_hw_vs_sim.m`).
4. Optional: install g++ on Windows (`winget install BrechtSanders.WinLibs.POSIX.UCRT`) so `run_all` also runs the C++ SIL check.

Detailed change log: `docs/HANDOFF_DOCUMENT.md` in the code folder.