# Bench Bring-Up Guide

## Safety Checklist (Before Powering Anything)

- [ ] SMPS is enclosed; mains wiring not exposed
- [ ] 1.5A fuse on SMPS 12V output
- [ ] 1A PTC on buck 6V output
- [ ] E-stop switch (NC) in series with gate-driver VDD (12V)
- [ ] All gate pins default LOW confirmed (flash ESP32 and measure)
- [ ] Common GND verified with multimeter (0 Ohm SMPS-GND to ESP32-GND)
- [ ] Flyback diodes on Tier 3 motor load

---

## Phase A: Power electronics OFF, sensors only

1. Connect ESP32 and USB. Flash firmware.
2. Open serial monitor at 115200 baud.
3. Check telemetry header: 	_ms,state,vbus,vpv,isrc,iload,soc,duty,load_mask,fault
4. Verify all readings are ~0 (bus unpowered).
5. Confirm GPIO states: all LOAD/SRC/PV pins LOW (measure with meter).

---

## Phase B: Calibrate ACS712 Offsets

1. Keep all loads DISCONNECTED, SRC_SW open (duty=0).
2. Boot ESP32. Watch serial for: [CAL] I_src_off=0.000A I_load_off=0.000A
3. Acceptable: offsets within +/-0.05A. If larger, check divider resistors.
4. Repeat calibration by pressing EN (reset) on ESP32.

---

## Phase C: Test Each MOSFET Gate

1. Replace each load with a 100 Ohm / 2W resistor and a voltmeter.
2. In MATLAB, run lackstart_fsm in a forced state that enables LOAD1.
3. OR: use Arduino Serial command (add a debug override in main.cpp).
4. Measure: voltage across resistor = 6V (minus Rds_on drop ~5-10mV).
5. Repeat for LOAD2, LOAD3, LOAD4, PV_SW, SRC_SW (at duty=100%).

---

## Phase D: Soft-Start into Resistive Load

1. Connect 47 Ohm resistor to bus output (Tier 2 load position).
2. Keep all LOAD gates open except SRC_SW.
3. Initiate black-start: connect authorised RFID tag (or set auto_auth=true in firmware debug).
4. Observe on oscilloscope / serial plot:
   - V_bus rises smoothly 0 -> 6V over ~1-2s (duty ramp).
   - I_src stays below 1.5A.
   - FSM transitions: S0 -> S1 -> S2 -> S3 -> S4.
5. Measure: V_bus steady-state = 6.0V +/- 5%. I_src = 6V/47Ohm = 0.128A.

---

## Phase E: Connect Solar Panel

1. Cover panel. Power up bus (Phase D).
2. Expose panel to light.
3. Observe: V_pv rises above V_bus + 0.45V (diode drop + margin).
4. FSM should close PV_SW (S5). Verify PV_SW gate is HIGH.
5. Measure I_pv = I_load - I_src (should be positive in sunlight).

---

## Phase F: Full Black-Start T1 (Manual)

1. Disconnect SMPS from bus (blackout condition).
2. Cover panel.
3. Wait for V_bus to drop to 0V; confirm FSM state = S0 (BLACKOUT_DETECT).
4. Reconnect SMPS.
5. Present authorised RFID tag.
6. Watch all 4 load tiers connect in order (serial log).
7. Verify time-to-bus-up < 5s, V_bus 6V +/- 5%, all tiers on.

---

## Phase G: Overload / Fuse Test

1. Connect a short circuit (< 1 Ohm) across the load bus through a 2A fuse.
2. Initiate black-start. The PTC or fuse should blow before I_src > 1.8A.
3. If firmware trips first: check serial log for FAULT_OC_HARD or I2T.
4. Replace fuse. Verify E-stop switch works (open it: all gates go LOW immediately).

---

## Phase H: Protection Feature Checks (match the simulation scenarios)

| Test | How | Expected (from simulation) |
|---|---|---|
| PV over-voltage clamp (T1, light load) | Sunny, only T1 on | V_bus stays at or below about 6.5 V. If it reaches 6.6 V you get an OV trip: the PV clamp/shunt is missing or mis-set |
| Faulty branch (T7) | After full restore, short T2 through a 2 A fuse with about 0.5 Ohm | Loads shed within about 20 ms; T2 retried once about 6 s later, then locked out; T1, T3 and T4 come back and stay on |
| Source switch stuck (T6) | Pull the SRC_SW gate wire while running | Lockout (S9) within about 50 ms; serial shows SWITCH_FAULT |
| Frozen sensor (T8) | Disconnect the V_bus divider output and hold it at a fixed voltage | Lockout after 2 s; SENSOR_FROZEN. Note: real ADC noise usually prevents bit-identical readings, so also check that a *floating* input is caught by the sanity limits |
| Bad RFID (T9) | Scan an unregistered card 3 times | Lockout; the source switch never turns on |

---

## Calibration Procedure (HW vs Sim)

### Step 1: Capture real telemetry
`
# Windows PowerShell - capture 30s of serial data
python tools/capture_serial.py --port COM3 --duration 30 > hw_telemetry.csv
`

### Step 2: Run MATLAB comparison
`matlab
p  = dc_microgrid_params();
sc = define_scenarios(p);
sim_results = plant_fallback(p, sc(1), 30);     % sc(1) = T1 nominal sunny start
compare_hw_vs_sim('hw_telemetry.csv', sim_results);
`
(Capture needs `pip install pyserial`; `tools/capture_serial.py` keeps only the CSV rows and echoes debug lines.)

### Step 3: Interpret discrepancies
| RMSE > 0.5V on V_bus | Adjust VSENS_DIV in config.h or divider resistors |
| I offset > 50mA | Re-run calibrate_offsets(), update ACS_OFFSET_ADC |
| Time delays off by > 0.5s | Check p.bus.C (actual capacitance may differ from 1000uF) |
| Inrush higher than sim | Reduce C_bus or increase SS_T_RAMP_S in config.h |

### Step 4: Update params and re-flash
Edit params/dc_microgrid_params.m, re-run 	ools/export_params_to_header.m, re-flash firmware.

---

## BOM (Bill of Materials)

| Part | Qty | Role | Notes |
|---|---|---|---|
| ESP32-WROOM-32 dev board | 1 | Controller | Any 38-pin variant |
| ACS712-5A module | 2 | Current sensors | 5A version, 185mV/A |
| 0-25V voltage sensor module | 2 | V_bus, V_pv | Has onboard 1/5 divider |
| IRF3205 N-MOSFET | 4 | Load switches Q_L1-Q_L4 (low-side) | TO-220, heatsink above 0.5 A |
| IRF4905 P-MOSFET | 2 | Source switches Q_SRC, Q_PV (high-side) | TO-220; see hardware_mapping.md |
| 2N7000 small N-MOSFET | 2 | Pull the P-MOSFET gates low | TO-92 |
| TC4427 dual gate driver | 3 | 6 channels: 3.3 V logic to 12 V gates | DIP-8, 0.1 uF decoupling on each VDD |
| RC522 RFID module | 1 | Auth | 13.56MHz, SPI |
| 12V 10A SMPS | 1 | Storage emulator / supply | Enclosed, mains-isolated |
| Adjustable buck module | 1 | Battery emulator | Set to about 6.5 V (bus sees about 6.15 V after D1) |
| 6V 3W mini solar panel | 1 | PV source | |
| 1N5822 Schottky diode | 2 | D1 (buck to Q_SRC), D2 (panel to Q_PV) | Block reverse current |
| 1N4007 diode | 4 | Flyback on inductive loads | |
| 470uF / 1000uF 16V electrolytic | 2 | Bus decoupling | |
| 10k Ohm resistor | 2 | ACS712 divider (top) | 1/4W |
| 15k Ohm resistor | 2 | ACS712 divider (bottom) | 1/4W |
| 10k Ohm resistor | 12 | Gate pull-downs (4 IRF3205 + 2 2N7000) and driver-input pull-downs (6) | 1/4W |
| 1k Ohm resistor | 2 | P-MOSFET gate-source pull-ups | 1/4W |
| 10 Ohm resistor | 4 | IRF3205 gate series resistors | 1/4W |
| 47 Ohm 5W resistor | 1 | Tier 2 load | |
| 100 Ohm 2W resistor | 1 | Tier 4 load | |
| 6V LED bar + 36 Ohm series R | 1 | Tier 1 load | |
| Small 6V DC fan/motor | 1 | Tier 3 load | |
| 1.5A fuse + holder | 1 | SMPS output protection | |
| 1A PTC (MF-R110) | 1 | Buck output protection | |
| NC switch | 1 | E-stop in the TC4427 12 V supply | Opens every switch |
| Breadboard (800 tie) | 1-2 | Prototyping | Max 1A per rail |
| Jumper wires | assorted | | Use 24AWG for signal, 20AWG for power |

**Optional additions:**
- NTC 10k thermistor on IRF3205 heatsink (connect to GPIO34 after remapping)
- Boost module (XL6009) for Config B (12V bus)
- 2S Li-ion pack + BMS (replaces SMPS storage emulator)
