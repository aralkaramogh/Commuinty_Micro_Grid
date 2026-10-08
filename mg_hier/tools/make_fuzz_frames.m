function make_fuzz_frames(P, logs, N)
% MAKE_FUZZ_FRAMES  Random node lines (links dropping, over-currents, SOC at the
% limits, odd set-points) through the MATLAB node twins -> results/logs/FUZZ_*.
% The SIL replays them through the C++ so rarely used branches are compared too.
if nargin < 3, N = 20000; end
rs = RandStream('mt19937ar', 'Seed', 7);
r = @() rand(rs);
st = node_load_init(); lin = strings(N,1); lout = strings(N,1);
for i = 1:N
    if mod(i, 400) == 0                               % reset now and then (lockouts are permanent)
        st = node_load_init(); lin(i) = "R"; lout(i) = "READY"; continue;
    end
    c = struct('valid', double(mod(floor(i/37), 6) ~= 0 && r() > 0.05), 'enable', double(r() > 0.05), 'flex_allow', double(r() > 0.3));
    m = struct('v', 200 + 40*r(), 'i', 60*r()^3, 'p_load', 3000*r(), 'q_load', 800*r() - 200, ...
               'p_pv', 3000*r()*(r() > 0.5), 'q_pv', 400*r() - 200, 'card_uid', (r() > 0.97) * 2712847105);
    lin(i) = node_lines('enc_L', i, c, m);
    [st, o] = node_load_step(st, node_lines('dec_L', lin(i)), P.node, P.sim.dt);
    lout(i) = node_lines('enc_l', i, o);
end
writelines(lin, fullfile(logs, 'FUZZ_L_in.txt')); writelines(lout, fullfile(logs, 'FUZZ_L_out.txt'));
st = node_sb_init(); lin = strings(N,1); lout = strings(N,1);
socs = [0 P.node.soc_floor P.node.soc_ch_stop 1];
for i = 1:N
    soc = r(); if r() < 0.2, soc = socs(randi(rs, 4)); end
    c = struct('valid', double(mod(floor(i/37), 6) ~= 0 && r() > 0.05), 'p_set', round(12000*r() - 6000, 1), 'q_set', round(12000*r() - 6000, 1), ...
               'sync', double(r() > 0.5));
    m = struct('soc', soc, 'p_bess', 8000*r() - 4000, 'q_bess', 2000*r() - 1000, 'bess_status', double(r() > 0.95), ...
               'v_c', 220 + 20*r(), 'f_mg', 49.5 + r(), 'p_cpv', 4000*r());
    lin(i) = node_lines('enc_B', i, c, m);
    [st, o] = node_sb_step(st, node_lines('dec_B', lin(i)), P.node, P.bess);
    lout(i) = node_lines('enc_b', i, o);
end
writelines(lin, fullfile(logs, 'FUZZ_B_in.txt')); writelines(lout, fullfile(logs, 'FUZZ_B_out.txt'));
end
