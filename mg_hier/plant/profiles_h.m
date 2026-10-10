function ext = profiles_h(t_s, P, sc)
% PROFILES_H  External inputs at time t_s for scenario sc: irradiance,
% temperature, load demand factors (houses + community pump), grid voltage and
% frequency, faults, RFID card taps. (Dashboard/AI commands are NOT here: they
% reach the main controller through the Pi inbox, see sim/run_hier.m.)
h = mod(sc.t0_h + t_s / 3600, 24);
if isfield(sc, 'hour_fn'), h = mod(h + sc.hour_fn(t_s), 24); end   % live: clock jumped by the panel
G = 0;
if ~isempty(sc.irr_hourly)                       % measured data (e.g. PVGIS / NASA POWER)
    G = interp1(0:24, [sc.irr_hourly(:); sc.irr_hourly(1)].', h);
elseif h > 6 && h < 18
    G = P.pv.G_max * sin(pi * (h - 6) / 12)^1.2;
end
ext.G = G * sc.cloud_fn(t_s) * sc.pv_gain;
ext.T_amb = P.pv.T_amb_mean + P.pv.T_amb_swing * sin(pi * (h - 9) / 12);
if isfield(sc, 'G_fn') && ~isempty(sc.G_fn)      % real data (sim/real_day_scenario.m): measured sun + temperature
    ext.G = sc.G_fn(t_s) * sc.cloud_fn(t_s) * sc.pv_gain;
    ext.T_amb = sc.T_fn(t_s);
end
n = P.n_house;
ext.d_crit = (0.6 + 0.4 * (h >= 18 && h < 23)) * ones(1, n);   % evening lights
ext.d_flex = zeros(1, n);
gain = sc.load_gain; if isfield(sc, 'load_gain_fn'), gain = sc.load_gain_fn(t_s); end   % live knob
for k = 1:n      % load_gain > 1 = more appliances than usual (overload tests)
    ext.d_flex(k) = demand_shape(P.house(k).profile, h) * gain(k);
end
if isfield(sc, 'house_W_fn') && ~isempty(sc.house_W_fn)   % real household demand [W] (sim/real_day_scenario.m)
    Dw = sc.house_W_fn(t_s) .* gain(1:n);
    for k = 1:n      % split [assumed]: the first P_crit watts are essentials (fridge, lights), the rest is flexible
        crit = min(Dw(k), P.house(k).P_crit);
        ext.d_crit(k) = crit / P.house(k).P_crit;
        ext.d_flex(k) = max(Dw(k) - crit, 0) / P.house(k).P_flex;
    end
end
ext.d_comm = 1;                                                  % street lights + hall
ext.d_cflex = demand_shape(P.comm.profile, h) * gain(n + 1);   % water pump
g = sc.grid_fn(t_s);                 % [V_pu, f_Hz] of the utility grid
ext.grid_V_pu = g(1); ext.grid_f = g(2);
ext.R_fault = zeros(1, n);
for f = 1:numel(sc.faults)
    F = sc.faults(f);
    if t_s >= F.t_on && t_s < F.t_off, ext.R_fault(F.house) = F.R; end
end
if isfield(sc, 'fault_fn'), ext.R_fault = sc.fault_fn(t_s); end                    % live knob
ext.card_house = 0; ext.card_uid = 0;
for c = 1:size(sc.cards, 1)
    if abs(t_s - sc.cards(c,1)) < 0.5 * P.sim.dt
        ext.card_house = sc.cards(c,2); ext.card_uid = sc.cards(c,3);
    end
end
if isfield(sc, 'card_fn')                                                           % live card tap
    c = sc.card_fn(t_s); if c(1) > 0, ext.card_house = c(1); ext.card_uid = c(2); end
end
end

function d = demand_shape(name, h)
% Hourly flexible-load demand factor 0..1.
switch name
    case 'office'
        s = [0 0 0 0 0 0 .2 .4 .6 .8 .8 .8 .6 .8 .8 .8 .6 .4 .6 .8 .6 .4 .2 0];
    case 'pump'     % solar water pumping: morning and midday, off in the evening
        s = [0 0 0 0 0 0 .6 .8 .6 .3 .5 .8 1 1 .8 .4 0 0 0 0 0 0 0 0];
    otherwise   % 'family': morning and evening peaks
        s = [.1 .1 .1 .1 .1 .2 .6 .8 .5 .3 .3 .4 .4 .3 .3 .4 .6 .8 1 1 .9 .7 .4 .2];
end
i0 = floor(h) + 1; i1 = mod(i0, 24) + 1; fr = h - floor(h);
d = s(i0) * (1 - fr) + s(i1) * fr;
end
