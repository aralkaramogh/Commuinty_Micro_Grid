function P_W = pv_power(kWp, G, T_amb, P)
% PV_POWER  AC power [W] a PV inverter can deliver (before any curtailment).
%   kWp module rating, G irradiance [W/m2], T_amb [degC].
if kWp <= 0 || G <= 0, P_W = 0; return; end
Tc  = T_amb + (P.pv.NOCT - 20) / 800 * G;               % cell temperature
P_W = kWp * 1000 * (G / 1000) * (1 + P.pv.gamma * (Tc - 25)) * P.pv.derate;
P_W = max(P_W, 0);
end
