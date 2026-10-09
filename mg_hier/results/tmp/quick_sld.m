function quick_sld()
root = 'D:\Amogh\MATLAB_Projects\Commuinty_Micro_Grid\mg_hier'; cd(root);
dfile = fullfile(root,'results','tmp','quick_sld.txt'); if exist(dfile,'file'), delete(dfile); end
diary(dfile);
try
addpath(genpath(root)); rmpath(genpath(fullfile(root,'results')));
P = hier_params();
for g = [1 0]
    sc = live_scenario(P); sc.dur_s = 150; sc.soc0 = 0.36;
    live_panel(); live_inputs('set', 'grid', g);
    R = run_hier(sc, P, struct('pace_s', 0)); %#ok<NASGU>
    f = findall(groot, 'Tag', 'mgSLD'); drawnow;
    exportgraphics(f(1), fullfile(root,'results','tmp',sprintf('sld_grid%d.png', g)));
    fprintf('grid %d done\n', g);
end
catch err, disp(getReport(err)); end
disp('SLD_DONE'); diary off;
end
