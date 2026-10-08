function v = live_inputs(op, name, val)
% LIVE_INPUTS  Knobs for a live demo, shared by the control panel (hil/live_panel.m),
% the Pi dashboard (topic mg/sim/<name>) and the simulation.
% WORLD knobs change the simulated power system (like a bench: pull the grid plug,
% short a wire, unplug a cable); the controllers only notice through their meters.
% REQUESTS are queued for the main controller exactly like dashboard requests:
% it checks them and may refuse them.
%   live_inputs('reset') | live_inputs('set', name, value) | s = live_inputs('get')
%   live_inputs('push_cmd', topic, payload)   queue a request (sent next tick)
%   q = live_inputs('take_cmds')              (run loop) requests to deliver now
%   live_inputs('tap', house, uid)            RFID card tap on a house node
%   [h, uid] = live_inputs('take_card')       (plant) the tap, once
%   live_inputs('set', 'reset_node', k)       technician resets node k (clears a lockout)
persistent s
if isempty(s) || strcmp(op, 'reset')
    s = struct('grid', 1, 'grid_v', 1, 'grid_f', 50, 'sun', 1, 'load', [1 1 1], ...
               'fault', [0 0], 'link_down', [0 0 0 0], 'stop', 0, ...
               'card_house', 0, 'card_uid', 0, 'cmds', {{}}, 'n_cmd', 0, 'reset_node', 0, 'hour_shift', 0, 'now_h', 0, 'estop', [0 0 0 0]);
end
v = [];
switch op
    case 'reset'
    case 'set'
        assert(isfield(s, name), 'unknown live input %s', name);
        s.(name) = double(val);
    case 'set_el'                       % one element of a vector knob: val = [index value]
        s.(name)(val(1)) = val(2);
    case 'push_cmd'
        s.n_cmd = s.n_cmd + 1;
        s.cmds{end+1} = struct('topic', name, 'payload', val);
    case 'take_cmds'
        v = s.cmds; s.cmds = {}; return;
    case 'tap'
        s.card_house = name; s.card_uid = val;
    case 'take_reset'                   % node to reset this tick (1..4 = H1, H2, CL, SB), once
        v = s.reset_node; s.reset_node = 0; return;
    case 'take_card'
        v = [s.card_house, s.card_uid]; s.card_house = 0; s.card_uid = 0; return;
end
v = s;
end
