function M = pi_messages(t_s, t0_h, in, st, o, P, links)
% PI_MESSAGES  What the main controller publishes to the Pi this tick (MQTT
% topic + JSON payload). Field meanings: docs/pi_data_contract.md.
% Built only from the main controller's own view (node reports, PCC meter).
v = P.pi.version; n = P.n_house; nL = P.n_load; tick = st.tick;
hh = mod(t0_h * 3600 + t_s, 86400);
simt = sprintf('%02d:%02d:%02d', floor(hh/3600), floor(mod(hh,3600)/60), floor(mod(hh,60)));
hdr = @(s) setfield(setfield(setfield(setfield(s, 'v', v), 'tick', tick), 'sim_time', simt), 'sim_s', t_s); %#ok<SFLD>
mn = {'BOOT','GRID','ISLAND','RESYNC'}; hs = {'ok','tripped','locked','estop'};
M = struct('topic', {}, 'payload', {});
if mod(tick - 1, P.pi.state_every) == 0
    s = hdr(struct());
    s.wall_time = '';                         % filled with the PC clock in a live run
    s.mode = mn{o.mode + 1}; s.flags = o.flags; s.heartbeat = tick;
    s.grid = struct('available', logical(o.grid_ok), 'voltage_v', in.pcc.v_grid, 'frequency_hz', in.pcc.f_grid, ...
        'p_w', in.pcc.p_pcc, 'q_var', in.pcc.q_pcc, 'breaker', pick(o.breaker, 'CLOSED', 'OPEN'));
    s.bus = struct('voltage_v', in.pcc.v_c, 'frequency_hz', in.pcc.f_mg, 'dtheta_deg', in.pcc.dtheta);
    s.bess = struct('soc_pct', 100 * st.sb.soc, 'p_w', st.sb.p_bess, 'q_var', st.sb.q_bess, ...
        'p_set_w', o.p_set, 'q_set_var', o.q_set, 'fault', st.sb.bess_status ~= 0, ...
        'max_charge_w', P.bess.P_ch_max, 'max_discharge_w', P.bess.P_dis_max, 'energy_kwh', P.bess.E_kWh, ...
        'data_fresh', st.n_stale_sb == 0, 'data_age_s', st.n_stale_sb * P.sim.dt);   % SB link down -> last known values
    hpv = arrayfun(@(r) r.p_pv, st.rep(1:n));
    s.pv = struct('community_w', st.sb.p_cpv, 'houses_w', sum(hpv), 'total_w', st.sb.p_cpv + sum(hpv));
    s.loads = struct('total_w', sum(arrayfun(@(r) r.p_load, st.rep)));
    s.price_rs_kwh = o.price; s.ai_status = o.ai_status;
    s.sharing = struct('sellers', {[{P.house.id}, {'C'}]}, 'sold_wh', {sum(st.p2p, 2).'}, ...
                       'buyers', {{P.house.id}}, 'bought_wh', {sum(st.p2p, 1)});
    M(end+1) = struct('topic', 'mg/state', 'payload', s);
    for j = 1:nL
        r = st.rep(j); s = hdr(struct());
        s.node_id = P.load_id{j}; s.link = links{j}; s.online = ~o.offline(j);
        s.meter = struct('voltage_v', r.v, 'current_a', r.i, 'load_p_w', r.p_load, 'load_q_var', r.q_load, ...
            'pv_p_w', r.p_pv, 'pv_q_var', r.q_pv, 'net_p_w', r.p_pv - r.p_load);
        s.relays = struct('critical_on', r.tie == 1, 'flexible_on', r.flex == 1);
        s.protection = hs{r.hstate + 1}; s.node_comm_lost = r.comm_lost == 1;
        s.energy = struct('import_wh', r.e_imp, 'export_wh', r.e_exp);
        s.status_code = o.code(j);
        M(end+1) = struct('topic', ['mg/node/' P.load_id{j}], 'payload', s); %#ok<AGROW>
    end
    s = hdr(struct()); b = st.sb;
    s.node_id = 'SB'; s.link = links{nL + 1}; s.online = ~o.offline(nL + 1);
    s.bess = struct('soc_pct', 100 * b.soc, 'p_w', b.p_bess, 'q_var', b.q_bess, 'fault', b.bess_status ~= 0);
    s.inverter = struct('p_applied_w', b.p, 'q_applied_var', b.q, 'clamped', b.clamped == 1, 'sync', b.sync == 1, 'estop', b.clamped == 2);
    s.pv_p_w = b.p_cpv; s.node_comm_lost = b.comm_lost == 1;
    M(end+1) = struct('topic', 'mg/node/SB', 'payload', s);
end
if mod(tick - 1, P.pi.account_every) == 0
    for k = 1:n
        s = hdr(struct()); r = st.rep(k);
        s.house_id = P.house(k).id; s.balance_rs = st.bal(k); s.credit_ok = st.credit_ok(k) == 1;
        s.flexible_allowed = o.cmd_load(k).flex_allow == 1; s.price_rs_kwh = o.price;
        s.import_wh = r.e_imp; s.export_wh = r.e_exp;
        s.bought_from_peers_wh = sum(st.p2p(:, k)); s.sold_to_peers_wh = sum(st.p2p(k, :));
        s.status_code = o.code(k);
        M(end+1) = struct('topic', ['mg/house/' P.house(k).id '/account'], 'payload', s); %#ok<AGROW>
    end
end
for e = 1:numel(o.events)
    s = hdr(struct()); ev = o.events{e};
    s.type = ev.type; s.node = ev.node; s.text = ev.text;
    M(end+1) = struct('topic', 'mg/event', 'payload', s); %#ok<AGROW>
end
for a = 1:numel(o.acks)
    ak = o.acks(a); s = hdr(struct());
    s.id = ak.id; s.accepted = ak.accepted; s.reason = ak.reason;
    switch ak.src
        case 'user', tp = ['mg/ack/user/' ak.user];
        case {'op', 'ai'}, tp = ['mg/ack/' ak.src];
        otherwise, tp = 'mg/ack/unknown';
    end
    M(end+1) = struct('topic', tp, 'payload', s); %#ok<AGROW>
end
end

function s = pick(c, a, b)
if c, s = a; else, s = b; end
end
