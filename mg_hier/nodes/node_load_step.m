function [st, r] = node_load_step(st, x, N, dt, estop)
% NODE_LOAD_STEP  One tick of a LOAD node (House H1/H2 or Community load CL).
% MATLAB twin of firmware_node/node.cpp (tools/run_sil_node.sh checks they agree).
% x: decoded "L" line = command from the main controller (valid, enable,
%    flex_allow) + this node's own meter (v, i, p/q load, p/q pv, card_uid)
% r: relay outputs + report for the main controller
% Local rules (the node decides these itself, no matter what it is told):
%  - over-current protection: trip, retry, lock out after repeated trips
%  - critical hold: once enabled, the critical circuit stays on (only its own
%    protection can open it); a later "enable = 0" is ignored
%  - comms-loss fallback: no command for N_comm_lost ticks -> flexible load off
%  - E-stop (estop = 1 while the button is pressed): both relays open and stay open
%    (latched) until a reset (R line); reported as hstate = 3
if nargin < 5, estop = 0; end
if estop, st.estop = 1; end
if x.valid
    st.n_nocmd = 0;
    if x.enable, st.enabled = 1; end            % latched: never switched off by a command
    st.flex_allow = x.flex_allow;
else
    st.n_nocmd = min(st.n_nocmd + 1, 1000000);
end
comm_lost = st.n_nocmd >= N.N_comm_lost;

% over-current protection (judged on the circuit that was closed last tick)
if st.estop
    % E-stop latched: protection frozen, relays forced open below
elseif st.hstate == 0
    if st.tie && x.i > N.I_trip, st.n_oc = st.n_oc + 1; else, st.n_oc = 0; end
    if st.n_oc >= N.N_oc
        st.strikes = st.strikes + 1; st.n_oc = 0; st.n_healthy = 0;
        if st.strikes >= N.strikes_max
            st.hstate = 2;                          % locked out (needs a person)
        else
            st.hstate = 1; st.retry = N.N_retry;    % tripped, retry later
        end
    else
        st.n_healthy = st.n_healthy + 1;
        if st.n_healthy >= N.N_strike_clear, st.strikes = 0; end
    end
elseif st.hstate == 1
    st.retry = st.retry - 1;
    if st.retry <= 0, st.hstate = 0; st.n_healthy = 0; end
end

st.tie  = double(st.enabled == 1 && st.hstate == 0 && st.estop == 0);
st.flex = double(st.tie == 1 && st.flex_allow == 1 && ~comm_lost);

% energy meter counters [Wh]: keep counting even when the main controller is silent
p_net = x.p_load - x.p_pv;
if p_net > 0
    st.e_imp = st.e_imp + p_net * dt / 3600;
else
    st.e_exp = st.e_exp - p_net * dt / 3600;
end

r.tie = st.tie; r.flex = st.flex; r.hstate = st.hstate + (3 - st.hstate) * st.estop; r.strikes = st.strikes;
r.comm_lost = double(comm_lost); r.e_imp = st.e_imp; r.e_exp = st.e_exp;
r.v = x.v; r.i = x.i; r.p_load = x.p_load; r.q_load = x.q_load; r.p_pv = x.p_pv; r.q_pv = x.q_pv;
r.card_uid = x.card_uid;
end
