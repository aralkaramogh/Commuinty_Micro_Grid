function ps = plant_init(P, soc0)
% PLANT_INIT  AC plant state at power-up: breaker open, every switch OFF,
% BESS inverter healthy and forming the community bus voltage.
ps.soc = soc0;
ps.dtheta = 0;              % [deg] microgrid phase minus grid phase
ps.bess_trip = false;
ps.ovl_t = 0;
ps.Vh_prev = P.ac.V_nom * ones(1, P.n_house);   % for the volt-var response
ps.breaker_prev = 0;
ps.prev_energised = false; ps.prev_Vc = 0; ps.prev_f = 0;
end
