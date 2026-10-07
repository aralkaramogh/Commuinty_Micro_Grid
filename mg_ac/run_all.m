% RUN_ALL  Build, validate and report the AC community microgrid model.
%  1 config.h  2 unit tests  3 scenarios (+ figures, frame logs)  4 AI CSVs
%  5 Monte Carlo  6 AI training dataset  7 SIL (needs g++)  8 summary
N_MC = 40; N_DAYS = 120;
root = fileparts(mfilename('fullpath')); if isempty(root), root = pwd; end
addpath(fullfile(root,'params'), fullfile(root,'models'), fullfile(root,'controller'), fullfile(root,'comms'), ...
        fullfile(root,'sim'), fullfile(root,'tests'), fullfile(root,'hil'), fullfile(root,'tools'));
P = ac_params();
export_params_to_header(P); make_arduino_sketch(); fprintf('[1] config.h + Arduino sketch written\n');
tr = runtests(fullfile(root, 'tests', 'test_models.m'));
fprintf('[2] unit tests %d/%d\n', sum([tr.Passed]), numel(tr));
S = define_scenarios(P); logs = fullfile(root,'results','logs'); figs = fullfile(root,'results','figures');
tabs = fullfile(root,'results','tables'); Rall = cell(1, numel(S)); rows = {};
for k = 1:numel(S)
    tic; R = run_scenario(S(k), P, struct('keep_frames', true)); el = toc;
    [ok, msg] = check_scenario(R, P); K = R.kpi;
    writelines(string(R.L.M), fullfile(logs, [S(k).name '_M.txt']));
    writelines(string(R.L.C), fullfile(logs, [S(k).name '_C.txt']));
    plot_scenario(R, P, fullfile(figs, [S(k).name '.png']));
    rows(end+1,:) = {S(k).name, ok, K.V_min_pu, K.V_max_pu, K.f_min, K.f_max, K.soc_min, ...
                     K.close_angle_max, strjoin(string(msg), '; '), el}; %#ok<SAGROW>
    fprintf('[3] %-26s %s (%.0f s)\n', S(k).name, string(ok), el);
    if ~ok, fprintf('      - %s\n', msg{:}); end
    R.L = rmfield(R.L, {'M','C'}); Rall{k} = R;
end
ST = cell2table(rows, 'VariableNames', {'scenario','pass','V_min_pu','V_max_pu','f_min','f_max','soc_min', ...
                                        'close_angle','failed_rules','wall_s'});
writetable(ST, fullfile(tabs, 'scenarios.csv'));
for k = [1 2], writetable(ai_table(Rall{k}, P, 1), fullfile(tabs, [S(k).name '_ai_1s.csv'])); end
fprintf('[4] 1-second AI CSVs written (S1, S2)\n');
tic; MC = montecarlo(P, N_MC, tabs); fprintf('[5] Monte Carlo %d/%d (%.0f s)\n', sum(MC.pass), N_MC, toc);
tic; DS = gen_ai_dataset(P, N_DAYS, fullfile(root, 'results', 'datasets', 'ai_dataset_60s.csv'), 60);
ds_info = sprintf('%d days x 1440 rows (60 s), %d columns, results/datasets/ai_dataset_60s.csv', N_DAYS, width(DS));
fprintf('[6] %s (%.0f s)\n', ds_info, toc);
sil = run_sil();
write_summary(root, P, tr, ST, MC, sil, Rall, ds_info);
fprintf('[8] results/results_summary.md written\n');
