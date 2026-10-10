function sc = real_day_scenario(P, day, t0_h, dur_s)
% REAL_DAY_SCENARIO  Scenario driven by MEASURED data for one calendar day.
%   sc = real_day_scenario(P, datetime(2025,8,12))            whole day 00:00-24:00
%   sc = real_day_scenario(P, datetime(2025,8,12), 6, 17*3600) 06:00-23:00
% Sun + temperature: NASA POWER hourly means (data/processed/solar_*.mat),
% placed at the middle of each hour and joined by straight lines, so the
% 1-second plant sees a smooth curve. Hourly data has no fast cloud flicker;
% sc.cloud_fn can still add it. Loads: synthetic shapes until the eMARC
% household data is processed (then sc.house_W_fn is set here as well).
% Everything else (grid, faults, cards...) is the same as base_scenario_h,
% so outages etc. are added by the caller exactly as in define_scenarios_h.
if nargin < 3, t0_h = 0; end
if nargin < 4, dur_s = 24 * 3600 - t0_h * 3600; end
persistent S file E efile
f = fullfile(P.data.dir, 'processed', P.data.solar_file);
if isempty(S) || ~strcmp(file, f), S = load(f); file = f; end
day = dateshift(datetime(day), 'start', 'day');
sc = base_scenario_h(P, char("REAL_" + string(day, 'yyyy-MM-dd')));
sc.t0_h = t0_h; sc.dur_s = dur_s; sc.day = day;
% hour-centre points from the day before to the day after (smooth at midnight)
th = hours(S.t_mid_ist - day);                          % hours since 00:00 of 'day'
r = th > -2 & th < 26 + dur_s / 3600;
assert(nnz(r) >= 20, 'no solar data for %s', string(day));
tx = th(r); G = S.G(r); T = S.T2M(r);
sc.G_fn = @(t) max(0, interp1(tx, G, t0_h + t / 3600, 'linear', 0));
sc.T_fn = @(t) interp1(tx, T, t0_h + t / 3600, 'linear', 'extrap');
% ---- household loads from eMARC (if processed) ----
lf = fullfile(P.data.dir, 'processed', P.data.load_file);
sc.load_note = 'synthetic house loads';
if isfile(lf)
    if isempty(E) || ~strcmp(efile, lf), E = load(lf); efile = lf; end
    m = month(day); s_i = 4; if m >= 3 && m <= 5, s_i = 1; elseif m >= 6 && m <= 9, s_i = 2; elseif m >= 10 && m <= 11, s_i = 3; end
    w_i = 1 + isweekend(day);
    n = P.n_house; prof = zeros(n, 96); src = strings(1, n);
    rs = RandStream('mt19937ar', 'Seed', 100 * s_i + w_i);           % same choice every run (reproducible)
    lm = month(E.lib_day); lsea = 4 * ones(size(lm)); lsea(lm >= 3 & lm <= 5) = 1; lsea(lm >= 6 & lm <= 9) = 2; lsea(lm >= 10 & lm <= 11) = 3;
    pool = find(lsea == s_i & isweekend(E.lib_day) == (w_i == 2));
    for h = 1:n
        Ed = P.data.house_kWh_month(min(h, end)) / 30;
        if isnan(Ed), Ed = E.E_season_kWh(s_i); end
        if strcmp(P.data.load_mode, 'typical')
            prof(h, :) = squeeze(E.shape(s_i, w_i, :))' * Ed; src(h) = "typical shape";
        else
            j = pool(randi(rs, numel(pool)));
            prof(h, :) = double(E.lib_kW_norm(j, :)) * Ed;
            src(h) = sprintf('home %s on %s', E.lib_dep(j), string(E.lib_day(j), 'dd-MMM-yyyy'));
        end
    end
    tb = ((-1:96) + 0.5) / 4;                                          % block centres, wrapped at midnight
    Pw = 1000 * [prof(:, end), prof, prof(:, 1)];                      % kW -> W
    sc.house_W_fn = @(t) interp1(tb, Pw.', mod(t0_h + t / 3600, 24)).';
    sc.house_kWh_day = sum(prof, 2).' * 0.25;
    sc.load_note = sprintf('eMARC %s, %s %s: %s', P.data.load_mode, E.seasons(s_i), E.daytypes(w_i), strjoin(src, '; '));
end
k = find(S.daily.date == day, 1);
sc.info = sprintf('%s: sun %.2f kWh/m2 (clear-sky index %.2f), T max %.1f C', ...
    string(day, 'dd-MMM-yyyy'), S.daily.H_kWh_m2(k), S.daily.clear_index(k), S.daily.T_max(k));
end
