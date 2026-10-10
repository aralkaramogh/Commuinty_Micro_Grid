%% dc_microgrid_params.m
% =========================================================================
% SINGLE SOURCE OF TRUTH - ALL PARAMETERS FOR SOLAR MICROGRID BLACK-START
% =========================================================================
% Part of: Aarambh Hackathon #34 - DC Microgrid Black-Start Controller
% Author:  Antigravity AI (generated 2026-10-01)
% Usage:   Called by all MATLAB scripts and Simulink models via a shared
%          workspace struct p. Also exported to firmware/include/config.h
%          by tools/export_params_to_header.m
%
% ASSUMPTIONS (see docs/architecture.md for full list):
%   - Config A: 6 V DC bus (no boost converter required)
%   - Storage emulated by 12V SMPS + buck module (virtual SOC)
%   - No real battery - coulomb counting of emulated current
%   - ACS712-5A variant assumed (185 mV/A sensitivity)
%   - 4x IRF3205 MOSFETs, driven via 12V gate driver
%   - Breadboard prototype, max 1A on bus
% =========================================================================

function p = dc_microgrid_params()
% Returns a struct p with all parameters organised by subsystem.

%% ---- CONFIGURATION SELECTOR ----------------------------------------
p.cfg.bus = 'A'; % A=6V bus (default), B=12V bus (needs boost)

%% ---- BUS / SYSTEM SCALE -------------------------------------------
p.SCALE = 1; % 1 = breadboard prototype

if p.cfg.bus == 'A'
    p.V_nom     = 6.0;
    p.V_max     = 6.48;
    p.V_min     = 5.52;
    p.V_trip_ov = 6.60;
    p.V_trip_uv = 4.80;
else
    p.V_nom     = 12.0;
    p.V_max     = 13.2;
    p.V_min     = 10.8;
    p.V_trip_ov = 13.5;
    p.V_trip_uv = 9.6;
end

%% ---- PV PANEL (6V 3W mini panel) ----------------------------------
p.pv.Isc    = 0.55;
p.pv.Voc    = 7.2;
p.pv.Imp    = 0.50;
p.pv.Vmp    = 6.0;
p.pv.Pmax   = p.pv.Imp * p.pv.Vmp; % 3.0 W
p.pv.n_cell = 12;
p.pv.T_ref  = 25;
p.pv.G_ref  = 1000;
p.pv.k_T_Isc = 0.065;
p.pv.k_T_Voc = -0.30;
p.pv.I_ph_ref = p.pv.Isc;
p.pv.I_0_ref  = 1e-9;
p.pv.n_id     = 1.3;
p.pv.R_s      = 0.2;
p.pv.R_sh     = 300;
p.pv.Vt_ref   = 26e-3 * p.pv.n_id * p.pv.n_cell;
p.pv.V_diode  = 0.30;
p.pv.connect_margin = 0.15;
p.pv.I_avail_min    = 0.05;

%% ---- STORAGE EMULATOR ---------------------------------------------
p.stor.V_oc     = p.V_nom + 0.15; % 6.15V: at I=0 Vbus=6.15V (2.5% over nom)
p.stor.R_series = 0.25;
p.stor.I_limit  = 1.0;
p.stor.I_inrush_max = 1.5;
p.stor.capacity_Wh  = 5.0;
p.stor.capacity_Ah  = p.stor.capacity_Wh / p.V_nom;
p.stor.SOC_init      = 0.80;
p.stor.SOC_min       = 0.10;
p.stor.SOC_crit      = 0.15;
p.stor.SOC_start_min = 0.20;
p.stor.eta_discharge = 0.90;

%% ---- MOSFET SWITCH MODELS (IRF3205) --------------------------------
p.sw.Rds_on      = 0.050;
p.sw.t_on        = 50e-6;
p.sw.t_off       = 50e-6;
p.sw.V_body_diode= 0.7;

%% ---- DC BUS PARASITICS --------------------------------------------
p.bus.C      = 1000e-6;
p.bus.R_wire = 0.1;
p.bus.L_wire = 5e-6;

%% ---- LOADS --------------------------------------------------------
p.load(1).name='Tier1_LED_critical'; p.load(1).R=36; p.load(1).L=0; p.load(1).P_nom=p.V_nom^2/36; p.load(1).inrush=1.2; p.load(1).t_inrush=0.010; p.load(1).tier=1; p.load(1).SOC_min_req=0.10;
p.load(2).name='Tier2_Resistor_47ohm'; p.load(2).R=47; p.load(2).L=0; p.load(2).P_nom=p.V_nom^2/47; p.load(2).inrush=1.1; p.load(2).t_inrush=0.005; p.load(2).tier=2; p.load(2).SOC_min_req=0.25;  % > SOC_start_min(0.20) so a low-SOC start restores Tier1 only
p.load(3).name='Tier3_DC_Fan_motor'; p.load(3).R=30; p.load(3).L=5e-3; p.load(3).P_nom=p.V_nom^2/30; p.load(3).inrush=4.0; p.load(3).t_inrush=0.150; p.load(3).tier=3; p.load(3).SOC_min_req=0.30;
p.load(4).name='Tier4_100ohm_dummy'; p.load(4).R=100; p.load(4).L=0; p.load(4).P_nom=p.V_nom^2/100; p.load(4).inrush=1.05; p.load(4).t_inrush=0.002; p.load(4).tier=4; p.load(4).SOC_min_req=0.40;

%% ---- SENSORS ------------------------------------------------------
p.sens.acs712.variant     = '5A';
p.sens.acs712.sensitivity = 0.185;
p.sens.acs712.V_offset    = 2.5;
p.sens.acs712.noise_rms   = 0.015;
p.sens.acs712.bandwidth   = 80e3;
p.sens.acs712.I_max       = 5.0;
p.sens.acs712.div_R1      = 10e3;
p.sens.acs712.div_R2      = 15e3;
p.sens.acs712.div_ratio   = 15e3/(10e3+15e3); % 0.6
p.sens.acs712.gain_adc    = p.sens.acs712.sensitivity * p.sens.acs712.div_ratio;
p.sens.acs712.offset_adc  = p.sens.acs712.V_offset * p.sens.acs712.div_ratio;
p.sens.acs712.n_oversample= 16;

p.sens.vsens.div_ratio    = 0.2;
p.sens.vsens.V_in_max     = 16.5;
p.sens.vsens.tolerance    = 0.01;
p.sens.vsens.noise_rms    = 0.005;

p.adc.bits       = 12;
p.adc.V_ref      = 3.3;
p.adc.counts_max = 4095;
p.adc.LSB        = p.adc.V_ref / p.adc.counts_max;
p.adc.nonlin_pct = 5;
p.adc.noise_lsb  = 3;
p.adc.atten_11dB = true;
p.adc.Ts         = 1e-3;

p.filt.tau_sensor = 0.020;
p.filt.alpha_sens = 1 - exp(-p.adc.Ts / p.filt.tau_sensor);

%% ---- CONTROL LOOP TIMING ------------------------------------------
p.ctrl.Ts_fast  = 1e-3;
p.ctrl.Ts_fsm   = 10e-3;
p.ctrl.Ts_plant = 20e-6;
p.ctrl.f_pwm    = 20e3;

%% ---- SOFT-START ---------------------------------------------------
p.ss.T_ramp     = 1.0;
p.ss.duty_min   = 0.0;
p.ss.duty_max   = 1.0;
p.ss.dDuty_step = p.ctrl.Ts_fast / p.ss.T_ramp;
p.ss.I_limit    = p.stor.I_inrush_max;

%% ---- MPPT-LITE ----------------------------------------------------
p.mppt.dI_step  = 0.01;
p.mppt.period   = 0.10;
p.mppt.I_max    = p.pv.Imp * 1.1;

%% ---- FSM TIMING ---------------------------------------------------
p.fsm.T_blackout_confirm = 1.0;
p.fsm.T_stable_min       = 1.0;
p.fsm.T_stable_dwell     = 2.0;
p.fsm.T_load_step_settle = 1.5;
p.fsm.V_stable_band      = 0.10;  % 10%: allows source headroom overshoot
p.fsm.V_blackout_thresh  = 0.20;
p.fsm.auth_lockout_scans = 3;
p.fsm.auth_lockout_time  = 30.0;
p.fsm.watchdog_timeout   = 5.0;
p.fsm.retry_max          = 3;
p.fsm.retry_backoff_base = 5.0;

%% ---- RESTORATION ENGINE -------------------------------------------
p.rest.k_cold           = 1.2;
p.rest.headroom_margin  = 1.15;
p.rest.I_src_max_frac   = 0.80;
p.rest.V_dip_max        = 0.15;
p.rest.P_pv_min_frac    = 0.10;
p.rest.t_blame          = 0.50;  % [s] stress within this time of a connect is blamed on that load
p.rest.max_strikes      = 2;     % blamed sheds before a tier is locked out (faulty branch)
p.rest.t_strike_clear   = 10.0;
p.rest.t_shed_holdoff   = 0.10;  % [s] after a blamed shed, let filtered sensors settle before shedding more  % [s] a load that stays on this long has its strikes cleared

%% ---- PROTECTION ---------------------------------------------------
p.prot.I_oc_hard         = 1.80;
p.prot.I_oc_soft         = 1.50;
p.prot.I2t_limit         = 2.0;
p.prot.V_ov_trip         = p.V_trip_ov;
p.prot.V_uv_trip         = p.V_trip_uv;
p.prot.t_oc_trip         = 5e-3;
p.prot.I_sw_expect_min   = 1.5;   % [A] expected-source-current threshold (must exceed ADC-gain-error equivalent: 3%*6.2V/0.25ohm)
p.prot.t_sw_mismatch     = 0.03;  % source-switch stuck-open debounce [s] (sag is only ~40 ms)
p.prot.V_mismatch_thresh = 0.3;
p.prot.t_mismatch_window = 0.5;
p.prot.sensor_freeze_time= 2.0;
p.prot.sensor_stuck_tol  = p.adc.LSB * 5;

%% ---- ESP32 GPIO PIN MAP -------------------------------------------
p.pins.V_bus     = 34;
p.pins.V_pv      = 35;
p.pins.I_src     = 32;
p.pins.I_load    = 33;
p.pins.SRC_SW    = 25;
p.pins.PV_SW     = 26;
p.pins.LOAD1     = 27;
p.pins.LOAD2     = 16;
p.pins.LOAD3     = 17;
p.pins.LOAD4     = 21;
p.pins.RC522_CS  = 5;
p.pins.RC522_SCK = 18;
p.pins.RC522_MOSI= 23;
p.pins.RC522_MISO= 19;
p.pins.RC522_RST = 22;
p.pins.LED_status= 2;
p.pins.BUZZER    = 4;

%% ---- SIMULATION DEFAULTS ------------------------------------------
p.sim.T_end      = 30.0;
p.sim.G_default  = 800;
p.sim.T_cell_def = 30;
p.sim.t_blackout = 1.0;
p.sim.auto_auth  = true;

%% ---- TELEMETRY ----------------------------------------------------
p.telem.baud   = 115200;
p.telem.format = 't_ms,state,vbus,vpv,isrc,iload,soc,duty,load_mask,fault';
p.telem.Ts     = 100e-3;

%% ---- MONTE CARLO --------------------------------------------------
p.mc.N_runs       = 30;
p.mc.load_var     = 0.20;
p.mc.pv_var       = 0.15;
p.mc.RC_var       = 0.10;
p.mc.adc_gain_var = 0.03;
p.mc.SOC_range    = [0.20, 0.90];
p.mc.pass_rate_req= 0.95;

%% ---- UNIT CHECKS --------------------------------------------------
P_loads_total = sum([p.load.P_nom]);
P_source_max  = p.stor.I_limit * p.V_nom;
P_pv_max      = p.pv.Pmax;

assert(P_loads_total < P_source_max + P_pv_max, ...
    'params:power_balance', ...
    'Total load power %.2fW > source+PV %.2fW', P_loads_total, P_source_max+P_pv_max);

V_bus_adc_max = p.V_trip_ov * p.sens.vsens.div_ratio;
assert(V_bus_adc_max <= p.adc.V_ref, ...
    'params:adc_range', 'V_trip_ov ADC=%.3fV > Vref=%.3fV', V_bus_adc_max, p.adc.V_ref);

V_acs_max = (p.stor.I_inrush_max * p.sens.acs712.sensitivity + p.sens.acs712.V_offset) ...
             * p.sens.acs712.div_ratio;
assert(V_acs_max <= p.adc.V_ref, ...
    'params:acs712_range', 'ACS712@Iinrush ADC=%.3fV > Vref=%.3fV', V_acs_max, p.adc.V_ref);

fprintf('[params] OK: Config %s | V_nom=%.1fV | P_loads=%.2fW | P_avail=%.2fW\n', ...
    p.cfg.bus, p.V_nom, P_loads_total, P_source_max+P_pv_max);
fprintf('[params]     SOC_cap=%.3fAh | ACS_div=%.3f | V_adc@Iinrush=%.3fV\n', ...
    p.stor.capacity_Ah, p.sens.acs712.div_ratio, V_acs_max);
end
