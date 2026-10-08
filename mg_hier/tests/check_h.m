function [ok, msg] = check_h(R, P)
% CHECK_H  Pass/fail rules for one run of the hierarchical microgrid.
% Same rules as the single-controller version (mg_ac/tests/check_scenario.m),
% shifted where the extra node hop delays a switching action by cmd_delay ticks,
% plus the new rules for nodes, comms loss, dashboard requests and Pi messages.
K = R.kpi; L = R.L; C = P.ctrl; dt = P.sim.dt; d = P.net.cmd_delay; f = {};
n = P.n_house; nL = P.n_load;
    function chk(c, txt), if ~c, f{end+1} = txt; end, end
    function v = at(x, t), v = x(abs(L.t - t) < dt/2, :); end
ne = size(R.sc.events, 1);
% ---- every scenario ----
blackout_ok = strcmp(R.sc.name, 'S10_long_outage_blackout');
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
        K.reconnect_delay(e) <= (C.N_grid_stable + 2 + d + ceil(360 / P.bess.sync_slip_deg)) * dt, ...
        sprintf('event %d: reconnect delay %g s', e, K.reconnect_delay(e)));
end
chk(K.n_island == ne && K.n_reconnect == ne + K.boot_grid_ok, sprintf( ...
    'islanding %d / reconnect %d, expected %d / %d', K.n_island, K.n_reconnect, ne, ne + K.boot_grid_ok));
if K.boot_grid_ok
    chk(K.t_first_grid <= (C.N_boot + C.N_grid_stable + 2 + d + ceil(360 / P.bess.sync_slip_deg)) * dt, ...
        sprintf('first grid connection only at %g s', K.t_first_grid));
end
% critical circuits (tie) of healthy nodes never open once enabled, whatever happens
on = L.t >= (C.N_boot + 1 + d) * dt;
for j = 1:nL
    if ~K.locked(j) && ~any(bitand(L.hcode(:, j), 3) > 0)
        chk(all(L.tie(on, j) == 1), sprintf('%s critical circuit opened', P.load_id{j}));
    end
end
% Pi messages
if isfield(R, 'PI') && R.PI.count.Count > 0
    chk(isempty(R.PI.bad), sprintf('Pi message problems: %s', strjoin(R.PI.bad(1:min(3,end)), ' | ')));
    chk(R.PI.count('mg/state') == numel(L.t), 'mg/state not published every tick');
end
% ---- scenario specific ----
switch R.sc.name
    case 'S1_normal_day'
        chk(K.export_Wh(1) > 100, 'House 1 (solar) did not export');
        chk(K.ledger.matrix(1,2) > 0 && K.ledger.matrix(3,2) > 0, 'no P2P sale to House 2 (from H1 and community PV)');
        chk(K.soc_min >= C.soc_reserve - 0.02, sprintf('rule dispatch went below reserve: SOC %.3f', K.soc_min));
        chk(K.q_pcc_p95 <= 150, sprintf('reactive power not compensated: |Q_pcc| p95 = %.0f var', K.q_pcc_p95));
        p2p_main = R.main_state.p2p;                  % live ledger in the main controller vs offline
        chk(max(abs(p2p_main(:) - K.ledger.matrix(:))) < 0.02 * max(1, max(K.ledger.matrix(:))), ...
            'live P2P ledger in the main controller disagrees with the offline ledger');
    case 'S2_grid_outage'
        chk(K.dead_s <= dt, 'transfer interruption longer than 1 tick');
        chk(L.soc(end) > L.soc(find(L.t >= R.sc.events(1,2), 1)) + 0.10, 'reserve not rebuilt after the outage');
    case 'S3_low_battery_outage'
        s = K.shed_soc_first;
        chk(all(isfinite(s)), sprintf('not all loads shed at low SOC: %s', mat2str(s)));
        chk(s(3) <= s(2) && s(2) <= s(1), sprintf('shed order wrong (want CL, H2, H1): %s', mat2str(s)));
        chk(K.soc_min > P.bess.soc_cutoff, sprintf('battery ran down to %.3f', K.soc_min));
    case 'S4_island_overload'
        chk(any(K.ufls), 'under-frequency shedding never acted');
        chk(max(L.ovl_t) <= P.bess.T_ovl, 'overload lasted too long');
        u = find(any(bitand(L.hcode, 32) > 0, 2), 1);    % first UF shed: next one not before N_uf_wait
        if ~isempty(u)
            nshed = sum(bitand(L.hcode(u:min(end, u + d), :), 32) > 0, 2);   % effect of a shed shows after d+1 ticks
            chk(all(nshed <= 1), 'second UF shed before the first one could act (over-shedding)');
        end
    case 'S5_island_surplus'
        chk(K.curtail_max > 0, 'PV was never curtailed');
        chk(K.f_max > P.pv.fw_f0, 'frequency never rose (no frequency-watt action)');
        chk(K.soc_max <= 1, 'SOC above 1');
    case 'S6_faulty_house'
        chk(isequal(K.locked, [false true false]), sprintf('locked = %s', mat2str(K.locked)));
        chk(L.tie(end, 1) == 1 && L.tie(end, 2) == 0 && L.tie(end, 3) == 1, 'wrong tie states at the end');
    case 'S7_abnormal_grid'
        chk(K.n_island == 2, 'expected two islanding events');
        chk(K.V_min_dist_pu < 0.85, 'sag not visible at the houses');
    case 'S8_prepaid_cards'
        lock2 = bitand(L.hcode(:,2), 16) > 0;
        chk(all(lock2(L.t >= 320 & L.t < 380)) && ~any(lock2(L.t >= 381)), 'card lockout window wrong');
        jump = @(t) at(L.bal(:,2), t) - at(L.bal(:,2), t - dt);
        chk(jump(340) < 1, 'card accepted during lockout');
        chk(jump(400) > C.card_topup - 1, 'valid card not accepted after lockout');
        out = L.bal(:,2) <= 0;
        chk(any(out), 'House 2 never ran out of credit');
        i0 = find(out, 1); i1 = find(L.t >= 7.5*3600, 1);
        chk(~isempty(i0) && i0 + d < i1 && all(L.flex(i0+d:i1-1, 2) == 0), 'flexible load stayed on at zero credit');
        chk(L.flex(end,2) == 1, 'top-up did not restore House 2');
        chk(all(L.tie(on, 2) == 1), 'House 2 critical load cut at zero credit');
    case 'S9_ai_advisor'
        st = L.ai_status; t = L.t;
        w1 = t >= 300 + d & t < 600; w2 = t >= 601 & t < 900;
        chk(all(bitand(st(w1), 2) > 0), 'unsafe AI discharge was not clamped');
        chk(all(L.p_set(w1) <= 0) && all(L.p_app(w1) <= 0), 'BESS discharged below the AI SOC floor');
        chk(all(L.flex(w1, 3) == 0) && all(L.flex(w1, 1) == 1), 'AI shed mask not applied to CL only');
        chk(all(abs(L.price(t >= 300 & t < 600) - 8) < 1e-9), 'valid AI price not accepted');
        chk(all(bitand(st(w2), 4) > 0) && all(abs(L.price(w2) - 8) < 1e-9), 'bad AI price not refused');
        w3 = t >= 900 + C.T_ai_timeout + 1 + d & t < 1500;
        chk(all(bitand(st(w3), 1) == 0) && all(abs(L.price(w3) - C.price_default) < 1e-9) ...
            && all(L.flex(w3, 3) == 1), 'no fallback to rules after AI timeout');
        w4 = t >= 1500 + (C.N_abn + 2) * dt & t < 2100 & (L.mode == 2 | L.mode == 3);
        chk(any(w4) && all(bitand(st(w4), 8) > 0), 'island AI request not refused');
    case 'S10_long_outage_blackout'
        chk(K.bess_trip, 'expected the battery to run empty in this scenario');
        a = find(L.bess_trip > 0, 1);
        chk(~isempty(a) && L.soc(a) <= P.bess.soc_cutoff + 0.01, 'BESS stopped before the battery was empty');
        back = L.t >= R.sc.events(1,2) + (C.N_grid_stable + 2 + d) * dt;
        chk(all(L.energised(back) > 0) && all(bitand(L.bits(back), 1) > 0), 'no dead-bus recovery after the grid returned');
        x = L.p_crit_srv(back, :) >= L.p_crit_dem(back, :) - 1e-9; chk(all(x(:)), 'critical loads not restored');
    case 'S12_node_comms_loss'
        t = L.t; N = P.node.N_comm_lost;
        w = t >= 300 + N - 1 & t < 330;                % H1 link down 300-330
        chk(all(L.flex(w, 1) == 0) && all(L.node_comm_lost(w, 1) == 1), 'H1 did not drop its flexible load after comms loss');
        chk(all(L.flex(t >= 300 & t < 300 + N - 1, 1) == 1), 'H1 dropped its flexible load too early');
        chk(all(L.tie(t >= 300 & t < 330, 1) == 1), 'H1 critical load cut during comms loss');
        chk(all(L.flex(t >= 331 & t < 600, 1) == 1), 'H1 flexible load not restored after the link returned');
        chk(all(bitand(L.hcode(w, 1), 1024) > 0), 'main controller did not flag H1 offline');
        e_end = L.e_imp(end, 1); x_end = L.e_exp(end, 1);   % bill = meter counters (nothing lost in the gap)
        bill = P.house(1).credit0 - (e_end - L.e_imp(1,1)) / 1000 * C.price_default ...
               + (x_end - L.e_exp(1,1)) / 1000 * C.price_default * C.sell_ratio;
        chk(abs(L.bal(end, 1) - bill) < 0.01, sprintf('H1 bill %.4f differs from meter-based %.4f', L.bal(end,1), bill));
        w = t >= 600 + N - 1 & t < 640;                % SB link down 600-640: hold set-point
        chk(all(L.sb_comm_lost(w) == 1), 'SB node did not detect comms loss');
        pa = L.p_app(t >= 600 & t < 640);
        chk(all(pa == pa(1)), 'SB node did not hold its last set-point');
        w = t >= 900 + N - 1 & t < 910;                % CL link down 900-910
        chk(all(L.flex(w, 3) == 0) && all(L.tie(t >= 900 & t < 910, 3) == 1), 'CL fallback wrong');
    case 'S13_dashboard_commands'
        A = R.acks; ids = [A.id];
        want = {1, true, ''; 2, true, ''; 3, false, 'not your house'; 4, false, 'critical loads cannot be switched off'; ...
                5, false, 'source not allowed'; 1, false, 'duplicate id'; 6, false, 'expired'; ...
                7, false, 'ttl out of range'; 8, false, 'unknown target'; 11, true, ''};
        chk(numel(A) == size(want, 1), sprintf('expected %d acks, got %d', size(want, 1), numel(A)));
        for k = 1:min(numel(A), size(want, 1))
            chk(ids(k) == want{k,1} && A(k).accepted == want{k,2} && strcmp(A(k).reason, want{k,3}), ...
                sprintf('ack %d: id %g accepted %d "%s"', k, A(k).id, A(k).accepted, A(k).reason));
        end
        chk(numel(R.drops) == 3, sprintf('broker should drop 3 requests (H2 as operator, H1 on H2''s topic, anonymous), dropped %d', numel(R.drops)));
        t = L.t;
        chk(all(L.flex(t >= 100 + d & t < 400 + d, 3) == 0) && all(L.flex(t >= 400 + d & t < 700, 3) == 1), 'operator restriction of CL wrong');
        chk(all(L.flex(t >= 150 + d & t < 350 + d, 1) == 0) && all(L.flex(t >= 350 + d & t < 700, 1) == 1), 'H1 user request wrong');
        chk(all(L.flex(t >= 250 + d & t < 310 + d, 2) == 0) && all(L.flex(t >= 310 + d & t < 700, 2) == 1) ...
            && all(L.flex(t >= 100 & t < 250 + d, 2) == 1), 'H2 restriction wrong (refused requests must not act)');
    case 'MC'
        chk(K.n_close >= ne, 'did not reconnect');
end
ok = isempty(f); msg = f;
end
