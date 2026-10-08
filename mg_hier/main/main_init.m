function st = main_init(P)
% MAIN_INIT  Main controller state at power-up. Every switch OFF (nodes keep
% their loads off until the first "enable").
n = P.n_house; nL = P.n_load; S = main_inputs_spec();
st.tick = 0; st.mode = 0;              % 0 BOOT, 1 GRID, 2 ISLAND, 3 RESYNC
st.n_good = 0; st.n_bad = 0;
st.n_island = 0; st.n_reconnect = 0;
z = cell2struct(num2cell(zeros(1, numel(S.load))), S.load, 2);
st.rep = repmat(z, 1, nL); st.n_stale = zeros(1, nL);      % last good report per load node
z = cell2struct(num2cell(zeros(1, numel(S.sb))), S.sb, 2);
st.sb = z; st.n_stale_sb = 0;
st.shed_soc = zeros(1,nL); st.shed_uf = zeros(1,nL); st.shed_ai = zeros(1,nL);
st.op_until = zeros(1,nL); st.user_until = zeros(1,nL);
st.uf_hold = 0; st.uf_wait = 0;
st.bal = [P.house.credit0]; st.credit_ok = double(st.bal > 0);
st.e_imp0 = nan(1,n); st.e_exp0 = nan(1,n);               % last billed meter counters
st.bad = zeros(1,n); st.card_lock = zeros(1,n);
st.price = P.ctrl.price_default;
st.ai_active = 0; st.ai_age = 0; st.ai_p = 0;
st.ids = nan(1, P.ctrl.N_ids); st.id_ptr = 0;                % recently seen command ids
st.p2p = zeros(n + 1, n);                                   % [Wh] sold by (H1..Hn, C) to house j
st.prev_hstate = zeros(1,nL); st.sb_estop = 0;
end
