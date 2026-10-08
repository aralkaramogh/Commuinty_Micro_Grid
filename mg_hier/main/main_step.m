function [st, o] = main_step(st, in, P)
% MAIN_STEP  One tick of the MAIN (community) controller.
% Same control rules as the verified single-controller version
% (mg_ac/controller/ac_controller_step.m), but split by layer:
%   - fast safety (over-current trip, critical hold, BESS hard limits) is now in
%     the NODES (nodes/node_load_step.m, nodes/node_sb_step.m);
%   - this function coordinates: operating mode, synchronisation + grid breaker,
%     BESS dispatch, load shedding priority, prepaid ledger, P2P sharing and the
%     checking of every request from the Pi (dashboards / AI).
% in: ONLY node reports + PCC meter + Pi inbox (input firewall, main_inputs_spec.m)
% o : breaker (direct to plant), commands to each node, acks, log values, events
check_main_inputs(in);
C = P.ctrl; n = P.n_house; nL = P.n_load; dt = P.sim.dt; H = P.house; V0 = P.ac.V_nom; b = P.bess;
st.tick = st.tick + 1; t = in.t_s;
o.events = {};

% ---------- node reports: keep the last good one, count missing ones ----------
fresh = false(1, nL);
for j = 1:nL
    if in.load(j).ok, st.rep(j) = in.load(j); st.n_stale(j) = 0; fresh(j) = true;
    else, st.n_stale(j) = st.n_stale(j) + 1; end
end
if in.sb.ok, st.sb = in.sb; st.n_stale_sb = 0; else, st.n_stale_sb = st.n_stale_sb + 1; end
offline = [st.n_stale, st.n_stale_sb] >= P.node.N_comm_lost;
soc = st.sb.soc;
bess_fault = st.sb.bess_status ~= 0;

% ---------- grid health (PCC meter) ----------
m = in.pcc;
vg = m.v_grid / V0;
grid_ok   = vg >= C.V_ok_lo && vg <= C.V_ok_hi && m.f_grid >= C.F_ok_lo && m.f_grid <= C.F_ok_hi;
grid_lost = vg < C.V_lost;
if grid_ok
    st.n_good = st.n_good + 1; st.n_bad = 0;
else
    st.n_bad = st.n_bad + 1; st.n_good = 0;
end

% ---------- operating mode ----------
mode0 = st.mode;
switch st.mode
    case 0   % BOOT: all off; the BESS forms the bus, so always start islanded
        if st.tick > C.N_boot, st.mode = 2; end
    case 1   % GRID
        if grid_lost || st.n_bad >= C.N_abn
            st.mode = 2; st.n_island = st.n_island + 1;
        end
    case 2   % ISLAND
        if st.n_good >= C.N_grid_stable, st.mode = 3; end
    case 3   % RESYNC: BESS slips slowly; close when V, f and phase all match
        if ~grid_ok
            st.mode = 2;
        elseif m.v_c < C.V_lost * V0
            st.mode = 1; st.n_reconnect = st.n_reconnect + 1;   % dead-bus closing
        else
            pred = wrap180(m.dtheta + 360 * (m.f_mg - m.f_grid) * dt);   % angle at closing
            if abs(m.v_grid - m.v_c) <= C.DV_sync && abs(m.f_mg - m.f_grid) <= C.DF_sync ...
                    && abs(pred) <= C.DTH_sync
                st.mode = 1; st.n_reconnect = st.n_reconnect + 1;
            end
        end
end
if st.mode ~= mode0
    mn = {'BOOT','GRID','ISLAND','RESYNC'};
    o.events{end+1} = struct('type', 'mode', 'node', 'MAIN', 'text', sprintf('%s -> %s', mn{mode0+1}, mn{st.mode+1}));
end
booted = st.mode ~= 0;
island = st.mode == 2 || st.mode == 3;
gridm  = st.mode == 1;

% ---------- requests from the Pi (dashboards, AI): checked, then applied or refused ----------
ai_status = 0; ai_seen = false;
o.acks = struct('id', {}, 'src', {}, 'user', {}, 'accepted', {}, 'reason', {});
for c = 1:numel(in.inbox)
    [src, user, kind] = parse_cmd_topic(in.inbox(c).topic);
    q = in.inbox(c).payload; if ~isstruct(q), q = struct(); end
    acc = false; why = '';
    val = getf(q, 'value'); ttl = getf(q, 'ttl');
    if ~isfield(q, 'id') || ~isnumeric(q.id) || ~isscalar(q.id)
        why = 'missing id';
    elseif any(st.ids == q.id)
        why = 'duplicate id';
    elseif ~(t - getf(q, 't_sent') <= C.T_cmd_stale && getf(q, 't_sent') <= t)
        why = 'expired';
    else
        j = 0; tg = ''; if isfield(q, 'target') && ischar(q.target), tg = q.target; end
        if ~isempty(tg), j = find(strcmp(P.load_id, tg), 1); if isempty(j), j = 0; end, end
        switch kind
            case 'ai_advice'
                if ~strcmp(src, 'ai')
                    why = 'source not allowed';
                else
                    pb = getf(q, 'p_bess'); mask = getf(q, 'shed_mask'); pr = getf(q, 'price');
                    if ~(isfinite(pb) && isfinite(mask) && mask >= 0 && mask == round(mask))
                        why = 'bad value';
                    else
                    acc = true; ai_seen = true;
                    st.ai_active = 1; st.ai_age = 0; st.ai_p = pb;
                    for k = 1:nL, st.shed_ai(k) = double(bitand(mask, 2^(k-1)) > 0); end
                    if pr >= C.price_min && pr <= C.price_max
                        st.price = pr;
                    else
                        ai_status = ai_status + 4; why = 'price refused';
                    end
                    end
                end
            case 'restrict'          % operator: hold a node's flexible load off for ttl seconds
                if ~strcmp(src, 'op')
                    why = 'source not allowed';
                elseif j == 0
                    why = 'unknown target';
                elseif ~(val == 0 || val == 1)
                    why = 'bad value';
                elseif val == 1 && ~(ttl > 0 && ttl <= C.T_cmd_max)
                    why = 'ttl out of range';
                elseif val == 1
                    st.op_until(j) = t + ttl; acc = true;
                else
                    st.op_until(j) = 0; acc = true;
                end
            case 'user_flex'         % a household switches its OWN flexible load off / back on
                if ~strcmp(src, 'user')
                    why = 'source not allowed';
                elseif j == 0 || j > n
                    why = 'unknown target';
                elseif ~strcmp(tg, user)
                    why = 'not your house';
                elseif ~(val == 0 || val == 1)
                    why = 'bad value';
                elseif val == 0 && ~(ttl > 0 && ttl <= C.T_cmd_max)
                    why = 'ttl out of range';
                elseif val == 0
                    st.user_until(j) = t + ttl; acc = true;
                else
                    st.user_until(j) = 0; acc = true;
                end
            case {'cut_critical', 'critical_off'}
                why = 'critical loads cannot be switched off';
            otherwise
                why = 'unknown command';
        end
    end
    if isfield(q, 'id') && isnumeric(q.id) && isscalar(q.id)       % remember ids (blocks replays)
        st.id_ptr = mod(st.id_ptr, C.N_ids) + 1; st.ids(st.id_ptr) = q.id; id = q.id;
    else
        id = NaN;
    end
    o.acks(end+1) = struct('id', id, 'src', src, 'user', user, 'accepted', acc, 'reason', why);
    if ~acc
        o.events{end+1} = struct('type', 'refused', 'node', 'MAIN', 'text', sprintf('%s/%s id %g: %s', src, kind, id, why));
    end
end
if ~ai_seen && st.ai_active
    st.ai_age = st.ai_age + dt;
    if st.ai_age > C.T_ai_timeout                  % AI silent: fall back to rules
        st.ai_active = 0; st.shed_ai = zeros(1,nL); st.price = C.price_default;
    end
end
if st.ai_active, ai_status = ai_status + 1; end
shed_op = double(t < st.op_until); shed_user = double(t < st.user_until);

% ---------- RFID cards (read by the house nodes, checked here against the ledger) ----------
for k = 1:n
    if st.card_lock(k) > 0, st.card_lock(k) = st.card_lock(k) - 1; end
end
for k = 1:n
    uid = in.load(k).card_uid;
    if ~fresh(k) || uid == 0, continue; end
    if st.card_lock(k) > 0
        % locked: ignore
    elseif uid == H(k).card_uid
        st.bal(k) = st.bal(k) + C.card_topup; st.bad(k) = 0;
        o.events{end+1} = struct('type', 'card', 'node', H(k).id, 'text', 'top-up accepted');
    else
        st.bad(k) = st.bad(k) + 1;
        o.events{end+1} = struct('type', 'card', 'node', H(k).id, 'text', 'unknown card');
        if st.bad(k) >= C.card_bad_max, st.card_lock(k) = C.N_card_lock; st.bad(k) = 0; end
    end
end

% ---------- island under-frequency load shedding ----------
% one load per decision; the next decision waits N_uf_wait ticks so the last
% shed has reached its node and shows in the frequency (avoids over-shedding)
st.uf_wait = max(0, st.uf_wait - 1);
if island
    if m.f_mg > 0 && m.f_mg < C.F_ufls
        if st.uf_wait == 0
            for k = nL:-1:1                          % lowest priority = highest index
                if st.shed_uf(k) == 0, st.shed_uf(k) = 1; st.uf_wait = C.N_uf_wait; break; end
            end
        end
        st.uf_hold = C.T_uf_hold;
    elseif st.uf_hold > 0
        st.uf_hold = st.uf_hold - dt;
    else
        for k = 1:nL                                 % restore highest priority first
            if st.shed_uf(k) == 1
                if st.sb.p_bess + P.load_P_flex(k) <= C.UF_restore * b.P_dis_max
                    st.shed_uf(k) = 0; st.uf_hold = C.T_uf_step;
                end
                break;
            end
        end
    end
else
    st.shed_uf = zeros(1,nL); st.uf_hold = 0; st.uf_wait = 0;
end

% ---------- per load node ----------
any_locked = 0; any_shed = 0; any_card = 0;
o.cmd_load = struct('enable', cell(1,nL), 'flex_allow', cell(1,nL));
o.code = zeros(1,nL);
for j = 1:nL
    r = st.rep(j);
    if r.hstate ~= st.prev_hstate(j)
        hs = {'ok','tripped (retry)','LOCKED OUT'};
        o.events{end+1} = struct('type', 'protection', 'node', P.load_id{j}, 'text', hs{r.hstate+1});
        st.prev_hstate(j) = r.hstate;
    end
    % island battery-priority shedding (critical loads are never shed)
    if island
        if soc < P.load_shed_soc(j)
            st.shed_soc(j) = 1;
        elseif soc > P.load_shed_soc(j) + C.soc_hyst
            st.shed_soc(j) = 0;
        end
    else
        st.shed_soc(j) = 0;
    end
    credit_ok = 1;
    if j <= n
        % prepaid account [Rs] from the node's energy counters (no energy is lost
        % from the bill if reports are missing for a while: the counter keeps counting)
        if fresh(j)
            if ~isnan(st.e_imp0(j)) && (r.e_imp < st.e_imp0(j) || r.e_exp < st.e_exp0(j))
                st.e_imp0(j) = NaN;                       % counter went back: the node was reset -> rebase, bill nothing
            end
            if ~isnan(st.e_imp0(j))
                d_imp = r.e_imp - st.e_imp0(j); d_exp = r.e_exp - st.e_exp0(j);
                st.bal(j) = st.bal(j) - d_imp / 1000 * st.price + d_exp / 1000 * st.price * C.sell_ratio;
            end
            st.e_imp0(j) = r.e_imp; st.e_exp0(j) = r.e_exp;
        end
        if st.bal(j) <= 0
            st.credit_ok(j) = 0;
        elseif st.bal(j) >= C.credit_restore
            st.credit_ok(j) = 1;
        end
        credit_ok = st.credit_ok(j);
        if st.card_lock(j) > 0, any_card = 1; end
    end
    flex_ok = st.shed_soc(j) == 0 && st.shed_uf(j) == 0 && st.shed_ai(j) == 0 && ...
              shed_op(j) == 0 && shed_user(j) == 0 && credit_ok == 1;
    o.cmd_load(j).enable = double(booted);       % critical loads: on once booted, never commanded off
    o.cmd_load(j).flex_allow = double(booted && flex_ok);
    if r.hstate == 2, any_locked = 1; end
    if st.shed_soc(j) || st.shed_uf(j) || st.shed_ai(j) || shed_op(j), any_shed = 1; end
    lock_k = 0; if j <= n, lock_k = st.card_lock(j) > 0; end
    o.code(j) = r.hstate + 4*st.shed_soc(j) + 8*(1 - credit_ok) + 16*lock_k + 32*st.shed_uf(j) ...
              + 64*st.shed_ai(j) + 128*shed_op(j) + 256*shed_user(j) + 512*(r.comm_lost ~= 0) + 1024*offline(j);
end

% ---------- live P2P sharing ledger [Wh] (pro rata, like sim/ledger_h.m) ----------
pn = zeros(1,n);
for k = 1:n, pn(k) = st.rep(k).p_load - st.rep(k).p_pv; end
e = [max(-pn, 0), max(st.sb.p_cpv - st.rep(nL).p_load, 0)];   % sellers: houses, community PV
d = max(pn, 0); E = sum(e); D = sum(d); S = min(E, D);
if S > 0, st.p2p = st.p2p + (e.' / E) * (d / D) * S * dt / 3600; end

% ---------- BESS set-points (used by the inverter only when grid-connected) ----------
p_set = 0; q_set = 0;
if gridm
    net_p = -st.sb.p_cpv; net_q = 0;
    for j = 1:nL
        net_p = net_p + st.rep(j).p_load - st.rep(j).p_pv;
        net_q = net_q + st.rep(j).q_load - st.rep(j).q_pv;
    end
    p_lo = 0; if soc < C.soc_ch_stop, p_lo = -b.P_ch_max; end
    if st.ai_active
        p_hi = 0; if soc > C.soc_ai_min, p_hi = b.P_dis_max; end
        p_set = min(max(st.ai_p, p_lo), p_hi);
        if p_set ~= st.ai_p, ai_status = ai_status + 2; end      % clamped to safe range
    else
        p_hi = 0; if soc > C.soc_reserve, p_hi = b.P_dis_max; end
        p_set = min(max(net_p, p_lo), p_hi);                     % self-consumption rule
        if soc < C.soc_reserve                                   % rebuild the outage reserve
            p_set = max(min(p_set, -C.P_recharge), p_lo);
        end
    end
    q_av = sqrt(max(0, b.S_rated * b.S_rated - p_set * p_set));
    q_set = min(max(net_q, -q_av), q_av);                        % reactive compensation
elseif st.ai_active && st.ai_p ~= 0
    ai_status = ai_status + 8;        % islanded: BESS follows physics, AI request ignored
end

o.breaker = double(gridm);                                       % direct to the grid breaker
o.cmd_sb = struct('p_set', p_set, 'q_set', q_set, 'sync', double(st.mode == 3));
o.mode = st.mode; o.p_set = p_set; o.q_set = q_set; o.price = st.price; o.ai_status = ai_status;
o.bal = st.bal; o.offline = offline; o.grid_ok = grid_ok;
o.flags = grid_ok + 4*any_card + 8*any_locked + 16*any_shed + 32*bess_fault + 64*st.ai_active + 128*any(offline);
end

function [src, user, kind] = parse_cmd_topic(topic)
% mg/cmd/op/<kind>, mg/cmd/ai/<kind>, mg/cmd/user/<house>/<kind>
% The source comes from the TOPIC (which the broker's ACL protects), never from the payload.
p = strsplit(topic, '/'); src = ''; user = ''; kind = '';
if numel(p) == 4 && strcmp(p{1}, 'mg') && strcmp(p{2}, 'cmd') && any(strcmp(p{3}, {'op', 'ai'}))
    src = p{3}; kind = p{4};
elseif numel(p) == 5 && strcmp(p{1}, 'mg') && strcmp(p{2}, 'cmd') && strcmp(p{3}, 'user')
    src = 'user'; user = p{4}; kind = p{5};
end
end

function v = getf(q, f)
% numeric scalar field or NaN (a malformed request is refused, never crashes the controller)
v = NaN;
if isfield(q, f) && isnumeric(q.(f)) && isscalar(q.(f)), v = double(q.(f)); end
end
