function write_summary(root, P, tr, ST, MC, sil, Rall, ds_info)
% WRITE_SUMMARY  results/results_summary.md from the latest run_all.
f = fopen(fullfile(root, 'results', 'results_summary.md'), 'w'); c = onCleanup(@() fclose(f));
w = @(varargin) fprintf(f, varargin{:});
w('# AC microgrid model: results summary\n\nGenerated %s by run_all.m. Everything electrical is simulated in MATLAB (phasor model); the controller is the MATLAB twin of the ESP32 firmware.\n\n', datestr(now));
w('| Check | Result |\n|---|---|\n');
w('| Unit tests | %d / %d pass |\n', sum([tr.Passed]), numel(tr));
w('| Scenarios | %d / %d pass |\n', sum(ST.pass), height(ST));
w('| Monte Carlo | %d / %d pass (%.1f %%, requirement %.0f %%) |\n', sum(MC.pass), height(MC), 100*mean(MC.pass), 100*P.req.mc_pass);
if isempty(sil), s = 'not run on this PC (no g++); run bash tools/run_sil.sh'; elseif sil, s = 'PASS, 0 mismatches'; else, s = 'FAIL'; end
w('| SIL C++ firmware vs MATLAB | %s |\n', s);
w('| AI training dataset | %s |\n\n', ds_info);
w('## Scenarios\n\n| Scenario | Pass | V min pu | V max pu | f min | f max | SOC min | close angle deg | failed rules |\n|---|---|---|---|---|---|---|---|---|\n');
for k = 1:height(ST)
    w('| %s | %s | %.3f | %.3f | %.2f | %.2f | %.2f | %.1f | %s |\n', ST.scenario{k}, string(ST.pass(k)), ...
      ST.V_min_pu(k), ST.V_max_pu(k), ST.f_min(k), ST.f_max(k), ST.soc_min(k), ST.close_angle(k), ST.failed_rules(k));
end
K = Rall{1}.kpi; Lg = K.ledger;
w('\n## Normal day (S1)\n\nGrid import %.1f kWh, export %.1f kWh, cable losses %.2f kWh. Grid power factor never below %.3f (BESS supplies the reactive power).\n\n', ...
  K.grid_import_Wh/1e3, K.grid_export_Wh/1e3, K.loss_Wh/1e3, K.pf_pcc_min);
w('P2P ledger (Wh, row sells to column):\n\n| seller | %s |\n|---|%s\n', strjoin({P.house.id}, ' | '), repmat('---|', 1, P.n_house));
for k = 1:numel(Lg.names), w('| %s | %s |\n', Lg.names{k}, strjoin(compose('%.0f', Lg.matrix(k,:)), ' | ')); end
w('\n## Monte Carlo\n\nRuns %d. Voltage %.3f-%.3f pu, island frequency %.2f-%.2f Hz, worst closing angle %.1f deg, worst SOC %.2f.\n', ...
  height(MC), min(MC.V_min_pu), max(MC.V_max_pu), min(MC.f_min), max(MC.f_max), max(MC.close_angle_max), min(MC.soc_min));
bad = MC(~MC.pass, :);
for k = 1:height(bad), w('- run %d failed: %s\n', bad.run(k), bad.failed_rules(k)); end
w(['\n## Not verified / simplifications\n\n- Phasor (RMS) model at 1 s steps: no waveforms, no sub-cycle transients. Real islanding detection and ' ...
   'breaker opening take milliseconds; here the transfer gap is one 1 s tick.\n- Over-current protection at 1 s is for logic only; real fault clearing is the MCB/fuse.\n' ...
   '- Firmware not yet built with the ESP32 toolchain or run on the board (hil/run_hil_demo.m untested on hardware).\n' ...
   '- All [assumed] numbers in params/ac_params.m; load profiles are synthetic.\n']);
end
