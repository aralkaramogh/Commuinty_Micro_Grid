function st = node_load_init()
% NODE_LOAD_INIT  Load-node state at power-up (MATLAB twin of firmware_node).
% Every relay OFF until the main controller sends the first "enable".
st.enabled = 0; st.flex_allow = 0; st.n_nocmd = 0;
st.hstate = 0; st.n_oc = 0; st.strikes = 0; st.n_healthy = 0; st.retry = 0;
st.tie = 0; st.flex = 0; st.e_imp = 0; st.e_exp = 0;
st.estop = 0;                 % E-stop latch: set by the button, cleared only by a reset (R)
end
