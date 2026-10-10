function [st, o] = ac_controller_step(st, m, P)
% AC_CONTROLLER_STEP  One controller tick. MATLAB twin of
% firmware/src/controller.cpp (tools/run_sil.sh checks they agree exactly).
%   m: decoded measurement frame (comms/proto_decode_meas)
%   o: relay bits, mode, BESS set-points, flags, AI status, price, per-house data
C = P.ctrl; n = P.n_house; dt = P.sim.dt; H = P.house; V0 = P.ac.V_nom; b = P.bess;
st.tick = st.tick + 1;

% ---------- grid health ----------
vg = m.v_grid / V0;
grid_ok   = vg >= C.V_ok_lo && vg <= C.V_ok_hi && m.f_grid >= C.F_ok_lo && m.f_grid <= C.F_ok_hi;
grid_lost = vg < C.V_lost;
if grid_ok
    st.n_good = st.n_good + 1; st.n_bad = 0;
else
    st.n_bad = st.n_bad + 1; st.n_good = 0;
end
mismatch = (st.tick > 1) && (m.fb ~= st.last_bits);
soc = m.soc;
bess_fault = m.bess_status ~= 0;

% ---------- operating mode ----------
switch st.mode
    case 0   % BOOT: all off. The BESS already forms the community bus, so the
             % microgrid is live: it always starts islanded and joins the grid
             % only through synchronisation (never closes onto a live bus blindly)
        if st.tick > C.N_boot, st.mode = 2; end
    case 1   % GRID
        if grid_lost || st.n_bad >= C.N_abn
            st.mode = 2; st.n_island = st.n_island + 1;
        end
    case 2   % ISLAND
        if st.n_good >= C.N_grid_stable, st.mode = 3; end
    case 3   % RESYNC: BESS slips slowly; close when V, f and phase all match
        if ~grid_ok
            st.mode = 2;
        elseif m.v_c < C.V_lost * V0
            st.mode = 1; st.n_reconnect = st.n_reconnect + 1;   % dead-bus closing: nothing to synchronise with
        else
            pred = wrap180(m.dtheta + 360 * (m.f_mg - m.f_grid) * dt);   % angle at closing
            if abs(m.v_grid - m.v_c) <= C.DV_sync && abs(m.f_mg - m.f_grid) <= C.DF_sync ...
                    && abs(pred) <= C.DTH_sync
                st.mode = 1; st.n_reconnect = st.n_reconnect + 1;
            end
        end
end
booted = st.mode ~= 0;
island = st.mode == 2 || st.mode == 3;
gridm  = st.mode == 1;

% ---------- AI advisor command (optional; the rules keep the final say) ----------
ai_status = 0;
if m.ai_valid ~= 0
    st.ai_active = 1; st.ai_age = 0; st.ai_p = m.ai_p;
    for k = 1:n, st.shed_ai(k) = double(bitand(m.ai_mask, 2^(k-1)) > 0); end
    if m.ai_price >= C.price_min && m.ai_price <= C.price_max
        st.price = m.ai_price;
    else
        ai_status = ai_status + 4;                 % price refused
    end
elseif st.ai_active
    st.ai_age = st.ai_age + dt;
    if st.ai_age > C.T_ai_timeout                  % AI silent: fall back to rules
        st.ai_active = 0; st.shed_ai = zeros(1,n); st.price = C.price_default;
    end
end
if st.ai_active, ai_status = ai_status + 1; end

% ---------- RFID cards ----------
for k = 1:n
    if st.card_lock(k) > 0, st.card_lock(k) = st.card_lock(k) - 1; end
end
if m.card_uid ~= 0 && m.card_house >= 1 && m.card_house <= n
    k = m.card_house;
    if st.card_lock(k) > 0
        % locked: ignore
    elseif m.card_uid == H(k).card_uid
        st.bal(k) = st.bal(k) + C.card_topup; st.bad(k) = 0;
    else
        st.bad(k) = st.bad(k) + 1;
        if st.bad(k) >= C.card_bad_max, st.card_lock(k) = C.N_card_lock; st.bad(k) = 0; end
    end
end

% ---------- island under-frequency load shedding (one house per tick) ----------
if island
    if m.f_mg > 0 && m.f_mg < C.F_ufls
        for k = n:-1:1                               % lowest priority = highest index
            if st.shed_uf(k) == 0, st.shed_uf(k) = 1; break; end
        end
        st.uf_hold = C.T_uf_hold;
    elseif st.uf_hold > 0
        st.uf_hold = st.uf_hold - dt;
    else
        for k = 1:n                                  % restore highest priority first
            if st.shed_uf(k) == 1
                if m.p_bess + H(k).P_flex <= C.UF_restore * b.P_dis_max
                    st.shed_uf(k) = 0; st.uf_hold = C.T_uf_step;
                end
                break;
            end
        end
    end
else
    st.shed_uf = zeros(1,n); st.uf_hold = 0;
end

% ---------- per house ----------
bits = 0; any_locked = 0; any_shed = 0; any_card = 0;
o.bal = zeros(1,n); o.hcode = zeros(1,n);
for k = 1:n
    tie_fb = bitand(m.fb, 2^(2 + 2*(k-1))) > 0;
    % over-current protection: trip, retry, lock after repeated trips
    if st.hstate(k) == 0
        if tie_fb && m.i_h(k) > C.I_trip, st.n_oc(k) = st.n_oc(k) + 1; else, st.n_oc(k) = 0; end
        if st.n_oc(k) >= C.N_oc
            st.strikes(k) = st.strikes(k) + 1; st.n_oc(k) = 0; st.n_healthy(k) = 0;
            if st.strikes(k) >= C.strikes_max
                st.hstate(k) = 2;
            else
                st.hstate(k) = 1; st.retry(k) = C.N_retry;
            end
        else
            st.n_healthy(k) = st.n_healthy(k) + 1;
            if st.n_healthy(k) >= C.N_strike_clear, st.strikes(k) = 0; end
        end
    elseif st.hstate(k) == 1
        st.retry(k) = st.retry(k) - 1;
        if st.retry(k) <= 0, st.hstate(k) = 0; st.n_healthy(k) = 0; end
    end
    % island battery-priority shedding (critical loads are never shed)
    if island
        if soc < H(k).shed_soc
            st.shed_soc(k) = 1;
        elseif soc > H(k).shed_soc + C.soc_hyst
            st.shed_soc(k) = 0;
        end
    else
        st.shed_soc(k) = 0;
    end
    % prepaid account [Rs]: buy at price, sell at price x sell_ratio
    p_net = m.p_load(k) - m.p_pv(k);
    if p_net > 0
        st.bal(k) = st.bal(k) - p_net * dt / 3600 / 1000 * st.price;
    else
        st.bal(k) = st.bal(k) - p_net * dt / 3600 / 1000 * st.price * C.sell_ratio;
    end
    if st.bal(k) <= 0
        st.credit_ok(k) = 0;
    elseif st.bal(k) >= C.credit_restore
        st.credit_ok(k) = 1;
    end
    tie  = booted && st.hstate(k) == 0;
    flex = tie && st.shed_soc(k) == 0 && st.shed_uf(k) == 0 && st.shed_ai(k) == 0 && st.credit_ok(k) == 1;
    bits = bits + tie * 2^(2 + 2*(k-1)) + flex * 2^(3 + 2*(k-1));
    if st.hstate(k) == 2, any_locked = 1; end
    if st.shed_soc(k) || st.shed_uf(k) || st.shed_ai(k), any_shed = 1; end
    if st.card_lock(k) > 0, any_card = 1; end
    o.bal(k) = st.bal(k);
    o.hcode(k) = st.hstate(k) + 4*st.shed_soc(k) + 8*(1 - st.credit_ok(k)) + 16*(st.card_lock(k) > 0) ...
                 + 32*st.shed_uf(k) + 64*st.shed_ai(k);
end

% ---------- BESS set-points (used by the inverter only when grid-connected) ----------
p_set = 0; q_set = 0;
if gridm
    net_p = m.p_cl - m.p_cpv; net_q = m.q_cl;
    for k = 1:n
        net_p = net_p + m.p_load(k) - m.p_pv(k);
        net_q = net_q + m.q_load(k) - m.q_pv(k);
    end
    p_lo = 0; if soc < C.soc_ch_stop, p_lo = -b.P_ch_max; end
    if st.ai_active
        p_hi = 0; if soc > C.soc_ai_min, p_hi = b.P_dis_max; end
        p_set = min(max(st.ai_p, p_lo), p_hi);
        if p_set ~= st.ai_p, ai_status = ai_status + 2; end      % clamped to safe range
    else
        p_hi = 0; if soc > C.soc_reserve, p_hi = b.P_dis_max; end
        p_set = min(max(net_p, p_lo), p_hi);                     % self-consumption rule
        if soc < C.soc_reserve                                   % rebuild the outage reserve
            p_set = max(min(p_set, -C.P_recharge), p_lo);
        end
    end
    q_av = sqrt(max(0, b.S_rated * b.S_rated - p_set * p_set));
    q_set = min(max(net_q, -q_av), q_av);                        % reactive compensation
elseif st.ai_active && st.ai_p ~= 0
    ai_status = ai_status + 8;        % islanded: BESS follows physics, AI request ignored
end

bits = bits + gridm * 1 + (st.mode == 3) * 2;
st.last_bits = bits;
o.bits = bits; o.mode = st.mode; o.p_set = p_set; o.q_set = q_set;
o.ai_status = ai_status; o.price = st.price;
o.flags = grid_ok + 2*mismatch + 4*any_card + 8*any_locked + 16*any_shed + 32*bess_fault + 64*st.ai_active;
end
