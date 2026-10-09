function quick_check()
root = 'D:\Amogh\MATLAB_Projects\Commuinty_Micro_Grid\mg_hier'; cd(root);
dfile = fullfile(root,'results','tmp','quick_check.txt'); if exist(dfile,'file'), delete(dfile); end
diary(dfile);
try
addpath(genpath(root)); rmpath(genpath(fullfile(root,'results')));
P = hier_params(); S = define_scenarios_h(P);
for k = [2 10 11]
  R = run_hier(S(k), P); [ok,msg] = check_h(R, P);
  fprintf('%s pass=%d\n', S(k).name, ok); if ~ok, disp(msg); end
  try, ev = R.PI.events; catch, ev = {}; end
  for i = 1:numel(ev), if contains(ev{i},'BLACKOUT') || contains(ev{i},'restored'), disp(ev{i}); end, end
end
catch err, disp(getReport(err)); end
disp('QUICK_DONE'); diary off;
end
