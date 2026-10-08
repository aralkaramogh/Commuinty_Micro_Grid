# mg_hier - hierarchical AC community microgrid (Stage A)

Plant in MATLAB -> 4 node controllers (ESP32: H1, H2, CL, SB) -> main controller
(MATLAB logic) -> Raspberry Pi (MQTT, dashboards, AI). The verified single-controller
version is in `../mg_ac` (Plan B, untouched).

```
 PLANT (physics, MATLAB)                 grid, H1 (PV), H2 (no PV), solar+BESS, community load
   | meter line per node (USB)           PCC meter + grid breaker go straight to the main controller
 NODES (ESP32 or MATLAB twin)            local: over-current trip, critical hold, BESS limits,
   | reports up / commands down          comms-loss fallback, RFID, LEDs
 MAIN CONTROLLER (MATLAB)                modes, sync, BESS dispatch, shedding, ledger, P2P,
   | MQTT (ACL)                          checks every request
 PI                                      broker, dashboards, AI (AI/ML team)
```

## Run (simulation only, no boards, no Pi)
`run_all_hier` in MATLAB: unit tests, 13 scenarios, Monte Carlo, node SIL (needs g++).

## Run with real node boards
Flash `firmware_node/mg_node` (same sketch on every board), set `PORTS` in
`hil/run_hil_nodes.m`, run it. Nodes not listed stay virtual. Each real reply is
compared with the MATLAB twin.

## Folders
| folder | what |
|---|---|
| params/hier_params.m | every number (single source of truth) |
| plant/ | physics only (phasor power flow, BESS, PV, loads) |
| nodes/ | node rules (MATLAB twins of the firmware) |
| main/ | main controller + its input firewall |
| comms/node_lines.m | text lines MATLAB <-> nodes (docs/node_protocol.md) |
| pi/ | MQTT messages, ACL, request helper (docs/pi_data_contract.md) |
| sim/ | closed loop (run_hier), scenarios, KPIs, ledger, Monte Carlo, plots |
| tests/ | unit tests + pass/fail rules |
| firmware_node/ | ESP32 node sketch + SIL host |
| tools/ | header export, Mosquitto files, SIL script |
| hil/ | real boards |

## One tick
1. plant steps with what the switches did last tick
2. each node gets its meter + the main command from 1 tick ago, applies its own rules, replies
3. main controller reads node reports + PCC meter + Pi inbox only, decides; grid breaker direct
4. main controller publishes to the Pi
