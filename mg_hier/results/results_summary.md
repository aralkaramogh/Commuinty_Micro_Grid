# mg_hier Stage A - results (MATLAB R2025b, 2026-10-08)

Simulation only: every node is the MATLAB twin of its firmware, the Pi is the simulated broker with the real ACL.

| check | result |
|---|---|
| unit tests (tests/test_hier.m) | 12/12 |
| scenarios S1-S13 (tests/check_h.m) | 13/13 |
| Monte Carlo (40 random evenings, outages, sags, noise, plant spread, random node-link drop) | 40/40 |
| node SIL: C++ firmware vs MATLAB twin (tools/run_sil_node.sh, g++ 11) | 835,600 replies, 0 mismatches (incl. 40,000 fuzz lines) |
| node sketch compiles against an Arduino stub | yes (not built with the ESP32 toolchain) |

Scenario table: results/tables/scenarios.csv. Monte Carlo: results/tables/montecarlo.csv.
Figures: results/figures. Example Pi messages: results/pi_msgs. Event logs: results/logs/*_events.txt.

Not verified: real ESP32 nodes (hil/run_hil_nodes.m), the real Pi broker, MATLAB -> Pi MQTT publishing.
