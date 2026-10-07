function S = define_scenarios(P)
% DEFINE_SCENARIOS  Validation scenarios; pass rules are in tests/check_scenario.m.
f0 = P.ac.f_nom; bad = 305419896; uid3 = P.house(3).card_uid;

s = base_scenario(P, 'S1_normal_day');          % grid-connected 24 h
s.t0_h = 0; s.dur_s = 24*3600; s.soc0 = 0.60;
S(1) = s;

s = base_scenario(P, 'S2_grid_outage');         % evening blackout, island, resync
s.t0_h = 16; s.dur_s = 7*3600; s.soc0 = 0.80;
s.events = [2*3600 4*3600];
s.grid_fn = @(t) [~(t >= 2*3600 && t < 4*3600), f0];
S(2) = s;

s = base_scenario(P, 'S3_low_battery_outage');  % battery-priority shedding
s.t0_h = 16; s.dur_s = 4*3600; s.soc0 = 0.48;
s.events = [1800 1800+2*3600];
s.grid_fn = @(t) [~(t >= 1800 && t < 1800+2*3600), f0];
S(3) = s;

s = base_scenario(P, 'S4_island_overload');     % evening peak > BESS rating -> UFLS
s.t0_h = 18.5; s.dur_s = 1800; s.soc0 = 0.90; s.load_gain = [1.5 1.5 1.5];
s.events = [120 1500];
s.grid_fn = @(t) [~(t >= 120 && t < 1500), f0];
S(4) = s;

s = base_scenario(P, 'S5_island_surplus');      % sunny noon, battery nearly full
s.t0_h = 11; s.dur_s = 3*3600; s.soc0 = 0.90;
s.events = [60 3*3600-600];
s.grid_fn = @(t) [~(t >= 60 && t < 3*3600-600), f0];
S(5) = s;

s = base_scenario(P, 'S6_faulty_house');        % short circuit in House 3
s.t0_h = 12; s.dur_s = 1200;
s.faults = struct('house', 3, 'R', 3.0, 't_on', 300, 't_off', inf);
S(6) = s;

s = base_scenario(P, 'S7_abnormal_grid');       % voltage sag, then low frequency
s.t0_h = 10; s.dur_s = 2400;
s.events = [300 360; 1200 1260];
s.grid_fn = @(t) abnormal(t, f0);
S(7) = s;

s = base_scenario(P, 'S8_prepaid_cards');       % bad cards, zero credit, top-up
s.t0_h = 17; s.dur_s = 8*3600;
s.cards = [300 3 bad; 310 3 bad; 320 3 bad; 340 3 uid3; 400 3 uid3; 7.5*3600 3 uid3];
S(8) = s;

s = base_scenario(P, 'S9_ai_advisor');          % AI commands checked by the rules
s.t0_h = 19; s.dur_s = 2400; s.soc0 = 0.25;
s.ai_fn = @(t) ai_script(t);
s.events = [1500 2100];
s.grid_fn = @(t) [~(t >= 1500 && t < 2100), f0];
S(9) = s;

s = base_scenario(P, 'S10_long_outage_blackout');   % battery empties -> blackout -> dead-bus recovery
s.t0_h = 18; s.dur_s = 6*3600; s.soc0 = 0.40;
s.events = [600 4*3600];
s.grid_fn = @(t) [~(t >= 600 && t < 4*3600), f0];
S(10) = s;

s = base_scenario(P, 'S11_demo_outage');     % short live demo: 10-minute evening blackout
s.t0_h = 17.9; s.dur_s = 1500; s.soc0 = 0.80;
s.events = [180 780];
s.grid_fn = @(t) [~(t >= 180 && t < 780), f0];
S(11) = s;
end

function g = abnormal(t, f0)
g = [1 f0];
if t >= 300 && t < 360,   g = [0.80 f0];  end       % sag to 0.8 pu
if t >= 1200 && t < 1260, g = [1 49.2];   end       % under-frequency grid
end

function a = ai_script(t)
% 300-600 s : discharge 5 kW (unsafe at SOC 0.25 -> clamped), shed H3, price 8 (ok)
% 600-900 s : same but price 50 (refused)
% 900-1500 s: AI silent -> rules after the 30 s timeout
% 1500-2100 s (island): AI asks 3 kW -> ignored (status 8)
a = ai_cmd();
if t >= 300 && t < 600,  a = ai_cmd(1, 5000, 4, 8);  end
if t >= 600 && t < 900,  a = ai_cmd(1, 5000, 4, 50); end
if t >= 1500 && t < 2100, a = ai_cmd(1, 3000, 0, 6); end
end
