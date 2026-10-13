# ETAP 19 cross-check of the mg_hier load flow (Stage 1)

Date: 13 Oct 2026. ETAP 19.0.1, project `etap/URJA_Microgrid/Microgrid/Microgrid.OTI` at the repo top level (open it from there).
Reference numbers: `benchmark_cases.csv`, made by `mg_hier/tools/etap/etap_benchmark.m` (our `net_solve`).
Build steps: `ETAP Model Build Guide.pdf` (live version: Claude doc "ETAP Model Build Guide").

## Result: all three cases match

| Case | Quantity | ETAP | MATLAB |
|---|---|---|---|
| A noon, grid (Grid-ON, Design) | Bus-COMM / H1 / H2 | 99.37 / 99.45 / 98.44 % | 99.38 / 99.45 / 98.44 % |
| | Grid at PCC | 1.19 kW export, 8.98 kvar import | -1.18 kW, +8.98 kvar |
| B evening, grid, BESS 9 kW (Grid-ON, Normal) | Bus-COMM / H1 / H2 | 98.94 / 98.17 / 98.00 % | 98.94 / 98.18 / 98.01 % |
| | Grid at PCC | 7.29 kW, 8.98 kvar | 7.30 kW, 8.99 kvar |
| C evening, island (Island, Normal) | Bus-COMM / H1 / H2 | 100 / 99.24 / 99.08 % | 100 / 99.24 / 99.07 % |
| | G-BESS (swing) | 16.3 kW, 8.97 kvar | 16.29 kW, 8.98 kvar |

Agreement: within 0.01 % in voltage and 0.01 kW in power.

## Model set-up that worked

- Balanced 3-phase equivalent at 0.3984 kV (ohms unchanged, powers x3).
- `U1` (1000 MVAsc, X/R 1.5) -> `Bus-GRID` -> `Z-GRID` (0.08 + j0.12 ohm) -> `Bus-PCC` -> `CB-PCC` -> `Bus-COMM`.
  In load flow ETAP holds a Power Grid at 100 %; its MVAsc is used only in short circuit.
- One battery element `G-BESS` (18 kVA). Generator mode is set per configuration in the Configuration Manager:

| Element | Grid-ON | Island |
|---|---|---|
| CB-PCC | Closed | Open |
| G-BESS | Mvar Control | Swing (100 %, 0 deg) |
| G-PV-COMM, G-PV-H1 | Mvar Control | Mvar Control |

- Generation categories (Rating page, in MW): Design = case A (PV 0.006541 / 0.010901 MW, BESS 0), Normal = case B/C (PV 0, BESS 0.009 MW).
- Lumped loads: 100 % constant kVA (ETAP default 80/20 constant kVA / constant Z), to match our constant-power loads.

## Mistakes found on the way

1. Results on screen came from a run in another configuration: always check the Config dropdown before Run.
2. `G-BESS` not attached to `Bus-COMM` (no connection dot): island dead, generator 0 kVA.
3. PV in Voltage Control pinned Bus-H1 at 100 %: PV must be Mvar Control.
4. Lumped loads at 80/20 drew ~0.6 % less power at 98.5 % voltage.

## Finding

Case C alert: G-BESS overload 106 % (kW) and 117 % (Mvar). An evening island with every load on needs
18.6 kVA from an 18 kVA inverter, so full demand cannot be carried in island without shedding.
Check this against the controller's shedding rules.

## Screenshots

`LF-A_grid_noon.png`, `LF-B_grid_evening.png`, `LF-C_island_evening.png`, `LF-C_alert_view.png`.

## Next (Stage 2+)

Short circuit (hand check, grid only, bolted 3-phase: 1595 A COMM, 713 A H1, 552 A H2; then inverter
contribution ~31 A vs 40 A node trip), harmonics vs IEEE 519, unbalanced single-phase loads.
