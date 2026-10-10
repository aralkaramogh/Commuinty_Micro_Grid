function run_logged(fn, logfile)
% RUN_LOGGED  Run fn() with its printed output copied to logfile (for long jobs
% started from a timer, so progress can be checked while it runs).
if isfile(logfile), delete(logfile); end
diary(logfile);
try
    fn();
catch e
    disp(getReport(e));
end
disp('RUN_LOGGED_DONE'); diary off;
end
