# Hardware Mapping & Signal Chain

## Wiring Overview

![Hardware wiring](diagrams/02_hardware_wiring.svg)

*(PNG copy: `diagrams/02_hardware_wiring.png`.) Coloured tags are net labels: `G1`-`G6` are the six gate-driver outputs, and `→GPIOxx` is a sensor output going to that ESP32 pin.*

## How the switches work (MOSFET gates)

![Gate drive explained](diagrams/03_gate_drive_explained.svg)

- A **MOSFET** is an electronic on/off switch for the power current (drain to source). Its **gate** is the control input: a voltage between gate and source closes the switch, and 0 V opens it.
- The ESP32 has **six gate pins**, one per switch. **GPIO HIGH = switch ON**, **GPIO LOW = switch OFF**. They all start LOW at boot, so everything is off.
- An ESP32 pin only gives 3.3 V, but an IRF3205 needs about 10 V on its gate to switch fully on. So each pin goes through a **gate driver channel (TC4427)**, which turns 3.3 V logic into a 0 V / 12 V gate signal. The drivers run from the 12 V supply through the **E-stop**: pressing it removes their 12 V and every switch opens.

| GPIO | Switch | Switches what | Type |
|---|---|---|---|
| 25 | SRC_SW (Q_SRC) | battery emulator onto the bus (**PWM 20 kHz** soft-start) | high-side P-MOSFET |
| 26 | PV_SW (Q_PV) | solar panel onto the bus | high-side P-MOSFET |
| 27 | LOAD1 (Q_L1) | T1 LED bar (critical) | low-side N-MOSFET |
| 16 | LOAD2 (Q_L2) | T2 47 Ohm | low-side N-MOSFET |
| 17 | LOAD3 (Q_L3) | T3 fan motor | low-side N-MOSFET |
| 21 | LOAD4 (Q_L4) | T4 100 Ohm | low-side N-MOSFET |

**Load switches (low-side):** load + goes to the bus, load - goes to the IRF3205 drain, and its source goes to GND. Gate path: GPIO, TC4427 channel, 10 Ohm, gate, with a 10 kOhm gate-to-GND pull-down.

**Source switches (high-side):** a P-MOSFET (IRF4905) sits in the + wire. Source side: buck through D1 (or panel through D2). Drain side: the bus. A 1 kOhm resistor from gate to source holds it OFF. A small 2N7000 (driven by a TC4427 channel, with a 10 kOhm gate pull-down) pulls the gate to 0 V, giving Vgs of about -6 V, which turns it ON. The 1 kOhm value keeps turn-off fast enough for the 20 kHz soft-start PWM.

> **Design correction (2026-10-02):** earlier versions of this file said to use low-side switching for every switch. That cannot work for the two **sources**. Their minus terminals are tied to the common star ground, which the sensors and drivers need, so a switch in a source's minus wire is bypassed. The sources therefore use high-side P-MOSFETs as above. Loads stay low-side. Also add **D1 (1N5822)** in the battery-emulator path: it stops the bus back-feeding the buck, matching the simulation's no-reverse-current assumption. Set the buck to about 6.5 V so the bus sees about 6.15 V after D1's drop.


## Pin Map (ESP32-WROOM-32, ADC1 only)

| Signal | Sensor | ESP32 Pin | Justification |
|---|---|---|---|
| V_bus | 0�25V module #1 | GPIO34 (ADC1_CH6) | Input-only pin, ADC1, no boot conflict |
| V_pv  | 0�25V module #2 | GPIO35 (ADC1_CH7) | Input-only pin, ADC1 |
| I_src | ACS712 #1 + divider | GPIO32 (ADC1_CH4) | ADC1, no conflict |
| I_load | ACS712 #2 + divider | GPIO33 (ADC1_CH5) | ADC1, no conflict |
| SRC_SW | Gate driver IN | GPIO25 (LEDC PWM) | LEDC ch0, 20 kHz soft-start |
| PV_SW  | Gate driver IN | GPIO26 | Digital output |
| LOAD1  | Gate driver IN | GPIO27 | Not a strapping pin |
| LOAD2  | Gate driver IN | GPIO16 | UART2 RX reconfigured; not JTAG |
| LOAD3  | Gate driver IN | GPIO17 | UART2 TX reconfigured |
| LOAD4  | Gate driver IN | GPIO21 | I2C SDA reconfigured (no I2C used) |
| RC522 CS  | SPI | GPIO5  | Default SPI CS, no conflict |
| RC522 SCK | SPI | GPIO18 | SPI SCK (shared with LOAD pin budget resolved) |
| RC522 MOSI| SPI | GPIO23 | SPI MOSI |
| RC522 MISO| SPI | GPIO19 | SPI MISO |
| RC522 RST | GPIO | GPIO22 | I2C SCL reconfigured |
| LED status| Output | GPIO2 | On-board LED |
| Buzzer    | Output | GPIO4 | No boot conflict |

> **GPIO12 avoided**: GPIO12 is a strapping pin (MTDI) � if HIGH at boot, sets flash voltage to 1.8V and bricks the module. Do NOT use for gates.
> **GPIO34, 35**: Input-only, cannot be used as outputs. Correctly assigned to ADC inputs.
> **ADC2 (GPIO0,2,4,12�15,25�27)**: Not used for ADC reads to avoid Wi-Fi conflict (even though Wi-Fi is not enabled currently). GPIO25�27 are used as PWM/digital OUT, not ADC in.

## ACS712 Signal Chain

```
Bus current --[ACS712-5A]-- Vout = 2.5V + I � 0.185 V/A (range 0�5V)
                             �
                         [10kO / 15kO divider] -- scale �0.6
                             �
                         ESP32 ADC pin (0�3.0V at �5A)
                         (midpoint at I=0: 2.5�0.6 = 1.5V)
```

**Calibration note:** At I=0 the ADC should read 1.500V. `sensors_calibrate_offsets()` measures this at boot with loads off and stores the offset.

**Noise:** ACS712-5A has ~10�20 mA rms noise at 80 kHz BW. At 1 kHz sampling with 16� oversampling and 20 ms IIR, effective noise floor � 5 mA rms � sufficient for this design (min meaningful current ~50 mA).

**Resolution:** 185 mV/A � 0.6 divider = 0.111 V/A at ADC. With 12-bit ADC and 3.3V ref: LSB = 0.806 mV ? current resolution = 0.806/111 � 7 mA/count.

## Voltage Sensor Signal Chain

```
Bus voltage --[�5 resistor divider module]-- Vout = Vbus/5
                                              �
                                         ESP32 ADC (0�3.3V covers 0�16.5V bus)
```
**Coverage:** At Vbus = 6.6V (OV trip): ADC = 1.32V ? (within 3.3V ref)

## MOSFET Gate Drive (summary)

- Load switches: **IRF3205** N-MOSFET, low-side, gate driven to 12 V by a TC4427 channel (needs Vgs about 10 V; Rds(on) is about 8 mOhm).
- Source switches: **IRF4905** P-MOSFET, high-side, gate pulled to 0 V by a 2N7000 (Vgs about -6 V; plenty for 1.5 A or less).
- Drivers: **3x TC4427** (dual, non-inverting; 3.3 V logic inputs are valid since VIH is 2.4 V or less), VDD = 12 V via the E-stop, with a 10 kOhm pull-down on every driver input.
- **Flyback diode** across the T3 motor (1N4007 or SS34) is mandatory.
- See the diagram above for the exact circuits.

## Common Ground Rule

All grounds (SMPS 0V, buck 0V, ESP32 GND, ACS712 GND, gate driver GND) **must be at the same potential**.
Run a star-ground from the SMPS 0V terminal.

## Fuse / PTC

- Fuse (1.5A) on SMPS 12V output
- PTC resettable fuse (1A, e.g. MF-R110) on buck module output (the 6V rail)
- This provides the hardware short-circuit protection that firmware cannot achieve in < 1ms

## E-Stop

Add a normally-closed switch in series with the gate-driver VDD (12V) supply.
Opening this switch de-energises all gates immediately (hardware-level, < 1�s).

## Breadboard Current Limit

Standard breadboards are rated ~1�2A. Keep **total bus current = 1A**. All loads in this design total:
- T1: 0.17A, T2: 0.13A, T3: 0.20A, T4: 0.06A ? total � 0.56A ?

## Precharge / Inrush for Capacitive Loads

The 1000�F bus capacitor charges through the SRC_SW MOSFET during soft-start.
At duty = 0.01 (1%), Rseries_effective � Rseries/duty � 25O ? peak I = (Vsrc - Vbus)/25O < 250mA ?
PWM ramp ensures inrush = I_inrush_max = 1.5A.
