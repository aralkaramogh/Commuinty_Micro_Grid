% RUN_HIL_DEMO  AC model with the REAL ESP32: MATLAB plant <-> USB <-> ESP32.
% Default = S11_demo_outage: 25 simulated minutes (1500 ticks), a 10-minute
% blackout at 17:57 and resync. Every tick is one USB round trip, so a run
% takes roughly 1-2 minutes. Status prints every 30 ticks.
% For the jury: set PACE_S = 0.2 to slow it down so the LEDs are easy to follow.
PORT   = "COM14";                 % <-- change me
SCEN   = 'S11_demo_outage';      % or S4_island_overload (1800 ticks), S2_grid_outage (long)
PACE_S = 0;                      % 0 = as fast as possible; 0.2 = 5 ticks per second
COMPARE_WITH_MATLAB = true;      % re-runs the same scenario in MATLAB (about 2 s) and compares
root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root,'params'), fullfile(root,'models'), fullfile(root,'controller'), ...
        fullfile(root,'comms'), fullfile(root,'sim'), fullfile(root,'tests'), fullfile(root,'hil'));
P = ac_params(); S = define_scenarios(P); sc = S(strcmp({S.name}, SCEN));
sc.dur_s = min(sc.dur_s, 3 * 3600);
fprintf('%s: %d ticks on %s\n', sc.name, round(sc.dur_s / P.sim.dt), PORT);
t0 = tic;
R_hw = run_scenario(sc, P, struct('transport', 'esp32', 'port', PORT, 'keep_frames', true, ...
                                  'progress_every', 30, 'pace_s', PACE_S));
el = toc(t0); N = numel(R_hw.L.t);
fprintf('Hardware run: %.1f s for %d ticks = %.1f ms per tick\n', el, N, 1000 * el / N);
if COMPARE_WITH_MATLAB
    R_ref = run_scenario(sc, P, struct('transport', 'matlab', 'keep_frames', true));
    fprintf('ESP32 replies identical to MATLAB: %d\n', isequal(R_hw.L.C, R_ref.L.C));
end
[ok, msg] = check_scenario(R_hw, P); fprintf('Scenario rules: %s\n', string(ok));
if ~ok, fprintf('  - %s\n', msg{:}); end
plot_scenario(R_hw, P, fullfile(root, 'results', 'figures', ['hil_' sc.name '.png']));
