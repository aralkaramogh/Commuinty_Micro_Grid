function T = etap_benchmark(P)
% ETAP_BENCHMARK  Reference answers for the ETAP model, computed with OUR solver
% (plant/net_solve.m) at fixed operating points, so ETAP's load flow can be
% compared number by number. Writes docs/etap/benchmark_cases.csv.
% The ETAP model is the "per-phase equivalent": a balanced 3-phase 400 V system
% whose every phase equals our single-phase 230 V system. So ohms stay the same,
% voltages in per unit stay the same, and every power is 3x ours.
%   Case A  noon, grid-connected: full sun (1000 W/m2, 30 C), all loads on, battery idle
%   Case B  evening, grid-connected: no sun, all loads on, battery discharging 3 kW
%   Case C  evening, islanded: no sun, all loads on, battery inverter holds 230 V (swing)
% Simplifications (state them in ETAP too): PV at unity power factor (no volt-var),
% loads constant-power, island voltage fixed at 1.00 pu (our droop is left out).
if nargin < 1, P = hier_params(); end
H = P.house; n = P.n_house; V0 = P.ac.V_nom;
q = @(p, pf) p * tan(acos(pf));
Sload = zeros(1, n);
for k = 1:n
    Sload(k) = H(k).P_crit + 1i*q(H(k).P_crit, H(k).pf_crit) + H(k).P_flex + 1i*q(H(k).P_flex, H(k).pf_flex);
end
Scl = P.comm.P_crit + 1i*q(P.comm.P_crit, P.comm.pf_crit) + P.comm.P_flex + 1i*q(P.comm.P_flex, P.comm.pf_flex);
pv1 = pv_power(1, 1000, 30, P);                       % W per kWp at 1000 W/m2, 30 C
cases = {'A_noon_grid', 'B_evening_grid', 'C_evening_island'};
pvon = [1 0 0]; pbess = [0 3000 NaN]; mode = {'grid', 'grid', 'island'};
rows = {};
for c = 1:3
    Ppv_h = [H.pv_kWp] * pv1 * pvon(c); Ppv_c = P.comm.pv_kWp * pv1 * pvon(c);
    Sh = Sload - Ppv_h;
    if strcmp(mode{c}, 'grid')
        Sc = Scl - Ppv_c - pbess(c);
        [Vc, Vh, Ih, Ic] = net_solve('grid', V0, P.grid.Z_th, Sh, zeros(1,n), [H.Z_line], Sc);
        Ssrc = Vc * conj(Ic);   % into the community bus from the grid
        src = 'grid (PCC)';
    else
        Sc = Scl - Ppv_c;
        [Vc, Vh, Ih, Ic] = net_solve('island', V0, 0, Sh, zeros(1,n), [H.Z_line], Sc);
        Ssrc = Vc * conj(Ic);   % supplied by the battery inverter
        src = 'battery inverter';
    end
    Vg_pcc = abs(V0); 
    rows(end+1, :) = {cases{c}, 'community bus', abs(Vc), abs(Vc)/V0, rad2deg(angle(Vc)), NaN, NaN}; %#ok<AGROW>
    for k = 1:n
        rows(end+1, :) = {cases{c}, [H(k).id ' bus'], abs(Vh(k)), abs(Vh(k))/V0, rad2deg(angle(Vh(k))), ...
                          3*real(Sh(k))/1000, 3*imag(Sh(k))/1000}; %#ok<AGROW>
    end
    rows(end+1, :) = {cases{c}, ['source: ' src], NaN, NaN, NaN, 3*real(Ssrc)/1000, 3*imag(Ssrc)/1000}; %#ok<AGROW>
    fprintf('%s: Vbus %.2f V (%.4f pu), V_H1 %.4f pu, V_H2 %.4f pu, source P %.3f kW Q %.3f kvar (3-phase)\n', ...
        cases{c}, abs(Vc), abs(Vc)/V0, abs(Vh(1))/V0, abs(Vh(2))/V0, 3*real(Ssrc)/1000, 3*imag(Ssrc)/1000);
    if c == 1, Vg_pcc = Vg_pcc; end %#ok<ASGSELF>
end
T = cell2table(rows, 'VariableNames', {'case', 'element', 'V_LN_volt', 'V_pu', 'angle_deg', 'P_3ph_kW', 'Q_3ph_kvar'});
% bolted 3-phase fault currents with the grid only (sanity check for ETAP short circuit)
Zth = P.grid.Z_th; Isc = [V0/abs(Zth), V0./abs(Zth + [H.Z_line])];
fprintf('3-phase bolted fault, grid only (no inverter contribution): community bus %.0f A, H1 %.0f A, H2 %.0f A\n', Isc);
T.Properties.Description = sprintf('PV %.0f W per kWp at 1000 W/m2, 30 C', pv1);
out = fullfile(fileparts(fileparts(fileparts(mfilename('fullpath')))), 'docs', 'etap', 'benchmark_cases.csv');
writetable(T, out); fprintf('PV output used: %.0f W per kWp. Saved %s\n', pv1, out);
end
