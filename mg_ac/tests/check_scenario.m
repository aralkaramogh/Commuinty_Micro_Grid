function [ok, msg] = check_scenario(R, P)
% CHECK_SCENARIO  Pass/fail rules. Returns ok and the list of failed rules.
K = R.kpi; L = R.L; C = P.ctrl; dt = P.sim.dt; f = {};
    function chk(c, txt), if ~c, f{end+1} = txt; end, end
ne = size(R.sc.events, 1);
% ---- every scenario ----
blackout_ok = strcmp(R.sc.name, 'S10_long_outage_blackout');   % the one scenario where it must happen
chk(~K.bess_trip || blackout_ok, 'BESS inverter tripped (overload)');
chk(K.bal_err_max < 1e-6, sprintf('power balance error %.2e W', K.bal_err_max));
chk(K.V_min_pu >= P.req.V_lo && K.V_max_pu <= P.req.V_hi, ...
    sprintf('house voltage %.3f-%.3f pu outside %.2f-%.2f', K.V_min_pu, K.V_max_pu, P.req.V_lo, P.req.V_hi));
chk(isinf(K.f_min) || (K.f_min >= P.req.f_lo && K.f_max <= P.req.f_hi), ...
    sprintf('island frequency %.3f-%.3f Hz', K.f_min, K.f_max));
chk(K.crit_ok, sprintf('critical load not fully served while energised: %s', mat2str(K.crit_served, 5)));
chk(K.comm_served >= 1 - 1e-9, 'community critical load not served');
chk(all(L.bits(L.t < C.N_boot * dt) == 0), 'a switch was ON during boot');
chk(K.dead_s <= ne * dt || blackout_ok, sprintf('%g s without supply (allowed: 1 tick per grid event)', K.dead_s));
chk(K.close_angle_max <= P.req.dth_close, sprintf('breaker closed at %.1f deg', K.close_angle_max));
chk(~K.relay_closed_in_event, 'grid breaker closed during a grid disturbance');
for e = 1:ne
    chk(K.island_delay(e) <= C.N_abn * dt, sprintf('event %d: island delay %g s', e, K.island_delay(e)));
    chk(K.reconnect_delay(e) >= (C.N_grid_stable - 1) * dt && ...
        K.reconnect_delay(e) <= (C.N_grid_stable + 2 + ceil(360 / P.bess.sync_slip_deg)) * dt, ...
        sprintf('event %d: reconnect delay %g s', e, K.reconnect_delay(e)));
end
chk(K.n_island == ne && K.n_reconnect == ne + K.boot_grid_ok, sprintf( ...
    'islanding %d / reconnect %d, expected %d / %d', K.n_island, K.n_reconnect, ne, ne + K.boot_grid_ok));
if K.boot_grid_ok
    chk(K.t_first_grid <= (C.N_boot + C.N_grid_stable + 2 + ceil(360 / P.bess.sync_slip_deg)) * dt, ...
        sprintf('first grid connection only at %g s', K.t_first_grid));
end
% ---- scenario specific ----
switch R.sc.name
    case 'S1_normal_day'
        chk(K.export_Wh(1) > 100 && K.export_Wh(2) > 100, 'solar houses did not export');
        chk(K.ledger.matrix(1,3) > 0 && K.ledger.matrix(2,3) > 0, 'no P2P sale to House 3');
        chk(K.soc_min >= C.soc_reserve - 0.02, sprintf('rule dispatch went below reserve: SOC %.3f', K.soc_min));
        chk(K.q_pcc_p95 <= 150, sprintf('reactive power not compensated: |Q_pcc| p95 = %.0f var', K.q_pcc_p95));
    case 'S2_grid_outage'
        chk(K.dead_s <= dt, 'transfer interruption longer than 1 tick');
        chk(L.soc(end) > L.soc(find(L.t >= R.sc.events(1,2), 1)) + 0.10, 'reserve not rebuilt after the outage');
    case 'S3_low_battery_outage'
        s = K.shed_soc_first;
        chk(all(isfinite(s)), 'not all houses shed at low SOC');
        chk(s(3) <= s(2) && s(2) <= s(1), sprintf('shed order wrong: %s', mat2str(s)));
        chk(K.soc_min > P.bess.soc_cutoff, sprintf('battery ran down to %.3f', K.soc_min));
    case 'S4_island_overload'
        chk(any(K.ufls), 'under-frequency shedding never acted');
        chk(max(L.ovl_t) <= P.bess.T_ovl, 'overload lasted too long');
    case 'S5_island_surplus'
        chk(K.curtail_max > 0, 'PV was never curtailed');
        chk(K.f_max > P.pv.fw_f0, 'frequency never rose (no frequency-watt action)');
        chk(K.soc_max <= 1, 'SOC above 1');
    case 'S6_faulty_house'
        chk(isequal(K.locked, [false false true]), sprintf('locked = %s', mat2str(K.locked)));
        chk(all(L.tie(end, 1:2) == 1) && L.tie(end, 3) == 0, 'wrong tie states at the end');
    case 'S7_abnormal_grid'
        chk(K.n_island == 2, 'expected two islanding events');
        chk(K.V_min_dist_pu < 0.85, 'sag not visible at the houses');
    case 'S8_prepaid_cards'
        lock3 = bitand(L.hcode(:,3), 16) > 0;
        chk(all(lock3(L.t >= 320 & L.t < 380)) && ~any(lock3(L.t >= 381)), 'card lockout window wrong');
        jump = @(t) L.bal(L.t == t, 3) - L.bal(L.t == t - dt, 3);
        chk(jump(340) < 1, 'card accepted during lockout');
        chk(jump(400) > C.card_topup - 1, 'valid card not accepted after lockout');
        out = L.bal(:,3) <= 0;
        chk(any(out), 'House 3 never ran out of credit');
        i0 = find(out, 1); i1 = find(L.t >= 7.5*3600, 1);
        chk(~isempty(i0) && all(L.flex(i0:i1-1, 3) == 0), 'flexible load stayed on at zero credit');
        chk(L.flex(end,3) == 1, 'top-up did not restore House 3');
    case 'S9_ai_advisor'
        st = L.ai_status; t = L.t;
        w1 = t >= 301 & t < 600; w2 = t >= 601 & t < 900;
        chk(all(bitand(st(w1), 2) > 0), 'unsafe AI discharge was not clamped');
        chk(all(L.p_set(w1) <= 0), 'BESS discharged below the AI SOC floor');
        chk(all(L.flex(w1, 3) == 0) && all(L.flex(w1, 1) == 1), 'AI shed mask not applied to H3 only');
        chk(all(abs(L.price(w1) - 8) < 1e-9), 'valid AI price not accepted');
        chk(all(bitand(st(w2), 4) > 0) && all(abs(L.price(w2) - 8) < 1e-9), 'bad AI price not refused');
        w3 = t >= 900 + C.T_ai_timeout + 2*dt & t < 1500;
        chk(all(bitand(st(w3), 1) == 0) && all(abs(L.price(w3) - C.price_default) < 1e-9) ...
            && all(L.flex(w3, 3) == 1), 'no fallback to rules after AI timeout');
        w4 = t >= 1500 + (C.N_abn + 2) * dt & t < 2100 & (L.mode == 2 | L.mode == 3);
        chk(any(w4) && all(bitand(st(w4), 8) > 0), 'island AI request not refused');
    case 'S10_long_outage_blackout'
        chk(K.bess_trip, 'expected the battery to run empty in this scenario');
        a = find(L.bess_trip > 0, 1);
        chk(~isempty(a) && L.soc(a) <= P.bess.soc_cutoff + 0.01, 'BESS stopped before the battery was empty');
        back = L.t >= R.sc.events(1,2) + (C.N_grid_stable + 2) * dt;
        chk(all(L.energised(back) > 0) && all(bitand(L.bits(back), 1) > 0), 'no dead-bus recovery after the grid returned');
        chk(all(L.p_crit_srv(back, :) >= L.p_crit_dem(back, :) - 1e-9, 'all'), 'critical loads not restored');
    case 'MC'
        chk(K.n_close >= ne, 'did not reconnect');
end
ok = isempty(f); msg = f;
end
