# Architecture and Assumptions

## System Diagram

![System architecture](diagrams/01_system_architecture.svg)

*(PNG copy for slides: `diagrams/01_system_architecture.png`)*

The system has three layers:

1. **Laptop (design and verification).** Every number lives in `params/dc_microgrid_params.m`. The MATLAB digital twin simulates the circuit and runs the controller logic through the T1-T9 scenarios and Monte Carlo. The same parameters are exported to `firmware/include/config.h`. The SIL test replays every scenario through the real C++ firmware to prove it makes identical decisions.
2. **ESP32 controller.** `sensors.cpp` reads 4 analog signals. `protection.cpp` checks for faults every tick. `fsm.cpp` walks through the black-start steps S0-S7, with S8 for faults and S9 for lockout. `restoration.cpp` decides which load to switch next. `auth_rfid.cpp` checks the operator's card. The decisions come out as six GPIO pins.
3. **Power hardware.** Those six pins drive six MOSFET switches through gate drivers: two connect the sources (battery emulator, solar) to the 6 V bus, and four connect the loads. Four sensors (blue) report back to the ESP32.

How the switches and their gates work is explained in [hardware_mapping.md](hardware_mapping.md#how-the-switches-work-mosfet-gates).

## System Configuration

**Selected: Config A - 6V DC Bus (default, all listed parts)**

| Parameter | Value | Source |
|---|---|---|
| Bus nominal | 6.0 V | params |
| Bus band | +-8% (5.52-6.48 V) | params |
| OV trip | 6.60 V | params |
| UV trip | 4.80 V | params |
| Max bus current | 1.0 A | SMPS/buck limit |
| PWM frequency | 20 kHz | params |
| Soft-start ramp | 1.0 s (0 to 100%) | params |

## Assumptions (Exhaustive)

### Storage / Battery
1. No real battery in parts list. 12V SMPS + buck module emulates storage.
2. Buck set to 6.15V. Thevenin: V_oc=6.15V, R_series=0.25 Ohm (no-load bus sits 2.5% above nominal).
3. Virtual SOC via coulomb counting. Capacity: 5 Wh (param).
4. To add real battery: change V_oc, R_series, capacity_Ah in params only.

### Bus
5. Config A: 6V bus. Panel Vmp~6V, direct OR-diode connect, no boost.
6. Config B (12V) modelled but needs boost module (not in parts).

### PV Panel
7. Single-diode model: Isc=0.55A, Voc=7.2V, Imp=0.5A, Vmp=6V, Pmax=3W.
8. n_cell=12 (0.6V/cell, consistent with Voc).
9. Schottky diode (1N5822) for PV OR-ing.

### ACS712
10. Variant assumed: 5A (185mV/A). For 20A: update sensitivity=0.100 in params.
11. Divider: 10k/15k => ratio 0.6 => midpoint at ADC = 1.5V.
12. 16x oversampling + 20ms IIR for noise reduction.

### MOSFETs (IRF3205)
13. Effective Rds(on) = 50mOhm (wiring + contact + partial gate drive).
14. Gate driver supply from 12V SMPS rail (always present).
15. Low-side switching. Common GND mandatory.

### Loads (Config A, 6V rated)
16. T1: 36 Ohm LED bar, ~1W, inrush x1.2 (critical; never shed by priority, only if it is itself the blamed faulty branch). SOC needed: 10%.
17. T2: 47 Ohm resistor, ~0.77W, inrush x1.1. SOC needed: 25% (above the 20% start minimum, so a low-SOC start restores T1 only).
18. T3: 30 Ohm DC motor, 5mH, inrush x4 for 150ms. SOC needed: 30%.
19. T4: 100 Ohm dummy, ~0.36W (lowest priority). SOC needed: 40%.

### Outage Emulation
20. Blackout: SRC_SW MOSFET open + panel covered.
21. Black-start trigger: V_bus < 20% V_nom for > 1s.
22. RFID auth required (or auto_auth flag in simulation).

### Firmware Limits
23. OC trip latency ~1-10ms (FreeRTOS). Hardware fuse mandatory.
24. No temperature sensor (NTC on heatsink recommended).
25. MPPT is simplified P&O, not full MPPT IC.
26. Breadboard limit <= 1A per rail.

## Protection Logic (as implemented, MATLAB = firmware)

| Check | Rule | Result |
|---|---|---|
| Hard over-current | I_src > 1.8 A sustained for 5 ms (single noise spikes ignored) | Fault recovery (retry with back-off) |
| I2t (thermal) | Leaky integral of (I_src^2 - 1.5^2): only current above the 1.5 A continuous rating heats the path; trips at 2.0 A^2.s | Fault recovery |
| Over-voltage | V_bus > 6.6 V | Fault recovery |
| Source switch stuck open | In S6/S7 with duty ~1: measured I_src < 0.05 A while (V_oc - V_bus)/R_series > 1.5 A, for 30 ms | Alarm lockout (S9) |
| Frozen bus-voltage sensor | Filtered V_bus bit-identical for 2 s while the source is connected | Alarm lockout (S9) |
| Bad RFID | 3 invalid scans | Lockout; bus never energised |
| Low SOC at start | SOC < 20% in self-check | Lockout |

The 1.5 A threshold for the stuck-switch check is deliberately large. A 3% ADC gain error on a 6.2 V bus is about 0.19 V, which through 0.25 Ohm looks like 0.75 A of "expected" current. A smaller threshold caused false trips in Monte Carlo.

**ACS712 zero offset:** captured in S2 (all gates off) and subtracted from every later current reading. On hardware, `sensors.cpp` also calibrates at boot.

## Load Restoration and Faulty-Branch Isolation

- One load step at a time, at least 1.5 s apart, highest priority first.
- **Headroom check:** P_step = P_nom x inrush x 1.2 (cold) x 1.15 (margin) must fit within the *short-term* source rating ((1.5 A - I_src) x V_bus) plus solar. Steady state is separately limited to I_src < 0.8 A. Using the short-term rating is valid because the largest inrush (motor) lasts only 150 ms.
- **Shedding:** if the bus is stressed (V_bus < 90%, I_src > 1.5 A, or SOC < 15%), shed one tier per 10 ms, lowest priority first (T4, then T3, then T2). A shed tier stays off for at least 5 s.
- **Blame:** if stress appears within 0.5 s of connecting a load, that load is shed (not the lowest priority) and gets a strike. Shedding then pauses 100 ms so filtered sensors can settle. **2 strikes lock that tier out** (faulty branch isolated); the strikes clear after 10 s of healthy running.

## Simulation Model Assumptions

- Plant step 20 us forward-Euler; FSM 10 ms; ADC 1 ms with 16x oversampling, +-3 LSB noise, 20 ms IIR filter.
- **PV curtailment:** PV current ramps to zero between 1.03 x and 1.08 x V_nom. This represents a PV over-voltage clamp or shunt that the **hardware must provide**. Without it, solar alone pushes a lightly loaded bus over the 6.6 V trip.
- Battery emulator = Thevenin source clamped to 0 to 1.5 A (no reverse current).
- Monte Carlo varies: load R +-20%, irradiance +-15%, bus C +-10%, ADC gain +-3%, initial SOC 20-90%.

## Scale Factor
p.SCALE = 1 (prototype). For a 1kW system: multiply P by 333, scale V to 48V bus, replace parts with rated equivalents.

## Next Steps
- Real Li-ion battery pack (2S/3S)
- Boost module for 12V Config B
- PCB design (>1A requires copper planes)
- NTC thermistor for thermal protection
- True MPPT controller IC
- AC inverter stage
- Wi-Fi/MQTT telemetry dashboard
