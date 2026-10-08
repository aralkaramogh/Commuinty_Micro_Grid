function R = run_hier(sc, P, opts)
% RUN_HIER  Closed loop of the hierarchical microgrid, one tick = 1 s:
%   1. PLANT (physics) steps with what the switches/inverter did last tick
%   2. each NODE gets one text line: its own meter + the main controller's
%      command (sent P.net.cmd_delay ticks earlier); it applies its local rules
%      and replies (relay states + report)
%   3. the MAIN controller reads the node reports + PCC meter + Pi inbox
%      (nothing else: input firewall) and decides; the grid breaker is direct
%   4. the main controller publishes MQTT messages to the Pi (simulated broker
%      with the real ACL)
% Nodes are 'virtual' (MATLAB twin of the firmware) or real ESP32s
% (opts.exchange{k} = @(line, seq) reply_line), in node order H1, H2, CL, SB.
%   opts.keep_frames true -> keep every node line (for the SIL check)
%   opts.P_plant   plant parameters if different (Monte Carlo)
%   opts.pi        false -> skip the Pi messages (faster Monte Carlo)
%   opts.link      live MQTT link (pi/pi_link_open.m): messages really go to the Pi and
%                  requests from the Pi (already filtered by the real broker's ACL) come back
if nargin < 3, opts = struct(); end
n = P.n_house; nL = P.n_load; nN = nL + 1; dt = P.sim.dt; N = round(sc.dur_s / dt);
node_id = [P.load_id, {'SB'}];
def = struct('keep_frames', false, 'P_plant', P, 'pi', true, 'progress_every', 0, 'pace_s', 0, 'link', []);
def.exchange = cell(1, nN);
for f = fieldnames(def).', if ~isfield(opts, f{1}), opts.(f{1}) = def.(f{1}); end, end
links = repmat({'virtual'}, 1, nN);
for k = 1:nN, if ~isempty(opts.exchange{k}), links{k} = 'real'; end, end
Pp = opts.P_plant;
rs = RandStream('mt19937ar', 'Seed', sc.seed);
d = P.net.cmd_delay; assert(d >= 1 && d == round(d), 'cmd_delay must be a whole number >= 1');

ps = plant_init_h(Pp, sc.soc0);
nst = repmat(node_load_init(), 1, nL); sbst = node_sb_init(); mst = main_init(P);
act = struct('breaker', 0, 'sync', 0, 'tie', zeros(1,nL), 'flex', zeros(1,nL), 'p_set', 0, 'q_set', 0, 'bess_stop', 0);
cmdq = cell(1, d); mode_prev = 0;                       % commands on their way to the nodes (empty = none yet)
Sx = main_inputs_spec();
zl = cell2struct(num2cell(zeros(1, numel(Sx.load))), Sx.load, 2);
zs = cell2struct(num2cell(zeros(1, numel(Sx.sb))), Sx.sb, 2);
acl = pi_acl(); aclc = containers.Map('KeyType', 'char', 'ValueType', 'logical');

z = zeros(N,1);
L.t = (0:N-1)' * dt;
for f = {'mode','bits','flags','ai_status','price','v_grid','f_grid','v_c','f_mg','dtheta', ...
         'p_pcc','q_pcc','p_bess','q_bess','p_set','q_set','p_app','q_app','sync','sb_clamped', ...
         'sb_comm_lost','soc','bess_trip','curtail','p_cl','q_cl','p_cpv','energised','p_loss', ...
         'bal_err','close_angle','close_dV','close_df','grid_V_pu','grid_f_true','p_comm_dem', ...
         'p_comm_srv','ovl_t','disturbed'}
    L.(f{1}) = z;
end
for f = {'v_h','i_h','p_load','q_load','p_pv','q_pv','bal','p_crit_dem','p_crit_srv','p_load_meas', ...
         'e_imp','e_exp'}
    L.(f{1}) = zeros(N, n);
end
for f = {'tie','flex','hcode','node_comm_lost','p_flex_dem','p_flex_srv'}, L.(f{1}) = zeros(N, nL); end
L.offline = zeros(N, nN);
if opts.keep_frames, L.lin = cell(N, nN); L.lout = cell(N, nN); end
frozen = nan(1, n);
L_G = z; lab.frozen = z; lab.abnormal = z; lab.card = z;
acks = struct('t', {}, 'id', {}, 'src', {}, 'user', {}, 'accepted', {}, 'reason', {});
drops = struct('t', {}, 'sender', {}, 'topic', {});
PI.count = containers.Map(); PI.sample = struct(); PI.bad = {}; PI.events = {};

for i = 1:N
    t_s = (i-1) * dt;
    ext = profiles_h(t_s, Pp, sc);
    [ps, m, y] = plant_step_h(ps, act, ext, Pp);
    mt = m;                                         % sensor errors (what the meters read)
    if sc.noise_P > 0 || sc.noise_V > 0
        mt.v_grid = m.v_grid + sc.noise_V * randn(rs) * (m.v_grid > 0);
        mt.v_c    = m.v_c + sc.noise_V * randn(rs) * (m.v_c > 0);
        mt.p_load = m.p_load + sc.noise_P * randn(rs, 1, n) .* (m.p_load > 0);
        mt.p_pv   = m.p_pv + sc.noise_P * randn(rs, 1, n) .* (m.p_pv > 0);
    end
    for f = 1:numel(sc.sensor_faults)               % frozen load sensor (anomaly)
        F = sc.sensor_faults(f);
        if t_s >= F.t_on && t_s < F.t_off
            if isnan(frozen(F.house)), frozen(F.house) = mt.p_load(F.house); end
            mt.p_load(F.house) = frozen(F.house); lab.frozen(i) = F.house;
        else
            frozen(F.house) = NaN;
        end
    end
    L_G(i) = ext.G;
    if any(ext.R_fault > 0), lab.abnormal(i) = find(ext.R_fault > 0, 1); end
    if ext.card_house > 0 && ext.card_uid ~= Pp.house(ext.card_house).card_uid, lab.card(i) = ext.card_house; end

    % ---- which node links are down this tick (both directions) ----
    down = false(1, nN);
    for f = 1:numel(sc.link_drops)
        D = sc.link_drops(f);
        if t_s >= D.t_on && t_s < D.t_off, down(strcmp(node_id, D.node)) = true; end
    end
    if isfield(sc, 'link_fn'), down = down | sc.link_fn(t_s); end    % live: cable pulled
    c_in = cmdq{1};
    estop_now = false(1, nN);                         % E-stop buttons of VIRTUAL nodes (live panel)
    if isfield(sc, 'estop_fn'), estop_now = sc.estop_fn(t_s) > 0; end
    if isfield(sc, 'live') && sc.live                 % live: technician resets a node (clears its lockout)
        rn = live_inputs('take_reset');
        if rn >= 1 && rn <= nL
            if isempty(opts.exchange{rn}), nst(rn) = node_load_init(); else, opts.exchange{rn}('R', i); end
        elseif rn == nN
            if isempty(opts.exchange{nN}), sbst = node_sb_init(); else, opts.exchange{nN}('R', i); end
        end
    end

    % ---- load nodes (H1, H2, CL) ----
    rep = repmat(zl, 1, nL);
    display_info('set', mode_prev, sum(m.p_load) + m.p_cl);   % for node LCDs only (D line)
    for j = 1:nL
        if j <= n
            mtr = struct('v', mt.v_h(j), 'i', m.i_h(j), 'p_load', mt.p_load(j), 'q_load', m.q_load(j), ...
                         'p_pv', mt.p_pv(j), 'q_pv', m.q_pv(j), 'card_uid', (ext.card_house == j) * ext.card_uid);
        else
            mtr = struct('v', mt.v_c, 'i', m.i_cl, 'p_load', m.p_cl, 'q_load', m.q_cl, ...
                         'p_pv', 0, 'q_pv', 0, 'card_uid', 0);
        end
        c = struct('valid', 0, 'enable', 0, 'flex_allow', 0);
        if ~isempty(c_in) && ~down(j)
            c.valid = 1; c.enable = c_in.load(j).enable; c.flex_allow = c_in.load(j).flex_allow;
        end
        lin = node_lines('enc_L', i, c, mtr);
        if isempty(opts.exchange{j})
            [nst(j), r] = node_load_step(nst(j), node_lines('dec_L', lin), P.node, dt, estop_now(j));
            lout = node_lines('enc_l', i, r);
        else
            lout = opts.exchange{j}(lin, i);
        end
        rr = node_lines('dec_l', lout);
        assert(rr.seq == i, 'node %s: sequence mismatch at tick %d', node_id{j}, i);
        act.tie(j) = rr.tie; act.flex(j) = rr.flex;
        if ~down(j)
            rr = rmfield(rr, 'seq'); rr.ok = 1; rep(j) = orderfields(rr, zl);
        end
        L.node_comm_lost(i, j) = rr.comm_lost;
        if j <= n, L.e_imp(i, j) = rr.e_imp; L.e_exp(i, j) = rr.e_exp; end
        if opts.keep_frames, L.lin{i, j} = lin; L.lout{i, j} = lout; end
    end
    % ---- solar + BESS node ----
    mtr = struct('soc', mt.soc, 'p_bess', m.p_bess, 'q_bess', m.q_bess, 'bess_status', m.bess_status, ...
                 'v_c', mt.v_c, 'f_mg', m.f_mg, 'p_cpv', m.p_cpv);
    c = struct('valid', 0, 'p_set', 0, 'q_set', 0, 'sync', 0);
    if ~isempty(c_in) && ~down(nN)
        c.valid = 1; c.p_set = c_in.sb.p_set; c.q_set = c_in.sb.q_set; c.sync = c_in.sb.sync;
    end
    lin = node_lines('enc_B', i, c, mtr);
    if isempty(opts.exchange{nN})
        [sbst, r] = node_sb_step(sbst, node_lines('dec_B', lin), P.node, P.bess, estop_now(nN));
        lout = node_lines('enc_b', i, r);
    else
        lout = opts.exchange{nN}(lin, i);
    end
    rb = node_lines('dec_b', lout);
    assert(rb.seq == i, 'node SB: sequence mismatch at tick %d', i);
    act.p_set = rb.p; act.q_set = rb.q; act.sync = rb.sync;
    act.bess_stop = rb.clamped == 2;                  % SB E-stop: inverter stopped
    sbrep = zs;
    if ~down(nN), rb2 = rmfield(rb, 'seq'); rb2.ok = 1; sbrep = orderfields(rb2, zs); end
    if opts.keep_frames, L.lin{i, nN} = lin; L.lout{i, nN} = lout; end
    % ---- PCC meter (synchroscope + power meter at the grid breaker) ----
    pcc = rmfield(node_lines('dec_P', node_lines('enc_P', i, mt)), 'seq');

    % ---- Pi inbox: requests that the broker's ACL lets through ----
    inbox = struct('topic', {}, 'payload', {});
    if isfield(sc, 'cmd_fn'), inbox = [inbox, sc.cmd_fn(t_s)]; end   % live panel requests (as the operator)
    ai = sc.ai_fn(t_s);
    if ai.valid
        inbox(end+1) = struct('topic', 'mg/cmd/ai/ai_advice', 'payload', struct('id', 1e6 + i, ...
            't_sent', t_s, 'p_bess', ai.p_bess, 'shed_mask', ai.shed_mask, 'price', ai.price)); %#ok<AGROW>
    end
    for k = 1:numel(sc.cmds)
        cq = sc.cmds(k);
        if abs(cq.t - t_s) < 0.5 * dt
            if acl_allows(cq.sender, 'write', cq.topic, acl)
                inbox(end+1) = struct('topic', cq.topic, 'payload', cq.payload); %#ok<AGROW>
            else
                drops(end+1) = struct('t', t_s, 'sender', cq.sender, 'topic', cq.topic); %#ok<AGROW>
            end
        end
    end

    if ~isempty(opts.link)                          % requests from the real Pi broker
        rx = opts.link.fetch();
        for k = 1:numel(rx)
            try, pl = jsondecode(rx(k).data); catch, pl = struct(); end   % bad JSON -> refused (missing id)
            if ~isstruct(pl) || ~isscalar(pl), pl = struct(); end
            if startsWith(rx(k).topic, 'mg/sim/')       % bench knobs from the dashboard: change the
                nm = extractAfter(rx(k).topic, 'mg/sim/'); % simulated world, never seen by the controller
                if isfield(pl, 'value') && any(strcmp(nm, {'grid', 'sun'})), live_inputs('set', nm, pl.value); end
                continue;
            end
            inbox(end+1) = struct('topic', rx(k).topic, 'payload', pl); %#ok<AGROW>
        end
    end

    % ---- main controller ----
    in = struct('t_s', t_s, 'pcc', pcc, 'load', {rep}, 'sb', sbrep, 'inbox', {inbox});
    [mst, o] = main_step(mst, in, P); mode_prev = o.mode;
    act.breaker = o.breaker;                                       % direct, no node
    cmdq = [cmdq(2:end), {struct('load', {o.cmd_load}, 'sb', o.cmd_sb)}];
    for a = 1:numel(o.acks)
        ak = o.acks(a);
        acks(end+1) = struct('t', t_s, 'id', ak.id, 'src', ak.src, 'user', ak.user, ...
                             'accepted', ak.accepted, 'reason', ak.reason); %#ok<AGROW>
    end

    % ---- Pi messages ----
    if opts.pi
        t0e = sc.t0_h; if isfield(sc, 'hour_fn'), t0e = t0e + sc.hour_fn(t_s); end
        Mg = pi_messages(t_s, t0e, in, mst, o, P, links);
        if ~isempty(opts.link), wall = char(datetime('now', 'Format', 'yyyy-MM-dd''T''HH:mm:ss')); end
        for k = 1:numel(Mg)
            tp = Mg(k).topic; pl = Mg(k).payload;
            if ~isempty(opts.link)
                if isfield(pl, 'wall_time'), pl.wall_time = wall; end
                opts.link.publish(tp, jsonencode(pl));
            end
            if ~isKey(aclc, tp), aclc(tp) = acl_allows('mgctl', 'write', tp, acl); end   % cached: same topics every tick
            if ~aclc(tp), PI.bad{end+1} = sprintf('%d: mgctl may not publish %s', i, tp); end
            if ~(isfield(pl, 'v') && pl.v == P.pi.version && isfield(pl, 'tick') && pl.tick == mst.tick ...
                    && isfield(pl, 'sim_time') && isfield(pl, 'sim_s'))
                PI.bad{end+1} = sprintf('%d: %s header missing', i, tp);
            end
            tk = strsplit(tp, '/');
            if numel(tk) == 4 && strcmp(tk{2}, 'house') && ~strcmp(pl.house_id, tk{3})
                PI.bad{end+1} = sprintf('%d: %s carries %s data', i, tp, pl.house_id);
            end
            key = tp; if startsWith(tp, 'mg/ack/'), key = 'mg/ack/*'; end
            if isKey(PI.count, key), PI.count(key) = PI.count(key) + 1;
            else
                PI.count(key) = 1;
                PI.sample.(matlab.lang.makeValidName(key)) = jsonencode(pl);
            end
            if strcmp(tp, 'mg/event'), PI.events{end+1} = sprintf('%s %s %s: %s', pl.sim_time, pl.type, pl.node, pl.text); end
        end
    end

    % ---- log ----
    bits = o.breaker + 2 * act.sync;
    for j = 1:nL, bits = bits + act.tie(j) * 2^(2 + 2*(j-1)) + act.flex(j) * 2^(3 + 2*(j-1)); end
    L.mode(i) = o.mode; L.bits(i) = bits; L.flags(i) = o.flags; L.ai_status(i) = o.ai_status;
    L.price(i) = o.price; L.p_set(i) = o.p_set; L.q_set(i) = o.q_set; L.bal(i,:) = o.bal; L.hcode(i,:) = o.code;
    L.p_app(i) = act.p_set; L.q_app(i) = act.q_set; L.sync(i) = act.sync;
    L.sb_clamped(i) = rb.clamped; L.sb_comm_lost(i) = rb.comm_lost; L.offline(i,:) = o.offline;
    L.v_grid(i) = m.v_grid; L.f_grid(i) = m.f_grid; L.v_c(i) = m.v_c; L.f_mg(i) = m.f_mg; L.dtheta(i) = m.dtheta;
    L.p_pcc(i) = m.p_pcc; L.q_pcc(i) = m.q_pcc; L.p_bess(i) = m.p_bess; L.q_bess(i) = m.q_bess;
    L.soc(i) = m.soc; L.bess_trip(i) = m.bess_status; L.curtail(i) = y.curtail;
    L.p_cl(i) = m.p_cl; L.q_cl(i) = m.q_cl; L.p_cpv(i) = m.p_cpv; L.energised(i) = y.energised;
    L.p_loss(i) = y.p_loss; L.bal_err(i) = y.bal_err; L.close_angle(i) = y.close_angle;
    L.close_dV(i) = y.close_dV; L.close_df(i) = y.close_df; L.grid_V_pu(i) = ext.grid_V_pu;
    L.grid_f_true(i) = ext.grid_f; L.p_comm_dem(i) = y.p_comm_dem; L.p_comm_srv(i) = y.p_comm_srv;
    L.ovl_t(i) = y.ovl_t; L.disturbed(i) = y.disturbed;
    L.v_h(i,:) = m.v_h; L.i_h(i,:) = m.i_h; L.p_load(i,:) = m.p_load; L.q_load(i,:) = m.q_load;
    L.p_pv(i,:) = m.p_pv; L.q_pv(i,:) = m.q_pv; L.p_load_meas(i,:) = mt.p_load;
    L.tie(i,:) = act.tie; L.flex(i,:) = act.flex;
    L.p_crit_dem(i,:) = y.p_crit_dem; L.p_crit_srv(i,:) = y.p_crit_srv;
    L.p_flex_dem(i,:) = y.p_flex_dem; L.p_flex_srv(i,:) = y.p_flex_srv;
    if opts.progress_every > 0 && mod(i, opts.progress_every) == 0
        mn = ["BOOT","GRID","ISLAND","RESYNC"];
        fprintf('%5.2f h  %-6s  grid %s  f %6.3f Hz  SOC %5.1f %%  BESS %6.0f W  shed %d   (%d/%d ticks)\n', ...
            mod(sc.t0_h + t_s/3600, 24), mn(o.mode+1), string(ext.grid_V_pu >= Pp.grid.V_dead), m.f_mg, ...
            100*m.soc, m.p_bess, bitand(o.flags, 16) > 0, i, N);
    end
    if isfield(sc, 'live') && sc.live
        if ~exist('t_ui', 'var') || toc(t_ui) > 0.25     % screen refresh at most 4x per second
            live_status(t_s, sc.t0_h + sc.hour_fn(t_s), o, m, act, P, true); drawnow limitrate; t_ui = tic;
        else
            live_status(t_s, sc.t0_h + sc.hour_fn(t_s), o, m, act, P, false);  % only log events / answers
        end
        if live_inputs('get').stop, Nrun = i; break; end
    end
    if opts.pace_s > 0
        if i == 1, t_wall = tic; end
        while toc(t_wall) < i * opts.pace_s, pause(0.002); end
    end
end
if exist('Nrun', 'var')                                % stopped early: keep the ticks that ran
    for f = fieldnames(L).', if size(L.(f{1}), 1) == N, L.(f{1}) = L.(f{1})(1:Nrun, :); end, end
    L_G = L_G(1:Nrun); sc.dur_s = Nrun * dt;
end
R.sc = sc; R.L = L; R.L_G = L_G; R.lab = lab; R.acks = acks; R.drops = drops; R.links = links;
R.PI = PI; R.main_state = mst;
R.kpi = kpi_h(L, sc, P);
end
