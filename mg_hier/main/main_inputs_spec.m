function S = main_inputs_spec()
% MAIN_INPUTS_SPEC  The ONLY information the main controller may receive
% ("input firewall"). main_step.m refuses any other field, so the brain can
% never peek at plant internals: it sees what a real community controller would
% see - node reports, the PCC meter (synchroscope + power meter at the grid
% breaker) and requests from the Pi.
S.top   = {'t_s', 'pcc', 'load', 'sb', 'inbox'};
S.pcc   = {'v_grid', 'f_grid', 'v_c', 'f_mg', 'dtheta', 'p_pcc', 'q_pcc'};
S.load  = {'ok', 'tie', 'flex', 'hstate', 'strikes', 'comm_lost', 'e_imp', 'e_exp', ...
           'v', 'i', 'p_load', 'q_load', 'p_pv', 'q_pv', 'card_uid'};
S.sb    = {'ok', 'p', 'q', 'sync', 'clamped', 'comm_lost', 'soc', 'p_bess', 'q_bess', ...
           'bess_status', 'v_c', 'f_mg', 'p_cpv'};
S.inbox = {'topic', 'payload'};
end
