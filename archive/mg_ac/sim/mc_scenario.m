function [sc, Pp] = mc_scenario(P, i)
% MC_SCENARIO  Random evening + random grid outage (+ sometimes a voltage sag),
% clouds, loads, sensor noise, and a plant whose parameters differ from the
% controller's nominal ones. The controller keeps P; the plant gets Pp.
rs = RandStream('mt19937ar', 'Seed', 1000 + i);
u = @(a, b) a + (b - a) * rand(rs);
f0 = P.ac.f_nom;
sc = base_scenario(P, 'MC'); sc.seed = 2000 + i;
sc.t0_h = 16; sc.dur_s = 5 * 3600; sc.soc0 = u(0.6, 0.95);
sc.pv_gain = u(0.6, 1.1);
if rand(rs) < 0.5
    seg = 0.3 + 0.7 * rand(rs, 1, ceil(sc.dur_s / 600) + 1);
    sc.cloud_fn = @(t) seg(floor(t / 600) + 1);
end
sc.load_gain = u(0.7, 1.2) * ones(1, P.n_house) .* (0.9 + 0.2 * rand(rs, 1, P.n_house));
a = round(u(1.0, 2.0) * 3600); b = round(a + u(0.5, 1.5) * 3600);
sc.events = [a b];
if rand(rs) < 0.5                                  % an extra voltage sag after the outage
    c = b + round(u(900, 1800)); d = c + round(u(30, 120));
    sc.events = [sc.events; c d];
    sc.grid_fn = @(t) [~(t >= a && t < b) * (1 - 0.2 * (t >= c && t < d)), f0];
else
    sc.grid_fn = @(t) [~(t >= a && t < b), f0];
end
sc.noise_P = 10; sc.noise_V = 0.5;
Pp = P;
Pp.grid.Z_th = P.grid.Z_th * u(0.7, 1.5);
for k = 1:P.n_house, Pp.house(k).Z_line = P.house(k).Z_line * u(0.7, 1.5); end
Pp.bess.E_kWh = P.bess.E_kWh * u(0.9, 1.05);
end
