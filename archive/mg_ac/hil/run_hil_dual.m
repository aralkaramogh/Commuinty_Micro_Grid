function out = run_hil_dual(portA, portB, scen, max_s)
% RUN_HIL_DUAL  Two ESP32 controllers on one simulated AC microgrid.
%   Board A drives the plant. Board B receives the SAME measurements every
%   tick (hot standby) and must give the SAME answers. If board A stops
%   answering (unplug its USB), board B takes over on the same tick with no
%   loss of state. At the end, both are compared with the MATLAB controller.
%
%   out = run_hil_dual("COM5", "COM7")                    % S11 demo outage, 1500 ticks
%   out = run_hil_dual("COM5", "COM7", 'S4_island_overload')
%   out = run_hil_dual("FAKE", "FAKE")                    % no boards: MATLAB stand-ins
%   out = run_hil_dual("FAKE@2000", "FAKE")               % stand-in A "unplugged" at tick 2000
if nargin < 3 || isempty(scen), scen = 'S11_demo_outage'; end
if nargin < 4, max_s = 3 * 3600; end
root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root,'params'), fullfile(root,'models'), fullfile(root,'controller'), ...
        fullfile(root,'comms'), fullfile(root,'sim'), fullfile(root,'tests'), fullfile(root,'hil'));
P = ac_params(); n = P.n_house; S = define_scenarios(P);
sc = S(strcmp({S.name}, scen)); assert(~isempty(sc), 'unknown scenario %s', scen);
sc.dur_s = min(sc.dur_s, max_s);

ports = string({portA, portB}); names = ["A", "B"];
kind = strings(1,2); link = cell(1,2); fst = cell(1,2); die_at = inf(1,2); alive = true(1,2);
for b = 1:2
    if startsWith(ports(b), "FAKE")
        kind(b) = "fake"; fst{b} = ac_controller_init(P);
        if contains(ports(b), "@"), die_at(b) = str2double(extractAfter(ports(b), "@")); end
    else
        kind(b) = "esp32"; link{b} = esp32_open(ports(b), P);
        fprintf('Board %s on %s: READY\n', names(b), ports(b));
    end
end
cleanupObj = onCleanup(@() close_links(kind, link));   % gets copies, not the nested workspace
mismatch = 0; takeover_tick = NaN; active = 1;
modes = ["BOOT","GRID","ISLAND","RESYNC"];

R = run_scenario(sc, P, struct('transport', 'custom', 'exchange', @exchange, 'keep_frames', true));

fprintf('\nDone: %d ticks. Board answers that differed (A vs B): %d\n', numel(R.L.t), mismatch);
if ~isnan(takeover_tick), fprintf('Board B took over at tick %d.\n', takeover_tick); end
R_ref = run_scenario(sc, P, struct('transport', 'matlab', 'keep_frames', true));
same = isequal(R.L.C, R_ref.L.C);
fprintf('Replies identical to the MATLAB controller for the whole run: %d\n', same);
[ok, msg] = check_scenario(R, P);
fprintf('Scenario rules: %s\n', string(ok)); if ~ok, fprintf('  - %s\n', msg{:}); end
f = fullfile(root, 'results', 'figures', ['hil_dual_' sc.name '.png']);
plot_scenario(R, P, f); fprintf('Plot: %s\n', f);
out = struct('R', R, 'mismatch', mismatch, 'takeover_tick', takeover_tick, 'same_as_matlab', same, 'rules_ok', ok);

    function Cline = exchange(Mline, seq)
        C = strings(1,2);
        for bb = 1:2
            if ~alive(bb), continue; end
            try
                if kind(bb) == "fake"
                    if seq >= die_at(bb), error('fake board unplugged'); end
                    [fst{bb}, o] = ac_controller_step(fst{bb}, proto_decode_meas(Mline, n), P);
                    C(bb) = proto_encode_cmd(seq, o);
                else
                    C(bb) = string(esp32_exchange(link{bb}, Mline, seq));
                end
            catch err
                alive(bb) = false;
                fprintf(2, '\n!! Board %s stopped answering at tick %d (%s)\n', names(bb), seq, err.message);
                if bb == active
                    active = find(alive, 1);
                    if isempty(active), error('both boards lost at tick %d', seq); end
                    takeover_tick = seq;
                    fprintf(2, '!! Board %s takes over (same state, no tick lost)\n', names(active));
                end
            end
        end
        if all(alive) && C(1) ~= C(2), mismatch = mismatch + 1; end
        Cline = char(C(active));
        if mod(seq, 300) == 0                        % progress every 5 simulated minutes
            v = sscanf(Cline(3:end), '%f,');
            fprintf('t=%5.2f h  mode %-6s  active board %s  flags %3d\n', sc.t0_h + seq/3600, ...
                    modes(v(3)+1), names(active), v(6));
        end
    end

end

function close_links(kind, link)
% Close the serial ports. A plain (not nested) function, so it still works
% while MATLAB is tearing down run_hil_dual's workspace.
for bb = 1:numel(kind)
    if kind(bb) == "esp32" && ~isempty(link{bb})
        try, esp32_close(link{bb}); catch, end
    end
end
end
