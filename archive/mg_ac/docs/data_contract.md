# Data contract for the AI/ML team (AC model)

Everything the microgrid gives the AI layer, and the one command it accepts back.
Built from Zakir's AI/ML ideas and the hardware-input list. Load data is synthetic.

## 1. What you get

| Source | Rate | File / channel |
|---|---|---|
| Live telemetry from the ESP32 | every 5 s | `T{json}` lines on USB (later MQTT to the Pi) |
| Event scenarios at 1 s | 1 row / s | `results/tables/S1_normal_day_ai_1s.csv`, `S2_grid_outage_ai_1s.csv` |
| Training set | 1 row / 60 s | `results/datasets/ai_dataset_60s.csv` (120 random days, `day_id` column) |

Columns (same names in CSV and JSON): `timestamp, mode, irradiance_wm2,
grid_available, grid_voltage_v, grid_frequency_hz, grid_p_w, grid_q_var, grid_breaker_closed,
bus_voltage_v, bus_frequency_hz, bess_soc_pct, bess_p_w, bess_q_var, bess_fault,
comm_load_p_w, comm_load_q_var, comm_pv_p_w, price_rs_kwh, ai_status`, and per house
`hN_voltage_v, hN_current_a, hN_load_p_w, hN_load_q_var, hN_pv_p_w, hN_pv_q_var, hN_net_p_w,
hN_import_wh, hN_export_wh, hN_balance_rs, hN_critical_on, hN_flexible_on, hN_status_code`.

Signs: grid_p_w + = importing; bess_p_w + = discharging; hN_net_p_w + = house exporting.
AC extras the DC model did not have: reactive power (var), frequency, bus voltage per house.
BESS limits: max charge 4000 W, max discharge 5000 W, 10 kWh, inverter 6 kVA.

## 2. Labels in the training set (never visible to the hub)

`label_grid_outage`, `label_grid_abnormal` (sag / bad frequency),
`label_frozen_sensor_house` (0 or house number: that house's load meter stuck),
`label_abnormal_load_house` (high-impedance fault drawing ~2.6 kW extra),
`label_card_abuse_house` (bad RFID taps). Split train/test **by day_id**, not randomly.

## 3. What you can send back (one command, checked by the ESP32)

`ai_valid, ai_p (W, + discharge), ai_mask (bit k = shed house k+1 flexible load), ai_price (Rs/kWh)`

The ESP32 keeps the final say:
- BESS request used only while grid-connected; clamped to [-4000, 5000] W and never below SOC 30 % (outage reserve); otherwise `ai_status +2`.
- In island the BESS follows physics; the request is ignored (`ai_status +8`).
- Shed mask only touches flexible loads; critical loads are never switched by AI.
- Price accepted only in 2-15 Rs/kWh (`ai_status +4` if refused).
- No new command for 30 s -> AI dropped, rules take over, price back to 6 Rs/kWh.

## 4. Mapping to the AI ideas
- Solar / load forecasting: `irradiance_wm2`, `hN_pv_p_w`, `comm_pv_p_w`, `hN_load_p_w`, `timestamp`.
- Forecast-aware shedding / battery planning: `bess_soc_pct`, mode, loads; act through `ai_p` and `ai_mask`. Baseline to beat = the rule controller already in the data.
- Anomaly detection: voltage/current/power columns + the labels above.
- Dynamic pricing: `ai_price`; ledger and balances show the effect.
