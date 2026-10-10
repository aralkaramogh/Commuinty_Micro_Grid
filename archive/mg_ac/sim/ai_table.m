function T = ai_table(R, P, step_s, day_id)
% AI_TABLE  One run as a table in the AI/ML data-contract column names
% (docs/data_contract.md). One row every step_s seconds, one column per signal.
if nargin < 3, step_s = P.sim.dt; end
if nargin < 4, day_id = 0; end
L = R.L; n = P.n_house; idx = (1:round(step_s / P.sim.dt):numel(L.t)).';
modes = ["BOOT","GRID","ISLAND","RESYNC"];
t0 = datetime(2026, 10, 8) + hours(R.sc.t0_h) + days(day_id);
T = table();
T.day_id = repmat(day_id, numel(idx), 1);
T.timestamp = string(t0 + seconds(L.t(idx)), 'yyyy-MM-dd''T''HH:mm:ss');
T.irradiance_wm2 = R.L_G(idx);
T.mode = modes(L.mode(idx) + 1).';
T.grid_available = double(L.grid_V_pu(idx) >= P.grid.V_dead);
T.grid_voltage_v = L.v_grid(idx); T.grid_frequency_hz = L.f_grid(idx);
T.grid_p_w = L.p_pcc(idx); T.grid_q_var = L.q_pcc(idx);
T.grid_breaker_closed = double(bitand(L.bits(idx), 1) > 0);
T.bus_voltage_v = L.v_c(idx); T.bus_frequency_hz = L.f_mg(idx);
T.bess_soc_pct = 100 * L.soc(idx); T.bess_p_w = L.p_bess(idx); T.bess_q_var = L.q_bess(idx);
T.bess_fault = L.bess_trip(idx);
T.comm_load_p_w = L.p_cl(idx); T.comm_load_q_var = L.q_cl(idx); T.comm_pv_p_w = L.p_cpv(idx);
T.price_rs_kwh = L.price(idx); T.ai_status = L.ai_status(idx);
pnet = L.p_pv - L.p_load;              % + = exporting
imp = cumsum(max(-pnet, 0)) * P.sim.dt / 3600; ex = cumsum(max(pnet, 0)) * P.sim.dt / 3600;
for k = 1:n
    h = lower(P.house(k).id);
    T.([h '_voltage_v'])   = L.v_h(idx, k);
    T.([h '_current_a'])   = L.i_h(idx, k);
    T.([h '_load_p_w'])    = L.p_load_meas(idx, k);     % as measured (may be a faulty sensor)
    T.([h '_load_q_var'])  = L.q_load(idx, k);
    T.([h '_pv_p_w'])      = L.p_pv(idx, k);
    T.([h '_pv_q_var'])    = L.q_pv(idx, k);
    T.([h '_net_p_w'])     = pnet(idx, k);
    T.([h '_import_wh'])   = imp(idx, k);
    T.([h '_export_wh'])   = ex(idx, k);
    T.([h '_balance_rs'])  = L.bal(idx, k);
    T.([h '_critical_on']) = L.tie(idx, k);
    T.([h '_flexible_on']) = L.flex(idx, k);
    T.([h '_status_code']) = L.hcode(idx, k);
end
% ground-truth labels (for training and scoring; the hub never sees these)
T.label_grid_outage = double(L.grid_V_pu(idx) < P.grid.V_dead);
T.label_grid_abnormal = double(abs(L.grid_V_pu(idx) - 1) > 0.10 | abs(L.grid_f_true(idx) - P.ac.f_nom) > 0.5);
T.label_frozen_sensor_house = R.lab.frozen(idx);
T.label_abnormal_load_house = R.lab.abnormal(idx);
T.label_card_abuse_house = R.lab.card(idx);
end
