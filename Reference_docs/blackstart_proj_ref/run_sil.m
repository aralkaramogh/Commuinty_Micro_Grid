function ok = run_sil(csv_files)
% RUN_SIL  Software-in-the-loop check: replays MATLAB scenario vectors through the
% real C++ firmware FSM (firmware/src/fsm.cpp, protection.cpp, restoration.cpp) and
% checks the C++ makes the same state / load decisions tick-for-tick.
%
% Needs a C++ compiler (g++) on the system PATH. On Windows the simplest is
%   winget install BrechtSanders.WinLibs.POSIX.UCRT     (MinGW-w64 g++)
% then restart MATLAB. Returns true/false; returns [] (skipped) if no g++.
if nargin < 1
    d = dir(fullfile('results','logs','sil_T*.csv'));
    csv_files = fullfile('results','logs',{d.name});
end
[st,~] = system('g++ --version');
if st ~= 0
    fprintf('[SIL] SKIPPED: g++ not found. Install a C++ compiler (see help run_sil) to run the C++ equivalence test.\n');
    ok = []; return;
end
exe = fullfile('results','logs','sil_test.exe');
src = 'firmware/src/fsm.cpp firmware/src/protection.cpp firmware/src/restoration.cpp firmware/test/test_sil_equivalence.cpp';
cmd = sprintf('g++ -std=c++17 -O2 -DSIL_TEST_MODE -Ifirmware/include %s -o "%s"', src, exe);
[st,out] = system(cmd);
if st ~= 0; fprintf('[SIL] Compile FAILED:\n%s\n', out); ok = false; return; end
[st,out] = system(sprintf('"%s" %s', exe, strjoin(strcat('"',csv_files,'"'),' ')));
lines = strsplit(out, newline);
keep = lines(~startsWith(lines,'['));          % hide the FSM's own trace prints
fprintf('%s\n', strjoin(keep, newline));
ok = (st == 0);
end
