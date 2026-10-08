function sc = base_scenario_h(P, name)
% BASE_SCENARIO_H  Default scenario; define_scenarios_h overrides fields.
sc.name = name;
sc.t0_h = 0;  sc.dur_s = 3600;  sc.soc0 = P.bess.soc_init;
sc.pv_gain = 1;  sc.cloud_fn = @(t) 1;  sc.irr_hourly = [];
sc.load_gain = ones(1, P.n_load);          % houses ..., community pump
sc.grid_fn = @(t) [1 P.ac.f_nom];          % [V_pu, f_Hz]
sc.faults = struct('house', {}, 'R', {}, 't_on', {}, 't_off', {});
sc.cards = zeros(0, 3);                    % rows [t_s, house, uid] (tapped on that house node)
sc.ai_fn = @(t) ai_cmd();                  % AI service requests (via the Pi)
sc.cmds = struct('t', {}, 'sender', {}, 'topic', {}, 'payload', {});   % dashboard requests (pi_cmd)
sc.link_drops = struct('node', {}, 't_on', {}, 't_off', {});          % node link down (both ways)
sc.events = zeros(0, 2);                   % [t_start t_end] of grid disturbances (for KPIs)
sc.seed = 1; sc.noise_P = 0; sc.noise_V = 0;
sc.sensor_faults = struct('house', {}, 't_on', {}, 't_off', {});   % frozen load sensor
end
