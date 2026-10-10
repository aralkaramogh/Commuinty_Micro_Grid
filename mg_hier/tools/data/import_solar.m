function S = import_solar(P, make_plots)
% IMPORT_SOLAR  NASA POWER hourly CSV (raw, UTC) -> data/processed/solar_sangli_<year>.mat
% Steps (each one is printed so the run doubles as a lesson):
%   1 read the raw file (skip the text header, read the column names)
%   2 replace the missing-value code -999 by NaN and fill short gaps
%   3 work out what the hour stamp means (start or middle of the hour) from the
%     clear-sky curve, which must be symmetric about solar noon
%   4 convert UTC -> IST and build daily totals (kWh/m2/day) and a clear-sky index
%   5 sanity checks: yearly sunshine and our PV model's yearly yield per kWp
if nargin < 1, P = hier_params(); end
if nargin < 2, make_plots = true; end
raw = fullfile(P.data.dir, 'raw', 'nasa_power', ...
      sprintf('nasa_power_%.2fN_%.2fE_%d_UTC.csv', P.data.lat, P.data.lon, P.data.year));
assert(isfile(raw), 'raw file missing: run fetch_nasa_power first (%s)', raw);

% ---- 1 read ----
L = readlines(raw);
h = find(contains(L, '-END HEADER-'), 1);
hdr = strtrim(split(L(h + 1), ','));
D = L(h + 2:end); D = D(strlength(strtrim(D)) > 0);
M = str2double(split(D, ','));
c = @(name) M(:, strcmp(hdr, name));
fprintf('[1] read %d hourly rows, columns: %s\n', size(M, 1), strjoin(hdr, ', '));

% ---- 2 missing values ----
G = c("ALLSKY_SFC_SW_DWN"); Gc = c("CLRSKY_SFC_SW_DWN"); T = c("T2M"); W = c("WS2M");
X = [G Gc T W]; nmiss = sum(X <= -998, 1); X(X <= -998) = NaN;
X = fillmissing(X, 'linear', 'MaxGap', 3);           % fill gaps of up to 3 hours
X(:, 1:2) = max(X(:, 1:2), 0);
G = X(:,1); Gc = X(:,2); T = X(:,3); W = X(:,4);
fprintf('[2] missing values (-999) per column: %s; left after filling: %d\n', mat2str(nmiss), sum(isnan(X(:))));

% ---- 3 meaning of the hour stamp ----
tU = datetime(c("YEAR"), c("MO"), c("DY"), c("HR"), 0, 0);       % UTC, as written in the file
doy = day(tU, 'dayofyear'); hr = c("HR");
B = deg2rad(360 / 365 * (doy - 81));
EoT = 9.87 * sin(2*B) - 7.53 * cos(B) - 1.5 * sin(B);            % equation of time [min]
noonU = 12 - P.data.lon / 15 - EoT / 60;                         % solar noon in UTC hours
off = zeros(1, 2); dd = unique(floor(datenum(tU)));
for k = 1:2
    delta = [0 0.5]; cen = nan(numel(dd), 1); nn = cen;
    for j = 1:numel(dd)
        r = floor(datenum(tU)) == dd(j) & Gc > 0;
        if nnz(r) < 4, continue; end
        cen(j) = sum(Gc(r) .* (hr(r) + delta(k))) / sum(Gc(r)); nn(j) = mean(noonU(r));
    end
    off(k) = mean(cen - nn, 'omitnan') * 60;
end
[~, kbest] = min(abs(off)); shift = [0 0.5]; shift = shift(kbest);
fprintf(['[3] clear-sky centre minus solar noon: %+.0f min if HR were the middle of the hour, %+.0f min if HR is the start\n' ...
         '    -> the hour stamp is the %s of the hour; values are hourly MEANS in W/m2\n'], ...
         off(1), off(2), string(ifelse(kbest == 2, "START", "MIDDLE")));

% ---- 4 UTC -> IST, daily totals ----
t0 = tU + hours(P.data.tz_h);                    % IST, start of each hour (if kbest == 2)
tm = t0 + hours(shift);                          % IST, middle of the averaging hour
in = year(t0) == P.data.year;                    % keep the IST calendar year
day_ist = dateshift(t0, 'start', 'day');
[dd, ~, gi] = unique(day_ist(in));
H   = accumarray(gi, G(in))  / 1000;             % kWh/m2/day (hourly Wh/m2 summed)
Hc  = accumarray(gi, Gc(in)) / 1000;
Tav = accumarray(gi, T(in), [], @mean); Tmx = accumarray(gi, T(in), [], @max);
daily = table(dd, H, Hc, H ./ max(Hc, eps), Tav, Tmx, ...
    'VariableNames', {'date', 'H_kWh_m2', 'Hclear_kWh_m2', 'clear_index', 'T_mean', 'T_max'});
fprintf('[4] IST days: %d (%s .. %s); IST solar noon is about %.2f h\n', height(daily), ...
        string(dd(1), 'dd-MMM'), string(dd(end), 'dd-MMM'), mean(noonU) + P.data.tz_h);

% ---- 5 sanity checks ----
Hy = sum(H); y1 = zeros(nnz(in), 1); Gi = G(in); Ti = T(in);
for k = 1:numel(Gi), y1(k) = pv_power(1, Gi(k), Ti(k), P); end      % W per kWp, hourly mean
Yy = sum(y1) / 1000;                                                  % kWh per kWp per year
mo = month(t0(in)); Ym = accumarray(mo, y1) / 1000;
fprintf(['[5] yearly sunshine on a flat surface: %.0f kWh/m2 (%.2f kWh/m2/day on average)\n' ...
         '    our PV model: %.0f kWh per kWp per year (%.2f per day); performance ratio %.2f\n' ...
         '    best month %s %.0f kWh/kWp, worst month %s %.0f kWh/kWp\n'], ...
         Hy, Hy / height(daily), Yy, Yy / height(daily), Yy / Hy, ...
         month_name(find(Ym == max(Ym), 1)), max(Ym), month_name(find(Ym == min(Ym), 1)), min(Ym));

S = struct('source', "NASA POWER hourly (CERES SYN1deg irradiance, MERRA-2 temperature/wind)", ...
    'site', string(P.data.site), 'lat', P.data.lat, 'lon', P.data.lon, 'year', P.data.year, ...
    'raw_file', string(raw), 't_start_ist', t0(in), 't_mid_ist', tm(in), ...
    'G', G(in), 'G_clear', Gc(in), 'T2M', T(in), 'WS2M', W(in), 'daily', daily, ...
    'pv_W_per_kWp', y1, 'yield_kWh_per_kWp', Yy, 'monthly_kWh_per_kWp', Ym, ...
    'H_year_kWh_m2', Hy, 'hour_stamp', string(ifelse(kbest == 2, "start", "middle")), 'made', datetime('now'));
out = fullfile(P.data.dir, 'processed', P.data.solar_file);
save(out, '-struct', 'S'); fprintf('    saved %s\n', out);

if make_plots
    f = figure('Visible', 'off', 'Position', [50 50 1200 900], 'Color', 'w');
    tl = tiledlayout(f, 3, 1, 'TileSpacing', 'compact');
    title(tl, sprintf('%s %d - NASA POWER solar data (processed)', P.data.site, P.data.year), 'FontWeight', 'bold');
    ax = nexttile(tl); plot(ax, daily.date, daily.Hclear_kWh_m2, 'Color', [.6 .6 .6]); hold(ax, 'on');
    plot(ax, daily.date, daily.H_kWh_m2, 'Color', [0.85 0.45 0.05]); grid(ax, 'on');
    ylabel(ax, 'kWh/m^2/day'); legend(ax, 'clear sky', 'actual (all sky)', 'Location', 'southwest');
    title(ax, 'Daily sunshine: the monsoon (Jun-Sep) cuts it sharply');
    ax = nexttile(tl); hh = hour(tm(in)) + minute(tm(in)) / 60;
    Z = accumarray([floor(hh) + 1, mo], G(in), [24 12], @mean);
    imagesc(ax, 1:12, 0:23, Z); axis(ax, 'xy'); colormap(ax, hot); cb = colorbar(ax); cb.Label.String = 'mean W/m^2';
    xticks(ax, 1:12); xticklabels(ax, month_name(1:12)); ylabel(ax, 'hour of day (IST)');
    title(ax, 'Average sunshine by hour and month (solar noon ~12:30 IST)');
    ax = nexttile(tl); bar(ax, Ym, 'FaceColor', [0.2 0.55 0.2]); grid(ax, 'on');
    xticks(ax, 1:12); xticklabels(ax, month_name(1:12)); ylabel(ax, 'kWh per kWp');
    title(ax, sprintf('Our PV model: monthly energy per kWp (year total %.0f kWh/kWp)', Yy));
    fig = fullfile(fileparts(P.data.dir), 'results', 'figures', sprintf('data_solar_%d.png', P.data.year));
    exportgraphics(f, fig, 'Resolution', 110); close(f); fprintf('    figure %s\n', fig);
end
end

function m = month_name(k)
n = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]; m = n(k);
end

function v = ifelse(c, a, b)
if c, v = a; else, v = b; end
end
