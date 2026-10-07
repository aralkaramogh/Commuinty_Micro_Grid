function [P_lo, P_hi] = bess_limits(soc, P)
% BESS_LIMITS  Allowed BESS active power [W] (+ discharge, - charge) at this SOC.
b = P.bess;
P_hi = b.P_dis_max * (soc > b.soc_cutoff);
P_lo = -b.P_ch_max * min(1, max(0, (1 - soc) / b.soc_taper));
end
