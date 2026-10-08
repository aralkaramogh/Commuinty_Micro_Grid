function q_pu = volt_var(V, P)
% VOLT_VAR  Reactive power of a house PV inverter [pu of its VA] for terminal
% voltage V [V]. + = injects vars (pushes voltage up), - = absorbs (pulls down).
q_pu = interp1(P.pv.vv_V, P.pv.vv_Q, min(max(V / P.ac.V_nom, P.pv.vv_V(1)), P.pv.vv_V(end)));
end
