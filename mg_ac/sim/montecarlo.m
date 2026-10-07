function T = montecarlo(P, N, out_dir)
% MONTECARLO  N random evenings (see mc_scenario). Uses parfor if a pool is open.
if nargin < 3, out_dir = ''; end
pass = false(N,1); fails = strings(N,1); soc0 = zeros(N,1); n_ev = zeros(N,1);
vmin = zeros(N,1); vmax = zeros(N,1); fmin = zeros(N,1); fmax = zeros(N,1);
cang = zeros(N,1); socmin = zeros(N,1); crit = zeros(N,1); rec = zeros(N,1);
parfor i = 1:N
    [sc, Pp] = mc_scenario(P, i);
    R = run_scenario(sc, P, struct('P_plant', Pp));
    [ok, msg] = check_scenario(R, P); K = R.kpi;
    pass(i) = ok; fails(i) = strjoin(string(msg), '; ');
    soc0(i) = sc.soc0; n_ev(i) = size(sc.events, 1);
    vmin(i) = K.V_min_pu; vmax(i) = K.V_max_pu; fmin(i) = K.f_min; fmax(i) = K.f_max;
    cang(i) = K.close_angle_max; socmin(i) = K.soc_min; crit(i) = min(K.crit_served);
    rec(i) = max(K.reconnect_delay);
end
run = (1:N)';
T = table(run, pass, soc0, n_ev, vmin, vmax, fmin, fmax, cang, socmin, crit, rec, fails, ...
    'VariableNames', {'run','pass','soc0','grid_events','V_min_pu','V_max_pu','f_min','f_max', ...
    'close_angle_max','soc_min','crit_served_min','reconnect_delay_max','failed_rules'});
if ~isempty(out_dir), writetable(T, fullfile(out_dir, 'montecarlo.csv')); end
end
