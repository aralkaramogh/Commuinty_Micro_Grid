function tests = test_hier
% TEST_HIER  Unit tests: physics, node rules, input firewall, protocol, ACL, duplication.
tests = functiontests(localfunctions);
end

function setupOnce(tc)
root = fileparts(fileparts(mfilename('fullpath')));
for f = {'params','plant','nodes','main','comms','pi','sim','tests','tools'}
    addpath(fullfile(root, f{1}));
end
tc.TestData.P = hier_params();
end

% ---------- physics (same as the verified model) ----------
function test_power_flow_single_line(tc)
Z = 0.3 + 0.1i; S = 2000 + 1000i; Vs = 230;
[~, Vh, Ih] = net_solve('island', Vs, 0, S, 0, Z, 0);
verifyEqual(tc, Vh * conj(Ih), S, 'AbsTol', 1e-6);
verifyEqual(tc, Vs - Z * Ih, Vh, 'AbsTol', 1e-9);
a = real(Z * conj(S)); B = Vs^2 - 2 * a;
x = (B + sqrt(B^2 - 4 * abs(Z * S)^2)) / 2;
verifyEqual(tc, abs(Vh), sqrt(x), 'AbsTol', 1e-6);
end

function test_reactive_power_drops_voltage(tc)
Z = 0.3 + 0.3i; Vs = 230;
[~, V1] = net_solve('island', Vs, 0, 1000, 0, Z, 0);
[~, V2] = net_solve('island', Vs, 0, 1000 + 1000i, 0, Z, 0);
verifyLessThan(tc, abs(V2), abs(V1));
[~, V3] = net_solve('island', Vs, 0, -2000, 0, Z, 0);
verifyGreaterThan(tc, abs(V3), Vs);
end

% ---------- node rules ----------
function test_node_critical_hold(tc)
N = tc.TestData.P.node; st = node_load_init();
x = struct('valid', 1, 'enable', 0, 'flex_allow', 1, 'v', 230, 'i', 5, 'p_load', 1000, 'q_load', 0, ...
           'p_pv', 0, 'q_pv', 0, 'card_uid', 0);
[st, r] = node_load_step(st, x, N, 1); verifyEqual(tc, [r.tie r.flex], [0 0]);   % not enabled yet: all off
x.enable = 1; [st, r] = node_load_step(st, x, N, 1); verifyEqual(tc, [r.tie r.flex], [1 1]);
x.enable = 0; x.flex_allow = 0; [~, r] = node_load_step(st, x, N, 1);
verifyEqual(tc, r.tie, 1, 'a command switched the critical circuit off');
verifyEqual(tc, r.flex, 0);
end

function test_node_comms_loss(tc)
N = tc.TestData.P.node; st = node_load_init();
x = struct('valid', 1, 'enable', 1, 'flex_allow', 1, 'v', 230, 'i', 5, 'p_load', 1000, 'q_load', 0, ...
           'p_pv', 0, 'q_pv', 0, 'card_uid', 0);
[st, r] = node_load_step(st, x, N, 1); verifyEqual(tc, r.flex, 1);
x.valid = 0;
for k = 1:N.N_comm_lost - 1, [st, r] = node_load_step(st, x, N, 1); end
verifyEqual(tc, r.flex, 1);                           % still within the grace time
[st, r] = node_load_step(st, x, N, 1);
verifyEqual(tc, [r.flex r.tie r.comm_lost], [0 1 1]); % fallback: flex off, critical on
x.valid = 1; [~, r] = node_load_step(st, x, N, 1);
verifyEqual(tc, [r.flex r.comm_lost], [1 0]);
end

function test_node_overcurrent_lockout(tc)
N = tc.TestData.P.node; st = node_load_init();
x = struct('valid', 1, 'enable', 1, 'flex_allow', 1, 'v', 230, 'i', 5, 'p_load', 1000, 'q_load', 0, ...
           'p_pv', 0, 'q_pv', 0, 'card_uid', 0);
[st, ~] = node_load_step(st, x, N, 1);
x.i = N.I_trip + 10;
for k = 1:N.N_oc, [st, r] = node_load_step(st, x, N, 1); end
verifyEqual(tc, [r.hstate r.tie], [1 0]);             % tripped, retry later
for k = 1:N.N_retry, [st, r] = node_load_step(st, x, N, 1); end
verifyEqual(tc, r.hstate, 0);                         % retried
for k = 1:N.N_oc, [st, r] = node_load_step(st, x, N, 1); end
verifyEqual(tc, [r.hstate r.tie], [2 0]);             % second strike: locked out
end

function test_node_energy_counters(tc)
N = tc.TestData.P.node; st = node_load_init();
x = struct('valid', 0, 'enable', 0, 'flex_allow', 0, 'v', 230, 'i', 5, 'p_load', 3600, 'q_load', 0, ...
           'p_pv', 0, 'q_pv', 0, 'card_uid', 0);
for k = 1:10, [st, r] = node_load_step(st, x, N, 1); end
verifyEqual(tc, r.e_imp, 10, 'AbsTol', 1e-9);         % 3600 W for 10 s = 10 Wh
x.p_pv = 7200; [~, r] = node_load_step(st, x, N, 1);
verifyEqual(tc, r.e_exp, 1, 'AbsTol', 1e-9);
end

function test_sb_hard_limits(tc)
P = tc.TestData.P; N = P.node; st = node_sb_init();
x = struct('valid', 1, 'p_set', 5000, 'q_set', 0, 'sync', 1, 'soc', N.soc_floor - 0.01, 'p_bess', 0, ...
           'q_bess', 0, 'bess_status', 0, 'v_c', 230, 'f_mg', 50, 'p_cpv', 0);
[st, r] = node_sb_step(st, x, N, P.bess); verifyEqual(tc, [r.p r.clamped], [0 1]);   % no discharge at low SOC
x.soc = N.soc_ch_stop + 0.01; x.p_set = -3000; [st, r] = node_sb_step(st, x, N, P.bess);
verifyEqual(tc, [r.p r.clamped], [0 1]);                                               % no charge when full
x.soc = 0.5; x.p_set = 4000; x.q_set = 9000; [st, r] = node_sb_step(st, x, N, P.bess);
verifyEqual(tc, r.p, 4000); verifyEqual(tc, r.q, sqrt(P.bess.S_rated^2 - 4000^2), 'AbsTol', 1e-9);
x.valid = 0; for k = 1:N.N_comm_lost, [st, r] = node_sb_step(st, x, N, P.bess); end
verifyEqual(tc, [r.p r.sync r.comm_lost], [4000 0 1]);                                 % hold set-point, stop sync
end

% ---------- input firewall ----------
function test_main_input_firewall(tc)
P = tc.TestData.P; S = main_inputs_spec();
z = @(f) cell2struct(num2cell(zeros(1, numel(f))), f, 2);
in = struct('t_s', 0, 'pcc', z(S.pcc), 'load', {repmat(z(S.load), 1, P.n_load)}, 'sb', z(S.sb), ...
            'inbox', {struct('topic', {}, 'payload', {})});
st = main_init(P);
[~, o] = main_step(st, in, P);                            % allowed inputs: runs
verifyEqual(tc, o.breaker, 0);
bad = in; bad.soc_true = 0.5;                             % a plant value sneaking in
verifyError(tc, @() main_step(st, bad, P), ?MException);
bad = in; bad.pcc.p_bess = 1;
verifyError(tc, @() main_step(st, bad, P), ?MException);
end

function test_main_never_cuts_critical(tc)
P = tc.TestData.P; S = main_inputs_spec();
z = @(f) cell2struct(num2cell(zeros(1, numel(f))), f, 2);
in = struct('t_s', 0, 'pcc', z(S.pcc), 'load', {repmat(z(S.load), 1, P.n_load)}, 'sb', z(S.sb), ...
            'inbox', {struct('topic', {}, 'payload', {})});
st = main_init(P);
for k = 1:10, in.t_s = k; [st, o] = main_step(st, in, P); end
verifyEqual(tc, [o.cmd_load.enable], ones(1, P.n_load));  % once booted, enable stays 1 ...
in.inbox = struct('topic', 'mg/cmd/op/cut_critical', 'payload', struct('id', 1, 't_sent', in.t_s + 1, 'target', 'H1'));
in.t_s = in.t_s + 1; [~, o] = main_step(st, in, P);
verifyEqual(tc, [o.cmd_load.enable], ones(1, P.n_load)); % ... even when asked to cut it
verifyFalse(tc, o.acks(1).accepted);
end

% ---------- protocol ----------
function test_node_lines_roundtrip(tc)
c = struct('valid', 1, 'enable', 1, 'flex_allow', 0);
m = struct('v', 229.123, 'i', 6.5432, 'p_load', 1234.56, 'q_load', -12.34, 'p_pv', 2000.5, 'q_pv', 300.25, ...
           'card_uid', 2712847106);
x = node_lines('dec_L', node_lines('enc_L', 7, c, m));
verifyEqual(tc, [x.seq x.valid x.enable x.flex_allow x.card_uid], [7 1 1 0 2712847106]);
verifyEqual(tc, x.p_load, 1234.56, 'AbsTol', 1e-9);
r = struct('tie', 1, 'flex', 0, 'hstate', 0, 'strikes', 1, 'comm_lost', 0, 'e_imp', 12345.6789, ...
           'e_exp', 0.5, 'v', 229.123, 'i', 6.5432, 'p_load', 1234.56, 'q_load', -12.34, 'p_pv', 2000.5, ...
           'q_pv', 300.25, 'card_uid', 0);
s1 = node_lines('enc_l', 7, r); rr = node_lines('dec_l', s1);
verifyEqual(tc, node_lines('enc_l', 7, rr), s1);          % print(parse(print(x))) == print(x)
b = struct('valid', 1, 'p_set', -1500, 'q_set', 99.5, 'sync', 1);
mb = struct('soc', 0.654321, 'p_bess', -1500.25, 'q_bess', 99.5, 'bess_status', 0, 'v_c', 230.5, ...
            'f_mg', 50.0167, 'p_cpv', 3000.75);
xb = node_lines('dec_B', node_lines('enc_B', 3, b, mb));
verifyEqual(tc, [xb.p_set xb.sync xb.soc], [-1500 1 0.654321]);
pm = struct('v_grid', 230.1, 'f_grid', 50.01, 'v_c', 229.9, 'f_mg', 50.02, 'dtheta', -3.25, 'p_pcc', 100.5, 'q_pcc', -4.25);
xp = node_lines('dec_P', node_lines('enc_P', 3, pm));
verifyEqual(tc, xp.dtheta, -3.25);
end

% ---------- MQTT access rules ----------
function test_acl(tc)
verifyTrue(tc, acl_allows('mgctl', 'write', 'mg/state'));
verifyTrue(tc, acl_allows('mgctl', 'write', 'mg/ack/user/H1'));
verifyTrue(tc, acl_allows('mgctl', 'read', 'mg/cmd/op/restrict'));
verifyTrue(tc, acl_allows('dash', 'read', 'mg/house/H2/account'));
verifyTrue(tc, acl_allows('dash', 'write', 'mg/cmd/op/restrict'));
verifyFalse(tc, acl_allows('dash', 'write', 'mg/state'));          % only the controller publishes data
verifyFalse(tc, acl_allows('ai', 'write', 'mg/cmd/op/restrict'));  % AI cannot pose as the operator
verifyTrue(tc, acl_allows('ai', 'write', 'mg/cmd/ai/ai_advice'));
verifyTrue(tc, acl_allows('ai', 'write', 'mg/ai/pv_forecast'));
verifyFalse(tc, acl_allows('ai', 'write', 'mg/state'));            % AI cannot fake measurements
verifyFalse(tc, acl_allows('H1', 'read', 'mg/ai/pv_forecast'));   % no AI on the user dashboard
verifyTrue(tc, acl_allows('H1', 'read', 'mg/house/H1/account'));
verifyFalse(tc, acl_allows('H1', 'read', 'mg/house/H2/account')); % no neighbour data
verifyFalse(tc, acl_allows('H1', 'read', 'mg/state'));            % no community-wide data on the user dashboard
verifyFalse(tc, acl_allows('H1', 'read', 'mg/ack/user/H2'));
verifyTrue(tc, acl_allows('H1', 'write', 'mg/cmd/user/H1/user_flex'));
verifyFalse(tc, acl_allows('H1', 'write', 'mg/cmd/user/H2/user_flex'));
verifyFalse(tc, acl_allows('H1', 'write', 'mg/cmd/op/restrict'));
verifyFalse(tc, acl_allows('', 'read', 'mg/state'));               % anonymous: nothing
verifyFalse(tc, acl_allows('stranger', 'read', 'mg/state'));
end

% ---------- scale: add a house with no code change ----------
function test_house_is_duplicable(tc)
P = tc.TestData.P;
P.house(3) = P.house(1); P.house(3).id = 'H3'; P.house(3).card_uid = 2712847107;
P.n_house = 3; P.n_load = 4; P.load_id = [{P.house.id}, {'CL'}];
P.load_P_flex = [[P.house.P_flex], P.comm.P_flex]; P.load_shed_soc = [[P.house.shed_soc], P.comm.shed_soc];
sc = base_scenario_h(P, 'dup'); sc.t0_h = 12; sc.dur_s = 120;
R = run_hier(sc, P);
verifyEqual(tc, size(R.L.p_pv, 2), 3);
verifyGreaterThan(tc, R.L.p_pv(end, 3), 0);
verifyEqual(tc, R.L.tie(end, :), ones(1, 4));
end

% ---------- live MQTT link (in-memory fake broker) ----------
function test_live_link_fake(tc)
P = tc.TestData.P;
[link, box] = pi_link_fake();
box.push('mg/cmd/op/restrict', '{"id": 501, "t_sent": 0, "target": "CL", "value": 1, "ttl": 60}');
box.push('mg/cmd/op/restrict', 'this is not json');
sc = base_scenario_h(P, 'live'); sc.t0_h = 10; sc.dur_s = 120;
R = run_hier(sc, P, struct('link', link));
verifyEqual(tc, numel(R.acks), 2);
verifyTrue(tc, R.acks(1).accepted == 1 && R.acks(1).id == 501);       % JSON request accepted
verifyEqual(tc, R.acks(2).reason, 'missing id');                     % garbage refused, no crash
verifyTrue(tc, all(R.L.flex(R.L.t >= 1 & R.L.t < 60, 3) == 0));      % pump held off ...
verifyTrue(tc, all(R.L.flex(R.L.t >= 61, 3) == 1));                  % ... then released
S = box.sent(); tp = {S.topic};
verifyEqual(tc, sum(strcmp(tp, 'mg/state')), 120);                    % one state message per tick
a = jsondecode(S(find(strcmp(tp, 'mg/ack/op'), 1)).data);
verifyEqual(tc, [a.id a.accepted], [501 true]);
st = jsondecode(S(find(strcmp(tp, 'mg/state'), 1, 'last')).data);
verifyEqual(tc, st.v, 1); verifyEqual(tc, st.tick, 120);
verifyNotEmpty(tc, st.wall_time);                                     % live runs carry the PC clock
end

% ---------- E-stop ----------
function test_estop_latch_nodes(tc)
P = tc.TestData.P; N = P.node; st = node_load_init();
x = struct('valid', 1, 'enable', 1, 'flex_allow', 1, 'v', 230, 'i', 5, 'p_load', 1000, 'q_load', 0, ...
           'p_pv', 0, 'q_pv', 0, 'card_uid', 0);
[st, r] = node_load_step(st, x, N, 1, 0); verifyEqual(tc, [r.tie r.flex r.hstate], [1 1 0]);
[st, r] = node_load_step(st, x, N, 1, 1); verifyEqual(tc, [r.tie r.flex r.hstate], [0 0 3]);   % pressed
for k = 1:5, [st, r] = node_load_step(st, x, N, 1, 0); end
verifyEqual(tc, [r.tie r.flex r.hstate], [0 0 3]);                   % released: still latched
st = node_load_init(); [~, r] = node_load_step(st, x, N, 1, 0);       % technician reset (R)
verifyEqual(tc, [r.tie r.flex r.hstate], [1 1 0]);
sb = node_sb_init();
y = struct('valid', 1, 'p_set', 3000, 'q_set', 500, 'sync', 1, 'soc', 0.7, 'p_bess', 0, 'q_bess', 0, ...
           'bess_status', 0, 'v_c', 230, 'f_mg', 50, 'p_cpv', 0);
[sb, r] = node_sb_step(sb, y, N, P.bess, 1); verifyEqual(tc, [r.p r.q r.sync r.clamped], [0 0 0 2]);
[~, r] = node_sb_step(sb, y, N, P.bess, 0);  verifyEqual(tc, r.clamped, 2);                  % latched
end

function test_estop_system(tc)
% live run, virtual nodes: E-stop H1 (latched, reported, reset restores) and SB in island (island goes dark)
P = tc.TestData.P; live_inputs('reset');
sc = live_scenario(P, 12, 400);
sc.estop_fn = @(t) [(t >= 100 && t < 110), 0, 0, (t >= 300)];
sc.grid_fn  = @(t) [~(t >= 250), 50];                                 % outage from 250 s
sc.link_fn  = @(t) (t == 200 && isempty(live_inputs('set', 'reset_node', 1))) | false(1, 4);
R = run_hier(sc, P, struct('pi', false)); L = R.L; t = L.t;
verifyTrue(tc, all(L.tie(t >= 100 & t < 200, 1) == 0));              % pressed, then still latched after release
verifyTrue(tc, all(bitand(L.hcode(t >= 101 & t < 200, 1), 3) == 3));  % main controller sees E-STOP
verifyTrue(tc, all(L.tie(t >= 202 & t < 300, 1) == 1));              % technician reset restores it
verifyTrue(tc, all(L.tie(t >= 100 & t < 300, 2) == 1));              % the other house is untouched
verifyTrue(tc, any(L.mode(t > 255 & t < 300) == 2) && all(L.energised(t > 255 & t < 300) == 1));   % islanded fine
verifyTrue(tc, all(L.energised(t >= 302) == 0));                     % SB E-stop in island: dark
verifyTrue(tc, all(L.p_bess(t >= 302) == 0));
end
