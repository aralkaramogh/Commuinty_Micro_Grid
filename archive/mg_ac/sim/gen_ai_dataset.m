function T = gen_ai_dataset(P, n_days, out_file, step_s)
% GEN_AI_DATASET  Training data for the AI/ML team: n_days random days at
% step_s resolution (default 60 s) with random clouds, loads, grid outages and
% sags, plus INJECTED ANOMALIES with ground-truth labels:
%   frozen load sensor, abnormal load (high-impedance fault), card abuse.
% Load data is synthetic (stated in docs/data_contract.md). To use real
% irradiance, give each scenario sc.irr_hourly (24 hourly W/m2 values).
if nargin < 4, step_s = 60; end
Pd = P; Pd.sim.dt = step_s;
parts = cell(n_days, 1);
parfor d = 1:n_days
    [sc, Pp] = day_scenario(Pd, d);
    R = run_scenario(sc, Pd, struct('P_plant', Pp));
    parts{d} = ai_table(R, Pd, step_s, d);
end
T = vertcat(parts{:});
if nargin >= 3 && ~isempty(out_file), writetable(T, out_file); end
end

function [sc, Pp] = day_scenario(P, d)
rs = RandStream('mt19937ar', 'Seed', 50000 + d);
u = @(a, b) a + (b - a) * rand(rs);
dt = P.sim.dt; snap = @(t) dt * round(t / dt);
sc = base_scenario(P, sprintf('day_%04d', d)); sc.seed = 60000 + d;
sc.t0_h = 0; sc.dur_s = 24 * 3600; sc.soc0 = u(0.4, 0.9); sc.pv_gain = u(0.5, 1.1);
seg = min(1, 0.25 + 0.9 * rand(rs, 1, 49));                     % 30-min cloud factors
sc.cloud_fn = @(t) seg(floor(t / 1800) + 1);
sc.load_gain = 0.7 + 0.6 * rand(rs, 1, P.n_house);
f0 = P.ac.f_nom; ev = zeros(0, 3);                             % [start end V_pu]
if rand(rs) < 0.4, a = snap(u(8, 22) * 3600); ev(end+1,:) = [a, a + snap(u(0.5, 2) * 3600), 0]; end
if rand(rs) < 0.2, a = snap(u(1, 23) * 3600); ev(end+1,:) = [a, a + snap(u(60, 600)), 0.8]; end
sc.events = ev(:, 1:2);
sc.grid_fn = @(t) [grid_v(t, ev), f0];
if rand(rs) < 0.25
    a = snap(u(1, 20) * 3600);
    sc.sensor_faults = struct('house', randi(rs, P.n_house), 't_on', a, 't_off', a + snap(u(1, 3) * 3600));
end
if rand(rs) < 0.25
    a = snap(u(1, 21) * 3600);
    sc.faults = struct('house', randi(rs, P.n_house), 'R', 20, 't_on', a, 't_off', a + snap(u(1, 2) * 3600));
end
cards = zeros(0, 3);
for k = 1:P.n_house                                             % normal top-ups
    cards(end+1, :) = [snap(u(7, 21) * 3600), k, P.house(k).card_uid]; %#ok<AGROW>
end
if rand(rs) < 0.25                                              % card abuse burst
    k = randi(rs, P.n_house); a = snap(u(1, 22) * 3600);
    for j = 0:randi(rs, [3 6]) - 1, cards(end+1, :) = [a + j * dt, k, 305419896 + j]; end %#ok<AGROW>
end
sc.cards = cards;
sc.noise_P = 10; sc.noise_V = 0.5;
Pp = P;
for k = 1:P.n_house, Pp.house(k).Z_line = P.house(k).Z_line * u(0.8, 1.3); end
end

function v = grid_v(t, ev)
v = 1;
for i = 1:size(ev, 1)
    if t >= ev(i,1) && t < ev(i,2), v = ev(i,3); end
end
end
