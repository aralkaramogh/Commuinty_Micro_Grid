function [Vc, Vh, Ih, Ic, ok] = net_solve(mode, Vsrc, Zth, Sh, Yh, Zh, Sc)
% NET_SOLVE  Phasor power flow of the radial microgrid (backward/forward sweep).
%   mode 'grid'  : Vsrc = grid voltage phasor behind Zth (Thevenin source)
%   mode 'island': Vsrc = community-bus voltage phasor set by the BESS inverter
%   Sh(k) house net complex power drawn [VA] (load - PV), constant-power
%   Yh(k) house shunt admittance [S] (used for a fault resistor), Zh(k) cable
%   Sc    community-bus net complex power drawn [VA] (load - PV - BESS in grid mode)
% Returns phasors: Vc community bus, Vh houses, Ih house currents (drawn),
% Ic current drawn from the source (grid through Zth, or the BESS in island).
n = numel(Sh); Vc = Vsrc; Vh = Vsrc * ones(1, n); ok = false;
for it = 1:100
    Ih  = conj(Sh ./ Vh) + Yh .* Vh;          % house currents at present voltages
    Ic  = sum(Ih) + conj(Sc / Vc);            % backward sweep: all currents
    if strcmp(mode, 'grid')
        Vc_new = Vsrc - Zth * Ic;             % forward sweep
    else
        Vc_new = Vsrc;
    end
    Vh_new = Vc_new - Zh .* Ih;
    err = max(abs([Vh_new - Vh, Vc_new - Vc]));
    Vc = Vc_new; Vh = Vh_new;
    if err < 1e-9, ok = true; break; end
end
Ih = conj(Sh ./ Vh) + Yh .* Vh;
Ic = sum(Ih) + conj(Sc / Vc);
end
