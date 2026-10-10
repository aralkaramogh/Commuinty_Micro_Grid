function E = import_emarc(P, make_plots)
% IMPORT_EMARC  Prayas eMARC 15-minute household load data (raw, 368 MB)
%   -> data/processed/emarc_load_shapes.mat (small) + a figure.
% What it does (each step prints what it found, so the run doubles as a lesson):
%   1 read the household list; keep Maharashtra homes and the MAIN-LINE meter
%     (each home also had a second meter on one appliance - not what we want)
%   2 read the 15-minute load file (only the columns we need)
%   3 build one row of 96 values (kW) per home per day; drop bad days
%     (missing blocks, meter offline = all zero, impossible values)
%   4 per-home statistics: energy per day, peak, load factor
%   5 typical day SHAPES per season and weekday/weekend, normalised to 1 kWh/day,
%     plus the spread between homes (10th-90th percentile)
%   6 keep a library of real normalised home-days for Monte Carlo sampling
if nargin < 1, P = hier_params(); end
if nargin < 2, make_plots = true; end
d = fullfile(P.data.dir, 'raw', 'emarc');
pick = @(pat) first_file(d, pat);

% ---- 1 households ----
fi = pick('*asic info*');
if endsWith(fi, '.xlsx'), Hh = readtable(fi, 'VariableNamingRule', 'preserve');
else, Hh = readtable(fi, 'FileType', 'text', 'Delimiter', '\t', 'VariableNamingRule', 'preserve'); end
Hh.Properties.VariableNames = regexprep(lower(Hh.Properties.VariableNames), '[^a-z0-9]', '');   % 'Deployment type' -> 'deploymenttype'
reg = string(Hh.region); dtyp = string(Hh.deploymenttype); htyp = string(Hh.householdtype);
fprintf('[1] %d deployments in %d homes\n    regions: %s\n    deployment types: %s\n    household types: %s\n', ...
    height(Hh), numel(unique(Hh.householdid)), strjoin(unique(reg), ' | '), strjoin(unique(dtyp), ' | '), strjoin(unique(htyp), ' | '));
isMH = contains(lower(reg), ["maharashtra", "pune", "aurangabad"]);
isMain = contains(lower(dtyp), ["main", "whole", "house", "home"]) & ~contains(lower(dtyp), "appliance");
keep = Hh(isMH & isMain, :);
fprintf('    kept %d Maharashtra main-line meters\n', height(keep));
assert(height(keep) > 0, 'filter matched nothing - check the printed region/deployment names');

% ---- 2 15-minute load file ----
fl = pick('*load blocks*');
t0 = tic;
opts = detectImportOptions(fl, 'VariableNamingRule', 'preserve');
vn = string(opts.VariableNames); vl = lower(strtrim(erase(vn, char(65279))));
c_dep = vn(find(contains(vl, "deployment") & contains(vl, "id"), 1));
c_date = vn(find(vl == "date" | contains(vl, "date"), 1));
c_blk = vn(find(contains(vl, "block") & ~contains(vl, "load"), 1));
c_load = vn(find(contains(vl, "load") | contains(vl, "kw") | contains(vl, "power"), 1));
if isempty(c_load), c_load = vn(end); end
fprintf('[2] columns in the load file: %s\n    using: id=%s date=%s block=%s load=%s\n', strjoin(vn, ', '), c_dep, c_date, c_blk, c_load);
opts.SelectedVariableNames = cellstr([c_dep c_date c_blk c_load]);
opts = setvartype(opts, cellstr(c_dep), 'string');
opts = setvartype(opts, cellstr(c_date), 'datetime'); opts = setvaropts(opts, cellstr(c_date), 'InputFormat', 'M/d/yyyy');
T = readtable(fl, opts);
T.Properties.VariableNames = {'dep', 'date', 'blk', 'kW'};
if ~isdatetime(T.date), T.date = datetime(string(T.date)); end
fprintf('    read %d rows in %.0f s (%s .. %s)\n', height(T), toc(t0), string(min(T.date), 'dd-MMM-yyyy'), string(max(T.date), 'dd-MMM-yyyy'));
T = T(ismember(T.dep, string(keep.deploymentid)), :);
fprintf('    %d rows belong to the kept meters\n', height(T));

% ---- 3 one row of 96 values per meter-day ----
T.day = dateshift(T.date, 'start', 'day');
[g, gdep, gday] = findgroups(T.dep, T.day);
n = max(g); X = nan(n, 96, 'single');
X(sub2ind(size(X), g, double(T.blk) + 1)) = single(T.kW);
nblk = sum(~isnan(X), 2);
bad_missing = nblk < 92;                              % more than 1 hour missing
X = fillmissing(X, 'linear', 2, 'EndValues', 'nearest');
dayE = sum(X, 2, 'omitnan') * 0.25;                   % kWh per day (15 min = 0.25 h)
bad_zero = dayE < 0.1;                                % meter offline / house empty
bad_high = max(X, [], 2) > 15;                        % > 15 kW on a home meter: not plausible
ok = ~(bad_missing | bad_zero | bad_high);
fprintf(['[3] %d meter-days; dropped: %d with >1 h missing, %d near-zero (offline/empty), %d impossible peaks\n' ...
         '    kept %d good meter-days from %d homes\n'], n, nnz(bad_missing), nnz(bad_zero & ~bad_missing), ...
         nnz(bad_high & ~bad_missing & ~bad_zero), nnz(ok), numel(unique(gdep(ok))));
X = X(ok, :); dep = gdep(ok); day = gday(ok); dayE = dayE(ok);

% ---- 4 per-home statistics ----
[hg, hdep] = findgroups(dep);
st = table(hdep, splitapply(@numel, dayE, hg), splitapply(@mean, dayE, hg), ...
     splitapply(@(x) prctile(max(x, [], 2), 95), X, hg), 'VariableNames', {'deployment', 'good_days', 'kWh_per_day', 'peak95_kW'});
st.load_factor = st.kWh_per_day / 24 ./ st.peak95_kW;
st = st(st.good_days >= 30, :);
fprintf(['[4] homes with >= 30 good days: %d\n    energy per day: median %.2f kWh (10-90%%: %.2f-%.2f) = about %.0f units/month\n' ...
         '    daily peak (95th pct of 15-min blocks): median %.2f kW;  load factor median %.2f\n'], height(st), ...
         median(st.kWh_per_day), prctile(st.kWh_per_day, 10), prctile(st.kWh_per_day, 90), median(st.kWh_per_day) * 30, ...
         median(st.peak95_kW), median(st.load_factor));
use = ismember(dep, st.deployment); X = X(use, :); dep = dep(use); day = day(use); dayE = dayE(use);

% ---- 5 typical shapes ----
seas = season_of(month(day)); wk = isweekend(day);
Xn = X ./ dayE;                                       % each home-day scaled to 1 kWh/day
names = ["summer (Mar-May)", "monsoon (Jun-Sep)", "post-monsoon (Oct-Nov)", "winter (Dec-Feb)"];
shape = zeros(4, 2, 96); p10 = shape; p90 = shape; nday = zeros(4, 2); Eseas = zeros(4, 1);
for s = 1:4
    Eseas(s) = median(dayE(seas == s));
    for w = 1:2
        r = seas == s & wk == (w == 2); nday(s, w) = nnz(r);
        % average per home first (so homes with many days do not dominate), then across homes
        [gg, ~] = findgroups(dep(r)); Mh = splitapply(@(x) mean(x, 1), Xn(r, :), gg);
        shape(s, w, :) = mean(Mh, 1); p10(s, w, :) = prctile(Mh, 10, 1); p90(s, w, :) = prctile(Mh, 90, 1);
    end
end
fprintf('[5] typical energy per home per day by season: %s kWh\n', strjoin(compose('%s %.2f', names(:), Eseas), ', '));
[~, bpk] = max(squeeze(shape(1, 1, :))); fprintf('    summer weekday peak block: %s\n', blk_time(bpk - 1));

E = struct('source', "Prayas (Energy Group) eMARC, Harvard Dataverse doi:10.7910/DVN/YJ5SP1, CC0", ...
    'region', "Maharashtra main-line meters", 'blocks_min', 15, 'seasons', names, 'daytypes', ["weekday", "weekend"], ...
    'shape', shape, 'p10', p10, 'p90', p90, 'n_days', nday, 'E_season_kWh', Eseas, 'homes', st, ...
    'lib_kW_norm', Xn, 'lib_day', day, 'lib_dep', dep, 'lib_kWh', dayE, 'made', datetime('now'));
out = fullfile(P.data.dir, 'processed', P.data.load_file);
save(out, '-struct', 'E'); fprintf('    saved %s (%.1f MB)\n', out, dir(out).bytes / 1e6);

if make_plots
    f = figure('Visible', 'off', 'Position', [50 50 1200 850], 'Color', 'w');
    tl = tiledlayout(f, 2, 2, 'TileSpacing', 'compact');
    title(tl, sprintf('eMARC: %d Maharashtra homes, 15-minute load (2018-2020)', height(st)), 'FontWeight', 'bold');
    hb = (0:95) / 4 + 0.125; col = lines(4);
    ax = nexttile(tl); hold(ax, 'on');
    for s = 1:4, plot(ax, hb, squeeze(shape(s, 1, :)) * Eseas(s), 'Color', col(s, :), 'LineWidth', 1.5); end
    grid(ax, 'on'); xlim(ax, [0 24]); xticks(ax, 0:3:24); xlabel(ax, 'hour (IST)'); ylabel(ax, 'kW (typical home)');
    legend(ax, names, 'Location', 'northwest'); title(ax, 'Typical weekday load by season');
    ax = nexttile(tl); s = 1; fill(ax, [hb fliplr(hb)], [squeeze(p10(s,1,:))' fliplr(squeeze(p90(s,1,:))')] * Eseas(s), [.85 .85 1], 'EdgeColor', 'none'); hold(ax, 'on');
    plot(ax, hb, squeeze(shape(s, 1, :)) * Eseas(s), 'b', 'LineWidth', 1.5); grid(ax, 'on'); xlim(ax, [0 24]); xticks(ax, 0:3:24);
    xlabel(ax, 'hour (IST)'); ylabel(ax, 'kW'); title(ax, 'Summer weekday: spread between homes (10-90%)');
    ax = nexttile(tl); histogram(ax, st.kWh_per_day * 30, 15, 'FaceColor', [.3 .5 .8]); grid(ax, 'on');
    xlabel(ax, 'units (kWh) per month'); ylabel(ax, 'homes'); title(ax, 'How much each home uses');
    ax = nexttile(tl); histogram(ax, st.peak95_kW, 15, 'FaceColor', [.8 .4 .3]); grid(ax, 'on');
    xlabel(ax, 'kW'); ylabel(ax, 'homes'); title(ax, 'Daily peak (15-min average, 95th percentile)');
    fig = fullfile(fileparts(P.data.dir), 'results', 'figures', 'data_emarc_loads.png');
    exportgraphics(f, fig, 'Resolution', 110); close(f); fprintf('    figure %s\n', fig);
end
end

function f = first_file(d, pat)
l = dir(fullfile(d, pat)); l = l(~[l.isdir]);
assert(~isempty(l), 'no file matching %s in %s (run fetch_emarc for download steps)', pat, d);
f = fullfile(d, l(1).name);
end

function s = season_of(m)
s = 4 * ones(size(m)); s(m >= 3 & m <= 5) = 1; s(m >= 6 & m <= 9) = 2; s(m >= 10 & m <= 11) = 3;
end

function t = blk_time(b)
t = sprintf('%02d:%02d-%02d:%02d', floor(b / 4), mod(b, 4) * 15, floor((b + 1) / 4), mod(b + 1, 4) * 15);
end
