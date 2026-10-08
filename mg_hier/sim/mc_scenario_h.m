function [sc, Pp] = mc_scenario_h(P, i)
% MC_SCENARIO_H  Random evening + random grid outage (+ sometimes a voltage sag),
% clouds, loads, sensor noise, a random node-link dropout on a load node, and a
% plant whose parameters differ from the controller's nominal ones.
rs = RandStream('mt19937ar', 'Seed', 1000 + i);
u = @(a, b) a + (b - a) * rand(rs);
f0 = P.ac.f_nom;
sc = base_scenario_h(P, 'MC'); sc.seed = 2000 + i;
sc.t0_h = 16; sc.dur_s = 5 * 3600; sc.soc0 = u(0.6, 0.95);
sc.pv_gain = u(0.6, 1.1);
if rand(rs) < 0.5
    seg = 0.3 + 0.7 * rand(rs, 1, ceil(sc.dur_s / 600) + 1);
    sc.cloud_fn = @(t) seg(floor(t / 600) + 1);
end
sc.load_gain = u(0.7, 1.2) * ones(1, P.n_load) .* (0.9 + 0.2 * rand(rs, 1, P.n_load));
a = round(u(1.0, 2.0) * 3600); b = round(a + u(0.5, 1.5) * 3600);
sc.events = [a b];
if rand(rs) < 0.5                                  % an extra voltage sag after the outage
    c = b + round(u(900, 1800)); d = c + round(u(30, 120));
    sc.events = [sc.events; c d];
    sc.grid_fn = @(t) [~(t >= a && t < b) * (1 - 0.2 * (t >= c && t < d)), f0];
else
    sc.grid_fn = @(t) [~(t >= a && t < b), f0];
end
k = randi(rs, P.n_load); t1 = round(u(300, sc.dur_s - 600));
sc.link_drops = struct('node', P.load_id{k}, 't_on', t1, 't_off', t1 + round(u(10, 40)));
sc.noise_P = 10; sc.noise_V = 0.5;
Pp = P;
Pp.grid.Z_th = P.grid.Z_th * u(0.7, 1.5);
for k = 1:P.n_house, Pp.house(k).Z_line = P.house(k).Z_line * u(0.7, 1.5); end
Pp.bess.E_kWh = P.bess.E_kWh * u(0.9, 1.05);
end
