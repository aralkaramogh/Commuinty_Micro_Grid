function S = define_scenarios_h(P)
% DEFINE_SCENARIOS_H  Validation scenarios; pass rules are in tests/check_h.m.
% Load nodes: 1 = H1 (prosumer), 2 = H2 (consumer, low credit), 3 = CL (community pump).
f0 = P.ac.f_nom; bad = 305419896; uid2 = P.house(2).card_uid;

s = base_scenario_h(P, 'S1_normal_day');          % grid-connected 24 h
s.t0_h = 0; s.dur_s = 24*3600; s.soc0 = 0.60;
S(1) = s;

s = base_scenario_h(P, 'S2_grid_outage');         % evening blackout, island, resync
s.t0_h = 16; s.dur_s = 7*3600; s.soc0 = 0.80;
s.events = [2*3600 4*3600];
s.grid_fn = @(t) [~(t >= 2*3600 && t < 4*3600), f0];
S(2) = s;

s = base_scenario_h(P, 'S3_low_battery_outage');  % battery-priority shedding
s.t0_h = 16; s.dur_s = 4*3600; s.soc0 = 0.48;
s.events = [1800 1800+2*3600];
s.grid_fn = @(t) [~(t >= 1800 && t < 1800+2*3600), f0];
S(3) = s;

s = base_scenario_h(P, 'S4_island_overload');     % evening peak > BESS comfort -> UFLS
s.t0_h = 18.5; s.dur_s = 1800; s.soc0 = 0.90; s.load_gain = [1.5 1.5 1.5];
s.events = [120 1500];
s.grid_fn = @(t) [~(t >= 120 && t < 1500), f0];
S(4) = s;

s = base_scenario_h(P, 'S5_island_surplus');      % sunny noon, battery nearly full
s.t0_h = 11; s.dur_s = 3*3600; s.soc0 = 0.90;
s.events = [60 3*3600-600];
s.grid_fn = @(t) [~(t >= 60 && t < 3*3600-600), f0];
S(5) = s;

s = base_scenario_h(P, 'S6_faulty_house');        % short circuit in House 2
s.t0_h = 12; s.dur_s = 1200;
s.faults = struct('house', 2, 'R', 3.0, 't_on', 300, 't_off', inf);
S(6) = s;

s = base_scenario_h(P, 'S7_abnormal_grid');       % voltage sag, then low frequency
s.t0_h = 10; s.dur_s = 2400;
s.events = [300 360; 1200 1260];
s.grid_fn = @(t) abnormal(t, f0);
S(7) = s;

s = base_scenario_h(P, 'S8_prepaid_cards');       % bad cards, zero credit, top-up (House 2)
s.t0_h = 17; s.dur_s = 8*3600; s.load_gain = [1 1.5 1];
s.cards = [300 2 bad; 310 2 bad; 320 2 bad; 340 2 uid2; 400 2 uid2; 7.5*3600 2 uid2];
S(8) = s;

s = base_scenario_h(P, 'S9_ai_advisor');          % AI requests checked by the main controller
s.t0_h = 19; s.dur_s = 2400; s.soc0 = 0.25;
s.ai_fn = @(t) ai_script(t);
s.events = [1500 2100];
s.grid_fn = @(t) [~(t >= 1500 && t < 2100), f0];
S(9) = s;

s = base_scenario_h(P, 'S10_long_outage_blackout');   % battery empties -> blackout -> dead-bus recovery
s.t0_h = 18; s.dur_s = 6*3600; s.soc0 = 0.40;
s.events = [600 4*3600];
s.grid_fn = @(t) [~(t >= 600 && t < 4*3600), f0];
S(10) = s;

s = base_scenario_h(P, 'S11_demo_outage');        % short live demo: 10-minute evening blackout
s.t0_h = 17.9; s.dur_s = 1500; s.soc0 = 0.80;
s.events = [180 780];
s.grid_fn = @(t) [~(t >= 180 && t < 780), f0];
S(11) = s;

s = base_scenario_h(P, 'S12_node_comms_loss');    % node links drop: nodes fall back safely
s.t0_h = 12; s.dur_s = 1200;
s.link_drops = struct('node', {'H1', 'SB', 'CL'}, 't_on', {300, 600, 900}, 't_off', {330, 640, 910});
S(12) = s;

s = base_scenario_h(P, 'S13_dashboard_commands'); % operator / user / AI requests, ACL + checks
s.t0_h = 10; s.dur_s = 1200;
s.cmds = [ ...
  pi_cmd(100, 'dash', 'mg/cmd/op/restrict',          'id', 1,  'target', 'CL', 'value', 1, 'ttl', 300), ...
  pi_cmd(150, 'H1',   'mg/cmd/user/H1/user_flex',    'id', 2,  'target', 'H1', 'value', 0, 'ttl', 200), ...
  pi_cmd(160, 'H1',   'mg/cmd/user/H1/user_flex',    'id', 3,  'target', 'H2', 'value', 0, 'ttl', 100), ...
  pi_cmd(170, 'dash', 'mg/cmd/op/cut_critical',      'id', 4,  'target', 'H2', 'value', 1, 'ttl', 60), ...
  pi_cmd(180, 'ai',   'mg/cmd/ai/restrict',          'id', 5,  'target', 'CL', 'value', 1, 'ttl', 60), ...
  pi_cmd(190, 'dash', 'mg/cmd/op/restrict',          'id', 1,  'target', 'H2', 'value', 1, 'ttl', 60), ...
  pi_cmd(200, 'dash', 'mg/cmd/op/restrict',          'id', 6,  'target', 'H2', 'value', 1, 'ttl', 60, 't_sent', 150), ...
  pi_cmd(210, 'dash', 'mg/cmd/op/restrict',          'id', 7,  'target', 'H2', 'value', 1, 'ttl', 99999), ...
  pi_cmd(220, 'dash', 'mg/cmd/op/restrict',          'id', 8,  'target', 'H9', 'value', 1, 'ttl', 60), ...
  pi_cmd(230, 'H2',   'mg/cmd/op/restrict',          'id', 9,  'target', 'H1', 'value', 1, 'ttl', 60), ...
  pi_cmd(240, 'H1',   'mg/cmd/user/H2/user_flex',    'id', 10, 'target', 'H2', 'value', 0, 'ttl', 60), ...
  pi_cmd(250, 'dash', 'mg/cmd/op/restrict',          'id', 11, 'target', 'H2', 'value', 1, 'ttl', 60), ...
  pi_cmd(260, '',     'mg/cmd/op/restrict',          'id', 12, 'target', 'H1', 'value', 1, 'ttl', 60)];
S(13) = s;
end

function g = abnormal(t, f0)
g = [1 f0];
if t >= 300 && t < 360,   g = [0.80 f0];  end       % sag to 0.8 pu
if t >= 1200 && t < 1260, g = [1 49.2];   end       % under-frequency grid
end

function a = ai_script(t)
% 300-600 s : discharge 5 kW (unsafe at SOC 0.25 -> clamped), shed CL pump, price 8 (ok)
% 600-900 s : same but price 50 (refused)
% 900-1500 s: AI silent -> rules after the 30 s timeout
% 1500-2100 s (island): AI asks 3 kW -> ignored (status 8)
a = ai_cmd();
if t >= 300 && t < 600,  a = ai_cmd(1, 5000, 4, 8);  end
if t >= 600 && t < 900,  a = ai_cmd(1, 5000, 4, 50); end
if t >= 1500 && t < 2100, a = ai_cmd(1, 3000, 0, 6); end
end
