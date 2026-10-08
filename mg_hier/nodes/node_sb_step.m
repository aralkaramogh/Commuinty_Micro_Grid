function [st, r] = node_sb_step(st, x, N, B, estop)
% NODE_SB_STEP  One tick of the SOLAR + BESS node (MATLAB twin of firmware_node).
% x: decoded "B" line = command (valid, p_set, q_set, sync) + own meter
%    (soc, p_bess, q_bess, bess_status, v_c, f_mg, p_cpv)
% Local rules: hard battery limits whatever it is told (no discharge at or below
% soc_floor, no charge at or above soc_ch_stop, inverter P and VA ratings);
% comms loss -> keep the last set-point (clamped), stop synchronising.
% E-stop: inverter stopped (P = Q = 0, no sync), latched until a reset; clamped = 2
if nargin < 5, estop = 0; end
if estop, st.estop = 1; end
if x.valid
    st.n_nocmd = 0; st.p_cmd = x.p_set; st.q_cmd = x.q_set; st.sync_cmd = x.sync;
else
    st.n_nocmd = min(st.n_nocmd + 1, 1000000);
end
comm_lost = st.n_nocmd >= N.N_comm_lost;
p_hi = 0; if x.soc > N.soc_floor,   p_hi = B.P_dis_max; end
p_lo = 0; if x.soc < N.soc_ch_stop, p_lo = -B.P_ch_max; end
p = min(max(st.p_cmd, p_lo), p_hi);
q_av = sqrt(max(0, B.S_rated * B.S_rated - p * p));
q = min(max(st.q_cmd, -q_av), q_av);
r.p = p; r.q = q;
r.sync = double(st.sync_cmd == 1 && ~comm_lost);
r.clamped = double(p ~= st.p_cmd || q ~= st.q_cmd);
r.comm_lost = double(comm_lost);
if st.estop, r.p = 0; r.q = 0; r.sync = 0; r.clamped = 2; end
r.soc = x.soc; r.p_bess = x.p_bess; r.q_bess = x.q_bess; r.bess_status = x.bess_status;
r.v_c = x.v_c; r.f_mg = x.f_mg; r.p_cpv = x.p_cpv;
end
