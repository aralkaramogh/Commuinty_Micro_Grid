function f = live_panel()
% LIVE_PANEL  Control panel for a live demo (run_hil_nodes / run_live_pi with SCEN = 'LIVE').
% Left: WORLD knobs - change the simulated power system, like a bench.
% (REQUESTS column removed for now: no dashboard/operator inputs in this demo.)
% Right: live read-outs (mode, battery, grid, every node's relays, balances, log).
live_inputs('reset');
old = findall(groot, 'Tag', 'mgLivePanel'); delete(old);
f = uifigure('Name', 'URJA microgrid - live demo panel', 'Position', [40 60 900 680], 'Tag', 'mgLivePanel');
g = uigridlayout(f, [1 2]); g.ColumnWidth = {320, '1x'};

% ---------- WORLD ----------
w = uipanel(g, 'Title', 'WORLD (simulated power system)', 'FontWeight', 'bold');
gw = uigridlayout(w, [20 2]); gw.RowHeight = repmat({22}, 1, 20);
uilabel(gw, 'Text', 'Utility grid', 'FontWeight', 'bold'); uilabel(gw, 'Text', '');
uibutton(gw, 'Text', 'Grid OFF (outage)', 'ButtonPushedFcn', @(~,~) live_inputs('set', 'grid', 0));
uibutton(gw, 'Text', 'Grid ON',           'ButtonPushedFcn', @(~,~) live_inputs('set', 'grid', 1));
uibutton(gw, 'state', 'Text', 'Voltage sag 0.8 pu', 'ValueChangedFcn', @(b,~) live_inputs('set', 'grid_v', 1 - 0.2 * b.Value));
uibutton(gw, 'state', 'Text', 'Low frequency 49.2 Hz', 'ValueChangedFcn', @(b,~) live_inputs('set', 'grid_f', 50 - 0.8 * b.Value));
uilabel(gw, 'Text', 'Jump clock to');
uidropdown(gw, 'Items', {'(keep)', '06:00 sunrise', '09:00', '12:00 noon', '15:00', '18:00 sunset', '21:00 night'}, ...
           'ItemsData', [0 6 9 12 15 18 21], 'ValueChangedFcn', @(d,~) jump(d));
uilabel(gw, 'Text', 'Sun % (clouds)');
uislider(gw, 'Limits', [0 100], 'Value', 100, 'MajorTicks', [0 50 100], 'ValueChangedFcn', @(s,~) live_inputs('set', 'sun', s.Value / 100));
uilabel(gw, 'Text', 'Appliances (x normal)', 'FontWeight', 'bold'); uilabel(gw, 'Text', '');
names = {'H1 load', 'H2 load', 'CL pump'};
for k = 1:3
    uilabel(gw, 'Text', names{k});
    uislider(gw, 'Limits', [0 2], 'Value', 1, 'MajorTicks', [0 1 2], ...
             'ValueChangedFcn', @(s,~) live_inputs('set_el', 'load', [k s.Value]));
end
uilabel(gw, 'Text', 'Faults and cables', 'FontWeight', 'bold'); uilabel(gw, 'Text', '');
uibutton(gw, 'state', 'Text', 'Short circuit H1', 'ValueChangedFcn', @(b,~) live_inputs('set_el', 'fault', [1 b.Value]));
uibutton(gw, 'state', 'Text', 'Short circuit H2', 'ValueChangedFcn', @(b,~) live_inputs('set_el', 'fault', [2 b.Value]));
ids = {'H1', 'H2', 'CL', 'SB'};
for k = 1:4
    uicheckbox(gw, 'Text', ['Cut link ' ids{k}], 'ValueChangedFcn', @(c,~) live_inputs('set_el', 'link_down', [k c.Value]));
end
uilabel(gw, 'Text', 'E-stop (any node)', 'FontWeight', 'bold'); uilabel(gw, 'Text', 'held = pressed');
for k = 1:4
    uibutton(gw, 'state', 'Text', ['E-STOP ' ids{k}], 'ValueChangedFcn', @(b,~) live_inputs('set_el', 'estop', [k b.Value]));
end
for k = 1:4
    uibutton(gw, 'Text', ['Technician: reset ' ids{k}], 'ButtonPushedFcn', @(~,~) live_inputs('set', 'reset_node', k));
end
uilabel(gw, 'Text', 'RFID card at H2', 'FontWeight', 'bold'); uilabel(gw, 'Text', '');
uibutton(gw, 'Text', 'Tap valid card (+Rs 20)', 'ButtonPushedFcn', @(~,~) live_inputs('tap', 2, 2712847106));
uibutton(gw, 'Text', 'Tap wrong card',          'ButtonPushedFcn', @(~,~) live_inputs('tap', 2, 305419896));
uilabel(gw, 'Text', ''); uilabel(gw, 'Text', '');
uibutton(gw, 'Text', 'STOP run', 'BackgroundColor', [1 .8 .8], 'ButtonPushedFcn', @(~,~) live_inputs('set', 'stop', 1));

gw.RowHeight = repmat({22}, 1, numel(gw.RowHeight)); gw.RowSpacing = 4; gw.Scrollable = 'on';   % scroll if the window is short
% ---------- READ-OUTS ----------
s = uipanel(g, 'Title', 'LIVE STATUS', 'FontWeight', 'bold');
gs = uigridlayout(s, [3 1]); gs.RowHeight = {150, 110, '1x'};
h.top  = uilabel(gs, 'Text', 'waiting for the first tick...', 'FontName', 'Consolas', 'FontSize', 13, 'VerticalAlignment', 'top');
h.node = uilabel(gs, 'Text', '', 'FontName', 'Consolas', 'FontSize', 12, 'VerticalAlignment', 'top');
h.log  = uitextarea(gs, 'Editable', 'off', 'FontName', 'Consolas', 'FontSize', 11);
f.UserData = h;
live_sld('open');                    % live single-line diagram in its own window
end

function jump(d)
% move the simulated clock (sun position, household demand) to the chosen hour
if d.Value == 0, return; end                    % 0 = (keep)
s = live_inputs('get'); dh = mod(d.Value - s.now_h, 24);
live_inputs('set', 'hour_shift', s.hour_shift + dh);
d.Value = 0;
end

function req(src, kind, target, value, ttl)
id = round(1e3 * posixtime(datetime('now'))) + randi(999);       % unique request id
live_inputs('push_cmd', ['mg/cmd/' src '/' kind], struct('id', id, 'target', target, 'value', value, 'ttl', ttl));
end
