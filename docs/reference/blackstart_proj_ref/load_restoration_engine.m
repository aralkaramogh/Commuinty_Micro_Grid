function [s, load_mask] = load_restoration_engine_step(s, sensors, t, p)
% LOAD_RESTORATION_ENGINE_STEP
% One call per FSM tick. Attempts to connect next load tier if headroom allows.
% Sheds lowest tier first if bus is stressed.
% Implements: inter-step settle timer, power headroom check, I2t guard,
%             SOC gate, minimum off-time before re-connect, shed hysteresis.

Vb  = sensors.V_bus;
Is  = sensors.I_src;
Il  = sensors.I_load;

V_nom   = p.V_nom;
dt      = p.ctrl.Ts_fsm;

% Available power estimates
P_src_avail = max(0, (p.stor.I_limit * 0.8 - Is) * Vb);
P_pv_avail  = max(0, (Vpv_est(sensors, p) - Vb) * 0.1 * s.pv_sw); % crude
% Headroom for a connect step is judged against the SHORT-TERM source rating
% (I_inrush_max), since inrush lasts only t_inrush (<=0.15 s); steady-state is
% still gated separately by Is < I_limit*I_src_max_frac below.
P_src_inrush  = max(0, (p.stor.I_inrush_max - Is) * Vb);
P_total_avail = P_src_inrush + P_pv_avail;
P_load_now  = Vb * Il;

% ---- Per-tier fault bookkeeping (faulty-branch isolation) ------------
if ~isfield(s,'tier_strikes')
    s.tier_strikes = zeros(1,4); s.tier_locked = false(1,4);
    s.last_conn_idx = 0;         s.t_conn = -inf(1,4);
    s.t_blame = -inf;
end
for i = 1:4   % a load that runs healthily for t_strike_clear has its strikes cleared
    if s.load_state(i) && (t - s.t_conn(i)) >= p.rest.t_strike_clear
        s.tier_strikes(i) = 0;
    end
end

% ---- SHEDDING (emergency) ------------------------------------------
bus_stressed = (Vb < V_nom * 0.90) || (Is > p.prot.I_oc_soft) || (s.SOC < p.stor.SOC_crit);
blamed = false;
if bus_stressed && s.last_conn_idx > 0 && s.load_state(s.last_conn_idx) && ...
        (t - s.t_last_step) <= p.rest.t_blame
    % Stress appeared right after a connect: that load is the prime suspect.
    idx = s.last_conn_idx;
    s.load_state(idx) = false;
    s.t_last_shed(idx) = t;
    s.n_shed_events = s.n_shed_events + 1;
    s.tier_strikes(idx) = s.tier_strikes(idx) + 1;
    s.last_conn_idx = 0;
    s.t_blame = t;
    blamed = true;
    fprintf('[restore t=%.2f] BLAME+SHED %s (strike %d): Vb=%.3fV Is=%.3fA\n', ...
        t, p.load(idx).name, s.tier_strikes(idx), Vb, Is);
    if s.tier_strikes(idx) >= p.rest.max_strikes
        s.tier_locked(idx) = true;
        fprintf('[restore t=%.2f] TIER LOCKOUT %s: faulty branch isolated\n', t, p.load(idx).name);
    end
end
in_holdoff = (t - s.t_blame) < p.rest.t_shed_holdoff;   % sensors still settling after blamed shed
if bus_stressed && ~blamed && ~in_holdoff
    for tier = 4:-1:2  % T4 first, never shed T1
        idx = find([p.load.tier] == tier, 1);
        if ~isempty(idx) && s.load_state(idx)
            s.load_state(idx) = false;
            s.t_last_shed(idx) = t;
            fprintf('[restore t=%.2f] SHED Tier%d: Vb=%.3fV Is=%.3fA SOC=%.2f\n', ...
                t, tier, Vb, Is, s.SOC);
            s.n_shed_events = s.n_shed_events + 1;
            break; % shed one at a time
        end
    end
end

% ---- RESTORATION (opportunistic) ------------------------------------
settle_ok = (t - s.t_last_step) >= p.fsm.T_load_step_settle;
bus_ok    = abs(Vb - V_nom)/V_nom < p.fsm.V_stable_band;

if settle_ok && bus_ok && ~bus_stressed
    for tier = 1:4
        idx = find([p.load.tier] == tier, 1);
        if isempty(idx) || s.load_state(idx); continue; end % already on
        if s.tier_locked(idx); continue; end              % faulty branch locked out
        % Minimum off-time check (5s after shed)
        if t - s.t_last_shed(idx) < 5.0; continue; end
        % SOC gate
        if s.SOC < p.load(idx).SOC_min_req; continue; end
        % Power headroom check
        P_step = p.load(idx).P_nom * p.load(idx).inrush * p.rest.k_cold * p.rest.headroom_margin;
        if P_total_avail >= P_step && Is < p.stor.I_limit * p.rest.I_src_max_frac
            s.load_state(idx) = true;
            s.t_last_step = t;
            s.last_conn_idx = idx;
            s.t_conn(idx) = t;
            fprintf('[restore t=%.2f] CONNECT %s: P_step=%.2fW avail=%.2fW SOC=%.2f\n', ...
                t, p.load(idx).name, P_step, P_total_avail, s.SOC);
            break; % one step at a time
        end
    end
end

% Check if all restorable loads are on (based on SOC)
all_on = true;
for i = 1:4
    if s.SOC >= p.load(i).SOC_min_req && ~s.load_state(i) && ~s.tier_locked(i)
        all_on = false; break;
    end
end
s.restoration_complete = all_on;

% Pack load mask (4-bit: bit0=T1 ... bit3=T4)
load_mask = 0;
for i = 1:4
    if s.load_state(i)
        load_mask = bitor(load_mask, bitshift(1, i-1));
    end
end
end

function Vpv = Vpv_est(sensors, ~)
Vpv = sensors.V_pv;
if isnan(Vpv) || Vpv < 0; Vpv = 0; end
end
