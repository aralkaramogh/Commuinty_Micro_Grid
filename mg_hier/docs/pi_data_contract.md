# Pi data contract (MQTT) - for the AI/ML team

Broker: Mosquitto on the Pi, port 1883, no anonymous users, passwords + ACL
(`docs/mosquitto/`, generated from `pi/pi_acl.m`). Payloads are JSON.
Every message has: `v` (format version, now 1), `tick`, `sim_time` ("HH:MM:SS"
simulated clock), `sim_s` (seconds since scenario start). Use sim time, not wall
time: the simulation can run faster or slower than real time.
Rule: fields are only ever ADDED, never renamed or removed, within a version.

| topic | rate | who reads | content |
|---|---|---|---|
| mg/state | 1 s | dash, ai | mode, flags, heartbeat, grid {available, voltage_v, frequency_hz, p_w, q_var, breaker}, bus {voltage_v, frequency_hz, dtheta_deg}, bess {soc_pct, p_w, q_var, p_set_w, q_set_var, fault, max_charge_w, max_discharge_w, energy_kwh}, pv {community_w, houses_w, total_w}, loads {total_w}, price_rs_kwh, ai_status, sharing {sellers, sold_wh, buyers, bought_wh} |
| mg/node/H1, H2, CL | 1 s | dash, ai | node_id, link (real/virtual), online, meter {...}, relays {critical_on, flexible_on}, protection (ok/tripped/locked), node_comm_lost, energy {import_wh, export_wh}, status_code |
| mg/node/SB | 1 s | dash, ai | bess {soc_pct, p_w, q_var, fault}, inverter {p_applied_w, q_applied_var, clamped, sync}, pv_p_w |
| mg/house/H1/account (H2) | 5 s | dash, ai, that house | balance_rs, credit_ok, flexible_allowed, price_rs_kwh, import_wh, export_wh, bought_from_peers_wh, sold_to_peers_wh, status_code |
| mg/event | on change | dash, ai | type (mode, protection, card, refused), node, text |
| mg/ack/op, mg/ack/ai, mg/ack/user/H1 | per request | sender | id, accepted, reason |
| mg/ai/<kind> (pv_forecast, load_forecast, anomaly, carbon) | AI's choice | dash | published BY the AI service: v, sim_s, value, unit, horizon_min, model (the main controller ignores it) |

Dashboard and AI requests (the main controller decides; it can refuse):
| topic | sender | payload |
|---|---|---|
| mg/cmd/op/restrict | dash | id, t_sent, target (H1/H2/CL), value 1 = hold flexible load off / 0 = release, ttl [s] (<= 3600) |
| mg/cmd/user/H1/user_flex | H1 | id, t_sent, target H1, value 0 = my flexible load off / 1 = back on, ttl |
| mg/cmd/ai/ai_advice | ai | id, t_sent, p_bess [W] (+ discharge), shed_mask (bit0 H1, bit1 H2, bit2 CL), price [Rs/kWh] |

Refusal reasons: duplicate id, expired (older than 10 s on arrival), source not
allowed, unknown target, not your house, ttl out of range, bad value, critical
loads cannot be switched off, unknown command, price refused (rest accepted).
AI advice must be repeated: after 30 s without advice the rules take over.

status_code bits: 1-2 protection (1 tripped, 2 locked), 4 shed (low battery),
8 no credit, 16 card locked, 32 shed (under-frequency), 64 shed (AI), 128 restricted
(operator), 256 off by user, 512 node lost the main controller, 1024 node offline.

Carbon, forecasts and anomaly detection are computed on the Pi from these data.
Example payloads: results/pi_msgs/*.json (written by run_all_hier).
