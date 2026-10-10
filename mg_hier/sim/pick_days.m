function D = pick_days(P)
% PICK_DAYS  Representative days from the real data year (see data/README.md).
% Simulating 365 days at 1-second steps would take many hours, so we test a few
% days chosen by rule (not by hand), each standing for a situation that matters.
S = load(fullfile(P.data.dir, 'processed', P.data.solar_file), 'daily');
d = S.daily; m = month(d.date); H = d.H_kWh_m2;
lab = strings(0, 1); dt = NaT(0, 1); reason = strings(0, 1);
    function add(l, mask, pickfn, w)
        idx = find(mask); [~, j] = pickfn(H(idx)); lab(end+1) = l; dt(end+1) = d.date(idx(j)); reason(end+1) = w;
    end
add("sunniest",       m >= 3 & m <= 5,  @max,        "most sun in the dry season (Mar-May)");
add("average",        true(size(H)),    @(x) min(abs(x - mean(H))), "sunshine closest to the year's average");
add("winter",         m == 12 | m <= 1, @(x) min(abs(x - median(x))), "typical Dec/Jan day (short days)");
add("monsoon_typical", m >= 7 & m <= 8, @(x) min(abs(x - median(x))), "typical Jul/Aug monsoon day");
add("darkest",        m >= 6 & m <= 9,  @min,        "least sun of the monsoon (worst case for the battery)");
% three gloomiest days in a row: the battery cannot catch up
H3 = movsum(H, [0 2]); H3(end-1:end) = inf; [~, j3] = min(H3);
lab(end+1) = "gloomy_3day_start"; dt(end+1) = d.date(j3); reason(end+1) = "start of the 3 darkest days in a row";
k = arrayfun(@(x) find(d.date == x, 1), dt(:));
D = table(lab(:), dt(:), H(k), d.clear_index(k), reason(:), ...
    'VariableNames', {'label', 'date', 'sun_kWh_m2', 'clear_index', 'reason'});
end
