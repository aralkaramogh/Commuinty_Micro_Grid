function live_sld(cmd, varargin)
% LIVE_SLD  Live single-line diagram (SCADA-style) of the microgrid for the demo.
%   live_sld('open')                          draw the diagram (live_panel calls this)
%   live_sld('update', clk, o, m, act, P)     recolour it (live_status calls this, max 4x/s)
% Colours: green = energised / closed, grey = dead, red = open / fault, amber = shed.
% Display only: it reads the same values as the panel and changes nothing.
switch cmd
    case 'open',   open_sld();
    case 'update', f = findall(groot, 'Tag', 'mgSLD'); if ~isempty(f), update_sld(f(1), varargin{:}); end
end
end

% ------------------------------------------------------------------ drawing
function open_sld()
delete(findall(groot, 'Tag', 'mgSLD'));
f = figure('Name', 'URJA microgrid - live single-line diagram', 'Tag', 'mgSLD', 'NumberTitle', 'off', ...
           'MenuBar', 'none', 'ToolBar', 'none', 'Color', 'w', 'Position', [120 80 1150 640]);
ax = axes(f, 'Position', [0 0 1 1], 'XLim', [0 120], 'YLim', [0 74], 'Visible', 'off'); hold(ax, 'on');
K = colours(); h = struct();
h.banner = text(ax, 60, 68.5, 'waiting for the first tick...', 'FontSize', 18, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
h.sub    = text(ax, 60, 65.2, '', 'FontSize', 11, 'HorizontalAlignment', 'center', 'Color', [.3 .3 .3]);
% utility grid + breaker
h.gsrc = rectangle(ax, 'Position', [3 47 9 9], 'Curvature', [1 1], 'LineWidth', 2, 'FaceColor', 'w');
text(ax, 7.5, 51.5, '~', 'FontSize', 22, 'HorizontalAlignment', 'center');
text(ax, 7.5, 44.5, 'Utility grid', 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
h.gtxt = text(ax, 7.5, 42, '', 'HorizontalAlignment', 'center', 'FontSize', 9);
h.gl1  = line(ax, [12 20], [51.5 51.5], 'LineWidth', 3);
h.brk  = rectangle(ax, 'Position', [20 49 5 5], 'LineWidth', 2);
h.brkx = line(ax, [20.6 24.4], [49.6 53.4], 'LineWidth', 2);
text(ax, 22.5, 58, 'Grid breaker (PCC)', 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
h.btxt = text(ax, 22.5, 46.5, '', 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
h.gl2  = line(ax, [25 30 30], [51.5 51.5 36], 'LineWidth', 3);
h.ptxt = text(ax, 31, 44, '', 'FontSize', 10);
% community bus
h.bus = line(ax, [30 114], [36 36], 'LineWidth', 7);
text(ax, 114, 38.5, 'Community bus 230 V AC', 'HorizontalAlignment', 'right', 'FontWeight', 'bold');
% feeders: SB and CL above the bus, houses below
X = [44 66 86 106];
h.fd(1) = line(ax, [X(1) X(1)], [36 42], 'LineWidth', 3);
h.fd(2) = line(ax, [X(2) X(2)], [36 42], 'LineWidth', 3);
h.fd(3) = line(ax, [X(3) X(3)], [36 29], 'LineWidth', 3);
h.fd(4) = line(ax, [X(4) X(4)], [36 29], 'LineWidth', 3);
h.ft(1) = text(ax, X(1) + 1, 39, '', 'FontSize', 9);
h.ft(2) = text(ax, X(2) + 1, 39, '', 'FontSize', 9);
h.ft(3) = text(ax, X(3) - 1, 32.5, '', 'FontSize', 9, 'HorizontalAlignment', 'right');
h.ft(4) = text(ax, X(4) - 1, 32.5, '', 'FontSize', 9, 'HorizontalAlignment', 'right');
% Solar + BESS box
h.box(1) = rectangle(ax, 'Position', [X(1)-9 42 18 21], 'Curvature', 0.08, 'LineWidth', 2, 'FaceColor', [1 .99 .88]);
text(ax, X(1), 61.3, 'Solar + BESS (SB)', 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
rectangle(ax, 'Position', [X(1)-7 54.5 14 3.2], 'LineWidth', 1);
h.socbar = rectangle(ax, 'Position', [X(1)-7 54.5 0.01 3.2], 'FaceColor', K.live, 'EdgeColor', 'none');
h.soct = text(ax, X(1), 52.6, '', 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
h.sbp  = text(ax, X(1), 50.0, '', 'HorizontalAlignment', 'center');
h.sbpv = text(ax, X(1), 47.4, '', 'HorizontalAlignment', 'center');
h.sbst = text(ax, X(1), 44.3, '', 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
% load boxes: CL, H1, H2
ttl = {'Community load (CL)', 'House 1 (prosumer)', 'House 2 (consumer)'};
c2  = {'pump', 'flexible', 'flexible'};
yb  = [42 7 7];
for j = 1:3
    x = X(j + 1); y = yb(j);
    h.box(j + 1) = rectangle(ax, 'Position', [x-9 y 18 21], 'Curvature', 0.08, 'LineWidth', 2, 'FaceColor', [.97 .97 1]);
    text(ax, x, y + 19.3, ttl{j}, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
    h.r1(j) = rectangle(ax, 'Position', [x-7.5 y + 14.4 2 2], 'LineWidth', 1.5);
    text(ax, x-4.8, y + 15.4, 'critical');
    h.r2(j) = rectangle(ax, 'Position', [x-7.5 y + 11.4 2 2], 'LineWidth', 1.5);
    text(ax, x-4.8, y + 12.4, c2{j});
    h.l1(j) = text(ax, x, y + 8.6, '', 'HorizontalAlignment', 'center');
    h.l2(j) = text(ax, x, y + 6.0, '', 'HorizontalAlignment', 'center');
    h.l3(j) = text(ax, x, y + 2.6, '', 'HorizontalAlignment', 'center', 'FontWeight', 'bold', 'Color', K.red, 'FontSize', 9);
end
text(ax, 2, 3.5, sprintf(['green = energised / relay closed     grey = dead     red = open / fault     amber = shed\n' ...
     'feeder labels: power flowing to / from the community bus']), 'FontSize', 9, 'Color', [.35 .35 .35]);
f.UserData = h;
end

% ------------------------------------------------------------------ live update
function update_sld(f, clk, o, m, act, P)
h = f.UserData; K = colours();
mn = ["BOOT", "GRID", "ISLAND", "RESYNC"]; mc = {K.dead, K.live, K.amber, K.blue};
Vn = P.ac.V_nom;
bus_on  = m.v_c > 0.5 * Vn;
grid_on = m.v_grid > 0.5 * Vn;
dark = ~bus_on && o.mode ~= 0;
if dark
    h.banner.String = 'BLACKOUT - community bus is dead'; h.banner.Color = K.red;
else
    h.banner.String = "MODE: " + mn(o.mode + 1); h.banner.Color = mc{o.mode + 1};
end
h.sub.String = sprintf('sim time %s     microgrid frequency %.2f Hz     bus %.0f V', clk, m.f_mg, m.v_c);
% grid + breaker
h.gsrc.EdgeColor = pick(grid_on, K.live, K.red);
h.gtxt.String = sprintf('%.0f V  %s', m.v_grid, char(pick(grid_on, "available", "DEAD")));
h.gl1.Color = pick(grid_on, K.live, K.dead);
if o.breaker
    h.brk.FaceColor = K.live; h.brk.EdgeColor = K.live; h.brkx.Visible = 'off';
    h.btxt.String = 'CLOSED'; h.btxt.Color = K.live;
else
    h.brk.FaceColor = 'w'; h.brk.EdgeColor = K.red; h.brkx.Visible = 'on'; h.brkx.Color = K.red;
    h.btxt.String = 'OPEN (island)'; h.btxt.Color = K.red;
end
h.gl2.Color = pick(grid_on && o.breaker, K.live, K.dead);
if o.breaker && abs(m.p_pcc) > 20
    h.ptxt.String = sprintf('grid %s %.2f kW', char(pick(m.p_pcc > 0, "import", "export")), abs(m.p_pcc) / 1000);
else
    h.ptxt.String = '';
end
h.bus.Color = pick(bus_on, K.live, K.dead);
% Solar + BESS
sb_fault = bitand(o.flags, 32) > 0; sb_off = bitand(o.flags, 128) > 0 && o.offline(end);
pin = m.p_bess + m.p_cpv;                                   % power the SB feeder puts into the bus
h.fd(1).Color = pick(bus_on && ~sb_fault, K.live, K.dead);
h.ft(1).String = flow(pin);
s = max(0, min(1, m.soc));
h.socbar.Position(3) = max(0.01, 14 * s);
h.socbar.FaceColor = pick(s > 0.5, K.live, pick(s > 0.3, K.amber, K.red));
h.soct.String = sprintf('battery %.1f %%', 100 * s);
st = 'idle'; if m.p_bess > 50, st = 'discharging'; elseif m.p_bess < -50, st = 'charging'; end
h.sbp.String = sprintf('%s %.2f kW', st, abs(m.p_bess) / 1000);
h.sbpv.String = sprintf('solar %.2f kW', m.p_cpv / 1000);
if sb_fault, h.sbst.String = 'INVERTER STOPPED'; h.sbst.Color = K.red;
elseif sb_off, h.sbst.String = 'NODE LINK DOWN'; h.sbst.Color = K.amber;
elseif o.mode == 2, h.sbst.String = 'forming the island'; h.sbst.Color = K.blue;
else, h.sbst.String = ''; end
h.box(1).EdgeColor = pick(sb_fault, K.red, pick(sb_off, K.amber, [.6 .5 .1]));
% loads: j = 1,2 houses (P.load_id order), 3 = CL; diagram order CL, H1, H2
order = [3 1 2];
for d = 1:3
    j = order(d); c = o.code(j);
    tie = act.tie(j) == 1; fl = act.flex(j) == 1;
    if j <= P.n_house
        net = m.p_load(j) - m.p_pv(j);                     % + = takes power from the bus
        h.l1(d).String = sprintf('use %.2f kW  solar %.2f kW', m.p_load(j) / 1000, m.p_pv(j) / 1000);
        h.l2(d).String = sprintf('prepaid Rs %.2f', o.bal(j));
    else
        net = m.p_cl;
        h.l1(d).String = sprintf('use %.2f kW', m.p_cl / 1000);
        h.l2(d).String = '';
    end
    h.ft(d + 1).String = flow(-net);
    h.fd(d + 1).Color = pick(bus_on && tie, K.live, K.dead);
    relay(h.r1(d), tie && bus_on, tie, K);
    shed = bitand(c, 4 + 32 + 64 + 128 + 256 + 8) > 0;
    relay(h.r2(d), fl && bus_on, fl, K);
    if ~fl && tie && shed, h.r2(d).FaceColor = K.amber; h.r2(d).EdgeColor = K.amber; end
    h.l3(d).String = reason(c);
    h.box(d + 1).EdgeColor = pick(bitand(c, 3) > 0 || bitand(c, 1024) > 0, K.red, [.4 .4 .6]);
end
end

% ------------------------------------------------------------------ helpers
function K = colours()
K.live = [0.13 0.55 0.13]; K.dead = [0.62 0.62 0.62]; K.red = [0.85 0.10 0.10];
K.amber = [0.93 0.55 0.05]; K.blue = [0.10 0.35 0.75];
end

function v = pick(c, a, b)
if c, v = a; else, v = b; end
end

function s = flow(p)           % p > 0: power goes INTO the bus from this feeder
if abs(p) < 20, s = ''; elseif p > 0, s = sprintf('to bus %.2f kW', p / 1000); else, s = sprintf('from bus %.2f kW', -p / 1000); end
end

function relay(r, energised, closed, K)
if closed
    r.FaceColor = pick(energised, K.live, K.dead); r.EdgeColor = r.FaceColor;
else
    r.FaceColor = 'w'; r.EdgeColor = K.red;
end
end

function s = reason(c)
s = "";
if bitand(c, 3) == 1, s = "TRIPPED"; elseif bitand(c, 3) == 2, s = "LOCKED OUT";
elseif bitand(c, 3) == 3, s = "E-STOP (reset needed)"; end
if bitand(c, 1024), s = strtrim(s + " NODE OFFLINE"); end
if s == "" && bitand(c, 4),   s = "shed: low battery"; end
if s == "" && bitand(c, 32),  s = "shed: low frequency"; end
if s == "" && bitand(c, 8),   s = "no credit"; end
if s == "" && bitand(c, 128), s = "restricted"; end
if s == "" && bitand(c, 256), s = "off by user"; end
s = char(s);
end
