function ok = run_sil_node()
% RUN_SIL_NODE  Run tools/run_sil_node.sh (node C++ vs MATLAB node twin, tick for tick).
% Needs bash + g++. Returns true/false, or [] when skipped (no g++ on this PC).
root = fileparts(fileparts(mfilename('fullpath')));
[st, ~] = system('g++ --version');
if st ~= 0
    fprintf('[5] SIL skipped here: no g++ on this PC. Run "bash tools/run_sil_node.sh" where g++ exists.\n');
    ok = []; return;
end
[st, out] = system(sprintf('cd "%s" && bash tools/run_sil_node.sh', root));
fprintf('[5] %s\n', strtrim(out)); ok = (st == 0);
end
