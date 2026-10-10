function P = ac_params()
% AC_PARAMS  Single source of truth for the AC community microgrid model
% (MATLAB plant) and the ESP32 controller (firmware/include/config.h is
% generated from this file by tools/export_params_to_header.m).
%
% System: single-phase 230 V, 50 Hz. Grid -> feeder -> COMMUNITY BUS (BESS,
% community PV plant, community load) -> service cables -> 3 houses.
% Labels: [design] our choice, [typical] textbook/typical value, [assumed] guess.

%% ---------- simulation ----------
P.sim.dt        = 1.0;      % [s] plant step = controller tick
P.sim.baud      = 115200;   % USB serial to the ESP32
P.sim.timeout_s = 2.0;

%% ---------- AC system ----------
P.ac.V_nom = 230;           % [V rms] [typical, India LT]
P.ac.f_nom = 50;            % [Hz]

%% ---------- utility grid (Thevenin source at the transformer) ----------
P.grid.Z_th    = 0.08 + 0.12i;  % [ohm] transformer + feeder to the community bus [assumed]
P.grid.V_dead  = 0.30;          % [pu] below this the grid counts as dead (no supply)

%% ---------- shared BESS (battery + bidirectional inverter) ----------
P.bess.E_kWh      = 10;     % [kWh] usable energy [design]
P.bess.S_rated    = 6000;   % [VA] inverter rating [design]
P.bess.P_dis_max  = 5000;   % [W] battery discharge limit [design]
P.bess.P_ch_max   = 4000;   % [W] battery charge limit [design]
P.bess.eta_ch     = 0.95;   % one-way efficiencies [typical]
P.bess.eta_dis    = 0.95;
P.bess.soc_init   = 0.70;
P.bess.soc_cutoff = 0.05;   % BMS stops discharge below this
P.bess.soc_taper  = 0.05;   % charge power tapers to 0 over the last 5 % [assumed]
P.bess.mp         = 0.5;    % [Hz] P-f droop: f = 50 - mp * P/P_dis_max (island)
P.bess.nq         = 0.05;   % [pu] Q-V droop: V = 230 * (1 - nq * Q/S_rated) (island)
P.bess.T_ovl      = 5;      % [s] overload longer than this trips the inverter
P.bess.sync_slip_deg = 6;   % [deg per tick] slip used while synchronising [design]

%% ---------- PV inverters ----------
P.pv.derate     = 0.85;     % soiling, wiring, mismatch [typical]
P.pv.gamma      = -0.004;   % [1/K] power temperature coefficient [typical]
P.pv.NOCT       = 45;       % [degC]
P.pv.S_over     = 1.10;     % inverter VA = 1.1 x kWp
P.pv.G_max      = 1000;     % [W/m2] clear-sky noon
P.pv.T_amb_mean = 28; P.pv.T_amb_swing = 6;
% volt-var (house inverters only): Q in pu of inverter VA, + = inject (raises V)
P.pv.vv_V = [0.92 0.98 1.02 1.08];   % [pu]
P.pv.vv_Q = [0.44 0 0 -0.44];         % [pu]  (IEEE 1547 Cat B style) [typical]
% frequency-watt (all PV, island over-frequency): output falls from 100 % at
% fw_f0 to 0 % at fw_f1  ->  f = fw_f0 + (fw_f1 - fw_f0) * curtailed fraction
P.pv.fw_f0 = 50.2; P.pv.fw_f1 = 51.5;

%% ---------- community place (water pump + street lights + hall) ----------
P.comm.P_crit = 600;  P.comm.pf_crit = 0.80;   % [W] critical, always on [design]
P.comm.pv_kWp = 5;                             % community solar plant [design]

%% ---------- houses: copy a row to add a house ----------
H = struct( ...
 'id',       {'H1',          'H2',          'H3'}, ...
 'pv_kWp',   {3,             2,             0}, ...        % rooftop PV
 'P_crit',   {300,           300,           300}, ...      % [W] fridge + lights
 'pf_crit',  {0.85,          0.85,          0.85}, ...
 'P_flex',   {1500,          1200,          1000}, ...     % [W] pump / AC / iron
 'pf_flex',  {0.90,          0.92,          0.95}, ...
 'Z_line',   {0.20+0.04i,    0.30+0.05i,    0.40+0.06i}, ... % [ohm] service cable
 'shed_soc', {0.30,          0.35,          0.40}, ...     % island: shed flex below
 'credit0',  {100,           100,           10}, ...       % [Rs] prepaid balance (H3: low-credit household)
 'card_uid', {2712847105,    2712847106,    2712847107}, ...
 'profile',  {'family',      'office',      'family'});
P.house = H; P.n_house = numel(H);

%% ---------- controller (runs on the ESP32) ----------
C.V_ok_lo = 0.85; C.V_ok_hi = 1.10;   % [pu] grid healthy voltage band
C.F_ok_lo = 49.5; C.F_ok_hi = 50.5;   % [Hz] grid healthy frequency band
C.V_lost  = 0.50;                     % [pu] below = grid lost: island at once
C.N_abn   = 3;      % [ticks] abnormal (but not lost) grid before islanding
C.N_boot  = 3;      % [ticks] everything OFF after power-up
C.N_grid_stable = 10;  % [ticks] healthy grid before resynchronising
C.DV_sync  = 10;    % [V]   max |V_grid - V_mg| to close the breaker
C.DF_sync  = 0.20;  % [Hz]  max |f_grid - f_mg|
C.DTH_sync = 5;     % [deg] max predicted phase difference at closing
C.F_ufls      = 49.6;  % [Hz] island under-frequency: shed one flexible load per tick
C.T_uf_hold   = 300;   % [s] wait after a UF shed before restoring
C.T_uf_step   = 30;    % [s] between restores
C.UF_restore  = 0.80;  % restore only if P_bess + P_flex <= 0.8 x P_dis_max
C.soc_hyst    = 0.08;
C.soc_reserve = 0.60;  % grid mode: rule dispatch never discharges below (outage reserve)
C.soc_ai_min  = 0.30;  % grid mode: AI may discharge down to here, never lower
C.soc_ch_stop = 0.95;  % grid mode: stop charging above
C.P_recharge = 1500;   % [W] grid mode: below the reserve, recharge from the grid at least this fast
C.I_trip      = 40;    % [A rms] house over-current
C.N_oc = 2; C.N_retry = 10; C.strikes_max = 2; C.N_strike_clear = 60;
C.price_default = 6.0;     % [Rs/kWh] buying price
C.price_min = 2.0; C.price_max = 15.0;   % AI price accepted only inside this band
C.sell_ratio    = 0.9;     % seller earns 90 % of the price
C.credit_restore = 1.0;    % [Rs] flexible load back above this balance
C.card_topup    = 20;      % [Rs] per valid card tap
C.card_bad_max  = 3; C.N_card_lock = 60;
C.T_ai_timeout  = 30;      % [s] AI command older than this is dropped (fallback to rules)
C.telemetry_every = 5;
P.ctrl = C;

%% ---------- ESP32 pins ----------
P.hw.led_grid   = 25;   % green : grid breaker closed
P.hw.led_island = 26;   % red   : islanded (blinks while synchronising)
P.hw.led_shed   = 27;   % yellow: some flexible load shed
P.hw.led_fault  = 14;   % white : house trip/lockout, BESS fault or E-stop
P.hw.estop_pin  = 33;   % E-stop input, pull-up, pressed = LOW
% ESP32-S3 has no GPIO 25 and uses 26-32 (and often 33-37) for flash/PSRAM,
% so the S3 build uses these instead (picked automatically at compile time)
P.hw.s3_led_grid = 4; P.hw.s3_led_island = 5; P.hw.s3_led_shed = 6; P.hw.s3_led_fault = 7;
P.hw.s3_estop_pin = 15;

%% ---------- validation limits ----------
P.req.V_lo = 0.90; P.req.V_hi = 1.10;   % [pu] house/bus voltage while energised
P.req.f_lo = 49.0; P.req.f_hi = 51.5;   % [Hz] island frequency
P.req.dth_close = 10;                   % [deg] max closing angle
P.req.mc_pass = 0.95;
end
