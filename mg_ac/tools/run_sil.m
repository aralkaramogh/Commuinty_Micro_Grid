function ok = run_sil()
% RUN_SIL  Run tools/run_sil.sh (firmware C++ vs MATLAB controller, tick for tick).
% Needs bash + g++. Returns true/false, or [] when skipped (no g++ on this PC).
root = fileparts(fileparts(mfilename('fullpath')));
[st, ~] = system('g++ --version');
if st ~= 0
    fprintf('[SIL] skipped here: no g++ on this PC. Run "bash tools/run_sil.sh" where g++ exists.\n');
    ok = []; return;
end
[st, out] = system(sprintf('cd "%s" && bash tools/run_sil.sh', root));
fprintf('%s\n', out); ok = (st == 0);
end
