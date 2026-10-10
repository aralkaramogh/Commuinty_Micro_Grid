function st = ac_controller_init(P)
% AC_CONTROLLER_INIT  Controller state at power-up (MATLAB twin of
% firmware/src/controller.cpp). Every switch OFF.
n = P.n_house;
st.tick = 0; st.mode = 0;              % 0 BOOT, 1 GRID, 2 ISLAND, 3 RESYNC
st.n_good = 0; st.n_bad = 0; st.last_bits = 0;
st.n_island = 0; st.n_reconnect = 0;
st.hstate = zeros(1,n); st.n_oc = zeros(1,n); st.strikes = zeros(1,n);
st.n_healthy = zeros(1,n); st.retry = zeros(1,n);
st.shed_soc = zeros(1,n); st.shed_uf = zeros(1,n); st.shed_ai = zeros(1,n);
st.uf_hold = 0;
st.bal = [P.house.credit0]; st.credit_ok = double(st.bal > 0);
st.bad = zeros(1,n); st.card_lock = zeros(1,n);
st.price = P.ctrl.price_default;
st.ai_active = 0; st.ai_age = 0; st.ai_p = 0;
end
