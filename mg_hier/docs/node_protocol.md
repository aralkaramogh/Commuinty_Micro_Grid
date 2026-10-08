# Node protocol (USB serial, 115200 baud, one line per tick, LF)

MATLAB sends one line to each node every tick; the node answers with one line.
`R` resets the node (all OFF), it answers `READY`. The first letter selects the role,
so the same sketch runs on every board.

## Load node (H1, H2, CL)
`L,seq,valid,enable,flex_allow,v,i,p_load,q_load,p_pv,q_pv,card_uid`
- valid 1 = a command from the main controller arrived this tick (0 = none: link down)
- enable: switch on the critical circuit (latched: a later 0 is ignored)
- flex_allow: flexible load allowed
- meter: v [V], i [A], p_load [W], q_load [var], p_pv [W], q_pv [var], card_uid (0 = no tap)

Reply `l,seq,tie,flex,hstate,strikes,comm_lost,e_imp,e_exp,v,i,p_load,q_load,p_pv,q_pv,card_uid`
- tie/flex: relay states the node applied; hstate 0 ok, 1 tripped (retry), 2 locked out
- comm_lost 1 = no command for N_comm_lost ticks (flexible load off, critical stays on)
- e_imp / e_exp: energy counters [Wh] (billing survives missing reports)

## Solar + BESS node (SB)
`B,seq,valid,p_set,q_set,sync,soc,p_bess,q_bess,bess_status,v_c,f_mg,p_cpv`
Reply `b,seq,p,q,sync,clamped,comm_lost,soc,p_bess,q_bess,bess_status,v_c,f_mg,p_cpv`
- p/q: set-points the node passed to the inverter after its hard limits
  (no discharge at SOC <= soc_floor, no charge at SOC >= soc_ch_stop, P and VA ratings)
- clamped 1 = the node changed the command; comm_lost: set-point held, sync stopped

## PCC meter (into the main controller, no node)
`P,seq,v_grid,f_grid,v_c,f_mg,dtheta,p_pcc,q_pcc`

Number formats are fixed (see comms/node_lines.m and firmware_node/mg_node/node.cpp),
so MATLAB and the ESP32 see bit-identical values. SIL: tools/run_sil_node.sh.
