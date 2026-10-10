% RUN_ALL_HIER  Build and validate the hierarchical microgrid in SIMULATION only
% (no ESP32, no Pi): every node is the MATLAB twin of its firmware, the Pi is the
% simulated broker with the real ACL.
%  1 node config.h + Mosquitto files  2 unit tests  3 scenarios (+ figures, node
%  frame logs, Pi message samples)  4 Monte Carlo  5 SIL (node C++ vs MATLAB)  6 summary
N_MC = 40;
root = fileparts(mfilename('fullpath')); if isempty(root), root = pwd; end
old = fullfile(fileparts(root), 'archive', 'mg_ac');   % never mix with the single-controller version (archived)
for f = {'params','models','controller','comms','sim','tests','hil','tools'}
    p = fullfile(old, f{1}); if contains(path, p), rmpath(p); end
end
for f = {'pv_power.m', 'volt_var.m', 'net_solve.m', 'bess_limits.m'}   % same physics files as mg_ac
    if ~exist(fullfile(root, 'plant', f{1}), 'file'), copyfile(fullfile(old, 'models', f{1}), fullfile(root, 'plant', f{1})); end
end
if ~exist(fullfile(root, 'main', 'wrap180.m'), 'file'), copyfile(fullfile(old, 'controller', 'wrap180.m'), fullfile(root, 'main', 'wrap180.m')); end
for f = {'params','plant','nodes','main','comms','pi','sim','tests','tools','hil'}
    addpath(fullfile(root, f{1}));
end
P = hier_params();
for f = {'logs','figures','tables','pi_msgs'}, d = fullfile(root, 'results', f{1}); if ~exist(d, 'dir'), mkdir(d); end, end
export_node_header(P); make_mosquitto_files();
fprintf('[1] firmware_node/config_node.h + docs/mosquitto/{mg.conf,acl} written\n');
tr = runtests(fullfile(root, 'tests', 'test_hier.m'));
fprintf('[2] unit tests %d/%d\n', sum([tr.Passed]), numel(tr));
S = define_scenarios_h(P); logs = fullfile(root,'results','logs'); rows = {}; Rall = cell(1, numel(S));
node_id = [P.load_id, {'SB'}];
for k = 1:numel(S)
    tic; R = run_hier(S(k), P, struct('keep_frames', true)); el = toc;
    [ok, msg] = check_h(R, P); K = R.kpi;
    for j = 1:numel(node_id)                      % node lines for the SIL replay
        writelines(string(R.L.lin(:, j)), fullfile(logs, sprintf('%s_%s_in.txt', S(k).name, node_id{j})));
        writelines(string(R.L.lout(:, j)), fullfile(logs, sprintf('%s_%s_out.txt', S(k).name, node_id{j})));
    end
    if ~isempty(R.PI.events), writelines(string(R.PI.events(:)), fullfile(logs, [S(k).name '_events.txt'])); end
    if any(strcmp(S(k).name, {'S2_grid_outage', 'S13_dashboard_commands'}))
        fn = fieldnames(R.PI.sample);
        for q = 1:numel(fn), writelines(R.PI.sample.(fn{q}), fullfile(root, 'results', 'pi_msgs', [fn{q} '.json'])); end
    end
    plot_h(R, P, fullfile(root, 'results', 'figures', [S(k).name '.png']));
    nmsg = 0; if R.PI.count.Count > 0, nmsg = sum(cell2mat(values(R.PI.count))); end
    rows(end+1,:) = {S(k).name, ok, K.V_min_pu, K.V_max_pu, K.f_min, K.f_max, K.soc_min, ...
                     K.close_angle_max, nmsg, strjoin(string(msg), '; '), el}; %#ok<SAGROW>
    fprintf('[3] %-26s %s  (%5.0f s, %d Pi messages)\n', S(k).name, string(ok), el, nmsg);
    if ~ok, fprintf('      - %s\n', msg{:}); end
    R.L = rmfield(R.L, {'lin','lout'}); Rall{k} = R;
end
ST = cell2table(rows, 'VariableNames', {'scenario','pass','V_min_pu','V_max_pu','f_min','f_max','soc_min', ...
                                        'close_angle','pi_messages','failed_rules','wall_s'});
writetable(ST, fullfile(root, 'results', 'tables', 'scenarios.csv'));
tic; MC = montecarlo_h(P, N_MC, fullfile(root, 'results', 'tables'));
fprintf('[4] Monte Carlo %d/%d (%.0f s)\n', sum(MC.pass), N_MC, toc);
if any(~MC.pass), disp(MC(~MC.pass, {'run','link_drop','failed_rules'})); end
make_fuzz_frames(P, fullfile(root, 'results', 'logs'));
sil = run_sil_node();
save(fullfile(root, 'results', 'last_run.mat'), 'ST', 'MC', 'sil');
fprintf('[6] done. unit %d/%d, scenarios %d/%d, Monte Carlo %d/%d, SIL %s\n', sum([tr.Passed]), numel(tr), ...
        sum(ST.pass), height(ST), sum(MC.pass), N_MC, string(mat2str(sil)));
