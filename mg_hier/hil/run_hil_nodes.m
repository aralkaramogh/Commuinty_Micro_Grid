% RUN_HIL_NODES  Real node ESP32s in the loop (Stage A). Set PORTS: any node not
% listed runs as a virtual node (MATLAB twin). Every real reply is ALSO checked
% against the MATLAB twin fed with the same line, so you see at once whether the
% board behaves exactly like the simulation. Flash firmware_node/mg_node first
% (the same sketch on every board).
%PORTS  = {'H1', 'COM14'; 'H2','COM15'; 'SB', 'COM16'; 'CL', 'COM20'; };    % <- your boards (node id, COM port)
PORTS = { };
LCD_NODES = {};     % boards flashed with firmware_node/mg_node_lcd (16x2 I2C LCD), e.g. {'H1','SB'}
SCEN   = 'S11_demo_outage';      % 'LIVE' = a panel lets you switch the grid OFF/ON and dim the sun whenever you like
                      % or a scripted test, e.g. 'S11_demo_outage' (has pass rules)
PACE_S = 0.25;        % seconds per tick (0 = as fast as the boards answer, ~60 ms per board)
LIVE_SOC0 = 0.45;     % LIVE only: battery at start. 0.45 -> in an outage the pump (CL) is shed within minutes,
                      % then H2 (0.35), then H1 (0.30); use 0.8 to show a calm, seamless outage

root = fileparts(fileparts(mfilename('fullpath')));
for f = {'params','plant','nodes','main','comms','pi','sim','tests','tools','hil'}, addpath(fullfile(root, f{1})); end
delete(serialportfind);   % free ports an earlier (crashed) run left open
P = hier_params();
live = strcmp(SCEN, 'LIVE');
if live, sc = live_scenario(P); sc.soc0 = LIVE_SOC0; else, S = define_scenarios_h(P); sc = S(strcmp({S.name}, SCEN)); end
node_id = [P.load_id, {'SB'}];
ex = cell(1, numel(node_id)); links = {}; node_twin_count('reset');
cl = onCleanup(@() delete(serialportfind));   % ports always released, even after an error
free = serialportlist("available");
for r = 1:size(PORTS, 1)
    assert(any(free == PORTS{r, 2}), 'Port %s not free. Free ports now: %s. Close the Arduino serial monitor / unplug-replug the board, or fix PORTS.', PORTS{r, 2}, strjoin(free, ', '));
    k = find(strcmp(node_id, PORTS{r, 1}));
    assert(~isempty(k), 'unknown node id %s', PORTS{r, 1});
    lk = node_link_open(PORTS{r, 2}, P); links{end+1} = lk; %#ok<SAGROW>
    ex{k} = node_exchange_twin(lk, node_id{k}, P, any(strcmp(LCD_NODES, node_id{k})));
end
if isempty(PORTS), PORTS = cell(0, 2); end
if isempty(PORTS)
    fprintf('Running %s with NO boards: all 4 nodes virtual (MATLAB twins of the firmware)\n', SCEN);
else
    fprintf('Running %s with real nodes: %s (others virtual)\n', SCEN, strjoin(PORTS(:,1).', ', '));
end
if live
    panel = live_panel(); %#ok<NASGU>
    fprintf('LIVE: use the panel - world knobs (grid, sun, loads, faults, cables, cards), requests, STOP run.\n');
end
t0 = tic;
R = run_hier(sc, P, struct('exchange', {ex}, 'progress_every', 20 + 40 * ~live, 'pace_s', PACE_S));
fprintf('Done: %d ticks in %.0f s (%.0f ms per tick)\n', numel(R.L.t), toc(t0), 1000 * toc(t0) / numel(R.L.t));
if live                       % a live run has no script, so no pass rules: print what happened
    K = R.kpi;
    fprintf('Islanded %d times, reconnected %d times, worst closing angle %.1f deg, critical loads served %s %%\n', ...
        K.n_island, K.n_reconnect, K.close_angle_max, mat2str(round(100 * K.crit_served)));
    plot_h(R, P, fullfile(root, 'results', 'figures', 'LIVE_last_run.png'));
    fprintf('Plot saved: results/figures/LIVE_last_run.png\n');
else
    [ok, msg] = check_h(R, P);
    fprintf('Scenario rules: %s\n', string(ok)); if ~ok, fprintf('  - %s\n', msg{:}); end
end
if ~isempty(PORTS), fprintf('Real board replies identical to the MATLAB twin: %d of %d differed\n', node_twin_count('get'), node_twin_count('n')); end
