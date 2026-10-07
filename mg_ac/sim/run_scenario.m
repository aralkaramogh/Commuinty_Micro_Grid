function R = run_scenario(sc, P, opts)
% RUN_SCENARIO  Closed loop: AC plant (MATLAB) <-> controller. Every tick goes
% through the real text protocol, exactly as over USB.
%   opts.transport 'matlab' (reference controller, default) | 'esp32' (opts.port)
%   opts.keep_frames true -> keep every M/C line (needed for the SIL check)
%   opts.P_plant   plant parameters if different from the controller's (Monte Carlo)
if nargin < 3, opts = struct(); end
if ~isfield(opts, 'transport'),   opts.transport = 'matlab'; end
if ~isfield(opts, 'keep_frames'), opts.keep_frames = false; end
if ~isfield(opts, 'P_plant'),     opts.P_plant = P; end
if ~isfield(opts, 'progress_every'), opts.progress_every = 0; end   % print a status line every N ticks
if ~isfield(opts, 'pace_s'),      opts.pace_s = 0; end      % min wall-clock seconds per tick (slow motion for a demo)
Pp = opts.P_plant; n = P.n_house; dt = P.sim.dt; N = round(sc.dur_s / dt);
rs = RandStream('mt19937ar', 'Seed', sc.seed);

ps = plant_init(Pp, sc.soc0);
cmd = struct('bits', 0, 'breaker', 0, 'sync', 0, 'tie', zeros(1,n), 'flex', zeros(1,n), ...
             'p_set', 0, 'q_set', 0);
switch opts.transport
    case 'matlab', st = ac_controller_init(P);
    case 'esp32',  link = esp32_open(opts.port, P); cl = onCleanup(@() esp32_close(link));
    case 'custom'  % opts.exchange(Mline, seq) -> Cline  (e.g. two boards, hil/run_hil_dual.m)
    otherwise, error('unknown transport');
end

z = zeros(N,1); zn = zeros(N,n);
L.t = (0:N-1)' * dt;
for f = {'mode','bits','flags','ai_status','price','v_grid','f_grid','v_c','f_mg','dtheta', ...
         'p_pcc','q_pcc','p_bess','q_bess','p_set','q_set','soc','bess_trip','curtail', ...
         'p_cl','q_cl','p_cpv','energised','p_loss','bal_err','close_angle','close_dV', ...
         'close_df','grid_V_pu','grid_f_true','p_comm_srv','ovl_t','disturbed'}
    L.(f{1}) = z;
end
for f = {'v_h','i_h','p_load','q_load','p_pv','q_pv','tie','flex','bal','hcode', ...
         'p_crit_dem','p_crit_srv','p_flex_dem','p_flex_srv','p_load_meas'}
    L.(f{1}) = zn;
end
if opts.keep_frames, L.M = cell(N,1); L.C = cell(N,1); end
frozen = nan(1, n);
L_G = z; lab.frozen = z; lab.abnormal = z; lab.card = z;

for i = 1:N
    t_s = (i-1) * dt;
    ext = ac_profiles(t_s, Pp, sc);
    [ps, m, y] = plant_step(ps, cmd, ext, Pp);
    mt = m;                                         % sensor errors (what the ESP32 sees)
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
            mt.p_load(F.house) = frozen(F.house);
        else
            frozen(F.house) = NaN;
        end
    end
    L_G(i) = ext.G;
    for f = 1:numel(sc.sensor_faults)
        F = sc.sensor_faults(f); if t_s >= F.t_on && t_s < F.t_off, lab.frozen(i) = F.house; end
    end
    if any(ext.R_fault > 0), lab.abnormal(i) = find(ext.R_fault > 0, 1); end
    if ext.card_house > 0 && ext.card_uid ~= Pp.house(ext.card_house).card_uid, lab.card(i) = ext.card_house; end
    Mline = proto_encode_meas(i, round(t_s*1000), mt);
    switch opts.transport
        case 'matlab'
            [st, o] = ac_controller_step(st, proto_decode_meas(Mline, n), P);
            Cline = proto_encode_cmd(i, o);
        case 'esp32'
            Cline = esp32_exchange(link, Mline, i);
        case 'custom'
            Cline = opts.exchange(Mline, i);
    end
    [cmd, o] = proto_decode_cmd(Cline, n);
    assert(o.seq == i, 'sequence mismatch at tick %d', i);

    L.mode(i) = o.mode; L.bits(i) = o.bits; L.flags(i) = o.flags; L.ai_status(i) = o.ai_status;
    L.price(i) = o.price; L.p_set(i) = o.p_set; L.q_set(i) = o.q_set; L.bal(i,:) = o.bal; L.hcode(i,:) = o.hcode;
    L.v_grid(i) = m.v_grid; L.f_grid(i) = m.f_grid; L.v_c(i) = m.v_c; L.f_mg(i) = m.f_mg; L.dtheta(i) = m.dtheta;
    L.p_pcc(i) = m.p_pcc; L.q_pcc(i) = m.q_pcc; L.p_bess(i) = m.p_bess; L.q_bess(i) = m.q_bess;
    L.soc(i) = m.soc; L.bess_trip(i) = m.bess_status; L.curtail(i) = y.curtail;
    L.p_cl(i) = m.p_cl; L.q_cl(i) = m.q_cl; L.p_cpv(i) = m.p_cpv; L.energised(i) = y.energised;
    L.p_loss(i) = y.p_loss; L.bal_err(i) = y.bal_err; L.close_angle(i) = y.close_angle;
    L.close_dV(i) = y.close_dV; L.close_df(i) = y.close_df; L.grid_V_pu(i) = ext.grid_V_pu;
    L.grid_f_true(i) = ext.grid_f; L.p_comm_srv(i) = y.p_comm_srv; L.ovl_t(i) = y.ovl_t; L.disturbed(i) = y.disturbed;
    L.v_h(i,:) = m.v_h; L.i_h(i,:) = m.i_h; L.p_load(i,:) = m.p_load; L.q_load(i,:) = m.q_load;
    L.p_pv(i,:) = m.p_pv; L.q_pv(i,:) = m.q_pv; L.p_load_meas(i,:) = mt.p_load;
    L.tie(i,:) = cmd.tie; L.flex(i,:) = cmd.flex;      % commanded for the next tick
    L.p_crit_dem(i,:) = y.p_crit_dem; L.p_crit_srv(i,:) = y.p_crit_srv;
    L.p_flex_dem(i,:) = y.p_flex_dem; L.p_flex_srv(i,:) = y.p_flex_srv;
    if opts.keep_frames, L.M{i} = Mline; L.C{i} = Cline; end
    if opts.progress_every > 0 && mod(i, opts.progress_every) == 0
        mn = ["BOOT","GRID","ISLAND","RESYNC"];
        fprintf('%5.2f h  %-6s  grid %s  f %6.3f Hz  SOC %5.1f %%  BESS %6.0f W  shed %d   (%d/%d ticks)\n', ...
            mod(sc.t0_h + t_s/3600, 24), mn(o.mode+1), string(ext.grid_V_pu >= Pp.grid.V_dead), m.f_mg, ...
            100*m.soc, m.p_bess, bitand(o.flags, 16) > 0, i, N);
    end
    if opts.pace_s > 0
        if i == 1, t_wall = tic; end
        while toc(t_wall) < i * opts.pace_s, end
    end
end
R.sc = sc; R.L = L; R.L_G = L_G; R.lab = lab;
R.kpi = ac_kpi(L, sc, P);
end
