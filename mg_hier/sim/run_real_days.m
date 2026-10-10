function T = run_real_days(P, make_plots)
% RUN_REAL_DAYS  Run the microgrid on representative REAL days (pick_days) and on
% the old synthetic day, and compare. Two runs per day:
%   A "normal day"  00:00-24:00, grid always on, battery starts at 50 %
%   B "outage"      06:00-23:00, battery starts at 40 % at 06:00, grid lost 18:00-22:00
% Run B asks the key question: did that day's sun charge the battery enough to
% carry the evening outage, and how much flexible load had to be shed?
if nargin < 1, P = hier_params(); end
if nargin < 2, make_plots = true; end
D = pick_days(P);
lab = ["synthetic"; D.label]; day = [NaT; D.date];
nC = numel(lab); jobs = [repmat((1:nC)', 2, 1), [ones(nC, 1); 2 * ones(nC, 1)]];
res = cell(size(jobs, 1), 1);
parfor q = 1:size(jobs, 1)
    c = jobs(q, 1); kind = jobs(q, 2);
    if kind == 1, t0 = 0; dur = 24 * 3600; soc0 = 0.50; else, t0 = 6; dur = 17 * 3600; soc0 = 0.40; end
    if c == 1
        sc = base_scenario_h(P, 'SYNTHETIC'); sc.t0_h = t0; sc.dur_s = dur; sc.info = 'old made-up sun'; sc.load_note = 'old made-up loads';
    else
        sc = real_day_scenario(P, day(c), t0, dur);
    end
    sc.soc0 = soc0;
    if kind == 2
        a = (18 - t0) * 3600; b = (22 - t0) * 3600; f0 = P.ac.f_nom;
        sc.events = [a b]; sc.grid_fn = @(t) [~(t >= a && t < b), f0];
    end
    R = run_hier(sc, P, struct('pi', false));
    [ok, msg] = check_h(R, P);
    res{q} = summarise(R, P, sc, kind, ok, msg);
end
% ---- table ----
T = table(); 
for c = 1:nC
    A = res{c}; B = res{c + nC};
    row = table(lab(c), day(c), A.pv_kWh, A.load_kWh, A.import_kWh, A.export_kWh, A.self_suff, A.p2p_kWh, ...
        B.soc_18, B.soc_min, B.shed_kWh, B.shed_first, B.dark_s, B.ok, string(A.info), string(A.load_note), ...
        'VariableNames', {'case', 'date', 'pv_kWh', 'load_kWh', 'grid_import_kWh', 'grid_export_kWh', 'self_sufficiency', ...
        'p2p_kWh', 'outage_soc_at_18h', 'outage_soc_min', 'outage_flex_shed_kWh', 'outage_first_shed', 'outage_dark_s', ...
        'rules_ok', 'sun', 'loads'});
    T = [T; row]; %#ok<AGROW>
end
od = fullfile(fileparts(P.data.dir), 'results', 'tables'); writetable(T, fullfile(od, 'real_days.csv'));
disp(T(:, 1:14));
if make_plots, plot_real_days(res, lab, nC, P); end
end

function s = summarise(R, P, sc, kind, ok, msg)
L = R.L; Wh = P.sim.dt / 3600; K = R.kpi;
t_h = mod(sc.t0_h + L.t / 3600, 24);
s.kind = kind; s.ok = ok; s.msg = strjoin(string(msg), '; ');
s.info = sc.info; s.load_note = sc.load_note;
s.pv_kWh = (sum(sum(L.p_pv, 2)) + sum(L.p_cpv)) * Wh / 1000;
s.load_kWh = (sum(sum(L.p_load, 2)) + sum(L.p_cl)) * Wh / 1000;
s.import_kWh = K.grid_import_Wh / 1000; s.export_kWh = K.grid_export_Wh / 1000;
s.self_suff = 1 - s.import_kWh / max(s.load_kWh, eps);
s.p2p_kWh = sum(K.ledger.matrix(:)) / 1000;
i18 = find(t_h >= 18, 1); if isempty(i18), i18 = numel(L.t); end
s.soc_18 = L.soc(i18); s.soc_min = min(L.soc);
s.shed_kWh = sum(sum(L.p_flex_dem - L.p_flex_srv)) * Wh / 1000;
sh = find(any(bitand(L.hcode, 4) > 0, 2), 1);
if isempty(sh), s.shed_first = "none"; else, s.shed_first = string(sprintf('%02d:%02d', floor(t_h(sh)), floor(mod(t_h(sh), 1) * 60))); end
s.dark_s = sum(~L.energised(L.mode > 0)) * P.sim.dt;
k = 1:30:numel(L.t);                                            % keep every 30 s for plots
s.t_h = sc.t0_h + L.t(k) / 3600; s.soc = L.soc(k); s.pv = sum(L.p_pv(k, :), 2) + L.p_cpv(k);
s.load = sum(L.p_load(k, :), 2) + L.p_cl(k); s.pcc = L.p_pcc(k); s.pbess = L.p_bess(k);
end

function plot_real_days(res, lab, nC, P)
f = figure('Visible', 'off', 'Position', [40 40 1250 950], 'Color', 'w');
tl = tiledlayout(f, 3, 1, 'TileSpacing', 'compact');
title(tl, 'Model on real days (NASA POWER sun, eMARC household loads) vs the old synthetic day', 'FontWeight', 'bold');
col = [0 0 0; lines(nC - 1)];
ax = nexttile(tl); hold(ax, 'on');
for c = 1:nC, B = res{c + nC}; plot(ax, B.t_h, 100 * B.soc, 'Color', col(c, :), 'LineWidth', 1.4 + (c == 1)); end
xline(ax, [18 22], '--', {'grid lost', 'grid back'}); grid(ax, 'on'); xlim(ax, [6 23]);
ylabel(ax, 'battery %'); legend(ax, replace(lab, '_', ' '), 'Location', 'eastoutside');
title(ax, 'Run B: battery charge through the day and a 4-hour evening outage (start 40 % at 06:00)');
for c = [2 nC - 1]
    if c > nC, continue; end
    A = res{c}; ax = nexttile(tl); hold(ax, 'on');
    plot(ax, A.t_h, A.pv / 1000, 'Color', [0.9 0.6 0.1]); plot(ax, A.t_h, A.load / 1000, 'k');
    plot(ax, A.t_h, A.pcc / 1000, 'b'); plot(ax, A.t_h, A.pbess / 1000, 'Color', [0.2 0.6 0.2]);
    yyaxis(ax, 'right'); plot(ax, A.t_h, 100 * A.soc, 'm--'); ylabel(ax, 'battery %'); yyaxis(ax, 'left');
    grid(ax, 'on'); xlim(ax, [0 24]); xticks(ax, 0:2:24); ylabel(ax, 'kW');
    legend(ax, 'all solar', 'all loads', 'grid (+ import)', 'battery (+ discharge)', 'battery %', 'Location', 'eastoutside');
    title(ax, sprintf('Run A on the %s day: %s', replace(lab(c), '_', ' '), A.info));
end
fig = fullfile(fileparts(P.data.dir), 'results', 'figures', 'real_days_compare.png');
exportgraphics(f, fig, 'Resolution', 110); close(f); fprintf('figure %s\n', fig);
end
