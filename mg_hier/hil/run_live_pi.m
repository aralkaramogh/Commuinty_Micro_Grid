% RUN_LIVE_PI  Main controller (MATLAB) live on the Pi broker over MQTT.
% Publishes mg/state, mg/node/*, mg/house/*/account, mg/event, mg/ack/* and
% obeys (after its own checks) the requests that arrive on mg/cmd/#.
% Before: Pi on the same network, Mosquitto user mgctl created (setup doc, section 3).
PI_HOST = '10.30.23.55';        % <- Pi IP address (hostname -I on the Pi)
%PI_HOST = '192.168.0.107';        % <- Pi IP address (hostname -I on the Pi) on Life Router
PI_USER = 'mgctl';
PI_PASS = '';                   % <- typed here at run time; do not save it in the file
PORTS   = {'H1','COM21'; 'H2','COM15'; 'SB','COM16';'CL','COM14'};                   % e.g. {'H1','COM14'; 'SB','COM16'}; {} = all nodes virtual
%PORTS   = {'H2','COM15'; 'SB','COM16';'CL','COM14'};                   % e.g. {'H1','COM14'; 'SB','COM16'}; {} = all nodes virtual
LCD_NODES = {'H1','H2','SB','CL'};     % boards flashed with firmware_node/mg_node_lcd (16x2 I2C LCD), e.g. {'H1','SB'}
SCEN    = 'S11_demo_outage';               % 'LIVE' = you pull the grid with the panel / dashboard; or e.g. 'S11_demo_outage'
%SCEN    = 'LIVE';               % 'LIVE' = you pull the grid with the panel / dashboard; or e.g. 'S11_demo_outage'
PACE_S  = 0.25;                 % seconds per tick (1 = real time; 0.25 = 4x faster; 0 = as fast as possible)
DASH_INPUTS = false;            % false = ignore everything arriving on mg/cmd/# and mg/sim/# (dashboard is display-only)
SOC0    = [0.45];                   % battery state of charge at start, 0..1 (e.g. 0.30); [] = scenario default (LIVE 0.80)
% Leave PI_HOST = '' to run without the Pi (panel + boards only).

root = fileparts(fileparts(mfilename('fullpath')));
for f = {'params','plant','nodes','main','comms','pi','sim','tests','tools','hil'}, addpath(fullfile(root, f{1})); end
delete(serialportfind);   % free ports an earlier (crashed) run left open
P = hier_params();
if strcmp(SCEN, 'LIVE'), sc = live_scenario(P); panel = live_panel(); else, S = define_scenarios_h(P); sc = S(strcmp({S.name}, SCEN)); end
if ~isempty(SOC0), sc.soc0 = SOC0; end
link = [];
if ~isempty(PI_HOST)
    if isempty(PI_PASS), PI_PASS = input('mgctl password: ', 's'); end
    link = pi_link_open(PI_HOST, PI_USER, PI_PASS); clear PI_PASS
    cl1 = onCleanup(@() link.close());
    if ~DASH_INPUTS, link.fetch = @() struct('topic', {}, 'data', {}); end   % publish only, no inputs
end
node_id = [P.load_id, {'SB'}]; ex = cell(1, numel(node_id)); boards = {};
node_twin_count('reset');
cl = onCleanup(@() delete(serialportfind));   % ports always released, even after an error
free = serialportlist("available");
for r = 1:size(PORTS, 1)
    assert(any(free == PORTS{r, 2}), 'Port %s not free. Free ports now: %s. Close the Arduino serial monitor / unplug-replug the board, or fix PORTS.', PORTS{r, 2}, strjoin(free, ', '));
    k = find(strcmp(node_id, PORTS{r, 1}));
    lk = node_link_open(PORTS{r, 2}, P); boards{end+1} = lk; %#ok<SAGROW>
    ex{k} = node_exchange_twin(lk, node_id{k}, P, any(strcmp(LCD_NODES, node_id{k})));
end
fprintf('Run %s at %.2f s per tick. Use the panel (Grid OFF/ON, Sun, STOP).\n', SCEN, PACE_S);
R = run_hier(sc, P, struct('exchange', {ex}, 'link', link, 'pace_s', PACE_S, 'progress_every', 60));
if ~strcmp(SCEN, 'LIVE')                     % scripted scenarios have pass rules; a live run has none
    [ok, msg] = check_h(R, P);
    fprintf('Scenario rules: %s\n', string(ok)); if ~ok, fprintf('  - %s\n', msg{:}); end
else
    K = R.kpi; fprintf('Live run: %d s simulated, islanded %d times, reconnected %d times, worst closing angle %.1f deg, critical loads served %s\n', ...
        numel(R.L.t), K.n_island, K.n_reconnect, K.close_angle_max, mat2str(round(100*K.crit_served)));
    plot_h(R, P, fullfile(root, 'results', 'figures', 'LIVE_last_run.png'));
end
fprintf('Requests from the Pi: %d (accepted %d)\n', numel(R.acks), sum([R.acks.accepted]));
if ~isempty(PORTS), fprintf('Board replies different from the MATLAB twin: %d of %d\n', node_twin_count('get'), node_twin_count('n')); end
