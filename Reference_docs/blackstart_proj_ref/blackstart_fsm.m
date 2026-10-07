function [state_out, gates_out, log_out, kpi_out] = blackstart_fsm(t, sensors, state_in, log_in, p, cfg_override)
% BLACKSTART_FSM  Supervisory Black-Start Finite State Machine (MATLAB reference implementation).
% This function is the MATLAB reference that is ported line-by-line to firmware/src/fsm.cpp.
% Call at Ts_fsm = 10 ms.
%
% INPUTS:
%   t            : current time [s]
%   sensors      : struct: V_bus, V_pv, I_src, I_load (filtered, calibrated)
%   state_in     : persistent state struct (first call: init_fsm_state(p))
%   log_in       : event log struct
%   p            : parameter struct from dc_microgrid_params()
%   cfg_override : optional struct to override auth/auto flags for testing
%
% OUTPUTS:
%   state_out    : updated state struct
%   gates_out    : struct: src_duty [0-1], pv_sw [0/1], load_mask [4-bit]
%   log_out      : updated event log
%   kpi_out      : KPI increments for this tick

% ---- State IDs (match firmware enum) --------------------------------
S0_BLACKOUT_DETECT = 0;
S1_AUTH_WAIT       = 1;
S2_SELF_CHECK      = 2;
S3_SOFT_START_BUS  = 3;
S4_BUS_STABLE_DWELL= 4;
S5_CONNECT_PV      = 5;
S6_LOAD_RESTORATION= 6;
S7_NORMAL_ISLANDED = 7;
SX_FAULT_RECOVERY  = 8;
SX_LOCKOUT_ALARM   = 9;

% ---- Unpack state ---------------------------------------------------
s = state_in;
dt = p.ctrl.Ts_fsm;

% ---- Sensor convenience aliases -------------------------------------
% ACS712 zero-offset compensation: offsets are recorded in S2 (gates off) and
% subtracted from every later reading (firmware does this in sensors.cpp).
Is_raw = sensors.I_src;  Il_raw = sensors.I_load;
sensors.I_src  = Is_raw - s.I_src_offset;
sensors.I_load = Il_raw - s.I_load_offset;
Vb  = sensors.V_bus;
Vpv = sensors.V_pv;
Is  = sensors.I_src;
Il  = sensors.I_load;

% ---- Derived quantities --------------------------------------------
P_bus   = Vb * Il;
P_pv    = max(0, Vpv * max(0, Il - Is));   % approx PV power
P_src   = Vb * Is;

% ---- Virtual SOC update (coulomb counting) -------------------------
if s.src_connected
    dSOC = -(Is * Vb * dt) / (p.stor.capacity_Wh * 3600 * p.stor.eta_discharge);
    s.SOC = max(p.stor.SOC_min, s.SOC + dSOC);
end

% ---- Protection (runs every tick regardless of state) -------------
[s, gates_prot] = check_protection(s, sensors, t, p, ...
    S0_BLACKOUT_DETECT, SX_FAULT_RECOVERY, SX_LOCKOUT_ALARM);

% ---- Fault injection from previous state ---------------------------
if s.fault_latched && s.state ~= SX_LOCKOUT_ALARM && s.state ~= SX_FAULT_RECOVERY
    if any(strcmp(s.fault_code, {'SWITCH_FAULT','SENSOR_FROZEN'}))
        % Unrecoverable by retry: go straight to alarm lockout
        s = log_event(s, log_in, t, 'PROTECTION_TRIP', s.fault_code);
        s = transition(s, SX_LOCKOUT_ALARM, t, s.fault_code);
    else
        s.state = SX_FAULT_RECOVERY;
        s = log_event(s, log_in, t, 'PROTECTION_TRIP', s.fault_code);
    end
end

% ---- MAIN FSM SWITCH -----------------------------------------------
switch s.state

    case S0_BLACKOUT_DETECT
        % All gates OFF
        s.src_duty  = 0;
        s.pv_sw     = 0;
        s.load_mask = 0;
        s.src_connected = false;
        % Debounce: V_bus < 20% for > T_blackout_confirm
        if Vb < p.fsm.V_blackout_thresh * p.V_nom
            s.t_blackout_timer = s.t_blackout_timer + dt;
        else
            s.t_blackout_timer = 0;
        end
        if s.t_blackout_timer >= p.fsm.T_blackout_confirm
            s = transition(s, S1_AUTH_WAIT, t, 'BLACKOUT_CONFIRMED');
            s.t_blackout_timer = 0;
        end

    case S1_AUTH_WAIT
        % All gates OFF; wait for RFID or auto_auth flag
        s.src_duty  = 0;
        s.pv_sw     = 0;
        s.load_mask = 0;
        auto = p.sim.auto_auth;
        if nargin >= 6 && isfield(cfg_override,'auto_auth')
            auto = cfg_override.auto_auth;
        end
        rfid_ok = auto || s.rfid_event == 1;
        rfid_bad= s.rfid_event == -1;
        s.rfid_event = 0; % consume event

        if s.lockout_remaining > 0
            s.lockout_remaining = s.lockout_remaining - dt;
            % Stay in AUTH_WAIT during lockout
        elseif rfid_bad
            s.bad_scan_count = s.bad_scan_count + 1;
            if s.bad_scan_count >= p.fsm.auth_lockout_scans
                s.lockout_remaining = p.fsm.auth_lockout_time;
                s = transition(s, SX_LOCKOUT_ALARM, t, 'BAD_SCAN_LOCKOUT');
            end
        elseif rfid_ok
            s.bad_scan_count = 0;
            s = transition(s, S2_SELF_CHECK, t, 'AUTHORISED');
        end

    case S2_SELF_CHECK
        % Sensor sanity + SOC check
        s.src_duty  = 0;
        s.pv_sw     = 0;
        s.load_mask = 0;
        sensors_raw = sensors; sensors_raw.I_src = Is_raw; sensors_raw.I_load = Il_raw;
        sensor_ok = check_sensor_sanity(sensors_raw, p);
        soc_ok    = s.SOC >= p.stor.SOC_start_min;
        if ~sensor_ok
            s = transition(s, SX_LOCKOUT_ALARM, t, 'SENSOR_FAULT_AT_SELFCHECK');
            s.fault_code = 'SENSOR';
        elseif ~soc_ok
            s = transition(s, SX_LOCKOUT_ALARM, t, 'SOC_TOO_LOW');
            s.fault_code = 'SOC_LOW';
        else
            % Zero-calibrate ACS712 offsets here (in sim: use nominal)
            s.I_src_offset = Is_raw; % record zero offset (raw reading, gates are OFF)
            s.I_load_offset= Il_raw;
            s = transition(s, S3_SOFT_START_BUS, t, 'SELF_CHECK_PASS');
            s.t_softstart_timer = 0;
            s.t_stable_timer    = 0;
        end

    case S3_SOFT_START_BUS
        % Ramp SRC_SW duty 0?1 over T_ramp; current-limited
        s.pv_sw     = 0;
        s.load_mask = 0;
        s.src_connected = true;
        % Ramp duty
        s.src_duty = min(p.ss.duty_max, s.src_duty + p.ss.dDuty_step * p.ctrl.Ts_fsm/p.ctrl.Ts_fast);
        % Current limit: if Is exceeds limit, hold duty
        if Is > p.ss.I_limit
            s.src_duty = max(0, s.src_duty - p.ss.dDuty_step*2);
        end
        s.t_softstart_timer = s.t_softstart_timer + dt;
        % Check bus stable: within 5% for T_stable_min
        in_band = abs(Vb - p.V_nom)/p.V_nom < p.fsm.V_stable_band;
        if in_band && s.src_duty >= 0.95
            s.t_stable_timer = s.t_stable_timer + dt;
        else
            s.t_stable_timer = 0;
        end
        if s.t_stable_timer >= p.fsm.T_stable_min
            s = transition(s, S4_BUS_STABLE_DWELL, t, 'BUS_STABLE');
            s.t_dwell_timer = 0;
        end
        % Timeout: if bus not stable after 3*T_ramp, fault
        if s.t_softstart_timer > 3 * p.ss.T_ramp
            s.fault_code = 'SOFTSTART_TIMEOUT';
            s = transition(s, SX_FAULT_RECOVERY, t, 'SOFTSTART_TIMEOUT');
        end

    case S4_BUS_STABLE_DWELL
        % Hold duty at max; verify no issues
        s.src_duty  = 1.0;
        s.pv_sw     = 0;
        s.load_mask = 0;
        s.t_dwell_timer = s.t_dwell_timer + dt;
        if s.t_dwell_timer >= p.fsm.T_stable_dwell
            s = transition(s, S5_CONNECT_PV, t, 'DWELL_COMPLETE');
        end

    case S5_CONNECT_PV
        % Connect PV if available
        s.src_duty  = 1.0;
        s.load_mask = 0;
        pv_avail = (Vpv >= Vb + p.pv.V_diode + p.pv.connect_margin) && ...
                   (Vpv > 0.5); % sanity: sensor reads something
        if pv_avail
            s.pv_sw = 1;
            % Simple MPPT-lite: P&O on source current reduction
            if t - s.t_mppt_last >= p.mppt.period
                P_pv_now = Vpv * max(0, Il - Is);
                if P_pv_now > s.P_pv_prev
                    s.mppt_I_ref = min(p.mppt.I_max, s.mppt_I_ref + p.mppt.dI_step);
                else
                    s.mppt_I_ref = max(0, s.mppt_I_ref - p.mppt.dI_step);
                end
                s.P_pv_prev  = P_pv_now;
                s.t_mppt_last= t;
            end
        else
            s.pv_sw = 0; % night or insufficient PV
        end
        s = transition(s, S6_LOAD_RESTORATION, t, 'PV_STEP_DONE');

    case S6_LOAD_RESTORATION
        s.src_duty = 1.0;
        % Restoration engine
        [s, new_mask] = load_restoration_engine_step(s, sensors, t, p);
        s.load_mask = new_mask;
        % Check if all restorable loads done
        if s.restoration_complete
            s = transition(s, S7_NORMAL_ISLANDED, t, 'ALL_LOADS_RESTORED');
        end

    case S7_NORMAL_ISLANDED
        s.src_duty = 1.0;
        % Monitor + shed/restore with hysteresis
        [s, new_mask] = load_restoration_engine_step(s, sensors, t, p);
        s.load_mask = new_mask;
        % MPPT-lite continues
        if s.pv_sw
            if Vb > p.V_nom * 1.05
                s.mppt_I_ref = max(0, s.mppt_I_ref - p.mppt.dI_step*3);
            end
        end

    case SX_FAULT_RECOVERY
        % Shed loads, retry with back-off
        s.src_duty  = 0;
        s.pv_sw     = 0;
        s.load_mask = 0;
        s.src_connected = false;
        s.t_fault_timer = s.t_fault_timer + dt;
        backoff_t = p.fsm.retry_backoff_base * 2^min(s.retry_count, 4);
        if s.t_fault_timer >= backoff_t
            if s.retry_count >= p.fsm.retry_max
                s = transition(s, SX_LOCKOUT_ALARM, t, 'MAX_RETRIES');
            else
                s.retry_count = s.retry_count + 1;
                s.t_fault_timer = 0;
                s.fault_latched = false;
                s = transition(s, S2_SELF_CHECK, t, 'FAULT_RETRY');
            end
        end

    case SX_LOCKOUT_ALARM
        % Hard lockout: all gates off; only authorised RFID resets
        s.src_duty  = 0;
        s.pv_sw     = 0;
        s.load_mask = 0;
        s.src_connected = false;
        if s.rfid_event == 1
            s.rfid_event = 0;
            s.retry_count = 0;
            s.fault_latched = false;
            s.fault_code = '';
            s.bad_scan_count = 0;
            s.lockout_remaining = 0;
            s = transition(s, S0_BLACKOUT_DETECT, t, 'RFID_RESET');
        end
end

% ---- Pack outputs --------------------------------------------------
state_out = s;
gates_out.src_duty  = s.src_duty;
gates_out.pv_sw     = s.pv_sw;
gates_out.load_mask = s.load_mask;
log_out   = s.event_log;

kpi_out.state = s.state;
kpi_out.SOC   = s.SOC;
kpi_out.P_src = P_src;
kpi_out.P_pv  = P_pv;
kpi_out.P_bus = P_bus;
end

% =========================================================================
function s = init_fsm_state(p)
% Initialise FSM persistent state struct (call once before simulation)
s.state            = 0;  % S0_BLACKOUT_DETECT
s.src_duty         = 0;
s.pv_sw            = 0;
s.load_mask        = 0;
s.src_connected    = false;
s.SOC              = p.stor.SOC_init;
s.rfid_event       = 0;
s.bad_scan_count   = 0;
s.lockout_remaining= 0;
s.fault_latched    = false;
s.fault_code       = '';
s.retry_count      = 0;
s.t_blackout_timer = 0;
s.t_stable_timer   = 0;
s.t_softstart_timer= 0;
s.t_dwell_timer    = 0;
s.t_fault_timer    = 0;
s.t_last_step      = -inf;
s.I_src_offset     = 0;
s.I_load_offset    = 0;
s.mppt_I_ref       = 0;
s.P_pv_prev        = 0;
s.t_mppt_last      = -inf;
s.restoration_complete = false;
s.load_state       = [false false false false];
s.t_last_shed      = [-inf -inf -inf -inf];
s.I2t_accum        = 0;
s.t_oc_confirm     = 0;
s.t_sw_mismatch    = 0;
s.t_Vb_still       = 0;
s.Vb_last          = -1;
s.tier_strikes     = zeros(1,4);
s.tier_locked      = false(1,4);
s.last_conn_idx    = 0;
s.t_conn           = -inf(1,4);
s.t_blame          = -inf;
s.load_connect_time= [0 0 0 0];
s.n_shed_events    = 0;
s.event_log        = struct('time',{},'from',{},'to',{},'reason',{});
end

% =========================================================================
function s = transition(s, new_state, t, reason)
% Record state transition in event log
entry.time   = t;
entry.from   = s.state;
entry.to     = new_state;
entry.reason = reason;
s.event_log(end+1) = entry;
fprintf('[FSM t=%.3fs] S%d -> S%d: %s\n', t, s.state, new_state, reason);
s.state = new_state;
end

% =========================================================================
function [s, gates_prot] = check_protection(s, sensors, t, p, S0, SX_FAULT, SX_LOCK)
gates_prot.trip = false;
Vb = sensors.V_bus;
Is = sensors.I_src;

% I2t accumulation
if s.src_connected
    % Leaky thermal-style I2t: only current above the continuous rating (I_oc_soft) heats
    s.I2t_accum = max(0, s.I2t_accum + (Is^2 - p.prot.I_oc_soft^2) * p.ctrl.Ts_fsm);
    if Is > p.prot.I_oc_hard
        % Require sustained over-current for t_oc_trip (rejects noise spikes)
        s.t_oc_confirm = s.t_oc_confirm + p.ctrl.Ts_fsm;
        if s.t_oc_confirm >= p.prot.t_oc_trip && s.state ~= SX_FAULT && s.state ~= SX_LOCK
            s.fault_latched = true;
            s.fault_code    = 'OC_HARD';
            gates_prot.trip = true;
        end
    else
        s.t_oc_confirm = 0;
    end
    % Source-switch health: with duty ~1 and Vbus below the source open-circuit
    % voltage the Thevenin source MUST deliver (V_oc-Vb)/R_series. Measured ~0 => stuck open.
    I_expect = (p.stor.V_oc - Vb) / p.stor.R_series;
    if s.state >= 6 && s.state <= 7 && s.src_duty >= 0.95 && I_expect > p.prot.I_sw_expect_min && Is < 0.05
        s.t_sw_mismatch = s.t_sw_mismatch + p.ctrl.Ts_fsm;
        if s.t_sw_mismatch >= p.prot.t_sw_mismatch
            s.fault_latched = true; s.fault_code = 'SWITCH_FAULT'; gates_prot.trip = true;
        end
    else
        s.t_sw_mismatch = 0;
    end
    % Frozen bus-voltage sensor: reading bit-identical for sensor_freeze_time
    if abs(Vb - s.Vb_last) < 1e-6
        s.t_Vb_still = s.t_Vb_still + p.ctrl.Ts_fsm;
        if s.t_Vb_still >= p.prot.sensor_freeze_time
            s.fault_latched = true; s.fault_code = 'SENSOR_FROZEN'; gates_prot.trip = true;
        end
    else
        s.t_Vb_still = 0;
    end
    s.Vb_last = Vb;
    if s.I2t_accum > p.prot.I2t_limit && s.state ~= SX_FAULT && s.state ~= SX_LOCK
        s.fault_latched = true;
        s.fault_code    = 'I2T';
        gates_prot.trip = true;
    end
    if Vb > p.prot.V_ov_trip && s.state ~= SX_FAULT && s.state ~= SX_LOCK
        s.fault_latched = true;
        s.fault_code    = 'OV';
        gates_prot.trip = true;
    end
else
    s.I2t_accum = max(0, s.I2t_accum - p.prot.I2t_limit * 0.01 * p.ctrl.Ts_fsm);
end
end

% =========================================================================
function ok = check_sensor_sanity(sensors, p)
ok = true;
if sensors.V_bus  > p.sens.vsens.V_in_max || sensors.V_bus  < 0; ok=false; end
if sensors.V_pv   > p.sens.vsens.V_in_max || sensors.V_pv   < 0; ok=false; end
if sensors.I_src  > p.sens.acs712.I_max   || sensors.I_src  < -0.5; ok=false; end
if sensors.I_load > p.sens.acs712.I_max   || sensors.I_load < -0.5; ok=false; end
end

% =========================================================================
function s = log_event(s, ~, t, reason, code)
entry.time   = t;
entry.from   = s.state;
entry.to     = s.state;
entry.reason = [reason ':' code];
s.event_log(end+1) = entry;
end
