function live_status(t_s, t0_h, o, m, act, P, refresh)
% LIVE_STATUS  Refresh the read-outs of the live panel (called every tick by run_hier).
persistent log fig dirty
if t_s == 0 || isempty(log), log = strings(0, 1); fig = []; dirty = false; end
hh = mod(t0_h * 3600 + t_s, 86400);
clk = sprintf('%02d:%02d:%02d', floor(hh/3600), floor(mod(hh, 3600)/60), floor(mod(hh, 60)));
for e = 1:numel(o.events)
    log(end+1) = sprintf('%s  %s: %s', clk, o.events{e}.node, o.events{e}.text); dirty = true;
end
for a = 1:numel(o.acks)
    ak = o.acks(a); res = 'ACCEPTED'; if ~ak.accepted, res = ['REFUSED (' ak.reason ')']; end
    if ak.accepted && ~isempty(ak.reason), res = ['accepted, ' ak.reason]; end
    usr = ''; if ~isempty(ak.user), usr = ['/' ak.user]; end
    log(end+1) = sprintf('%s  request from %s%s: %s', clk, ak.src, usr, res); dirty = true;
end
if numel(log) > 200, log = log(end-199:end); end
if ~refresh, return; end
if isempty(fig) || ~isvalid(fig)
    fig = findall(groot, 'Tag', 'mgLivePanel');
    if isempty(fig), return; end
    fig = fig(1);
end
h = fig.UserData;
mn = ["BOOT", "GRID", "ISLAND", "RESYNC"];
sb = 'idle'; if m.p_bess > 50, sb = 'DISCHARGING'; elseif m.p_bess < -50, sb = 'CHARGING'; end
h.top.Text = sprintf(['sim time  %s\nmode      %s\ngrid      %s, breaker %s\nfrequency %.3f Hz\n' ...
    'battery   %.1f %%  %s %.0f W\ngrid P    %.0f W (+ import)\nsolar     %.0f W   price Rs %.1f'], ...
    clk, mn(o.mode + 1), string(ifelse(m.v_grid > 0.5 * P.ac.V_nom, 'available', 'DEAD')), ...
    string(ifelse(o.breaker, 'closed', 'OPEN')), m.f_mg, 100 * m.soc, sb, m.p_bess, m.p_pcc, ...
    sum(m.p_pv) + m.p_cpv, o.price);
lines = strings(0, 1); on = ["off", "ON "];
for j = 1:P.n_load
    c = o.code(j); why = "";
    if bitand(c, 3) == 1, why = why + " TRIPPED"; elseif bitand(c, 3) == 2, why = why + " LOCKED OUT";
    elseif bitand(c, 3) == 3, why = why + " E-STOP (reset needed)"; end
    if bitand(c, 4), why = why + " shed:battery"; end
    if bitand(c, 8), why = why + " no credit"; end
    if bitand(c, 32), why = why + " shed:frequency"; end
    if bitand(c, 64), why = why + " shed:AI"; end
    if bitand(c, 128), why = why + " restricted"; end
    if bitand(c, 256), why = why + " off by user"; end
    if bitand(c, 1024), why = why + " NODE OFFLINE"; end
    bal = ""; if j <= P.n_house, bal = sprintf("  Rs %6.2f", o.bal(j)); end
    lines(end+1) = sprintf("%-3s critical %s flexible %s%s%s", P.load_id{j}, on(act.tie(j) + 1), on(act.flex(j) + 1), bal, why); %#ok<AGROW>
end
if bitand(o.flags, 32)
    lines(end+1) = "SB  BATTERY INVERTER STOPPED (E-stop or overload trip)";
end
if bitand(o.flags, 128) && o.offline(end)
    lines(end+1) = "SB  LINK DOWN: main controller uses last known battery data, node holds last set-point";
end
h.node.Text = strjoin(lines, newline);
live_inputs('set', 'now_h', hh / 3600);                 % for the panel's 'jump clock'
if dirty, h.log.Value = flip(log(:)); dirty = false; end   % newest first
live_sld('update', clk, o, m, act, P);                  % live single-line diagram (if open)
end

function s = ifelse(c, a, b)
if c, s = a; else, s = b; end
end
