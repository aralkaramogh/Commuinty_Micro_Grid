# PS #38 Community Microgrid & Energy Sharing: Carry-Forward Context

Written 2026-10-04. Purpose: let a fresh chat (and a fresh Claude project) pick up the PS #38 work with no loss. Paste or attach this at the start of the new chat.

---

## 1. Where we are

- **Black-start project (Aarambh Hackathon #34, hardware track)** is finished and verified. Folder: `D:\Amogh\MATLAB_Projects\aarambh_hackathon`. Keep it intact.
- We are now considering **PS #38 Community Microgrid & Energy Sharing** as a different problem statement. It is at the **concept/design stage**: no folder, no code yet, no team name chosen.

### PS #38 statement (as given)
An intelligent microgrid controller that detects grid failure, manages locally generated renewable energy and storage, prioritises critical loads, and safely manages grid-connected to islanded transition. Hardware: a prepaid RFID-based energy dispensing meter that lets neighbouring households trade and route localised solar power. A PZEM (AC meter) is provided but not required; we are free to choose other components.

---

## 2. Black-start background (only what matters for PS #38)

**What it is:** a DC solar microgrid black-start controller. A 6 V bus, a battery emulator (12 V SMPS + buck at ~6.5 V), a 6 V/3 W panel, four load tiers, and an ESP32 running a state machine.

**Final verification status:** 7/7 unit tests, 9/9 scenarios (T1-T9), Monte Carlo 30/30, SIL equivalence 0 mismatches (real C++ firmware vs MATLAB tick for tick), `run_all` about 2.5 min. Not done: ESP32 PlatformIO build, bench bring-up, PV over-voltage clamp, tuning from real telemetry.

**Things we built that PS #38 can reuse:**

| Black-start asset | Reuse in PS #38 |
|---|---|
| FSM S0-S9 (blackout, start, soft-start, restoration, normal, S8 fault recovery, S9 lockout) | Islanding sequence and safe re-start of the community bus |
| Soft-start PWM (20 kHz LEDC ramp) | Soft reconnect to the grid emulator and soft pickup of the shared battery |
| Load tiers T1-T4 with SOC gates (0.10/0.25/0.30/0.40) | Critical-load "lifeline" and shed order per household |
| Protections: OC_HARD, leaky I²t, OV, stuck-switch detect, frozen-sensor detect, ACS712 offset capture | Per-household metering and fault isolation |
| Faulty-branch isolation (blame within 0.5 s, 2 strikes lock the tier, strikes clear after 10 s healthy) | Isolating a bad household or branch without dropping the bus |
| RFID auth (RC522, 3 bad cards = lockout) | Prepaid card for each household meter |
| MATLAB digital twin + scenarios + Monte Carlo + SIL test + `config.h` generated from one params file | Same method: simulate first, then export constants to firmware |
| Gate-drive design: low-side IRF3205 (10 Ω gate, 10 kΩ pull-down) for loads; high-side IRF4905 + 2N7000 + 1 kΩ pull-up for sources; E-stop cuts the drivers' 12 V | Same switch topologies; sources must be switched in the + wire because grounds are shared |
| Diagram toolkit `tools/diagrams/svglib.py` | Draw the PS #38 system and wiring diagrams |
| Hardware pin map: GPIO34/35/32/33 sensors, 25/26/27/16/17/21 gates, RC522 on 5/18/23/19/22 | Starting point; INA226 (I²C) replaces the ACS712 analog path for metering |

**Does black start need a 100 % battery?** No. Start requires SOC ≥ 0.20; tiers add as SOC rises.

---

## 3. PS #38 proposed design

### 3.1 Architecture
- **12 V DC community bus.** Safe to handle at a hackathon, easy to source parts for.
- **Hub ESP32** plus **one ESP32 meter per household**. Hub talks to meters over **ESP-NOW** (no router needed).
- **Shared battery:** 12 V LiFePO4 (4S + BMS) preferred, or sealed lead-acid.
- **Grid emulator:** a 12 V SMPS + CC/CV buck behind a **back-to-back MOSFET grid switch**. Unplugging it is the "grid failure".
- **Three households:** two with solar, one without. This makes trading visible.
- **Per-household meter:** INA226 bidirectional metering, RC522 RFID, OLED, high-side load switch.
- **Ledger on the hub**, keyed by card ID (credit balance, kWh bought/sold). **Web dashboard** served from the hub.
- **Islanding:** detect grid loss from bus voltage and grid-side current, open the grid switch, keep critical loads on. **Soft reconnect** by reusing the black-start soft-start.
- **Critical-load lifeline:** a household's critical load keeps running at zero credit.

### 3.2 Bidirectional energy sharing: three options
- **A. Real battery directly on a 12 V bus (recommended).** Needs an 18 V panel + charge controller (MPPT or CC/CV) per solar household, a back-to-back P-MOSFET bidirectional switch, and negative-current handling in the sensing. Simplest and most robust.
- **B. Bidirectional half-bridge DC-DC** (ESP32 MCPWM, IR2104 drivers, inductor). More impressive, much more to debug.
- **C. Multi-node droop control.** Closest to real microgrids; hardest to tune. Stretch goal.

### 3.3 Parts list (first draft)
ESP32 (hub + 3 meters), INA226 modules, RC522 + cards, SSD1306 OLED, IRF4905 / IRF3205 / 2N7000 MOSFETs, TC4427 or IR2104 drivers, 12 V LiFePO4 4S + BMS (or SLA), 12 V SMPS, CC/CV buck modules, 18 V panels + charge controller, fuses/PTCs, 1N5822 diodes, E-stop, 12 V loads (LED bar, fan, resistive). PZEM optional (AC only).

---

## 4. AI/ML energy manager (for the teammate)

Claude Doc: **Community Microgrid Energy Manager: Brief for the AI/ML Lead**
https://claude.ai/code/artifact/80ff37d5-b90e-42ee-a796-1223b93cc7ea

Summary:
- **Inputs:** grid_available, price_buy/sell, pv_w, load_crit_w, load_flex_w, soc, battery specs, household credit.
- **Outputs:** p_batt_w, shed, curtail_pv_w, trades, p2p_price.
- **Model:** energy balance + SOC update equation. Ranked objectives: (1) critical loads are a hard constraint, (2) outage reserve, (3) cost, (4) fairness.
- **Approach ladder:** rule-based baseline, then MPC (cvxpy/PuLP), then ML forecasting (LightGBM/LSTM for PV and load), then RL (gymnasium + Stable-Baselines3) as a stretch.
- **Interface:** MQTT between hub and the manager. Evaluate on cost saved, self-sufficiency, unserved critical energy, fairness.
- **Reference:** Smart Grid Analytics' Solvyn AURA ("Automated Utility Response & Allocation") is the style of product we are echoing.
- **Indian ToD rules** (PIB, 2023 amendment): solar hours (8 h) at least 20 % cheaper; peak at least 10 % higher for residential (20 % for C&I); ToD for non-C&I consumers from 1 Apr 2025. Use these to shape the price signal.

---

## 5. Team / product name work

- Wanted: energy sharing + sustainability + microgrid, Indian touch, mythology angle, a meaningful initial letter like AURA.
- Many names turned out to be **taken** in quick web searches. These were quick checks, **not trademark searches**.
- **No name chosen.** Next step: pick the top 3-5 and clash-check them properly. The shortlist is in `claude/ps38_community_microgrid_notes.md`.

---

## 6. Open decisions

1. Bidirectional approach: A (battery on bus, recommended), B, or C.
2. Battery chemistry: LiFePO4 4S + BMS vs SLA (cost, safety, availability).
3. Number of households and which have solar (proposed 3: two solar, one not).
4. Real grid emulator vs software-only grid-failure flag.
5. Hackathon track and deadline (affects how much hardware vs simulation to commit to).
6. Team name.
7. Whether the AI manager runs on the hub, a laptop, or a cloud broker.

---

## 7. Suggested order of work

1. Lock decisions 1-4 above.
2. Create `D:\Amogh\MATLAB_Projects\community_microgrid`, copy the reusable pieces (diagram toolkit, params-to-header exporter, FSM/protection code, docs structure).
3. Write a params file and a MATLAB/Python **digital twin** of the 12 V bus, shared battery, 3 households, grid switch.
4. Build scenarios: normal day, grid outage, battery low, bad card, faulty household, reconnect.
5. Hand the twin's data format to the AI/ML teammate so the manager can be trained and tested in simulation first.
6. Firmware: meter node, hub, ledger, islanding FSM (adapt black-start FSM), SIL test as before.
7. Bench bring-up in phases (single meter, two meters, battery, grid switch, full island).
8. Dashboard and demo script.

---

## 8. Documents to carry forward

**From the black-start folder (`aarambh_hackathon`)** — read-only references:
- `README.md`
- `docs/architecture.md`
- `docs/hardware_mapping.md` (gate-drive and high-side switch correction)
- `docs/bench_bringup.md` (phase method and BOM style)
- `docs/HANDOFF_DOCUMENT.md` (v2, change log)
- `docs/results_summary.md`
- `docs/diagrams/01_system_architecture`, `02_hardware_wiring`, `03_gate_drive_explained` (.svg and .png)
- `docs/Problem_Statements_Updated (1).docx` (PS #38 text)
- Code to copy: `params/dc_microgrid_params.m`, `src/blackstart_fsm.m`, `src/load_restoration_engine.m`, `src/plant_fallback.m`, `src/kpi_compute.m`, `src/montecarlo.m`, `tools/export_params_to_header.m`, `tools/run_sil.m`, `tools/diagrams/svglib.py`, `firmware/src/{fsm,protection,restoration,sensors,pwm_soft_start,auth_rfid,telemetry}.cpp`, `firmware/test/test_sil_equivalence.cpp`.

**From Claude:**
- This document.
- `claude/ps38_community_microgrid_notes.md` (design summary, AI/ML brief link, naming shortlist).
- `claude/blackstart_project_overview.md` (background only).
- AI/ML brief link in section 4.

---

## 9. Kickoff message for the new chat

> I'm starting the PS #38 Community Microgrid & Energy Sharing project. Read the attached carry-forward context. Black start is finished and lives in `D:\Amogh\MATLAB_Projects\aarambh_hackathon`; reuse its FSM, protections, soft-start, SIL method and diagram toolkit. First, help me settle the open decisions in section 6, then create the new project folder and the digital-twin params file.
