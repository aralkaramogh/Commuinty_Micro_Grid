# USB serial protocol: MATLAB (AC plant) <-> ESP32 (controller)

115200 baud, one text line per message. Lockstep: one `M` line per tick, the ESP32 answers with the `C` line of the same `seq`.

## M: measurements (MATLAB -> ESP32)

`M,seq,t_ms,v_grid,f_grid,v_c,f_mg,dtheta,p_pcc,q_pcc,p_bess,q_bess,soc,bess_status,p_cl,q_cl,p_cpv,fb,card_house,card_uid,ai_valid,ai_p,ai_mask,ai_price` then per house `,v_h,i_h,p_load,q_load,p_pv,q_pv`

| Field | Unit | Meaning |
|---|---|---|
| v_grid, f_grid | V, Hz | utility side of the grid breaker (sync-check relay). f_grid = 0 when the grid is dead |
| v_c, f_mg | V, Hz | community bus (microgrid side) |
| dtheta | deg | phase of microgrid minus grid (0 while connected) |
| p_pcc, q_pcc | W, var | power through the grid breaker, + = microgrid imports |
| p_bess, q_bess | W, var | BESS inverter, + = discharging / injecting vars |
| soc | 0..1 | from the battery BMS |
| bess_status | - | 0 ok, 1 inverter tripped |
| p_cl, q_cl, p_cpv | W, var, W | community load and community PV plant |
| fb | bits | relay feedback (same layout as `bits`) |
| card_house, card_uid | - | RFID tap this tick, 0 = none |
| ai_valid, ai_p, ai_mask, ai_price | -, W, bits, Rs/kWh | AI advisor command (0 = none). ai_mask bit k = shed house k+1's flexible load |
| v_h, i_h | V, A | per house at its meter |
| p_load, q_load | W, var | per house appliances |
| p_pv, q_pv | W, var | per house rooftop inverter (q from volt-var) |

## C: commands (ESP32 -> MATLAB)

`C,seq,bits,mode,p_set,q_set,flags,ai_status,price` then per house `,bal,hcode`

- `bits`: bit0 grid breaker closed, bit1 synchronise request, house k (0-based): bit 2+2k tie (critical side), bit 3+2k flexible load.
- `mode`: 0 BOOT, 1 GRID, 2 ISLAND, 3 RESYNC.
- `p_set, q_set`: BESS set-points [W, var], used by the inverter only while grid-connected. In island the BESS follows physics (grid-forming).
- `flags`: +1 grid healthy, +2 relay feedback mismatch, +4 card reader locked, +8 house locked out, +16 some flexible load shed, +32 BESS fault, +64 AI command active, +128 E-stop.
- `ai_status`: +1 AI active, +2 BESS request clamped to the safe range, +4 price refused, +8 BESS request ignored (islanded).
- `price`: Rs/kWh in use. `bal`: prepaid balance Rs.
- `hcode`: 0 ok / 1 tripped / 2 locked, +4 shed (battery), +8 no credit, +16 card locked, +32 shed (under-frequency), +64 shed (AI).

## Other lines
- `R` -> `READY`: reset. `T{json}`: telemetry every 5 ticks (docs/data_contract.md). `E,parse`: bad M line.
