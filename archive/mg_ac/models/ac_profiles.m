function ext = ac_profiles(t_s, P, sc)
% AC_PROFILES  External inputs at time t_s for scenario sc: irradiance,
% temperature, load demand factors, grid voltage/frequency, faults, cards,
% and the optional AI advisor command.
h = mod(sc.t0_h + t_s / 3600, 24);
G = 0;
if ~isempty(sc.irr_hourly)                       % measured data (e.g. PVGIS / NASA POWER)
    G = interp1(0:24, [sc.irr_hourly(:); sc.irr_hourly(1)].', h);
elseif h > 6 && h < 18
    G = P.pv.G_max * sin(pi * (h - 6) / 12)^1.2;
end
ext.G = G * sc.cloud_fn(t_s) * sc.pv_gain;
ext.T_amb = P.pv.T_amb_mean + P.pv.T_amb_swing * sin(pi * (h - 9) / 12);
n = P.n_house;
ext.d_crit = (0.6 + 0.4 * (h >= 18 && h < 23)) * ones(1, n);   % evening lights
ext.d_flex = zeros(1, n);
for k = 1:n
    ext.d_flex(k) = min(1, demand_shape(P.house(k).profile, h) * sc.load_gain(k));
end
ext.d_comm = 1;
g = sc.grid_fn(t_s);                 % [V_pu, f_Hz] of the utility grid
ext.grid_V_pu = g(1); ext.grid_f = g(2);
ext.R_fault = zeros(1, n);
for f = 1:numel(sc.faults)
    F = sc.faults(f);
    if t_s >= F.t_on && t_s < F.t_off, ext.R_fault(F.house) = F.R; end
end
ext.card_house = 0; ext.card_uid = 0;
for c = 1:size(sc.cards, 1)
    if abs(t_s - sc.cards(c,1)) < 0.5 * P.sim.dt
        ext.card_house = sc.cards(c,2); ext.card_uid = sc.cards(c,3);
    end
end
ext.ai = sc.ai_fn(t_s);       % struct valid, p_bess, shed_mask, price
end

function d = demand_shape(name, h)
% Hourly flexible-load demand factor 0..1.
switch name
    case 'office'
        s = [0 0 0 0 0 0 .2 .4 .6 .8 .8 .8 .6 .8 .8 .8 .6 .4 .6 .8 .6 .4 .2 0];
    otherwise   % 'family': morning and evening peaks
        s = [.1 .1 .1 .1 .1 .2 .6 .8 .5 .3 .3 .4 .4 .3 .3 .4 .6 .8 1 1 .9 .7 .4 .2];
end
i0 = floor(h) + 1; i1 = mod(i0, 24) + 1; fr = h - floor(h);
d = s(i0) * (1 - fr) + s(i1) * fr;
end
