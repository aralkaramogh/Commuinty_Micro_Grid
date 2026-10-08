function sc = live_scenario(P, t0_h, dur_s)
% LIVE_SCENARIO  Open-ended demo run: grid, sun, loads, faults, card taps, node links
% and requests all follow the live knobs (sim/live_inputs.m), not a script.
if nargin < 2, t0_h = 12.0; end                  % noon: the sun slider matters; jump to 18:00 for an evening outage
if nargin < 3, dur_s = 6 * 3600; end
sc = base_scenario_h(P, 'LIVE');
sc.t0_h = t0_h; sc.dur_s = dur_s; sc.soc0 = 0.80;
sc.grid_fn      = @(t) grid_now();
sc.cloud_fn     = @(t) pick('sun');
sc.load_gain_fn = @(t) pick('load');
sc.fault_fn     = @(t) 3.0 * pick('fault');        % 3 ohm short circuit where switched on
sc.card_fn      = @(t) live_inputs('take_card');
sc.link_fn      = @(t) pick('link_down') > 0;      % order H1, H2, CL, SB
sc.cmd_fn       = @(t) take_cmds(t);
sc.hour_fn      = @(t) pick('hour_shift');          % panel 'jump clock' (sun position, load profiles)
sc.live = true;
end

function v = pick(name)
s = live_inputs('get'); v = s.(name);
end

function g = grid_now()
s = live_inputs('get'); g = [s.grid * s.grid_v, s.grid_f];
end

function q = take_cmds(t)
c = live_inputs('take_cmds');
q = struct('topic', {}, 'payload', {});
for k = 1:numel(c)
    p = c{k}.payload; p.t_sent = t;                % stamped with the simulated time
    q(end+1) = struct('topic', c{k}.topic, 'payload', p); %#ok<AGROW>
end
end
