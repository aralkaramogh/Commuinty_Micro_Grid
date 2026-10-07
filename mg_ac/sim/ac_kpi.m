function K = ac_kpi(L, sc, P)
% AC_KPI  Key numbers of one run (used by the checks, Monte Carlo and the report).
dt = P.sim.dt; n = P.n_house; Wh = dt / 3600; V0 = P.ac.V_nom; C = P.ctrl;
en = L.energised > 0;
run = L.t >= (C.N_boot + 1) * dt;                      % after the all-OFF boot
isl = (L.mode == 2 | L.mode == 3) & en;
gm  = L.mode == 1 & en & bitand(L.bits, 1) > 0;
K.bess_trip = any(L.bess_trip);
K.dead_s = sum(~en & run) * dt;                        % seconds with no supply
vt = en & run & ~L.disturbed;                         % normal operation only
K.V_min_pu = min([L.v_h(vt, :); inf(1,n)], [], 'all') / V0;
K.V_max_pu = max([L.v_h(vt, :); -inf(1,n)], [], 'all') / V0;
K.V_min_dist_pu = min([L.v_h(en & L.disturbed, :); inf(1,n)], [], 'all') / V0;
K.f_min = min([L.f_mg(isl); inf]); K.f_max = max([L.f_mg(isl); -inf]);
K.soc_min = min(L.soc); K.soc_max = max(L.soc);
K.bal_err_max = max(abs(L.bal_err));
K.locked = bitand(L.hcode(end,:), 3) == 2;
ok_t = run & en;                                       % critical service while energised
K.crit_served = sum(L.p_crit_srv(ok_t,:), 1) ./ max(sum(L.p_crit_dem(ok_t,:), 1), eps);
K.crit_ok = all(K.crit_served(~K.locked) >= 1 - 1e-9);
K.comm_served = sum(L.p_comm_srv(ok_t)) / max(sum(ok_t) * P.comm.P_crit, eps);
prev = [0; L.mode(1:end-1)];
K.n_island = sum(prev == 1 & L.mode == 2);
K.n_reconnect = sum(prev == 3 & L.mode == 1);
K.boot_grid_ok = L.grid_V_pu(1) >= C.V_ok_lo && L.grid_V_pu(1) <= C.V_ok_hi;
K.t_first_grid = first_t(L, L.mode == 1);
ca = L.close_angle(~isnan(L.close_angle));
K.close_angle_max = max([abs(ca); 0]);
K.close_dV_max = max([abs(L.close_dV(~isnan(L.close_dV))); 0]);
K.n_close = numel(ca);
ne = size(sc.events, 1);
K.island_delay = nan(1, ne); K.reconnect_delay = nan(1, ne); K.relay_closed_in_event = false;
for e = 1:ne
    a = sc.events(e,1); b = sc.events(e,2);
    K.island_delay(e) = first_t(L, L.t >= a & L.mode == 2) - a;
    K.reconnect_delay(e) = first_t(L, L.t >= b & L.mode == 1) - b;
    in = L.t >= a + (C.N_abn + 1) * dt & L.t < b;
    K.relay_closed_in_event = K.relay_closed_in_event || any(bitand(L.bits(in), 1) > 0);
end
q = abs(L.q_pcc(gm)); p = abs(L.p_pcc(gm));
if isempty(q), K.q_pcc_p95 = 0; K.pf_pcc_min = 1; else
    K.q_pcc_p95 = prctile(q, 95);
    big = p > 500; K.pf_pcc_min = min([p(big) ./ hypot(p(big), q(big)); 1]);
end
K.q_bess_max = max(abs(L.q_bess));
pnet = L.p_load - L.p_pv;                              % + import
K.import_Wh = sum(max(pnet, 0), 1) * Wh;  K.export_Wh = sum(max(-pnet, 0), 1) * Wh;
K.loss_Wh = sum(L.p_loss) * Wh;  K.grid_import_Wh = sum(max(L.p_pcc, 0)) * Wh;
K.grid_export_Wh = sum(max(-L.p_pcc, 0)) * Wh;
K.curtail_max = max(L.curtail); K.ufls = any(bitand(L.hcode, 32) > 0, 1);
K.shed_soc_first = nan(1, n);
for k = 1:n
    K.shed_soc_first(k) = first_t(L, bitand(L.hcode(:,k), 4) > 0);
end
K.ledger = ac_ledger(L, P);
end

function t = first_t(L, mask)
i = find(mask, 1);
if isempty(i), t = inf; else, t = L.t(i); end
end
