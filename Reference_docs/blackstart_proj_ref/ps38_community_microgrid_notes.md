# PS #38 Community Microgrid & Energy Sharing: working notes (2026-10-02)

The team is considering switching from PS #34 (black start) to PS #38: "an intelligent microgrid controller that detects grid failure, manages locally generated renewable energy and storage, prioritizes critical loads, and safely manages the transition between grid-connected and islanded operation". The hardware brief is a prepaid RFID energy-dispensing meter that lets neighbouring households trade and route local solar power.

## Proposed design
- **Bus:** 12 V DC community bus (not AC; the PZEM-004T is a mains meter, so it's skipped).
- **Households:** 3 (Houses 1 and 2 with solar, House 3 without), each with an ESP32 meter: INA226 (bidirectional), RC522 RFID, OLED, high-side switches for critical and flexible loads.
- **Community side:** one 12 V battery (LiFePO4 4S + BMS, or sealed lead-acid), and a grid emulator (SMPS + CC/CV buck, unplug to simulate failure) behind a back-to-back MOSFET grid switch.
- **Hub:** ESP32 doing safety, islanding, ledger and dashboard. Meters talk to it over ESP-NOW.
- **Reuse from PS #34:** state machine, soft-start (now used for grid reconnection), load priorities and shedding, protections, RFID, digital-twin and SIL approach.

## AI/ML energy manager (teammate)
- **Brief:** Claude Doc "Community Microgrid Energy Manager: Brief for the AI/ML Lead" (https://claude.ai/code/artifact/80ff37d5-b90e-42ee-a796-1223b93cc7ea).
- **Approach:** rule-based baseline, then MPC (LP/MILP), then ML forecasting, then RL as a stretch. Same JSON over MQTT for the simulator and the real hub. The hub can always override.
- **Inspiration:** Smart Grid Analytics' Solvyn / AURA (forecasting + BESS arbitrage + dispatch), scaled down to a neighbourhood.

## Naming (shortlist, quick web checks only)
- **Team / acronym:** AMRIT (Autonomous Microgrid for Renewable Islanding & Trading), checked clear.
- **Product:** Govardhan Grid, Mohalla Grid, Saanjhi Urja, UrjaMesh all found clear.
- **Taken:** Urja Setu, GridShare, SunSwap, SolarSathi, MITRA, PRANA, DIYA, Bijli Bazaar, Surya Sangam, ArkaGrid, Indrajaal, Akshaya Patra.