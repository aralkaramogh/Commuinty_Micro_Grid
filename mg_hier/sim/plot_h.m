function plot_h(R, P, file)
% PLOT_H  Six-panel overview of one run, saved as PNG.
L = R.L; th = R.sc.t0_h + L.t / 3600;
fig = figure('Visible', 'off', 'Position', [0 0 1150 1300]);
tl = tiledlayout(fig, 6, 1, 'TileSpacing', 'compact');
title(tl, strrep(R.sc.name, '_', ' '));
ax = nexttile(tl);
plot(ax, th, L.p_pcc/1e3, th, L.p_bess/1e3, th, (sum(L.p_pv,2) + L.p_cpv)/1e3); hold(ax, 'on');
plot(ax, th, (sum(L.p_load,2) + L.p_cl)/1e3, 'k--'); hold(ax, 'off');   % dashed: often equal to the BESS or grid line
yline(ax, 0, 'k:'); grid(ax, 'on'); ylabel(ax, 'kW');
legend(ax, 'grid import (+)', 'BESS discharge (+)', 'all PV', 'all loads', 'Location', 'eastoutside');
title(ax, 'Active power P');
ax = nexttile(tl);
plot(ax, th, L.q_pcc/1e3, th, L.q_bess/1e3, th, (sum(L.q_load,2) + L.q_cl)/1e3, th, sum(L.q_pv,2)/1e3);
yline(ax, 0, 'k:'); grid(ax, 'on'); ylabel(ax, 'kvar');
legend(ax, 'grid Q (+ import)', 'BESS Q (+ inject)', 'loads Q', 'PV volt-var Q', 'Location', 'eastoutside');
title(ax, 'Reactive power Q');
ax = nexttile(tl);
v = [L.v_c, L.v_h]; v(~L.energised, :) = NaN;
plot(ax, th, v); yline(ax, [0.9 1.1] * P.ac.V_nom, 'r:'); grid(ax, 'on'); ylabel(ax, 'V rms');
legend(ax, [{'community bus'}, {P.house.id}], 'Location', 'eastoutside'); title(ax, 'Voltages');
ax = nexttile(tl);
f = L.f_mg; f(~L.energised) = NaN;
yyaxis(ax, 'left'); plot(ax, th, f); ylabel(ax, 'Hz'); ylim(ax, [49 51.6]);
yyaxis(ax, 'right'); stairs(ax, th, L.mode); ylim(ax, [-0.2 3.5]);
yticks(ax, 0:3); yticklabels(ax, {'BOOT', 'GRID', 'ISLAND', 'RESYNC'});
grid(ax, 'on'); legend(ax, 'microgrid frequency', 'main controller mode', 'Location', 'eastoutside');
title(ax, 'Frequency and operating mode');
ax = nexttile(tl);
nL = P.n_load; hold(ax, 'on');
for j = 1:nL
    stairs(ax, th, 2*(nL - j) + 0.9 * L.flex(:, j), 'LineWidth', 1.2);
end
hold(ax, 'off'); yticks(ax, 2*(0:nL-1)); yticklabels(ax, flip(strcat(P.load_id, ' flex')));
ylim(ax, [-0.3 2*nL]); grid(ax, 'on'); title(ax, 'Flexible-load relays at the nodes (high = ON)');
ax = nexttile(tl);
yyaxis(ax, 'left'); plot(ax, th, 100 * L.soc); ylabel(ax, 'SOC %'); ylim(ax, [0 100]);
yyaxis(ax, 'right'); plot(ax, th, L.bal); ylabel(ax, 'balance Rs');
grid(ax, 'on'); xlabel(ax, 'clock hour');
legend(ax, [{'BESS SOC'}, strcat({P.house.id}, ' prepaid')], 'Location', 'eastoutside');
title(ax, 'Battery and prepaid balances');
exportgraphics(fig, file, 'Resolution', 100); close(fig);
end
