function st = node_sb_init()
% NODE_SB_INIT  Solar+BESS node state at power-up: set-points zero, no sync.
st.n_nocmd = 0; st.p_cmd = 0; st.q_cmd = 0; st.sync_cmd = 0;
end
