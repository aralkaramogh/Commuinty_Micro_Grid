function [ps, m, y] = plant_step_h(ps, act, ext, P)
% PLANT_STEP_H  One step of the AC community microgrid (phasor / RMS model).
% PHYSICS ONLY: no control decisions here. Same physics as mg_ac/models/plant_step.m,
% plus a switchable community load (critical part + flexible water pump).
%   act: what the switches/inverter actually do this step
%        breaker, sync (from main / SB node), tie(1..nL), flex(1..nL), p_set, q_set
%        load index 1..n = houses, n+1 = community load (CL)
%   ext: from profiles_h
% Signs: loads + drawn, PV + produced, BESS + discharging, PCC + = microgrid imports.
n = P.n_house; H = P.house; dt = P.sim.dt; V0 = P.ac.V_nom; b = P.bess; nL = P.n_load;

grid_avail = ext.grid_V_pu >= P.grid.V_dead;
Vg = ext.grid_V_pu * V0;                  % grid voltage phasor, angle 0 (reference)
fg = ext.grid_f * grid_avail;

% ---- breaker closing event: record synchronisation quality ----
y.close_angle = NaN; y.close_dV = NaN; y.close_df = NaN;
if act.breaker && ~ps.breaker_prev && ps.prev_energised && grid_avail
    y.close_angle = ps.dtheta; y.close_dV = ps.prev_Vc - Vg; y.close_df = ps.prev_f - fg;
end
ps.breaker_prev = act.breaker;

% ---- what is connected this tick ----
tieA = act.tie(:).'; flexA = act.flex(:).';
tie = tieA(1:n); flex = flexA(1:n); tie_cl = tieA(nL); flex_cl = flexA(nL);
Pc = zeros(1,n); Qc = Pc; Pf = Pc; Qf = Pc; Pav = Pc; Sinv = Pc; Yh = Pc;
for k = 1:n
    Pc(k) = H(k).P_crit * ext.d_crit(k);          Qc(k) = Pc(k) * tan(acos(H(k).pf_crit));
    Pf(k) = H(k).P_flex * ext.d_flex(k);          Qf(k) = Pf(k) * tan(acos(H(k).pf_flex));
    Pav(k) = pv_power(H(k).pv_kWp, ext.G, ext.T_amb, P);
    Sinv(k) = P.pv.S_over * H(k).pv_kWp * 1000;
    if ext.R_fault(k) > 0, Yh(k) = 1 / ext.R_fault(k); end
end
y.p_crit_dem = Pc; y.p_flex_dem = [Pf, P.comm.P_flex * ext.d_cflex];
Pcc = P.comm.P_crit * ext.d_comm;  Pcf = P.comm.P_flex * ext.d_cflex;      % community crit / pump demand
P_cl = tie_cl * (Pcc + flex_cl * Pcf);
Q_cl = tie_cl * (Pcc * tan(acos(P.comm.pf_crit)) + flex_cl * Pcf * tan(acos(P.comm.pf_flex)));
P_cav = pv_power(P.comm.pv_kWp, ext.G, ext.T_amb, P);
% house PV reactive power from volt-var, using last tick's voltage (inverter lag)
Qpv = zeros(1,n);
for k = 1:n
    if Sinv(k) > 0
        q = volt_var(ps.Vh_prev(k), P) * Sinv(k);
        qmax = sqrt(max(0, Sinv(k)^2 - Pav(k)^2));
        Qpv(k) = min(max(q, -qmax), qmax);
    end
end
Pload = tie .* (Pc + flex .* Pf);  Qload = tie .* (Qc + flex .* Qf);
Yh = tie .* Yh;

[P_lo, P_hi] = bess_limits(ps.soc, P);
c = 0; Pb = 0; Qb = 0; Vc = 0; Vh = zeros(1,n); Ih = zeros(1,n); f_mg = 0;
P_pcc = 0; Q_pcc = 0; mode = 'dead'; Ppv = zeros(1,n); Qp = zeros(1,n);
if isfield(act, 'bess_stop') && act.bess_stop && ~(act.breaker && grid_avail)
    ps.bess_trip = true;                     % E-stop on the SB node: the inverter stops; an island goes dark
end
if act.breaker && grid_avail
    mode = 'grid';
elseif ~act.breaker && ~ps.bess_trip
    mode = 'island';
end

switch mode
case 'grid'      % grid forms the voltage; BESS follows its P/Q set-points
    ps.bess_trip = false; ps.ovl_t = 0;      % a tripped inverter restarts once the grid is back
    Pb = min(max(act.p_set, P_lo), P_hi);
    qa = sqrt(max(0, b.S_rated^2 - Pb^2));
    Qb = min(max(act.q_set, -qa), qa);
    Ppv = tie .* Pav; Qp = tie .* Qpv;
    Sh = (Pload - Ppv) + 1i * (Qload - Qp);
    Sc = (P_cl - P_cav - Pb) + 1i * (Q_cl - Qb);
    [Vc, Vh, Ih, Ic, ok] = net_solve('grid', Vg, P.grid.Z_th, Sh, Yh, [H.Z_line], Sc);
    assert(ok, 'grid power flow did not converge');
    S_pcc = Vc * conj(Ic);  P_pcc = real(S_pcc); Q_pcc = imag(S_pcc);
    f_mg = fg; ps.dtheta = 0;
case 'island'    % BESS inverter forms the voltage (grid-forming, droop)
    syncing = act.sync && grid_avail;
    Vm = V0; Ptot_pv = sum(tie .* Pav) + P_cav;
    for it = 1:60
        Ppv = tie .* Pav * (1 - c); Qp = tie .* Qpv;
        Sh = (Pload - Ppv) + 1i * (Qload - Qp);
        Sc = (P_cl - P_cav * (1 - c)) + 1i * Q_cl;
        [Vc, Vh, Ih, Ic, ok] = net_solve('island', Vm, 0, Sh, Yh, [H.Z_line], Sc);
        assert(ok, 'island power flow did not converge');
        Sb = Vc * conj(Ic); Pb = real(Sb); Qb = imag(Sb);
        c_old = c;
        if Ptot_pv > 0                    % frequency-watt curtailment of the PV
            if Pb < P_lo
                c = min(1, c + (P_lo - Pb) / Ptot_pv);
            elseif c > 0 && Pb > P_lo
                c = max(0, c - (Pb - P_lo) / Ptot_pv);
            end
        end
        if syncing, Vm_new = Vg; else, Vm_new = V0 * (1 - b.nq * Qb / b.S_rated); end
        if abs(Vm_new - Vm) < 1e-9 && abs(c - c_old) < 1e-12, break; end
        Vm = Vm_new;
    end
    f_droop = P.ac.f_nom - b.mp * Pb / b.P_dis_max;
    if syncing
        f_mg = fg + b.sync_slip_deg / (360 * dt);
    elseif c > 0
        f_mg = max(f_droop, P.pv.fw_f0 + (P.pv.fw_f1 - P.pv.fw_f0) * c);
    else
        f_mg = f_droop;
    end
    if Pb > P_hi + 1 || abs(Pb + 1i*Qb) > b.S_rated   % inverter overloaded
        ps.ovl_t = ps.ovl_t + dt;
    else
        ps.ovl_t = 0;
    end
    if ps.ovl_t > b.T_ovl, ps.bess_trip = true; end
otherwise        % de-energised (grid dead with breaker closed, or BESS tripped)
    P_cl = 0; Q_cl = 0; P_cav = 0;
end
energised = ~strcmp(mode, 'dead');
if ~energised, Pload = zeros(1,n); Qload = zeros(1,n); Pb = 0; Qb = 0; Ppv = zeros(1,n); Qp = zeros(1,n); end

% ---- measurements (true values; the run splits them into node meters + PCC meter) ----
m.v_grid = abs(Vg); m.f_grid = fg;
m.v_c = abs(Vc); m.f_mg = f_mg; m.dtheta = ps.dtheta;
m.p_pcc = P_pcc; m.q_pcc = Q_pcc; m.p_bess = Pb; m.q_bess = Qb;
m.soc = ps.soc; m.bess_status = double(ps.bess_trip);
m.p_cl = P_cl; m.q_cl = Q_cl; m.p_cpv = P_cav * (1 - c) * energised;
m.i_cl = 0; if energised && abs(Vc) > 0, m.i_cl = abs(P_cl + 1i*Q_cl) / abs(Vc); end
m.v_h = abs(Vh); m.i_h = abs(Ih); m.p_load = Pload; m.q_load = Qload;
m.p_pv = Ppv; m.q_pv = Qp;

% ---- log ----
y.mode = mode; y.energised = energised; y.curtail = c; y.p_pv_avail = [tie .* Pav, P_cav];
y.p_crit_srv = tie .* Pc * energised; y.p_flex_srv = [tie .* flex .* Pf, tie_cl * flex_cl * Pcf] * energised;
y.p_comm_dem = Pcc; y.p_comm_srv = tie_cl * Pcc * energised;
if energised      % losses two ways: power balance vs I^2 R (checks the solver)
    P_in = P_pcc + Pb + sum(m.p_pv) + m.p_cpv;
    P_out = sum(Pload) + P_cl + sum(Yh .* abs(Vh).^2);
    P_loss_I2R = sum(abs(Ih).^2 .* real([H.Z_line]));
    y.p_loss = P_in - P_out; y.bal_err = y.p_loss - P_loss_I2R;
else
    y.p_loss = 0; y.bal_err = 0;
end
y.ovl_t = ps.ovl_t;
y.disturbed = (act.breaker && abs(ext.grid_V_pu - 1) > 0.10) || any(tie & ext.R_fault > 0);

% ---- state update ----
if Pb >= 0
    ps.soc = ps.soc - Pb * dt / 3600 / (b.E_kWh * 1000) / b.eta_dis;
else
    ps.soc = ps.soc - Pb * b.eta_ch * dt / 3600 / (b.E_kWh * 1000);
end
ps.soc = min(max(ps.soc, 0), 1);
if strcmp(mode, 'island')
    f_ref = P.ac.f_nom; if grid_avail, f_ref = fg; end
    ps.dtheta = wrap180(ps.dtheta + 360 * (f_mg - f_ref) * dt);
end
if energised, ps.Vh_prev = abs(Vh); end
ps.prev_energised = energised; ps.prev_Vc = abs(Vc); ps.prev_f = f_mg;
end
