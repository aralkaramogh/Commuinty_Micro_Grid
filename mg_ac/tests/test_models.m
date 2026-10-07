function tests = test_models
% TEST_MODELS  Unit tests: PV, volt-var, power flow physics, protocol, house duplication.
tests = functiontests(localfunctions);
end

function setupOnce(tc)
root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root,'params'), fullfile(root,'models'), fullfile(root,'controller'), ...
        fullfile(root,'comms'), fullfile(root,'sim'), fullfile(root,'tests'));
tc.TestData.P = ac_params();
end

function test_pv(tc)
P = tc.TestData.P; Tamb = 25 - (P.pv.NOCT - 20) / 800 * 1000;   % cell at 25 C
verifyEqual(tc, pv_power(3, 1000, Tamb, P), 3000 * P.pv.derate, 'AbsTol', 1e-9);
verifyEqual(tc, pv_power(3, 0, 25, P), 0);
verifyLessThan(tc, pv_power(3, 1000, 40, P), pv_power(3, 1000, 20, P));   % hotter = less
end

function test_volt_var(tc)
P = tc.TestData.P;
verifyEqual(tc, volt_var(230, P), 0);
verifyGreaterThan(tc, volt_var(0.9 * 230, P), 0);      % low voltage -> inject vars
verifyLessThan(tc, volt_var(1.09 * 230, P), 0);        % high voltage -> absorb vars
end

function test_power_flow_single_line(tc)
% One house, one line, grid source: compare with the exact closed-form answer.
Z = 0.3 + 0.1i; S = 2000 + 1000i; Vs = 230;
[~, Vh, Ih] = net_solve('island', Vs, 0, S, 0, Z, 0);
verifyEqual(tc, Vh * conj(Ih), S, 'AbsTol', 1e-6);              % house gets its power
verifyEqual(tc, Vs - Z * Ih, Vh, 'AbsTol', 1e-9);               % Ohm's law on the line
% exact |Vh|^2 = x solves x^2 + (2a - Vs^2) x + |Z S|^2 = 0, a = Re(Z conj(S)), high root
a = real(Z * conj(S)); B = Vs^2 - 2 * a;
x = (B + sqrt(B^2 - 4 * abs(Z * S)^2)) / 2;
verifyEqual(tc, abs(Vh), sqrt(x), 'AbsTol', 1e-6);
end

function test_reactive_power_drops_voltage(tc)
Z = 0.3 + 0.3i; Vs = 230;
[~, V1] = net_solve('island', Vs, 0, 1000, 0, Z, 0);
[~, V2] = net_solve('island', Vs, 0, 1000 + 1000i, 0, Z, 0);
verifyLessThan(tc, abs(V2), abs(V1));                            % more Q -> more voltage drop
[~, V3] = net_solve('island', Vs, 0, -2000, 0, Z, 0);            % export
verifyGreaterThan(tc, abs(V3), Vs);                              % export raises voltage
end

function test_grid_mode_losses(tc)
% Plant-level energy balance equals I^2 R losses in every scenario tick.
P = tc.TestData.P; S = define_scenarios(P);
R = run_scenario(S(6), P);
verifyLessThan(tc, max(abs(R.L.bal_err)), 1e-6);
end

function test_protocol_roundtrip(tc)
P = tc.TestData.P; n = P.n_house;
m = struct('v_grid',230.123,'f_grid',50.01,'v_c',229.5,'f_mg',50.01,'dtheta',-3.25,'p_pcc',1200.5, ...
    'q_pcc',-40.25,'p_bess',-500,'q_bess',300,'soc',0.654321,'bess_status',0,'p_cl',600,'q_cl',450, ...
    'p_cpv',2500,'fb',4+8+16,'card_house',3,'card_uid',2712847107);
m.ai = ai_cmd(1, 1500, 5, 7.5);
m.v_h = [229 228 227]; m.i_h = [5 6 7]; m.p_load = [1 2 3]*100; m.q_load = [4 5 6]; m.p_pv = [700 0 0]; m.q_pv = [-10 0 0];
d = proto_decode_meas(proto_encode_meas(9, 9000, m), n);
verifyEqual(tc, d.card_uid, 2712847107); verifyEqual(tc, d.ai_mask, 5); verifyEqual(tc, d.q_pv, m.q_pv);
verifyEqual(tc, d.soc, 0.654321); verifyEqual(tc, d.dtheta, -3.25);
o = struct('bits', 1+4+8, 'mode', 1, 'p_set', -1234.5, 'q_set', 99.1, 'flags', 65, 'ai_status', 3, ...
           'price', 7.5, 'bal', [10 20 -1.5], 'hcode', [0 4 72]);
[cmd, oo] = proto_decode_cmd(proto_encode_cmd(9, o), n);
verifyEqual(tc, cmd.breaker, 1); verifyEqual(tc, cmd.tie, [1 0 0]); verifyEqual(tc, cmd.flex, [1 0 0]);
verifyEqual(tc, oo.hcode, [0 4 72]); verifyEqual(tc, cmd.p_set, -1234.5);
end

function test_house_is_duplicable(tc)
P = tc.TestData.P;
P.house(4) = P.house(1); P.house(4).id = 'H4'; P.n_house = 4;
sc = base_scenario(P, 'dup'); sc.t0_h = 12; sc.dur_s = 120;
R = run_scenario(sc, P);
verifyEqual(tc, size(R.L.p_pv, 2), 4);
verifyGreaterThan(tc, R.L.p_pv(end, 4), 0);
end
